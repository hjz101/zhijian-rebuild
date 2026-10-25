// ReaderContracts.swift — 阅读器与内容服务之间的接口
import Foundation

struct BookChapterContent: Sendable {
    var title: String
    var text: String
    var nextChapterIndex: Int?
}

protocol ReaderContentProviding: AnyObject, Sendable {
    func chapters(for book: Book) async throws -> [Chapter]
    func content(for book: Book, chapter: Chapter) async throws -> BookChapterContent
    /// 换源后清理该书的详情/目录缓存
    func invalidate(bookId: String)
}

extension ReaderContentProviding {
    func invalidate(bookId: String) {}
}

protocol TTSControlling: AnyObject, Sendable {
    func speak(_ text: String) async
    func stop()
    var isSpeaking: Bool { get }
}
