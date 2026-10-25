// WebDAVClient.swift — PROPFIND / MKCOL / PUT / GET（Basic Auth、URL 拼接、错误映射）
import Foundation

enum WebDAVError: LocalizedError {
    case invalidURL(String)
    case unauthorized
    case notFound(String)
    case methodNotAllowed(Int)
    case conflict(Int)
    case locked
    case insufficientStorage
    case serverError(Int)
    case unexpectedStatus(Int, String)
    case network(String)
    case invalidResponse(String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value): return "WebDAV URL 非法：\(value)"
        case .unauthorized: return "WebDAV 认证失败（401/403），请检查用户名/密码"
        case .notFound(let path): return "WebDAV 路径不存在：\(path)"
        case .methodNotAllowed(let status): return "WebDAV 方法不被允许（HTTP \(status)）"
        case .conflict(let status): return "WebDAV 目录冲突（HTTP \(status)）"
        case .locked: return "WebDAV 资源被锁定（423）"
        case .insufficientStorage: return "WebDAV 存储空间不足（507）"
        case .serverError(let status): return "WebDAV 服务端错误（HTTP \(status)）"
        case .unexpectedStatus(let status, let detail):
            return "WebDAV 返回 HTTP \(status)\(detail.isEmpty ? "" : "：\(detail)")"
        case .network(let detail): return "WebDAV 网络错误：\(detail)"
        case .invalidResponse(let detail): return "WebDAV 响应无效：\(detail)"
        case .parse(let detail): return "WebDAV XML 解析失败：\(detail)"
        }
    }
}

/// WebDAV 基础客户端。
///
/// - 配置目录 `directory` 会按 `/` 拆分逐段创建（MKCOL）；
/// - 备份文件名使用 `zhijian-*.zjbk`，列表按修改时间倒序；
/// - 所有请求带 Basic Auth；密码当前明文存 Application Support（UI 已提示）。
final class WebDAVClient: @unchecked Sendable {

    let config: WebDAVConfig
    private let session: URLSession

