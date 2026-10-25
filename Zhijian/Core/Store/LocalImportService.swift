// LocalImportService.swift — 本地 TXT 导入、编码探测与分章（Lead 维护）
import Foundation
import UIKit
import PDFKit

@MainActor
final class LocalImportService {
    static let shared = LocalImportService()

    private let chapterPattern = try! NSRegularExpression(
        pattern: #"(?m)^\s*(第[0-9零一二三四五六七八九十百千万两]+[章回节卷篇][^\n]{0,40})\s*$"#,
        options: []
    )
    private let volumePattern = try! NSRegularExpression(
        pattern: #"(?m)^\s*(第[0-9零一二三四五六七八九十百千万两]+[卷部][^\n]{0,40})\s*$"#,
        options: []
    )

    func importTXT(url: URL, into store: BookStore) throws -> Book {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let text = Self.decode(data)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.empty }

        let title = url.deletingPathExtension().lastPathComponent
        let chapters = Self.splitChapters(trimmed, pattern: chapterPattern)
        let bookId = "local-" + UUID().uuidString
        let records = chapters.enumerated().map { i, c in
            LocalChapterRecord(index: i, title: c.title, text: c.text)
        }
        LocalLibrary.shared.save(LocalBookRecord(bookId: bookId, chapters: records))

