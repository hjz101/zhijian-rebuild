// ReaderViewModel.swift — 阅读器状态机（目录 / 正文 / 分页 / 翻页 / 预取 / 进度 / TTS）
//
// 只负责状态与调度，不依赖具体 UI：
// - 分页模式：ReaderViewModel 持有当前章正文的 NSAttributedString 与页范围，UI 只渲染单页；
// - 滚动模式：UI 用整章富文本滚动，ViewModel 只记录 scrollRatio；
// - 所有对 env.books / env.settings / env.tts 的写入都集中在 @MainActor 上。
import SwiftUI
import Observation
import Combine

@MainActor
@Observable
final class ReaderViewModel {

    // MARK: - 不可变依赖

    private(set) var book: Book
    @ObservationIgnored private let bookStore: BookStore
    @ObservationIgnored private let contentProvider: ReaderContentProviding
    @ObservationIgnored private let tts: TTSControlling
    @ObservationIgnored private let paginator = PaginationEngine()
    @ObservationIgnored private let annotationStore = AnnotationStore.shared
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    // MARK: - 可观察状态

    /// 阅读设置的镜像。SettingsStore 变化时由 Combine 同步进来，UI 读这里即可实时刷新。
    private(set) var settings: ReadingSettings

    private(set) var chapters: [Chapter] = []
    private(set) var currentChapterIndex: Int = 0
    private(set) var pageIndex: Int = 0
    private(set) var pages: [ReaderPage] = []
    private(set) var chapterContent: BookChapterContent?
    private(set) var attributedChapter: NSAttributedString?
    /// 每次富文本或页范围变化时自增，供 UIKit 层判断是否需要重建。
    private(set) var renderVersion = 0
    private(set) var isLoadingChapters = false
    private(set) var isLoadingChapter = false
    private(set) var isPaginating = false
    private(set) var errorMessage: String?
    private(set) var scrollRatio: Double = 0
    private(set) var pendingChapterTitle: String?
    /// TTS 当前句在本章的 UTF-16 范围（供分页高亮/自动翻页）。
    private(set) var ttsHighlightRange: NSRange?

    // MARK: - 私有缓存 / 任务

    /// 页尺寸（正文可用区域，由 SwiftUI GeometryReader 传入）。
    @ObservationIgnored private var pageSize: CGSize = .zero
    /// 双页模式下的单栏宽度（含 1/2 间距）
    @ObservationIgnored private(set) var columnWidth: CGFloat = 0
    static let twoPageGutter: CGFloat = 28
    /// 已下载章节正文，key 为 chapter.id。
    @ObservationIgnored private var contentCache: [String: BookChapterContent] = [:]
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    @ObservationIgnored private var stateGeneration = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored private var pendingChapterPosition: Int?

    // MARK: - 初始化

