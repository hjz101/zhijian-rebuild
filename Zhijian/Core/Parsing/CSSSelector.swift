// CSSSelector.swift —— Legado 书源用的 CSS 选择器子集 + 索引后缀（`.N` / `!N` / `[a,b]` / `[a:b:step]`）
//
// 覆盖 jsoup 在书源里最常见的写法：
// - 简单选择器：`tag`、`*`、`.class`、`#id`、`[attr]`、`[attr=v]`、`[attr~=v]`、
//   `[attr^=v]`、`[attr$=v]`、`[attr*=v]`、`[attr|=v]`（大小写不敏感属性名，可选 `i` 标志）；
// - 组合器：后代（空格）、子 `>`、相邻 `+`、兄弟 `~`、并集 `,`；
// - 伪类：`:first-child`、`:last-child`、`:only-child`、`:nth-child(an+b)`、
//   `:nth-last-child`、`:first-of-type`、`:last-of-type`、`:nth-of-type`、`:empty`、
//   `:not(sel)`、`:has(sel)`、`:contains(text)`、`:containsOwn(text)`、
//   `:eq(n)`、`:gt(n)`、`:lt(n)`（jsoup 语义：按元素兄弟序号，0 基）；
// - Legado 专有前缀：`class.x` / `tag.x` / `id.x` / `text.x` / `children`；
// - Legado 索引后缀：`.N`（第 N 个，含负数）、`!N`（排除第 N 个）、`[N]`、`[a,b]`、
//   `[start:end]`、`[start:end:step]`、`[!...]`（排除）；区间端点可省略、可为负。
//
// 说明：`!` 在 Legado 源码里是「排除」（AnalyzeByJSoup.ElementsSingle，`split == '!'` 走
// `removeAll`），不是「倒数第 N」。这里对齐真实书源行为；倒数用 `.N` 的负索引表达。
import Foundation

// MARK: - 选择器模型

enum CSSCombinator {
    case descendant
    case child
    case adjacent
    case sibling
}

enum CSSAttributeOperator {
    case exists
    case equals
    case includes   // ~=
    case dashMatch  // |=
    case prefix     // ^=
    case suffix     // $=
    case substring  // *=
}

struct CSSAttributeTest {
    var name: String
    var op: CSSAttributeOperator
    var value: String
    var caseInsensitive: Bool

    func matches(_ node: HTMLNode) -> Bool {
        guard let raw = node.attribute(name) else { return false }
        if op == .exists { return true }
        let left = caseInsensitive ? raw.lowercased() : raw
        let right = caseInsensitive ? value.lowercased() : value
        switch op {
        case .exists:
            return true
        case .equals:
            return left == right
        case .includes:
            return left.split(whereSeparator: { $0.isWhitespace }).contains { $0 == Substring(right) }
        case .dashMatch:
            return left == right || left.hasPrefix(right + "-")
        case .prefix:
            return left.hasPrefix(right)
        case .suffix:
            return left.hasSuffix(right)
        case .substring:
            return left.contains(right)
        }
    }
}

/// `an+b` 形式的序号表达式
struct CSSAnB {
    var a: Int
    var b: Int

    func matches(position: Int) -> Bool {
        if a == 0 { return position == b }
        let difference = position - b
        guard difference % a == 0 else { return false }
        return difference / a >= 0
    }
}

enum CSSPseudo {
    case firstChild
    case lastChild
    case onlyChild
    case nthChild(CSSAnB)
    case nthLastChild(CSSAnB)
    case firstOfType
    case lastOfType
    case nthOfType(CSSAnB)
    case empty
    case not([CSSComplex])
    case has([CSSComplex])
    case contains(String)
    case containsOwn(String)
    case eq(Int)
    case gt(Int)
    case lt(Int)
    case root

