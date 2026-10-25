// RuleEngine.swift —— Legado 规则求值：裸规则/JSONPath、{{}}、##替换##、@put/@get、&& || %%、$0、URL 模板与 URL,{json} 选项
import Foundation

// MARK: - 错误

enum RuleEngineError: LocalizedError {
    /// 规则语法错误（映射到 -8）
    case syntax(String)
    /// 首版不支持的能力（CSS/XPath 等，映射到 -8）
    case unsupported(String)
    /// URL 规则拼接失败
    case emptyURL(String)

    var errorDescription: String? {
        switch self {
        case .syntax(let message): return message
        case .unsupported(let message): return message
        case .emptyURL(let message): return message
        }
    }
}

// MARK: - 上下文与变量

/// 规则内变量表（`@put:{k:rule}` / `@get:{k}`），按书源会话共享。
final class RuleVariableStore {
    private var storage: [String: Any] = [:]

    subscript(key: String) -> Any? {
        get { storage[key] }
        set { storage[key] = newValue }
    }

    func set(_ key: String, _ value: Any?) {
        storage[key] = value
    }

    func text(_ key: String) -> String {
        JSONValueUtil.text(storage[key])
    }
}

/// 一次规则求值所需的上下文（对应 Node 参考实现的 Analyzer ctx）。
struct RuleContext {
    var result: Any = ""
    var key: String = ""
    var page: Int = 1
    var baseURL: String = ""
    var source: BookSource?
    var book: Any?
    var chapter: Any?
    /// 网络层可注入响应 Content-Type；未注入时按正文嗅探（首字符 `{`/`[` → JSON，否则 HTML）
    var contentType: String?

    init(result: Any = "", key: String = "", page: Int = 1, baseURL: String = "",
         source: BookSource? = nil, book: Any? = nil, chapter: Any? = nil,
         contentType: String? = nil) {
        self.result = result
        self.key = key
        self.page = page
        self.baseURL = baseURL
        self.source = source
        self.book = book
        self.chapter = chapter
        self.contentType = contentType
    }
}

/// 传给 JS 沙箱的绑定快照（`result`/`key`/`page`/`baseUrl`/`book`/`chapter`…）。
struct RuleBindings {
    var result: Any = ""
    var key: String = ""
    var page: Int = 1
    var baseURL: String = ""
    var title: String = ""
    var book: Any?
    var chapter: Any?
    var sourceName: String = ""
    /// 当前解析上下文的内容（页面/列表项的原始值），对应 Legado JS 全局 `src`
    var content: Any = ""
}

/// JS 内部 `java.getString/getStringList/getElement/getElements/getList` 的求值回调：
/// `(规则串, 内容/上下文, 是否要列表)`。内容为 nil 时用当前 `context.result`（页面 / 列表项）。
typealias RuleResolver = (_ rule: String, _ input: Any?, _ asList: Bool) -> Any?

/// JS 规则执行器：由 JSRuntime 实现，规则引擎只依赖这个协议。
protocol RuleJSEvaluating: AnyObject {
    func evaluateJS(_ code: String, bindings: RuleBindings) throws -> Any?
    /// 带规则解析器执行 JS（Legado JS DOM API 需要）
    func evaluateJS(_ code: String, bindings: RuleBindings, resolver: RuleResolver?) throws -> Any?
}

extension RuleJSEvaluating {
    /// 默认实现：不支持解析器的沙箱降级为普通求值
    func evaluateJS(_ code: String, bindings: RuleBindings, resolver: RuleResolver?) throws -> Any? {
        try evaluateJS(code, bindings: bindings)
    }
}

// MARK: - 顶层切分

/// 按连接符切分规则串，尊重引号、`[]`、`()`、`{}`、`{{}}` 与 `<js>` 段。
///
/// 之所以不用正则：Legado 的规则里 `&&` 可能出现在 JSONPath 过滤表达式的字符串内。
enum RuleSplitter {

    struct Result {
        var parts: [String]
        var separators: [String]
    }

    static func split(_ input: String, separators: [String]) -> Result {
        let chars = Array(input)
        var parts: [String] = []
        var separatorsFound: [String] = []
        var current = ""
        var depthSquare = 0
        var depthParen = 0
        var depthCurly = 0
        var quote: Character?
        var inJS = false
        var mustacheDepth = 0
        var index = 0

        while index < chars.count {
            let char = chars[index]

            if inJS {
                current.append(char)
                if matches(chars, at: index, "</js>") {
                    current.append(contentsOf: chars[(index + 1)..<(index + 5)])
                    index += 5
                    inJS = false
                    continue
                }
                index += 1
                continue
            }

            if matches(chars, at: index, "<js>") {
                inJS = true
                current += "<js>"
                index += 4
                continue
            }

            if let activeQuote = quote {
                current.append(char)
                if char == activeQuote, index == 0 || chars[index - 1] != "\\" {
                    quote = nil
                }
                index += 1
                continue
            }

            if char == "\"" || char == "'" {
                quote = char
                current.append(char)
                index += 1
                continue
            }

            if matches(chars, at: index, "{{") {
                mustacheDepth += 1
                current += "{{"
                index += 2
                continue
            }
            if matches(chars, at: index, "}}"), mustacheDepth > 0 {
                mustacheDepth -= 1
                current += "}}"
                index += 2
                continue
            }
            if mustacheDepth > 0 {
                current.append(char)
                index += 1
                continue
            }

            switch char {
            case "[": depthSquare += 1
            case "]": depthSquare = max(0, depthSquare - 1)
            case "(": depthParen += 1
            case ")": depthParen = max(0, depthParen - 1)
            case "{": depthCurly += 1
            case "}": depthCurly = max(0, depthCurly - 1)
            default: break
            }

            if depthSquare == 0, depthParen == 0, depthCurly == 0 {
                if let separator = separators.first(where: { matches(chars, at: index, $0) }) {
                    parts.append(current)
                    current = ""
                    index += separator.count
                    separatorsFound.append(separator)
                    continue
                }
            }

            current.append(char)
            index += 1
        }

        parts.append(current)
        return Result(parts: parts, separators: separatorsFound)
    }

    static func matches(_ chars: [Character], at index: Int, _ target: String) -> Bool {
        let targetChars = Array(target)
        guard index + targetChars.count <= chars.count else { return false }
        for offset in 0..<targetChars.count where chars[index + offset] != targetChars[offset] {
            return false
        }
        return true
    }
}

