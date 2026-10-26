// SourcePipeline.swift —— 网络层（UA/Cookie/1 req/s 限速/超时/错误码 -1…-14）与四阶段流水线 search → bookInfo → toc → content
import Foundation

// MARK: - 错误码

/// 引擎错误，`code` 与实测报告 §6.3 的 -1…-14 对齐。
enum SourceEngineError: Error, LocalizedError, CustomStringConvertible {
    case timeout
    case socket(String)
    case dns(String)
    case connectionRefused(String)
    case tls(String)
    case http4xx(Int)
    case http5xx(Int)
    case ruleSyntax(String)
    case jsError(String)
    case missingAPI(String)
    case ruleNoResult(String)
    case needLogin
    case emptyContent(String)
    case privateProtocol(String)
    case invalidSource(String)
    case unknown(String)

    var code: Int {
        switch self {
        case .timeout: return -1
        case .socket: return -2
        case .dns: return -3
        case .connectionRefused: return -4
        case .tls: return -5
        case .http4xx: return -6
        case .http5xx: return -7
        case .ruleSyntax: return -8
        case .jsError: return -9
        case .missingAPI: return -10
        case .ruleNoResult: return -11
        case .needLogin: return -12
        case .emptyContent: return -13
        case .privateProtocol: return -14
        case .invalidSource: return -11
        case .unknown: return -99
        }
    }

    var message: String {
        switch self {
        case .timeout:
            return "请求超时"
        case .socket(let detail):
            return "连接/Socket 错误：\(detail)"
        case .dns(let detail):
            return "DNS 解析失败：\(detail)"
        case .connectionRefused(let detail):
            return "连接被拒绝：\(detail)"
        case .tls(let detail):
            return "TLS/证书错误：\(detail)"
        case .http4xx(let status):
            return "HTTP \(status)（书源失效或需要登录）"
        case .http5xx(let status):
            return "HTTP \(status)（站点错误）"
        case .ruleSyntax(let detail):
            return "规则错误：\(detail)"
        case .jsError(let detail):
            return "JS 规则执行失败：\(detail)"
        case .missingAPI(let detail):
            return "缺失 JS API：\(detail)"
        case .ruleNoResult(let detail):
            return "规则无结果：\(detail)"
        case .needLogin:
            return "需要登录 / 付费墙"
        case .emptyContent(let detail):
            return "内容为空：\(detail)"
        case .privateProtocol(let detail):
            return "使用了私有协议：\(detail)"
        case .invalidSource(let detail):
            return "书源配置无效：\(detail)"
        case .unknown(let detail):
            return "未知错误：\(detail)"
        }
    }

    var errorDescription: String? { "[\(code)] \(message)" }
    var description: String { "[\(code)] \(message)" }

    /// HTTP 状态码 → 错误码
    static func from(response: EngineHTTPResponse) -> SourceEngineError {
        if response.status == 429 { return .http4xx(429) }
        if response.status >= 500 { return .http5xx(response.status) }
        if response.status >= 400 { return .http4xx(response.status) }
        return .unknown("HTTP \(response.status)")
    }
}

// MARK: - 响应

struct EngineHTTPResponse {
    var status: Int
    var body: String
    var headers: [String: String]
    var finalURL: String
    var isInline: Bool = false
    var elapsedMilliseconds: Int = 0

    var isOK: Bool { (200..<300).contains(status) }
}

// MARK: - CookieJar

/// 按域名保存的 Cookie（进程内有效，不落盘）。
final class CookieJar: @unchecked Sendable {

    private let lock = NSLock()
    private var storage: [String: [String: String]] = [:]

    init(initial: [String: [String: String]] = [:]) {
        storage = initial
    }

    /// 导出全部 Cookie（用于持久化到 App 侧 CookieStore）
    func export() -> [String: [String: String]] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// 合并外部导入的 Cookie（例如 WKWebView 登录后拿到的）
    func merge(_ cookies: [String: [String: String]]) {
        lock.lock()
        defer { lock.unlock() }
        for (domain, values) in cookies {
            var existing = storage[domain] ?? [:]
            for (name, value) in values { existing[name] = value }
            storage[domain] = existing
        }
    }

    /// 拼出该 URL 可用的 Cookie 请求头
    func header(for url: String) -> String {
        let host = Self.host(of: url)
        guard !host.isEmpty else { return "" }
        lock.lock()
        defer { lock.unlock() }
        let hostETLD1 = PublicSuffixList.eTLDPlusOne(host: host)
        var parts: [String] = []
        for (domain, cookies) in storage {
            let domainETLD1 = PublicSuffixList.eTLDPlusOne(host: domain)
            // 同一 eTLD+1 内共享 Cookie（a.example.com 与 b.example.com）
            guard hostETLD1 == domainETLD1 else { continue }
            for (name, value) in cookies.sorted(by: { $0.key < $1.key }) {
                parts.append("\(name)=\(value)")
            }
        }
        return parts.joined(separator: "; ")
    }

    /// `cookie.setCookie(url, "k=v; Path=/; Max-Age=0")`
    func set(url: String, cookie: String) {
        let host = Self.host(of: url)
        guard !host.isEmpty else { return }
        let segments = cookie.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let first = segments.first, let equals = first.firstIndex(of: "=") else { return }
        let name = String(first[..<equals]).trimmingCharacters(in: .whitespaces)
        let value = String(first[first.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let lowered = cookie.lowercased()
        let expired = lowered.contains("max-age=0")
            || lowered.range(of: "max-age=-", options: .regularExpression) != nil
            || lowered.contains("expires=thu, 01 jan 1970")

        lock.lock()
        defer { lock.unlock() }
        var cookies = storage[host] ?? [:]
        if expired {
            cookies.removeValue(forKey: name)
        } else {
            cookies[name] = value
        }
        storage[host] = cookies
    }

    func remove(url: String) {
        let host = Self.host(of: url)
        guard !host.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        for domain in storage.keys where host == domain || host.hasSuffix("." + domain) || domain.hasSuffix("." + host) {
            storage.removeValue(forKey: domain)
        }
    }

    func value(for url: String, key: String) -> String {
        let host = Self.host(of: url)
        lock.lock()
        defer { lock.unlock() }
        for (domain, cookies) in storage where host == domain || host.hasSuffix("." + domain) {
            if let value = cookies[key] { return value }
        }
        return ""
    }

    static func host(of url: String) -> String {
        guard let components = URLComponents(string: url), let host = components.host else { return "" }
        return host.lowercased()
    }
}

// MARK: - 限速

/// 单源限速：解析 Legado `concurrentRate` 语义（`次数/毫秒` 或单独毫秒间隔）。
///
/// Legado `ConcurrentRateLimiter` 的规则：
/// - 空 / 非法 → 不额外限制；本工程保留原默认 1 req/s 作为安全兜底
///   （`source.concurrentRate` 未填写时不做突刺抓取）；
/// - `"0"` → 不限制；
/// - `"1000"` → 1 次 / 1000ms；
/// - `"3/1000"` → 3 次 / 1000ms（窗口内最多 3 次，超限等窗口结束）。
final class RateLimiter: @unchecked Sendable {

    struct Configuration: Equatable, Sendable {
        var accessLimit: Int
        var intervalMilliseconds: Int

        var isUnlimited: Bool { accessLimit <= 0 || intervalMilliseconds <= 0 }

        /// 稳定平均间隔（诊断展示用）
        var averageInterval: TimeInterval {
            guard accessLimit > 0 else { return 0 }
            return Double(intervalMilliseconds) / 1000 / Double(accessLimit)
        }

        static let `default` = Configuration(accessLimit: 1, intervalMilliseconds: 1000)
        static let unlimited = Configuration(accessLimit: 0, intervalMilliseconds: 0)

        static func parse(_ raw: String?) -> Configuration {
            guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return .default
            }
            if text == "0" { return .unlimited }
            if let slash = text.firstIndex(of: "/") {
                let left = Int(text[..<slash].trimmingCharacters(in: .whitespaces)) ?? 0
                let right = Int(text[text.index(after: slash)...].trimmingCharacters(in: .whitespaces)) ?? 0
                if left > 0, right > 0 {
                    return Configuration(accessLimit: left, intervalMilliseconds: right)
                }
                return .default
            }
            if let milliseconds = Int(text), milliseconds > 0 {
                return Configuration(accessLimit: 1, intervalMilliseconds: milliseconds)
            }
            return .default
        }
    }

    let configuration: Configuration
    private let lock = NSLock()
    private var windowStart: Date = .distantPast
    private var frequency: Int = 0

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    convenience init(interval: TimeInterval = 1.0) {
        self.init(configuration: Configuration(
            accessLimit: 1,
            intervalMilliseconds: max(0, Int(interval * 1000))
        ))
    }

    func waitSync() {
        guard !configuration.isUnlimited else { return }
        let interval = Double(configuration.intervalMilliseconds) / 1000
        while true {
            var delay: TimeInterval = 0
            lock.lock()
            let now = Date()
            if now.timeIntervalSince(windowStart) >= interval {
                windowStart = now
                frequency = 1
            } else if frequency < configuration.accessLimit {
                frequency += 1
            } else {
                delay = interval - now.timeIntervalSince(windowStart)
            }
            lock.unlock()
            if delay <= 0 { return }
            Thread.sleep(forTimeInterval: delay)
        }
    }
}

// MARK: - HTTP 客户端

/// 书源网络客户端：UA 注入、Cookie 合并、`URL,{json}` 选项、1 req/s 限速、5xx/超时重试 1 次。
final class HTTPClient: @unchecked Sendable {

