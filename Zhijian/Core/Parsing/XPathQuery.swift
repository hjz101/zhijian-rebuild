// XPathQuery.swift —— 书源用的 XPath 子集（自研，不依赖 libxml2）
//
// 支持：
// - 路径：`//tag`、`/tag`、`//*`、`.//tag`、相对路径、`|` 并集；
// - 谓词：`[n]`、`[last()]`、`[last()-k]`、`[@attr]`、`[@attr='v']`、`[@attr!='v']`、
//   `[text()]`、`[contains(@class,'x')]`、`[starts-with(@id,'x')]`、
//   `[contains(text(),'x')]`、`[position()>1]`，以及 `and` / `or` / `not(...)` 组合；
// - 末尾（或路径中）的 `/text()`、`//text()`、`/@attr`、`//@attr`。
//
// 子树上下文：列表项里以「当前节点」为上下文求值，`//x` 等价于 `.//x`（与 Legado
// JsoupXpath 的 `JXNode.sel()` 行为一致，不会跑到整篇文档里）。
import Foundation

// MARK: - 对外入口

enum XPathQuery {

    static func evaluate(_ expression: String, in context: HTMLNode) -> [Any] {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 顶层并集 `//a | //b`
        let unions = XPathParser.splitTopLevel(trimmed, separator: "|")
        if unions.count > 1 {
            var results: [Any] = []
            var seen = Set<ObjectIdentifier>()
            for part in unions {
                for value in evaluate(part, in: context) {
                    if let node = value as? HTMLNode {
                        if seen.insert(ObjectIdentifier(node)).inserted { results.append(node) }
                    } else {
                        results.append(value)
                    }
                }
            }
            return results
        }

        guard let steps = XPathParser.parse(trimmed), !steps.isEmpty else { return [] }
        return XPathEvaluator.evaluate(steps, context: context)
    }

    static func evaluate(_ expression: String, in contexts: [HTMLNode]) -> [Any] {
        var results: [Any] = []
        var seen = Set<ObjectIdentifier>()
        for context in contexts {
            for value in evaluate(expression, in: context) {
                if let node = value as? HTMLNode {
                    if seen.insert(ObjectIdentifier(node)).inserted { results.append(node) }
                } else {
                    results.append(value)
                }
            }
        }
        return results
    }
}

// MARK: - 语法模型

struct XPathStep {

    enum Axis {
        case child
        case descendant
    }

    enum Test {
        case name(String)
        case wildcard
        case text
        case attribute(String)
    }

    var axis: Axis
    var test: Test
    var predicates: [XPathPredicate]
}

indirect enum XPathPredicate {
    case position(Int)
    case last(offset: Int)
    case existsAttribute(String)
    case missingAttribute(String)
    case attributeEquals(String, String)
    case attributeNotEquals(String, String)
    case attributeContains(String, String)
    case attributeStartsWith(String, String)
    case attributeEndsWith(String, String)
    case hasText
    case containsText(String)
    case startsWithText(String)
    case positionCompare(operator: String, value: Int)
    case negate(XPathPredicate)
    case all([XPathPredicate])
    case any([XPathPredicate])
}

// MARK: - 解析

enum XPathParser {

    static func parse(_ expression: String) -> [XPathStep]? {
        let characters = Array(expression)
        var index = 0
        var steps: [XPathStep] = []
        var pendingAxis: XPathStep.Axis?

        while index < characters.count {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            guard index < characters.count else { break }
            let character = characters[index]

            if character == "/" {
                index += 1
                if index < characters.count, characters[index] == "/" {
                    index += 1
                    pendingAxis = .descendant
                } else {
                    pendingAxis = .child
                }
                continue
            }

            if character == "." {
                // `.` / `.//x`
                if index + 1 < characters.count, characters[index + 1] == "/" {
                    index += 1
                    continue
                }
                if index + 1 >= characters.count || characters[index + 1].isWhitespace
                    || characters[index + 1] == "[" {
                    index += 1
                    continue
                }
                return nil
            }

            let axis = pendingAxis ?? .child
            pendingAxis = nil

            guard let (test, afterTest) = parseNodeTest(characters, from: index) else { return nil }
            index = afterTest

            var predicates: [XPathPredicate] = []
            while index < characters.count, characters[index] == "[" {
                guard let (inner, afterPredicate) = readBalanced(characters, from: index) else { return nil }
                guard let predicate = parsePredicate(inner) else { return nil }
                predicates.append(predicate)
                index = afterPredicate
            }

            steps.append(XPathStep(axis: axis, test: test, predicates: predicates))

            while index < characters.count, characters[index].isWhitespace { index += 1 }
            if index < characters.count, characters[index] != "/" { return nil }
        }

        return steps
    }