    init(book: Book, env: AppEnvironment) {
        self.book = book
        self.bookStore = env.books
        self.contentProvider = env.content
        self.tts = env.tts
        self.settings = env.settings.settings
        self.currentChapterIndex = max(0, book.currentChapterIndex)
        self.pageIndex = max(0, book.currentPageIndex)
        self.scrollRatio = Self.clampRatio(book.currentScrollRatio)

        env.settings.$settings
            .dropFirst()
            .sink { [weak self] value in
                Task { @MainActor in
                    self?.applySettings(value)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 派生状态

    var currentChapter: Chapter? {
        chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex] : nil
    }

    var chapterTitle: String { currentChapter?.title ?? book.title }

    var pageCount: Int { pages.count }

    /// 是否强制分页（滚动模式下超长章节自动切换）
    private(set) var forcedPagedForLongChapter = false
    private static let longChapterThreshold = 60_000

    var isPaged: Bool {
        if settings.pageMode == .scroll, forcedPagedForLongChapter { return true }
        return settings.pageMode == .paged
    }

    var previousChapterTitle: String? {
        chapters.indices.contains(currentChapterIndex - 1) ? chapters[currentChapterIndex - 1].title : nil
    }

    var nextChapterTitle: String? {
        chapters.indices.contains(currentChapterIndex + 1) ? chapters[currentChapterIndex + 1].title : nil
    }

    var bookProgress: Double {
        guard !chapters.isEmpty else { return 0 }
        let withinChapter: Double
        if settings.pageMode == .paged, !pages.isEmpty {
            withinChapter = Double(pageIndex + 1) / Double(pages.count)
        } else {
            withinChapter = Self.clampRatio(scrollRatio)
        }
        let value = (Double(currentChapterIndex) + withinChapter) / Double(chapters.count)
        return min(max(value, 0), 1)
    }

    var progressPercent: Int { Int((bookProgress * 100).rounded()) }

    /// 当前页纯文本，用于 TTS；滚动模式退化为整章文本。
    var currentPageText: String {
        guard let attributedChapter else { return "" }
        if settings.pageMode == .scroll { return attributedChapter.string }
        guard pages.indices.contains(pageIndex) else { return attributedChapter.string }
        let range = pages[pageIndex].range
        guard range.location >= 0, range.location + range.length <= attributedChapter.length else { return "" }
        return attributedChapter.attributedSubstring(from: range).string
    }

    // MARK: - 生命周期 / 加载

    func start() async {
        guard !started else { return }
        started = true
        await reloadChapters(restoreProgress: true)
        #if DEBUG
        seedDebugAnnotationsIfNeeded()
        #endif
    }

    #if DEBUG
    private func seedDebugAnnotationsIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-seedAnnotations"),
              let text = attributedChapter?.string,
              annotationStore.annotations(bookId: book.id).isEmpty else { return }
        if let r = text.range(of: "朋友说，山顶") {
            let ns = NSRange(r, in: text)
            annotationStore.addAnnotation(
                bookId: book.id, chapterIndex: currentChapterIndex, chapterTitle: chapterTitle,
                location: ns.location, length: ns.length, text: String(text[r]),
                note: "这里开始进入书庐的线索，注意“随意取阅”四个字。",
                kind: .note
            )
        }
        if let r = text.range(of: "雾忽然薄了") {
            let ns = NSRange(r, in: text)
            annotationStore.addAnnotation(
                bookId: book.id, chapterIndex: currentChapterIndex, chapterTitle: chapterTitle,
                location: ns.location, length: ns.length, text: String(text[r]),
                note: nil, kind: .highlight, colorHex: "#D9A441"
            )
        }
        _ = annotationStore.toggleBookmark(
            bookId: book.id, chapterIndex: currentChapterIndex,
            chapterTitle: chapterTitle, pageIndex: pageIndex
        )
        renderVersion += 1
    }
    #endif

    private func reloadChapters(restoreProgress: Bool) async {
        guard !isLoadingChapters else { return }
        isLoadingChapters = true
        errorMessage = nil
        let generation = beginGeneration()
        do {
            let list = try await contentProvider.chapters(for: book)
            guard generation == stateGeneration else { return }
            chapters = list
            isLoadingChapters = false
            guard !list.isEmpty else {
                errorMessage = ReaderContentError.emptyBook(book.title).localizedDescription
                return
            }
            let position = min(max(restoreProgress ? book.currentChapterIndex : currentChapterIndex, 0), list.count - 1)
            let landing: Landing = (restoreProgress && settings.pageMode == .paged)
                ? .page(max(0, book.currentPageIndex))
                : .first
            await loadChapter(position, landing: landing, resetScroll: restoreProgress)
        } catch is CancellationError {
            if generation == stateGeneration { isLoadingChapters = false }
        } catch {
            guard generation == stateGeneration else { return }
            isLoadingChapters = false
            errorMessage = friendly(error)
        }
    }

    private func loadChapter(_ position: Int, landing: Landing, resetScroll: Bool = false) async {
        guard chapters.indices.contains(position) else { return }
        let generation = beginGeneration()
        isLoadingChapter = true
        errorMessage = nil
        pendingChapterPosition = position
        pendingChapterTitle = chapters[position].title
        prefetchTask?.cancel()

        let chapter = chapters[position]
        do {
            let content = try await content(for: chapter)
            guard generation == stateGeneration else { return }

            let sourceWidth = isTwoPage ? columnSize(for: pageSize).width : pageSize.width
            let titleImage = await titleSnapshot(title: content.title, width: sourceWidth)
            let hasImages = !content.images.isEmpty
            if hasImages { await prefetchImages(content.images) }
            let attributed = ReaderTextBuilder.build(
                title: content.title,
                body: content.text,
                settings: settings,
                theme: settings.theme,
                titleImage: titleImage,
                pageWidth: sourceWidth,
                images: content.images,
                imageProvider: { ReaderImageCache.memoryImage($0) }
            )
            var layoutSize = pageSize
            if isTwoPage { layoutSize.width = columnSize(for: pageSize).width }
            columnWidth = layoutSize.width
            // R2-04：滚动模式下超长章节自动切分页
            forcedPagedForLongChapter = settings.pageMode == .scroll
                && settings.longChapterAutoPaged
                && content.text.count > Self.longChapterThreshold
            var newPages: [ReaderPage] = []
            if isPaged, layoutSize.width > 1, layoutSize.height > 1 {
                isPaginating = true
                let result = await paginator.paginate(
                    bookId: book.id,
                    chapterIndex: position,
                    layoutSignature: ReaderTextBuilder.layoutSignature(settings),
                    attributed: attributed,
                    pageSize: layoutSize
                )
                guard generation == stateGeneration else { return }
                isPaginating = false
                newPages = result.pages
            }
            guard generation == stateGeneration else { return }

            chapterContent = content
            currentChapterIndex = position
            attributedChapter = attributed
            pages = newPages
            pageIndex = resolvePage(landing, pages: newPages, textLength: attributed.length)
            renderVersion += 1
            pendingChapterPosition = nil
            pendingChapterTitle = nil

            if settings.pageMode == .scroll && !forcedPagedForLongChapter {
                switch landing {
                case .last:
                    scrollRatio = 1
                case .first, .page(_):
                    scrollRatio = resetScroll ? Self.clampRatio(book.currentScrollRatio) : 0
                case .offset:
                    break
                }
            } else {
                scrollRatio = newPages.isEmpty ? 0 : Double(pageIndex) / Double(newPages.count)
            }

            isLoadingChapter = false
            schedulePersist()
            prefetchNextChapter()

            // 排版期间视口又变了（旋转 / 分屏）：用最新尺寸再排一次。
            if settings.pageMode == .paged,
               !newPages.isEmpty,
               abs(pageSize.width - layoutSize.width) > 0.5 || abs(pageSize.height - layoutSize.height) > 0.5 {
                repaginateKeepingCurrentPage(anchor: newPages[pageIndex].range.location)
            }
        } catch is CancellationError {
            if generation == stateGeneration {
                isLoadingChapter = false
                isPaginating = false
            }
        } catch {
            guard generation == stateGeneration else { return }
            isLoadingChapter = false
            isPaginating = false
            pendingChapterTitle = nil
            errorMessage = friendly(error)
        }
    }

    private func content(for chapter: Chapter) async throws -> BookChapterContent {
        if let cached = contentCache[chapter.id] { return cached }
        let value = try await contentProvider.content(for: book, chapter: chapter)
        contentCache[chapter.id] = value
        trimContentCache()
        return value
    }

    private func trimContentCache() {
        if contentCache.count > 12 { contentCache.removeAll() }
    }

    // MARK: - 换源

    var currentSourceURL: String { book.sourceUrl ?? "" }

    /// 切换到另一个书源，保留当前章节序号与阅读进度。
    func changeSource(to candidate: SourceBook, source: BookSource) async {
        guard !book.isLocal else { return }
        var updated = book
        updated.sourceUrl = source.bookSourceUrl
        updated.bookUrl = candidate.bookUrl
        updated.title = candidate.name.isEmpty ? book.title : candidate.name
        updated.author = candidate.author
        updated.coverURL = candidate.coverUrl
        updated.intro = candidate.intro
        updated.lastChapter = candidate.lastChapter
        updated.totalChapters = 0
        book = updated
        bookStore.update(updated)
        contentProvider.invalidate(bookId: updated.id)

        contentCache.removeAll()
        chapters = []
        chapterContent = nil
        attributedChapter = nil
        pages = []
        errorMessage = nil
        await reloadChapters(restoreProgress: false)
    }

    // MARK: - 书签 / 划线 / 笔记

    var bookmarks: [ReadingBookmark] { annotationStore.bookmarks(bookId: book.id) }
    var notes: [ReadingAnnotation] { annotationStore.annotations(bookId: book.id) }

    var isCurrentChapterBookmarked: Bool {
        annotationStore.isBookmarked(bookId: book.id, chapterIndex: currentChapterIndex)
    }

    @discardableResult
    func toggleBookmark() -> Bool {
        let added = annotationStore.toggleBookmark(
            bookId: book.id,
            chapterIndex: currentChapterIndex,
            chapterTitle: chapterTitle,
            pageIndex: pageIndex
        )
        renderVersion += 1
        return added
    }

    func removeBookmark(_ id: String) {
        annotationStore.removeBookmark(id)
        renderVersion += 1
    }

    func addHighlight(location: Int, length: Int, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard length > 0, !trimmed.isEmpty else { return }
        let body = attributedChapter?.string ?? ""
        let anchor = StableTextCoordinate.makeAnchor(text: body, location: location)
        annotationStore.addAnnotation(
            bookId: book.id, chapterIndex: currentChapterIndex, chapterTitle: chapterTitle,
            location: location, length: length, text: trimmed,
            note: nil, kind: .highlight,
            anchor: anchor?.anchor, anchorOffset: anchor?.anchorOffset ?? 0
        )
        renderVersion += 1
    }

    func addNote(location: Int, length: Int, text: String, note: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard length > 0, !trimmed.isEmpty, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let body = attributedChapter?.string ?? ""
        let anchor = StableTextCoordinate.makeAnchor(text: body, location: location)
        annotationStore.addAnnotation(
            bookId: book.id, chapterIndex: currentChapterIndex, chapterTitle: chapterTitle,
            location: location, length: length, text: trimmed,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines), kind: .note,
            anchor: anchor?.anchor, anchorOffset: anchor?.anchorOffset ?? 0
        )
        renderVersion += 1
    }