    func matches(_ node: HTMLNode) -> Bool {
        switch self {
        case .firstChild:
            return node.elementSiblingIndex == 0
        case .lastChild:
            guard let parent = node.parent else { return false }
            return node.elementSiblingIndex == parent.elementChildren.count - 1
        case .onlyChild:
            guard let parent = node.parent else { return false }
            return parent.elementChildren.count == 1
        case .nthChild(let expression):
            return expression.matches(position: node.elementSiblingIndex + 1)
        case .nthLastChild(let expression):
            guard let parent = node.parent else { return false }
            let count = parent.elementChildren.count
            return expression.matches(position: count - node.elementSiblingIndex)
        case .firstOfType:
            return typePosition(of: node) == 1
        case .lastOfType:
            guard let parent = node.parent else { return false }
            let siblings = parent.elementChildren.filter { $0.tag == node.tag }
            return siblings.last === node
        case .nthOfType(let expression):
            return expression.matches(position: typePosition(of: node))
        case .empty:
            for child in node.children {
                if child.isElement { return false }
                if child.isText, !child.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            }
            return true
        case .not(let selectors):
            for selector in selectors where CSSSelector.matches(selector, node: node) { return false }
            return true
        case .has(let selectors):
            for descendant in node.descendantElements {
                for selector in selectors where CSSSelector.matches(selector, node: descendant) { return true }
            }
            return false
        case .contains(let text):
            return node.text().range(of: text, options: .caseInsensitive) != nil
        case .containsOwn(let text):
            return node.ownText().range(of: text, options: .caseInsensitive) != nil
        case .eq(let index):
            return node.elementSiblingIndex == index
        case .gt(let index):
            return node.elementSiblingIndex > index
        case .lt(let index):
            return node.elementSiblingIndex < index
        case .root:
            return node.tag == "html" || node.parent?.isDocument == true
        }
    }

    private func typePosition(of node: HTMLNode) -> Int {
        guard let parent = node.parent else { return 1 }
        var position = 0
        for sibling in parent.children where sibling.isElement {
            if sibling.tag == node.tag { position += 1 }
            if sibling === node { return position }
        }
        return position
    }
}

struct CSSCompound {
    var tag: String?
    var ids: [String] = []
    var classes: [String] = []
    var attributes: [CSSAttributeTest] = []
    var pseudos: [CSSPseudo] = []

    func matches(_ node: HTMLNode) -> Bool {
        guard node.isElement else { return false }
        if let tag, tag != "*", node.tag != tag { return false }
        if !ids.isEmpty {
            guard let id = node.idValue else { return false }
            for expected in ids where id != expected { return false }
        }
        if !classes.isEmpty {
            var available = Set(node.classList)
            for expected in classes where !available.contains(expected) { return false }
            available.removeAll()
        }
        for attribute in attributes where !attribute.matches(node) { return false }
        for pseudo in pseudos where !pseudo.matches(node) { return false }
        return true
    }
}

struct CSSComplex {
    struct Part {
        var combinator: CSSCombinator
        var compound: CSSCompound
    }
    var parts: [Part]
}

// MARK: - 选择器引擎

enum CSSSelector {

    /// 在上下文节点内查询（含上下文自身，jsoup `Element.select` 语义）
    static func select(_ query: String, in context: HTMLNode) -> [HTMLNode] {
        let groups = parseList(query)
        guard !groups.isEmpty else { return [] }

        let candidates: [HTMLNode]
        if context.isElement {
            candidates = [context] + context.descendantElements
        } else {
            candidates = context.descendantElements
        }

        var results: [HTMLNode] = []
        var seen = Set<ObjectIdentifier>()
        for node in candidates {
            for group in groups where matches(group, node: node) {
                if seen.insert(ObjectIdentifier(node)).inserted { results.append(node) }
                break
            }
        }
        return results
    }

    /// 文档序匹配（右到左回溯祖先 / 兄弟）
    static func matches(_ complex: CSSComplex, node: HTMLNode) -> Bool {
        guard !complex.parts.isEmpty else { return false }
        return matches(complex.parts, index: complex.parts.count - 1, node: node)
    }

    private static func matches(_ parts: [CSSComplex.Part], index: Int, node: HTMLNode) -> Bool {
        guard parts[index].compound.matches(node) else { return false }
        if index == 0 { return true }
        switch parts[index].combinator {
        case .descendant:
            var ancestor = node.parent
            while let element = ancestor {
                if element.isElement, matches(parts, index: index - 1, node: element) { return true }
                ancestor = element.parent
            }
            return false
        case .child:
            guard let parent = node.parent, parent.isElement else { return false }
            return matches(parts, index: index - 1, node: parent)
        case .adjacent:
            guard let sibling = node.previousElementSibling else { return false }
            return matches(parts, index: index - 1, node: sibling)
        case .sibling:
            var sibling = node.previousElementSibling
            while let element = sibling {
                if matches(parts, index: index - 1, node: element) { return true }
                sibling = element.previousElementSibling
            }
            return false
        }
    }

    // MARK: Legado 前缀 + 索引

