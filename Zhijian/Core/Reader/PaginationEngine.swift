// PaginationEngine.swift — TextKit 分页内核（NSTextStorage + NSLayoutManager + NSTextContainer）
//
// 一章富文本 → 按页面可用尺寸切成若干页，输出 UTF-16 字符范围。
// 断页在后台串行队列完成（TextKit 对象全部在闭包内创建，不跨线程共享），
// 结果按 (bookId, chapterIndex, layoutSignature, size, contentHash) 缓存。
import UIKit

struct ReaderPage: Identifiable, Equatable {
    let index: Int
    let range: NSRange

    var id: Int { index }
    var location: Int { range.location }
    var length: Int { range.length }
}

struct PaginationResult: Equatable {
    var pages: [ReaderPage]
    var textLength: Int

    static let empty = PaginationResult(pages: [], textLength: 0)
}

final class PaginationEngine: @unchecked Sendable {

    struct Key: Hashable {
        var bookId: String
        var chapterIndex: Int
        var layoutSignature: String
        /// 半像素精度，避免浮点抖动导致缓存全部失效。
        var width: Int
        var height: Int
        var contentHash: Int
    }

    private let lock = NSLock()
    private var cache: [Key: PaginationResult] = [:]
    private var order: [Key] = []
    private let maxEntries = 160
    private let queue = DispatchQueue(label: "com.zhijian.reader.pagination", qos: .userInitiated)

    // MARK: - 对外接口

    func cachedPages(bookId: String, chapterIndex: Int, layoutSignature: String, pageSize: CGSize, contentHash: Int) -> PaginationResult? {
        let key = Self.key(bookId: bookId, chapterIndex: chapterIndex, layoutSignature: layoutSignature,
                           pageSize: pageSize, contentHash: contentHash)
        return read(key)
    }

    func paginate(
        bookId: String,
        chapterIndex: Int,
        layoutSignature: String,
        attributed: NSAttributedString,
        pageSize: CGSize
    ) async -> PaginationResult {
        let contentHash = attributed.string.hashValue
        let key = Self.key(bookId: bookId, chapterIndex: chapterIndex, layoutSignature: layoutSignature,
                           pageSize: pageSize, contentHash: contentHash)
        if let hit = read(key) { return hit }

        let safeSize = CGSize(
            width: max(pageSize.width, 1),
            height: max(pageSize.height - 0.5, 1)
        )
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<PaginationResult, Never>) in
            queue.async {
                let pages = Self.layout(attributed: attributed, pageSize: safeSize)
                continuation.resume(returning: pages)
            }
        }
        write(key, result)
        return result
    }

    /// 清掉某本书（或全部）的缓存；换源/重排/内存紧张时调用。
    func invalidate(bookId: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard let bookId else {
            cache.removeAll()
            order.removeAll()
            return
        }
        let keys = cache.keys.filter { $0.bookId == bookId }
        for key in keys { cache.removeValue(forKey: key) }
        order.removeAll { $0.bookId == bookId }
    }

    // MARK: - 缓存

    private static func key(
        bookId: String,
        chapterIndex: Int,
        layoutSignature: String,
        pageSize: CGSize,
        contentHash: Int
    ) -> Key {
        Key(
            bookId: bookId,
            chapterIndex: chapterIndex,
            layoutSignature: layoutSignature,
            width: Int((pageSize.width * 2).rounded()),
            height: Int((pageSize.height * 2).rounded()),
            contentHash: contentHash
        )
    }

    private func read(_ key: Key) -> PaginationResult? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    private func write(_ key: Key, _ result: PaginationResult) {
        lock.lock()
        defer { lock.unlock() }
        if cache[key] == nil {
            order.append(key)
            while order.count > maxEntries {
                let evicted = order.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        }
        cache[key] = result
    }

    // MARK: - TextKit 断页

    /// 纯函数：不持有 TextKit 对象，调用方可以安全地放到任意线程执行。
    private static func layout(attributed: NSAttributedString, pageSize: CGSize) -> PaginationResult {
        let textLength = attributed.length
        guard textLength > 0, pageSize.width > 1, pageSize.height > 1 else {
            return PaginationResult(pages: [], textLength: textLength)
        }

        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = true
        storage.addLayoutManager(layoutManager)

        var pages: [ReaderPage] = []
        var consumed = 0
        // 极端输入（超长章节）下的安全上限，防止死循环。
        let pageLimit = 8192

        while consumed < textLength && pages.count < pageLimit {
            let container = NSTextContainer(size: pageSize)
            container.lineFragmentPadding = 0
            container.maximumNumberOfLines = 0
            container.lineBreakMode = .byWordWrapping
            layoutManager.addTextContainer(container)
            layoutManager.ensureLayout(for: container)

            let glyphRange = layoutManager.glyphRange(for: container)
            guard glyphRange.length > 0 else { break }

            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard charRange.length > 0 else { break }

            pages.append(ReaderPage(index: pages.count, range: charRange))

            let next = charRange.location + charRange.length
            guard next > consumed else { break }
            consumed = next
        }

        // 兜底：任何情况下都至少给一页，避免 UI 空白。
        if pages.isEmpty {
            pages = [ReaderPage(index: 0, range: NSRange(location: 0, length: textLength))]
        }
        return PaginationResult(pages: pages, textLength: textLength)
    }
}