    func removeAnnotation(_ id: String) {
        annotationStore.removeAnnotation(id)
        renderVersion += 1
    }

    func jumpToBookmark(chapterIndex: Int, pageIndex: Int) async {
        guard chapters.indices.contains(chapterIndex) else { return }
        if chapterIndex == currentChapterIndex, pages.indices.contains(pageIndex) {
            self.pageIndex = pageIndex
            renderVersion += 1
            schedulePersist()
        } else {
            await jumpToChapter(chapterIndex, page: pageIndex)
        }
    }

    private func jumpToChapter(_ chapterIndex: Int, page: Int) async {
        guard chapters.indices.contains(chapterIndex) else { return }
        await loadChapter(chapterIndex, landing: .page(max(0, page)))
    }

    // MARK: - 公开操作

    func retry() async {
        guard !isLoadingChapter, !isLoadingChapters else { return }
        errorMessage = nil
        if chapters.isEmpty {
            await reloadChapters(restoreProgress: true)
            return
        }
        let position = pendingChapterPosition ?? min(max(currentChapterIndex, 0), chapters.count - 1)
        if chapters.indices.contains(position) {
            contentCache.removeValue(forKey: chapters[position].id)
        }
        let landing: Landing = position == currentChapterIndex ? .page(pageIndex) : .first
        await loadChapter(position, landing: landing)
    }

