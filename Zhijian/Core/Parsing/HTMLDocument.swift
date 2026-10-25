// HTMLDocument.swift —— 自研容错 HTML 解析器：词法 + 建树 + 实体解码 + 文本 / HTML 提取
//
// 设计目标（对齐 jsoup 在 Legado 里的实际用法，但零第三方依赖、不桥接 libxml2）：
// - 真实站点大量存在未闭合标签（`<li>` 省略 `</li>`、`<p>` 嵌套）、属性无引号、
//   大小写混写的标签名、script/style 里的 `<`，解析必须尽量不抛错、不丢内容；
// - 只做「书源规则需要的那部分 DOM」：element / text / 注释（跳过）、属性字典、
//   父子关系、文档序；不需要 CSS 渲染、不需要 DOM 修改 API；
// - 文本提取分三档：`text()`（阅读友好，块级元素与 `<br>` 产生换行）、`ownText()`
//   （仅直接文本）、`textNodes()`（直接文本节点列表），另有 `html()` 简化序列化。
import Foundation

// MARK: - 节点

/// 一个解析后的 HTML 节点。
///
/// 用引用类型承载父子关系（弱引用 parent，避免循环引用），因为 CSS/XPath 求值需要
/// 在节点集合之间反复比较身份（`===` / `ObjectIdentifier`）。
final class HTMLNode: CustomStringConvertible {

    enum Kind {
        case document
        case element
        /// 普通文本
        case text
        /// script / style 内的原始数据（不参与 text()/ownText()，序列化时不转义）
        case data
        case comment
    }

    let kind: Kind
    private(set) var tag: String
    private(set) var attributes: [String: String]
    private(set) var attributeOrder: [String]
    private(set) var textContent: String
    private(set) weak var parent: HTMLNode?
    private(set) var children: [HTMLNode] = []
    /// 在父节点 children 中的位置（含文本节点）
    private(set) var indexInParent: Int = 0
    /// 文档序（HTMLDocument 建树后统一赋值），用于跨父节点的结果排序
    fileprivate(set) var documentIndex: Int = 0

    init(kind: Kind, tag: String = "", text: String = "", attributes: [(String, String)] = []) {
        self.kind = kind
        self.tag = tag
        self.textContent = text
        var map: [String: String] = [:]
        var order: [String] = []
        for (name, value) in attributes {
            guard map[name] == nil else { continue }
            map[name] = value
            order.append(name)
        }
        self.attributes = map
        self.attributeOrder = order
    }

    // MARK: 基本判断

    var isElement: Bool { kind == .element }
    var isText: Bool { kind == .text }
    var isDocument: Bool { kind == .document }
    var isComment: Bool { kind == .comment }
    var isRawData: Bool { kind == .data }

    // MARK: 结构

    func append(_ child: HTMLNode) {
        child.parent = self
        child.indexInParent = children.count
        children.append(child)
    }

    /// 元素子节点（忽略文本/注释）
    var elementChildren: [HTMLNode] {
        children.filter { $0.isElement }
    }

    /// 所有后代元素（文档序、不含自身）
    var descendantElements: [HTMLNode] {
        var out: [HTMLNode] = []
        out.reserveCapacity(16)
        collectElements(into: &out)
        return out
    }

    private func collectElements(into out: inout [HTMLNode]) {
        for child in children where child.isElement {
            out.append(child)
            child.collectElements(into: &out)
        }
    }

    /// 所有后代文本节点（含相邻文本节点，不含 script/style 数据）
    var descendantTextNodes: [HTMLNode] {
        var out: [HTMLNode] = []
        collectTextNodes(into: &out)
        return out
    }

    private func collectTextNodes(into out: inout [HTMLNode]) {
        for child in children {
            switch child.kind {
            case .text: out.append(child)
            case .element: child.collectTextNodes(into: &out)
            default: break
            }
        }
    }

    // MARK: 属性

    /// 属性名大小写不敏感（解析时已统一小写）；同名属性保留第一次出现的值
    func attribute(_ name: String) -> String? {
        attributes[name.lowercased()]
    }

    func hasAttribute(_ name: String) -> Bool {
        attributes[name.lowercased()] != nil
    }

    var idValue: String? { attribute("id") }

    var classList: [String] {
        guard let raw = attribute("class") else { return [] }
        return raw.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\u{0C}" })
            .map(String.init)
    }

    // MARK: 兄弟节点