    static let defaultUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    /// P2-08：书源 HTTPS 优先开关（默认开启）
    static var httpsFirstEnabled = true
    /// 书源 JS 执行器模式（SettingsStore.jsExecutorMode 同步）
    static var currentExecutorMode: Int = 0

    static func httpsUpgrade(_ url: String) -> String? {
        guard url.hasPrefix("http://") else { return nil }
        return "https://" + String(url.dropFirst("http://".count))
    }

    /// P3-07：全局代理（HTTP / SOCKS），应用到所有书源请求；不影响系统其他 App。
    static var proxyConfiguration: [String: Any]? = nil

    static func applyProxy(_ proxy: (host: String, port: Int, socks: Bool)?) {
        guard let proxy else {
            proxyConfiguration = nil
            return
        }
        if proxy.socks {
            // SOCKS5：使用 CFNetwork 字典键（iOS 上这些常量不可用，用字符串字面量）
            proxyConfiguration = [
                "SOCKSEnable": 1,
                "SOCKSProxy": proxy.host,
                "SOCKSPort": proxy.port
            ]
        } else {
            proxyConfiguration = [
                "HTTPEnable": 1,
                "HTTPProxy": proxy.host,
                "HTTPPort": proxy.port,
                "HTTPSEnable": 1,
                "HTTPSProxy": proxy.host,
                "HTTPSPort": proxy.port
            ]
        }
    }

    let jar: CookieJar
    let limiter: RateLimiter
    var defaultTimeout: TimeInterval = 15
    /// 每次请求后回调最新 Cookie，供 App 侧持久化/共享给 WKWebView
    var onCookiesChanged: (([String: [String: String]]) -> Void)?
    /// 登录失效检测关键词（HTTPClient 侧）
    static let loginFailureMarkers = ["访问被拒绝", "未登录", "请先登录", "登录已过期", "登录失效", "unauthorized",
                                      "login first", "需要登录", "请登录", "认证失败", "鉴权失败", "forbidden",
                                      "invalid token", "token 失效", "token已失效", "session expired", "请重新登录"]

    private let session: URLSession
    private var sourceHeaders: [String: String]
    private let logLock = NSLock()
    private var records: [String] = []
    /// 短时响应缓存（GET 200，20s）：同源同 URL 重复请求（如搜索后立刻详情）直接命中
    private var responseCache: [String: (date: Date, response: EngineHTTPResponse)] = [:]
    private let cacheLock = NSLock()

    init(jar: CookieJar = CookieJar(), limiter: RateLimiter = RateLimiter(interval: 1.0), headers: [String: String] = [:]) {
        self.jar = jar
        self.limiter = limiter
        self.sourceHeaders = headers
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let proxy = HTTPClient.proxyConfiguration {
            configuration.connectionProxyDictionary = proxy
        }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: queue)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    /// 动态 header 规则（书源 `header` 为 `@js:`/`<js>` 时由 pipeline 求值后回填）
    func setSourceHeaders(_ headers: [String: String]) {
        sourceHeaders = headers
    }

    /// 请求流水（调试入口展示用）
    var log: [String] {
        logLock.lock()
        defer { logLock.unlock() }
        return records
    }

    // MARK: 异步请求

    func request(
        _ target: RuleURL,
        method: String? = nil,
        headers: [String: String] = [:],
        body: String? = nil,
        timeout: TimeInterval? = nil,
        retry: Int? = nil
    ) async throws -> EngineHTTPResponse {
        // 选项优先保留规则里写的，再与调用方参数合并
        // 目标字符串里可能仍带 `URL,{json}` 选项（阶段之间透传），这里拆出来再合并
        let split = RuleURLResolver.splitOptions(target.url)
        let options = URLOptions.merge(split.options, target.options)
        var mergedHeaders = headers
        if let optionHeaders = options.headers {
            for (key, value) in optionHeaders { mergedHeaders[key] = value }
        }
        var prepared = try prepare(
            url: split.url,
            method: method ?? options.method,
            headers: mergedHeaders,
            body: body ?? options.body,
            charset: options.charset,
            timeout: timeout ?? defaultTimeout,
            retry: retry ?? options.retry ?? 1
        )
        // P2-08：书源 HTTPS 优先——http 地址先试 https，失败再回退 http
        if Self.httpsFirstEnabled, prepared.url.hasPrefix("http://"),
           let https = Self.httpsUpgrade(prepared.url), let httpsURL = URL(string: https) {
            let httpsPrepared = Prepared(url: https, method: prepared.method, headers: prepared.headers,
                                         body: prepared.body, charset: prepared.charset,
                                         timeout: prepared.timeout, retry: 0)
            do {
                let response = try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do { continuation.resume(returning: try self.perform(httpsPrepared)) }
                        catch { continuation.resume(throwing: error) }
                    }
                }
                return response
            } catch {
                _ = httpsURL
                // 回退 http
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try self.perform(prepared))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 同步请求（`java.ajax` / `java.get` 用，保持 Legado 的同步语义）
    func requestSync(
        _ rawURL: String,
        method: String? = nil,
        headers: [String: String] = [:],
        body: String? = nil,
        timeout: TimeInterval? = nil,
        retry: Int? = nil
    ) throws -> EngineHTTPResponse {
        let split = RuleURLResolver.splitOptions(rawURL)
        var mergedHeaders = headers
        if let optionHeaders = split.options.headers {
            for (key, value) in optionHeaders { mergedHeaders[key] = value }
        }
        let prepared = try prepare(
            url: split.url,
            method: method ?? split.options.method,
            headers: mergedHeaders,
            body: body ?? split.options.body,
            charset: split.options.charset,
            timeout: timeout ?? defaultTimeout,
            retry: retry ?? split.options.retry ?? 1
        )
        return try perform(prepared)
    }

    // MARK: 请求准备与执行

    private struct Prepared {
        var url: String
        var method: String
        var headers: [String: String]
        var body: String?
        var charset: String?
        var timeout: TimeInterval
        var retry: Int
    }

    private func prepare(
        url: String,
        method: String?,
        headers: [String: String],
        body: String?,
        charset: String?,
        timeout: TimeInterval,
        retry: Int
    ) throws -> Prepared {
        let finalURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalURL.isEmpty else { throw SourceEngineError.invalidSource("URL 为空") }
        if finalURL.lowercased().hasPrefix("data:") {
            throw SourceEngineError.privateProtocol("data: 内联协议（阅读 Sigma/源阅私有协议）不在首版支持范围")
        }
        guard URL(string: finalURL) != nil else {
            throw SourceEngineError.ruleSyntax("URL 非法：\(String(finalURL.prefix(140)))")
        }

        var mergedHeaders = sourceHeaders
        mergedHeaders.merge(headers) { _, new in new }
        if !mergedHeaders.keys.contains(where: { $0.lowercased() == "user-agent" }) {
            mergedHeaders["User-Agent"] = Self.defaultUserAgent
        }
        if !mergedHeaders.keys.contains(where: { $0.lowercased() == "cookie" }) {
            let cookie = jar.header(for: finalURL)
            if !cookie.isEmpty { mergedHeaders["Cookie"] = cookie }
        }
        // POST body 是 JSON 且未显式声明 Content-Type 时补 application/json
        // （源里常用 `URL,{method:"POST", body:{...}}`，后端会因此返回 400）
        if let body,
           !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !mergedHeaders.keys.contains(where: { $0.lowercased() == "content-type" }) {
            if let data = body.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                mergedHeaders["Content-Type"] = "application/json; charset=utf-8"
            } else if body.contains("="), !body.contains("\n"), !body.contains("<") {
                // 表单登录：email=..&password=..
                mergedHeaders["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8"
            }
        }

        return Prepared(
            url: finalURL,
            method: (method ?? "GET").uppercased(),
            headers: mergedHeaders,
            body: body,
            charset: charset,
            timeout: max(1, timeout),
            retry: max(0, retry)
        )
    }