    func selectChapter(_ position: Int) async {
        guard chapters.indices.contains(position), !isLoadingChapter, !isLoadingChapters else { return }
        guard position != currentChapterIndex || chapterContent == nil else { return }
        await loadChapter(position, landing: .first)
    }

    func nextPage() async {
        guard !isLoadingChapters, !isLoadingChapter, chapterContent != nil else { return }
        if settings.pageMode == .scroll {
            await nextChapter()
            return
        }
        if pages.indices.contains(pageIndex + 1) {
            pageIndex += 1
            scrollRatio = pages.isEmpty ? 0 : Double(pageIndex) / Double(pages.count)
            schedulePersist()
        } else if chapters.indices.contains(currentChapterIndex + 1) {
            await loadChapter(currentChapterIndex + 1, landing: .first)
        }
    }

    func previousPage() async {
        guard !isLoadingChapters, !isLoadingChapter, chapterContent != nil else { return }
        if settings.pageMode == .scroll {
            await previousChapter()
            return
        }
        if pageIndex > 0, pages.indices.contains(pageIndex - 1) {
            pageIndex -= 1
            scrollRatio = pages.isEmpty ? 0 : Double(pageIndex) / Double(pages.count)
            schedulePersist()
        } else if chapters.indices.contains(currentChapterIndex - 1) {
            await loadChapter(currentChapterIndex - 1, landing: .last)
        }
    }

