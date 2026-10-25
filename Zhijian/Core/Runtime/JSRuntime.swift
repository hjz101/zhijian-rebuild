// JSRuntime.swift —— 每个书源一个 JavaScriptCore 沙箱，注入 Legado 白名单 API（java/source/cookie/cache/result…）
import Foundation
import JavaScriptCore
import CommonCrypto
import CryptoKit

/// 书源 JS 沙箱。
///
/// 设计要点（对齐 Legado JsExtensions）：
/// - 一个书源一个 `JSContext`，JS 只从本类的串行队列进入（JavaScriptCore 非线程安全）；
/// - `java.ajax` 等网络 API 是**同步语义**（URLSession + 信号量，单请求 15s 超时），
///   书源里的同步写法因此可以直接工作；
/// - 不导出文件/相册/原始 socket 等能力，缺失 API 统一映射成 `-10`；
/// - JS 异常映射成 `-9`。
final class JSRuntime: RuleJSEvaluating {

    // MARK: 存储属性

    let context: JSContext
    let http: HTTPClient
    let jar: CookieJar
    let source: BookSource
    private let queue = DispatchQueue(label: "zhijian.engine.js")
    private var bindings = RuleBindings()
    var cache: [String: String] = [:]
    private var sourceVariables: String = ""
    var loginInfo: [String: Any] = [:]
    /// 登录头（java.putLoginHeader 写入；下次请求由 SourcePipeline 合并）。
    var loginHeaders: [String: String] = [:]
    private var logLines: [String] = []
    /// 当前 JS 求值注入的规则解析器（只在 js 队列内存取）
    private var currentResolver: RuleResolver?
    /// JS 侧元素对象 ↔ HTMLNode 的映射：让 java.getElements 的结果能继续用于 @ 提取
    var elementTable: [String: HTMLNode] = [:]
    private var elementSequence: Int = 0
    let queueKey = DispatchSpecificKey<UInt8>()
    /// jsoup_bridge.js 使用的 DOM 句柄表
    let jsoupStore = JsoupDOMStore()
    /// 兼容层脚本是否成功注入（诊断用）
    var compatibilityLayerError: String?
    /// jsLib 共享脚本加载状态（诊断用）
    var jsLibStatus: String?

    /// 本源的默认 UA（与 Legado `getWebViewUA` 对齐）
    static let defaultUserAgent = HTTPClient.defaultUserAgent

    init(source: BookSource, http: HTTPClient, jar: CookieJar) {
        self.source = source
        self.http = http
        self.jar = jar
        self.context = JSContext(virtualMachine: JSVirtualMachine())
        queue.setSpecific(key: queueKey, value: 1)
        installAPIs()
        installJsLibIfNeeded()
        installExecutionTimeLimit(seconds: 12)
    }