    /// 在所有元素兄弟中的序号（0 基，`:first-child` / `:eq(n)` 用）
    var elementSiblingIndex: Int {
        guard let parent else { return 0 }
        var index = 0
        for child in parent.children {
            if child === self { return index }
            if child.isElement { index += 1 }
        }
        return index
    }

    var previousElementSibling: HTMLNode? {
        guard let parent, let position = parent.children.firstIndex(where: { $0 === self }) else { return nil }
        var index = position - 1
        while index >= 0 {
            if parent.children[index].isElement { return parent.children[index] }
            index -= 1
        }
        return nil
    }

    var nextElementSibling: HTMLNode? {
        guard let parent, let position = parent.children.firstIndex(where: { $0 === self }) else { return nil }
        var index = position + 1
        while index < parent.children.count {
            if parent.children[index].isElement { return parent.children[index] }
            index += 1
        }
        return nil
    }

    // MARK: 文本提取

    /// 阅读友好文本：块级元素与 `<br>` 产生换行，行内空白折叠成单个空格。
    ///
    /// 注意：jsoup 的 `Element.text()` 把块级元素也折叠成空格；Legado 靠随后的
    /// HtmlFormatter 再补换行。我们直接在这里保留换行，正文规则（`div@text`）
    /// 拿到的就是可读的多行文本，不需要额外的格式化层。
    func text() -> String {
        var buffer = ""
        HTMLText.appendText(self, into: &buffer)
        return HTMLText.normalizeLines(buffer)
    }

    /// 仅直接子文本节点（jsoup `ownText()` 语义）
    func ownText() -> String {
        var buffer = ""
        for child in children {
            switch child.kind {
            case .text:
                buffer += child.textContent
            case .element where child.tag == "br":
                buffer += " "
            default:
                break
            }
        }
        return HTMLText.collapseWhitespace(buffer)
    }

    /// 直接文本节点列表（每个都做空白折叠，空串被丢弃）——对齐 Legado `@textNodes`
    func textNodes() -> [String] {
        var out: [String] = []
        for child in children where child.isText {
            let value = HTMLText.collapseWhitespace(child.textContent)
            if !value.isEmpty { out.append(value) }
        }
        return out
    }

    /// 原始文本（不折叠空白，含 script/style 数据）——空规则时的兜底
    func rawText() -> String {
        switch kind {
        case .text, .data:
            return textContent
        case .comment:
            return ""
        case .element, .document:
            var buffer = ""
            for child in children { buffer += child.rawText() }
            return buffer
        }
    }

    // MARK: HTML 序列化

    /// 简化 outerHTML（属性按源码顺序输出，文本转义，script/style 原样）
    func html() -> String {
        var buffer = ""
        HTMLText.appendHTML(self, into: &buffer, removingScriptAndStyle: false)
        return buffer
    }

    func innerHTML() -> String {
        switch kind {
        case .text, .data:
            return HTMLText.escapeText(textContent)
        case .comment:
            return textContent
        case .document, .element:
            var buffer = ""
            for child in children {
                HTMLText.appendHTML(child, into: &buffer, removingScriptAndStyle: false)
            }
            return buffer
        }
    }

    /// `@html` 用的序列化：先去掉 script/style（对齐 Legado `getResultLast("html")`）
    func htmlRemovingScriptAndStyle() -> String {
        var buffer = ""
        HTMLText.appendHTML(self, into: &buffer, removingScriptAndStyle: true)
        return buffer
    }

    var description: String { text() }
}

// MARK: - 文本 / 序列化工具

enum HTMLText {