    /// 正文/目录失败时是否提供「换源」入口（远程书才有意义）。
    var canChangeSource: Bool {
        !book.isLocal && !(book.sourceUrl ?? "").isEmpty
    }

    func nextChapter() async {
        guard !isLoadingChapters, !isLoadingChapter, chapters.indices.contains(currentChapterIndex + 1) else { return }
        await loadChapter(currentChapterIndex + 1, landing: .first)
    }

    func previousChapter() async {
        guard !isLoadingChapters, !isLoadingChapter, chapters.indices.contains(currentChapterIndex - 1) else { return }
        await loadChapter(currentChapterIndex - 1, landing: .last)
    }

    /// 用户滑动（UIPageViewController）落到新页时同步状态。
    func didDisplayPage(_ index: Int) {
        guard pages.indices.contains(index), index != pageIndex else { return }
        pageIndex = index
        scrollRatio = pages.isEmpty ? 0 : Double(index) / Double(pages.count)
        schedulePersist()
    }

    // MARK: - 尺寸 / 设置

    /// 预取本章图片（并发上限 3），保证首屏分页时图片附件尽量已就绪。
    private func prefetchImages(_ images: [ExtractedReaderImage]) async {
        guard !images.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var iterator = images.makeIterator()
            for _ in 0..<min(4, images.count) {
                if let item = iterator.next() {
                    group.addTask { _ = await ReaderImageCache.store.image(for: item.url,
                                                                               headers: item.headers,
                                                                               imageDecode: item.imageDecode,
                                                                               decodeJS: item.js) }
                }
            }
            while await group.next() != nil {
                if let item = iterator.next() {
                    group.addTask { _ = await ReaderImageCache.store.image(for: item.url,
                                                                           headers: item.headers,
                                                                           imageDecode: item.imageDecode,
                                                                           decodeJS: item.js) }
                }
            }
        }
    }

    /// 章节标题快照（仅在启用模板时生成，按标题+宽度缓存）。
    private var titleSnapshotCache: [String: UIImage] = [:]

    private func titleSnapshot(title: String, width: CGFloat) async -> UIImage? {
        let store = ChapterTitleTemplateStore.shared
        guard store.enabled, let template = store.selected, width > 1 else { return nil }
        let key = "\(template.id)|\(Int(width))|\(title)"
        if let hit = titleSnapshotCache[key] { return hit }
        guard let image = await ChapterTitleSnapshotService.shared.snapshot(template: template,
                                                                            title: title,
                                                                            width: width,
                                                                            theme: settings.theme) else { return nil }
        titleSnapshotCache[key] = image
        if titleSnapshotCache.count > 40 {
            titleSnapshotCache.removeAll()
            titleSnapshotCache[key] = image
        }
        return image
    }

    /// 双页生效条件：开关打开 + 横向（宽 > 高）+ 宽度足够。
    var isTwoPage: Bool {
        guard settings.pageMode == .paged, settings.twoPageEnabled else { return false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-forceTwoPage") { return true }
        #endif
        return pageSize.width > pageSize.height * 1.05 && pageSize.width >= 640
    }

    func columnSize(for size: CGSize) -> CGSize {
        let gutter = Self.twoPageGutter
        return CGSize(width: max(160, (size.width - gutter) / 2), height: size.height)
    }

    func setViewport(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let changed = abs(size.width - pageSize.width) > 0.5 || abs(size.height - pageSize.height) > 0.5
        guard changed else { return }
        let anchor = currentCharOffset
        pageSize = size
        guard settings.pageMode == .paged, attributedChapter != nil, !isLoadingChapter else { return }
        isPaginating = true
        let attributed = attributedChapter ?? NSAttributedString()
        let signature = ReaderTextBuilder.layoutSignature(settings)
        var layoutSize = pageSize
        if isTwoPage { layoutSize.width = columnSize(for: pageSize).width }
        columnWidth = layoutSize.width
        Task { @MainActor in
            let result = await paginator.paginate(bookId: book.id, chapterIndex: currentChapterIndex,
                                                  layoutSignature: signature, attributed: attributed,
                                                  pageSize: layoutSize)
            pages = result.pages
            renderVersion += 1
            pageIndex = resolvePage(.offset(anchor), pages: pages, textLength: attributed.length)
            isPaginating = false
        }
    }

    /// 由 SettingsStore 的 Combine 订阅调用；也允许 UI 主动调用（例如设置 Sheet 关闭后兜底）。
    func applySettings(_ newValue: ReadingSettings) {
        guard newValue != settings else { return }
        let previous = settings
        let anchor = currentCharOffset
        let wasScroll = previous.pageMode == .scroll
        settings = newValue

        let layoutChanged = ReaderTextBuilder.layoutSignature(newValue) != ReaderTextBuilder.layoutSignature(previous)
        let modeChanged = newValue.pageMode != previous.pageMode
        let themeChanged = newValue.theme != previous.theme
        guard modeChanged || layoutChanged || themeChanged else { return }
        guard let content = chapterContent else { return }

        if newValue.pageMode == .scroll {
            let width = pageSize.width
            let cachedTitle = titleSnapshotCache["\(ChapterTitleTemplateStore.shared.selectedID)|\(Int(width))|\(content.title)"]
            let rebuilt = ReaderTextBuilder.build(
                title: content.title,
                body: content.text,
                settings: newValue,
                theme: newValue.theme,
                titleImage: cachedTitle,
                pageWidth: width
            )
            attributedChapter = rebuilt
            renderVersion += 1
            if modeChanged {
                pages = []
                pageIndex = 0
            }
            if modeChanged, !wasScroll, rebuilt.length > 0 {
                scrollRatio = Self.clampRatio(Double(anchor) / Double(rebuilt.length))
            }
            return
        }

        if pages.isEmpty || modeChanged || layoutChanged {
            repaginateKeepingCurrentPage(anchor: anchor)
        } else if themeChanged {
            let width = isTwoPage ? columnSize(for: pageSize).width : pageSize.width
            let cachedTitle = titleSnapshotCache["\(ChapterTitleTemplateStore.shared.selectedID)|\(Int(width))|\(content.title)"]
            attributedChapter = ReaderTextBuilder.build(
                title: content.title,
                body: content.text,
                settings: newValue,
                theme: newValue.theme,
                titleImage: cachedTitle,
                pageWidth: width,
                images: content.images,
                imageProvider: { ReaderImageCache.memoryImage($0) }
            )
            renderVersion += 1
        }
    }

    private func repaginateKeepingCurrentPage(anchor: Int) {
        guard settings.pageMode == .paged,
              !isLoadingChapter,
              let attributed = attributedChapter,
              pageSize.width > 1, pageSize.height > 1 else { return }
        let generation = beginGeneration()
        let position = currentChapterIndex
        let signature = ReaderTextBuilder.layoutSignature(settings)
        let size = pageSize
        isPaginating = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.paginator.paginate(
                bookId: self.book.id,
                chapterIndex: position,
                layoutSignature: signature,
                attributed: attributed,
                pageSize: size
            )
            guard generation == self.stateGeneration else { return }
            self.pages = result.pages
            self.pageIndex = self.pageIndex(containing: anchor, in: result.pages, fallback: self.pageIndex)
            self.renderVersion += 1
            self.isPaginating = false
            self.scrollRatio = result.pages.isEmpty ? 0 : Double(self.pageIndex) / Double(result.pages.count)
            self.schedulePersist()
        }
    }

    // MARK: - 滚动进度

    func updateScrollRatio(_ ratio: Double) {
        let clamped = Self.clampRatio(ratio)
        if abs(clamped - scrollRatio) > 0.001 {
            scrollRatio = clamped
        }
        schedulePersist()
    }

    // MARK: - TTS

    func toggleTTS() async {
        if tts.isSpeaking {
            tts.stop()
            return
        }
        let text = currentPageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let controller = tts as? TTSController {
            controller.play(text: text, bookTitle: book.title, chapterTitle: chapterTitle)
        } else {
            await tts.speak(text)
        }
    }

    func stopTTS() {
        tts.stop()
    }

    // MARK: - 进度写回

    func persistNow() {
        guard !chapters.isEmpty else { return }
        persistTask?.cancel()
        bookStore.markRead(book.id, chapter: currentChapterIndex, page: pageIndex, ratio: bookProgress)
    }

    private func schedulePersist() {
        guard !chapters.isEmpty else { return }
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let self else { return }
            self.bookStore.markRead(self.book.id, chapter: self.currentChapterIndex, page: self.pageIndex, ratio: self.bookProgress)
        }
    }

    // MARK: - 预取

    private func prefetchNextChapter() {
        let next = currentChapterIndex + 1
        guard chapters.indices.contains(next) else { return }
        let chapter = chapters[next]
        guard contentCache[chapter.id] == nil else { return }
        prefetchTask?.cancel()
        prefetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, self.contentCache[chapter.id] == nil else { return }
            do {
                let content = try await self.contentProvider.content(for: self.book, chapter: chapter)
                guard !Task.isCancelled else { return }
                self.contentCache[chapter.id] = content
            } catch {
                // 预取失败静默：真正翻到下一章时再走错误提示与重试。
            }
        }
    }

    // MARK: - 页定位

    /// 更新 TTS 高亮；分页模式下若当前句不在本页，自动翻到对应页。
    func setTTSHighlight(_ range: NSRange?) {
        guard ttsHighlightRange != range else { return }
        ttsHighlightRange = range
        if let range, isPaged, !pages.isEmpty {
            let target = pageIndex(containing: range.location, in: pages, fallback: pageIndex)
            if target != pageIndex { pageIndex = target }
        }
        renderVersion += 1
    }

    /// 章节内非空段落的字符范围（标题为第 0 段）；段评以此索引。
    func paragraphRanges() -> [NSRange] {
        guard let text = attributedChapter?.string else { return [] }
        let ns = text as NSString
        var result: [NSRange] = []
        var location = 0
        for line in text.components(separatedBy: "\n") {
            let length = (line as NSString).length
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(NSRange(location: location, length: length))
            }
            location += length + 1
        }
        return result
    }

    /// 只含正文段落（排除标题与标题装饰），供段评使用。
    func bodyParagraphRanges() -> [NSRange] {
        guard let attributed = attributedChapter else { return [] }
        let ns = attributed.string as NSString
        let bodySize = settings.fontSize
        var result: [NSRange] = []
        var location = 0
        for line in attributed.string.components(separatedBy: "\n") {
            let length = (line as NSString).length
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, length > 0 {
                if let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? UIFont,
                   abs(Double(font.pointSize) - bodySize) < 0.6 {
                    result.append(NSRange(location: location, length: length))
                }
            }
            location += length + 1
        }
        return result
    }

    func refreshAnnotations() { renderVersion += 1 }

    /// 滚动模式整章富文本：叠加划线/笔记与 TTS 当前句。
    func attributedTextForScroll() -> NSAttributedString {
        guard let attributedChapter else { return NSAttributedString() }
        let mutable = NSMutableAttributedString(attributedString: attributedChapter)
        let anns = annotationStore.annotations(bookId: book.id, chapterIndex: currentChapterIndex)
        for ann in anns {
            let range = NSRange(location: ann.location, length: ann.length)
            guard range.location >= 0, range.location + range.length <= mutable.length else { continue }
            mutable.addAttribute(.backgroundColor, value: AnnotationStore.uiColor(hex: ann.colorHex), range: range)
            if ann.kind == .note {
                mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                mutable.addAttribute(.underlineColor, value: AnnotationStore.uiColor(hex: ann.colorHex, alpha: 0.9), range: range)
            }
        }
        if let ttsHighlightRange, ttsHighlightRange.location != NSNotFound {
            let range = ttsHighlightRange
            if range.location >= 0, range.location + range.length <= mutable.length {
                mutable.addAttribute(.backgroundColor,
                                     value: UIColor(red: 0.85, green: 0.64, blue: 0.25, alpha: 0.36),
                                     range: range)
            }
        }
        return mutable
    }

    /// 页文本缓存（renderVersion / 批注 / TTS 高亮变化时失效）
    private var pageTextCache: [Int: NSAttributedString] = [:]
    private var pageTextCacheVersion = -1

    func attributedText(forPage index: Int) -> NSAttributedString {
        // 缓存命中：renderVersion 与 TTS 高亮未变时直接复用（避免每次翻页重建）
        if pageTextCacheVersion == renderVersion, let cached = pageTextCache[index] {
            return cached
        }
        defer {
            pageTextCacheVersion = renderVersion
            if pageTextCache.count > 40 { pageTextCache.removeAll() }
        }
        let result = buildPageText(forPage: index)
        if pageTextCacheVersion != renderVersion {
            pageTextCache[index] = result
        }
        return result
    }

    private func buildPageText(forPage index: Int) -> NSAttributedString {
        guard let attributedChapter, pages.indices.contains(index) else { return NSAttributedString() }
        let range = pages[index].range
        guard range.location >= 0, range.location + range.length <= attributedChapter.length else {
            return NSAttributedString()
        }
        let substring = attributedChapter.attributedSubstring(from: range)
        let anns = annotationStore.annotations(bookId: book.id, chapterIndex: currentChapterIndex)
        let mutable = NSMutableAttributedString(attributedString: substring)
        if let ttsHighlightRange, ttsHighlightRange.location != NSNotFound {
            let overlap = NSIntersectionRange(ttsHighlightRange, range)
            if overlap.length > 0 {
                let local = NSRange(location: overlap.location - range.location, length: overlap.length)
                if local.location >= 0, local.location + local.length <= mutable.length {
                    mutable.addAttribute(.backgroundColor,
                                         value: UIColor(red: 0.85, green: 0.64, blue: 0.25, alpha: 0.36),
                                         range: local)
                }
            }
        }
        for ann in anns {
            let annRange = NSRange(location: ann.location, length: ann.length)
            let overlap = NSIntersectionRange(annRange, range)
            guard overlap.length > 0 else { continue }
            let local = NSRange(location: overlap.location - range.location, length: overlap.length)
            guard local.location >= 0, local.location + local.length <= mutable.length else { continue }
            mutable.addAttribute(.backgroundColor,
                                 value: AnnotationStore.uiColor(hex: ann.colorHex),
                                 range: local)
            if ann.kind == .note {
                mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: local)
                mutable.addAttribute(.underlineColor, value: AnnotationStore.uiColor(hex: ann.colorHex, alpha: 0.9), range: local)
            }
        }
        return mutable
    }

    private var currentCharOffset: Int {
        if pages.indices.contains(pageIndex) { return pages[pageIndex].range.location }
        if let attributedChapter, settings.pageMode == .scroll {
            return Int(Double(attributedChapter.length) * Self.clampRatio(scrollRatio))
        }
        return 0
    }

    private func pageIndex(containing offset: Int, in pages: [ReaderPage], fallback: Int) -> Int {
        guard !pages.isEmpty else { return 0 }
        let target = max(0, offset)
        for page in pages where target < page.range.location + page.range.length {
            return page.index
        }
        return pages.count - 1
    }

    private func resolvePage(_ landing: Landing, pages: [ReaderPage], textLength: Int) -> Int {
        guard !pages.isEmpty else { return 0 }
        switch landing {
        case .first:
            return 0
        case .last:
            return pages.count - 1
        case .page(let page):
            return min(max(page, 0), pages.count - 1)
        case .offset(let offset):
            _ = textLength
            return pageIndex(containing: offset, in: pages, fallback: 0)
        }
    }

    // MARK: - 工具

    private func beginGeneration() -> Int {
        stateGeneration += 1
        return stateGeneration
    }

    private static func clampRatio(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func friendly(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }

    // MARK: - 翻页落点

    private enum Landing {
        case first
        case last
        case page(Int)
        case offset(Int)
    }
}