    private func perform(_ prepared: Prepared) throws -> EngineHTTPResponse {
        // GET 且非 POST 表单：命中短时缓存直接返回（免网络 + 免限速等待）
        if prepared.method == "GET" || prepared.method == "get" {
            let cacheKey = prepared.url
            cacheLock.lock()
            if let cached = responseCache[cacheKey], Date().timeIntervalSince(cached.date) < 20 {
                cacheLock.unlock()
                return cached.response
            }
            cacheLock.unlock()
        }
        var lastError: SourceEngineError = .unknown("请求未执行")
        let attempts = prepared.retry + 1

        for attempt in 0..<attempts {
            if attempt > 0 { Thread.sleep(forTimeInterval: 1.2) }
            limiter.waitSync()
            let started = Date()
            do {
                var response = try send(prepared)
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                response.elapsedMilliseconds = elapsed
                let bodyHint = response.isOK ? "" : " | " + String(response.body.prefix(120)).replacingOccurrences(of: "\n", with: " ")
                note("\(prepared.method) \(prepared.url) → \(response.status) \(response.body.utf8.count)B \(elapsed)ms\(bodyHint)")
                onCookiesChanged?(jar.export())
                if response.isOK {
                    if prepared.method == "GET" || prepared.method == "get" {
                        cacheLock.lock()
                        responseCache[prepared.url] = (Date(), response)
                        // LRU 淘汰：超上限时移除最旧条目（修复：原逻辑仅删「已过期」导致实际无上限）
                        while responseCache.count > 200 {
                            if let oldest = responseCache.min(by: { $0.value.date < $1.value.date }) {
                                responseCache.removeValue(forKey: oldest.key)
                            } else { break }
                        }
                        cacheLock.unlock()
                    }
                    return response
                }
                // 4xx 不重试（429 除外）；429 按 Retry-After 或 2.5s 退避
                if (400..<500).contains(response.status), response.status != 429 {
                    // 401/403 且响应体命中登录失效关键词 → 提示需要登录
                    if (response.status == 401 || response.status == 403),
                       response.body.count < 1200,
                       Self.loginFailureMarkers.contains(where: { response.body.lowercased().contains($0) }) {
                        throw SourceEngineError.needLogin
                    }
                    return response
                }
                if response.status == 429 {
                    let retryAfter = response.headers.first { $0.key.lowercased() == "retry-after" }
                        .flatMap { TimeInterval($0.value) }
                    Thread.sleep(forTimeInterval: min(8, max(1.5, retryAfter ?? 2.5)))
                }
                lastError = SourceEngineError.from(response: response)
            } catch let error as SourceEngineError {
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                note("\(prepared.method) \(prepared.url) → ✗ \(error.message) \(elapsed)ms")
                lastError = error
            } catch {
                lastError = Self.mapNetworkError(error)
            }
        }
        throw lastError
    }

    private func send(_ prepared: Prepared) throws -> EngineHTTPResponse {
        guard let url = URL(string: prepared.url) else {
            throw SourceEngineError.ruleSyntax("URL 非法：\(prepared.url)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = prepared.method
        request.timeoutInterval = prepared.timeout
        for (key, value) in prepared.headers { request.setValue(value, forHTTPHeaderField: key) }
        if let body = prepared.body, prepared.method != "GET", prepared.method != "HEAD" {
            request.httpBody = body.data(using: .utf8)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var data: Data?
        var response: URLResponse?
        var failure: Error?
        let task = session.dataTask(with: request) { bodyData, urlResponse, error in
            data = bodyData
            response = urlResponse
            failure = error
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + prepared.timeout + 3) == .timedOut {
            task.cancel()
            throw SourceEngineError.timeout
        }
        if let failure { throw Self.mapNetworkError(failure) }
        guard let http = response as? HTTPURLResponse else {
            throw SourceEngineError.socket("没有收到 HTTP 响应")
        }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        let charset = prepared.charset ?? Self.charset(from: headers)
        let text = Self.decode(data: data ?? Data(), charset: charset)
        let finalURL = http.url?.absoluteString ?? prepared.url

        // 收集 Set-Cookie
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
            jar.set(url: finalURL, cookie: "\(cookie.name)=\(cookie.value)")
        }

        return EngineHTTPResponse(
            status: http.statusCode,
            body: text,
            headers: headers,
            finalURL: finalURL,
            elapsedMilliseconds: 0
        )
    }

    private func note(_ line: String) {
        logLock.lock()
        if records.count > 300 { records.removeFirst(100) }
        records.append(line)
        logLock.unlock()
    }

    // MARK: 错误与编码

    static func mapNetworkError(_ error: Error) -> SourceEngineError {
        if let engine = error as? SourceEngineError { return engine }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return .socket(error.localizedDescription)
        }
        switch nsError.code {
        case NSURLErrorTimedOut:
            return .timeout
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return .dns(nsError.localizedDescription)
        case NSURLErrorCannotConnectToHost:
            return .connectionRefused(nsError.localizedDescription)
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid,
             NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorClientCertificateRejected:
            return .tls(nsError.localizedDescription)
        case NSURLErrorCancelled:
            return .timeout
        case NSURLErrorUnsupportedURL, NSURLErrorBadURL:
            return .ruleSyntax("URL 非法：\(nsError.localizedDescription)")
        default:
            return .socket(nsError.localizedDescription)
        }
    }

    private static func charset(from headers: [String: String]) -> String? {
        let contentType = headers.first { $0.key.lowercased() == "content-type" }?.value ?? ""
        guard let range = contentType.range(of: "charset=", options: .caseInsensitive) else { return nil }
        let value = contentType[range.upperBound...].split(separator: ";").first.map(String.init) ?? ""
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 按 charset 解码：声明 charset（header 或 meta）优先，多候选解码后按乱码评分择优。
    static func decode(data: Data, charset: String?) -> String {
        var declared = charset?.trimmingCharacters(in: .whitespacesAndNewlines)
        if declared?.isEmpty ?? true {
            declared = sniffMetaCharset(data)
        }
        var candidates: [String] = []
        if let declared, !declared.isEmpty, let text = decode(data, usingCharset: declared) {
            candidates.append(text)
        }
        if let utf8 = String(data: data, encoding: .utf8) { candidates.append(utf8) }
        if let gb = decode(data, usingCharset: "gb18030") { candidates.append(gb) }
        guard !candidates.isEmpty else { return decodeGB18030(data) }
        // 同一文本去重，按乱码评分升序取最优
        var seen = Set<String>()
        let unique = candidates.filter { seen.insert($0).inserted }
        return unique.min { mojibakeScore($0) < mojibakeScore($1) } ?? unique[0]
    }

    /// 从 HTML 前 4KB 里嗅探 `<meta charset=...>` / `content="text/html; charset=..."`（数据按 ASCII/Latin1 读取）
    private static func sniffMetaCharset(_ data: Data) -> String? {
        let prefix = data.prefix(4096)
        guard let ascii = String(data: prefix, encoding: .isoLatin1) else { return nil }
        let patterns = [
            #"charset\s*=\s*["']?([A-Za-z0-9_\-]+)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: ascii, range: NSRange(location: 0, length: (ascii as NSString).length)),
               match.numberOfRanges > 1 {
                let value = (ascii as NSString).substring(with: match.range(at: 1)).lowercased()
                if value != "utf-8" && value != "utf8" { return value }
                return value
            }
        }
        return nil
    }

    private static func decode(_ data: Data, usingCharset charset: String) -> String? {
        let lowered = charset.lowercased()
        if lowered.contains("gb") || lowered.contains("gbk") || lowered.contains("gb2312") {
            return decodeGB18030Optional(data)
        }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        if cfEncoding != kCFStringEncodingInvalidId {
            let encoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            if let text = String(data: data, encoding: String.Encoding(rawValue: encoding)) { return text }
        }
        return nil
    }

    private static func decodeGB18030Optional(_ data: Data) -> String? {
        let encoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: encoding))
    }

    /// 简单乱码评分：常见 GBK/UTF-8 互转乱码字符 + replacement char 越多分越高
    private static func mojibakeScore(_ text: String) -> Int {
        let markers: [Character] = ["锟", "鎴", "鐨", "鈥", "銆", "锛", "�", "銉", "鍙", "鍦", "锟"]
        var score = 0
        for character in text.prefix(20_000) {
            if markers.contains(character) { score += 3 }
        }
        return score
    }