    /// HTML 的 void 元素（没有结束标签）
    static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "keygen",
        "link", "meta", "param", "source", "track", "wbr"
    ]

    /// 块级元素（text() 时产生换行）
    static let blockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "body", "center", "dd", "details",
        "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer",
        "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "html",
        "legend", "li", "main", "menu", "nav", "ol", "p", "pre", "section", "summary",
        "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul"
    ]

    /// 内容按原始文本处理（不解析标签、不解码实体）的元素
    static let rawTextTags: Set<String> = ["script", "style"]

    /// 实体需要解码但内容不解析子标签的元素
    static let escapedTextTags: Set<String> = ["textarea", "title"]

    static func appendText(_ node: HTMLNode, into out: inout String) {
        switch node.kind {
        case .text:
            out += node.textContent
        case .data, .comment:
            break
        case .document:
            for child in node.children { appendText(child, into: &out) }
        case .element:
            let block = blockTags.contains(node.tag)
            if block || node.tag == "br" { out += "\n" }
            for child in node.children { appendText(child, into: &out) }
            if block { out += "\n" }
        }
    }

    static func appendHTML(_ node: HTMLNode, into out: inout String, removingScriptAndStyle: Bool) {
        switch node.kind {
        case .text:
            out += escapeText(node.textContent)
        case .data:
            out += node.textContent
        case .comment:
            out += "<!--\(node.textContent)-->"
        case .document:
            for child in node.children {
                appendHTML(child, into: &out, removingScriptAndStyle: removingScriptAndStyle)
            }
        case .element:
            if removingScriptAndStyle && (node.tag == "script" || node.tag == "style") { return }
            out += "<" + node.tag
            for name in node.attributeOrder {
                out += " " + name + "=\"" + escapeAttribute(node.attributes[name] ?? "") + "\""
            }
            out += ">"
            if !voidTags.contains(node.tag) {
                for child in node.children {
                    appendHTML(child, into: &out, removingScriptAndStyle: removingScriptAndStyle)
                }
                out += "</" + node.tag + ">"
            }
        }
    }

    /// 折叠空白（含换行）为单个空格并去首尾空白
    static func collapseWhitespace(_ text: String) -> String {
        var out = ""
        for character in text {
            if character.isWhitespace {
                if !out.isEmpty && out.last != " " { out.append(" ") }
            } else {
                out.append(character)
            }
        }
        while out.last == " " { out.removeLast() }
        return out
    }

    /// 保留 `\n` 作为段落分隔，行内空白折叠，丢弃空行
    static func normalizeLines(_ text: String) -> String {
        var lines: [String] = []
        var current = ""
        func flush() {
            while current.last == " " { current.removeLast() }
            if !current.isEmpty { lines.append(current) }
            current = ""
        }
        for character in text {
            if character.isNewline {
                flush()
            } else if character.isWhitespace {
                if !current.isEmpty && current.last != " " { current.append(" ") }
            } else {
                current.append(character)
            }
        }
        flush()
        return lines.joined(separator: "\n")
    }

    static func escapeText(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(character)
            }
        }
        return out
    }

    static func escapeAttribute(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(character)
            }
        }
        return out
    }
}

// MARK: - 实体解码

enum HTMLEntities {

