// JSONPath.swift —— Legado/JsonPath 子集求值（输入 JSONSerialization 产物，输出 [Any]）与宽松 JSON 工具
import Foundation

// MARK: - JSON 值工具

/// JSON 值的规范化、转文本与宽松解析。
///
/// `JSONSerialization` 产出的是 NSDictionary/NSArray/NSString/NSNumber/NSNull，
/// 这里统一收敛成 `[String: Any]` / `[Any]` / `String` / `Double` / `Bool` / `NSNull`，
/// 让规则引擎与 JS 沙箱共享同一套值表示。
enum JSONValueUtil {

    /// 递归规范化 JSONSerialization 的产物
    static func normalize(_ value: Any) -> Any {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            return number.doubleValue
        case let string as NSString:
            return string as String
        case is NSNull:
            return NSNull()
        case let array as [Any]:
            return array.map(normalize)
        case let dictionary as [String: Any]:
            var out: [String: Any] = [:]
            for (key, element) in dictionary { out[key] = normalize(element) }
            return out
        case let array as NSArray:
            return array.map { normalize($0) }
        case let dictionary as NSDictionary:
            var out: [String: Any] = [:]
            for (key, element) in dictionary {
                guard let key = key as? String else { continue }
                out[key] = normalize(element)
            }
            return out
        default:
            return value
        }
    }

    /// 宽松 JSON 解析（失败返回 nil）
    static func parseJSON(_ text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return normalize(object)
    }

    /// 判断字符串是否是“看起来可信的 JSON 正文”（首字符是 { 或 [，且能解析）
    static func looksLikeJSON(_ value: Any?) -> Bool {
        guard let text = value as? String else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return false }
        return parseJSON(trimmed) != nil
    }

    /// 值转文本（对齐 Node 参考实现 textOf）
    static func text(_ value: Any?) -> String {
        guard let value else { return "" }
        switch value {
        case is NSNull:
            return ""
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return doubleText(number.doubleValue)
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let int as Int:
            return String(int)
        case let int64 as Int64:
            return String(int64)
        case let double as Double:
            return doubleText(double)
        case let array as [Any]:
            return jsonText(array)
        case let dictionary as [String: Any]:
            return jsonText(dictionary)
        default:
            return String(describing: value)
        }
    }

    /// JSON 序列化文本（字典按键排序，便于调试输出稳定）
    static func jsonText(_ value: Any) -> String {
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }

    /// JS 真假语义（对齐 `!!v`）
    static func boolValue(_ value: Any?) -> Bool {
        guard let value else { return false }
        switch value {
        case is NSNull: return false
        case let bool as Bool: return bool
        case let string as String: return !string.isEmpty
        case let array as [Any]: return !array.isEmpty
        case let dictionary as [String: Any]: return !dictionary.isEmpty
        case let number as NSNumber: return number.doubleValue != 0
        default: return true
        }
    }

    /// 提取数值（不能转成数字时返回 nil）
    static func numberValue(_ value: Any?) -> Double? {
        guard let value else { return nil }
        switch value {
        case let bool as Bool:
            return bool ? 1 : 0
        case let int as Int:
            return Double(int)
        case let double as Double:
            return double
        case let string as String:
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? 1 : 0
            }
            return number.doubleValue
        default:
            return nil
        }
    }

    private static func doubleText(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }
}

// MARK: - 宽松 JSON

/// GSON/书源作者常用的宽松 JSON（注释、尾逗号、裸 key、单引号）。
enum LenientJSON {

    static func parse(_ text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let value = JSONValueUtil.parseJSON(trimmed) { return value }

        var working = stripComments(trimmed)
        working = quoteBareKeys(working)
        working = convertSingleQuotes(working)
        working = removeTrailingCommas(working)
        return JSONValueUtil.parseJSON(working)
    }

    // MARK: 内部扫描（全部区分字符串内外，避免把 URL 里的 // 当注释）