    /// 按 Legado 默认规则语义在上下文内取元素：
    /// 前缀（`class.` / `tag.` / `id.` / `text.` / `children`）→ CSS 查询 → 索引后缀筛选
    static func selectLegado(_ rule: String, in context: HTMLNode) -> [HTMLNode] {
        let parsed = LegadoSelectorIndex.parse(rule)
        let candidates = candidatesLegado(base: parsed.base, in: context)
        return LegadoSelectorIndex.apply(parsed, to: candidates)
    }

    private static func candidatesLegado(base: String, in context: HTMLNode) -> [HTMLNode] {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return context.elementChildren }

        let lowered = trimmed.lowercased()
        if lowered == "children" { return context.elementChildren }
        if lowered.hasPrefix("class.") {
            return select("." + String(trimmed.dropFirst("class.".count)), in: context)
        }
        if lowered.hasPrefix("tag.") {
            return select(String(trimmed.dropFirst("tag.".count)), in: context)
        }
        if lowered.hasPrefix("id.") {
            return select("#" + String(trimmed.dropFirst("id.".count)), in: context)
        }
        if lowered.hasPrefix("text.") {
            let needle = String(trimmed.dropFirst("text.".count)).lowercased()
            guard !needle.isEmpty else { return [] }
            let candidates = context.isElement ? [context] + context.descendantElements : context.descendantElements
            return candidates.filter { $0.ownText().lowercased().contains(needle) }
        }
        return select(trimmed, in: context)
    }

    // MARK: 解析

    static func parseList(_ query: String) -> [CSSComplex] {
        var groups: [CSSComplex] = []
        for part in splitTopLevel(query, separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let complex = parseComplex(trimmed) { groups.append(complex) }
        }
        return groups
    }

    private static func parseComplex(_ text: String) -> CSSComplex? {
        let characters = Array(text)
        var index = 0
        var parts: [CSSComplex.Part] = []
        var pendingCombinator: CSSCombinator = .descendant

        while index < characters.count {
            while index < characters.count, characters[index].isWhitespace {
                index += 1
            }
            guard index < characters.count else { break }
            let character = characters[index]
            if character == ">" || character == "+" || character == "~" {
                pendingCombinator = character == ">" ? .child : (character == "+" ? .adjacent : .sibling)
                index += 1
                continue
            }
            guard let (compound, next) = parseCompound(characters, from: index) else { return nil }
            index = next
            // 显式组合器优先；没有显式组合器时（中间可能隔了空白）按后代处理
            let combinator = parts.isEmpty ? CSSCombinator.descendant : pendingCombinator
            parts.append(CSSComplex.Part(combinator: combinator, compound: compound))
            pendingCombinator = .descendant
        }
        guard !parts.isEmpty else { return nil }
        return CSSComplex(parts: parts)
    }

    private static func parseCompound(_ characters: [Character], from start: Int) -> (CSSCompound, Int)? {
        var index = start
        var compound = CSSCompound()
        var consumed = false

        while index < characters.count {
            let character = characters[index]
            switch character {
            case "*":
                consumed = true
                index += 1
            case ".":
                guard let (name, next) = readIdentifier(characters, from: index + 1) else { return nil }
                compound.classes.append(name)
                index = next
                consumed = true
            case "#":
                guard let (name, next) = readIdentifier(characters, from: index + 1) else { return nil }
                compound.ids.append(name)
                index = next
                consumed = true
            case "[":
                guard let (test, next) = readAttributeTest(characters, from: index) else { return nil }
                compound.attributes.append(test)
                index = next
                consumed = true
            case ":":
                guard let (pseudo, next) = readPseudo(characters, from: index) else { return nil }
                compound.pseudos.append(pseudo)
                index = next
                consumed = true
            default:
                if isIdentifierStart(character) {
                    guard compound.tag == nil,
                          let (name, next) = readIdentifier(characters, from: index) else { return nil }
                    compound.tag = name.lowercased()
                    index = next
                    consumed = true
                } else {
                    return consumed ? (compound, index) : nil
                }
            }
        }
        return consumed ? (compound, index) : nil
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_" || character == "-" || character.unicodeScalars.first.map { $0.value > 0x7F } == true
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_"
            || character.unicodeScalars.first.map { $0.value > 0x7F } == true
    }

    private static func readIdentifier(_ characters: [Character], from start: Int) -> (String, Int)? {
        var index = start
        var name = ""
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count {
                name.append(characters[index + 1])
                index += 2
                continue
            }
            if isIdentifierCharacter(character) {
                name.append(character)
                index += 1
            } else {
                break
            }
        }
        guard !name.isEmpty else { return nil }
        return (name, index)
    }

    private static func readAttributeTest(_ characters: [Character], from start: Int) -> (CSSAttributeTest, Int)? {
        var index = start + 1 // '['
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard let (name, afterName) = readIdentifier(characters, from: index) else { return nil }
        index = afterName
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard index < characters.count else { return nil }

        if characters[index] == "]" {
            return (CSSAttributeTest(name: name.lowercased(), op: .exists, value: "", caseInsensitive: false), index + 1)
        }

        var op: CSSAttributeOperator
        let character = characters[index]
        if character == "=" {
            op = .equals
            index += 1
        } else if character == "~" || character == "|" || character == "^" || character == "$" || character == "*" {
            guard index + 1 < characters.count, characters[index + 1] == "=" else { return nil }
            switch character {
            case "~": op = .includes
            case "|": op = .dashMatch
            case "^": op = .prefix
            case "$": op = .suffix
            default: op = .substring
            }
            index += 2
        } else {
            return nil
        }

        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard index < characters.count else { return nil }

        var value = ""
        if characters[index] == "\"" || characters[index] == "'" {
            let quote = characters[index]
            index += 1
            while index < characters.count, characters[index] != quote {
                if characters[index] == "\\", index + 1 < characters.count {
                    value.append(characters[index + 1])
                    index += 2
                    continue
                }
                value.append(characters[index])
                index += 1
            }
            guard index < characters.count else { return nil }
            index += 1
        } else {
            let valueStart = index
            while index < characters.count, characters[index] != "]", !characters[index].isWhitespace {
                index += 1
            }
            value = String(characters[valueStart..<index])
        }

        while index < characters.count, characters[index].isWhitespace { index += 1 }
        var caseInsensitive = false
        if index < characters.count, characters[index] == "i" || characters[index] == "I" {
            caseInsensitive = true
            index += 1
        }
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard index < characters.count, characters[index] == "]" else { return nil }
        return (CSSAttributeTest(name: name.lowercased(), op: op, value: value, caseInsensitive: caseInsensitive), index + 1)
    }

    private static func readPseudo(_ characters: [Character], from start: Int) -> (CSSPseudo, Int)? {
        guard let (rawName, afterName) = readIdentifier(characters, from: start + 1) else { return nil }
        let name = rawName.lowercased()
        var index = afterName
        var argument: String?

        if index < characters.count, characters[index] == "(" {
            var depth = 0
            var quote: Character?
            var collected = ""
            var cursor = index
            while cursor < characters.count {
                let character = characters[cursor]
                if let activeQuote = quote {
                    collected.append(character)
                    if character == activeQuote { quote = nil }
                    cursor += 1
                    continue
                }
                if character == "\"" || character == "'" {
                    quote = character
                    collected.append(character)
                    cursor += 1
                    continue
                }
                if character == "(" {
                    depth += 1
                    if depth > 1 { collected.append(character) }
                    cursor += 1
                    continue
                }
                if character == ")" {
                    depth -= 1
                    if depth == 0 {
                        cursor += 1
                        break
                    }
                    collected.append(character)
                    cursor += 1
                    continue
                }
                collected.append(character)
                cursor += 1
            }
            guard depth == 0 else { return nil }
            argument = collected
            index = cursor
        }

        switch name {
        case "first-child", "first":
            return (.firstChild, index)
        case "last-child", "last":
            return (.lastChild, index)
        case "only-child":
            return (.onlyChild, index)
        case "nth-child":
            guard let argument, let expression = parseAnB(argument) else { return nil }
            return (.nthChild(expression), index)
        case "nth-last-child":
            guard let argument, let expression = parseAnB(argument) else { return nil }
            return (.nthLastChild(expression), index)
        case "first-of-type":
            return (.firstOfType, index)
        case "last-of-type":
            return (.lastOfType, index)
        case "nth-of-type":
            guard let argument, let expression = parseAnB(argument) else { return nil }
            return (.nthOfType(expression), index)
        case "empty":
            return (.empty, index)
        case "root":
            return (.root, index)
        case "not":
            guard let argument else { return nil }
            let selectors = parseList(argument)
            guard !selectors.isEmpty else { return nil }
            return (.not(selectors), index)
        case "has":
            guard let argument else { return nil }
            let selectors = parseList(argument)
            guard !selectors.isEmpty else { return nil }
            return (.has(selectors), index)
        case "contains":
            guard let argument else { return nil }
            return (.contains(unquote(argument)), index)
        case "containsown":
            guard let argument else { return nil }
            return (.containsOwn(unquote(argument)), index)
        case "eq":
            guard let argument, let value = Int(argument.trimmingCharacters(in: .whitespaces)) else { return nil }
            return (.eq(value), index)
        case "gt":
            guard let argument, let value = Int(argument.trimmingCharacters(in: .whitespaces)) else { return nil }
            return (.gt(value), index)
        case "lt":
            guard let argument, let value = Int(argument.trimmingCharacters(in: .whitespaces)) else { return nil }
            return (.lt(value), index)
        default:
            return nil
        }
    }

    private static func unquote(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, let last = value.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func parseAnB(_ raw: String) -> CSSAnB? {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if text == "odd" { return CSSAnB(a: 2, b: 1) }
        if text == "even" { return CSSAnB(a: 2, b: 0) }
        if let value = Int(text) { return CSSAnB(a: 0, b: value) }
        guard let nIndex = text.firstIndex(of: "n") else { return nil }
        let aPart = String(text[text.startIndex..<nIndex]).replacingOccurrences(of: " ", with: "")
        var bPart = String(text[text.index(after: nIndex)...]).replacingOccurrences(of: " ", with: "")
        if bPart.hasPrefix("+") { bPart.removeFirst() }
        let a: Int
        switch aPart {
        case "", "+": a = 1
        case "-": a = -1
        default:
            guard let value = Int(aPart) else { return nil }
            a = value
        }
        let b = bPart.isEmpty ? 0 : (Int(bPart) ?? 0)
        return CSSAnB(a: a, b: b)
    }

    static func splitTopLevel(_ text: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var square = 0
        var paren = 0
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
            if character == "[" {
                square += 1
            } else if character == "]" {
                square = max(0, square - 1)
            } else if character == "(" {
                paren += 1
            } else if character == ")" {
                paren = max(0, paren - 1)
            } else if character == separator, square == 0, paren == 0 {
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

// MARK: - Legado 索引后缀

/// Legado 选择器尾部的索引：
/// - `.N` / `.a:b:c`：选取（`AnalyzeByJSoup.ElementsSingle.split == '.'`）
/// - `!N` / `!a:b`：排除（`split == '!'`）
/// - `[N]`、`[a,b]`、`[start:end]`、`[start:end:step]`、`[!...]`：[] 索引写法
///
/// 索引 0 基；负数从尾部数（`-1` = 最后一个）。
enum LegadoSelectorIndex {

    enum Item {
        case single(Int)
        case range(Int?, Int?, Int) // start, end(nil = 最后一个), step
    }

    struct Parsed {
        var base: String
        var mode: Character?  // "." 选取 / "!" 排除 / nil 无索引
        var items: [Item]

        var hasIndex: Bool { mode != nil && !items.isEmpty }
    }

    /// 拆出「选择器本体 + 索引」
    static func parse(_ rule: String) -> Parsed {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Parsed(base: "", mode: nil, items: []) }

        if trimmed.hasSuffix("]"), let parsed = parseBracketStyle(trimmed) {
            return parsed
        }
        if let parsed = parseLegacyStyle(trimmed) {
            return parsed
        }
        return Parsed(base: trimmed, mode: nil, items: [])
    }

    private static func parseBracketStyle(_ rule: String) -> Parsed? {
        // 找到最后一个未被引号包裹的 '['（从尾部向前，遇到 ']' 记深度）
        var quote: Character?
        var depth = 0
        var open: String.Index?
        var index = rule.endIndex
        while index > rule.startIndex {
            index = rule.index(before: index)
            let character = rule[index]
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character == "]" {
                depth += 1
            } else if character == "[" {
                depth -= 1
                if depth == 0 {
                    open = index
                    break
                }
            }
        }
        guard let open else { return nil }
        let inner = String(rule[rule.index(after: open)..<rule.index(before: rule.endIndex)])
        guard let parsedItems = parseIndexItems(inner, allowRanges: true) else { return nil }

        var base = String(rule[rule.startIndex..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix(".") { base.removeLast() }
        let mode: Character = parsedItems.excluded ? "!" : "."
        return Parsed(base: base, mode: mode, items: parsedItems.items)
    }

    private static func parseLegacyStyle(_ rule: String) -> Parsed? {
        guard let separatorIndex = lastLegacySeparator(in: rule) else { return nil }
        let suffix = String(rule[rule.index(after: separatorIndex)...]).replacingOccurrences(of: " ", with: "")
        // 阅读原版写法里 `:` 分隔的是「多个独立索引」，不是区间（区间只在 `[...]` 里）
        var items: [Item] = []
        for piece in suffix.split(separator: ":", omittingEmptySubsequences: false) {
            guard let value = Int(piece) else { return nil }
            items.append(.single(value))
        }
        guard !items.isEmpty else { return nil }
        let base = String(rule[rule.startIndex..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return Parsed(base: base, mode: rule[separatorIndex], items: items)
    }

    /// 从尾部找 `.` 或 `!`，其后的内容必须全部是 `数字(:数字)*`
    private static func lastLegacySeparator(in rule: String) -> String.Index? {
        var index = rule.endIndex
        while index > rule.startIndex {
            index = rule.index(before: index)
            let character = rule[index]
            if character == "." || character == "!" {
                let suffix = String(rule[rule.index(after: index)...]).replacingOccurrences(of: " ", with: "")
                if !suffix.isEmpty, suffix.range(of: "^[-0-9]+(:[-0-9]+)*$", options: .regularExpression) != nil {
                    return index
                }
                if suffix.isEmpty { return nil }
            }
        }
        return nil
    }

    /// 解析索引内容：`0`、`-1`、`1,2`、`0:5`、`1:10:2`、`!0`（排除）
    private static func parseIndexItems(_ raw: String, allowRanges: Bool) -> (items: [Item], excluded: Bool)? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var excluded = false
        if text.hasPrefix("!") {
            excluded = true
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty else { return nil }
        // 只允许数字 / 负号 / 冒号 / 逗号 / 空格
        guard text.range(of: "^[-0-9:, ]+$", options: .regularExpression) != nil,
              text.range(of: "[0-9]", options: .regularExpression) != nil else { return nil }

        var items: [Item] = []
        for piece in text.split(separator: ",") {
            let token = piece.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty else { return nil }
            if allowRanges, token.contains(":") {
                let pieces = token.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
                guard pieces.count <= 3 else { return nil }
                var values: [Int?] = pieces.map { $0.isEmpty ? nil : Int($0) }
                while values.count < 2 { values.append(nil) }
                let start = values[0]
                let end = values[1]
                let step = values.count > 2 ? (values[2] ?? 1) : 1
                items.append(.range(start, end, step))
            } else {
                guard let value = Int(token) else { return nil }
                items.append(.single(value))
            }
        }
        guard !items.isEmpty else { return nil }
        return (items, excluded)
    }

    /// 把索引套到元素列表上（对齐 AnalyzeByJSoup 的越界 / 反向 / 排除逻辑）
    static func apply(_ parsed: Parsed, to nodes: [HTMLNode]) -> [HTMLNode] {
        guard parsed.hasIndex else { return nodes }
        let count = nodes.count
        guard count > 0 else { return [] }

        var selected: Set<Int> = []
        var ordered: [Int] = []

        func add(_ index: Int) {
            guard index >= 0, index < count else { return }
            if selected.insert(index).inserted { ordered.append(index) }
        }

        for item in parsed.items {
            switch item {
            case .single(let rawIndex):
                if rawIndex >= 0, rawIndex < count {
                    add(rawIndex)
                } else if rawIndex < 0, -rawIndex <= count {
                    add(rawIndex + count)
                }
            case .range(let startRaw, let endRaw, let stepRaw):
                var start = startRaw ?? 0
                if start < 0 { start += count }
                var end = endRaw ?? (count - 1)
                if end < 0 { end += count }
                if (start < 0 && end < 0) || (start >= count && end >= count) { continue }
                start = min(max(start, 0), count - 1)
                end = min(max(end, 0), count - 1)
                if start == end || stepRaw >= count {
                    add(start)
                    continue
                }
                let step: Int
                if stepRaw > 0 {
                    step = stepRaw
                } else if -stepRaw < count {
                    step = stepRaw + count
                } else {
                    step = 1
                }
                if step == 0 {
                    add(start)
                    continue
                }
                let stride = abs(step)
                if end > start {
                    var position = start
                    while position <= end {
                        add(position)
                        position += stride
                    }
                } else {
                    var position = start
                    while position >= end {
                        add(position)
                        position -= stride
                    }
                }
            }
        }

        if parsed.mode == "!" {
            let excluded = Set(ordered)
            return nodes.enumerated().filter { !excluded.contains($0.offset) }.map { $0.element }
        }
        return ordered.map { nodes[$0] }
    }
}