    private static func decodeGB18030(_ data: Data) -> String {
        let encoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let text = String(data: data, encoding: String.Encoding(rawValue: encoding)) { return text }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - 流水线数据

struct SourceBook {
    var name: String = ""
    var author: String = ""
    var kind: String = ""
    var intro: String = ""
    var lastChapter: String = ""
    var coverUrl: String = ""
    var wordCount: String = ""
    var bookUrl: String = ""
    var checkKeyWord: String = ""
}

struct SourceBookInfo {
    var name: String = ""
    var author: String = ""
    var kind: String = ""
    var intro: String = ""
    var lastChapter: String = ""
    var coverUrl: String = ""
    var wordCount: String = ""
    var updateTime: String = ""
    var bookUrl: String = ""
    var tocUrl: String = ""
}

struct SourceChapter {
    var index: Int = 0
    var title: String = ""
    var url: String = ""
    var updateTime: String = ""
    var isVolume: Bool = false
}

struct SourceChapterContent {
    var title: String = ""
    var content: String = ""
    var chapter: SourceChapter = SourceChapter()
    /// P1-04：正文内嵌图片
    var images: [ExtractedReaderImage] = []
    /// 站点返回登录/付费提示：链路正常，正文被站点拦截（对应错误码 -12）
    var isPaywall: Bool = false
    var paywallHint: String?
    var characters: Int { content.count }
}

// MARK: - 四阶段流水线

/// Legado 书源四阶段流水线。
///
/// 每个阶段一个整体 deadline：search/bookInfo 15s、toc 60s、content 30s；
/// 单请求超时 15s、失败重试 1 次；同源 1 req/s 串行；UA 与 Cookie 自动注入。
/// 实例内部状态（当前书、变量表、baseUrl）按调用顺序串行使用，不做跨任务并发。
final class SourcePipeline {

    static let searchTimeout: TimeInterval = 15
    /// 发现页：分类接口可能较慢，但单类失败要快速跳过
    static let exploreTimeout: TimeInterval = 20
    static let bookInfoTimeout: TimeInterval = 15
    static let tocTimeout: TimeInterval = 60
    static let contentTimeout: TimeInterval = 30
    static let requestTimeout: TimeInterval = 15

    let source: BookSource
    let http: HTTPClient

    private let js: JSRuntime
    private let vars = RuleVariableStore()
    private(set) var keyword: String = ""
    private(set) var page: Int = 1
    private(set) var currentBook: SourceBookInfo?
    private(set) var currentChapter: SourceChapter?
    /// 最近一次请求的 HTTP 状态（调试入口展示用）
    private(set) var lastHTTPStatus: Int = 0
    /// 最近一次（可能被 loginCheckJs 改写后的）响应，供 UI/诊断查看
    private(set) var lastHTTPResponse: EngineHTTPResponse?
    /// 登录态（loginInfo），登录页/登录脚本写入，规则 JS 可读。
    private(set) var loginInfo: [String: String] = [:]
    /// 最近一次响应 URL / Content-Type
    private(set) var lastResponseURL: String = ""
    private(set) var lastContentType: String?
    /// 书源 `source.concurrentRate` 解析结果（诊断用）
    var rateLimitDescription: String {
        let config = http.limiter.configuration
        if config.isUnlimited { return "不限速" }
        return "\(config.accessLimit) 次/\(config.intervalMilliseconds)ms（平均 \(String(format: "%.0f", config.averageInterval * 1000))ms/次）"
    }
    /// JS 控制台输出（最近 200 条），供书源调试页展示
    var jsLogs: [String] { js.logs }
    /// 兼容层注入错误（nil 表示 packages_stub.js / jsoup_bridge.js 正常）
    var compatibilityLayerError: String? { js.compatibilityLayerError }

    init(source: BookSource,
         initialCookies: [String: [String: String]] = [:],
         loginInfo: [String: String] = [:],
         loginHeader: [String: String] = [:],
         onCookiesChanged: (([String: [String: String]]) -> Void)? = nil) {
        self.source = source
        self.loginInfo = loginInfo
        let jar = CookieJar(initial: initialCookies)
        let limiter = RateLimiter(configuration: RateLimiter.Configuration.parse(source.concurrentRate))
        var headers = source.headerMap
        for (key, value) in loginHeader { headers[key] = value }
        let client = HTTPClient(jar: jar, limiter: limiter, headers: headers)
        client.onCookiesChanged = onCookiesChanged
        self.http = client
        let runtime = JSRuntime(source: source, http: client, jar: jar)
        runtime.loginInfo = loginInfo.reduce(into: [:]) { $0[$1.key] = $1.value }
        runtime.executorMode = HTTPClient.currentExecutorMode
        self.js = runtime

        // 书源 `header` 可以是 JS（很多聚合源用 @js: getSecretKey() 生成签名头），
        // jsLib 在 runtime 初始化时已注入，这里求值一次并回填到 HTTPClient。
        if let rawHeader = source.header?.textValue,
           !rawHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = rawHeader.trimmingCharacters(in: .whitespacesAndNewlines)
            if JSBlock.isScript(trimmed) {
                let code = JSBlock.unwrap(trimmed)
                if let value = try? runtime.evaluateJS(code, bindings: RuleBindings()) {
                    let text = RuleEngine.text(value)
                    if let parsed = LenientJSON.parse(text) as? [String: Any] {
                        var dynamic = headers
                        for (key, item) in parsed { dynamic[key] = RuleEngine.text(item) }
                        client.setSourceHeaders(dynamic)
                    } else {
                        runtime.appendLog("header", "header 规则返回的不是 JSON 对象：\(text.prefix(120))")
                    }
                }
            }
        }
    }

    /// 站点根地址（bookSourceUrl 去掉 `#fragment`）
    var baseURL: String { RuleURLResolver.sourceBaseURL(source.bookSourceUrl) }

    // MARK: 阶段 1：搜索

    func search(_ keyword: String, page: Int = 1) async throws -> [SourceBook] {
        let clock = StageClock(Self.searchTimeout)
        self.keyword = keyword
        self.page = page
        self.currentBook = nil
        self.currentChapter = nil

        guard let searchRule = source.searchUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !searchRule.isEmpty else {
            throw SourceEngineError.invalidSource("书源缺少 searchUrl")
        }
        let searchAnalyzer = makeAnalyzer(result: "", baseURL: baseURL)
        let target = try rule { try RuleURLResolver.analyzeURL(searchRule, with: searchAnalyzer) }
        guard !target.url.isEmpty else { throw SourceEngineError.ruleNoResult("searchUrl 规则求值为空") }

        let response = try await fetch(target, timeout: clock.requestTimeout(cap: Self.requestTimeout))
        try clock.ensure()
        let body = response.body

        guard let searchRules = source.ruleSearch, let bookListRule = searchRules.bookList?.ruleString else {
            throw SourceEngineError.ruleNoResult("ruleSearch.bookList 为空")
        }
        let bodyAnalyzer = makeAnalyzer(result: body, baseURL: response.finalURL)
        var items = try rule { try bodyAnalyzer.analyzeList(bookListRule, input: body) }
        guard !items.isEmpty else {
            throw SourceEngineError.ruleNoResult("bookList 规则无结果（响应前 120 字：\(String(body.prefix(120)))）")
        }
        if items.count > 200 { items = Array(items.prefix(200)) }

        var books: [SourceBook] = []
        for item in items {
            let analyzer = makeAnalyzer(result: item, baseURL: response.finalURL)
            var book = SourceBook()
            book.checkKeyWord = searchRules.checkKeyWord?.textValue ?? ""
            book.name = try fieldText(searchRules.name, analyzer, input: item)
            book.author = try fieldText(searchRules.author, analyzer, input: item)
            book.kind = try fieldText(searchRules.kind, analyzer, input: item)
            book.intro = try fieldText(searchRules.intro, analyzer, input: item)
            book.lastChapter = try fieldText(searchRules.lastChapter, analyzer, input: item)
            book.coverUrl = try fieldText(searchRules.coverUrl, analyzer, input: item)
            book.wordCount = try fieldText(searchRules.wordCount, analyzer, input: item)
            if let bookURLRule = searchRules.bookUrl?.ruleString {
                book.bookUrl = try rule { try RuleURLResolver.analyzeURL(bookURLRule, with: analyzer) }.urlWithOptions
            }
            if book.bookUrl.isEmpty { book.bookUrl = response.finalURL }
            books.append(book)
        }
        return books
    }

    // MARK: 阶段 2：详情

    func bookInfo(_ book: SourceBook) async throws -> SourceBookInfo {
        let clock = StageClock(Self.bookInfoTimeout)
        guard !book.bookUrl.isEmpty else {
            throw SourceEngineError.ruleNoResult("搜索结果缺少 bookUrl，无法进入详情")
        }
        let pseudo = PseudoURL.isData(book.bookUrl)
        var content: Any
        var baseURL = book.bookUrl

        if pseudo {
            // data: 详情协议：payload 交给 init 规则自行解码 + 请求
            let payload = PseudoURL.payload(book.bookUrl)
            let searchBook = SourceBookInfo(name: book.name, author: book.author, bookUrl: book.bookUrl)
            if let initRule = source.ruleBookInfo?.`init`?.ruleString {
                let initAnalyzer = makeAnalyzer(result: payload, baseURL: book.bookUrl, book: searchBook)
                let value = try rule { try initAnalyzer.analyze(initRule, input: payload) }
                let isEmpty = !(value is [String: Any] || value is [Any]) && JSONValueUtil.text(value).isEmpty
                guard !isEmpty else { throw SourceEngineError.ruleNoResult("ruleBookInfo.init 结果为空") }
                content = value
            } else {
                content = payload
            }
        } else {
            let target = RuleURL(url: book.bookUrl)
            let response = try await fetch(target, timeout: clock.requestTimeout(cap: Self.requestTimeout))
            try clock.ensure()
            baseURL = response.finalURL
            content = response.body
            if let initRule = source.ruleBookInfo?.`init`?.ruleString {
                let initAnalyzer = makeAnalyzer(result: response.body, baseURL: response.finalURL)
                let value = try rule { try initAnalyzer.analyze(initRule, input: response.body) }
                let isEmpty = !(value is [String: Any] || value is [Any]) && JSONValueUtil.text(value).isEmpty
                guard !isEmpty else { throw SourceEngineError.ruleNoResult("ruleBookInfo.init 结果为空") }
                content = value
            }
        }

        let searchBook = SourceBookInfo(name: book.name, author: book.author, bookUrl: book.bookUrl)
        let analyzer = makeAnalyzer(result: content, baseURL: baseURL, book: searchBook)
        let rules = source.ruleBookInfo
        var info = SourceBookInfo(
            name: book.name,
            author: book.author,
            kind: book.kind,
            intro: book.intro,
            lastChapter: book.lastChapter,
            coverUrl: book.coverUrl,
            wordCount: book.wordCount,
            updateTime: "",
            bookUrl: book.bookUrl,
            tocUrl: ""
        )
        if rules?.name?.ruleString != nil { info.name = try fieldText(rules?.name, analyzer, input: content) }
        if rules?.author?.ruleString != nil { info.author = try fieldText(rules?.author, analyzer, input: content) }
        if rules?.kind?.ruleString != nil { info.kind = try fieldText(rules?.kind, analyzer, input: content) }
        if rules?.intro?.ruleString != nil { info.intro = try fieldText(rules?.intro, analyzer, input: content) }
        if rules?.lastChapter?.ruleString != nil { info.lastChapter = try fieldText(rules?.lastChapter, analyzer, input: content) }
        if rules?.coverUrl?.ruleString != nil { info.coverUrl = try fieldText(rules?.coverUrl, analyzer, input: content) }
        if rules?.wordCount?.ruleString != nil { info.wordCount = try fieldText(rules?.wordCount, analyzer, input: content) }
        if rules?.updateTime?.ruleString != nil { info.updateTime = try fieldText(rules?.updateTime, analyzer, input: content) }

        if let tocURLRule = rules?.tocUrl?.ruleString {
            info.tocUrl = try rule { try RuleURLResolver.analyzeURL(tocURLRule, with: analyzer) }.urlWithOptions
        }
        if info.tocUrl.isEmpty { info.tocUrl = book.bookUrl }
        guard !info.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SourceEngineError.ruleNoResult("详情页 name 规则为空")
        }
        currentBook = info
        return info
    }