    private static func stripComments(_ text: String) -> String {
        let chars = Array(text)
        var out = ""
        var index = 0
        var quote: Character?
        while index < chars.count {
            let char = chars[index]
            if let current = quote {
                out.append(char)
                if char == "\\", index + 1 < chars.count {
                    out.append(chars[index + 1])
                    index += 2
                    continue
                }
                if char == current { quote = nil }
                index += 1
                continue
            }
            if char == "\"" || char == "'" {
                quote = char
                out.append(char)
                index += 1
                continue
            }
            if char == "/", index + 1 < chars.count {
                let next = chars[index + 1]
                if next == "/" {
                    index += 2
                    while index < chars.count, chars[index] != "\n", chars[index] != "\r" { index += 1 }
                    continue
                }
                if next == "*" {
                    index += 2
                    while index + 1 < chars.count, !(chars[index] == "*" && chars[index + 1] == "/") { index += 1 }
                    index = min(index + 2, chars.count)
                    continue
                }
            }
            out.append(char)
            index += 1
        }
        return out
    }

    private static func quoteBareKeys(_ text: String) -> String {
        let chars = Array(text)
        var out = ""
        var index = 0
        var quote: Character?
        while index < chars.count {
            let char = chars[index]
            if let current = quote {
                out.append(char)
                if char == "\\", index + 1 < chars.count {
                    out.append(chars[index + 1])
                    index += 2
                    continue
                }
                if char == current { quote = nil }
                index += 1
                continue
            }
            if char == "\"" || char == "'" {
                quote = char
                out.append(char)
                index += 1
                continue
            }
            if char == "{" || char == "," {
                out.append(char)
                index += 1
                // 跳过空白
                while index < chars.count, chars[index] == " " || chars[index] == "\n" || chars[index] == "\t" || chars[index] == "\r" {
                    out.append(chars[index])
                    index += 1
                }
                let identifierStart = index
                while index < chars.count, isIdentifierChar(chars[index]) { index += 1 }
                let identifier = String(chars[identifierStart..<index])
                if !identifier.isEmpty, index < chars.count, chars[index] == ":" {
                    out.append("\"" + identifier + "\"")
                } else {
                    out.append(identifier)
                }
                continue
            }
            out.append(char)
            index += 1
        }
        return out
    }

    private static func convertSingleQuotes(_ text: String) -> String {
        let chars = Array(text)
        var out = ""
        var index = 0
        var inDouble = false
        var inSingle = false
        while index < chars.count {
            let char = chars[index]
            if char == "\\", index + 1 < chars.count {
                out.append(char)
                out.append(chars[index + 1])
                index += 2
                continue
            }
            if inDouble {
                out.append(char)
                if char == "\"" { inDouble = false }
                index += 1
                continue
            }
            if inSingle {
                if char == "'" {
                    out.append("\"")
                    inSingle = false
                } else if char == "\"" {
                    out.append("\\\"")
                } else {
                    out.append(char)
                }
                index += 1
                continue
            }
            if char == "\"" {
                inDouble = true
                out.append(char)
            } else if char == "'" {
                inSingle = true
                out.append("\"")
            } else {
                out.append(char)
            }
            index += 1
        }
        return out
    }

    private static func removeTrailingCommas(_ text: String) -> String {
        let chars = Array(text)
        var out = ""
        var index = 0
        var quote: Character?
        while index < chars.count {
            let char = chars[index]
            if let current = quote {
                out.append(char)
                if char == "\\", index + 1 < chars.count {
                    out.append(chars[index + 1])
                    index += 2
                    continue
                }
                if char == current { quote = nil }
                index += 1
                continue
            }
            if char == "\"" || char == "'" {
                quote = char
                out.append(char)
                index += 1
                continue
            }
            if char == "," {
                var lookahead = index + 1
                while lookahead < chars.count, chars[lookahead] == " " || chars[lookahead] == "\n" || chars[lookahead] == "\t" || chars[lookahead] == "\r" {
                    lookahead += 1
                }
                if lookahead < chars.count, chars[lookahead] == "}" || chars[lookahead] == "]" {
                    index += 1 // 丢弃这个尾逗号
                    continue
                }
            }
            out.append(char)
            index += 1
        }
        return out
    }

    private static func isIdentifierChar(_ char: Character) -> Bool {
        if char == "_" || char == "$" { return true }
        return char.isLetter || char.isNumber
    }
}

// MARK: - JSONPath