    /// 常用命名实体（书源站点高频：空白、标点、书名号、货币符号等）
    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}",
        "shy": "\u{00AD}", "zwnj": "\u{200C}", "zwj": "\u{200D}",
        "copy": "\u{00A9}", "reg": "\u{00AE}", "trade": "\u{2122}", "deg": "\u{00B0}",
        "hellip": "\u{2026}", "mdash": "\u{2014}", "ndash": "\u{2013}", "middot": "\u{00B7}",
        "bull": "\u{2022}", "prime": "\u{2032}", "Prime": "\u{2033}", "permil": "\u{2030}",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "laquo": "\u{00AB}", "raquo": "\u{00BB}", "lsaquo": "\u{2039}", "rsaquo": "\u{203A}",
        "times": "\u{00D7}", "divide": "\u{00F7}", "plusmn": "\u{00B1}", "minus": "\u{2212}",
        "frac12": "\u{00BD}", "frac14": "\u{00BC}", "frac34": "\u{00BE}",
        "sup1": "\u{00B9}", "sup2": "\u{00B2}", "sup3": "\u{00B3}",
        "cent": "\u{00A2}", "pound": "\u{00A3}", "yen": "\u{00A5}", "euro": "\u{20AC}",
        "curren": "\u{00A4}", "sect": "\u{00A7}", "para": "\u{00B6}", "dagger": "\u{2020}",
        "Dagger": "\u{2021}", "iexcl": "\u{00A1}", "iquest": "\u{00BF}",
        "larr": "\u{2190}", "uarr": "\u{2191}", "rarr": "\u{2192}", "darr": "\u{2193}",
        "harr": "\u{2194}", "crarr": "\u{21B5}", "lArr": "\u{21D0}", "rArr": "\u{21D2}",
        "forall": "\u{2200}", "part": "\u{2202}", "exist": "\u{2203}", "empty": "\u{2205}",
        "nabla": "\u{2207}", "isin": "\u{2208}", "notin": "\u{2209}", "ni": "\u{220B}",
        "prod": "\u{220F}", "sum": "\u{2211}", "infin": "\u{221E}", "ang": "\u{2220}",
        "and": "\u{2227}", "or": "\u{2228}", "cap": "\u{2229}", "cup": "\u{222A}",
        "int": "\u{222B}", "there4": "\u{2234}", "sim": "\u{223C}", "cong": "\u{2245}",
        "asymp": "\u{2248}", "ne": "\u{2260}", "equiv": "\u{2261}", "le": "\u{2264}",
        "ge": "\u{2265}", "sub": "\u{2282}", "sup": "\u{2283}", "nsub": "\u{2284}",
        "spades": "\u{2660}", "clubs": "\u{2663}", "hearts": "\u{2665}", "diams": "\u{2666}",
        "loz": "\u{25CA}", "star": "\u{2606}", "starf": "\u{2605}", "check": "\u{2713}",
        "cross": "\u{2717}", "alpha": "\u{03B1}", "beta": "\u{03B2}", "gamma": "\u{03B3}",
        "delta": "\u{03B4}", "epsilon": "\u{03B5}", "lambda": "\u{03BB}", "mu": "\u{03BC}",
        "pi": "\u{03C0}", "sigma": "\u{03C3}", "omega": "\u{03C9}", "Omega": "\u{03A9}",
        "agrave": "\u{00E0}", "aacute": "\u{00E1}", "acirc": "\u{00E2}", "atilde": "\u{00E3}",
        "auml": "\u{00E4}", "aring": "\u{00E5}", "aelig": "\u{00E6}", "ccedil": "\u{00E7}",
        "egrave": "\u{00E8}", "eacute": "\u{00E9}", "ecirc": "\u{00EA}", "euml": "\u{00EB}",
        "igrave": "\u{00EC}", "iacute": "\u{00ED}", "icirc": "\u{00EE}", "iuml": "\u{00EF}",
        "ntilde": "\u{00F1}", "ograve": "\u{00F2}", "oacute": "\u{00F3}", "ocirc": "\u{00F4}",
        "otilde": "\u{00F5}", "ouml": "\u{00F6}", "oslash": "\u{00F8}", "ugrave": "\u{00F9}",
        "uacute": "\u{00FA}", "ucirc": "\u{00FB}", "uuml": "\u{00FC}", "yacute": "\u{00FD}",
        "yuml": "\u{00FF}", "szlig": "\u{00DF}", "micro": "\u{00B5}", "ordf": "\u{00AA}",
        "ordm": "\u{00BA}", "not": "\u{00AC}", "macr": "\u{00AF}", "acute": "\u{00B4}",
        "cedil": "\u{00B8}", "uml": "\u{00A8}", "brvbar": "\u{00A6}", "uml2": "\u{00A8}",
        "AElig": "\u{00C6}", "Ccedil": "\u{00C7}", "Eacute": "\u{00C9}", "Ntilde": "\u{00D1}",
        "Ouml": "\u{00D6}", "Uuml": "\u{00DC}", "Yacute": "\u{00DD}", "THORN": "\u{00DE}",
        "thorn": "\u{00FE}", "eth": "\u{00F0}", "ETH": "\u{00D0}"
    ]

    /// 把 `[range]` 范围内的 UTF-8 字节解码成字符串，并替换实体
    static func decode(_ bytes: [UInt8], range: Range<Int>) -> String {
        guard range.lowerBound < range.upperBound else { return "" }
        var hasAmpersand = false
        var cursor = range.lowerBound
        while cursor < range.upperBound {
            if bytes[cursor] == 0x26 { hasAmpersand = true; break }
            cursor += 1
        }
        if !hasAmpersand {
            return String(decoding: bytes[range], as: UTF8.self)
        }
        var out: [UInt8] = []
        out.reserveCapacity(range.count)
        var index = range.lowerBound
        while index < range.upperBound {
            if bytes[index] == 0x26, let entity = entity(at: index, bytes: bytes, limit: range.upperBound) {
                out.append(contentsOf: entity.text.utf8)
                index = entity.end
            } else {
                out.append(bytes[index])
                index += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return decode(Array(text.utf8), range: 0..<text.utf8.count)
    }

    private static func entity(at index: Int, bytes: [UInt8], limit: Int) -> (text: String, end: Int)? {
        var cursor = index + 1
        guard cursor < limit else { return nil }
        if bytes[cursor] == 0x23 { // '#'
            cursor += 1
            var hexadecimal = false
            if cursor < limit, bytes[cursor] == 0x78 || bytes[cursor] == 0x58 { // x / X
                hexadecimal = true
                cursor += 1
            }
            var value: UInt32 = 0
            var digits = 0
            while cursor < limit, bytes[cursor] != 0x3B { // ';'
                guard let digit = digitValue(bytes[cursor], hexadecimal: hexadecimal) else { return nil }
                value = value * UInt32(hexadecimal ? 16 : 10) + digit
                digits += 1
                if digits > 8 { return nil }
                cursor += 1
            }
            guard digits > 0, cursor < limit, bytes[cursor] == 0x3B else { return nil }
            cursor += 1
            if let scalar = Unicode.Scalar(value), !(0xD800...0xDFFF).contains(value) {
                var text = ""
                text.unicodeScalars.append(scalar)
                return (text, cursor)
            }
            return ("\u{FFFD}", cursor)
        }
        let nameStart = cursor
        while cursor < limit, bytes[cursor] != 0x3B, cursor - nameStart <= 32 { cursor += 1 }
        guard cursor < limit, bytes[cursor] == 0x3B, cursor > nameStart else { return nil }
        let name = String(decoding: bytes[nameStart..<cursor], as: UTF8.self)
        if let value = named[name] ?? named[name.lowercased()] {
            return (value, cursor + 1)
        }
        return nil
    }

    private static func digitValue(_ byte: UInt8, hexadecimal: Bool) -> UInt32? {
        if byte >= 0x30, byte <= 0x39 { return UInt32(byte - 0x30) }
        guard hexadecimal else { return nil }
        if byte >= 0x61, byte <= 0x66 { return UInt32(byte - 0x61 + 10) }
        if byte >= 0x41, byte <= 0x46 { return UInt32(byte - 0x41 + 10) }
        return nil
    }
}

// MARK: - 解析器

enum HTMLParser {

    static func parse(_ source: String) -> HTMLNode {
        let bytes = Array(source.utf8)
        let count = bytes.count
        let root = HTMLNode(kind: .document)
        var stack: [HTMLNode] = [root]
        var index = 0
        var textStart = 0

        func current() -> HTMLNode { stack[stack.count - 1] }

        func flushText(upTo end: Int) {
            guard end > textStart else { return }
            let decoded = HTMLEntities.decode(bytes, range: textStart..<end)
            if !decoded.isEmpty {
                current().append(HTMLNode(kind: .text, text: decoded))
            }
            textStart = end
        }

        while index < count {
            guard bytes[index] == 0x3C else { index += 1; continue } // '<'
            guard index + 1 < count else { index += 1; continue }
            let marker = bytes[index + 1]
            let startsTag = isAsciiLetter(marker) || marker == 0x2F /* / */ || marker == 0x21 /* ! */ || marker == 0x3F /* ? */
            guard startsTag else { index += 1; continue }

            flushText(upTo: index)

            // 注释 / DOCTYPE / 处理指令
            if marker == 0x21 || marker == 0x3F {
                if matches(bytes, at: index, needle: Array("<!--".utf8)) {
                    if let end = find(Array("-->".utf8), in: bytes, from: index + 4) {
                        let commentText = String(decoding: bytes[(index + 4)..<end], as: UTF8.self)
                        current().append(HTMLNode(kind: .comment, text: commentText))
                        index = end + 3
                    } else {
                        index = count
                    }
                } else if let end = find(Array(">".utf8), in: bytes, from: index + 2) {
                    index = end + 1
                } else {
                    index = count
                }
                textStart = index
                continue
            }

            // 结束标签
            if marker == 0x2F {
                let (name, afterName) = scanName(bytes, from: index + 2)
                guard !name.isEmpty, let end = find(Array(">".utf8), in: bytes, from: afterName) else {
                    index += 2
                    textStart = index
                    continue
                }
                if let position = stack.lastIndex(where: { $0.isElement && $0.tag == name }), position > 0 {
                    stack.removeSubrange(position...)
                }
                // 没有匹配的开放标签：忽略（容错）
                index = end + 1
                textStart = index
                continue
            }

            // 开始标签
            let (name, afterName) = scanName(bytes, from: index + 1)
            guard !name.isEmpty else {
                if let end = find(Array(">".utf8), in: bytes, from: index + 1) {
                    index = end + 1
                    textStart = index
                } else {
                    index = count
                }
                continue
            }

            let parsed = scanAttributes(bytes, from: afterName)
            index = parsed.next
            textStart = index

            // 隐式闭合（`<li>` / `<p>` / `<td>` 等）
            while stack.count > 1, let top = stack.last, top.isElement, impliesClose(open: top.tag, by: name) {
                stack.removeLast()
            }

            let element = HTMLNode(kind: .element, tag: name, attributes: parsed.attributes)
            current().append(element)

            if parsed.selfClosing || HTMLText.voidTags.contains(name) {
                continue
            }

            if HTMLText.rawTextTags.contains(name) || HTMLText.escapedTextTags.contains(name) {
                // script/style：内容原样；textarea/title：内容解码实体但不解析标签
                let closeStart = rawTextClosingIndex(name: name, bytes: bytes, from: index)
                let contentEnd = max(index, closeStart ?? count)
                let isRawData = HTMLText.rawTextTags.contains(name)
                let content = isRawData
                    ? String(decoding: bytes[index..<contentEnd], as: UTF8.self)
                    : HTMLEntities.decode(bytes, range: index..<contentEnd)
                if !content.isEmpty {
                    element.append(HTMLNode(kind: isRawData ? .data : .text, text: content))
                }
                if let closeStart {
                    if let end = find(Array(">".utf8), in: bytes, from: closeStart) {
                        index = end + 1
                    } else {
                        index = count
                    }
                } else {
                    index = count
                }
                textStart = index
                continue
            }

            stack.append(element)
        }

        flushText(upTo: count)
        return root
    }

    // MARK: 词法辅助

    static func isAsciiLetter(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
    }

    static func isAsciiDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
    }

    static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C
    }

    static func isNameByte(_ byte: UInt8) -> Bool {
        if isAsciiLetter(byte) || isAsciiDigit(byte) { return true }
        switch byte {
        case 0x2D, 0x5F, 0x3A, 0x2E: return true // - _ : .
        default: return byte >= 0x80
        }
    }

    private static func scanName(_ bytes: [UInt8], from start: Int) -> (name: String, next: Int) {
        var index = start
        while index < bytes.count, isNameByte(bytes[index]) { index += 1 }
        let name = String(decoding: bytes[start..<index], as: UTF8.self).lowercased()
        return (name, index)
    }

    private static func scanAttributes(_ bytes: [UInt8], from start: Int) -> (attributes: [(String, String)], selfClosing: Bool, next: Int) {
        var attributes: [(String, String)] = []
        var index = start
        var selfClosing = false
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x3E { // '>'
                index += 1
                break
            }
            if isWhitespace(byte) {
                index += 1
                continue
            }
            if byte == 0x2F { // '/'
                if index + 1 < bytes.count, bytes[index + 1] == 0x3E {
                    selfClosing = true
                    index += 2
                    break
                }
                index += 1
                continue
            }

            // 属性名
            let nameStart = index
            while index < bytes.count, !isAttributeNameTerminator(bytes[index]) { index += 1 }
            let name = String(decoding: bytes[nameStart..<index], as: UTF8.self).lowercased()
            while index < bytes.count, isWhitespace(bytes[index]) { index += 1 }

            var value = ""
            if index < bytes.count, bytes[index] == 0x3D { // '='
                index += 1
                while index < bytes.count, isWhitespace(bytes[index]) { index += 1 }
                if index < bytes.count, bytes[index] == 0x22 || bytes[index] == 0x27 {
                    let quote = bytes[index]
                    index += 1
                    let valueStart = index
                    while index < bytes.count, bytes[index] != quote { index += 1 }
                    value = HTMLEntities.decode(bytes, range: valueStart..<index)
                    if index < bytes.count { index += 1 }
                } else {
                    let valueStart = index
                    while index < bytes.count, !isWhitespace(bytes[index]), bytes[index] != 0x3E { index += 1 }
                    value = HTMLEntities.decode(bytes, range: valueStart..<index)
                }
            }

            if !name.isEmpty, !attributes.contains(where: { $0.0 == name }) {
                attributes.append((name, value))
            }
            if name.isEmpty { index += 1 } // 防止死循环
        }
        return (attributes, selfClosing, index)
    }

    private static func isAttributeNameTerminator(_ byte: UInt8) -> Bool {
        isWhitespace(byte) || byte == 0x3D || byte == 0x3E || byte == 0x2F
    }

    /// 找出 `</name` 的位置（大小写不敏感，且后面必须是空白或 `>`）
    private static func rawTextClosingIndex(name: String, bytes: [UInt8], from start: Int) -> Int? {
        let needle = Array(("</" + name).utf8)
        var index = start
        while index + needle.count <= bytes.count {
            if matchesIgnoreCase(bytes, at: index, needle: needle) {
                let after = index + needle.count
                if after >= bytes.count || isWhitespace(bytes[after]) || bytes[after] == 0x3E {
                    return index
                }
            }
            index += 1
        }
        return nil
    }

    private static func matches(_ bytes: [UInt8], at index: Int, needle: [UInt8]) -> Bool {
        guard index + needle.count <= bytes.count else { return false }
        for offset in 0..<needle.count where bytes[index + offset] != needle[offset] { return false }
        return true
    }

    private static func matchesIgnoreCase(_ bytes: [UInt8], at index: Int, needle: [UInt8]) -> Bool {
        guard index + needle.count <= bytes.count else { return false }
        for offset in 0..<needle.count {
            let left = lowercasedASCII(bytes[index + offset])
            let right = lowercasedASCII(needle[offset])
            if left != right { return false }
        }
        return true
    }

    private static func lowercasedASCII(_ byte: UInt8) -> UInt8 {
        (byte >= 0x41 && byte <= 0x5A) ? byte + 0x20 : byte
    }

    private static func find(_ needle: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard !needle.isEmpty else { return start }
        var index = max(0, start)
        while index + needle.count <= bytes.count {
            if matches(bytes, at: index, needle: needle) { return index }
            index += 1
        }
        return nil
    }

    // MARK: 隐式闭合

    private static let paragraphClosingTags: Set<String> = [
        "address", "article", "aside", "blockquote", "details", "div", "dl", "fieldset",
        "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
        "header", "hgroup", "hr", "li", "main", "menu", "nav", "ol", "p", "pre",
        "section", "table", "ul", "dd", "dt"
    ]

    private static func impliesClose(open: String, by new: String) -> Bool {
        switch open {
        case "p":
            return paragraphClosingTags.contains(new)
        case "li":
            return new == "li"
        case "dt", "dd":
            return new == "dt" || new == "dd"
        case "option":
            return new == "option" || new == "optgroup"
        case "thead", "tbody", "tfoot":
            return new == "thead" || new == "tbody" || new == "tfoot"
        case "tr":
            return new == "tr"
        case "td", "th":
            return new == "td" || new == "th" || new == "tr"
        default:
            return false
        }
    }
}