    // MARK: 阶段 3：目录

    func toc(_ book: SourceBookInfo) async throws -> [SourceChapter] {
        let clock = StageClock(Self.tocTimeout)
        guard !book.tocUrl.isEmpty else { throw SourceEngineError.invalidSource("没有 tocUrl") }
        var content: Any
        var baseURL = book.tocUrl
        if PseudoURL.isData(book.tocUrl) {
            content = PseudoURL.payload(book.tocUrl)
        } else {
            let response = try await fetch(RuleURL(url: book.tocUrl), timeout: clock.requestTimeout(cap: Self.requestTimeout))
            try clock.ensure()
            baseURL = response.finalURL
            content = response.body
            if let preUpdate = source.ruleToc?.preUpdateJs?.ruleString {
                let preAnalyzer = makeAnalyzer(result: response.body, baseURL: response.finalURL, book: book)
                if let value = try? preAnalyzer.analyze(preUpdate, input: response.body),
                   !JSONValueUtil.text(value).isEmpty {
                    content = value
                }
            }
        }

        let analyzer = makeAnalyzer(result: content, baseURL: baseURL, book: book)
        guard let listRule = source.ruleToc?.chapterList?.ruleString else {
            throw SourceEngineError.ruleNoResult("ruleToc.chapterList 为空")
        }
        let items: [Any]
        do {
            items = try rule { try analyzer.analyzeList(listRule, input: content) }
        } catch {
            throw rethrowIfAuthRejected(error)
        }
        guard !items.isEmpty else {
            throw SourceEngineError.emptyContent("目录为空（chapterList 无结果）")
        }

        var chapters: [SourceChapter] = []
        for (index, item) in items.enumerated() {
            let itemAnalyzer = makeAnalyzer(result: item, baseURL: baseURL, book: book)
            var chapter = SourceChapter(index: index, title: "", url: "", updateTime: "", isVolume: false)
            chapter.title = try fieldText(source.ruleToc?.chapterName, itemAnalyzer, input: item)
            if let urlRule = source.ruleToc?.chapterUrl?.ruleString {
                chapter.url = try rule { try RuleURLResolver.analyzeURL(urlRule, with: itemAnalyzer) }.urlWithOptions
            }
            chapter.updateTime = try fieldText(source.ruleToc?.updateTime, itemAnalyzer, input: item)
            if let volumeRule = source.ruleToc?.isVolume?.ruleString {
                chapter.isVolume = JSONValueUtil.boolValue(try? itemAnalyzer.analyze(volumeRule, input: item))
            }
            chapters.append(chapter)
        }
        // P0-04 章节规则：去空/去重/卷名识别/倒序/标题清理，再做编号排序。
        let ruleConfig = await MainActor.run { ChapterRuleStore.shared.config(for: source.bookSourceUrl) }
        return ChapterRuleEngine.apply(chapters, config: ruleConfig).chapters
    }

    // MARK: 阶段 4：正文