/// JSONPath 子集：`$`、`.key`、`['key']`、`..key`、`[*]`、`[n]`、`[-n]`、`[a,b]`、
/// `[a:b]`/`[a:b:step]`、`[?(@.k=='v')]`（`== != > < >= <= =~` 与 `&&`/`||`）、`.length()`。
enum JSONPath {

    /// 求值，返回命中的值列表（保持文档顺序）。“无结果”就是空数组，不抛错。
    static func evaluate(_ root: Any, _ expression: String) -> [Any] {
        guard let tokens = parse(expression) else { return [] }
        var current: [Any] = [root]

        for token in tokens {
            var next: [Any] = []
            for item in current {
                if item is NSNull { continue }
                switch token {
                case .child(let name):
                    if name == "*" {
                        if let array = item as? [Any] {
                            next.append(contentsOf: array)
                        } else if let dictionary = item as? [String: Any] {
                            next.append(contentsOf: dictionary.values)
                        }
                    } else if let dictionary = item as? [String: Any], let value = dictionary[name] {
                        next.append(value)
                    }

                case .recursive(let name):
                    walk(item) { key, value in
                        if name == "*" || key == name { next.append(value) }
                    }

                case .wildcard:
                    if let array = item as? [Any] {
                        next.append(contentsOf: array)
                    } else if let dictionary = item as? [String: Any] {
                        next.append(contentsOf: dictionary.values)
                    }

                case .index(let index):
                    if let array = item as? [Any] {
                        let resolved = index < 0 ? array.count + index : index
                        if resolved >= 0, resolved < array.count { next.append(array[resolved]) }
                    }

                case .slice(let start, let end, let step):
                    guard let array = item as? [Any] else { break }
                    let length = array.count
                    var begin = start ?? 0
                    var finish = end ?? length
                    if begin < 0 { begin += length }
                    if finish < 0 { finish += length }
                    let stride = step == 0 ? 1 : step
                    var cursor = begin
                    while stride > 0 ? cursor < finish : cursor > finish {
                        if cursor >= 0, cursor < length { next.append(array[cursor]) }
                        cursor += stride
                    }

                case .union(let names):
                    if let dictionary = item as? [String: Any] {
                        for name in names {
                            if let value = dictionary[name] { next.append(value) }
                        }
                    } else if let array = item as? [Any] {
                        for name in names {
                            guard let index = Int(name), index >= 0, index < array.count else { continue }
                            next.append(array[index])
                        }
                    }

                case .filter(let expression):
                    let candidates = (item as? [Any]) ?? [item]
                    for element in candidates where evalFilter(element, expression) {
                        next.append(element)
                    }

                case .length:
                    if let array = item as? [Any] {
                        next.append(Double(array.count))
                    } else if let string = item as? String {
                        next.append(Double(string.count))
                    } else if let dictionary = item as? [String: Any] {
                        next.append(Double(dictionary.count))
                    }
                }
            }
            current = next
        }
        return current
    }

    /// 只取第一个命中值（规则引擎 asList=false 时使用）
    static func first(_ root: Any, _ expression: String) -> Any? {
        evaluate(root, expression).first
    }

    // MARK: Token 解析

    private enum Token {
        case child(String)
        case recursive(String)
        case wildcard
        case index(Int)
        case slice(Int?, Int?, Int)
        case union([String])
        case filter(String)
        case length
    }

    private static func parse(_ expression: String) -> [Token]? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("$") else { return nil }
        let chars = Array(trimmed)
        var tokens: [Token] = []
        var index = 0

