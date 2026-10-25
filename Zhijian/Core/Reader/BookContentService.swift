// BookContentService.swift — 阅读内容提供（远程书源 + 本地书）
//
// 远程书：book.sourceUrl → BookSource → SourcePipeline(bookInfo → toc → content)
// 本地书：LocalLibrary（Lead 维护的本地内容仓库）按 bookId 取章节
//
// 并发约定：SourcePipeline 的内部状态（currentBook / currentChapter / vars）只能在一次
// 顺序调用里使用，不能跨任务共享。因此每次阶段调用都新建一个 pipeline，并通过
// initialCookies / onCookiesChanged 让 Cookie 在多次调用之间延续。
import Foundation

/// 阅读内容层的明确错误（UI 直接展示 errorDescription）。
enum ReaderContentError: LocalizedError {
    case localBookMissing(title: String)
    case localChapterMissing(title: String, index: Int)
    case sourceNotFound(String)
    case bookURLMissing(String)
    case emptyBook(String)

    var errorDescription: String? {
        switch self {
        case .localBookMissing(let title):
            return "本地书《\(title)》没有内容记录，请重新导入文件。"
        case .localChapterMissing(let title, let index):
            return "《\(title)》缺少第 \(index + 1) 章内容，文件可能已损坏。"
        case .sourceNotFound(let detail):
            return "找不到可用的书源（\(detail)），请在书源页重新导入或换源。"
        case .bookURLMissing(let title):
            return "《\(title)》缺少详情页地址（bookUrl），无法从书源加载，请重新搜索加入书架。"
        case .emptyBook(let title):
            return "《\(title)》目录为空，暂时无法阅读。"
        }
    }
}

@MainActor
final class BookContentService: ReaderContentProviding {
    let books: BookStore
    let sources: SourceStore

    /// 跨请求共享的 Cookie（按域名）。新 pipeline 创建时注入，站点登录态可以延续。
    private var cookieStore: [String: [String: String]] = [:]
    /// 每本书的 bookInfo 结果（含 tocUrl），content 阶段复用，避免重复请求详情页。
    private var bookInfoCache: [String: SourceBookInfo] = [:]
    /// 最近一次目录，用于计算 nextChapterIndex。
    private var chapterCache: [String: [Chapter]] = [:]

    init(books: BookStore, sources: SourceStore) {
        self.books = books
        self.sources = sources
    }

    func invalidate(bookId: String) {
        bookInfoCache.removeValue(forKey: bookId)
        chapterCache.removeValue(forKey: bookId)
        ChapterCacheStore.shared.remove(bookId: bookId)
    }

    // MARK: - 目录

    func chapters(for book: Book) async throws -> [Chapter] {
        if book.isLocal {
            return try loadLocalChapters(for: book)
        }

        let cache = ChapterCacheStore.shared
        if let cached = cache.loadChapters(bookId: book.id), !cached.isEmpty {
            chapterCache[book.id] = cached
            updateBookMetadata(book, chapters: cached)
            if cache.tocIsFresh(bookId: book.id) {
                return cached
            }
            // TTL 过期：后台刷新，失败保留旧目录（离线可用）
            Task { [weak self] in
                guard let self else { return }
                do {
                    let fresh = try await self.fetchFreshChapters(for: book)
                    cache.saveChapters(bookId: book.id, title: book.title, chapters: fresh)
                    self.chapterCache[book.id] = fresh
                    self.updateBookMetadata(book, chapters: fresh)
                } catch {
                    // keep stale cache
                }
            }
            return cached
        }

        let chapters = try await fetchFreshChapters(for: book)
        cache.saveChapters(bookId: book.id, title: book.title, chapters: chapters)
        return chapters
    }

    private func fetchFreshChapters(for book: Book) async throws -> [Chapter] {
        let pipeline = try makePipeline(for: book)
        let info = try await fetchInfo(for: book, pipeline: pipeline)
        let toc = try await pipeline.toc(info)

        // 卷名行没有正文（chapterUrl 为空），直接不进入阅读章节列表，
        // 否则书城/阅读器会把它当成普通章节并报「chapterUrl 为空」。
        let readable = toc.filter { !$0.isVolume && !$0.url.isEmpty }
        let chapters = readable.enumerated().map { position, chapter in
            Chapter(
                id: "\(book.id)#\(position)",
                index: position,
                title: chapter.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "第 \(position + 1) 章"
                    : chapter.title,
                url: chapter.url,
                isVip: false,
                isPay: false,
                isVolume: false
            )
        }
        guard !chapters.isEmpty else { throw ReaderContentError.emptyBook(book.title) }

        chapterCache[book.id] = chapters
        updateBookMetadata(book, chapters: chapters)
        return chapters
    }

    // MARK: - 正文

