// ChapterCacheStore.swift — 章节磁盘缓存（目录 + 正文，LRU 容量控制）
import Foundation
import CryptoKit
import Combine

struct CachedTOCCheckpoint: Codable, Sendable {
    var chapters: [Chapter]
    var savedAt: Date
}

struct CachedBookMeta: Codable, Sendable {
    var bookId: String
    var title: String
    var updatedAt: Date
}

struct CachedBookSummary: Identifiable, Sendable {
    var id: String { bookId }
    var bookId: String
    var title: String
    var bytes: Int64
    var files: Int
}

struct CachedChapterBody: Codable, Sendable {
    var title: String
    var text: String
    var nextChapterIndex: Int?
    var chapterUrl: String
    var savedAt: Date
    var images: [ExtractedReaderImage] = []
}

@MainActor
final class ChapterCacheStore: ObservableObject {
    static let shared = ChapterCacheStore()

    /// 默认上限 200 MB；超过后按最后访问时间删除最旧章节。
    static let defaultLimitBytes: Int64 = 200 * 1024 * 1024
    static let tocTTL: TimeInterval = 24 * 60 * 60

    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var chapterFileCount: Int = 0
    @Published private(set) var bookCount: Int = 0

    private let fm = FileManager.default
    private let root: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("ChapterCache", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        refreshStats()
    }

    // MARK: - 目录

    func loadChapters(bookId: String) -> [Chapter]? {
        let url = directory(for: bookId).appendingPathComponent("toc.json")
        guard let data = try? Data(contentsOf: url),
              let checkpoint = try? JSONDecoder().decode(CachedTOCCheckpoint.self, from: data) else { return nil }
        touch(url)
        return checkpoint.chapters
    }

    func tocIsFresh(bookId: String) -> Bool {
        let url = directory(for: bookId).appendingPathComponent("toc.json")
        guard let data = try? Data(contentsOf: url),
              let checkpoint = try? JSONDecoder().decode(CachedTOCCheckpoint.self, from: data) else { return false }
        return Date().timeIntervalSince(checkpoint.savedAt) < Self.tocTTL
    }

    func saveChapters(bookId: String, title: String = "", chapters: [Chapter]) {
        let dir = directory(for: bookId)
        let checkpoint = CachedTOCCheckpoint(chapters: chapters, savedAt: Date())
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        try? data.write(to: dir.appendingPathComponent("toc.json"), options: .atomic)
        let meta = CachedBookMeta(bookId: bookId, title: title, updatedAt: Date())
        if let metaData = try? JSONEncoder().encode(meta) {
            try? metaData.write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
        }
        refreshStats()
    }

    func summaries() -> [CachedBookSummary] {
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var result: [CachedBookSummary] = []
        for dir in dirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let metaURL = dir.appendingPathComponent("meta.json")
            let meta = (try? Data(contentsOf: metaURL)).flatMap { try? JSONDecoder().decode(CachedBookMeta.self, from: $0) }
            var bytes: Int64 = 0
            var files = 0
            for file in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? [] where file.pathExtension == "json" {
                files += 1
                bytes += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            guard files > 0 else { continue }
            result.append(CachedBookSummary(bookId: meta?.bookId ?? dir.lastPathComponent,
                                            title: meta?.title ?? dir.lastPathComponent,
                                            bytes: bytes, files: files))
        }
        return result.sorted { $0.bytes > $1.bytes }
    }

    // MARK: - 正文

    func loadContent(bookId: String, chapter: Chapter) -> BookChapterContent? {
        let url = bodyURL(bookId: bookId, index: chapter.index)
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedChapterBody.self, from: data) else { return nil }
        // 章节地址变了（换源/更新目录）视为失效
        if !chapter.url.isEmpty, !cached.chapterUrl.isEmpty, cached.chapterUrl != chapter.url {
            return nil
        }
        touch(url)
        return BookChapterContent(title: cached.title, text: cached.text,
                                  nextChapterIndex: cached.nextChapterIndex, images: cached.images)
    }

    func saveContent(bookId: String, chapter: Chapter, content: BookChapterContent) {
        let dir = directory(for: bookId)
        let cached = CachedChapterBody(title: content.title, text: content.text,
                                       nextChapterIndex: content.nextChapterIndex,
                                       chapterUrl: chapter.url, savedAt: Date(),
                                       images: content.images)
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: bodyURL(bookId: bookId, index: chapter.index), options: .atomic)
        refreshStats()
        trimIfNeeded()
    }

    // MARK: - 清理

    func remove(bookId: String) {
        try? fm.removeItem(at: directory(for: bookId))
        refreshStats()
    }

    func clearAll() {
        try? fm.removeItem(at: root)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        refreshStats()
    }

    func clearBook(_ bookId: String) { remove(bookId: bookId) }

    func refreshStats() {
        var bytes: Int64 = 0
        var files = 0
        var books = 0
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for dir in dirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            books += 1
            let contents = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            for file in contents where file.pathExtension == "json" {
                files += 1
                bytes += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        totalBytes = bytes
        chapterFileCount = files
        bookCount = books
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    // MARK: - LRU

    func trimIfNeeded(limit: Int64 = ChapterCacheStore.defaultLimitBytes) {
        guard totalBytes > limit else { return }
        var entries: [(url: URL, date: Date, size: Int64)] = []
        for bookDir in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for file in (try? fm.contentsOfDirectory(at: bookDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? [] {
                guard file.pathExtension == "json", file.lastPathComponent != "toc.json" else { continue }
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                entries.append((file, date, size))
            }
        }
        var bytes = totalBytes
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard bytes > limit else { break }
            try? fm.removeItem(at: entry.url)
            bytes -= entry.size
        }
        refreshStats()
    }

    // MARK: - 路径

    private func directory(for bookId: String) -> URL {
        let key = Self.hash(bookId)
        let url = root.appendingPathComponent(key, isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func bodyURL(bookId: String, index: Int) -> URL {
        directory(for: bookId).appendingPathComponent(String(format: "chapter_%06d.json", index))
    }

    private func touch(_ url: URL) {
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