    // MARK: 节点测试

    private static func parseNodeTest(_ characters: [Character], from start: Int) -> (XPathStep.Test, Int)? {
        var index = start
        guard index < characters.count else { return nil }

        if characters[index] == "@" {
            index += 1
            guard let (name, next) = readName(characters, from: index) else { return nil }
            return (.attribute(name.lowercased()), next)
        }
        if characters[index] == "*" {
            return (.wildcard, index + 1)
        }
        // text()（容忍空白：`text ( )`）
        if let (name, next) = readName(characters, from: index), name.lowercased() == "text" {
            var cursor = next
            while cursor < characters.count, characters[cursor].isWhitespace { cursor += 1 }
            if cursor < characters.count, characters[cursor] == "(" {
                cursor += 1
                while cursor < characters.count, characters[cursor].isWhitespace { cursor += 1 }
                if cursor < characters.count, characters[cursor] == ")" {
                    return (.text, cursor + 1)
                }
            }
        }
        guard let (name, next) = readName(characters, from: index) else { return nil }
        return (.name(name.lowercased()), next)
    }

    private static func readName(_ characters: [Character], from start: Int) -> (String, Int)? {
        var index = start
        var name = ""
        while index < characters.count {
            let character = characters[index]
            let isNameCharacter = character.isLetter || character.isNumber
                || character == "-" || character == "_" || character == ":" || character == "."
                || character.unicodeScalars.first.map { $0.value > 0x7F } == true
            guard isNameCharacter else { break }
            name.append(character)
            index += 1
        }
        guard !name.isEmpty else { return nil }
        return (name, index)
    }

    private static func readBalanced(_ characters: [Character], from start: Int) -> (String, Int)? {
        guard start < characters.count, characters[start] == "[" else { return nil }
        var index = start + 1
        var depth = 1
        var quote: Character?
        var inner = ""
        while index < characters.count {
            let character = characters[index]
            if let activeQuote = quote {
                inner.append(character)
                if character == activeQuote { quote = nil }
                index += 1
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                inner.append(character)
                index += 1
                continue
            }
            if character == "[" {
                depth += 1
                inner.append(character)
                index += 1
                continue
            }
            if character == "]" {
                depth -= 1
                if depth == 0 { return (inner, index + 1) }
                inner.append(character)
                index += 1
                continue
            }
            inner.append(character)
            index += 1
        }
        return nil
    }

    // MARK: 谓词

    static func parsePredicate(_ raw: String) -> XPathPredicate? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let parts = splitLogical(text, keyword: " and ") {
            let predicates = parts.compactMap { parsePredicate($0) }
            return predicates.count == parts.count ? .all(predicates) : nil
        }
        if let parts = splitLogical(text, keyword: " or ") {
            let predicates = parts.compactMap { parsePredicate($0) }
            return predicates.count == parts.count ? .any(predicates) : nil
        }
        if text.hasPrefix("not("), text.hasSuffix(")") {
            let inner = String(text.dropFirst(4).dropLast())
            guard let predicate = parsePredicate(inner) else { return nil }
            return .negate(predicate)
        }
        if let value = Int(text) {
            return .position(value)
        }
        if text.hasPrefix("last()") {
            var rest = String(text.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            guard !rest.isEmpty else { return .last(offset: 0) }
            var negative = false
            if rest.hasPrefix("-") {
                negative = true
                rest.removeFirst()
            } else if rest.hasPrefix("+") {
                rest.removeFirst()
            }
            guard let value = Int(rest) else { return nil }
            return .last(offset: negative ? value : -value)
        }
        if text == "text()" {
            return .hasText
        }
        if text.hasPrefix("contains("), text.hasSuffix(")") {
            let inner = String(text.dropFirst("contains(".count).dropLast())
            return parseTextFunction(inner, kind: .contains)
        }
        if text.hasPrefix("starts-with("), text.hasSuffix(")") {
            let inner = String(text.dropFirst("starts-with(".count).dropLast())
            return parseTextFunction(inner, kind: .startsWith)
        }
        if text.hasPrefix("ends-with("), text.hasSuffix(")") {
            let inner = String(text.dropFirst("ends-with(".count).dropLast())
            return parseTextFunction(inner, kind: .endsWith)
        }
        if text.hasPrefix("position()") {
            let rest = text.dropFirst("position()".count).trimmingCharacters(in: .whitespaces)
            for op in [">=", "<=", "!=", "=", ">", "<"] where rest.hasPrefix(op) {
                let valueText = rest.dropFirst(op.count).trimmingCharacters(in: .whitespaces)
                guard let value = Int(valueText) else { return nil }
                return .positionCompare(operator: op, value: value)
            }
            return .position(1)
        }
        if text.hasPrefix("@") {
            return parseAttributePredicate(text)
        }
        // `normalize-space(@class)='x'` 之类暂不支持
        return nil
    }

