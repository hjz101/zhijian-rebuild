// EPUBContentStore.swift — EPUB 原始包保存、解包与渲染清单（富文本阅读用）
import Foundation

struct EPUBManifestFile: Codable, Hashable {
    var bookId: String
    var chapters: [EPUBImporter.RenderChapter]
}

@MainActor
final class EPUBContentStore {
    static let shared = EPUBContentStore()

    private let base: URL = {
        let dir = AppData.root.appendingPathComponent("EPUB", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private let fm = FileManager.default

    private init() {}

    func bookDirectory(_ bookId: String) -> URL {
        base.appendingPathComponent(bookId, isDirectory: true)
    }

    func epubURL(_ bookId: String) -> URL {
        base.appendingPathComponent(bookId + ".epub")
    }

    func manifestURL(_ bookId: String) -> URL {
        bookDirectory(bookId).appendingPathComponent("manifest.json")
    }

    func hasManifest(bookId: String) -> Bool {
        fm.fileExists(atPath: manifestURL(bookId).path)
    }

    func manifest(bookId: String) -> EPUBManifestFile? {
        guard let data = try? Data(contentsOf: manifestURL(bookId)) else { return nil }
        return try? JSONDecoder().decode(EPUBManifestFile.self, from: data)
    }

    func chapterURL(bookId: String, href: String) -> URL? {
        let root = bookDirectory(bookId).standardizedFileURL
        let url = root.appendingPathComponent(href).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/"), fm.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func rootURL(bookId: String) -> URL { bookDirectory(bookId) }

    /// 保存原始 epub、解包并生成章节清单。重复调用会复用已解包结果。
    @discardableResult
    func prepare(bookId: String, data: Data) throws -> EPUBManifestFile {
        if let existing = manifest(bookId: bookId) { return existing }
        let dir = bookDirectory(bookId)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: epubURL(bookId), options: .atomic)
        try extract(data: data, to: dir)

        let plan = try EPUBImporter.renderChapters(data: data, fallbackTitle: bookId)
        let manifest = EPUBManifestFile(bookId: bookId, chapters: plan.chapters)
        let encoded = try JSONEncoder().encode(manifest)
        try encoded.write(to: manifestURL(bookId), options: .atomic)
        return manifest
    }

    private func extract(data: Data, to directory: URL) throws {
        let zip = try ZipReader(data: data)
        let root = directory.standardizedFileURL
        for name in zip.fileNames {
            // 防 zip-slip / 绝对路径 / 目录穿越
            let normalized = name.replacingOccurrences(of: "\\", with: "/")
            guard !normalized.hasPrefix("/"), !normalized.split(separator: "/").contains("..") else { continue }
            guard !normalized.hasSuffix("/") else { continue }
            let dest = root.appendingPathComponent(normalized).standardizedFileURL
            guard dest.path.hasPrefix(root.path + "/") else { continue }
            guard let payload = try? zip.read(name) else { continue }
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? payload.write(to: dest, options: .atomic)
        }
    }
}
