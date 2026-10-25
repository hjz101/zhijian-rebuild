// EPUBImporter.swift — EPUB 解析：ZIP → container.xml → OPF(manifest/spine) → 章节文本
// 说明：MVP 先抽纯文本（保留段落），复用旧工程解析思路；图片/内嵌 CSS 的富文本渲染后续接 WKWebView。
import Foundation

enum EPUBImporter {
    struct ImportedBook {
        var title: String
        var author: String
        var chapters: [LocalChapterRecord]
    }

    struct RenderChapter: Codable, Hashable {
        var title: String
        var href: String   // ZIP 内完整路径（相对解包根目录）
    }

    enum EPUBError: LocalizedError {
        case noContainer, noPackage, noSpine, empty
        var errorDescription: String? {
            switch self {
            case .noContainer: return "EPUB 缺少 META-INF/container.xml"
            case .noPackage: return "EPUB 缺少 OPF 包文件"
            case .noSpine: return "EPUB 目录（spine）为空"
            case .empty: return "EPUB 没有可读正文"
            }
        }
    }

    private struct ManifestItem {
        var id: String
        var href: String
        var mediaType: String
        var properties: String
    }

    private struct Package {
        var title = ""
        var author = ""
        var manifest: [String: ManifestItem] = [:]
        var spine: [String] = []
        var navHref: String?
        var tocId: String?
        var opfDirectory = ""
    }

    static func parse(data: Data, fallbackTitle: String) throws -> ImportedBook {
        let zip = try ZipReader(data: data)
        guard let container = try? zip.text("META-INF/container.xml"),
              let opfPath = firstMatch(container, #"full-path=\"([^\"]+)\""#) else {
            throw EPUBError.noContainer
        }
        guard let opfText = try? zip.text(opfPath) else { throw EPUBError.noPackage }
        var package = try parsePackage(opfText, opfPath: opfPath)

        // 目录标题（nav 优先，ncx 兜底）
        var tocTitles: [String: String] = [:]
        if let navID = package.navHref, let nav = package.manifest[navID],
           let html = try? zip.text(itemPath(nav.href, opfDirectory: package.opfDirectory)) {
            tocTitles = parseNavTitles(html)
        }
        if tocTitles.isEmpty, let tocID = package.tocId, let toc = package.manifest[tocID],
           let ncx = try? zip.text(itemPath(toc.href, opfDirectory: package.opfDirectory)) {
            tocTitles = parseNCXTitles(ncx)
        }

        var chapters: [LocalChapterRecord] = []
        for idref in package.spine {
            guard let item = package.manifest[idref], item.mediaType.contains("html") else { continue }
            let path = itemPath(item.href, opfDirectory: package.opfDirectory)
            guard let html = try? zip.text(path) else { continue }
            var body = htmlToText(html).trimmingCharacters(in: .whitespacesAndNewlines)
            guard body.count > 20 else { continue }
            let key = item.href.components(separatedBy: "#").first ?? item.href
            let title = tocTitles[item.href] ?? tocTitles[key] ?? firstHeading(html) ?? "第\(chapters.count + 1)节"
            // 去掉正文开头与标题重复的行
            var lines = body.components(separatedBy: "\n")
            while let first = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
                  first.trimmingCharacters(in: .whitespaces) == title,
                  let idx = lines.firstIndex(of: first) {
                lines.remove(at: idx)
            }
            body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            chapters.append(LocalChapterRecord(index: chapters.count, title: title, text: body))
        }
        guard !chapters.isEmpty else { throw EPUBError.empty }

        let title = package.title.isEmpty ? fallbackTitle : package.title
        let author = package.author.isEmpty ? "未知作者" : package.author
        return ImportedBook(title: title, author: author, chapters: chapters)
    }

    /// 生成富文本渲染计划：spine 顺序 + 章节标题 + ZIP 内文件路径
    static func renderChapters(data: Data, fallbackTitle: String) throws -> (title: String, chapters: [RenderChapter]) {
        let zip = try ZipReader(data: data)
        guard let container = try? zip.text("META-INF/container.xml"),
              let opfPath = firstMatch(container, #"full-path=\"([^\"]+)\""#) else {
            throw EPUBError.noContainer
        }
        guard let opfText = try? zip.text(opfPath) else { throw EPUBError.noPackage }
        var package = try parsePackage(opfText, opfPath: opfPath)

        var tocTitles: [String: String] = [:]
        if let navID = package.navHref, let nav = package.manifest[navID],
           let html = try? zip.text(itemPath(nav.href, opfDirectory: package.opfDirectory)) {
            tocTitles = parseNavTitles(html)
        }
        if tocTitles.isEmpty, let tocID = package.tocId, let toc = package.manifest[tocID],
           let ncx = try? zip.text(itemPath(toc.href, opfDirectory: package.opfDirectory)) {
            tocTitles = parseNCXTitles(ncx)
        }

        var chapters: [RenderChapter] = []
        for idref in package.spine {
            guard let item = package.manifest[idref], item.mediaType.contains("html") else { continue }
            let path = itemPath(item.href, opfDirectory: package.opfDirectory)
            let key = item.href.components(separatedBy: "#").first ?? item.href
            let title = tocTitles[item.href] ?? tocTitles[key]
                ?? firstHeading((try? zip.text(path)) ?? "")
                ?? "第\(chapters.count + 1)节"
            chapters.append(RenderChapter(title: title, href: path))
        }
        guard !chapters.isEmpty else { throw EPUBError.empty }
        let title = package.title.isEmpty ? fallbackTitle : package.title
        return (title, chapters)
    }