    private enum TextFunctionKind {
        case contains
        case startsWith
        case endsWith
    }

    private static func parseTextFunction(_ inner: String, kind: TextFunctionKind) -> XPathPredicate? {
        let arguments = splitArguments(inner)
        guard arguments.count >= 2 else { return nil }
        let subject = arguments[0].trimmingCharacters(in: .whitespaces)
        let value = unquote(arguments[1].trimmingCharacters(in: .whitespaces))
        guard !value.isEmpty else { return nil }

        if subject == "text()" || subject == "." || subject == "string(.)" {
            switch kind {
            case .contains: return .containsText(value)
            case .startsWith: return .startsWithText(value)
            case .endsWith: return nil
            }
        }
        if subject.hasPrefix("@") {
            let name = String(subject.dropFirst()).trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty else { return nil }
            switch kind {
            case .contains: return .attributeContains(name, value)
            case .startsWith: return .attributeStartsWith(name, value)
            case .endsWith: return .attributeEndsWith(name, value)
            }
        }
        return nil
    }

    private static func parseAttributePredicate(_ text: String) -> XPathPredicate? {
        for op in ["!=", "="] {
            if let range = text.range(of: op) {
                let name = String(text[text.startIndex..<range.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "@", with: "")
                    .lowercased()
                let value = unquote(String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces))
                guard !name.isEmpty else { return nil }
                return op == "=" ? .attributeEquals(name, value) : .attributeNotEquals(name, value)
            }
        }
        let name = String(text.dropFirst()).trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return nil }
        return .existsAttribute(name)
    }

    /// 按顶层 ` and ` / ` or ` 切分（引号、括号内的不算）
    private static func splitLogical(_ text: String, keyword: String) -> [String]? {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        let characters = Array(text)
        var index = 0
        let needle = Array(keyword)
        while index < characters.count {
            let character = characters[index]
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
                index += 1
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
                index += 1
                continue
            }
            if character == "(" || character == "[" {
                depth += 1
            } else if character == ")" || character == "]" {
                depth = max(0, depth - 1)
            }
            if depth == 0, matches(characters, at: index, needle: needle) {
                parts.append(current)
                current = ""
                index += needle.count
                continue
            }
            current.append(character)
            index += 1
        }
        guard !parts.isEmpty else { return nil }
        parts.append(current)
        return parts
    }

    static func splitArguments(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for character in text {
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
            if character == "(" || character == "[" {
                depth += 1
            } else if character == ")" || character == "]" {
                depth = max(0, depth - 1)
            }
            if character == ",", depth == 0 {
                parts.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        parts.append(current)
        return parts
    }

    private static func unquote(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2, let first = value.first, let last = value.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func matches(_ characters: [Character], at index: Int, needle: [Character]) -> Bool {
        guard index + needle.count <= characters.count else { return false }
        for offset in 0..<needle.count where characters[index + offset] != needle[offset] { return false }
        return true
    }

    /// 顶层分隔（并集 `|`）
    static func splitTopLevel(_ text: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for character in text {
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
            if character == "[" || character == "(" {
                depth += 1
            } else if character == "]" || character == ")" {
                depth = max(0, depth - 1)
            } else if character == separator, depth == 0 {
                parts.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        parts.append(current)
        return parts
    }
}

// MARK: - 求值

enum XPathEvaluator {

    static func evaluate(_ steps: [XPathStep], context: HTMLNode) -> [Any] {
        var nodes: [HTMLNode] = [context]

        for step in steps {
            switch step.test {
            case .text:
                return textValues(step: step, nodes: nodes)
            case .attribute(let name):
                return attributeValues(step: step, name: name, nodes: nodes)
            case .name, .wildcard:
                nodes = selectElements(step: step, nodes: nodes)
                if nodes.isEmpty { return [] }
            }
        }

        return nodes.sorted { $0.documentIndex < $1.documentIndex }.map { $0 as Any }
    }

    // MARK: 元素步进

    private static func selectElements(step: XPathStep, nodes: [HTMLNode]) -> [HTMLNode] {
        var results: [HTMLNode] = []
        for context in nodes {
            var candidates: [HTMLNode]
            switch step.axis {
            case .child:
                candidates = context.elementChildren
            case .descendant:
                candidates = context.descendantElements
            }
            if case .name(let name) = step.test {
                candidates = candidates.filter { $0.tag == name }
            }
            if !step.predicates.isEmpty {
                candidates = applyPredicates(step.predicates, to: candidates)
            }
            results.append(contentsOf: candidates)
        }
        return results
    }

    /// 谓词按「同父节点分组」应用：XPath 的位置语义是每个父节点下重新计数
    static func applyPredicates(_ predicates: [XPathPredicate], to candidates: [HTMLNode]) -> [HTMLNode] {
        var current = candidates
        for predicate in predicates {
            var groups: [ObjectIdentifier: [HTMLNode]] = [:]
            var order: [ObjectIdentifier] = []
            for node in current {
                let key = ObjectIdentifier(node.parent ?? node)
                if groups[key] == nil { order.append(key) }
                groups[key, default: []].append(node)
            }
            var kept: [HTMLNode] = []
            for key in order {
                guard let group = groups[key] else { continue }
                for (offset, node) in group.enumerated()
                where matches(predicate, node: node, position: offset + 1, count: group.count) {
                    kept.append(node)
                }
            }
            current = kept
        }
        return current
    }

    static func matches(_ predicate: XPathPredicate, node: HTMLNode, position: Int, count: Int) -> Bool {
        switch predicate {
        case .position(let expected):
            return position == expected
        case .last(let offset):
            return position == count - offset
        case .existsAttribute(let name):
            return node.attribute(name) != nil
        case .missingAttribute(let name):
            return node.attribute(name) == nil
        case .attributeEquals(let name, let value):
            return node.attribute(name) == value
        case .attributeNotEquals(let name, let value):
            return node.attribute(name) != value
        case .attributeContains(let name, let value):
            guard let attribute = node.attribute(name) else { return false }
            return attribute.contains(value)
        case .attributeStartsWith(let name, let value):
            guard let attribute = node.attribute(name) else { return false }
            return attribute.hasPrefix(value)
        case .attributeEndsWith(let name, let value):
            guard let attribute = node.attribute(name) else { return false }
            return attribute.hasSuffix(value)
        case .hasText:
            for child in node.children where child.isText {
                if !child.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            }
            return false
        case .containsText(let value):
            return node.text().contains(value)
        case .startsWithText(let value):
            return node.text().hasPrefix(value)
        case .positionCompare(let op, let value):
            switch op {
            case ">": return position > value
            case "<": return position < value
            case ">=": return position >= value
            case "<=": return position <= value
            case "=": return position == value
            case "!=": return position != value
            default: return false
            }
        case .negate(let inner):
            return !matches(inner, node: node, position: position, count: count)
        case .all(let predicates):
            return predicates.allSatisfy { matches($0, node: node, position: position, count: count) }
        case .any(let predicates):
            return predicates.contains { matches($0, node: node, position: position, count: count) }
        }
    }

    // MARK: 文本 / 属性取值

    private static func textValues(step: XPathStep, nodes: [HTMLNode]) -> [Any] {
        var values: [String] = []
        for node in nodes {
            let textNodes: [HTMLNode]
            switch step.axis {
            case .descendant:
                textNodes = node.descendantTextNodes
            case .child:
                textNodes = node.children.filter { $0.isText }
            }
            var texts: [String] = []
            for textNode in textNodes {
                let value = HTMLText.collapseWhitespace(textNode.textContent)
                if !value.isEmpty { texts.append(value) }
            }
            if texts.isEmpty, node.isElement || node.isDocument {
                // 宽松兜底：`//div[@id=content]/text()` 在正文被 `<p>` 包住时仍然能出内容
                let fallback = node.text()
                if !fallback.isEmpty { texts = [fallback] }
            }
            values.append(contentsOf: texts)
        }
        return values.map { $0 as Any }
    }

    private static func attributeValues(step: XPathStep, name: String, nodes: [HTMLNode]) -> [Any] {
        var values: [String] = []
        for node in nodes {
            switch step.axis {
            case .child:
                // `/@href`：取上下文节点自身的属性
                if let value = node.attribute(name), !value.isEmpty { values.append(value) }
            case .descendant:
                // `//@href`：上下文节点及其所有后代的属性
                var elements: [HTMLNode] = []
                if node.isElement { elements.append(node) }
                elements.append(contentsOf: node.descendantElements)
                for element in elements {
                    if let value = element.attribute(name), !value.isEmpty { values.append(value) }
                }
            }
        }
        return values.map { $0 as Any }
    }
}
