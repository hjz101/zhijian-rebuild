// CommentWebDAVSync.swift — 段评/章末评论独立 WebDAV 同步（合并 + 回传）
import Foundation

struct CommentSyncEnvelope: Codable, Sendable {
    var version: Int = 1
    var exportedAt: Date = Date()
    var paragraphComments: [ParagraphComment]
    var chapterComments: [ChapterComment]
}

struct CommentSyncSummary: Sendable {
    var localCount: Int
    var remoteCount: Int
    var added: Int
    var updated: Int
    var conflicts: Int
    var tombstones: Int

    var localizedDescription: String {
        "本地 \(localCount) 条 · 云端 \(remoteCount) 条 · 新增 \(added) · 更新 \(updated) · 冲突 \(conflicts) · 删除 \(tombstones)"
    }
}

@MainActor
extension BackupService {
    static let commentSyncFileName = "zhijian-comments.json"

    /// 双向同步：下载云端评论 → 按 updatedAt/墓碑合并 → 回传合并结果。
    func syncComments(to config: WebDAVConfig) async throws -> CommentSyncSummary {
        let client = WebDAVClient(config: config)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZhijianCommentSync", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let remoteURL = dir.appendingPathComponent(Self.commentSyncFileName)
        let localURL = dir.appendingPathComponent("merged-\(Self.commentSyncFileName)")

        var remoteEnvelope: CommentSyncEnvelope?
        do {
            try await client.download(fileName: Self.commentSyncFileName, to: remoteURL)
            remoteEnvelope = try JSONDecoder().decode(CommentSyncEnvelope.self, from: Data(contentsOf: remoteURL))
        } catch WebDAVError.notFound {
            remoteEnvelope = nil
        }

        let paragraphResult: CommentMergeResult
        let chapterResult: CommentMergeResult
        if let remoteEnvelope {
            paragraphResult = ParagraphCommentStore.shared.merge(remoteEnvelope.paragraphComments)
            chapterResult = ChapterCommentStore.shared.merge(remoteEnvelope.chapterComments)
        } else {
            paragraphResult = CommentMergeResult()
            chapterResult = CommentMergeResult()
        }

        let envelope = CommentSyncEnvelope(paragraphComments: ParagraphCommentStore.shared.all(),
                                           chapterComments: ChapterCommentStore.shared.all())
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: localURL, options: .atomic)
        try await client.upload(fileURL: localURL, fileName: Self.commentSyncFileName)

        return CommentSyncSummary(
            localCount: envelope.paragraphComments.count + envelope.chapterComments.count,
            remoteCount: (remoteEnvelope?.paragraphComments.count ?? 0) + (remoteEnvelope?.chapterComments.count ?? 0),
            added: paragraphResult.added + chapterResult.added,
            updated: paragraphResult.updated + chapterResult.updated,
            conflicts: paragraphResult.conflicts + chapterResult.conflicts,
            tombstones: paragraphResult.tombstones + chapterResult.tombstones
        )
    }
}