    // MARK: - OPF

    private static func parsePackage(_ xml: String, opfPath: String) throws -> Package {
        var p = Package()
        p.opfDirectory = (opfPath as NSString).deletingLastPathComponent
        p.title = decodeEntities(stripTags(firstMatch(xml, #"<dc:title[^>]*>(.*?)</dc:title>"#) ?? ""))
        p.author = decodeEntities(stripTags(firstMatch(xml, #"<dc:creator[^>]*>(.*?)</dc:creator>"#) ?? ""))

        let itemRegex = try! NSRegularExpression(pattern: #"<item\b([^>]*)/?>"#)
        let ns = xml as NSString
        itemRegex.enumerateMatches(in: xml, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let attrs = ns.substring(with: m.range(at: 1))
            let id = attr(attrs, "id") ?? ""
            let href = attr(attrs, "href") ?? ""
            let mediaType = attr(attrs, "media-type") ?? ""
            let properties = attr(attrs, "properties") ?? ""
            guard !id.isEmpty, !href.isEmpty else { return }
            p.manifest[id] = ManifestItem(id: id, href: href, mediaType: mediaType, properties: properties)
            if properties.contains("nav") { p.navHref = id }
        }

        if let spineRange = xml.range(of: #"<spine[^>]*>(.*?)</spine>"#, options: .regularExpression) {
            let spineXML = String(xml[spineRange])
            if let tocId = firstMatch(spineXML, #"toc=\"([^\"]+)\""#) { p.tocId = tocId }
            let refRegex = try! NSRegularExpression(pattern: #"<itemref\b[^>]*idref=\"([^\"]+)\""#)
            let s = spineXML as NSString
            refRegex.enumerateMatches(in: spineXML, range: NSRange(location: 0, length: s.length)) { m, _, _ in
                guard let m else { return }
                p.spine.append(s.substring(with: m.range(at: 1)))
            }
        }
        guard !p.spine.isEmpty else { throw EPUBError.noSpine }
        return p
    }

    private static func attr(_ attrs: String, _ name: String) -> String? {
        firstMatch(attrs, name + #"=\"([^\"]*)\""#)
    }

    private static func itemPath(_ href: String, opfDirectory: String) -> String {
        let decoded = href.removingPercentEncoding ?? href
        if opfDirectory.isEmpty { return decoded }
        if decoded.hasPrefix("/") { return String(decoded.dropFirst()) }
        return opfDirectory + "/" + decoded
    }

    // MARK: - 目录

    private static func parseNavTitles(_ html: String) -> [String: String] {
        var map: [String: String] = [:]
        let regex = try! NSRegularExpression(pattern: #"<a\b[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>"#,
                                             options: [.dotMatchesLineSeparators, .caseInsensitive])
        let ns = html as NSString
        regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let href = ns.substring(with: m.range(at: 1))
            let text = decodeEntities(stripTags(ns.substring(with: m.range(at: 2))))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            map[href] = text
            if let key = href.components(separatedBy: "#").first { map[key] = text }
        }
        return map
    }

    private static func parseNCXTitles(_ ncx: String) -> [String: String] {
        var map: [String: String] = [:]
        let regex = try! NSRegularExpression(pattern: #"<navPoint\b.*?<text>(.*?)</text>.*?<content\b[^>]*src=\"([^\"]+)\""#,
                                             options: [.dotMatchesLineSeparators, .caseInsensitive])
        let ns = ncx as NSString
        regex.enumerateMatches(in: ncx, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let title = decodeEntities(stripTags(ns.substring(with: m.range(at: 1))))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let src = ns.substring(with: m.range(at: 2))
            guard !title.isEmpty else { return }
            map[src] = title
            if let base = src.components(separatedBy: "#").first { map[base] = title }
        }
        return map
    }

    // MARK: - HTML → 文本

    static func htmlToText(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: #"<head[\s\S]*?</head>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"</(p|div|h[1-6]|li|tr|blockquote)>"#, with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: #"[ \t\u{00A0}]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstHeading(_ html: String) -> String? {
        guard let raw = firstMatch(html, #"<h[1-3][^>]*>(.*?)</h[1-3]>"#) else { return nil }
        let text = decodeEntities(stripTags(raw)).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(40))
    }

    private static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    private static func firstMatch(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
              m.numberOfRanges > 1 else { return nil }
        return (text as NSString).substring(with: m.range(at: 1))
    }

    static func decodeEntities(_ s: String) -> String {
        var out = s
        let map = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                   "&#39;": "'", "&apos;": "'", "&mdash;": "—", "&ldquo;": "“", "&rdquo;": "”", "&hellip;": "…"]
        for (k, v) in map { out = out.replacingOccurrences(of: k, with: v) }
        if let regex = try? NSRegularExpression(pattern: #"&#(\d+);"#) {
            let ns = out as NSString
            for m in regex.matches(in: out, range: NSRange(location: 0, length: ns.length)).reversed() {
                let num = Int(ns.substring(with: m.range(at: 1))) ?? 0
                if let scalar = Unicode.Scalar(num) {
                    out = (out as NSString).replacingCharacters(in: m.range, with: String(Character(scalar)))
                }
            }
        }
        return out
    }
}