// MARK: - 规则分析器

/// Legado 规则求值核心（对齐 AnalyzeRule / AnalyzeByJSonPath / AnalyzeByRegex 的语义）。
final class RuleAnalyzer {

    enum Mode {
        case `default`
        case json
        case regex
        case literal
        /// CSS 选择器（Legado 默认规则在 HTML 内容上的分支）
        case html
        /// XPath 子集
        case xpath
    }

    private enum Segment {
        case text(String)
        case js(String)
    }

    var context: RuleContext
    let vars: RuleVariableStore
    private let js: RuleJSEvaluating?
    /// @webjs: 求值器：(html, baseURL, js) -> 结果
    private let webView: ((String, String, String) -> Any?)?

    private static let jsPattern = try! NSRegularExpression(
        pattern: "<js>([\\s\\S]*?)</js>|@js:([\\s\\S]*)",
        options: [.caseInsensitive]
    )
    private static let mustachePattern = try! NSRegularExpression(pattern: "\\{\\{([\\s\\S]*?)\\}\\}")
    private static let putPattern = try! NSRegularExpression(pattern: "@put:(\\{[^}]+?\\})", options: [.caseInsensitive])
    /// Legado 变量读取：`@get:{key}`（可嵌在规则串里）
    private static let getPattern = try! NSRegularExpression(pattern: "@get:\\{([^}]+)\\}", options: [.caseInsensitive])
    /// 整条规则就是 `@get:key` / `@get:{key}` 时直接取变量（阅读文档的裸 key 写法）
    private static let getOnlyPattern = try! NSRegularExpression(
        pattern: "^\\s*@get:\\s*\\{?([^}\\s]+)\\}?\\s*$",
        options: [.caseInsensitive]
    )
    private static let listIndexPattern = try! NSRegularExpression(pattern: "\\$(\\d{1,2})")
    private static let webJSPattern = try! NSRegularExpression(
        pattern: "^\\s*@webjs:\\s*([\\s\\S]*)$", options: [.caseInsensitive]
    )

    static func webJSScript(_ rule: String) -> String? {
        let ns = rule as NSString
        guard let match = webJSPattern.firstMatch(in: rule, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        let script = ns.substring(with: match.range(at: 1))
        return script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : script
    }

    init(context: RuleContext, vars: RuleVariableStore, js: RuleJSEvaluating?,
         webView: ((String, String, String) -> Any?)? = nil) {
        self.context = context
        self.vars = vars
        self.js = js
        self.webView = webView
    }

    // MARK: 对外入口

    /// 规则求值（可含 `<js>` 段）。`asList` 为 true 时总是返回数组。
    func analyze(_ rule: String?, input: Any? = nil, asList: Bool = false) throws -> Any {
        guard let rule, !rule.isEmpty else { return asList ? [] : "" }
        let current = input ?? context.result
        if let webScript = Self.webJSScript(rule) {
            guard let webView else {
                throw RuleEngineError.syntax("@webjs: 规则需要 WebView，但当前执行环境未启用")
            }
            let html = JSONValueUtil.text(current)
            let value = webView(html, context.baseURL, webScript) ?? ""
            if asList { return toList(value) }
            return value is NSNull ? "" : value
        }
        try ensureNoWebJSRule(rule)
        let segments = splitJSSegments(rule)
        var value: Any = current

        for segment in segments {
            switch segment {
            case .js(let code):
                value = try evaluateJS(code, result: value) ?? ""
            case .text(let text):
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    value = try analyzeText(text, input: value, asList: asList)
                }
            }
        }

        if asList { return toList(value) }
        return value is NSNull ? "" : value
    }

    /// 列表规则：处理首字符 `-`（反转）/ `+`（仅去标记）。
    func analyzeList(_ rule: String, input: Any?) throws -> [Any] {
        let (stripped, reversed) = ListedRule.normalize(rule)
        var list = toList(try analyze(stripped, input: input, asList: true))
        if reversed { list.reverse() }
        return list
    }

    // MARK: 文本段

    private func analyzeText(_ text: String, input: Any, asList: Bool) throws -> Any {
        let parsed = try putRules(text, input: input)
        let rule = parsed.trimmingCharacters(in: .whitespacesAndNewlines)
        if rule.isEmpty { return input }
        if let key = Self.getOnlyKey(rule) { return vars[key] ?? "" }

        // HTML 内容：`&&` / `%%` 是「各段独立求值再合并」，不是把结果继续套规则
        // （对齐 Legado AnalyzeByJSoup.getStringList / getElements 的行为）
        if HTMLContentDetector.kind(of: input, contentType: context.contentType) == .html {
            return try analyzeHTMLText(rule, input: input, asList: asList)
        }

        let split = RuleSplitter.split(rule, separators: ["&&", "||", "%%"])
        if split.parts.count == 1 {
            return try applyOne(split.parts[0], input: input, asList: asList)
        }

        let mode = split.separators.first ?? "&&"
        if mode == "||" {
            for part in split.parts where !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let result = try applyOne(part, input: input, asList: asList)
                if !isEmptyValue(result) { return result }
            }
            return asList ? [] : ""
        }
        if mode == "%%" {
            let lists = try split.parts
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { toList(try applyOne($0, input: input, asList: true)) }
            var merged: [Any] = []
            let maxCount = lists.map(\.count).max() ?? 0
            for index in 0..<maxCount {
                for list in lists where index < list.count {
                    merged.append(list[index])
                }
            }
            return merged
        }