    init(config: WebDAVConfig, session: URLSession? = nil) {
        self.config = config
        if let session {
            self.session = session
        } else {
            let urlConfig = URLSessionConfiguration.default
            urlConfig.timeoutIntervalForRequest = 30
            urlConfig.timeoutIntervalForResource = 120
            urlConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: urlConfig)
        }
    }

    // MARK: 对外操作

    func checkConnection() async throws {
        let url = try directoryURL()
        do {
            _ = try await propfind(url: url, depth: 0)
        } catch WebDAVError.notFound {
            // 目录不存在但认证通过：只要 base URL 可访问即可
            _ = try await propfind(url: try baseURL(), depth: 0)
        }
    }

    func ensureDirectory() async throws {
        var url = try baseURL()
        for segment in directorySegments {
            url.appendPathComponent(segment)
            do {
                _ = try await propfind(url: url, depth: 0)
            } catch WebDAVError.notFound {
                var request = makeRequest(url: url, method: "MKCOL")
                request.setValue("0", forHTTPHeaderField: "Content-Length")
                let (data, response) = try await perform(request)
                switch response.statusCode {
                case 200, 201, 204:
                    continue
                case 405: // 已存在（部分服务器）
                    continue
                case 409:
                    throw WebDAVError.conflict(response.statusCode)
                default:
                    try ensureSuccess(response, data: data, url: url)
                }
            }
        }
    }

    func listBackups() async throws -> [RemoteBackupItem] {
        let url = try directoryURL()
        let items: [RemoteBackupItem]
        do {
            items = try await propfind(url: url, depth: 1)
        } catch WebDAVError.notFound {
            return []
        }
        let ownPath = normalizedPath(url)
        return items
            .filter { item in
                guard !item.isDirectory, !item.fileName.isEmpty else { return false }
                guard normalizedPathString(item.href) != ownPath else { return false }
                return item.fileName.lowercased().hasSuffix(".zjbk")
            }
            .sorted {
                if let lhs = $0.modifiedAt, let rhs = $1.modifiedAt, lhs != rhs { return lhs > rhs }
                return $0.fileName > $1.fileName
            }
    }

    /// 列出目录下的直接子项（Depth 1）。
    func listDirectoryContents(_ url: URL) async throws -> [RemoteBackupItem] {
        try await propfind(url: url, depth: 1)
    }

    /// 上传任意文件到相对路径（自动建目录）。
    @discardableResult
    func putFile(localURL: URL, remoteRelativePath: String, contentType: String = "application/octet-stream") async throws -> RemoteBackupItem {
        var base = try directoryURL()
        let segments = remoteRelativePath.split(separator: "/").map(String.init)
        for segment in segments.dropLast() {
            base.appendPathComponent(segment)
            do {
                _ = try await self.propfind(url: base, depth: 0)
            } catch WebDAVError.notFound {
                var request = makeRequest(url: base, method: "MKCOL")
                request.setValue("0", forHTTPHeaderField: "Content-Length")
                let (data, response) = try await perform(request)
                if ![200, 201, 204, 405].contains(response.statusCode) {
                    try ensureSuccess(response, data: data, url: base)
                }
            }
        }
        base.appendPathComponent(segments.last ?? localURL.lastPathComponent)
        let data = try Data(contentsOf: localURL)
        var request = makeRequest(url: base, method: "PUT")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        let (responseData, response) = try await session.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse("上传没有收到 HTTP 响应")
        }
        try ensureSuccess(http, data: responseData, url: base)
        return RemoteBackupItem(fileName: segments.last ?? localURL.lastPathComponent,
                                href: base.absoluteString, size: Int64(data.count),
                                modifiedAt: Date(), isDirectory: false)
    }

    func deleteRemoteFile(remoteRelativePath: String) async throws {
        var url = try directoryURL()
        for segment in remoteRelativePath.split(separator: "/").map(String.init) {
            url.appendPathComponent(segment)
        }
        let request = makeRequest(url: url, method: "DELETE")
        let (data, response) = try await perform(request)
        if response.statusCode == 404 { return }
        try ensureSuccess(response, data: data, url: url)
    }

    @discardableResult
    func upload(fileURL: URL, fileName: String? = nil) async throws -> RemoteBackupItem {
        try await ensureDirectory()
        let name = fileName ?? fileURL.lastPathComponent
        let data = try Data(contentsOf: fileURL)
        let url = try remoteFileURL(name)

        var request = makeRequest(url: url, method: "PUT")
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")

        let (responseData, response) = try await session.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse("上传没有收到 HTTP 响应")
        }
        try ensureSuccess(http, data: responseData, url: url)

        return RemoteBackupItem(
            fileName: name,
            href: url.absoluteString,
            size: Int64(data.count),
            modifiedAt: Date(),
            isDirectory: false
        )
    }

    @discardableResult
    func download(fileName: String, to destination: URL) async throws -> URL {
        let url = try remoteFileURL(fileName)
        let request = makeRequest(url: url, method: "GET")
        let (data, response) = try await perform(request)
        try ensureSuccess(response, data: data, url: url)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        return destination
    }

    func delete(fileName: String) async throws {
        let url = try remoteFileURL(fileName)
        let request = makeRequest(url: url, method: "DELETE")
        let (data, response) = try await perform(request)
        if response.statusCode == 404 { return }
        try ensureSuccess(response, data: data, url: url)
    }

    // MARK: URL

    private var directorySegments: [String] {
        config.directory
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func baseURL() throws -> URL {
        let raw = config.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw), url.scheme != nil else {
            throw WebDAVError.invalidURL(config.url)
        }
        return url
    }

    private func directoryURL() throws -> URL {
        var url = try baseURL()
        for segment in directorySegments {
            url.appendPathComponent(segment)
        }
        return url
    }

    private func remoteFileURL(_ fileName: String) throws -> URL {
        var url = try directoryURL()
        url.appendPathComponent(fileName)
        return url
    }

    private func normalizedPath(_ url: URL) -> String {
        normalizedPathString(url.absoluteString)
    }

    private func normalizedPathString(_ value: String) -> String {
        guard let components = URLComponents(string: value) else {
            return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        let path = (components.percentEncodedPath.removingPercentEncoding ?? components.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path
    }

    // MARK: 请求

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Zhijian/2.0 (iOS)", forHTTPHeaderField: "User-Agent")
        if !config.username.isEmpty {
            let credential = Data("\(config.username):\(config.password)".utf8).base64EncodedString()
            request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static let propfindBody = """
    <?xml version="1.0" encoding="utf-8" ?>
    <d:propfind xmlns:d="DAV:">
      <d:prop>
        <d:resourcetype/>
        <d:getcontentlength/>
        <d:getlastmodified/>
      </d:prop>
    </d:propfind>
    """

    private func propfind(url: URL, depth: Int) async throws -> [RemoteBackupItem] {
        var request = makeRequest(url: url, method: "PROPFIND")
        request.setValue(String(depth), forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.propfindBody.data(using: .utf8)

        let (data, response) = try await perform(request)
        if response.statusCode == 404 {
            throw WebDAVError.notFound(url.path)
        }
        try ensureSuccess(response, data: data, url: url)
        return try PropfindParser.parse(data, requestURL: url)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw WebDAVError.invalidResponse("不是 HTTP 响应")
            }
            return (data, http)
        } catch let error as WebDAVError {
            throw error
        } catch {
            throw WebDAVError.network(error.localizedDescription)
        }
    }

    private func ensureSuccess(_ response: HTTPURLResponse, data: Data, url: URL) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw WebDAVError.unauthorized
        case 404:
            throw WebDAVError.notFound(url.path)
        case 405:
            throw WebDAVError.methodNotAllowed(response.statusCode)
        case 409:
            throw WebDAVError.conflict(response.statusCode)
        case 423:
            throw WebDAVError.locked
        case 507:
            throw WebDAVError.insufficientStorage
        case 500..<600:
            throw WebDAVError.serverError(response.statusCode)
        default:
            let snippet = String(data: data.prefix(160), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw WebDAVError.unexpectedStatus(response.statusCode, snippet)
        }
    }
}

