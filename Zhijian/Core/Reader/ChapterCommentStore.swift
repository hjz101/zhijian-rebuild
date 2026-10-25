// ChapterCommentStore.swift — 章末评论（按书 + 章节持久化）
import Foundation
import Combine

struct ChapterComment: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var bookId: String
    var chapterIndex: Int
    var chapterTitle: String
    var text: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var likes: Int = 0
    var likedByMe: Bool = false
    var replyToId: String?
    var mentions: [String] = []

    init(id: String = UUID().uuidString, bookId: String, chapterIndex: Int, chapterTitle: String,
         text: String, createdAt: Date = Date(), updatedAt: Date? = nil, deletedAt: Date? = nil,
         likes: Int = 0, likedByMe: Bool = false, replyToId: String? = nil, mentions: [String] = []) {
        self.id = id
        self.bookId = bookId
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
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
        case id, bookId, chapterIndex, chapterTitle, text, createdAt, updatedAt, deletedAt
        case likes, likedByMe, replyToId, mentions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        bookId = try c.decode(String.self, forKey: .bookId)
        chapterIndex = try c.decode(Int.self, forKey: .chapterIndex)
        chapterTitle = try c.decodeIfPresent(String.self, forKey: .chapterTitle) ?? ""
        text = try c.decode(String.self, forKey: .text)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        likes = try c.decodeIfPresent(Int.self, forKey: .likes) ?? 0
        likedByMe = try c.decodeIfPresent(Bool.self, forKey: .likedByMe) ?? false
        replyToId = try c.decodeIfPresent(String.self, forKey: .replyToId)
        mentions = try c.decodeIfPresent([String].self, forKey: .mentions) ?? []
    }
}

@MainActor
final class ChapterCommentStore: ObservableObject {
    static let shared = ChapterCommentStore()

    @Published private(set) var items: [ChapterComment] = []
    private let file = "chapter_comments.json"

    private init() {
        items = AppData.load([ChapterComment].self, file) ?? []
    }

    func comments(bookId: String, chapterIndex: Int, limit: Int? = nil, offset: Int = 0) -> [ChapterComment] {
        let all = items.filter {
            $0.deletedAt == nil && $0.bookId == bookId && $0.chapterIndex == chapterIndex
        }.sorted { $0.createdAt < $1.createdAt }
        let start = min(max(offset, 0), all.count)
        guard let limit, limit > 0 else { return Array(all.dropFirst(start)) }
        return Array(all.dropFirst(start).prefix(limit))
    }

    func topLevelComments(bookId: String, chapterIndex: Int, limit: Int? = nil) -> [ChapterComment] {
        let all = comments(bookId: bookId, chapterIndex: chapterIndex).filter { $0.replyToId == nil }
        guard let limit, limit > 0 else { return all }
        return Array(all.prefix(limit))
    }

    func topLevelCount(bookId: String, chapterIndex: Int) -> Int {
        comments(bookId: bookId, chapterIndex: chapterIndex).filter { $0.replyToId == nil }.count
    }

    func replies(bookId: String, chapterIndex: Int, parentId: String) -> [ChapterComment] {
        comments(bookId: bookId, chapterIndex: chapterIndex).filter { $0.replyToId == parentId }
    }

    func toggleLike(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].likedByMe.toggle()
        items[index].likes = max(0, items[index].likes + (items[index].likedByMe ? 1 : -1))
        items[index].updatedAt = Date()
        persist()
    }

    func totalCount(bookId: String, chapterIndex: Int) -> Int {
        items.filter { $0.deletedAt == nil && $0.bookId == bookId && $0.chapterIndex == chapterIndex }.count
    }

    func count(bookId: String, chapterIndex: Int) -> Int {
        totalCount(bookId: bookId, chapterIndex: chapterIndex)
    }

    func all() -> [ChapterComment] { items }

    @discardableResult
    func merge(_ list: [ChapterComment]) -> CommentMergeResult {
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

    func replaceAll(_ list: [ChapterComment]) {
        items = list
        persist()
    }

    func add(bookId: String, chapterIndex: Int, chapterTitle: String, text: String, replyToId: String? = nil) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let mentions = Self.parseMentions(in: value)
        items.append(ChapterComment(bookId: bookId, chapterIndex: chapterIndex,
                                    chapterTitle: chapterTitle, text: value,
                                    replyToId: replyToId, mentions: mentions))
        persist()
    }

    static func parseMentions(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"@([\p{L}\p{N}_]{1,12})"#) else { return [] }
        let ns = text as NSString
        var names: [String] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) where match.numberOfRanges > 1 {
            let name = ns.substring(with: match.range(at: 1))
            if !names.contains(name) { names.append(name) }
        }
        return names
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
