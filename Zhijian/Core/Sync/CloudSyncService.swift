// CloudSyncService.swift — iCloud KVS（设置 + 阅读进度）与 iCloud Drive 备份
import Foundation
import UIKit
import Combine

struct CloudProgress: Codable {
    var title: String
    var chapterIndex: Int
    var pageIndex: Int
    var ratio: Double
    var lastReadAt: Date?
}

@MainActor
final class CloudSyncService: ObservableObject {
    static let shared = CloudSyncService()

    @Published private(set) var lastPushAt: Date?
    @Published private(set) var lastPullAt: Date?
    @Published private(set) var remoteUpdated = false
    @Published private(set) var statusMessage = "尚未同步"
    @Published private(set) var usingFallback = false
    @Published private(set) var lastConflictCount = 0

    private let store = NSUbiquitousKeyValueStore.default
    private let settingsKey = "zhijian.settings.v1"
    private let progressKey = "zhijian.progress.v1"
    private let updatedKey = "zhijian.updatedAt.v1"
    private let commentsKey = "zhijian.comments.v1"

    struct CommentBundle: Codable {
        var paragraphComments: [ParagraphComment]
        var chapterComments: [ChapterComment]
        var annotations: AnnotationBackup
        var updatedAt: Date
    }
    private let fallbackFile = "cloud_kvs_fallback.json"

    private struct Fallback: Codable {
        var settings: Data?
        var progress: Data?
        var comments: Data?
        var updatedAt: Date
    }
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.remoteUpdated = true
                self?.statusMessage = "云端有更新，可点击「从 iCloud 同步」"
            }
        }
        _ = store.synchronize()
        usingFallback = store.data(forKey: settingsKey) == nil
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var driveAvailable: Bool { driveDirectory() != nil }

    func driveDirectory() -> URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        let dir = container.appendingPathComponent("Documents/Zhijian", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func push(settings: ReadingSettings, books: [Book]) {
        let settingsData = try? JSONEncoder().encode(settings)
        if let settingsData { store.set(settingsData, forKey: settingsKey) }
        var progress: [String: CloudProgress] = [:]
        for book in books {
            progress[book.id] = CloudProgress(title: book.title,
                                              chapterIndex: book.currentChapterIndex,
                                              pageIndex: book.currentPageIndex,
                                              ratio: book.currentScrollRatio,
                                              lastReadAt: book.lastReadAt)
        }
        let progressData = try? JSONEncoder().encode(progress)
        if let progressData { store.set(progressData, forKey: progressKey) }
        let commentBundle = CommentBundle(paragraphComments: ParagraphCommentStore.shared.all(),
                                          chapterComments: ChapterCommentStore.shared.all(),
                                          annotations: AnnotationStore.shared.backup(),
                                          updatedAt: Date())
        let commentsData = try? JSONEncoder().encode(commentBundle)
        if let commentsData { store.set(commentsData, forKey: commentsKey) }
        store.set(Date().timeIntervalSince1970, forKey: updatedKey)
        let ok = store.synchronize()
        // 未签名/无 iCloud entitlement 时 KVS 不落盘：降级为本地镜像，签名后自动恢复 iCloud 路径
        if store.data(forKey: settingsKey) == nil {
            usingFallback = true
            AppData.save(Fallback(settings: settingsData,
                                  progress: progressData,
                                  comments: commentsData,
                                  updatedAt: Date()), fallbackFile)
        } else {
            usingFallback = false
        }
        lastPushAt = Date()
        statusMessage = ok && !usingFallback
            ? "已上传设置与 \(books.count) 本书进度"
            : "iCloud 不可用，已写入本地镜像（\(books.count) 本书进度；签名后自动走 iCloud）"
    }

    @discardableResult
    func pull(into settings: SettingsStore, books: BookStore) -> String {
        let fallback: Fallback? = AppData.load(Fallback.self, fallbackFile)
        let settingsData = store.data(forKey: settingsKey) ?? fallback?.settings
        guard let settingsData,
              let remoteSettings = try? JSONDecoder().decode(ReadingSettings.self, from: settingsData) else {
            statusMessage = "云端没有可同步的数据"
            return statusMessage
        }
        settings.settings = remoteSettings
        var restored = 0
        if let data = store.data(forKey: progressKey) ?? fallback?.progress,
           let progress = try? JSONDecoder().decode([String: CloudProgress].self, from: data) {
            for book in books.books {
                guard let item = progress[book.id] else { continue }
                books.markRead(book.id, chapter: item.chapterIndex, page: item.pageIndex, ratio: item.ratio)
                restored += 1
            }
        }
        let commentData = store.data(forKey: commentsKey) ?? fallback?.comments
        var commentCount = 0
        var conflicts = 0
        if let commentData,
           let bundle = try? JSONDecoder().decode(CommentBundle.self, from: commentData) {
            let paragraphResult = ParagraphCommentStore.shared.merge(bundle.paragraphComments)
            let chapterResult = ChapterCommentStore.shared.merge(bundle.chapterComments)
            AnnotationStore.shared.merge(bundle.annotations)
            conflicts = paragraphResult.conflicts + chapterResult.conflicts
            commentCount = bundle.paragraphComments.count + bundle.chapterComments.count
                + bundle.annotations.annotations.count + bundle.annotations.bookmarks.count
        }
        lastConflictCount = conflicts
        lastPullAt = Date()
        remoteUpdated = false
        let source = store.data(forKey: settingsKey) != nil ? "iCloud" : "本地镜像"
        var summary = "已从\(source)同步设置、\(restored) 本书进度、\(commentCount) 条评论/批注"
        if conflicts > 0 { summary += "，处理 \(conflicts) 处冲突（以较新版本为准）" }
        statusMessage = summary
        return statusMessage
    }

    /// 把加密/普通 .zjbk 复制到 iCloud Drive 的 Zhijian 目录。
    func mirrorBackup(_ source: URL) throws -> URL {
        guard let dir = driveDirectory() else {
            throw NSError(domain: "CloudSync", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "iCloud Drive 不可用（需要签名并声明 iCloud 容器）"])
        }
        let target = dir.appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: source, to: target)
        lastPushAt = Date()
        statusMessage = "已镜像到 iCloud Drive：\(target.lastPathComponent)"
        return target
    }
}