    /// P0-10：执行书源的共享脚本 `jsLib`（远程 URL 或内联 JS），失败写入诊断。
    private func installJsLibIfNeeded() {
        guard let raw = source.jsLib?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
        var code = raw
        var loadedURL: String?
        if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") {
            let json = SharedJsLibCache.shared.load(url: raw)
            code = json ?? ""
            loadedURL = raw
        }
        if code.lowercased().hasPrefix("@js:") { code = String(code.dropFirst(4)) }
        if code.hasPrefix("<js>"), code.hasSuffix(">") { code = String(code.dropFirst(4).dropLast(4)) }
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            jsLibStatus = "jsLib 加载失败：\(loadedURL ?? "内联脚本为空")"
            appendLog("jsLib", jsLibStatus ?? "")
            return
        }
        context.exception = nil
        context.evaluateScript(code, withSourceURL: URL(fileURLWithPath: loadedURL ?? "jsLib.js"))
        if let exception = context.exception {
            let message = exception.toString() ?? "未知异常"
            context.exception = nil
            jsLibStatus = "jsLib 执行失败：\(message)"
            appendLog("jsLib", jsLibStatus ?? "")
        } else {
            jsLibStatus = loadedURL == nil ? "jsLib 已加载（内联）" : "jsLib 已加载（\(loadedURL!)）"
            appendLog("jsLib", jsLibStatus ?? "")
        }
    }

    // MARK: 对外求值

    /// 执行一段 JS 规则代码，返回最后一次表达式的值。
    func evaluateJS(_ code: String, bindings: RuleBindings) throws -> Any? {
        try evaluateJS(code, bindings: bindings, resolver: nil)
    }

    /// 执行 JS，并把「用当前解析上下文求值任意规则」的解析器注入给 java.getString 等 API。
    func evaluateJS(_ code: String, bindings: RuleBindings, resolver: RuleResolver?) throws -> Any? {
        try syncExecute {
            let previousResolver = currentResolver
            currentResolver = resolver
            defer { currentResolver = previousResolver }

            installBindings(bindings)
            context.exception = nil
            let value = context.evaluateScript(code)
            if let exception = context.exception {
                let message = exception.toString() ?? "JS 异常"
                let line = exception.objectForKeyedSubscript("line")?.toString() ?? ""
                let column = exception.objectForKeyedSubscript("column")?.toString() ?? ""
                context.exception = nil
                let location = line.isEmpty ? "" : "（line \(line)\(column.isEmpty ? "" : ", column \(column)")）"
                throw Self.mapJSError(message + location)
            }
            return fromJSValue(value)
        }
    }

    /// 同一队列上重入时直接执行，避免 `java.getString()` 里再跑 JS 造成 dispatch.sync 死锁
    func syncExecute<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try body()
        }
        return try queue.sync(execute: body)
    }

    /// 调试用日志（JS 内 `java.log` / `console.log`）
    var logs: [String] {
        syncExecute { logLines }
    }

    // MARK: 绑定注入

    func installBindings(_ newBindings: RuleBindings) {
        bindings = newBindings
        let ctx = context
        let resultValue = makeResultValue(newBindings.result)
        ctx.setObject(resultValue, forKeyedSubscript: "result" as NSString)
        ctx.setObject(JSValue(nullIn: ctx), forKeyedSubscript: "result2" as NSString)
        ctx.setObject(JSValue(object: newBindings.key, in: ctx), forKeyedSubscript: "key" as NSString)
        ctx.setObject(JSValue(double: Double(newBindings.page), in: ctx), forKeyedSubscript: "page" as NSString)
        ctx.setObject(JSValue(object: newBindings.baseURL, in: ctx), forKeyedSubscript: "baseUrl" as NSString)
        ctx.setObject(JSValue(object: newBindings.baseURL, in: ctx), forKeyedSubscript: "baseUrl2" as NSString)
        ctx.setObject(JSValue(object: newBindings.title, in: ctx), forKeyedSubscript: "title" as NSString)
        // Legado 的 JS 全局 `src` = 当前解析上下文的内容（页面/列表项），不是上一个规则结果
        ctx.setObject(makeResultValue(newBindings.content), forKeyedSubscript: "src" as NSString)
        ctx.setObject(toJS(newBindings.book), forKeyedSubscript: "book" as NSString)
        ctx.setObject(toJS(newBindings.chapter), forKeyedSubscript: "chapter" as NSString)
        if let chapter = newBindings.chapter as? [String: Any] {
            ctx.setObject(toJS(chapter["title"]), forKeyedSubscript: "chapterTitle" as NSString)
        }
    }

    // MARK: API 安装

    private func installAPIs() {
        let ctx = context

        // console.log 方便调试书源
        let console = JSValue(newObjectIn: ctx)!
        let consoleLog: @convention(block) (JSValue) -> Void = { [weak self] value in
            self?.appendLog("console.log", Self.stringArg(value))
        }
        console.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
        ctx.setObject(console, forKeyedSubscript: "console" as NSString)

        ctx.setObject(buildJava(), forKeyedSubscript: "java" as NSString)
        ctx.setObject(buildSource(), forKeyedSubscript: "source" as NSString)
        ctx.setObject(buildCookie(), forKeyedSubscript: "cookie" as NSString)
        ctx.setObject(buildCache(), forKeyedSubscript: "cache" as NSString)

        // 原生算法入口 + jsoup DOM 桥 + Rhino/Java 兼容层（packages_stub.js / jsoup_bridge.js）
        installNativeGlobals(ctx)
        installJsoupBridge(ctx)
        installCompatibilityScripts(ctx)
    }
    
    /// 从 Bundle 资源加载并执行兼容层脚本（进程内只读一次文件）
    private func installCompatibilityScripts(_ ctx: JSContext) {
        let scripts = ["packages_stub", "jsoup_bridge"]
        for name in scripts {
            guard let source = Self.compatibilityScriptSource(named: name) else {
                compatibilityLayerError = "缺少资源 \(name).js"
                appendLog("compat", "缺少 Bundle 资源 \(name).js")
                continue
            }
            ctx.exception = nil
            ctx.evaluateScript(source, withSourceURL: URL(fileURLWithPath: "\(name).js"))
            if let exception = ctx.exception {
                let message = exception.toString() ?? "未知异常"
                ctx.exception = nil
                compatibilityLayerError = "\(name).js 注入失败：\(message)"
                appendLog("compat", "\(name).js 注入失败：\(message)")
            } else {
                appendLog("compat", "\(name).js 已注入")
            }
        }
    }

    private static let compatibilitySourceCache = NSCache<NSString, NSString>()

    private static func compatibilityScriptSource(named name: String) -> String? {
        if let cached = compatibilitySourceCache.object(forKey: name as NSString) { return cached as String }
        let bundle = Bundle.main
        var url = bundle.url(forResource: name, withExtension: "js")
        if url == nil {
            url = bundle.bundleURL.appendingPathComponent("\(name).js")
            if let candidate = url, !FileManager.default.fileExists(atPath: candidate.path) { url = nil }
        }
        guard let url, let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        compatibilitySourceCache.setObject(source as NSString, forKey: name as NSString)
        return source
    }

    // MARK: java.*

    private func buildJava() -> JSValue {
        let ctx = context
        let java = JSValue(newObjectIn: ctx)!

        // java.ajax(url) -> String?（失败返回 null，与 Legado runCatching 语义一致）
        let ajax: @convention(block) (JSValue) -> JSValue = { [weak self] argument in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let url = Self.stringArg(argument)
            guard !url.isEmpty else { return JSValue(nullIn: self.context) }
            do {
                let response = try self.http.requestSync(url, timeout: 15)
                guard response.isOK else {
                    self.appendLog("java.ajax", "HTTP \(response.status) \(url)")
                    return JSValue(nullIn: self.context)
                }
                return JSValue(object: response.body, in: self.context)
            } catch {
                self.appendLog("java.ajax", "失败：\(error.localizedDescription) \(url)")
                return JSValue(nullIn: self.context)
            }
        }
        java.setObject(ajax, forKeyedSubscript: "ajax" as NSString)

        // java.get(url, headers) -> Response / java.get(key) -> 缓存
        let get: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] first, second in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let key = Self.stringArg(first)
            if key.hasPrefix("http://") || key.hasPrefix("https://") || key.hasPrefix("data:") {
                return self.makeResponseValue(url: key, method: "GET", headers: self.headerMap(from: second), body: nil)
            }
            return JSValue(object: self.cache[key] ?? "", in: self.context)
        }
        java.setObject(get, forKeyedSubscript: "get" as NSString)

        // java.post(url, body, headers) -> Response
        let post: @convention(block) (JSValue, JSValue, JSValue) -> JSValue = { [weak self] urlValue, bodyValue, headerValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let url = Self.stringArg(urlValue)
            let body = Self.stringArg(bodyValue)
            return self.makeResponseValue(url: url, method: "POST", headers: self.headerMap(from: headerValue), body: body)
        }
        java.setObject(post, forKeyedSubscript: "post" as NSString)

        let head: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] urlValue, headerValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return self.makeResponseValue(url: Self.stringArg(urlValue), method: "HEAD", headers: self.headerMap(from: headerValue), body: nil)
        }
        java.setObject(head, forKeyedSubscript: "head" as NSString)

        // 编解码
        let base64Encode: @convention(block) (JSValue) -> JSValue = { [weak self] value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let data = Self.stringArg(value).data(using: .utf8) ?? Data()
            return JSValue(object: data.base64EncodedString(), in: self.context)
        }
        java.setObject(base64Encode, forKeyedSubscript: "base64Encode" as NSString)

        let base64Decode: @convention(block) (JSValue) -> JSValue = { [weak self] value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let text = Self.stringArg(value)
            let data = Data(base64Encoded: text) ?? Data()
            return JSValue(object: String(data: data, encoding: .utf8) ?? "", in: self.context)
        }
        java.setObject(base64Decode, forKeyedSubscript: "base64Decode" as NSString)

        let md5: @convention(block) (JSValue) -> JSValue = { [weak self] value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let digest = Insecure.MD5.hash(data: Data(Self.stringArg(value).utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            return JSValue(object: hex, in: self.context)
        }
        java.setObject(md5, forKeyedSubscript: "md5Encode" as NSString)
        java.setObject(md5, forKeyedSubscript: "md5" as NSString)

        let hexEncode: @convention(block) (JSValue) -> JSValue = { [weak self] value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let hex = Self.stringArg(value).utf8.map { String(format: "%02x", $0) }.joined()
            return JSValue(object: hex, in: self.context)
        }
        java.setObject(hexEncode, forKeyedSubscript: "hexEncodeToString" as NSString)

        let hexDecode: @convention(block) (JSValue) -> JSValue = { [weak self] value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let hex = Self.stringArg(value).trimmingCharacters(in: .whitespacesAndNewlines)
            var bytes: [UInt8] = []
            var index = hex.startIndex
            while index < hex.endIndex {
                let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
                guard let byte = UInt8(hex[index..<next], radix: 16) else {
                    return self.raise("hexDecodeToString: 输入不是合法 hex")
                }
                bytes.append(byte)
                index = next
            }
            return JSValue(object: String(decoding: bytes, as: UTF8.self), in: self.context)
        }
        java.setObject(hexDecode, forKeyedSubscript: "hexDecodeToString" as NSString)

        // 时间格式化（时间戳按毫秒处理，与 Legado 一致）
        let timeFormat: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] timestamp, format in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let millis = timestamp.isUndefined || timestamp.isNull ? Date().timeIntervalSince1970 * 1000 : timestamp.toDouble()
            let pattern = format.isUndefined || format.isNull ? "yyyy/MM/dd HH:mm" : format.toString() ?? "yyyy/MM/dd HH:mm"
            return JSValue(object: Self.formatDate(Date(timeIntervalSince1970: millis / 1000), pattern: pattern), in: self.context)
        }
        java.setObject(timeFormat, forKeyedSubscript: "timeFormat" as NSString)

        // 日志
        let log: @convention(block) (JSValue) -> Void = { [weak self] value in
            self?.appendLog("java.log", Self.stringArg(value))
        }
        java.setObject(log, forKeyedSubscript: "log" as NSString)
        java.setObject(log, forKeyedSubscript: "toast" as NSString)
        java.setObject(log, forKeyedSubscript: "longToast" as NSString)

        // 缓存
        let put: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] key, value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            self.cache[Self.stringArg(key)] = JSONValueUtil.text(Self.any(from: value))
            return value
        }
        java.setObject(put, forKeyedSubscript: "put" as NSString)

        let delete: @convention(block) (JSValue) -> Void = { [weak self] key in
            self?.cache.removeValue(forKey: Self.stringArg(key))
        }
        java.setObject(delete, forKeyedSubscript: "delete" as NSString)

        // UA / cookie 桥
        let userAgent: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: Self.defaultUserAgent, in: self.context)
        }
        java.setObject(userAgent, forKeyedSubscript: "getWebViewUA" as NSString)

        let getCookie: @convention(block) (JSValue) -> JSValue = { [weak self] url in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: self.jar.header(for: Self.stringArg(url)), in: self.context)
        }
        java.setObject(getCookie, forKeyedSubscript: "getCookie" as NSString)

        let setCookie: @convention(block) (JSValue, JSValue) -> Void = { [weak self] url, cookie in
            guard let self else { return }
            self.jar.set(url: Self.stringArg(url), cookie: Self.stringArg(cookie))
        }
        java.setObject(setCookie, forKeyedSubscript: "setCookie" as NSString)

        // DOM 规则 API（对齐 Legado JsExtensions）：
        //   java.getString(rule[, content])、getStringList、getElement、getElements、getList
        let getString: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] rule, content in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let value = self.resolveJSRule(rule: rule, content: content, asList: false)
            return JSValue(object: self.ruleText(value), in: self.context)
        }
        java.setObject(getString, forKeyedSubscript: "getString" as NSString)

        let getStringList: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] rule, content in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let value = self.resolveJSRule(rule: rule, content: content, asList: true)
            return self.makeStringArray(self.ruleStringList(value))
        }
        java.setObject(getStringList, forKeyedSubscript: "getStringList" as NSString)

        let getElement: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] rule, content in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let value = self.resolveJSRule(rule: rule, content: content, asList: true)
            return self.makeFirstElement(value)
        }
        java.setObject(getElement, forKeyedSubscript: "getElement" as NSString)

        let getElements: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] rule, content in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let value = self.resolveJSRule(rule: rule, content: content, asList: true)
            return self.makeElementArray(self.elementNodes(value))
        }
        java.setObject(getElements, forKeyedSubscript: "getElements" as NSString)

        let getList: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] rule, content in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let value = self.resolveJSRule(rule: rule, content: content, asList: true)
            return self.makeListValue(value)
        }
        java.setObject(getList, forKeyedSubscript: "getList" as NSString)

        // AES 解密（Legado JsExtensions.aesBase64DecodeToString）
        let aesBase64Decode: @convention(block) (JSValue, JSValue, JSValue, JSValue) -> JSValue = { [weak self] dataValue, keyValue, transformationValue, ivValue in
            guard let self else { return JSValue(nullIn: JSContext.current()) }
            let base64 = Self.stringArg(dataValue)
            let key = Self.stringArg(keyValue)
            let transformation = Self.stringArg(transformationValue)
            let iv = Self.stringArg(ivValue)
            let text = Self.aesBase64DecodeToString(base64, key: key, transformation: transformation, iv: iv)
            return JSValue(object: text ?? "", in: self.context)
        }
        java.setObject(aesBase64Decode, forKeyedSubscript: "aesBase64DecodeToString" as NSString)

        // 明确不支持的私有能力：显式抛错，便于上层区分「缺 API」
        let unsupported: @convention(block) (JSValue) -> JSValue = { [weak self] value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return self.raise("UnsupportedApi: \(Self.stringArg(value)) 在 iOS 首版未实现")
        }
        java.setObject(unsupported, forKeyedSubscript: "startBrowser" as NSString)
        java.setObject(unsupported, forKeyedSubscript: "startBrowserAwait" as NSString)
        java.setObject(unsupported, forKeyedSubscript: "createSymmetricCrypto" as NSString)
        java.setObject(unsupported, forKeyedSubscript: "queryBase64TTF" as NSString)
        let javaGetLoginHeader: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: JSONValueUtil.jsonText(self.loginHeaders), in: self.context)
        }
        java.setObject(javaGetLoginHeader, forKeyedSubscript: "getLoginHeader" as NSString)

        let javaPutLoginHeader: @convention(block) (JSValue) -> Void = { [weak self] value in
            guard let self else { return }
            let any = Self.any(from: value)
            var headers: [String: String] = [:]
            if let dictionary = any as? [String: Any] {
                for (key, item) in dictionary { headers[key] = JSONValueUtil.text(item) }
            } else if let text = any as? String,
                      let parsed = LenientJSON.parse(text) as? [String: Any] {
                for (key, item) in parsed { headers[key] = JSONValueUtil.text(item) }
            }
            for (key, item) in headers { self.loginHeaders[key] = item }
        }
        java.setObject(javaPutLoginHeader, forKeyedSubscript: "putLoginHeader" as NSString)

        installJavaCompatMethods(on: java)

        return java
    }

    // MARK: source.*

    private func buildSource() -> JSValue {
        let ctx = context
        let object = JSValue(newObjectIn: ctx)!

        // 属性（大量书源直接用 source.bookSourceUrl / source.key / source.name）
        let properties: [String: String] = [
            "url": source.bookSourceUrl,
            "key": source.bookSourceUrl,
            "name": source.bookSourceName,
            "bookSourceUrl": source.bookSourceUrl,
            "bookSourceName": source.bookSourceName,
            "bookSourceGroup": source.bookSourceGroup ?? "",
            "bookSourceComment": source.bookSourceComment ?? "",
            "header": source.header?.textValue ?? "",
            "loginUrl": source.loginUrl ?? "",
            "jsLib": ""
        ]
        for (key, value) in properties {
            object.setObject(JSValue(object: value, in: ctx), forKeyedSubscript: key as NSString)
        }
        object.setObject(JSValue(int32: Int32(source.bookSourceType ?? 0), in: ctx), forKeyedSubscript: "bookSourceType" as NSString)
        object.setObject(JSValue(bool: source.enabledCookieJar ?? false, in: ctx), forKeyedSubscript: "enabledCookieJar" as NSString)
        object.setObject(JSValue(object: source.headerMap, in: ctx), forKeyedSubscript: "headerMap" as NSString)

        let get: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] urlValue, headerValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let url = Self.stringArg(urlValue)
            return JSValue(object: self.sourceRequest(url: url, method: "GET", body: nil, headers: self.headerMap(from: headerValue)), in: self.context)
        }
        object.setObject(get, forKeyedSubscript: "get" as NSString)

        let post: @convention(block) (JSValue, JSValue, JSValue) -> JSValue = { [weak self] urlValue, bodyValue, headerValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let url = Self.stringArg(urlValue)
            return JSValue(object: self.sourceRequest(url: url, method: "POST", body: Self.stringArg(bodyValue), headers: self.headerMap(from: headerValue)), in: self.context)
        }
        object.setObject(post, forKeyedSubscript: "post" as NSString)

        let put: @convention(block) (JSValue, JSValue, JSValue) -> JSValue = { [weak self] urlValue, bodyValue, headerValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let url = Self.stringArg(urlValue)
            return JSValue(object: self.sourceRequest(url: url, method: "PUT", body: Self.stringArg(bodyValue), headers: self.headerMap(from: headerValue)), in: self.context)
        }
        object.setObject(put, forKeyedSubscript: "put" as NSString)

        // 源变量（首次返回空串，与 Legado 一致）
        let getVariable: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: self.sourceVariables, in: self.context)
        }
        object.setObject(getVariable, forKeyedSubscript: "getVariable" as NSString)

        let setVariable: @convention(block) (JSValue) -> Void = { [weak self] value in
            guard let self else { return }
            let any = Self.any(from: value)
            if let text = any as? String {
                self.sourceVariables = text
            } else {
                self.sourceVariables = JSONValueUtil.jsonText(any)
            }
        }
        object.setObject(setVariable, forKeyedSubscript: "setVariable" as NSString)

        let getKey: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: self.source.bookSourceUrl, in: self.context)
        }
        object.setObject(getKey, forKeyedSubscript: "getKey" as NSString)

        let getName: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: self.source.bookSourceName, in: self.context)
        }
        object.setObject(getName, forKeyedSubscript: "getName" as NSString)

        let getUrl: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: self.source.bookSourceUrl, in: self.context)
        }
        object.setObject(getUrl, forKeyedSubscript: "getUrl" as NSString)

        let getTag: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: self.source.bookSourceGroup ?? "", in: self.context)
        }
        object.setObject(getTag, forKeyedSubscript: "getTag" as NSString)

        let getHeaderMap: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: self.source.headerMap, in: self.context)
        }
        object.setObject(getHeaderMap, forKeyedSubscript: "getHeaderMap" as NSString)

        let getLoginInfo: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: JSONValueUtil.jsonText(self.loginInfo), in: self.context)
        }
        object.setObject(getLoginInfo, forKeyedSubscript: "getLoginInfo" as NSString)

        let getLoginInfoMap: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: self.loginInfo, in: self.context)
        }
        object.setObject(getLoginInfoMap, forKeyedSubscript: "getLoginInfoMap" as NSString)

        let getLoginHeader: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: JSONValueUtil.jsonText(self.loginHeaders), in: self.context)
        }
        object.setObject(getLoginHeader, forKeyedSubscript: "getLoginHeader" as NSString)

        let putLoginHeader: @convention(block) (JSValue) -> Void = { [weak self] value in
            guard let self else { return }
            let any = Self.any(from: value)
            var headers: [String: String] = [:]
            if let dictionary = any as? [String: Any] {
                for (key, item) in dictionary { headers[key] = JSONValueUtil.text(item) }
            } else if let text = any as? String,
                      let parsed = LenientJSON.parse(text) as? [String: Any] {
                for (key, item) in parsed { headers[key] = JSONValueUtil.text(item) }
            }
            for (key, item) in headers { self.loginHeaders[key] = item }
        }
        object.setObject(putLoginHeader, forKeyedSubscript: "putLoginHeader" as NSString)

        let putLoginInfo: @convention(block) (JSValue) -> Void = { [weak self] value in
            guard let self else { return }
            let any = Self.any(from: value)
            if let dictionary = any as? [String: Any] {
                self.loginInfo = dictionary
            } else if let text = any as? String, let parsed = LenientJSON.parse(text) as? [String: Any] {
                self.loginInfo = parsed
            }
        }
        object.setObject(putLoginInfo, forKeyedSubscript: "putLoginInfo" as NSString)

        return object
    }

    // MARK: cookie.*

    private func buildCookie() -> JSValue {
        let ctx = context
        let object = JSValue(newObjectIn: ctx)!

        let getCookie: @convention(block) (JSValue) -> JSValue = { [weak self] url in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: self.jar.header(for: Self.stringArg(url)), in: self.context)
        }
        object.setObject(getCookie, forKeyedSubscript: "getCookie" as NSString)

        let setCookie: @convention(block) (JSValue, JSValue) -> Void = { [weak self] url, cookie in
            guard let self else { return }
            self.jar.set(url: Self.stringArg(url), cookie: Self.stringArg(cookie))
        }
        object.setObject(setCookie, forKeyedSubscript: "setCookie" as NSString)

        let removeCookie: @convention(block) (JSValue) -> Void = { [weak self] url in
            guard let self else { return }
            self.jar.remove(url: Self.stringArg(url))
        }
        object.setObject(removeCookie, forKeyedSubscript: "removeCookie" as NSString)

        let putCookie: @convention(block) (JSValue, JSValue) -> Void = { [weak self] url, key in
            guard let self else { return }
            let urlText = Self.stringArg(url)
            let keyText = Self.stringArg(key)
            let existing = self.jar.header(for: urlText)
            let value = existing.split(separator: ";").first { $0.contains("\(keyText)=") }?
                .split(separator: "=").dropFirst().joined(separator: "=") ?? ""
            self.jar.set(url: urlText, cookie: "\(keyText)=\(value)")
        }
        object.setObject(putCookie, forKeyedSubscript: "putCookie" as NSString)

        return object
    }

    // MARK: cache.*

    private func buildCache() -> JSValue {
        let ctx = context
        let object = JSValue(newObjectIn: ctx)!

        let put: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] key, value in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            self.cache[Self.stringArg(key)] = JSONValueUtil.text(Self.any(from: value))
            return value
        }
        object.setObject(put, forKeyedSubscript: "put" as NSString)

        let get: @convention(block) (JSValue) -> JSValue = { [weak self] key in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: self.cache[Self.stringArg(key)] ?? "", in: self.context)
        }
        object.setObject(get, forKeyedSubscript: "get" as NSString)

        let delete: @convention(block) (JSValue) -> Void = { [weak self] key in
            self?.cache.removeValue(forKey: Self.stringArg(key))
        }
        object.setObject(delete, forKeyedSubscript: "delete" as NSString)

        return object
    }

    // MARK: 请求辅助

    private func sourceRequest(url: String, method: String, body: String?, headers: [String: String]) -> String {
        guard !url.isEmpty else { return "" }
        do {
            let response = try http.requestSync(url, method: method, headers: headers, body: body, timeout: 15)
            guard response.isOK else {
                appendLog("source.\(method.lowercased())", "HTTP \(response.status) \(url)")
                return ""
            }
            return response.body
        } catch {
            appendLog("source.\(method.lowercased())", "失败：\(error.localizedDescription) \(url)")
            return ""
        }
    }

    /// 构造 Jsoup `Response` 的最小兼容对象：body()/text()/statusCode()/header()/headers()
    func makeResponseValue(url: String, method: String, headers: [String: String], body: String?) -> JSValue {
        let ctx = context
        do {
            let response = try http.requestSync(url, method: method, headers: headers, body: body, timeout: 15)
            let object = JSValue(newObjectIn: ctx)!
            object.setObject(JSValue(object: response.body, in: ctx), forKeyedSubscript: "bodyText" as NSString)
            object.setObject(JSValue(int32: Int32(response.status), in: ctx), forKeyedSubscript: "status" as NSString)

            let bodyFunction: @convention(block) () -> JSValue = { JSValue(object: response.body, in: ctx) }
            object.setObject(bodyFunction, forKeyedSubscript: "body" as NSString)
            object.setObject(bodyFunction, forKeyedSubscript: "text" as NSString)

            let statusFunction: @convention(block) () -> JSValue = { JSValue(int32: Int32(response.status), in: ctx) }
            object.setObject(statusFunction, forKeyedSubscript: "statusCode" as NSString)

            let headerFunction: @convention(block) (JSValue) -> JSValue = { name in
                JSValue(object: response.headers[Self.stringArg(name)] ?? "", in: ctx)
            }
            object.setObject(headerFunction, forKeyedSubscript: "header" as NSString)

            let headersFunction: @convention(block) () -> JSValue = { JSValue(object: response.headers, in: ctx) }
            object.setObject(headersFunction, forKeyedSubscript: "headers" as NSString)
            return object
        } catch {
            appendLog("java.\(method.lowercased())", "失败：\(error.localizedDescription) \(url)")
            return raise("\(method) 请求失败：\(error.localizedDescription)")
        }
    }

    func headerMap(from value: JSValue?) -> [String: String] {
        guard let value, value.isObject, let object = value.toObject() as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (key, element) in object { out[key] = JSONValueUtil.text(element) }
        return out
    }

    // MARK: JS DOM 规则 API

    /// 调用 RuleEngine 注入的解析器；未注入（例如纯 JS 调试）返回 nil
    private func resolveJSRule(rule: JSValue, content: JSValue?, asList: Bool) -> Any? {
        let ruleText = Self.stringArg(rule).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ruleText.isEmpty, let resolver = currentResolver else { return nil }
        return resolver(ruleText, contentInput(content), asList)
    }

    /// JS 传入的 content：元素对象取回真实节点，元素数组转节点数组，其余按 JS 值转换
    private func contentInput(_ value: JSValue?) -> Any? {
        guard let value, !value.isUndefined, !value.isNull else { return nil }
        if value.isString { return value.toString() }
        if value.isArray {
            let nodes = elementNodes(value)
            if !nodes.isEmpty { return nodes.map { $0 as Any } }
            return fromJSValue(value)
        }
        if value.isObject {
            if let node = elementNode(from: value) { return node }
            return fromJSValue(value)
        }
        return fromJSValue(value)
    }

    private func elementNode(from value: Any?) -> HTMLNode? {
        if let node = value as? HTMLNode { return node }
        if let dictionary = value as? [String: Any],
           let token = dictionary["__zhijian_node"] as? String {
            return elementTable[token]
        }
        if let js = value as? JSValue,
           let token = js.objectForKeyedSubscript("__zhijian_node")?.toString() {
            return elementTable[token]
        }
        return nil
    }

    private func elementNodes(_ value: Any?) -> [HTMLNode] {
        if let node = value as? HTMLNode { return [node] }
        if let js = value as? JSValue {
            if js.isArray, let items = js.toArray() {
                return items.compactMap { elementNode(from: $0) }
            }
            return elementNode(from: js).map { [$0] } ?? []
        }
        if let array = value as? [Any] {
            return array.compactMap { elementNode(from: $0) }
        }
        return elementNode(from: value).map { [$0] } ?? []
    }

    /// java.getString 用：元素优先返回 outerHtml（对齐 Legado Element 的字符串形态）
    private func ruleText(_ value: Any?) -> String {
        guard let value else { return "" }
        if let array = value as? [Any] {
            return array.map { item -> String in
                if let node = item as? HTMLNode { return node.html() }
                return JSONValueUtil.text(item)
            }.filter { !$0.isEmpty }.joined(separator: "\n")
        }
        if let node = value as? HTMLNode { return node.html() }
        return JSONValueUtil.text(value)
    }

    /// java.getStringList 用：元素转纯文本
    private func ruleStringList(_ value: Any?) -> [String] {
        guard let value else { return [] }
        if let array = value as? [Any] {
            return array.map { item -> String in
                if let node = item as? HTMLNode { return node.text() }
                return JSONValueUtil.text(item)
            }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        if let node = value as? HTMLNode {
            let text = node.text()
            return text.isEmpty ? [] : [text]
        }
        let text = JSONValueUtil.text(value)
        return text.isEmpty ? [] : [text]
    }

    // MARK: JS 值构造

    /// 元素对象：属性 `__zhijian_node` 保存句柄，方法兼容常用 Element API
    private func makeElementValue(_ node: HTMLNode) -> JSValue {
        let ctx = context
        let object = JSValue(newObjectIn: ctx)!
        let token = "zhn_\(elementSequence)"
        elementSequence += 1
        elementTable[token] = node
        if elementTable.count > 4000 {
            // 极端页面兜底：丢弃旧句柄（新句柄仍然有效）
            elementTable = [token: node]
        }
        object.setObject(JSValue(object: token, in: ctx), forKeyedSubscript: "__zhijian_node" as NSString)

        let html = node.html()
        let toString: @convention(block) () -> JSValue = { JSValue(object: html, in: ctx) }
        object.setObject(toString, forKeyedSubscript: "toString" as NSString)
        let valueOf: @convention(block) () -> JSValue = { JSValue(object: html, in: ctx) }
        object.setObject(valueOf, forKeyedSubscript: "valueOf" as NSString)

        let textFn: @convention(block) () -> JSValue = { JSValue(object: node.text(), in: ctx) }
        object.setObject(textFn, forKeyedSubscript: "text" as NSString)
        let ownTextFn: @convention(block) () -> JSValue = { JSValue(object: node.ownText(), in: ctx) }
        object.setObject(ownTextFn, forKeyedSubscript: "ownText" as NSString)
        let htmlFn: @convention(block) () -> JSValue = { JSValue(object: html, in: ctx) }
        object.setObject(htmlFn, forKeyedSubscript: "html" as NSString)
        let attrFn: @convention(block) (JSValue) -> JSValue = { name in
            JSValue(object: node.attribute(Self.stringArg(name)) ?? "", in: ctx)
        }
        object.setObject(attrFn, forKeyedSubscript: "attr" as NSString)
        let selectFn: @convention(block) (JSValue) -> JSValue = { [weak self] rule in
            guard let self else { return JSValue(undefinedIn: ctx) }
            let value = self.currentResolver?(Self.stringArg(rule), node, true)
            return self.makeElementArray(self.elementNodes(value))
        }
        object.setObject(selectFn, forKeyedSubscript: "select" as NSString)
        object.setObject(JSValue(object: node.tag, in: ctx), forKeyedSubscript: "tagName" as NSString)
        let toArray: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: ctx) }
            return self.makeElementArray([node])
        }
        object.setObject(toArray, forKeyedSubscript: "toArray" as NSString)
        let sizeOne: @convention(block) () -> JSValue = { JSValue(int32: 1, in: ctx) }
        object.setObject(sizeOne, forKeyedSubscript: "size" as NSString)
        let getZero: @convention(block) (JSValue) -> JSValue = { indexValue in
            Int(indexValue.toInt32()) == 0 ? object : JSValue(nullIn: ctx)
        }
        object.setObject(getZero, forKeyedSubscript: "get" as NSString)
        let firstSelf: @convention(block) () -> JSValue = { object }
        object.setObject(firstSelf, forKeyedSubscript: "first" as NSString)
        object.setObject(firstSelf, forKeyedSubscript: "last" as NSString)
        attachStringMethods(to: object, html: html)
        return object
    }

    /// 元素数组：额外暴露 `.size()` / `.get(i)`，兼容书源里的 Java List 写法
    private func makeElementArray(_ nodes: [HTMLNode]) -> JSValue {
        let ctx = context
        let array = JSValue(newArrayIn: ctx)!
        for (index, node) in nodes.enumerated() {
            array.setObject(makeElementValue(node), atIndexedSubscript: index)
        }
        let count = nodes.count
        let size: @convention(block) () -> JSValue = { JSValue(int32: Int32(count), in: ctx) }
        array.setObject(size, forKeyedSubscript: "size" as NSString)
        let get: @convention(block) (JSValue) -> JSValue = { [weak self] indexValue in
            let index = Int(indexValue.toInt32())
            guard let self, index >= 0, index < count else { return JSValue(nullIn: ctx) }
            return self.makeElementValue(nodes[index])
        }
        array.setObject(get, forKeyedSubscript: "get" as NSString)
        let toArray: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: ctx) }
            return self.makeElementArray(nodes)
        }
        array.setObject(toArray, forKeyedSubscript: "toArray" as NSString)
        let firstFn: @convention(block) () -> JSValue = { [weak self] in
            guard let self, let first = nodes.first else { return JSValue(nullIn: ctx) }
            return self.makeElementValue(first)
        }
        array.setObject(firstFn, forKeyedSubscript: "first" as NSString)
        let lastFn: @convention(block) () -> JSValue = { [weak self] in
            guard let self, let last = nodes.last else { return JSValue(nullIn: ctx) }
            return self.makeElementValue(last)
        }
        array.setObject(lastFn, forKeyedSubscript: "last" as NSString)
        let textAll: @convention(block) () -> JSValue = {
            JSValue(object: nodes.map { $0.text() }.joined(separator: "\n"), in: ctx)
        }
        array.setObject(textAll, forKeyedSubscript: "text" as NSString)
        let htmlAll: @convention(block) () -> JSValue = {
            JSValue(object: nodes.map { $0.html() }.joined(separator: "\n"), in: ctx)
        }
        array.setObject(htmlAll, forKeyedSubscript: "html" as NSString)
        let selectAll: @convention(block) (JSValue) -> JSValue = { [weak self] rule in
            guard let self else { return JSValue(undefinedIn: ctx) }
            var collected: [HTMLNode] = []
            let ruleText = Self.stringArg(rule)
            for node in nodes {
                if let value = self.currentResolver?(ruleText, node, true) {
                    collected.append(contentsOf: self.elementNodes(value))
                }
            }
            return self.makeElementArray(collected)
        }
        array.setObject(selectAll, forKeyedSubscript: "select" as NSString)
        return array
    }

    /// 全局 result：HTML 节点/节点数组/HTML 字符串转为可 `toArray()` 的元素对象；JSON/纯文本保持原样
    private func makeResultValue(_ value: Any?) -> JSValue {
        if let node = value as? HTMLNode { return makeElementValue(node) }
        if let array = value as? [Any] {
            let nodes = elementNodes(array)
            if !nodes.isEmpty { return makeElementArray(nodes) }
        }
        if let text = value as? String, text.contains("<"), text.count > 20 {
            let root = HTMLDocument.parse(text).root
            return makeElementValue(root)
        }
        return toJS(value)
    }

    /// 给元素对象补上常用 String 方法：书源里常见 `result.match(...)`、`result.split(...)` 与 `result.toArray()` 混用
    private func attachStringMethods(to object: JSValue, html: String) {
        let ctx = context
        object.setObject(JSValue(int32: Int32(html.count), in: ctx), forKeyedSubscript: "length" as NSString)
        let match: @convention(block) (JSValue) -> JSValue = { pattern in
            guard let text = JSValue(object: html, in: ctx) else { return JSValue(nullIn: ctx) }
            return text.invokeMethod("match", withArguments: [pattern]) ?? JSValue(nullIn: ctx)
        }
        object.setObject(match, forKeyedSubscript: "match" as NSString)
        let split: @convention(block) (JSValue) -> JSValue = { separator in
            guard let text = JSValue(object: html, in: ctx) else { return JSValue(nullIn: ctx) }
            return text.invokeMethod("split", withArguments: [separator]) ?? JSValue(nullIn: ctx)
        }
        object.setObject(split, forKeyedSubscript: "split" as NSString)
        let replace: @convention(block) (JSValue, JSValue) -> JSValue = { a, b in
            guard let text = JSValue(object: html, in: ctx) else { return JSValue(object: html, in: ctx) }
            return text.invokeMethod("replace", withArguments: [a, b]) ?? JSValue(object: html, in: ctx)
        }
        object.setObject(replace, forKeyedSubscript: "replace" as NSString)
        let includes: @convention(block) (JSValue) -> JSValue = { needle in
            JSValue(bool: html.contains(Self.stringArg(needle)), in: ctx)
        }
        object.setObject(includes, forKeyedSubscript: "includes" as NSString)
        let indexOf: @convention(block) (JSValue) -> JSValue = { needle in
            let target = Self.stringArg(needle)
            if let range = html.range(of: target) {
                return JSValue(int32: Int32(html.distance(from: html.startIndex, to: range.lowerBound)), in: ctx)
            }
            return JSValue(int32: -1, in: ctx)
        }
        object.setObject(indexOf, forKeyedSubscript: "indexOf" as NSString)
        let slice: @convention(block) (JSValue, JSValue) -> JSValue = { a, b in
            guard let text = JSValue(object: html, in: ctx) else { return JSValue(object: html, in: ctx) }
            return text.invokeMethod("slice", withArguments: [a, b]) ?? JSValue(object: html, in: ctx)
        }
        object.setObject(slice, forKeyedSubscript: "slice" as NSString)
        let substring: @convention(block) (JSValue, JSValue) -> JSValue = { a, b in
            guard let text = JSValue(object: html, in: ctx) else { return JSValue(object: html, in: ctx) }
            return text.invokeMethod("substring", withArguments: [a, b]) ?? JSValue(object: html, in: ctx)
        }
        object.setObject(substring, forKeyedSubscript: "substring" as NSString)
        let trim: @convention(block) () -> JSValue = {
            JSValue(object: html.trimmingCharacters(in: .whitespacesAndNewlines), in: ctx)
        }
        object.setObject(trim, forKeyedSubscript: "trim" as NSString)
        let toLower: @convention(block) () -> JSValue = { JSValue(object: html.lowercased(), in: ctx) }
        object.setObject(toLower, forKeyedSubscript: "toLowerCase" as NSString)
        let toUpper: @convention(block) () -> JSValue = { JSValue(object: html.uppercased(), in: ctx) }
        object.setObject(toUpper, forKeyedSubscript: "toUpperCase" as NSString)
    }

    private func makeStringArray(_ values: [String]) -> JSValue {
        let ctx = context
        let array = JSValue(newArrayIn: ctx)!
        for (index, value) in values.enumerated() {
            array.setObject(JSValue(object: value, in: ctx), atIndexedSubscript: index)
        }
        let count = values.count
        let size: @convention(block) () -> JSValue = { JSValue(int32: Int32(count), in: ctx) }
        array.setObject(size, forKeyedSubscript: "size" as NSString)
        let get: @convention(block) (JSValue) -> JSValue = { indexValue in
            let index = Int(indexValue.toInt32())
            guard index >= 0, index < count else { return JSValue(nullIn: ctx) }
            return JSValue(object: values[index], in: ctx)
        }
        array.setObject(get, forKeyedSubscript: "get" as NSString)
        return array
    }

    private func makeFirstElement(_ value: Any?) -> JSValue {
        let nodes = elementNodes(value)
        if let first = nodes.first { return makeElementValue(first) }
        // 属性/字符串结果：把首项当 HTML 片段再取元素
        if let array = value as? [Any], let first = array.first {
            if let text = first as? String, let node = HTMLDocument.parse(text).root.elementChildren.first {
                return makeElementValue(node)
            }
        }
        return JSValue(nullIn: context)
    }

    /// java.getList：JSON 数组原样转 JS（对象/数组/字符串），元素节点转元素对象
    private func makeListValue(_ value: Any?) -> JSValue {
        let ctx = context
        let array = JSValue(newArrayIn: ctx)!
        let items: [Any]
        if let list = value as? [Any] {
            items = list
        } else if let value {
            items = [value]
        } else {
            items = []
        }
        for (index, item) in items.enumerated() {
            if let node = item as? HTMLNode {
                array.setObject(makeElementValue(node), atIndexedSubscript: index)
            } else {
                array.setObject(toJS(item), atIndexedSubscript: index)
            }
        }
        let count = items.count
        let size: @convention(block) () -> JSValue = { JSValue(int32: Int32(count), in: ctx) }
        array.setObject(size, forKeyedSubscript: "size" as NSString)
        let get: @convention(block) (JSValue) -> JSValue = { indexValue in
            let index = Int(indexValue.toInt32())
            guard index >= 0, index < count else { return JSValue(nullIn: ctx) }
            return array.objectAtIndexedSubscript(index)
        }
        array.setObject(get, forKeyedSubscript: "get" as NSString)
        return array
    }

    // MARK: 值转换

    func toJS(_ value: Any?) -> JSValue {
        let ctx = context
        guard let value else { return JSValue(nullIn: ctx) }
        switch value {
        case is NSNull:
            return JSValue(nullIn: ctx)
        case let bool as Bool:
            return JSValue(bool: bool, in: ctx)
        case let int as Int:
            return JSValue(double: Double(int), in: ctx)
        case let double as Double:
            return JSValue(double: double, in: ctx)
        case let string as String:
            return JSValue(object: string, in: ctx)
        case let array as [Any]:
            let jsArray = JSValue(newArrayIn: ctx)!
            for (index, element) in array.enumerated() {
                jsArray.setObject(toJS(element), atIndexedSubscript: index)
            }
            return jsArray
        case let dictionary as [String: Any]:
            let jsObject = JSValue(newObjectIn: ctx)!
            for (key, element) in dictionary {
                jsObject.setObject(toJS(element), forKeyedSubscript: key as NSString)
            }
            return jsObject
        default:
            return JSValue(object: value, in: ctx)
        }
    }

    private func fromJSValue(_ value: JSValue?) -> Any? {
        guard let value else { return nil }
        if value.isUndefined || value.isNull { return nil }
        if value.isBoolean { return value.toBool() }
        if value.isString { return value.toString() ?? "" }
        if value.isNumber { return Double(value.toNumber()?.doubleValue ?? value.toDouble()) }
        if value.isArray {
            let nodes = elementNodes(value)
            if !nodes.isEmpty { return nodes.map { $0 as Any } }
            if let array = value.toArray() { return JSONValueUtil.normalize(array) }
        }
        if value.isObject {
            if let node = elementNode(from: value) { return node }
            if let dictionary = value.toDictionary() { return JSONValueUtil.normalize(dictionary) }
        }
        return value.toString()
    }

    /// JSValue → Swift Any（用于缓存/源变量）
    static func any(from value: JSValue?) -> Any {
        guard let value else { return "" }
        if value.isUndefined || value.isNull { return "" }
        if value.isBoolean { return value.toBool() }
        if value.isString { return value.toString() ?? "" }
        if value.isNumber { return Double(value.toNumber()?.doubleValue ?? value.toDouble()) }
        if value.isArray, let array = value.toArray() {
            return JSONValueUtil.normalize(array)
        }
        if value.isObject, let dictionary = value.toDictionary() {
            return JSONValueUtil.normalize(dictionary)
        }
        return value.toString() ?? ""
    }

    /// AES/CBC/PKCS5Padding base64 解密（key/iv 按 UTF-8 字节；transformation 只用于识别模式）
    static func aesBase64DecodeToString(_ base64: String, key: String, transformation: String, iv: String) -> String? {
        guard let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) else { return nil }
        let keyBytes = Array(key.utf8)
        let ivBytes = Array(iv.utf8)
        let mode = transformation.lowercased()
        guard mode.contains("aes") else { return nil }
        if mode.contains("ecb") {
            return aesCrypt(data, key: keyBytes, iv: nil)
        }
        guard ivBytes.count == kCCBlockSizeAES128 else { return nil }
        return aesCrypt(data, key: keyBytes, iv: ivBytes)
    }

    private static func aesCrypt(_ data: Data, key: [UInt8], iv: [UInt8]?) -> String? {
        guard [16, 24, 32].contains(key.count) else { return nil }
        var out = Data(count: data.count + kCCBlockSizeAES128)
        let outputCapacity = out.count
        var outLength = 0
        let options = CCOptions(kCCOptionPKCS7Padding)
        let status: CCCryptorStatus = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { inPtr in
                let ivPtr = iv?.withUnsafeBytes { $0.baseAddress } ?? nil
                return CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), options,
                               key, key.count, ivPtr,
                               inPtr.baseAddress, data.count,
                               outPtr.baseAddress, outputCapacity, &outLength)
            }
        }
        guard status == kCCSuccess else { return nil }
        out.removeSubrange(outLength..<out.count)
        return String(data: out, encoding: .utf8)
    }

    static func stringArg(_ value: JSValue?) -> String {
        guard let value, !value.isUndefined, !value.isNull else { return "" }
        if value.isString { return value.toString() ?? "" }
        if value.isNumber { return JSONValueUtil.text(value.toNumber()) }
        if value.isBoolean { return value.toBool() ? "true" : "false" }
        if value.isObject, let object = value.toDictionary() {
            return JSONValueUtil.jsonText(object)
        }
        return value.toString() ?? ""
    }

    // MARK: 异常

    private func raise(_ message: String) -> JSValue {
        context.exception = JSValue(newErrorFromMessage: message, in: context)
        return JSValue(undefinedIn: context)
    }

    func appendLog(_ tag: String, _ message: String) {
        let line = "[\(tag)] \(message)"
        if logLines.count > 200 { logLines.removeFirst(50) }
        logLines.append(line)
        #if DEBUG
        print("[JS] \(line)")
        #endif
    }

    static func mapJSError(_ message: String) -> Error {
        let lowered = message.lowercased()
        let missingMarkers = [
            "unsupportedapi",
            "is not a function",
            "is not an object",
            "can't find variable",
            "undefined is not",
            "referenceerror: can't find"
        ]
        if missingMarkers.contains(where: { lowered.contains($0) }) {
            return SourceEngineError.missingAPI(message)
        }
        return SourceEngineError.jsError(message)
    }

    // MARK: 日期格式化

    /// Java 风格 pattern（yyyy/MM/dd HH:mm:ss）→ 字符串
    static func formatDate(_ date: Date, pattern: String, timeZoneOffsetHours: Int = 0) -> String {
        var calendar = Calendar(identifier: .gregorian)
        if timeZoneOffsetHours != 0 {
            calendar.timeZone = TimeZone(secondsFromGMT: timeZoneOffsetHours * 3600) ?? TimeZone(secondsFromGMT: 0)!
        }
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = String(format: "%04d", components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 0)
        let day = String(format: "%02d", components.day ?? 0)
        let hour = String(format: "%02d", components.hour ?? 0)
        let minute = String(format: "%02d", components.minute ?? 0)
        let second = String(format: "%02d", components.second ?? 0)
        return pattern
            .replacingOccurrences(of: "yyyy", with: year)
            .replacingOccurrences(of: "MM", with: month)
            .replacingOccurrences(of: "dd", with: day)
            .replacingOccurrences(of: "HH", with: hour)
            .replacingOccurrences(of: "mm", with: minute)
            .replacingOccurrences(of: "ss", with: second)
    }
}
