// ReaderImageExtractor.swift — 从正文 HTML 中提取图片标记与 URL
import Foundation

struct ExtractedReaderImage: Codable, Hashable, Sendable {
    var url: String
    var alt: String = ""
    /// 在纯文本中的行号（0-based）
    var lineIndex: Int = 0
    /// qysg 图片 json 协议：headers / js / imageDecode
    var headers: [String: String] = [:]
    var js: String = ""
    var imageDecode: Bool = false
}

enum ReaderImageExtractor {
    /// 解析 `url,{json}`（qysg 协议）；返回 URL 与 JSON 字典。
    static func splitOptions(_ raw: String) -> (url: String, options: [String: Any]) {
        // 找到第一个 `,{`：逗号后是 JSON
        guard let range = raw.range(of: ",{") else { return (raw, [:]) }
        let url = String(raw[..<range.lowerBound])
        let jsonPart = String(raw[raw.index(after: range.lowerBound)...])
        // qysg 协议用单引号 JSON：转成双引号再解析（值内引号已由源保证）
        // 单引号 JSON → 双引号（值内无单引号；若有则此简单替换不适用，走容错分支）
        var normalized = jsonPart.replacingOccurrences(of: "'", with: "\"")
        guard let data = normalized.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (url, [:])
        }
        return (url, json)
    }

    /// 把正文中的 `<img>` 替换为占位符，并返回图片清单（按出现顺序）。
    static func extract(from html: String, baseURL: String) -> (text: String, images: [ExtractedReaderImage]) {
        guard html.contains("<img") || html.contains("<IMG") else {
            // 没有图片时仍要按 HTML 规则清洗标签，否则正文会带 <div>/<p> 原始标记
            return (HtmlFormatter.formatIfNeeded(html), [])
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
                // qysg 协议：`url,{'headers':{...},'js':'...','imageDecode':true}`
                let (pureURL, options) = Self.splitOptions(raw)
                let url = RuleURLResolver.resolve(base: baseURL, relative: pureURL)
                if !url.isEmpty, !url.hasPrefix("data:") {
                    let lineIndex = out.components(separatedBy: "\n").count - 1
                    var image = ExtractedReaderImage(url: url, alt: alt, lineIndex: lineIndex)
                    image.headers = options["headers"] as? [String: String] ?? [:]
                    image.js = (options["js"] as? String) ?? ""
                    image.imageDecode = (options["imageDecode"] as? Bool) ?? false
                    images.append(image)
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