    func content(for book: Book, chapter: Chapter) async throws -> BookChapterContent {
        if book.isLocal {
            return try loadLocalContent(for: book, chapter: chapter)
        }

        let cache = ChapterCacheStore.shared
        if let cached = cache.loadContent(bookId: book.id, chapter: chapter) {
            return cached
        }

        let pipeline = try makePipeline(for: book)
        let info = try await fetchInfo(for: book, pipeline: pipeline)
        let sourceChapter = SourceChapter(
            index: chapter.index,
            title: chapter.title,
            url: chapter.url,
            updateTime: "",
            isVolume: false
        )
        let result = try await pipeline.content(sourceChapter, book: info)
        if result.isPaywall { throw SourceEngineError.needLogin }

        let text = result.content
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SourceEngineError.emptyContent("正文为空（\(chapter.title)）")
        }
        var title = result.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? chapter.title
            : result.title
        var body = text
        let store = ReplaceRuleStore.shared
        if !store.rules.isEmpty {
            title = store.cleanTitle(title)
            body = store.cleanContent(body)
        }
        let content = BookChapterContent(
            title: title,
            text: body,
            nextChapterIndex: nextChapterIndex(after: chapter, bookId: book.id),
            images: result.images
        )
        cache.saveContent(bookId: book.id, chapter: chapter, content: content)
        return content
    }

    // MARK: - 远程书流水线

    private func source(for book: Book) throws -> BookSource {
        guard let sourceURL = book.sourceUrl, !sourceURL.isEmpty else {
            throw ReaderContentError.sourceNotFound("《\(book.title)》没有记录来源")
        }
        guard let source = sources.sources.first(where: { $0.bookSourceUrl == sourceURL }) else {
            throw ReaderContentError.sourceNotFound(sourceURL)
        }
        return source
    }

    /// 新建 pipeline：注入已收集的 Cookie，并把新 Cookie 合并回本服务的共享表。
    private func makePipeline(for book: Book) throws -> SourcePipeline {
        let bookSource = try source(for: book)
        return SourcePipeline(
            source: bookSource,
            initialCookies: CookieStore.shared.snapshot(),
            loginInfo: SourceLoginStore.shared.loginInfo(for: bookSource.bookSourceUrl),
            loginHeader: SourceLoginStore.shared.loginHeader(for: bookSource.bookSourceUrl),
            onCookiesChanged: { cookies in
                CookieStore.onChange(cookies)
            }
        )
    }

    private func fetchInfo(for book: Book, pipeline: SourcePipeline) async throws -> SourceBookInfo {
        if let cached = bookInfoCache[book.id] { return cached }
        guard let bookURL = book.bookUrl, !bookURL.isEmpty else {
            throw ReaderContentError.bookURLMissing(book.title)
        }
        let sourceBook = SourceBook(
            name: book.title,
            author: book.author,
            kind: book.kind ?? "",
            intro: book.intro ?? "",
            lastChapter: book.lastChapter ?? "",
            coverUrl: book.coverURL ?? "",
            bookUrl: bookURL
        )
        let info = try await pipeline.bookInfo(sourceBook)
        bookInfoCache[book.id] = info
        return info
    }

    private func nextChapterIndex(after chapter: Chapter, bookId: String) -> Int? {
        guard let list = chapterCache[bookId],
              let position = list.firstIndex(where: { $0.id == chapter.id }),
              list.indices.contains(position + 1) else { return nil }
        return list[position + 1].index
    }

    private func mergeCookies(_ cookies: [String: [String: String]]) {
        for (domain, values) in cookies {
            var merged = cookieStore[domain] ?? [:]
            for (name, value) in values { merged[name] = value }
            cookieStore[domain] = merged
        }
    }

    private func updateBookMetadata(_ book: Book, chapters: [Chapter]) {
        guard let index = books.books.firstIndex(where: { $0.id == book.id }) else { return }
        var updated = books.books[index]
        let lastTitle = chapters.last?.title
        guard updated.totalChapters != chapters.count || updated.lastChapter != lastTitle else { return }
        updated.totalChapters = chapters.count
        updated.lastChapter = lastTitle
        books.update(updated)
    }

    // MARK: - 本地书

    private func loadLocalChapters(for book: Book) throws -> [Chapter] {
        guard let record = LocalLibrary.shared.record(for: book.id) else {
            throw ReaderContentError.localBookMissing(title: book.title)
        }
        let sorted = record.chapters.sorted { $0.index < $1.index }
        guard !sorted.isEmpty else { throw ReaderContentError.emptyBook(book.title) }

        let chapters = sorted.enumerated().map { position, chapter in
            Chapter(
                id: "\(book.id)#local#\(chapter.index)",
                index: chapter.index,
                title: chapter.title,
                url: "local://\(book.id)/\(chapter.index)",
                isVip: false,
                isPay: false
            )
        }
        chapterCache[book.id] = chapters
        updateBookMetadata(book, chapters: chapters)
        return chapters
    }

    private func loadLocalContent(for book: Book, chapter: Chapter) throws -> BookChapterContent {
        guard let record = LocalLibrary.shared.record(for: book.id) else {
            throw ReaderContentError.localBookMissing(title: book.title)
        }
        let sorted = record.chapters.sorted { $0.index < $1.index }
        guard let position = sorted.firstIndex(where: { $0.index == chapter.index }) else {
            throw ReaderContentError.localChapterMissing(title: book.title, index: chapter.index)
        }
        let current = sorted[position]
        let next = sorted.indices.contains(position + 1) ? position + 1 : nil
        var title = current.title
        var body = current.text
        let store = ReplaceRuleStore.shared
        if !store.rules.isEmpty {
            title = store.cleanTitle(title)
            body = store.cleanContent(body)
        }
        return BookChapterContent(
            title: title,
            text: body,
            nextChapterIndex: next
        )
    }
}
