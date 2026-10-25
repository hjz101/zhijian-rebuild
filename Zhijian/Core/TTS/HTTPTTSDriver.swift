// HTTPTTSDriver.swift — HTTP TTS 三种 URL 模式、Header/Cookie 注入、contentType 校验与 Caches 缓存
import Foundation
import AVFoundation
import JavaScriptCore
import CryptoKit

enum TTSDriverError: LocalizedError {
    case emptySourceURL
    case invalidURL(String)
    case unauthorized
    case httpStatus(Int)
    case badContentType(String)
    case emptyAudio
    case audioDecodeFailed(String)
    case jsError(String)
    case requestFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .emptySourceURL: return "HTTP TTS 源 URL 为空"
        case .invalidURL(let value): return "URL 非法：\(value)"
        case .unauthorized: return "HTTP TTS 需要登录（401/403）"
        case .httpStatus(let status): return "HTTP TTS 返回 HTTP \(status)"
        case .badContentType(let detail): return "HTTP TTS 内容类型校验失败：\(detail)"
        case .emptyAudio: return "HTTP TTS 返回空音频"
        case .audioDecodeFailed(let detail): return "音频解码失败：\(detail)"
        case .jsError(let detail): return "@js: 脚本执行失败：\(detail)"
        case .requestFailed(let detail): return "HTTP TTS 请求失败：\(detail)"
        case .cancelled: return "HTTP TTS 已取消"
        }
    }
}

/// HTTP TTS 播放器驱动。
///
/// 支持三种 URL：
/// 1. 模板：`https://host/tts?text={{speakText}}&speed={{speakSpeed}}`
/// 2. Legado 选项：`https://host/tts,{"method":"POST","body":"{\"text\":\"{{speakText}}\"}"}`
/// 3. JavaScriptCore：`@js:...`（独立 JSContext，返回 URL / 请求对象 / base64 音频）
///
/// 音频统一落到 `Caches/ZhijianTTS`，同一 `(source, text, speed)` 二次播放不再请求。
final class HTTPTTSDriver: @unchecked Sendable {

    static let shared = HTTPTTSDriver()