// MARK: - 文档

/// 一份解析完成的 HTML 文档。
///
/// 解析结果按原文做小容量缓存：一次搜索要对同一响应求值 10+ 条规则，
/// 缓存能把「每个字段重新 parse 一遍 100KB HTML」的成本摊掉。
final class HTMLDocument {

    let root: HTMLNode

    init(_ source: String) {
        root = HTMLParser.parse(source)
        assignDocumentOrder()
    }

    /// 按 CSS 选择器查询（文档根作为上下文，不包含 document 节点自身）
    func select(_ selector: String) -> [HTMLNode] {
        CSSSelector.select(selector, in: root)
    }

    private func assignDocumentOrder() {
        var counter = 0
        func walk(_ node: HTMLNode) {
            node.documentIndex = counter
            counter += 1
            for child in node.children { walk(child) }
        }
        walk(root)
    }

    // MARK: 缓存

    private struct CacheKey: Hashable {
        let count: Int
        let hash: Int
        let head: String
        let tail: String
    }

    private static let cacheLock = NSLock()
    private static var cache: [(key: CacheKey, document: HTMLDocument)] = []
    private static let cacheLimit = 6

    static func parse(_ source: String) -> HTMLDocument {
        let key = CacheKey(
            count: source.count,
            hash: source.hashValue,
            head: String(source.prefix(80)),
            tail: String(source.suffix(80))
        )
        cacheLock.lock()
        if let hit = cache.first(where: { $0.key == key }) {
            let document = hit.document
            cacheLock.unlock()
            return document
        }
        cacheLock.unlock()

        let document = HTMLDocument(source)

        cacheLock.lock()
        cache.append((key, document))
        if cache.count > cacheLimit { cache.removeFirst(cache.count - cacheLimit) }
        cacheLock.unlock()
        return document
    }