    func content(_ chapter: SourceChapter, book: SourceBookInfo? = nil) async throws -> SourceChapterContent {
        let clock = StageClock(Self.contentTimeout)
        currentChapter = chapter
        guard !chapter.url.isEmpty else {
            throw SourceEngineError.ruleNoResult(chapter.isVolume ? "该目录项是卷名（没有正文）" : "chapterUrl 为空（目录规则未取到章节地址）")
        }
        let pseudoChapter = PseudoURL.isData(chapter.url)
        var response: EngineHTTPResponse
        if pseudoChapter {
            // data: 正文协议：payload 交给 content 规则自行解码 + 请求
            response = EngineHTTPResponse(status: 200,
                                          body: PseudoURL.payload(chapter.url),
                                          headers: [:],
                                          finalURL: chapter.url,
                                          isInline: true)
        } else {
            response = try await fetch(RuleURL(url: chapter.url), timeout: clock.requestTimeout(cap: 20))
            try clock.ensure()
        }

        let webJs = pseudoChapter ? nil : source.ruleContent?.webJs?.ruleString
        let sourceRegex = pseudoChapter ? nil : source.ruleContent?.sourceRegex?.ruleString

        // Legado ruleContent.sourceRegex：从 WebView 拦截到的 XHR/fetch 响应中挑出正文
        if let sourceRegex, !sourceRegex.isEmpty {
            let rendered = try? await HeadlessWebViewEngine.shared.renderDetailed(
                html: response.body, baseURL: response.finalURL, url: nil,
                javaScript: webJs, timeout: 25,
                captureNetwork: true, captureWait: 2.5,
                headerOverrides: source.headerMap
            )
            let matched = rendered?.responses.first { item in
                Self.regexMatches(sourceRegex, item.body) || Self.regexMatches(sourceRegex, item.url)
            }
            if let matched, !matched.body.isEmpty {
                response.body = matched.body
            } else if let js = rendered?.javaScriptResult, !js.isEmpty, HtmlFormatter.containsHTMLTags(js) || js.count > 200 {
                response.body = js
            } else if let html = rendered?.html, HtmlFormatter.containsHTMLTags(html) {
                response.body = html
            }
        } else if let webJs, !webJs.isEmpty {
            // Legado ruleContent.webJs：正文页需要 WebView 执行 JS 后再取正文
            if let rendered = HeadlessWebViewEngine.renderSync(
                html: response.body, baseURL: response.finalURL, url: nil,
                javaScript: webJs, timeout: 25
            ), !rendered.isEmpty {
                response.body = rendered
            }
        }

        guard let contentRule = source.ruleContent?.content?.ruleString else {
            throw SourceEngineError.ruleNoResult("ruleContent.content 为空")
        }
        let analyzer = makeAnalyzer(result: response.body, baseURL: response.finalURL, book: book, chapter: chapter)
        var raw: Any
        do {
            raw = try rule { try analyzer.analyze(contentRule, input: response.body, asList: false) }
        } catch {
            throw rethrowIfAuthRejected(error)
        }
        if let array = raw as? [Any] {
            raw = array.map { JSONValueUtil.text($0) }.joined(separator: "\n")
        }
        let rawText = JSONValueUtil.text(raw)
        // `@html` / `@all` 等规则的正文是 HTML 片段：转成阅读器可用的纯文本。
        // 已经是纯文本（`@text` / `@textNodes`）的结果不含标签，不会被二次格式化。
        let extracted = ReaderImageExtractor.extract(from: rawText, baseURL: response.finalURL)
        let text = extracted.text
        let images = extracted.images
        if Self.looksLikeCiphertext(text) {
            throw SourceEngineError.emptyContent("站点返回加密正文：请在「书源 → 登录」完成该书源账号登录，或更新到最新书源版本后再试")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // 站点可能把登录/付费提示放在 msg/code 等非 content 字段里（如 {"code":-1,"msg":"...上限..."}），
            // 此时应判为 -12 需要登录，而不是 -13 空正文。
            let bodyText = JSONValueUtil.text(response.body)
            if Self.detectPaywall(bodyText) {
                throw SourceEngineError.needLogin
            }
            throw SourceEngineError.emptyContent("正文为空（ruleContent.content 无结果；响应：\(bodyText.prefix(140))）")
        }

        var title = chapter.title
        if source.ruleContent?.title?.ruleString != nil,
           let value = try? fieldText(source.ruleContent?.title, analyzer, input: response.body),
           !value.isEmpty {
            title = value
        }
        // 标题规则也可能返回 html（如 `h1@html`），同样清洗成单行纯文本
        if HtmlFormatter.containsHTMLTags(title) {
            title = HtmlFormatter.formatTitle(title)
        }

        let paywall = Self.detectPaywall(text)
        return SourceChapterContent(
            title: title,
            content: text,
            chapter: chapter,
            images: images,
            isPaywall: paywall,
            paywallHint: paywall ? "站点返回登录/付费提示：规则链路正常，正文被站点拦截" : nil
        )
    }

    /// 后端用 200 + `{"error":"访问被拒绝"}` 表示未登录：映射为 -12 需要登录。
    static func authRejected(body: String) -> Bool {
        guard body.count < 1200 else { return false }
        let markers = ["访问被拒绝", "未登录", "请先登录", "登录已过期", "登录失效", "unauthorized",
                       "login first", "需要登录", "请登录", "认证失败", "鉴权失败", "forbidden",
                       "invalid token", "token 失效", "token已失效", "session expired", "请重新登录"]
        return markers.contains { body.lowercased().contains($0.lowercased()) }
    }

    private func rethrowIfAuthRejected(_ error: Error) -> Error {
        if case SourceEngineError.jsError = error, Self.authRejected(body: js.lastAjaxBody) {
            return SourceEngineError.needLogin
        }
        return error
    }

    /// 严格模式：正文命中付费墙时直接抛 `-12`，方便调用方统一弹登录界面
    func contentOrThrow(_ chapter: SourceChapter, book: SourceBookInfo? = nil) async throws -> SourceChapterContent {
        let result = try await content(chapter, book: book)
        if result.isPaywall { throw SourceEngineError.needLogin }
        return result
    }

    static func regexMatches(_ pattern: String, _ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return false }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    // MARK: 内部工具

    /// `data:detailsUrl;base64,<payload>{"opt":1}` 这类私有协议：
    /// 不发起 HTTP，而是把 payload 作为 `result` 交给规则 JS 自行处理。
    /// 源里普遍紧跟 `java.hexDecodeToString(result)`，因此统一转成 hex 传给规则。
    enum PseudoURL {
        static func isData(_ url: String) -> Bool {
            url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("data:")
        }

        static func payload(_ url: String) -> String {
            guard let comma = url.firstIndex(of: ",") else { return url }
            var text = String(url[url.index(after: comma)...])
            if let optionRange = text.range(of: ",{") {
                text = String(text[..<optionRange.lowerBound])
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, looksLikeHex(text) { return text.lowercased() }
            if let data = Data(base64Encoded: text, options: [.ignoreUnknownCharacters]) {
                return data.map { String(format: "%02x", $0) }.joined()
            }
            return text
        }

        static func looksLikeHex(_ text: String) -> Bool {
            guard text.count >= 8, text.count % 2 == 0 else { return false }
            return text.allSatisfy { $0.isHexDigit }
        }
    }

    private struct StageClock {
        let deadline: Date

        init(_ timeout: TimeInterval) {
            deadline = Date().addingTimeInterval(timeout)
        }

        /// 本阶段还能用多久（至少 1s，最多 cap）
        func requestTimeout(cap: TimeInterval) -> TimeInterval {
            max(1, min(cap, deadline.timeIntervalSinceNow))
        }

        func ensure() throws {
            if Date() > deadline { throw SourceEngineError.timeout }
        }
    }

    private func fetch(_ target: RuleURL, timeout: TimeInterval, retry: Int? = nil) async throws -> EngineHTTPResponse {
        #if DEBUG
        print("[engine] GET \(target.url.prefix(160))")
        #endif
        var response = try await http.request(target, timeout: timeout, retry: retry)
        lastHTTPStatus = response.status
        lastResponseURL = response.finalURL
        lastContentType = Self.contentType(from: response.headers)

        // loginCheckJs：每次响应后执行（Legado WebBook 语义）。JS 可以：
        //   - 返回字符串 → 替换 body；
        //   - 返回 result / 调用 result.setBody(...) → 使用修改后的 body；
        //   - 抛错（常见 throw '未登录'）→ 映射为 -12 需要登录。
        if let check = source.loginCheckJs?.trimmingCharacters(in: .whitespacesAndNewlines), !check.isEmpty {
            do {
                response = try js.applyLoginCheck(check, to: response)
            } catch let error as SourceEngineError {
                if case .jsError(let message) = error, Self.looksLikeLoginFailure(message) {
                    throw SourceEngineError.needLogin
                }
                throw error
            } catch {
                throw SourceEngineError.jsError(error.localizedDescription)
            }
            lastHTTPStatus = response.status
            lastResponseURL = response.finalURL
        }
        lastHTTPResponse = response
        #if DEBUG
        print("[engine] → HTTP \(response.status) \(response.body.utf8.count)B \(target.url.prefix(120))")
        #endif
        guard response.isOK else { throw SourceEngineError.from(response: response) }
        return response
    }

    // MARK: - 登录

    /// 执行 loginUrl 的 `@js:`/`<js>` 脚本；返回脚本写入的登录头（java.putLoginHeader 或返回对象）。
    func runLoginScript() async throws -> [String: String] {
        guard let raw = source.loginUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return [:]
        }
        let code = Self.loginCode(from: raw)
        guard !code.isEmpty else { return [:] }
        var bindings = RuleBindings()
        bindings.result = loginInfo
        bindings.sourceName = source.bookSourceName
        // Legado 约定：loginUrl 里只放函数定义，执行时再调用 login()
        let invocation = "\n;if (typeof login === 'function') { login.apply(this); }"
        let value = try js.evaluateJS(code + invocation, bindings: bindings)
        var headers = js.loginHeaders
        if let dictionary = value as? [String: Any] {
            for (key, item) in dictionary { headers[key] = RuleEngine.text(item) }
        } else if let text = value as? String,
                  let parsed = LenientJSON.parse(text) as? [String: Any] {
            for (key, item) in parsed { headers[key] = RuleEngine.text(item) }
        }
        return headers
    }

    /// 执行 loginUi 里按钮的 action（`login(true)` / `fq_login()` / `sethost()` …），
    /// 复用 loginUrl 里的函数定义，并把 `java.putLoginHeader` 的结果带回来。
    func runLoginAction(_ action: String, loginInfo: [String: String]) async throws -> [String: String] {
        let raw = source.loginUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, !action.isEmpty else { return [:] }
        let base = Self.loginCode(from: raw)
        var bindings = RuleBindings()
        bindings.result = loginInfo
        bindings.sourceName = source.bookSourceName
        let value = try js.evaluateJS(base + "\n;" + action, bindings: bindings)
        return Self.headers(from: value, runtime: js)
    }