    private let cacheDirectory: URL
    private let session: URLSession
    private let throttle = TTSRequestThrottle()

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = caches.appendingPathComponent("ZhijianTTS", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: configuration)
    }

    // MARK: 对外接口

    /// 取得一段文本的音频文件 URL（命中缓存时同步返回）。
    func audioFile(
        for text: String,
        source: HttpTTS,
        rate: Double,
        loginHeader: String = "",
        sourceVariable: String = ""
    ) async throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TTSDriverError.emptyAudio }
        let speed = Self.speechSpeed(rate)
        let key = Self.cacheKey(source: source, text: trimmed, speed: speed)

        if let cached = cachedFile(for: key) { return cached }

        let headers = Self.mergedHeaders(source: source, loginHeader: loginHeader)
        try await throttle.wait(sourceID: source.id, concurrentRate: source.concurrentRate)

        let prepared = try prepare(
            text: trimmed,
            source: source,
            speed: speed,
            headers: headers,
            sourceVariable: sourceVariable
        )

        let data: Data
        let mime: String?
        if let inline = prepared.inlineData {
            data = inline
            mime = Self.sniffMime(inline)
        } else {
            guard let url = prepared.url else { throw TTSDriverError.emptySourceURL }
            let fetched = try await fetch(prepared, url: url, source: source)
            data = fetched.data
            mime = fetched.mime
        }

        guard !data.isEmpty else { throw TTSDriverError.emptyAudio }
        let ext = Self.fileExtension(mime: mime, data: data, url: prepared.url)
        let target = cacheDirectory.appendingPathComponent("\(key).\(ext)")
        try data.write(to: target, options: .atomic)

        do {
            let player = try AVAudioPlayer(contentsOf: target)
            guard player.duration > 0 else { throw TTSDriverError.audioDecodeFailed("音频时长为 0") }
        } catch let error as TTSDriverError {
            try? FileManager.default.removeItem(at: target)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw TTSDriverError.audioDecodeFailed(error.localizedDescription)
        }
        return target
    }

    /// 仅预览：不复用播放控制器，返回音频文件供配置页 AVAudioPlayer 播放。
    @MainActor
    func previewFile(text: String, source: HttpTTS, rate: Double = 0.5) async throws -> URL {
        try await audioFile(
            for: text,
            source: source,
            rate: rate,
            loginHeader: TTSRuntimeStore.shared.loginHeader(for: source.id),
            sourceVariable: TTSRuntimeStore.shared.sourceVariable(for: source.id)
        )
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func cacheStats() -> (count: Int, bytes: Int64) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var bytes: Int64 = 0
        for file in files {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            bytes += Int64(size)
        }
        return (files.count, bytes)
    }

    // MARK: 请求构造

    private struct PreparedRequest {
        var url: URL?
        var method: String = "GET"
        var headers: [String: String] = [:]
        var body: Data?
        var inlineData: Data?
    }

    private func prepare(
        text: String,
        source: HttpTTS,
        speed: Int,
        headers: [String: String],
        sourceVariable: String
    ) throws -> PreparedRequest {
        let raw = source.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw TTSDriverError.emptySourceURL }

        if raw.lowercased().hasPrefix("@js:") {
            let script = String(raw.dropFirst(4))
            return try evaluateJS(
                script: script,
                source: source,
                text: text,
                speed: speed,
                headers: headers,
                sourceVariable: sourceVariable
            )
        }

        let split = Self.splitOptions(raw)
        let urlTemplate = split.url
        let options = split.options
        var requestHeaders = headers
        if let optionHeaders = options?["headers"] as? [String: Any] {
            for (key, value) in optionHeaders {
                requestHeaders[key] = Self.stringValue(value)
            }
        }
        requestHeaders = requestHeaders.mapValues { value in
            Self.replacePlaceholders(value, text: text, speed: speed, urlEncoded: false)
        }

        var bodyText = options?["body"] as? String
        let hasBodyTemplate = bodyText?.contains("{{") ?? false
        let hasURLTemplate = urlTemplate.contains("{{")
        let method = ((options?["method"] as? String) ?? (bodyText == nil ? "GET" : "POST")).uppercased()

        var urlText = Self.replacePlaceholders(urlTemplate, text: text, speed: speed, urlEncoded: true)
        if !hasURLTemplate && !hasBodyTemplate && method == "GET" {
            urlText = Self.appendQuery(to: urlText, text: text, speed: speed)
        }

        var body: Data?
        if let bodyText {
            let isJSON = {
                let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
            }()
            let replaced = Self.replacePlaceholders(bodyText, text: text, speed: speed, urlEncoded: !isJSON)
            body = replaced.data(using: .utf8)
            if !requestHeaders.keys.contains(where: { $0.lowercased() == "content-type" }) {
                requestHeaders["Content-Type"] = isJSON
                    ? "application/json; charset=utf-8"
                    : "application/x-www-form-urlencoded; charset=utf-8"
            }
        }

        guard let url = URL(string: urlText) else { throw TTSDriverError.invalidURL(urlText) }
        var finalHeaders = requestHeaders
        if !finalHeaders.keys.contains(where: { $0.lowercased() == "user-agent" }) {
            finalHeaders["User-Agent"] = HTTPClient.defaultUserAgent
        }
        if !finalHeaders.keys.contains(where: { $0.lowercased() == "accept" }) {
            finalHeaders["Accept"] = "audio/*,*/*;q=0.8"
        }

        return PreparedRequest(url: url, method: method, headers: finalHeaders, body: body)
    }

    private func fetch(_ prepared: PreparedRequest, url: URL, source: HttpTTS) async throws -> (data: Data, mime: String?) {
        var request = URLRequest(url: url)
        request.httpMethod = prepared.method
        request.timeoutInterval = 30
        request.httpBody = prepared.body
        request.httpShouldHandleCookies = source.enabledCookieJar ?? false
        for (key, value) in prepared.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if (source.enabledCookieJar ?? false),
           !prepared.headers.keys.contains(where: { $0.lowercased() == "cookie" }) {
            let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
            if !cookies.isEmpty {
                request.setValue(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "),
                                 forHTTPHeaderField: "Cookie")
            }
        }

        var attempt = 0
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw TTSDriverError.requestFailed("没有收到 HTTP 响应")
                }
                let mime = Self.mimeType(http.value(forHTTPHeaderField: "Content-Type"))
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw TTSDriverError.unauthorized
                }
                if (500..<600).contains(http.statusCode) {
                    if attempt < 1 {
                        attempt += 1
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        continue
                    }
                    throw TTSDriverError.httpStatus(http.statusCode)
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw TTSDriverError.httpStatus(http.statusCode)
                }
                try Self.validateContentType(mime: mime, source: source, data: data)
                return (data, mime.isEmpty ? nil : mime)
            } catch let error as TTSDriverError {
                throw error
            } catch let error as URLError {
                let retryable: Bool = {
                    switch error.code {
                    case .timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet:
                        return true
                    default:
                        return false
                    }
                }()
                if retryable && attempt < 1 {
                    attempt += 1
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    continue
                }
                throw TTSDriverError.requestFailed(error.localizedDescription)
            } catch {
                throw TTSDriverError.requestFailed(error.localizedDescription)
            }
        }
    }

    // MARK: URL 选项 / 模板

    private static func splitOptions(_ raw: String) -> (url: String, options: [String: Any]?) {
        guard let range = raw.range(of: ",{", options: .backwards) else { return (raw, nil) }
        let urlPart = String(raw[..<range.lowerBound])
        let jsonPart = String(raw[range.lowerBound...].dropFirst())
        guard let data = jsonPart.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (raw, nil)
        }
        return (urlPart, object)
    }

    private static func replacePlaceholders(_ template: String, text: String, speed: Int, urlEncoded: Bool) -> String {
        let encodedText = urlEncoded ? urlEncode(text) : jsonEscape(text)
        var output = template.replacingOccurrences(of: "{{speakText}}", with: encodedText)
        output = output.replacingOccurrences(of: "{{speakSpeed}}", with: String(speed))
        output = output.replacingOccurrences(of: "{{speakSpeedInt}}", with: String(speed))
        return output
    }

    private static func appendQuery(to url: String, text: String, speed: Int) -> String {
        var components = URLComponents(string: url)
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "text", value: text))
        items.append(URLQueryItem(name: "speed", value: String(speed)))
        components?.queryItems = items
        if let rebuilt = components?.url?.absoluteString { return rebuilt }
        let separator = url.contains("?") ? "&" : "?"
        return url + separator + "text=\(urlEncode(text))&speed=\(speed)"
    }

    static func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func jsonEscape(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              var text = String(data: data, encoding: .utf8) else { return value }
        if text.hasPrefix("\"") { text.removeFirst() }
        if text.hasSuffix("\"") { text.removeLast() }
        return text
    }

    // MARK: Header / Cookie

    static func mergedHeaders(source: HttpTTS, loginHeader: String) -> [String: String] {
        var headers = parseHeaderBlock(source.header)
        for (key, value) in parseHeaderBlock(loginHeader) {
            headers[key] = value
        }
        return headers
    }

    /// 支持 JSON 对象与 `Key: Value` / `Key=Value` 多行格式。
    static func parseHeaderBlock(_ text: String?) -> [String: String] {
        guard let text else { return [:] }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }

        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var result: [String: String] = [:]
            for (key, value) in object {
                let name = key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                result[name] = stringValue(value)
            }
            return result
        }

        var result: [String: String] = [:]
        for line in trimmed.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if let range = line.range(of: ":") {
                let name = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { result[name] = value }
            } else if let range = line.range(of: "=") {
                let name = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { result[name] = value }
            }
        }
        return result
    }

    // MARK: contentType

    private static func mimeType(_ header: String?) -> String {
        guard let header else { return "" }
        return header.split(separator: ";").first.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        } ?? ""
    }

    private static func validateContentType(mime: String, source: HttpTTS, data: Data) throws {
        let declared = source.contentType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !declared.isEmpty {
            let patterns = declared
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let matched = patterns.contains { pattern in
                if pattern.hasSuffix("/*") {
                    return mime.hasPrefix(String(pattern.dropLast(2)).lowercased())
                }
                let lower = pattern.lowercased()
                if mime.contains(lower) { return true }
                if mime == "application/octet-stream" { return true }
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    let range = NSRange(location: 0, length: (mime as NSString).length)
                    return regex.firstMatch(in: mime, range: range) != nil
                }
                return false
            }
            guard matched else {
                throw TTSDriverError.badContentType("期望 \(declared)，实际 \(mime.isEmpty ? "无 Content-Type" : mime)")
            }
            return
        }

        // 未声明 contentType：拒绝网页/JSON 等明显错误响应
        if mime.contains("text/html") || mime.contains("application/json") || mime.contains("text/plain") {
            throw TTSDriverError.badContentType("未声明 contentType 且返回 \(mime)")
        }
        if let prefix = String(data: data.prefix(64), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) {
            if prefix.hasPrefix("<") || prefix.hasPrefix("{") || prefix.hasPrefix("[") {
                throw TTSDriverError.badContentType("响应看起来是网页/JSON，不是音频")
            }
        }
    }

    private static func sniffMime(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.count >= 3, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 { return "audio/mpeg" }
        if bytes.count >= 4, bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46 { return "audio/wav" }
        if bytes.count >= 8, bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 { return "audio/mp4" }
        if bytes.count >= 2, bytes[0] == 0xFF, (bytes[1] & 0xF0) == 0xF0 { return "audio/mpeg" }
        if bytes.count >= 4, bytes[0] == 0x4F, bytes[1] == 0x67, bytes[2] == 0x67, bytes[3] == 0x53 { return "audio/ogg" }
        return nil
    }

    private static func fileExtension(mime: String?, data: Data, url: URL?) -> String {
        let resolved = mime?.lowercased() ?? ""
        if resolved.contains("mpeg") || resolved.contains("mp3") { return "mp3" }
        if resolved.contains("wav") { return "wav" }
        if resolved.contains("mp4") || resolved.contains("m4a") { return "m4a" }
        if resolved.contains("aac") { return "aac" }
        if resolved.contains("ogg") { return "ogg" }
        if resolved.contains("flac") { return "flac" }
        if let ext = url?.pathExtension.lowercased(),
           ["mp3", "wav", "m4a", "aac", "ogg", "flac"].contains(ext) {
            return ext
        }
        if let sniffed = sniffMime(data) {
            return fileExtension(mime: sniffed, data: Data(), url: nil)
        }
        return "audio"
    }

    // MARK: 缓存

    static func speechSpeed(_ rate: Double) -> Int {
        min(30, max(1, Int((rate * 10).rounded())))
    }

    private static func cacheKey(source: HttpTTS, text: String, speed: Int) -> String {
        let raw = "\(source.id)|\(source.url)|\(text)|\(speed)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func cachedFile(for key: String) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        guard let file = files.first(where: { $0.lastPathComponent.hasPrefix(key + ".") }) else { return nil }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0 ? file : nil
    }

    // MARK: @js:

    private func evaluateJS(
        script: String,
        source: HttpTTS,
        text: String,
        speed: Int,
        headers: [String: String],
        sourceVariable: String
    ) throws -> PreparedRequest {
        guard let context = JSContext() else {
            throw TTSDriverError.jsError("无法创建 JSContext")
        }
        context.exception = nil

        // 全局变量：speakText / speakSpeed / source / java / console
        context.setObject(text, forKeyedSubscript: "speakText" as NSString)
        context.setObject(NSNumber(value: speed), forKeyedSubscript: "speakSpeed" as NSString)
        context.setObject(sourceVariable, forKeyedSubscript: "sourceVariable" as NSString)

        let sourceObject = JSValue(newObjectIn: context)!
        sourceObject.setObject(source.name, forKeyedSubscript: "name" as NSString)
        sourceObject.setObject(source.url, forKeyedSubscript: "url" as NSString)
        sourceObject.setObject(source.header ?? "", forKeyedSubscript: "header" as NSString)
        var currentVariable = sourceVariable
        let getVariable: @convention(block) () -> JSValue = { JSValue(object: currentVariable, in: context) }
        let setVariable: @convention(block) (JSValue) -> Void = { value in
            currentVariable = value.toString() ?? ""
        }
        sourceObject.setObject(getVariable, forKeyedSubscript: "getVariable" as NSString)
        sourceObject.setObject(setVariable, forKeyedSubscript: "setVariable" as NSString)
        sourceObject.setObject(source.id, forKeyedSubscript: "id" as NSString)
        context.setObject(sourceObject, forKeyedSubscript: "source" as NSString)

        let http = HTTPClient(headers: headers)
        let java = JSValue(newObjectIn: context)!
        Self.installJavaAPI(java, context: context, http: http)
        context.setObject(java, forKeyedSubscript: "java" as NSString)

        let console = JSValue(newObjectIn: context)!
        let consoleLog: @convention(block) (JSValue) -> Void = { _ in }
        console.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)

        let result = context.evaluateScript(script)
        if let exception = context.exception {
            let message = exception.toString() ?? "未知 JS 异常"
            context.exception = nil
            throw TTSDriverError.jsError(message)
        }
        guard let result else { throw TTSDriverError.jsError("脚本没有返回值") }

        if result.isString, let value = result.toString() {
            return try preparedFromJSString(value, source: source, text: text, speed: speed, headers: headers)
        }
        if result.isObject, let object = result.toObject() as? [String: Any] {
            return try preparedFromJSDictionary(object, source: source, text: text, speed: speed, headers: headers)
        }
        throw TTSDriverError.jsError("脚本返回值不是 URL / 请求对象 / base64 音频")
    }

    private func preparedFromJSString(
        _ value: String,
        source: HttpTTS,
        text: String,
        speed: Int,
        headers: [String: String]
    ) throws -> PreparedRequest {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TTSDriverError.jsError("脚本返回空字符串") }

        if let data = Self.inlineAudioData(trimmed) {
            return PreparedRequest(inlineData: data)
        }
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return try preparedFromJSDictionary(object, source: source, text: text, speed: speed, headers: headers)
        }
        var urlText = trimmed
        if urlText.contains("{{speakText}}") || urlText.contains("{{speakSpeed}}") {
            urlText = Self.replacePlaceholders(urlText, text: text, speed: speed, urlEncoded: true)
        }
        guard let url = URL(string: urlText) else { throw TTSDriverError.invalidURL(urlText) }
        var finalHeaders = headers
        if !finalHeaders.keys.contains(where: { $0.lowercased() == "user-agent" }) {
            finalHeaders["User-Agent"] = HTTPClient.defaultUserAgent
        }
        return PreparedRequest(url: url, method: "GET", headers: finalHeaders)
    }

    private func preparedFromJSDictionary(
        _ dictionary: [String: Any],
        source: HttpTTS,
        text: String,
        speed: Int,
        headers: [String: String]
    ) throws -> PreparedRequest {
        if let audio = dictionary["audio"] as? String ?? dictionary["base64"] as? String,
           let data = Self.inlineAudioData(audio) {
            return PreparedRequest(inlineData: data)
        }
        let rawURL = Self.stringValue(dictionary["url"])
        guard !rawURL.isEmpty else {
            throw TTSDriverError.jsError("请求对象缺少 url")
        }
        let method = (Self.stringValue(dictionary["method"]).isEmpty ? "GET" : Self.stringValue(dictionary["method"])).uppercased()
        var finalHeaders = headers
        if let object = dictionary["headers"] as? [String: Any] {
            for (key, value) in object { finalHeaders[key] = Self.stringValue(value) }
        }
        var bodyText = dictionary["body"].map { Self.stringValue($0) }
        if var replaced = bodyText, !replaced.isEmpty {
            replaced = Self.replacePlaceholders(replaced, text: text, speed: speed, urlEncoded: false)
            bodyText = replaced
        }
        guard let url = URL(string: rawURL) else { throw TTSDriverError.invalidURL(rawURL) }
        if !finalHeaders.keys.contains(where: { $0.lowercased() == "user-agent" }) {
            finalHeaders["User-Agent"] = HTTPClient.defaultUserAgent
        }
        if bodyText != nil, !finalHeaders.keys.contains(where: { $0.lowercased() == "content-type" }) {
            finalHeaders["Content-Type"] = "application/json; charset=utf-8"
        }
        return PreparedRequest(
            url: url,
            method: method,
            headers: finalHeaders,
            body: bodyText?.data(using: .utf8)
        )
    }

    private static func inlineAudioData(_ value: String) -> Data? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("data:") {
            guard let comma = trimmed.firstIndex(of: ",") else { return nil }
            let meta = String(trimmed[..<comma]).lowercased()
            guard meta.contains("audio") || meta.contains("base64") else { return nil }
            let base64 = String(trimmed[trimmed.index(after: comma)...])
            return Data(base64Encoded: base64, options: [.ignoreUnknownCharacters])
        }
        guard trimmed.count > 256,
              let data = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]),
              !data.isEmpty,
              sniffMime(data) != nil else {
            return nil
        }
        return data
    }

    // MARK: JS API

    private static func installJavaAPI(_ java: JSValue, context: JSContext, http: HTTPClient) {
        let ajax: @convention(block) (JSValue) -> JSValue = { value in
            let url = value.toString() ?? ""
            guard !url.isEmpty else { return JSValue(nullIn: context) }
            do {
                let response = try http.requestSync(url, timeout: 15)
                return JSValue(object: response.body, in: context)
            } catch {
                return JSValue(nullIn: context)
            }
        }
        java.setObject(ajax, forKeyedSubscript: "ajax" as NSString)

        let get: @convention(block) (JSValue, JSValue) -> JSValue = { urlValue, headerValue in
            let url = urlValue.toString() ?? ""
            let headers = dictionary(from: headerValue)
            do {
                let response = try http.requestSync(url, headers: headers, timeout: 15)
                return makeResponse(context, response)
            } catch {
                return JSValue(nullIn: context)
            }
        }
        java.setObject(get, forKeyedSubscript: "get" as NSString)

        let post: @convention(block) (JSValue, JSValue, JSValue) -> JSValue = { urlValue, bodyValue, headerValue in
            let url = urlValue.toString() ?? ""
            let body = bodyValue.toString() ?? ""
            let headers = dictionary(from: headerValue)
            do {
                let response = try http.requestSync(url, method: "POST", headers: headers, body: body, timeout: 15)
                return makeResponse(context, response)
            } catch {
                return JSValue(nullIn: context)
            }
        }
        java.setObject(post, forKeyedSubscript: "post" as NSString)

        let base64Encode: @convention(block) (JSValue) -> JSValue = { value in
            let text = value.toString() ?? ""
            return JSValue(object: Data(text.utf8).base64EncodedString(), in: context)
        }
        java.setObject(base64Encode, forKeyedSubscript: "base64Encode" as NSString)

        let base64Decode: @convention(block) (JSValue) -> JSValue = { value in
            let text = value.toString() ?? ""
            let data = Data(base64Encoded: text, options: [.ignoreUnknownCharacters]) ?? Data()
            return JSValue(object: String(data: data, encoding: .utf8) ?? "", in: context)
        }
        java.setObject(base64Decode, forKeyedSubscript: "base64Decode" as NSString)

        let md5: @convention(block) (JSValue) -> JSValue = { value in
            let text = value.toString() ?? ""
            let digest = Insecure.MD5.hash(data: Data(text.utf8))
            return JSValue(object: digest.map { String(format: "%02x", $0) }.joined(), in: context)
        }
        java.setObject(md5, forKeyedSubscript: "md5Encode" as NSString)
        java.setObject(md5, forKeyedSubscript: "md5" as NSString)

        let userAgent: @convention(block) () -> JSValue = {
            JSValue(object: HTTPClient.defaultUserAgent, in: context)
        }
        java.setObject(userAgent, forKeyedSubscript: "getWebViewUA" as NSString)

        let log: @convention(block) (JSValue) -> Void = { _ in }
        java.setObject(log, forKeyedSubscript: "log" as NSString)
        java.setObject(log, forKeyedSubscript: "toast" as NSString)
    }

    private static func dictionary(from value: JSValue) -> [String: String] {
        guard value.isObject, let object = value.toObject() as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, element) in object { result[key] = stringValue(element) }
        return result
    }

    private static func makeResponse(_ context: JSContext, _ response: EngineHTTPResponse) -> JSValue {
        let object = JSValue(newObjectIn: context)!
        let body: @convention(block) () -> JSValue = { JSValue(object: response.body, in: context) }
        let text: @convention(block) () -> JSValue = { JSValue(object: response.body, in: context) }
        let status: @convention(block) () -> JSValue = { JSValue(int32: Int32(response.status), in: context) }
        let header: @convention(block) (JSValue) -> JSValue = { name in
            JSValue(object: response.headers[name.toString() ?? ""] ?? "", in: context)
        }
        let headers: @convention(block) () -> JSValue = { JSValue(object: response.headers, in: context) }
        object.setObject(body, forKeyedSubscript: "body" as NSString)
        object.setObject(text, forKeyedSubscript: "string" as NSString)
        object.setObject(status, forKeyedSubscript: "code" as NSString)
        object.setObject(status, forKeyedSubscript: "statusCode" as NSString)
        object.setObject(header, forKeyedSubscript: "header" as NSString)
        object.setObject(headers, forKeyedSubscript: "headers" as NSString)
        return object
    }

    private static func stringValue(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if let dictionary = value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dictionary),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let array = value as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: array),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }
}

// MARK: - 请求限速

/// 按 `concurrentRate` 串行限速：
/// - `"1500"` → 每 1.5s 一次
/// - `"1/1000"` → 每 1s 一次
/// - 空 → 0.25s（保证连续分句不把服务端打爆）
actor TTSRequestThrottle {
    private var lastRequestAt: [String: Date] = [:]

    func wait(sourceID: String, concurrentRate: String?) async throws {
        let interval = Self.interval(from: concurrentRate)
        guard interval > 0 else { return }
        if let last = lastRequestAt[sourceID] {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < interval {
                try? await Task.sleep(nanoseconds: UInt64((interval - elapsed) * 1_000_000_000))
            }
        }
        lastRequestAt[sourceID] = Date()
    }

    static func interval(from raw: String?) -> TimeInterval {
        guard let raw else { return 0.25 }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return 0.25 }
        if text.contains("/") {
            let parts = text.split(separator: "/").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { return 0.25 }
            let count = max(1, Double(parts[0]) ?? 1)
            let milliseconds = max(0, Double(parts[1]) ?? 1000)
            return milliseconds / 1000 / count
        }
        if let milliseconds = Double(text) {
            return max(0, milliseconds / 1000)
        }
        return 0.25
    }
}
