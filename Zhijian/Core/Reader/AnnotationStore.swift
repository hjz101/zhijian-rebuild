// AnnotationStore.swift — 书签 / 划线 / 笔记（本地 JSON 持久化）
import Foundation
import Combine
import UIKit

struct ReadingBookmark: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var bookId: String
    var chapterIndex: Int
    var chapterTitle: String
    var pageIndex: Int
    var createdAt: Date
}

struct ReadingAnnotation: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable { case highlight, note }
    var id: String
    var bookId: String
    var chapterIndex: Int
    var chapterTitle: String
    var location: Int        // 章内 UTF-16 起点
    var length: Int
    var text: String
    var note: String?
    var colorHex: String
    var kind: Kind
    var createdAt: Date
}

struct AnnotationBackup: Codable, Sendable {
    var bookmarks: [ReadingBookmark]
    var annotations: [ReadingAnnotation]
}

@MainActor
final class AnnotationStore: ObservableObject {
    static let shared = AnnotationStore()

    @Published private(set) var bookmarks: [ReadingBookmark] = []
    @Published private(set) var annotations: [ReadingAnnotation] = []

    private let file = "annotations.json"

    private init() {
        if let payload = AppData.load(AnnotationBackup.self, file) {
            bookmarks = payload.bookmarks
            annotations = payload.annotations
        }
    }

    // MARK: - 查询

    func bookmarks(bookId: String) -> [ReadingBookmark] {
        bookmarks.filter { $0.bookId == bookId }.sorted { $0.createdAt > $1.createdAt }
    }

    func isBookmarked(bookId: String, chapterIndex: Int) -> Bool {
        bookmarks.contains { $0.bookId == bookId && $0.chapterIndex == chapterIndex }
    }

    func annotations(bookId: String, chapterIndex: Int) -> [ReadingAnnotation] {
        annotations.filter { $0.bookId == bookId && $0.chapterIndex == chapterIndex }
    }

    func annotations(bookId: String) -> [ReadingAnnotation] {
        annotations.filter { $0.bookId == bookId }.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - 书签

    @discardableResult
    func toggleBookmark(bookId: String, chapterIndex: Int, chapterTitle: String, pageIndex: Int) -> Bool {
        if let idx = bookmarks.firstIndex(where: { $0.bookId == bookId && $0.chapterIndex == chapterIndex }) {
            bookmarks.remove(at: idx)
            persist()
            return false
        }
        bookmarks.append(ReadingBookmark(id: UUID().uuidString, bookId: bookId, chapterIndex: chapterIndex,
                                         chapterTitle: chapterTitle, pageIndex: pageIndex, createdAt: Date()))
        persist()
        return true
    }

    func removeBookmark(_ id: String) {
        bookmarks.removeAll { $0.id == id }
        persist()
    }

    // MARK: - 划线 / 笔记

    @discardableResult
    func addAnnotation(bookId: String, chapterIndex: Int, chapterTitle: String,
                       location: Int, length: Int, text: String,
                       note: String?, kind: ReadingAnnotation.Kind, colorHex: String = "#E8663D") -> ReadingAnnotation {
        // 同一位置重复划线视为覆盖
        annotations.removeAll {
            $0.bookId == bookId && $0.chapterIndex == chapterIndex && $0.location == location && $0.length == length
        }
        let ann = ReadingAnnotation(id: UUID().uuidString, bookId: bookId, chapterIndex: chapterIndex,
                                    chapterTitle: chapterTitle, location: location, length: length,
                                    text: text, note: note, colorHex: colorHex, kind: kind, createdAt: Date())
        annotations.append(ann)
        persist()
        return ann
    }

    func updateNote(_ id: String, note: String?) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[idx].note = note
        annotations[idx].kind = (note?.isEmpty == false) ? .note : .highlight
        persist()
    }

    func removeAnnotation(_ id: String) {
        annotations.removeAll { $0.id == id }
        persist()
    }

    func clearAll(bookId: String) {
        bookmarks.removeAll { $0.bookId == bookId }
        annotations.removeAll { $0.bookId == bookId }
        persist()
    }

    // MARK: - 持久化

    func backup() -> AnnotationBackup {
        AnnotationBackup(bookmarks: bookmarks, annotations: annotations)
    }

    func merge(_ payload: AnnotationBackup) {
        var bookmarkMap = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.id, $0) })
        var annotationMap = Dictionary(uniqueKeysWithValues: annotations.map { ($0.id, $0) })
        for item in payload.bookmarks where bookmarkMap[item.id] == nil { bookmarkMap[item.id] = item }
        for item in payload.annotations where annotationMap[item.id] == nil { annotationMap[item.id] = item }
        bookmarks = bookmarkMap.values.sorted { $0.createdAt > $1.createdAt }
        annotations = annotationMap.values.sorted { $0.createdAt > $1.createdAt }
        persist()
    }

    func replaceAll(_ payload: AnnotationBackup) {
        bookmarks = payload.bookmarks
        annotations = payload.annotations
        persist()
    }

    private func persist() {
        AppData.save(AnnotationBackup(bookmarks: bookmarks, annotations: annotations), file)
    }

    // MARK: - 颜色

    static func uiColor(hex: String, alpha: CGFloat = 0.30) -> UIColor {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: alpha)
    }
}
