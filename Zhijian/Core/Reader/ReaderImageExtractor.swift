// ReaderImageExtractor.swift — 从正文 HTML 中提取图片标记与 URL
import Foundation

struct ExtractedReaderImage: Codable, Hashable, Sendable {
    var url: String
    var alt: String = ""
    /// 在纯文本中的行号（0-based）
    var lineIndex: Int = 0
}

enum ReaderImageExtractor {
    /// 把正文中的 `<img>` 替换为占位符，并返回图片清单（按出现顺序）。
    static func extract(from html: String, baseURL: String) -> (text: String, images: [ExtractedReaderImage]) {
        guard html.contains("<img") || html.contains("<IMG") else {
            return (html, [])
        }
        let document = HTMLDocument.parse(html)
        var images: [ExtractedReaderImage] = []
        var buffer = ""
        walk(document.root, into: &buffer, images: &images, baseURL: baseURL)
        let normalized = HtmlFormatter.format(buffer)
        return (normalized, images)
    }

    private static func walk(_ node: HTMLNode, into out: inout String,
                             images: inout [ExtractedReaderImage], baseURL: String) {
        switch node.kind {
        case .text:
            out += node.textContent
        case .data, .comment:
            break
        case .document:
            for child in node.children { walk(child, into: &out, images: &images, baseURL: baseURL) }
        case .element:
            let tag = node.tag.lowercased()
            if tag == "script" || tag == "style" { return }
            if tag == "img" {
                let raw = node.attribute("src") ?? node.attribute("data-src") ?? node.attribute("data-original") ?? ""
                let alt = (node.attribute("alt") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let url = RuleURLResolver.resolve(base: baseURL, relative: raw)
                if !url.isEmpty, !url.hasPrefix("data:") {
                    let lineIndex = out.components(separatedBy: "\n").count - 1
                    images.append(ExtractedReaderImage(url: url, alt: alt, lineIndex: lineIndex))
                    out += "\n[[IMG\(images.count - 1)]]\n"
                } else {
                    out += "\n[图片]\n"
                }
                return
            }
            if tag == "br" { out += "\n"; return }
            if tag == "pre" { out += "\n" + node.rawText() + "\n"; return }
            let block = HTMLText.blockTags.contains(tag)
            if block { out += "\n" }
            for child in node.children { walk(child, into: &out, images: &images, baseURL: baseURL) }
            if block { out += "\n" }
        }
    }
}