// MARK: - PROPFIND XML 解析

/// 解析 `<d:response>`：href / resourcetype(collection) / getcontentlength / getlastmodified。
private final class PropfindParser: NSObject, XMLParserDelegate {

    private struct RawItem {
        var href = ""
        var isDirectory = false
        var size: Int64?
        var modifiedAt: Date?
    }

    private var items: [RemoteBackupItem] = []
    private var current: RawItem?
    private var text = ""
    private var currentElement = ""
    private var requestURL: URL?

    static func parse(_ data: Data, requestURL: URL) throws -> [RemoteBackupItem] {
        let delegate = PropfindParser()
        delegate.requestURL = requestURL
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        guard parser.parse() else {
            throw WebDAVError.parse(parser.parserError?.localizedDescription ?? "未知错误")
        }
        return delegate.items
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        switch name {
        case "response":
            current = RawItem()
        case "href", "getcontentlength", "getlastmodified":
            text = ""
            currentElement = name
        case "collection":
            current?.isDirectory = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !currentElement.isEmpty else { return }
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        switch name {
        case "href":
            current?.href = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "getcontentlength":
            current?.size = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case "getlastmodified":
            current?.modifiedAt = Self.parseDate(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case "response":
            if let raw = current {
                finalize(raw)
            }
            current = nil
        default:
            break
        }
        if name == currentElement { currentElement = "" }
        text = ""
    }

    // MARK: 组装

    private func finalize(_ raw: RawItem) {
        guard !raw.href.isEmpty else { return }
        let decodedHref = raw.href.removingPercentEncoding ?? raw.href
        var fileName = ""
        if let url = URL(string: decodedHref), !url.lastPathComponent.isEmpty {
            fileName = url.lastPathComponent
        } else {
            fileName = (decodedHref as NSString).lastPathComponent
        }
        if fileName.isEmpty, raw.isDirectory { return }

        let isSelf: Bool = {
            guard let requestURL else { return false }
            let requestPath = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?
                .percentEncodedPath.removingPercentEncoding ?? requestURL.path
            let hrefPath = URLComponents(string: decodedHref)?.percentEncodedPath.removingPercentEncoding ?? decodedHref
            return requestPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                == hrefPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }()
        if isSelf && raw.isDirectory { return }

        items.append(RemoteBackupItem(
            fileName: fileName,
            href: raw.href,
            size: raw.size,
            modifiedAt: raw.modifiedAt,
            isDirectory: raw.isDirectory
        ))
    }

    private static func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let rfc1123 = DateFormatter()
        rfc1123.locale = Locale(identifier: "en_US_POSIX")
        rfc1123.timeZone = TimeZone(secondsFromGMT: 0)
        rfc1123.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = rfc1123.date(from: value) { return date }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: value)
    }
}