    /// 把任意输入转成可查询的上下文节点
    static func contextNodes(from input: Any) -> [HTMLNode] {
        if let node = input as? HTMLNode {
            return [node]
        }
        if let array = input as? [Any] {
            var nodes: [HTMLNode] = []
            for element in array {
                if let node = element as? HTMLNode {
                    nodes.append(node)
                }
            }
            return nodes
        }
        if let string = input as? String {
            return [parse(string).root]
        }
        return []
    }
}

// MARK: - jsoup 兼容：可变 DOM 操作（供 jsoup_bridge.js 的原生层使用）
//
// 书源里少数规则会通过 `document.select(...).first().text("新文本")` / `.append(...)`
// 修改 DOM 后再取结果。原生解析器默认只读，这里补上最小可变能力：
// 属性、文本、innerHTML、结构增删与克隆。所有操作只影响 HTMLParser.parse 出来的
// 独立文档（JsoupDOMStore 不走 HTMLDocument.parse 的缓存），不会污染规则缓存。

extension HTMLNode {

    func jsoupSetAttribute(_ name: String, _ value: String) {
        let key = name.lowercased()
        if attributes[key] == nil { attributeOrder.append(key) }
        attributes[key] = value
    }

    func jsoupRemoveAttribute(_ name: String) {
        let key = name.lowercased()
        attributes.removeValue(forKey: key)
        attributeOrder.removeAll { $0 == key }
    }

