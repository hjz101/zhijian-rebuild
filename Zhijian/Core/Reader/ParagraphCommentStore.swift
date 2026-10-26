// ParagraphCommentStore.swift — 段评（按章节 + 段落索引持久化）
import Foundation
import Combine

struct ParagraphComment: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case comment, authorSay
        var label: String { self == .authorSay ? "作家说" : "段评" }
    }

    var id: String = UUID().uuidString
    var kind: Kind = .comment
    var bookId: String
    var chapterIndex: Int
    var paragraphIndex: Int
    var text: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var likes: Int = 0
    var likedByMe: Bool = false
    var replyToId: String?
    var mentions: [String] = []

    init(id: String = UUID().uuidString, bookId: String, chapterIndex: Int, paragraphIndex: Int,
         text: String, createdAt: Date = Date(), updatedAt: Date? = nil, deletedAt: Date? = nil,
         likes: Int = 0, likedByMe: Bool = false, replyToId: String? = nil, mentions: [String] = [],
         kind: Kind = .comment) {
        self.id = id
        self.kind = kind
        self.bookId = bookId
        self.chapterIndex = chapterIndex
        self.paragraphIndex = paragraphIndex
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
        self.likes = likes
        self.likedByMe = likedByMe
        self.replyToId = replyToId
        self.mentions = mentions
    }

    enum CodingKeys: String, CodingKey {
        case id, bookId, chapterIndex, paragraphIndex, text, createdAt, updatedAt, deletedAt
        case likes, likedByMe, replyToId, mentions, kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        bookId = try c.decode(String.self, forKey: .bookId)
        chapterIndex = try c.decode(Int.self, forKey: .chapterIndex)
        paragraphIndex = try c.decode(Int.self, forKey: .paragraphIndex)
        text = try c.decode(String.self, forKey: .text)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        likes = try c.decodeIfPresent(Int.self, forKey: .likes) ?? 0
        likedByMe = try c.decodeIfPresent(Bool.self, forKey: .likedByMe) ?? false
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .comment
        replyToId = try c.decodeIfPresent(String.self, forKey: .replyToId)
        mentions = try c.decodeIfPresent([String].self, forKey: .mentions) ?? []
    }
}

struct CommentMergeResult: Sendable {
    var added = 0
    var updated = 0
    var conflicts = 0
    var tombstones = 0
}

@MainActor
final class ParagraphCommentStore: ObservableObject {
    static let shared = ParagraphCommentStore()

    @Published private(set) var items: [ParagraphComment] = []
    private let file = "paragraph_comments.json"

    private init() {
        items = AppData.load([ParagraphComment].self, file) ?? []
    }

    func comments(bookId: String, chapterIndex: Int, paragraphIndex: Int) -> [ParagraphComment] {
        items.filter {
            $0.deletedAt == nil && $0.bookId == bookId && $0.chapterIndex == chapterIndex && $0.paragraphIndex == paragraphIndex
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func counts(bookId: String, chapterIndex: Int) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for item in items where item.deletedAt == nil && item.bookId == bookId && item.chapterIndex == chapterIndex {
            result[item.paragraphIndex, default: 0] += 1
        }
        return result
    }

    func all() -> [ParagraphComment] { items }

    @discardableResult
    func merge(_ list: [ParagraphComment]) -> CommentMergeResult {
        var byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var result = CommentMergeResult()
        for remote in list {
            guard let local = byId[remote.id] else {
                byId[remote.id] = remote
                result.added += 1
                continue
            }
            let localDeleted = local.deletedAt != nil
            let remoteDeleted = remote.deletedAt != nil
            if remote.updatedAt > local.updatedAt {
                if local.text != remote.text && !localDeleted && !remoteDeleted { result.conflicts += 1 }
                if remoteDeleted && !localDeleted { result.tombstones += 1 }
                byId[remote.id] = remote
                result.updated += 1
            } else if remote.updatedAt == local.updatedAt && local.text != remote.text {
                result.conflicts += 1
            }
        }
        items = byId.values.sorted { $0.createdAt < $1.createdAt }
        persist()
        return result
    }

    func replaceAll(_ list: [ParagraphComment]) {
        items = list
        persist()
    }

    func add(bookId: String, chapterIndex: Int, paragraphIndex: Int, text: String,
             replyToId: String? = nil, kind: ParagraphComment.Kind = .comment) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        items.append(ParagraphComment(bookId: bookId, chapterIndex: chapterIndex,
                                      paragraphIndex: paragraphIndex, text: value,
                                      replyToId: replyToId,
                                      mentions: ChapterCommentStore.parseMentions(in: value),
                                      kind: kind))
        persist()
    }

    func topLevelComments(bookId: String, chapterIndex: Int, paragraphIndex: Int) -> [ParagraphComment] {
        comments(bookId: bookId, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex)
            .filter { $0.replyToId == nil }
    }

    func replies(bookId: String, chapterIndex: Int, paragraphIndex: Int, parentId: String) -> [ParagraphComment] {
        comments(bookId: bookId, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex)
            .filter { $0.replyToId == parentId }
    }

    func toggleLike(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].likedByMe.toggle()
        items[index].likes = max(0, items[index].likes + (items[index].likedByMe ? 1 : -1))
        items[index].updatedAt = Date()
        persist()
    }

    func remove(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].deletedAt = Date()
        items[index].updatedAt = Date()
        persist()
    }

    private func persist() {
        AppData.save(items, file)
    }
}
