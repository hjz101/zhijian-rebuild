// MangaLibrary.swift — 本地漫画页仓库（CBZ / ZIP 图片）
import Foundation

struct MangaManifest: Codable {
    var pages: [String]
}

@MainActor
final class MangaLibrary {
    static let shared = MangaLibrary()
    private let fm = FileManager.default
    private let root: URL = {
        let url = AppData.root.appendingPathComponent("Manga", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private init() {}

    func directory(bookId: String) -> URL {
        let url = root.appendingPathComponent(bookId, isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func has(bookId: String) -> Bool {
        !pageURLs(bookId: bookId).isEmpty
    }

    func pageURLs(bookId: String) -> [URL] {
        let dir = directory(bookId: bookId)
        let manifestURL = dir.appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: manifestURL),
           let manifest = try? JSONDecoder().decode(MangaManifest.self, from: data) {
            return manifest.pages.map { dir.appendingPathComponent($0) }
        }
        // 兼容无 manifest 的目录：按自然序读取图片
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    @discardableResult
    func save(entries: [(name: String, data: Data)], bookId: String) throws -> [URL] {
        let dir = directory(bookId: bookId)
        var pages: [String] = []
        for (index, entry) in entries.enumerated() {
            let ext = (entry.name as NSString).pathExtension.lowercased()
            let safeExt = Self.imageExtensions.contains(ext) ? ext : "jpg"
            let name = String(format: "%04d.%@", index + 1, safeExt)
            try entry.data.write(to: dir.appendingPathComponent(name), options: .atomic)
            pages.append(name)
        }
        let manifest = MangaManifest(pages: pages)
        try JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
        return pages.map { dir.appendingPathComponent($0) }
    }

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic"]
}
