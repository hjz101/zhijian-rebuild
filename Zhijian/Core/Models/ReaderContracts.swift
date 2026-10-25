// ReaderContracts.swift — 阅读器与内容服务之间的接口
import Foundation

struct BookChapterContent: Sendable {
    var title: String
    var text: String
    var nextChapterIndex: Int?
    /// P1-04：正文内嵌图片（与文本中的 `[[IMGn]]` 标记对应）
    var images: [ExtractedReaderImage] = []

    init(title: String, text: String, nextChapterIndex: Int? = nil,
         images: [ExtractedReaderImage] = []) {
        self.title = title
        self.text = text
        self.nextChapterIndex = nextChapterIndex
        self.images = images
    }
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