        while index < chars.count {
            let char = chars[index]

            if char == "$" {
                index += 1
                continue
            }

            if char == ".", index + 1 < chars.count, chars[index + 1] == "." {
                index += 2
                var name = ""
                while index < chars.count, isNameChar(chars[index]) {
                    name.append(chars[index])
                    index += 1
                }
                if name.isEmpty, index < chars.count, chars[index] == "*" {
                    name = "*"
                    index += 1
                }
                tokens.append(.recursive(name))
                continue
            }

            if char == "." {
                index += 1
                var name = ""
                while index < chars.count, isNameChar(chars[index]) {
                    name.append(chars[index])
                    index += 1
                }
                if name.isEmpty, index < chars.count, chars[index] == "*" {
                    name = "*"
                    index += 1
                }
                if name == "length", index + 1 < chars.count, chars[index] == "(", chars[index + 1] == ")" {
                    index += 2
                    tokens.append(.length)
                    continue
                }
                if !name.isEmpty { tokens.append(.child(name)) }
                continue
            }

            if char == "[" {
                var depth = 1
                var cursor = index + 1
                var quote: Character?
                while cursor < chars.count, depth > 0 {
                    let current = chars[cursor]
                    if let activeQuote = quote {
                        if current == activeQuote, cursor > 0, chars[cursor - 1] != "\\" { quote = nil }
                    } else if current == "\"" || current == "'" {
                        quote = current
                    } else if current == "[" {
                        depth += 1
                    } else if current == "]" {
                        depth -= 1
                    }
                    cursor += 1
                }
                let inner = String(chars[(index + 1)..<max(index + 1, cursor - 1)])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                index = cursor
                tokens.append(tokenForBracket(inner))
                continue
            }

            index += 1
        }
        return tokens
    }

    private static func tokenForBracket(_ inner: String) -> Token {
        if inner == "*" { return .wildcard }
        if inner.hasPrefix("?") {
            var expression = inner
            expression.removeFirst()
            return .filter(expression.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let index = Int(inner) { return .index(index) }
        if let slice = parseSlice(inner) { return slice }
        if inner.count >= 2, let first = inner.first, let last = inner.last,
           (first == "'" && last == "'") || (first == "\"" && last == "\"") {
            return .child(String(inner.dropFirst().dropLast()))
        }
        if inner.contains(",") {
            let names = inner.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            }
            return .union(names)
        }
        return .child(inner.trimmingCharacters(in: CharacterSet(charactersIn: "'\"")))
    }

    private static func parseSlice(_ inner: String) -> Token? {
        let parts = inner.split(separator: ":", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var numbers: [Int?] = []
        for part in parts {
            if part.isEmpty {
                numbers.append(nil)
            } else if let value = Int(part) {
                numbers.append(value)
            } else {
                return nil
            }
        }
        let step = numbers.count == 3 ? (numbers[2] ?? 1) : 1
        return .slice(numbers[0], numbers[1], step)
    }

    private static func isNameChar(_ char: Character) -> Bool {
        if char == "_" || char == "$" || char == "@" || char == "-" { return true }
        return char.isLetter || char.isNumber
    }

    /// 递归收集所有层级里 key 命中的值（对齐 Node 参考实现 `..key` 的顺序）
    private static func walk(_ value: Any, visit: (String, Any) -> Void) {
        if let array = value as? [Any] {
            for element in array { walk(element, visit: visit) }
            return
        }
        if let dictionary = value as? [String: Any] {
            for (key, element) in dictionary {
                visit(key, element)
                walk(element, visit: visit)
            }
        }
    }

    // MARK: 过滤表达式

    private static func evalFilter(_ object: Any, _ expression: String) -> Bool {
        var trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // `?((@.a && @.b))`：先剥掉整体包裹的括号，否则 `splitTopLevel` 会因为括号深度不切分
        while isWrappedInParens(trimmed) {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else { return false }

        let orParts = splitTopLevel(trimmed, separator: "||")
        if orParts.count > 1 { return orParts.contains { evalFilter(object, $0) } }

        let andParts = splitTopLevel(trimmed, separator: "&&")
        if andParts.count > 1 { return andParts.allSatisfy { evalFilter(object, $0) } }

        let inner = trimmed

        // 正则匹配：@.name =~ /pattern/i
        if let groups = regexGroups("^@\\.?([^\\s=~<>!]+)\\s*=~\\s*/(.*)/([i]?)$", inner), groups.count == 3 {
            let value = JSONValueUtil.text(pathValue(object, groups[0]))
            let pattern = groups[1].replacingOccurrences(of: "\\/", with: "/")
            let options: NSRegularExpression.Options = groups[2].lowercased().contains("i") ? [.caseInsensitive] : []
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return regex.firstMatch(in: value, options: [], range: range) != nil
        }

        // 相等/不等
        if let groups = regexGroups("^@\\.?([^\\s=<>!]+)\\s*([=!]=)\\s*(.+)$", inner), groups.count == 3 {
            let left = pathValue(object, groups[0])
            let right = parseLiteral(groups[2])
            let isEqual = areEqual(left, right)
            return groups[1] == "==" ? isEqual : !isEqual
        }

        // 数值比较
        if let groups = regexGroups("^@\\.?([^\\s=<>!]+)\\s*(>=|<=|>|<)\\s*(-?\\d+(?:\\.\\d+)?)$", inner),
           groups.count == 3,
           let left = JSONValueUtil.numberValue(pathValue(object, groups[0])),
           let right = Double(groups[2]) {
            switch groups[1] {
            case ">": return left > right
            case "<": return left < right
            case ">=": return left >= right
            default: return left <= right
            }
        }

        // 存在性：@.key
        if let groups = regexGroups("^@\\.?([^\\s=<>!]+)$", inner), groups.count == 1 {
            return JSONValueUtil.boolValue(pathValue(object, groups[0]))
        }

        return false
    }

    /// 判断字符串是否整体被一对括号包裹（`(a && b)`），而不是 `(a) && (b)`
    private static func isWrappedInParens(_ text: String) -> Bool {
        let chars = Array(text)
        guard chars.count >= 2, chars.first == "(", chars.last == ")" else { return false }
        var depth = 0
        var quote: Character?
        for (index, char) in chars.enumerated() {
            if let activeQuote = quote {
                if char == activeQuote, index > 0, chars[index - 1] != "\\" { quote = nil }
                continue
            }
            if char == "\"" || char == "'" { quote = char; continue }
            if char == "(" { depth += 1 }
            if char == ")" {
                depth -= 1
                if depth == 0, index != chars.count - 1 { return false }
            }
        }
        return depth == 0
    }

    private static func pathValue(_ object: Any, _ path: String) -> Any? {
        if path.isEmpty { return object }
        var current: Any? = object
        for part in path.split(separator: ".") {
            guard let value = current else { return nil }
            if part == "*" { return value }
            guard let dictionary = value as? [String: Any] else { return nil }
            current = dictionary[String(part)]
        }
        return current
    }

    private static func parseLiteral(_ text: String) -> Any {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2,
           let first = trimmed.first, let last = trimmed.last,
           (first == "'" && last == "'") || (first == "\"" && last == "\"") {
            return String(trimmed.dropFirst().dropLast())
        }
        if let number = Double(trimmed) { return number }
        if trimmed == "true" { return true }
        if trimmed == "false" { return false }
        if trimmed == "null" { return NSNull() }
        return trimmed
    }

    private static func areEqual(_ left: Any?, _ right: Any) -> Bool {
        if let leftNumber = JSONValueUtil.numberValue(left), let rightNumber = JSONValueUtil.numberValue(right) {
            return leftNumber == rightNumber
        }
        if let leftBool = left as? Bool, let rightBool = right as? Bool {
            return leftBool == rightBool
        }
        return JSONValueUtil.text(left) == JSONValueUtil.text(right)
    }

    /// 顶层切分（尊重引号与括号），用于 `||` / `&&`
    private static func splitTopLevel(_ text: String, separator: String) -> [String] {
        let chars = Array(text)
        let separatorChars = Array(separator)
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if let activeQuote = quote {
                current.append(char)
                if char == "\\", index + 1 < chars.count {
                    current.append(chars[index + 1])
                    index += 2
                    continue
                }
                if char == activeQuote { quote = nil }
                index += 1
                continue
            }
            if char == "\"" || char == "'" {
                quote = char
                current.append(char)
                index += 1
                continue
            }
            if char == "(" || char == "[" || char == "{" { depth += 1 }
            if char == ")" || char == "]" || char == "}" { depth = max(0, depth - 1) }
            if depth == 0, index + separatorChars.count <= chars.count,
               Array(chars[index..<(index + separatorChars.count)]) == separatorChars {
                parts.append(current)
                current = ""
                index += separatorChars.count
                continue
            }
            current.append(char)
            index += 1
        }
        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// 用 NSRegularExpression 取捕获组文本（groups[0] 是第一个捕获组）
    private static func regexGroups(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)) else {
            return nil
        }
        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            groups.append(String(text[range]))
        }
        return groups
    }
}