    private static func headers(from value: Any?, runtime: JSRuntime) -> [String: String] {
        var headers = runtime.loginHeaders
        if let dictionary = value as? [String: Any] {
            for (key, item) in dictionary { headers[key] = RuleEngine.text(item) }
        } else if let text = value as? String,
                  let parsed = LenientJSON.parse(text) as? [String: Any] {
            for (key, item) in parsed { headers[key] = RuleEngine.text(item) }
        }
        return headers
    }

    /// loginUi 的 `@js:`/`<js>` 形式返回 JSON 字符串；普通 JSON 原样返回。
    func resolvedLoginUI() async throws -> String {
        guard let raw = source.loginUi?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return ""
        }
        let code = Self.loginCode(from: raw)
        if code == raw { return raw }
        let value = try js.evaluateJS(code, bindings: RuleBindings())
        return RuleEngine.text(value)
    }

    static func loginCode(from raw: String) -> String {
        JSBlock.unwrap(raw)
    }

    // MARK: - 发现 / Explore

    struct ExploreCategory: Identifiable, Hashable, Sendable {
        var title: String
        var url: String
        var id: String { title + "|" + url }
    }

    /// 解析 exploreUrl：JS / JSON 数组 / `标题::URL` 行文本。
    func exploreCategories() async throws -> [ExploreCategory] {
        guard let raw = source.exploreUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return []
        }
        if JSBlock.isScript(raw) {
            let code = Self.loginCode(from: raw)
            let value = try js.evaluateJS(code, bindings: RuleBindings())
            return Self.parseExploreCategories(value)
        }
        if let value = LenientJSON.parse(raw) {
            let parsed = Self.parseExploreCategories(value)
            if !parsed.isEmpty { return parsed }
        }
        var categories: [ExploreCategory] = []
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let range = trimmed.range(of: "::") else { continue }
            let title = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let url = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !url.isEmpty else { continue }
            categories.append(ExploreCategory(title: title, url: url))
        }
        return categories
    }

    static func parseExploreCategories(_ value: Any?) -> [ExploreCategory] {
        let array: [Any]
        if let list = value as? [Any] {
            array = list
        } else if let text = value as? String,
                  let parsed = LenientJSON.parse(text) as? [Any] {
            array = parsed
        } else if let text = value as? String {
            var result: [ExploreCategory] = []
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let range = trimmed.range(of: "::") else { continue }
                let title = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let url = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty, !url.isEmpty {
                    result.append(ExploreCategory(title: title, url: url))
                }
            }
            return result
        } else {
            return []
        }

        var result: [ExploreCategory] = []
        for item in array {
            if let dictionary = item as? [String: Any] {
                let title = RuleEngine.text(dictionary["title"] ?? dictionary["name"] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let url = RuleEngine.text(dictionary["url"] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty, !url.isEmpty {
                    result.append(ExploreCategory(title: title, url: url))
                }
            }
        }
        return result
    }

    /// 拉取某个发现分类的一页书籍。
    func explore(category: ExploreCategory, page: Int = 1) async throws -> [SourceBook] {
        self.page = page
        guard let rules = source.ruleExplore,
              let bookListRule = rules.bookList?.ruleString,
              !bookListRule.isEmpty else {
            throw SourceEngineError.invalidSource("ruleExplore.bookList 为空")
        }
        let clock = StageClock(Self.exploreTimeout)
        let targetAnalyzer = makeAnalyzer(result: "", baseURL: baseURL)
        let target: RuleURL
        if category.url.isEmpty {
            target = RuleURL(url: baseURL)
        } else {
            target = try rule { try RuleURLResolver.analyzeURL(category.url, with: targetAnalyzer) }
        }
        guard !target.url.isEmpty else { throw SourceEngineError.ruleNoResult("发现分类 URL 为空") }

        // 发现分类是「一屏一类」，失败应当快速跳到下一类，避免重试把 30s+ 拖满。
        let response = try await fetch(target, timeout: clock.requestTimeout(cap: 10), retry: 0)
        try clock.ensure()
        let body = response.body
        let analyzer = makeAnalyzer(result: body, baseURL: response.finalURL)
        var items = try rule { try analyzer.analyzeList(bookListRule, input: body) }
        guard !items.isEmpty else {
            throw SourceEngineError.ruleNoResult("发现列表为空（响应前 120 字：\(String(body.prefix(120)))）")
        }
        if items.count > 200 { items = Array(items.prefix(200)) }

        var books: [SourceBook] = []
        for item in items {
            let itemAnalyzer = makeAnalyzer(result: item, baseURL: response.finalURL)
            var book = SourceBook()
            book.name = try fieldText(rules.name, itemAnalyzer, input: item)
            book.author = try fieldText(rules.author, itemAnalyzer, input: item)
            book.kind = try fieldText(rules.kind, itemAnalyzer, input: item)
            book.intro = try fieldText(rules.intro, itemAnalyzer, input: item)
            book.lastChapter = try fieldText(rules.lastChapter, itemAnalyzer, input: item)
            book.coverUrl = try fieldText(rules.coverUrl, itemAnalyzer, input: item)
            book.wordCount = try fieldText(rules.wordCount, itemAnalyzer, input: item)
            if let bookURLRule = rules.bookUrl?.ruleString {
                book.bookUrl = try rule { try RuleURLResolver.analyzeURL(bookURLRule, with: itemAnalyzer) }.urlWithOptions
            }
            if book.bookUrl.isEmpty { book.bookUrl = response.finalURL }
            if !book.name.isEmpty { books.append(book) }
        }
        return books
    }

    var jsLibStatus: String? { js.jsLibStatus }
    var lastJSAjaxStatus: Int { js.lastAjaxStatus }
    var lastJSAjaxBody: String { js.lastAjaxBody }

    /// 自检：调用 jsLib 中定义的函数，验证共享脚本已注入。
    func testJsLib() throws -> String {
        let code = "typeof sharedGreeting === 'function' ? sharedGreeting('阅读') : ('未定义: ' + (typeof sharedGreeting))"
        let value = try js.evaluateJS(code, bindings: RuleBindings())
        return RuleEngine.text(value)
    }

    /// 诊断快照：UI 可直接展示（书源名、最近 HTTP、JS console、请求流水）
    var diagnosticsSnapshot: [String] {
        var lines: [String] = []
        lines.append("书源：\(source.bookSourceName)")
        lines.append("最近 HTTP：\(lastHTTPStatus) \(lastResponseURL.isEmpty ? "-" : String(lastResponseURL.prefix(160)))")
        lines.append("限速：\(rateLimitDescription)")
        if let contentType = lastContentType { lines.append("Content-Type：\(contentType)") }
        if let error = js.compatibilityLayerError { lines.append("JS 兼容层：\(error)") }
        if let jsLib = js.jsLibStatus { lines.append("jsLib：\(jsLib)") }
        let requestLines = http.log
        if !requestLines.isEmpty {
            lines.append("--- HTTP 流水（最近 20 条）---")
            lines.append(contentsOf: requestLines.suffix(20))
        }
        let jsLines = js.logs
        if !jsLines.isEmpty {
            lines.append("--- JS console（最近 60 条）---")
            lines.append(contentsOf: jsLines.suffix(60))
        }
        return lines
    }

    private static func contentType(from headers: [String: String]) -> String? {
        headers.first { $0.key.lowercased() == "content-type" }?.value
    }

    private static func looksLikeLoginFailure(_ message: String) -> Bool {
        let lowered = message.lowercased()
        let markers = ["登录", "login", "未登陆", "需要验证", "请先登录", "cookie"]
        return markers.contains { lowered.contains($0) }
    }

    /// 请求流水（调试入口展示用）
    var requestLog: [String] { http.log }

    /// 规则错误统一映射成 `-8`（JS 错误保留 `-9` / `-10`）
    private func rule<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as SourceEngineError {
            throw error
        } catch let error as RuleEngineError {
            throw SourceEngineError.ruleSyntax(error.errorDescription ?? "规则执行失败")
        } catch {
            throw SourceEngineError.unknown(error.localizedDescription)
        }
    }

    private func makeAnalyzer(
        result: Any,
        baseURL: String,
        book: SourceBookInfo? = nil,
        chapter: SourceChapter? = nil
    ) -> RuleAnalyzer {
        let context = RuleContext(
            result: result,
            key: keyword,
            page: page,
            baseURL: baseURL,
            source: source,
            book: bookDictionary(book ?? currentBook),
            chapter: chapterDictionary(chapter ?? currentChapter),
            contentType: lastContentType
        )
        let webViewEvaluator: (String, String, String) -> Any? = { html, base, script in
            let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty, !base.isEmpty {
                return HeadlessWebViewEngine.renderSync(html: nil, baseURL: base, url: base,
                                                        javaScript: script, timeout: 25) ?? ""
            }
            return HeadlessWebViewEngine.renderSync(html: html, baseURL: base.isEmpty ? nil : base,
                                                    url: nil, javaScript: script, timeout: 25) ?? ""
        }
        return RuleAnalyzer(context: context, vars: vars, js: js, webView: webViewEvaluator)
    }

    private func fieldText(_ ruleValue: RuleValue?, _ analyzer: RuleAnalyzer, input: Any) throws -> String {
        guard let text = ruleValue?.ruleString else { return "" }
        let value = try rule { try analyzer.analyze(text, input: input, asList: false) }
        return JSONValueUtil.text(value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func bookDictionary(_ book: SourceBookInfo?) -> [String: Any]? {
        guard let book else { return nil }
        return ["name": book.name, "author": book.author, "bookUrl": book.bookUrl, "tocUrl": book.tocUrl]
    }

    private func chapterDictionary(_ chapter: SourceChapter?) -> [String: Any]? {
        guard let chapter else { return nil }
        return ["index": chapter.index, "title": chapter.title, "url": chapter.url]
    }

    // MARK: 目录顺序归一化

    private struct TOCSortMeta {
        var volume: Int?
        var chapter: Int?
    }

    /// 第N章 / 第N回 / 第N节 / 第N话 / 第N集 / 第N篇（中文数字或阿拉伯数字）
    private static let chapterOrderPattern = try! NSRegularExpression(
        pattern: "第\\s*([0-9零〇一二两三四五六七八九十百千万]+)\\s*(?:章|回|节|话|集|篇)"
    )
    /// 第N卷 / 第N部
    private static let volumeOrderPattern = try! NSRegularExpression(
        pattern: "第\\s*([0-9零〇一二两三四五六七八九十百千万]+)\\s*(?:卷|部)"
    )
    /// 卷一 / 卷十二
    private static let volumePrefixPattern = try! NSRegularExpression(
        pattern: "^\\s*卷\\s*([0-9零〇一二两三四五六七八九十百千万]+)"
    )
    /// 无「第N章」时的裸数字标题：`83 今天` / `83. 今天` / `83、今天`
    private static let leadingOrderPattern = try! NSRegularExpression(
        pattern: "^\\s*([0-9]{1,6})(?:[.、．:：\\s]|$)"
    )

    /// 把目录按 (卷号, 章号) 升序做**稳定**排序。
    ///
    /// 触发条件：≥80% 的条目能从标题解析出章号/卷号，且至少 2 个正文章号。
    /// 卷标题（isVolume）不参与排序，回到它原来的插入位置；没有卷号的章节继承
    /// 最近一次卷标题，若整本书只出现过一个卷号则所有章节都归入该卷。
    static func normalizedTOC(_ chapters: [SourceChapter]) -> [SourceChapter] {
        guard chapters.count >= 3 else { return chapters }

        var metas: [TOCSortMeta] = []
        metas.reserveCapacity(chapters.count)
        var currentVolume: Int?
        var volumes = Set<Int>()
        var parsedCount = 0
        var parsedChapterCount = 0

        for chapter in chapters {
            let title = chapter.title
            if chapter.isVolume {
                let volume = matchNumber(volumeOrderPattern, in: title)
                    ?? matchNumber(volumePrefixPattern, in: title)
                if let volume {
                    parsedCount += 1
                    volumes.insert(volume)
                    currentVolume = volume
                }
                metas.append(TOCSortMeta(volume: volume, chapter: nil))
            } else {
                let chapterNumber = matchNumber(chapterOrderPattern, in: title)
                    ?? matchNumber(leadingOrderPattern, in: title)
                let explicitVolume = matchNumber(volumeOrderPattern, in: title)
                    ?? matchNumber(volumePrefixPattern, in: title)
                if chapterNumber != nil {
                    parsedCount += 1
                    parsedChapterCount += 1
                }
                if let explicitVolume { volumes.insert(explicitVolume) }
                metas.append(TOCSortMeta(volume: explicitVolume ?? currentVolume, chapter: chapterNumber))
            }
        }

        // ≥80% 才认为目录「可编号」，否则保持服务端顺序（避免把「第一卷」这类
        // 散文式标题误排序）。
        guard parsedChapterCount >= 2, parsedCount * 5 >= chapters.count * 4 else {
            return chapters
        }

        let singleVolume = volumes.count == 1 ? volumes.first : nil
        var lastChapter = 0
        var lastVolume = singleVolume ?? 0
        var keys: [(volume: Int, chapter: Int)] = []
        keys.reserveCapacity(chapters.count)

        for (index, chapter) in chapters.enumerated() {
            if chapter.isVolume {
                if let volume = metas[index].volume { lastVolume = volume }
                keys.append((lastVolume, Int.max))
                continue
            }
            if let volume = metas[index].volume ?? singleVolume { lastVolume = volume }
            if let chapterNumber = metas[index].chapter { lastChapter = chapterNumber }
            // 无法解析的条目（楔子/番外）沿用前一个章号并靠原顺序保持相邻
            keys.append((lastVolume, metas[index].chapter ?? lastChapter))
        }

        let ordered = chapters.indices
            .filter { !chapters[$0].isVolume }
            .sorted { left, right in
                if keys[left].volume != keys[right].volume { return keys[left].volume < keys[right].volume }
                if keys[left].chapter != keys[right].chapter { return keys[left].chapter < keys[right].chapter }
                return left < right
            }

        var output = ordered.map { chapters[$0] }
        for index in chapters.indices where chapters[index].isVolume {
            output.insert(chapters[index], at: min(index, output.count))
        }
        return output
    }

    private static func matchNumber(_ regex: NSRegularExpression, in text: String) -> Int? {
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > 1 else { return nil }
        return parseTOCNumber(nsText.substring(with: match.range(at: 1)))
    }

    /// 中文数字 / 阿拉伯数字 → Int（覆盖 1…99999999，章节号足够）
    static func parseTOCNumber(_ raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }) {
            return Int(text)
        }

        let digitMap: [Character: Int] = [
            "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        let unitMap: [Character: Int] = ["十": 10, "百": 100, "千": 1000, "万": 10000]

        // 「一零二」这种纯数字串（无单位）
        if !text.contains(where: { unitMap[$0] != nil }) {
            var digits = ""
            for character in text {
                guard let value = digitMap[character] else { return nil }
                digits += String(value)
            }
            return digits.isEmpty ? nil : Int(digits)
        }

        var total = 0
        var section = 0
        var number = 0
        var sawAny = false

        for character in text {
            if let digit = digitMap[character] {
                number = digit
                sawAny = true
            } else if let unit = unitMap[character] {
                sawAny = true
                if unit == 10000 {
                    section += number
                    if section == 0 { section = 1 }
                    total += section * unit
                    section = 0
                    number = 0
                } else {
                    if number == 0 { number = 1 }
                    section += number * unit
                    number = 0
                }
            } else {
                return nil
            }
        }
        guard sawAny else { return nil }
        let value = total + section + number
        return value > 0 ? value : nil
    }

    // MARK: 付费墙识别

    /// 正文命中登录/付费提示时标记为 `paywall`（-12），而不是当成“空正文”（-13）。
    /// 正文像密文/Base64 而不是中文正文时判定为「站点加密正文」。
    static func looksLikeCiphertext(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 400 else { return false }
        let sample = trimmed.prefix(1200)
        var base64Count = 0
        var cjkCount = 0
        for scalar in sample.unicodeScalars {
            if (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
                || (48...57).contains(scalar.value)
                || scalar == "+" || scalar == "/" || scalar == "=" {
                base64Count += 1
            }
            if (0x4E00...0x9FFF).contains(scalar.value) { cjkCount += 1 }
        }
        let ratio = Double(base64Count) / Double(sample.unicodeScalars.count)
        return ratio > 0.95 && cjkCount < 5
    }

    static func detectPaywall(_ text: String) -> Bool {
        // 站点拦截提示通常很短；真正文里零星出现“VIP/购买”字样时不算付费墙
        guard text.count < 400 else { return false }
        return paywallPattern(String(text.prefix(300)))
    }

    private static func paywallPattern(_ text: String) -> Bool {
        let markers = [
            "免登录访问次数", "登录后刷新", "请登录", "开通VIP", "VIP专属", "VIP",
            "购买本章", "订阅本章", "付费阅读", "章节已下架", "今日免费次数", "免费次数",
            "需要登录", "购买", "访问被拒绝", "登录已过期", "未登录", "token失效"
        ]
        return markers.contains { text.contains($0) }
    }
}