        // && 串联
        var value: Any = input
        for part in split.parts where !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value = try applyOne(part, input: value, asList: asList)
        }
        return value
    }

    /// 单条规则（已无 && || %%，已处理过 @put）
    private func applyOne(_ ruleRaw: String, input: Any, asList: Bool) throws -> Any {
        let rawRule = ruleRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hadMustache = Self.mustachePattern.firstMatch(
            in: rawRule,
            range: NSRange(rawRule.startIndex..<rawRule.endIndex, in: rawRule)
        ) != nil

        var rule = try makeUp(rawRule, current: input)
        if rule.isEmpty { return input }

        // ##正则##替换## —— 第 3 个 ## 表示只替换首个匹配
        let hashParts = rule.components(separatedBy: "##")
        rule = hashParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let replaceRegex = hashParts.count > 1 ? hashParts[1] : ""
        let replacement = hashParts.count > 2 ? hashParts[2] : ""
        let replaceFirstOnly = hashParts.count > 3

        var mode: Mode = .default
        var body = rule
        if hadMustache { mode = .literal }

        let lowered = body.lowercased()
        if lowered.hasPrefix("@css:") {
            // @css：强制按 CSS 处理（正文不像 HTML 时也解析一次）
            mode = .html
            body = String(body.dropFirst(5))
        } else if body.hasPrefix("@@") {
            // @@：默认规则，交给下面的内容嗅探决定 CSS / JSONPath
            body = String(body.dropFirst(2))
        } else if lowered.hasPrefix("@xpath:") {
            mode = .xpath
            body = String(body.dropFirst(7))
        } else if lowered.hasPrefix("@json:") {
            mode = .json
            body = String(body.dropFirst(6))
        } else if body.hasPrefix("$.") || body.hasPrefix("$[") {
            mode = .json
        } else if body.hasPrefix(":") {
            mode = .regex
            body = String(body.dropFirst())
        }

        if mode == .default, !hadMustache {
            // 内容嗅探：JSON 首字符 `{` / `[`（且能解析）或 Content-Type: json → JSONPath；
            // 其余（含纯文本，Legado 会 Jsoup.parse 包装）→ HTML
            switch HTMLContentDetector.kind(of: input, contentType: context.contentType) {
            case .json:
                mode = .json
            case .html, .other:
                // 首字符 `/` 是 XPath 的省略写法（Legado SourceRule 语义）
                mode = body.hasPrefix("/") ? .xpath : .html
            }
        }

        // 引号包裹的字面量（如 `|| '未知'` 的兜底分支）按字面值返回
        if let literal = Self.quotedLiteral(body) {
            mode = .literal
            body = literal
        }

        var result: Any
        switch mode {
        case .literal:
            result = body

        case .json:
            result = try evaluateJSON(body, input: input, asList: asList)

        case .regex:
            let matches = try regexExtract(JSONValueUtil.text(input), rule: body)
            result = asList ? matches : matches.joined(separator: "\n")

        case .html:
            result = try evaluateHTML(body, input: input, asList: asList)

        case .xpath:
            result = try evaluateXPath(body, input: input, asList: asList)

        case .default:
            if let dictionary = input as? [String: Any], !body.contains(" ") {
                // 非 HTML 输入下的裸字段名（Legado 默认规则在 JSON 内容上仍可能落到这里）
                result = dictionary[body] ?? ""
            } else {
                result = try evaluateHTML(body, input: input, asList: asList)
            }
        }

        if !replaceRegex.isEmpty {
            if let array = result as? [Any] {
                result = array.map {
                    applyReplace(JSONValueUtil.text($0), pattern: replaceRegex, template: replacement, firstOnly: replaceFirstOnly)
                }
            } else {
                result = applyReplace(JSONValueUtil.text(result), pattern: replaceRegex, template: replacement, firstOnly: replaceFirstOnly)
            }
        }
        return result
    }

    private func evaluateJSON(_ body: String, input: Any, asList: Bool) throws -> Any {
        let rule = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let values: [Any]

        if input is [String: Any] || input is [Any] {
            if rule.hasPrefix("$") {
                values = JSONPath.evaluate(input, rule)
            } else {
                values = barePathValues(input, path: rule)
            }
        } else if let string = input as? String,
                  let parsed = JSONValueUtil.parseJSON(string) {
            let expression = rule.hasPrefix("$") ? rule : "$." + rule
            values = JSONPath.evaluate(parsed, expression)
        } else {
            values = []
        }

        if values.isEmpty { return asList ? [] : "" }
        // 命中多个时整体返回数组：与 Node 参考实现一致，asList 的“拍平”交给 toList 处理
        return values.count == 1 ? values[0] : values
    }

    /// 裸字段规则（`data` / `data.name`）在 JSON 对象上的取值
    private func barePathValues(_ input: Any, path: String) -> [Any] {
        var current: Any? = input
        for part in path.split(separator: ".") {
            guard let value = current else { return [] }
            guard let dictionary = value as? [String: Any] else { return [] }
            current = dictionary[String(part)]
        }
        guard let value = current else { return [] }
        return [value]
    }

    // MARK: - HTML / XPath 求值

    /// HTML 内容上的 `&&` / `||` / `%%`（Legado AnalyzeByJSoup 语义）：
    /// 每一段都**独立**对原始内容求值，再按连接符合并，而不是把上一段结果继续套规则。
    private func analyzeHTMLText(_ rule: String, input: Any, asList: Bool) throws -> Any {
        let split = RuleSplitter.split(rule, separators: ["&&", "||", "%%"])
        let parts = split.parts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if parts.count <= 1 {
            return try applyOne(rule, input: input, asList: asList)
        }
        let separator = split.separators.first ?? "&&"

        if separator == "||" {
            for part in parts {
                let result = try applyOne(part, input: input, asList: asList)
                if !isEmptyValue(result) { return result }
            }
            return asList ? [] : ""
        }

        if separator == "%%" {
            // 字符串规则的多值结果是 "\n" 拼接的，这里再拆回列表才能正确交错
            let lists = try parts.map { part -> [Any] in
                let value = try applyOne(part, input: input, asList: asList)
                if asList { return toList(value) }
                if let node = value as? HTMLNode { return [node] }
                if let array = value as? [Any] { return array }
                return JSONValueUtil.text(value)
                    .components(separatedBy: "\n")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
            var merged: [Any] = []
            let maxCount = lists.map(\.count).max() ?? 0
            for index in 0..<maxCount {
                for list in lists where index < list.count { merged.append(list[index]) }
            }
            return asList ? merged : joinedText(merged)
        }

        // `&&`：元素结果合并成节点列表，文本结果换行拼接
        var values: [Any] = []
        for part in parts {
            values.append(contentsOf: toList(try applyOne(part, input: input, asList: asList)))
        }
        if asList { return values }
        if values.allSatisfy({ $0 is HTMLNode }) {
            if values.isEmpty { return "" }
            return values.count == 1 ? values[0] : values
        }
        return joinedText(values)
    }

    /// CSS 规则求值：`asList` 为 true 时走「元素列表」语义（bookList / chapterList），
    /// 否则最后一段是字段 / 属性（text / html / ownText / textNodes / all / attr）。
    private func evaluateHTML(_ ruleBody: String, input: Any, asList: Bool) throws -> Any {
        let rule = ruleBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let contexts = htmlContexts(from: input)
        guard !contexts.isEmpty else { return asList ? [] : "" }
        if rule.isEmpty { return asList ? [] : joinedText(contexts.map { $0 as Any }) }

        let segments = Self.splitHTMLChain(rule)
        guard !segments.isEmpty else { return asList ? [] : "" }

        if asList {
            var nodes = contexts
            for segment in segments {
                nodes = selectHTMLNodes(segment, in: nodes)
                if nodes.isEmpty { return [] }
            }
            return nodes.map { $0 as Any }
        }

        let lastSegment = segments[segments.count - 1]
        var nodes = contexts
        if segments.count > 1 {
            for index in 0..<(segments.count - 1) {
                nodes = selectHTMLNodes(segments[index], in: nodes)
                if nodes.isEmpty { return "" }
            }
        }
        return extractHTMLValue(lastSegment, from: nodes)
    }

    private func evaluateXPath(_ body: String, input: Any, asList: Bool) throws -> Any {
        let expression = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else { return asList ? [] : "" }
        let contexts = htmlContexts(from: input)
        guard !contexts.isEmpty else { return asList ? [] : "" }

        let values = XPathQuery.evaluate(expression, in: contexts)
        if values.isEmpty { return asList ? [] : "" }
        if asList { return values }
        if values.count == 1 { return values[0] }
        return joinedText(values)
    }

    /// 把任意输入转成 HTML 上下文节点
    private func htmlContexts(from input: Any) -> [HTMLNode] {
        if let node = input as? HTMLNode { return [node] }
        if let array = input as? [Any] {
            let nodes = array.compactMap { $0 as? HTMLNode }
            if !nodes.isEmpty { return nodes }
            let strings = array.compactMap { $0 as? String }.filter { !$0.isEmpty }
            if !strings.isEmpty, strings.count <= 32 {
                return strings.map { HTMLDocument.parse($0).root }
            }
            return []
        }
        if let string = input as? String {
            guard !string.isEmpty else { return [] }
            return [HTMLDocument.parse(string).root]
        }
        return []
    }

    /// 按 Legado 默认规则取元素：`class.` / `tag.` / `id.` / `text.` / `children` 前缀 + 索引后缀
    private func selectHTMLNodes(_ segmentRaw: String, in contexts: [HTMLNode]) -> [HTMLNode] {
        let segment = segmentRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segment.isEmpty else { return contexts }
        var results: [HTMLNode] = []
        var seen = Set<ObjectIdentifier>()
        for context in contexts {
            for node in CSSSelector.selectLegado(segment, in: context) {
                if seen.insert(ObjectIdentifier(node)).inserted { results.append(node) }
            }
        }
        return results
    }

    /// 最后一段：字段 → 属性名 → 选择器（单元素返回节点，便于 `init` 规则拿到子树）
    private func extractHTMLValue(_ segmentRaw: String, from nodes: [HTMLNode]) -> Any {
        let segment = segmentRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segment.isEmpty else { return joinedText(nodes.map { $0 as Any }) }

        if let values = htmlFieldValues(segment, nodes: nodes) {
            return values.isEmpty ? "" : values.joined(separator: "\n")
        }
        if let values = htmlAttributeValues(segment, nodes: nodes) {
            return values.isEmpty ? "" : values.joined(separator: "\n")
        }

        let selected = selectHTMLNodes(segment, in: nodes)
        if selected.isEmpty { return "" }
        if selected.count == 1 { return selected[0] }
        return selected.map { $0 as Any }
    }

    /// `@text` / `@html` / `@ownText` / `@textNodes` / `@all`
    private func htmlFieldValues(_ token: String, nodes: [HTMLNode]) -> [String]? {
        switch token.lowercased() {
        case "text":
            return nodes.map { $0.text() }.filter { !$0.isEmpty }
        case "owntext":
            return nodes.map { $0.ownText() }.filter { !$0.isEmpty }
        case "textnodes":
            var out: [String] = []
            for node in nodes {
                let lines = node.textNodes()
                if !lines.isEmpty { out.append(lines.joined(separator: "\n")) }
            }
            return out
        case "html":
            let html = nodes.map { $0.htmlRemovingScriptAndStyle() }.filter { !$0.isEmpty }
            return html.isEmpty ? [] : [html.joined(separator: "\n")]
        case "all":
            let html = nodes.map { $0.html() }.filter { !$0.isEmpty }
            return html.isEmpty ? [] : [html.joined(separator: "\n")]
        default:
            return nil
        }
    }

    /// `@href` / `@src` / `@data-original`：属性名形状且确实存在才返回，否则当选择器
    private func htmlAttributeValues(_ token: String, nodes: [HTMLNode]) -> [String]? {
        guard token.range(of: "^[A-Za-z_:][A-Za-z0-9_:.\\-]*$", options: .regularExpression) != nil else {
            return nil
        }
        let name = token.lowercased()
        var present = false
        var values: [String] = []
        for node in nodes {
            guard let value = node.attribute(name) else { continue }
            present = true
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !values.contains(trimmed) { values.append(trimmed) }
        }
        return present ? values : nil
    }

    private func joinedText(_ values: [Any]) -> String {
        var lines: [String] = []
        for value in values {
            if let node = value as? HTMLNode {
                let text = node.text()
                if !text.isEmpty { lines.append(text) }
            } else {
                let text = JSONValueUtil.text(value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { lines.append(text) }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 按 `@` 切分提取链，尊重引号与 `[]` / `()`（属性选择器里可能带 `@`）
    static func splitHTMLChain(_ rule: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var square = 0
        var paren = 0
        var quote: Character?
        for character in rule {
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
                continue
            }
            switch character {
            case "[":
                square += 1
            case "]":
                square = max(0, square - 1)
            case "(":
                paren += 1
            case ")":
                paren = max(0, paren - 1)
            case "@" where square == 0 && paren == 0:
                parts.append(current)
                current = ""
                continue
            default:
                break
            }
            current.append(character)
        }
        parts.append(current)
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: 规则预展开

    /// `{{...}}` / `@get:` / `$N` 替换
    private func makeUp(_ rule: String, current: Any) throws -> String {
        var output = rule
        // @put 在 putRules 阶段已执行，这里清掉残留标记
        output = Self.putPattern.stringByReplacingMatches(
            in: output,
            range: NSRange(output.startIndex..<output.endIndex, in: output),
            withTemplate: ""
        )
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        output = replaceGetRules(output)
        output = try replaceMustaches(output, current: current)

        if let array = current as? [Any] {
            output = replaceListIndexes(output, current: array)
        }
        return output
    }

    private func replaceListIndexes(_ text: String, current: [Any]) -> String {
        var output = text
        let matches = Self.listIndexPattern.matches(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output))
        for match in matches.reversed() {
            guard let full = Range(match.range, in: output),
                  let group = Range(match.range(at: 1), in: output),
                  let index = Int(output[group]) else { continue }
            let value = index < current.count ? JSONValueUtil.text(current[index]) : ""
            output.replaceSubrange(full, with: value)
        }
        return output
    }

    private func replaceMustaches(_ rule: String, current: Any) throws -> String {
        let matches = Self.mustachePattern.matches(in: rule, range: NSRange(rule.startIndex..<rule.endIndex, in: rule))
        guard !matches.isEmpty else { return rule }
        var output = rule
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: output),
                  let innerRange = Range(match.range(at: 1), in: output) else { continue }
            let expression = String(output[innerRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = try evaluateMustache(expression, current: current)
            output.replaceSubrange(fullRange, with: replacement)
        }
        return output
    }

    private func evaluateMustache(_ expression: String, current: Any) throws -> String {
        if expression.hasPrefix("@get:") {
            var key = String(expression.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            if key.hasPrefix("{") && key.hasSuffix("}") { key = String(key.dropFirst().dropLast()) }
            return vars.text(key)
        }
        if isSubRule(expression) {
            let value = try analyze(expression, input: current, asList: false)
            return JSONValueUtil.text(value)
        }
        // 快速路径：这几个绑定不需要进 JS 沙箱
        switch expression {
        case "key": return context.key
        case "page": return String(context.page)
        case "baseUrl": return context.baseURL
        case "title": return JSONValueUtil.text((context.chapter as? [String: Any])?["title"])
        default: break
        }
        guard js != nil else { return "" }
        let value = try evaluateJS(expression, result: current)
        return JSONValueUtil.text(value)
    }

    private func isSubRule(_ expression: String) -> Bool {
        expression.hasPrefix("@") || expression.hasPrefix("$.") || expression.hasPrefix("$[")
            || expression.hasPrefix("//") || expression.hasPrefix("#")
    }

    /// 传进 JS 沙箱前把 HTML 节点折成 html 字符串（列表项内部 JS 也能拿到 `html`）
    static func jsFriendly(_ value: Any) -> Any {
        // 保留 HTMLNode，交给 JSRuntime 包装成带 toArray()/select() 的元素对象（Legado Elements 语义）。
        // JS 里当字符串用时，包装对象的 toString()/valueOf() 会返回 outerHtml，所以不会破坏 `String(result)`。
        if value is HTMLNode { return value }
        if let array = value as? [Any] { return array.map { jsFriendly($0) } }
        return value
    }

    // MARK: @put

    private func putRules(_ text: String, input: Any) throws -> String {
        var output = text
        let matches = Self.putPattern.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
        for match in matches {
            guard let range = Range(match.range, in: text),
                  let jsonRange = Range(match.range(at: 1), in: text) else { continue }
            let jsonText = String(text[jsonRange])
            let entries = Self.parsePutBlock(jsonText)
            guard !entries.isEmpty else {
                throw RuleEngineError.syntax("@put 解析失败：\(jsonText)")
            }
            for (key, value) in entries {
                vars.set(key, try analyze(value, input: input, asList: false))
            }
            output = output.replacingOccurrences(of: text[range], with: "")
        }
        return output
    }

    /// 解析 `@put:{k:rule}`：优先按合法 JSON（值必须带引号）解析，
    /// 失败再按 Legado 书源常见写法 `{k:rule}` 逐项切分（值可以不带引号）。
    private static func parsePutBlock(_ text: String) -> [String: String] {
        if let dictionary = LenientJSON.parse(text) as? [String: Any], !dictionary.isEmpty {
            var out: [String: String] = [:]
            for (key, value) in dictionary { out[key] = JSONValueUtil.text(value) }
            return out
        }
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("{") { body.removeFirst() }
        if body.hasSuffix("}") { body.removeLast() }
        var out: [String: String] = [:]
        for part in RuleSplitter.split(body, separators: [","]).parts {
            guard let colon = part.firstIndex(of: ":") else { continue }
            let key = part[..<colon].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            var value = part[part.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2, let first = value.first, let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty else { continue }
            out[key] = value
        }
        return out
    }

    // MARK: @get / @webjs

    /// 整条规则是 @get 时返回变量名
    private static func getOnlyKey(_ rule: String) -> String? {
        let nsRule = rule as NSString
        guard let match = getOnlyPattern.firstMatch(in: rule, range: NSRange(location: 0, length: nsRule.length)),
              match.numberOfRanges > 1 else { return nil }
        let key = nsRule.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    /// 规则串里嵌的 `@get:{key}`（Legado evalPattern 支持在任意文本片段中插值）
    private func replaceGetRules(_ text: String) -> String {
        guard text.contains("@get:") || text.lowercased().contains("@get:") else { return text }
        var output = text
        let matches = Self.getPattern.matches(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output))
        for match in matches.reversed() {
            guard let full = Range(match.range, in: output),
                  let keyRange = Range(match.range(at: 1), in: output) else { continue }
            let key = String(output[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            output.replaceSubrange(full, with: vars.text(key))
        }
        return output
    }

    /// `@webjs:` 需要 WKWebView 执行页面脚本；首版不启用时给出明确诊断，而不是静默返回空。
    private func ensureNoWebJSRule(_ rule: String) throws {
        for segment in splitJSSegments(rule) {
            if case .text(let text) = segment,
               text.range(of: "@webjs:", options: .caseInsensitive) != nil {
                throw RuleEngineError.unsupported(
                    "@webjs: 规则需要 WebView 执行页面脚本，iOS 首版未启用（请改用 @js:/@css:/@xpath:；规则：\(String(text.prefix(80))))"
                )
            }
        }
    }

    // MARK: 正则提取

    private func regexExtract(_ text: String, rule: String) throws -> [String] {
        let parts = RuleSplitter.split(rule, separators: ["&&"]).parts
        var results: [String] = []
        for part in parts {
            var pattern = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if parts.count == 1, pattern.hasPrefix(":") { pattern.removeFirst() }
            guard !pattern.isEmpty else { continue }
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                throw RuleEngineError.syntax("正则非法：\(pattern)")
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                if match.numberOfRanges > 1, let group = Range(match.range(at: 1), in: text) {
                    results.append(String(text[group]))
                } else if let whole = Range(match.range(at: 0), in: text) {
                    results.append(String(text[whole]))
                }
            }
        }
        return results
    }

    private func applyReplace(_ text: String, pattern: String, template: String, firstOnly: Bool) -> String {
        guard !pattern.isEmpty, let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let safeTemplate = Self.sanitizedTemplate(template)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if firstOnly, let match = regex.firstMatch(in: text, range: range),
           let matchRange = Range(match.range, in: text) {
            let replacement = regex.replacementString(for: match, in: text, offset: 0, template: safeTemplate)
            return String(text[..<matchRange.lowerBound]) + replacement + String(text[matchRange.upperBound...])
        }
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: safeTemplate)
    }

    /// 判断整条规则是否是引号包裹的字面量，返回去掉引号后的值
    private static func quotedLiteral(_ text: String) -> String? {
        guard text.count >= 2, let first = text.first, let last = text.last else { return nil }
        guard (first == "'" && last == "'") || (first == "\"" && last == "\"") else { return nil }
        let inner = text.dropFirst().dropLast()
        guard !inner.contains(first), !inner.contains("\n") else { return nil }
        return String(inner)
    }

    /// NSRegularExpression 的模板里非法 `$` 会抛异常，这里把非 `$数字` 的 `$` 转义掉。
    private static func sanitizedTemplate(_ template: String) -> String {
        var output = ""
        var index = template.startIndex
        while index < template.endIndex {
            let char = template[index]
            if char == "$" {
                let next = template.index(after: index)
                if next < template.endIndex, template[next].isNumber {
                    output.append(char)
                } else {
                    output.append("\\$")
                }
            } else {
                output.append(char)
            }
            index = template.index(after: index)
        }
        return output
    }

    // MARK: JS 段

    private func splitJSSegments(_ rule: String) -> [Segment] {
        let matches = Self.jsPattern.matches(in: rule, range: NSRange(rule.startIndex..<rule.endIndex, in: rule))
        guard !matches.isEmpty else { return [.text(rule)] }
        var segments: [Segment] = []
        var cursor = rule.startIndex
        for match in matches {
            guard let range = Range(match.range, in: rule) else { continue }
            if range.lowerBound > cursor {
                segments.append(.text(String(rule[cursor..<range.lowerBound])))
            }
            let code: String
            if let jsRange = Range(match.range(at: 1), in: rule) {
                code = String(rule[jsRange])
            } else if let jsRange = Range(match.range(at: 2), in: rule) {
                code = String(rule[jsRange])
            } else {
                code = ""
            }
            segments.append(.js(code))
            cursor = range.upperBound
        }
        if cursor < rule.endIndex {
            segments.append(.text(String(rule[cursor...])))
        }
        return segments
    }

    private func evaluateJS(_ code: String, result: Any) throws -> Any? {
        guard let js else { throw RuleEngineError.unsupported("规则包含 JS，但当前没有可用的 JS 沙箱") }
        let resolver: RuleResolver = { [weak self] rule, input, asList in
            self?.resolveRuleForJS(rule, input: input, asList: asList)
        }
        return try js.evaluateJS(code, bindings: makeBindings(result: result), resolver: resolver)
    }

    /// JS DOM API 的规则求值入口（`java.getString(rule[, content])` 等）。
    ///
    /// - 不传 content 时对 `context.result` 求值（与 Legado AnalyzeRule.content 一致：
    ///   搜索阶段是整页、列表项规则是当前 li）；
    /// - `asList == true` 时 HTML 规则按「字段 → 属性 → 元素选择器」返回**数组**，
    ///   而不是字符串 API 的换行拼接结果；
    /// - JSON 规则直接走 JSONPath 列表求值。
    func resolveRuleForJS(_ rule: String, input: Any?, asList: Bool) -> Any? {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return asList ? [] : "" }
        let target = input ?? context.result
        if asList, HTMLContentDetector.kind(of: target, contentType: context.contentType) == .html {
            return htmlResolveList(trimmed, input: target)
        }
        return try? analyze(trimmed, input: target, asList: asList)
    }

    /// HTML 规则的列表求值（供 `java.getStringList` / `java.getElements` / `java.getList` 使用）
    private func htmlResolveList(_ rule: String, input: Any) -> [Any] {
        var text = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        if lowered.hasPrefix("@css:") {
            text = String(text.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lowered.hasPrefix("@xpath:") {
            text = String(text.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else { return [] }
        let contexts = htmlContexts(from: input)
        guard !contexts.isEmpty else { return [] }

        // XPath 规则（`//li`、`//a/@href`）直接走 XPath 求值
        if text.hasPrefix("/") {
            return XPathQuery.evaluate(text, in: contexts)
        }

        // `&&` / `||` / `%%` 与 Legado 一致：各段独立求值再合并
        let split = RuleSplitter.split(text, separators: ["&&", "||", "%%"])
        let parts = split.parts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if parts.count > 1 {
            let separator = split.separators.first ?? "&&"
            var lists: [[Any]] = []
            for part in parts {
                let values = htmlResolveList(part, input: input)
                if separator == "||", !values.isEmpty { return values }
                lists.append(values)
            }
            if separator == "%%" {
                var merged: [Any] = []
                let maxCount = lists.map(\.count).max() ?? 0
                for index in 0..<maxCount {
                    for list in lists where index < list.count { merged.append(list[index]) }
                }
                return merged
            }
            return lists.flatMap { $0 }
        }

        let segments = Self.splitHTMLChain(text)
        guard !segments.isEmpty else { return [] }

        var nodes = contexts
        if segments.count > 1 {
            for index in 0..<(segments.count - 1) {
                nodes = selectHTMLNodes(segments[index], in: nodes)
                if nodes.isEmpty { return [] }
            }
        }
        let last = segments[segments.count - 1]
        if let values = htmlFieldValues(last, nodes: nodes) { return values.map { $0 as Any } }
        if let values = htmlAttributeValues(last, nodes: nodes) { return values.map { $0 as Any } }
        return selectHTMLNodes(last, in: nodes).map { $0 as Any }
    }

    func makeBindings(result: Any) -> RuleBindings {
        RuleBindings(
            result: Self.jsFriendly(result),
            key: context.key,
            page: context.page,
            baseURL: context.baseURL,
            title: JSONValueUtil.text((context.chapter as? [String: Any])?["title"]),
            book: context.book,
            chapter: context.chapter,
            sourceName: context.source?.bookSourceName ?? "",
            content: Self.jsFriendly(context.result)
        )
    }

    // MARK: URL 模板

    /// URL 规则求值：先跑 `<js>` 段，再替换 `{{}}`，返回“未解析相对路径”的原始 URL 串。
    func expandURLTemplate(_ raw: String) throws -> String {
        try ensureNoWebJSRule(raw)
        let hasJS = Self.jsPattern.firstMatch(in: raw, range: NSRange(raw.startIndex..<raw.endIndex, in: raw)) != nil
        let hasMustache = Self.mustachePattern.firstMatch(in: raw, range: NSRange(raw.startIndex..<raw.endIndex, in: raw)) != nil
        guard hasJS || hasMustache else { return raw }

        var output = ""
        var usedJS = false
        for segment in splitJSSegments(raw) {
            switch segment {
            case .js(let code):
                usedJS = true
                let value = try evaluateJS(code, result: output.isEmpty ? context.result : output)
                output = JSONValueUtil.text(value)
            case .text(let text):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                output = output.isEmpty ? text.replacingOccurrences(of: "@result", with: output) : output
            }
        }
        if output.isEmpty {
            if usedJS {
                throw RuleEngineError.emptyURL("URL 规则里的 JS 返回空串，无法构成 URL")
            }
            output = raw
        }
        output = try replaceMustaches(output, current: context.result)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: 结果工具

    private func toList(_ value: Any) -> [Any] {
        if value is NSNull { return [] }
        if let array = value as? [Any] { return array }
        if let string = value as? String {
            if let parsed = JSONValueUtil.parseJSON(string), JSONValueUtil.looksLikeJSON(string) {
                return (parsed as? [Any]) ?? [parsed]
            }
            return string.isEmpty ? [] : [string]
        }
        return [value]
    }

    private func isEmptyValue(_ value: Any) -> Bool {
        if let array = value as? [Any] { return array.isEmpty }
        if value is NSNull { return true }
        return JSONValueUtil.text(value).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - 内容类型嗅探

enum HTMLContentKind {
    case json
    case html
    case other
}

/// 判定一条规则该走 JSONPath 还是 CSS / XPath。
///
/// 对齐 Legado `AnalyzeRule.setContent`：`isJSON` 看正文是否 `{...}` / `[...]`（能解析）；
/// 其余一律当 HTML（Jsoup.parse 会把纯文本包成 html/body，规则仍能取到文本）。
/// `Content-Type` 只在可用时作为辅助信号（网络层可把它注入 `RuleContext.contentType`）。
enum HTMLContentDetector {

    static func kind(of value: Any?, contentType: String? = nil) -> HTMLContentKind {
        guard let value else { return .other }

        if value is HTMLNode { return .html }
        if let array = value as? [Any] {
            if array.contains(where: { $0 is HTMLNode }) { return .html }
            return array.isEmpty ? .other : .json
        }
        if value is [String: Any] { return .json }

        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return .other }
            if looksLikeJSONText(trimmed) { return .json }
            if let contentType = contentType?.lowercased() {
                if contentType.contains("json") { return .json }
                if contentType.contains("html") || contentType.contains("xml") { return .html }
            }
            return .html
        }

        if let contentType = contentType?.lowercased() {
            if contentType.contains("json") { return .json }
            if contentType.contains("html") || contentType.contains("xml") { return .html }
        }
        return .other
    }

    static func looksLikeJSONText(_ text: String) -> Bool {
        guard let first = text.first, let last = text.last else { return false }
        guard (first == "{" && last == "}") || (first == "[" && last == "]") else { return false }
        return JSONValueUtil.parseJSON(text) != nil
    }
}

/// 首版遗留的 HTML 探测（保留给调试/外部调用）
enum LooksHTML {
    static func check(_ text: String) -> Bool {
        let prefix = text.prefix(4000)
        guard let regex = try? NSRegularExpression(pattern: "<\\s*[a-zA-Z!/][^>]*>") else { return false }
        let string = String(prefix)
        return regex.firstMatch(in: string, range: NSRange(string.startIndex..<string.endIndex, in: string)) != nil
    }
}

// MARK: - 列表规则修饰符

enum ListedRule {
    /// 首字符 `-` 表示反转，`+` 只是去标记
    static func normalize(_ rule: String) -> (rule: String, reversed: Bool) {
        var text = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        var reversed = false
        if text.hasPrefix("-") {
            reversed = true
            text.removeFirst()
        } else if text.hasPrefix("+") {
            text.removeFirst()
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), reversed)
    }
}

// MARK: - URL 选项

/// `URL,{json}` 里的请求选项
struct URLOptions {
    var method: String?
    var headers: [String: String]?
    var body: String?
    var charset: String?
    var retry: Int?
    var type: String?

    static let empty = URLOptions()

    init() {}

    var isEmpty: Bool { jsonDictionary == nil }

    /// 回写成 `URL,{json}` 里的 JSON 对象（用于把选项透传到下一阶段）
    var jsonDictionary: [String: Any]? {
        var out: [String: Any] = [:]
        if let method { out["method"] = method }
        if let headers, !headers.isEmpty { out["headers"] = headers }
        if let body { out["body"] = body }
        if let charset { out["charset"] = charset }
        if let retry { out["retry"] = retry }
        if let type { out["type"] = type }
        return out.isEmpty ? nil : out
    }

    /// 选项合并：`override` 里非空字段优先
    static func merge(_ base: URLOptions, _ override: URLOptions) -> URLOptions {
        var result = base
        if let method = override.method { result.method = method }
        if let headers = override.headers { result.headers = (result.headers ?? [:]).merging(headers) { _, new in new } }
        if let body = override.body { result.body = body }
        if let charset = override.charset { result.charset = charset }
        if let retry = override.retry { result.retry = retry }
        if let type = override.type { result.type = type }
        return result
    }

    init(dictionary: [String: Any]) {
        if let value = dictionary["method"] as? String, !value.isEmpty {
            method = value.uppercased()
        }
        if let rawHeaders = dictionary["headers"] as? [String: Any] {
            var parsed: [String: String] = [:]
            for (key, value) in rawHeaders { parsed[key] = JSONValueUtil.text(value) }
            headers = parsed
        }
        if let value = dictionary["charset"] as? String, !value.isEmpty {
            charset = value
        }
        if let value = JSONValueUtil.numberValue(dictionary["retry"]) {
            retry = Int(value)
        }
        if let value = dictionary["type"] as? String, !value.isEmpty {
            type = value
        }
        if let bodyValue = dictionary["body"] {
            if let string = bodyValue as? String {
                body = string
            } else {
                body = JSONValueUtil.jsonText(bodyValue)
            }
        }
    }
}

/// URL 规则求值结果：已解析成绝对 URL + 请求选项
struct RuleURL {
    var url: String
    var options: URLOptions = .empty

    /// 带 `URL,{json}` 选项后缀的完整写法（用于模型字段透传到下一阶段）
    var urlWithOptions: String {
        guard let dictionary = options.jsonDictionary else { return url }
        return url + "," + JSONValueUtil.jsonText(dictionary)
    }
}

/// URL 模板拼接、相对路径解析、`URL,{json}` 选项拆分
enum RuleURLResolver {

    /// 书源站点根（bookSourceUrl 去掉 fragment / query / 末尾斜杠）
    static func sourceBaseURL(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
        if let query = text.firstIndex(of: "?") { text = String(text[..<query]) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    /// 解析一条 URL 规则（bookUrl / tocUrl / chapterUrl / searchUrl）
    static func analyzeURL(_ rule: String, with analyzer: RuleAnalyzer) throws -> RuleURL {
        let raw = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return RuleURL(url: "") }

        var output: String
        let hasJS = raw.range(of: "<js>", options: .caseInsensitive) != nil || raw.lowercased().contains("@js:")
        let hasMustache = raw.contains("{{")
        if hasJS || hasMustache {
            output = try analyzer.expandURLTemplate(raw)
        } else {
            let value = JSONValueUtil.text(try analyzer.analyze(raw, input: analyzer.context.result, asList: false))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                output = value
            } else if isLiteralURL(raw) {
                output = raw
            } else {
                output = ""
            }
        }

        let split = splitOptions(output)
        let resolved = resolve(base: analyzer.context.baseURL, relative: split.url)
        return RuleURL(url: resolved, options: split.options)
    }

    /// 拆分 `URL,{json}` 选项（从右往左找 `,{`，避免切坏 URL 里本来就有的逗号）
    static func splitOptions(_ raw: String) -> (url: String, options: URLOptions) {
        var searchRange = raw.startIndex..<raw.endIndex
        while let candidate = raw.range(of: ",{", options: .backwards, range: searchRange) {
            let jsonPart = String(raw[raw.index(after: candidate.lowerBound)...])
            if let dictionary = LenientJSON.parse(jsonPart) as? [String: Any] {
                let url = String(raw[..<candidate.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (url, URLOptions(dictionary: dictionary))
            }
            if candidate.lowerBound == raw.startIndex { break }
            searchRange = raw.startIndex..<candidate.lowerBound
        }
        return (raw.trimmingCharacters(in: .whitespacesAndNewlines), .empty)
    }

    /// 相对路径按 base 解析（等价于 `new URL(relative, base)`），并给非 ASCII 字符做百分号编码
    static func resolve(base: String, relative: String) -> String {
        let raw = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        if raw.hasPrefix("data:") || raw.hasPrefix("javascript:") { return raw }

        let encoded = percentEncode(raw)
        if encoded.contains("://") || encoded.hasPrefix("mailto:") {
            return encoded
        }
        let baseText = stripFragment(base)
        guard !baseText.isEmpty else { return encoded }

        if let baseURL = URL(string: percentEncode(baseText)),
           let resolved = URL(string: encoded, relativeTo: baseURL) {
            return resolved.absoluteString
        }
        // 退化路径：手工拼 origin
        if let schemeRange = baseText.range(of: "://") {
            let origin = String(baseText[..<schemeRange.upperBound]) + (baseText[schemeRange.upperBound...].split(separator: "/").first.map(String.init) ?? "")
            if encoded.hasPrefix("/") { return origin + encoded }
            return origin + "/" + encoded
        }
        return encoded
    }

    /// 去掉 `URL,{json}` 选项后缀，供 UI 展示
    static func displayURL(_ raw: String) -> String {
        splitOptions(raw).url
    }

    static func stripFragment(_ url: String) -> String {
        guard let hash = url.firstIndex(of: "#") else { return url }
        return String(url[..<hash])
    }

    private static func isLiteralURL(_ rule: String) -> Bool {
        guard rule.hasPrefix("http://") || rule.hasPrefix("https://") || rule.hasPrefix("/") || rule.hasPrefix("./") else {
            return false
        }
        return !rule.contains("[") && !rule.contains("]") && !rule.contains("<")
    }

    /// 只对非 ASCII、空格与 URL 非法字符做百分号编码；已存在的 `%xx` 原样保留。
    static func percentEncode(_ text: String) -> String {
        var output = ""
        for scalar in text.unicodeScalars {
            if scalar.isASCII {
                switch scalar {
                case " ": output += "%20"
                case "\"": output += "%22"
                case "<": output += "%3C"
                case ">": output += "%3E"
                case "|": output += "%7C"
                case "\\": output += "%5C"
                case "^": output += "%5E"
                case "`": output += "%60"
                case "{": output += "%7B"
                case "}": output += "%7D"
                default: output.unicodeScalars.append(scalar)
                }
            } else {
                for byte in String(scalar).utf8 {
                    output += String(format: "%%%02X", byte)
                }
            }
        }
        return output
    }
}

// MARK: - 门面

/// 规则引擎门面（供流水线与调试入口使用）
enum RuleEngine {
    static func text(_ value: Any?) -> String { JSONValueUtil.text(value) }

    static func analyze(
        _ rule: String,
        input: Any,
        context: RuleContext,
        vars: RuleVariableStore,
        js: RuleJSEvaluating?
    ) throws -> Any {
        try RuleAnalyzer(context: context, vars: vars, js: js).analyze(rule, input: input)
    }
}
