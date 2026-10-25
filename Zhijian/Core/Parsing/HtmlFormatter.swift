// HtmlFormatter.swift —— 把 HTML 片段转成阅读器可用的纯文本
//
// 书源的正文规则经常写成 `@html` / `@all` / `div#content`（Legado 侧输出的是 outerHtml），
// 而本项目的阅读器只渲染纯文本。Legado 在 BookContent 里用 HtmlFormatter.formatKeepImg
// 再清洗一遍，这里补上同等职责的轻量实现：
// - 块级元素（p/div/br/li/h1-h6/tr/td/table/blockquote…）产生换行，行内空白折叠；
// - 丢弃 script/style/注释/所有属性；
// - 实体解码（复用 HTMLDocument 的解析器，`&nbsp;` 归一成空格）；
// - 图片默认丢弃，`keepImages: true` 时输出 alt 文本或 `[图片]`；
// - `<pre>` / `<blockquote>` 等结构保留内部文本与换行；
// - 连续空行合并、首尾空白裁剪。
//
// 对「已经是纯文本」的输入直接原样返回（只做 CRLF 归一），避免二次格式化破坏
// `@text` / `@textNodes` 的结果。
import Foundation

enum HtmlFormatter {

    /// 图片占位符（阅读器是纯文本，默认不保留图片）
    static let imagePlaceholder = "[图片]"

    // MARK: 对外入口

    /// HTML → 纯文本；输入不含标签时原样返回（只归一换行符）
    static func format(_ text: String, keepImages: Bool = false) -> String {
        guard containsHTMLTags(text) else { return normalizePlainText(text) }
        let document = HTMLDocument.parse(text)
        var buffer = ""
        appendText(document.root, into: &buffer, keepImages: keepImages)
        return normalize(buffer)
    }

    /// 规则结果需要清洗时才格式化（已经是纯文本则原样返回）
    static func formatIfNeeded(_ text: String, keepImages: Bool = false) -> String {
        guard containsHTMLTags(text) else { return text }
        return format(text, keepImages: keepImages)
    }

    /// 标题清洗：先按正文格式化，再压成单行
    static func formatTitle(_ text: String) -> String {
        let formatted = formatIfNeeded(text)
        var single = ""
        for character in formatted {
            if character.isNewline {
                if !single.isEmpty, single.last != " " { single.append(" ") }
            } else {
                single.append(character)
            }
        }
        return HTMLText.collapseWhitespace(single)
    }

    /// 是否含有 HTML 标签（`<tag ...>` / `</tag>` / `<br/>`；`a < b` 这种不算）
    static func containsHTMLTags(_ text: String) -> Bool {
        guard text.contains("<") else { return false }
        // 只剩注释的片段也要走解析（解析器会丢弃注释）
        if text.contains("<!--") { return true }
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            if characters[index] == "<" {
                var cursor = index + 1
                if cursor < characters.count,
                   characters[cursor] == "/" || characters[cursor] == "!" || characters[cursor] == "?" {
                    cursor += 1
                }
                if cursor < characters.count, characters[cursor].isLetter {
                    var probe = cursor
                    var steps = 0
                    while probe < characters.count, steps < 2000 {
                        if characters[probe] == ">" { return true }
                        probe += 1
                        steps += 1
                    }
                }
            }
            index += 1
        }
        return false
    }

    // MARK: 遍历

    private static func appendText(_ node: HTMLNode, into out: inout String, keepImages: Bool) {
        switch node.kind {
        case .text:
            out += node.textContent
        case .data, .comment:
            // script / style / 注释一律丢弃
            break
        case .document:
            for child in node.children {
                appendText(child, into: &out, keepImages: keepImages)
            }
        case .element:
            let tag = node.tag
            if tag == "script" || tag == "style" {
                return
            }
            if tag == "br" {
                out += "\n"
                return
            }
            if tag == "img" {
                if keepImages {
                    let alt = (node.attribute("alt") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    out += alt.isEmpty ? imagePlaceholder : alt
                }
                return
            }
            if tag == "hr" {
                out += "\n"
                return
            }
            // pre 保留内部换行与缩进（代码块 / 部分站点正文）
            if tag == "pre" {
                out += "\n" + node.rawText() + "\n"
                return
            }
            let block = HTMLText.blockTags.contains(tag)
            if block { out += "\n" }
            for child in node.children {
                appendText(child, into: &out, keepImages: keepImages)
            }
            if block { out += "\n" }
        }
    }

    // MARK: 空白归一

    /// 每行内部空白折叠成单空格、去行首尾空白、丢弃空行（等价「合并多余空行」）
    private static func normalize(_ text: String) -> String {
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
                if !current.isEmpty, current.last != " " { current.append(" ") }
            } else {
                current.append(character)
            }
        }
        flush()
        return lines.joined(separator: "\n")
    }

    /// 纯文本输入：只做 CRLF 归一与行尾空白裁剪，不改动内容结构
    private static func normalizePlainText(_ text: String) -> String {
        // 注意：Swift 里 "\r\n" 是一个 Character（扩展字形簇），不能用 text.contains("\r") 判断
        guard text.unicodeScalars.contains("\r") else { return text }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