        var book = Book.local(title: title, author: "本地导入", fileName: url.lastPathComponent)
        book.id = bookId
        book.totalChapters = records.count
        book.lastChapter = records.last?.title
        store.add(book)
        return book
    }

    func importEPUB(url: URL, into store: BookStore) throws -> Book {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let parsed = try EPUBImporter.parse(data: data, fallbackTitle: url.deletingPathExtension().lastPathComponent)
        let bookId = "epub-" + UUID().uuidString
        LocalLibrary.shared.save(LocalBookRecord(bookId: bookId, chapters: parsed.chapters))
        // 保存原始 EPUB 并解包，供富文本阅读使用；失败则回退纯文本。
        try? EPUBContentStore.shared.prepare(bookId: bookId, data: data)

        var book = Book.local(title: parsed.title, author: parsed.author, fileName: url.lastPathComponent)
        book.id = bookId
        book.totalChapters = parsed.chapters.count
        book.lastChapter = parsed.chapters.last?.title
        store.add(book)
        return book
    }

    func importManga(url: URL, into store: BookStore) throws -> Book {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let zip = try ZipReader(data: data)
        var entries: [(String, Data)] = []
        for name in zip.fileNames {
            let ext = (name as NSString).pathExtension.lowercased()
            guard MangaLibrary.imageExtensions.contains(ext) else { continue }
            guard let payload = try? zip.read(name), !payload.isEmpty else { continue }
            entries.append((name, payload))
        }
        entries.sort { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
        guard !entries.isEmpty else { throw ImportError.empty }

        let bookId = "manga-" + UUID().uuidString
        let urls = try MangaLibrary.shared.save(entries: entries, bookId: bookId)
        var book = Book.local(title: url.deletingPathExtension().lastPathComponent,
                              author: "漫画",
                              fileName: url.lastPathComponent)
        book.id = bookId
        book.totalChapters = urls.count
        book.lastChapter = "共 \(urls.count) 页"
        store.add(book)
        return book
    }

    /// P2-05：RAR / 7z 导入（自动识别：纯图片 → 漫画；单 txt → TXT；内含 epub → EPUB）。
    func importArchive(url: URL, into store: BookStore) throws -> Book {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let entries = try ArchiveReader.list(data: data)
        guard !entries.isEmpty else { throw ImportError.empty }

        let imageExts = MangaLibrary.imageExtensions
        let images = entries.filter { imageExts.contains(($0.name as NSString).pathExtension.lowercased()) }
        let texts = entries.filter { $0.name.lowercased().hasSuffix(".txt") }
        let epubs = entries.filter { $0.name.lowercased().hasSuffix(".epub") }

        if images.count >= 2 {
            var payloads: [(String, Data)] = []
            for entry in images.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
                if let entryData = try? ArchiveReader.read(data: data, entry: entry.name) {
                    payloads.append((entry.name, entryData))
                }
            }
            guard !payloads.isEmpty else { throw ImportError.empty }
            let bookId = "manga-" + UUID().uuidString
            let urls = try MangaLibrary.shared.save(entries: payloads, bookId: bookId)
            var book = Book.local(title: url.deletingPathExtension().lastPathComponent,
                                  author: "漫画",
                                  fileName: url.lastPathComponent)
            book.id = bookId
            book.totalChapters = urls.count
            book.lastChapter = "共 \(urls.count) 页"
            store.add(book)
            return book
        }

        if let txt = texts.first {
            let payload = try ArchiveReader.read(data: data, entry: txt.name)
            let text = Self.decode(payload)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ImportError.empty }
            let title = url.deletingPathExtension().lastPathComponent
            let chapters = Self.splitChapters(trimmed, pattern: chapterPattern)
            let bookId = "local-" + UUID().uuidString
            let records = chapters.enumerated().map { i, c in
                LocalChapterRecord(index: i, title: c.title, text: c.text)
            }
            LocalLibrary.shared.save(LocalBookRecord(bookId: bookId, chapters: records))
            var book = Book.local(title: title, author: "本地导入", fileName: url.lastPathComponent)
            book.id = bookId
            book.totalChapters = records.count
            book.lastChapter = records.last?.title
            store.add(book)
            return book
        }

        if let epub = epubs.first {
            let payload = try ArchiveReader.read(data: data, entry: epub.name)
            let parsed = try EPUBImporter.parse(data: payload, fallbackTitle: url.deletingPathExtension().lastPathComponent)
            let bookId = "epub-" + UUID().uuidString
            LocalLibrary.shared.save(LocalBookRecord(bookId: bookId, chapters: parsed.chapters))
            try? EPUBContentStore.shared.prepare(bookId: bookId, data: payload)
            var book = Book.local(title: parsed.title, author: parsed.author, fileName: url.lastPathComponent)
            book.id = bookId
            book.totalChapters = parsed.chapters.count
            book.lastChapter = parsed.chapters.last?.title
            store.add(book)
            return book
        }

        throw ImportError.unsupported("压缩包内没有可识别的 TXT / EPUB / 图片")
    }

    func importPDF(url: URL, into store: BookStore) throws -> Book {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw ImportError.empty
        }
        let bookId = "pdf-" + UUID().uuidString
        try PDFLibrary.shared.save(data: data, bookId: bookId)

        var book = Book.local(title: url.deletingPathExtension().lastPathComponent,
                              author: document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String ?? "PDF 文档",
                              fileName: url.lastPathComponent)
        book.id = bookId
        book.totalChapters = document.pageCount
        book.lastChapter = "共 \(document.pageCount) 页"
        store.add(book)
        return book
    }

    // MARK: - 分章

    struct SplitChapter { var title: String; var text: String }

    static func splitChapters(_ text: String, pattern: NSRegularExpression) -> [SplitChapter] {
        let ns = text as NSString
        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 2 else {
            // 无章节标题：按 6000 字切块
            return chunk(text, size: 6000)
        }
        var out: [SplitChapter] = []
        if matches[0].range.location > 0 {
            let preface = ns.substring(to: matches[0].range.location).trimmingCharacters(in: .whitespacesAndNewlines)
            if !preface.isEmpty { out.append(.init(title: "前言", text: preface)) }
        }
        for (i, m) in matches.enumerated() {
            let start = m.range.location
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            guard end > start else { continue }
            let block = ns.substring(with: NSRange(location: start, length: end - start))
            let lines = block.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            let title = lines.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "第\(i + 1)章"
            let body = lines.count > 1 ? String(lines[1]) : ""
            out.append(.init(title: title, text: body.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return out.isEmpty ? chunk(text, size: 6000) : out
    }

    private static func chunk(_ text: String, size: Int) -> [SplitChapter] {
        var out: [SplitChapter] = []
        var idx = text.startIndex
        var i = 1
        while idx < text.endIndex {
            let end = text.index(idx, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            out.append(.init(title: "第\(i)节", text: String(text[idx..<end])))
            idx = end; i += 1
        }
        return out
    }

    // MARK: - 编码

    static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8), !s.contains("\u{FFFD}") { return s }
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: gb)) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    enum ImportError: LocalizedError {
        case empty
        case unsupported(String)
        var errorDescription: String? {
            switch self {
            case .empty: return "文件内容为空"
            case .unsupported(let detail): return detail
            }
        }
    }
}