    func jsoupSetTagName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty { tag = trimmed }
    }

    func jsoupRefreshChildrenIndexes() {
        for (index, child) in children.enumerated() {
            child.indexInParent = index
        }
    }

    /// 清空子节点
    func jsoupEmpty() {
        for child in children { child.parent = nil }
        children.removeAll()
    }

    /// 用文本替换全部子节点（jsoup `Element.text(String)`）
    func jsoupSetText(_ text: String) {
        jsoupEmpty()
        let child = HTMLNode(kind: tag == "script" || tag == "style" ? .data : .text, text: text)
        append(child)
    }

    /// 用 HTML 片段替换全部子节点（jsoup `Element.html(String)`）
    func jsoupSetInnerHTML(_ html: String) {
        let parsedRoot = HTMLParser.parse(html)
        let body = parsedRoot.descendantElements.first { $0.tag == "body" } ?? parsedRoot
        let nodes = body.children
        jsoupEmpty()
        for node in nodes {
            node.parent = nil
            append(node)
        }
    }

    func jsoupAppendNodes(_ nodes: [HTMLNode]) {
        for node in nodes {
            node.removeFromParentIfNeeded()
            append(node)
        }
        jsoupRefreshDocumentOrder()
    }

    func jsoupPrependNodes(_ nodes: [HTMLNode]) {
        for (offset, node) in nodes.enumerated() {
            node.removeFromParentIfNeeded()
            node.parent = self
            children.insert(node, at: offset)
        }
        jsoupRefreshChildrenIndexes()
        jsoupRefreshDocumentOrder()
    }

    /// 在 `reference` 前插入；reference 为空或不是子节点时追加到末尾
    func jsoupInsertNodes(_ nodes: [HTMLNode], before reference: HTMLNode?) {
        guard let reference, let index = children.firstIndex(where: { $0 === reference }) else {
            jsoupAppendNodes(nodes)
            return
        }
        for (offset, node) in nodes.enumerated() {
            node.removeFromParentIfNeeded()
            node.parent = self
            children.insert(node, at: index + offset)
        }
        jsoupRefreshChildrenIndexes()
        jsoupRefreshDocumentOrder()
    }

    /// 在 `reference` 后插入；reference 为空或不是子节点时追加到末尾
    func jsoupInsertNodes(_ nodes: [HTMLNode], after reference: HTMLNode?) {
        guard let reference, let index = children.firstIndex(where: { $0 === reference }) else {
            jsoupAppendNodes(nodes)
            return
        }
        for (offset, node) in nodes.enumerated() {
            node.removeFromParentIfNeeded()
            node.parent = self
            children.insert(node, at: index + 1 + offset)
        }
        jsoupRefreshChildrenIndexes()
        jsoupRefreshDocumentOrder()
    }

    func jsoupRemoveFromParent() {
        removeFromParentIfNeeded()
        jsoupRefreshDocumentOrder()
    }

    private func removeFromParentIfNeeded() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        parent.jsoupRefreshChildrenIndexes()
        self.parent = nil
    }

    /// 克隆节点（浅/深）。返回的节点没有父节点，可直接 append。
    func jsoupClone(deep: Bool) -> HTMLNode {
        let copy = HTMLNode(kind: kind, tag: tag, text: textContent, attributes: attributeOrder.compactMap { name in
            attributes[name].map { (name, $0) }
        })
        if deep {
            for child in children { copy.append(child.jsoupClone(deep: true)) }
        }
        return copy
    }

    /// 变更后刷新文档序（XPath 结果排序依赖 documentIndex）
    func jsoupRefreshDocumentOrder() {
        var root = self
        while let parent = root.parent { root = parent }
        var counter = 0
        func walk(_ node: HTMLNode) {
            node.documentIndex = counter
            counter += 1
            for child in node.children { walk(child) }
        }
        walk(root)
    }
}
