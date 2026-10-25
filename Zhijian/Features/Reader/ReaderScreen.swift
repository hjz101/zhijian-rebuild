// ReaderScreen.swift — 阅读器入口与 SwiftUI 控制层
//
// 入口：ReaderScreen(book: Book)
// - 阅读页纸面质感（主题底色 + 暖光渐变 + 纸纹颗粒）
// - 玻璃顶栏：返回 / 目录 / 设置 / TTS；中央页区域点击中间 1/3 显隐控制层
// - 分页模式页码、滚动模式百分比；目录与设置 Sheet
import SwiftUI

struct ReaderScreen: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let book: Book

    @State private var model: ReaderViewModel?
    @State private var sessionStart = Date()
    @Environment(\.scenePhase) private var scenePhase

    init(book: Book) {
        self.book = book
    }

    var body: some View {
        Group {
            if MangaLibrary.shared.has(bookId: book.id) {
                MangaReaderScreen(book: book)
            } else if PDFLibrary.shared.has(bookId: book.id) {
                PDFReaderScreen(book: book)
            } else if EPUBContentStore.shared.hasManifest(bookId: book.id) {
                EPUBRichReaderScreen(book: book)
            } else {
                textReader
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { sessionStart = Date() }
        .onDisappear { flushReadingTime() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { flushReadingTime() }
        }
    }

    private func flushReadingTime() {
        let elapsed = Date().timeIntervalSince(sessionStart)
        if elapsed >= 5 { ReadingStatsStore.shared.add(seconds: elapsed, bookId: book.id) }
        sessionStart = Date()
    }

    private var textReader: some View {
        ZStack {
            ZJ.bgBase.ignoresSafeArea()
            if let model {
                ReaderSurface(
                    model: model,
                    settingsStore: env.settings,
                    tts: env.tts,
                    onClose: { dismiss() }
                )
            } else {
                ProgressView()
                    .tint(ZJ.accent)
            }
        }
        .onAppear(perform: prepareModel)
        .onDisappear {
            model?.persistNow()
            model?.stopTTS()
        }
    }

    private func prepareModel() {
        guard model == nil,
              !MangaLibrary.shared.has(bookId: book.id),
              !PDFLibrary.shared.has(bookId: book.id),
              !EPUBContentStore.shared.hasManifest(bookId: book.id) else { return }
        let created = ReaderViewModel(book: book, env: env)
        model = created
        Task {
            await created.start()
            if ProcessInfo.processInfo.arguments.contains("-autoTTS") {
                await created.toggleTTS()
            }
        }
    }
}

// MARK: - 阅读页

private struct ReaderSurface: View {
    let model: ReaderViewModel
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var tts: TTSController
    let onClose: () -> Void

    @State private var chromeVisible = true
    @State private var showCatalog = false
    @State private var showSettings = false
    @State private var showTitleDesigner = false
    @State private var noteDraft: NoteDraft?
    @State private var toast: String?
    @State private var showChangeSource = false
    @State private var scrollTTSRange: NSRange?
    @State private var commentTarget: ParagraphTarget?
    @State private var showParagraphList = false
    @State private var showChapterComments = false
    @ObservedObject private var chapterComments = ChapterCommentStore.shared
    @ObservedObject private var paragraphComments = ParagraphCommentStore.shared

    private var settings: ReadingSettings { settingsStore.settings }

    private func handleVolumeTurn(_ direction: Int) {
        guard settings.volumeButtonPageTurn, model.isPaged else { return }
        Task {
            if direction > 0 {
                await model.nextPage()
            } else {
                await model.previousPage()
            }
        }
    }
    private var theme: ReaderTheme { settings.theme }
    private var horizontalPadding: CGFloat { CGFloat(settings.horizontalPadding) }

    var body: some View {
        GeometryReader { geo in
            // 顶部为悬浮玻璃控制层留出空间，正文从控制层下方开始；底部留给页码。
            let topSpace: CGFloat = 64
            let bottomSpace: CGFloat = 44
            let pageSize = CGSize(
                width: max(140, geo.size.width - horizontalPadding * 2),
                height: max(180, geo.size.height - topSpace - bottomSpace)
            )

            ZStack {
                ReaderPaperBackground(theme: theme)
                    .ignoresSafeArea()

                readerContent(pageSize: pageSize)
                    .frame(width: pageSize.width, height: pageSize.height)
                    .position(x: geo.size.width / 2, y: topSpace + pageSize.height / 2)

                if chromeVisible {
                    chrome
                        .transition(.opacity)
                }

                pageIndicator
                statusOverlay

                VolumeButtonPageTurnMonitor(enabled: settings.volumeButtonPageTurn && model.isPaged,
                                            onTurn: handleVolumeTurn)
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
            }
            .onChange(of: pageSize, initial: true) { _, newSize in
                model.setViewport(newSize)
            }
        }
        .background(ZJ.bgBase)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .sheet(isPresented: $showCatalog) {
            ReaderCatalogSheet(model: model, theme: theme)
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(settingsStore: settingsStore)
        }
        .sheet(isPresented: $showTitleDesigner) {
            ChapterTitleDesignerView()
        }
        .sheet(isPresented: $showChangeSource) {
            ChangeSourceSheet(model: model, theme: theme)
        }
        .sheet(isPresented: $showChapterComments) {
            ChapterCommentsSheet(bookId: model.book.id,
                                 chapterIndex: model.currentChapterIndex,
                                 chapterTitle: model.chapterTitle,
                                 theme: theme)
        }
        .sheet(isPresented: $showParagraphList) {
            ParagraphCommentListSheet(bookId: model.book.id,
                                      chapterIndex: model.currentChapterIndex,
                                      paragraphs: bodyParagraphTexts,
                                      theme: theme)
        }
        .sheet(item: $commentTarget) { target in
            ParagraphCommentsSheet(bookId: model.book.id,
                                   chapterIndex: model.currentChapterIndex,
                                   paragraphIndex: target.index,
                                   paragraphText: paragraphText(at: target.index),
                                   theme: theme)
                .onDisappear { model.refreshAnnotations() }
        }
        .onChange(of: paragraphComments.items) { _, _ in
            model.refreshAnnotations()
        }
        .sheet(item: $noteDraft) { draft in
            NoteEditorSheet(draft: draft, theme: theme) { note in
                model.addNote(location: draft.location, length: draft.length, text: draft.text, note: note)
                showToast("笔记已保存")
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.72), in: Capsule())
                    .padding(.top, 74)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: chromeVisible)
        .onChange(of: tts.currentSegmentRange) { _, range in
            updateTTSHighlight(range)
        }
        .onChange(of: tts.isSpeaking) { _, speaking in
            if !speaking { model.setTTSHighlight(nil) }
        }
        .onAppear {
            updateTTSHighlight(tts.currentSegmentRange)
            if ProcessInfo.processInfo.arguments.contains("-showCatalog") {
                showCatalog = true
            }
            if ProcessInfo.processInfo.arguments.contains("-showChangeSource") {
                showChangeSource = true
            }
            if ProcessInfo.processInfo.arguments.contains("-showReaderSettings") {
                showSettings = true
            }
            if ProcessInfo.processInfo.arguments.contains("-showTitleDesigner") {
                showTitleDesigner = true
            }
            if ProcessInfo.processInfo.arguments.contains("-showChapterComments") {
                showChapterComments = true
            }
            if ProcessInfo.processInfo.arguments.contains("-showParagraphList") {
                showParagraphList = true
            }
            if ProcessInfo.processInfo.arguments.contains("-showParagraphComments") {
                Task {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    commentTarget = ParagraphTarget(index: 1)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TTSPlayerBar(tts: tts)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.74))
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
        }
    }

    // MARK: 正文

    @ViewBuilder
    private func readerContent(pageSize: CGSize) -> some View {
        if model.isPaged {
            if model.pages.isEmpty {
                Color.clear
            } else {
                PagedReaderView(
                    pages: model.pages,
                    currentIndex: model.pageIndex,
                    renderVersion: model.renderVersion,
                    theme: theme,
                    previousChapterTitle: model.previousChapterTitle,
                    nextChapterTitle: model.nextChapterTitle,
                    pageText: { model.attributedText(forPage: $0) },
                    onPageChanged: { model.didDisplayPage($0) },
                    onNextPage: { Task { await model.nextPage() } },
                    onPreviousPage: { Task { await model.previousPage() } },
                    onChapterBoundary: { direction in
                        Task {
                            if direction > 0 {
                                await model.nextChapter()
                            } else {
                                await model.previousChapter()
                            }
                        }
                    },
                    onToggleChrome: toggleChrome,
                    onHighlight: { location, length, text in
                        model.addHighlight(location: location, length: length, text: text)
                        showToast("已划线")
                    },
                    onNote: { location, length, text in
                        noteDraft = NoteDraft(location: location, length: length, text: text)
                    },
                    paragraphRanges: model.bodyParagraphRanges(),
                    commentCounts: paragraphComments.counts(bookId: model.book.id,
                                                             chapterIndex: model.currentChapterIndex),
                    onParagraphComment: { index in
                        commentTarget = ParagraphTarget(index: index)
                    },
                    chapterCommentCount: chapterComments.count(bookId: model.book.id,
                                                               chapterIndex: model.currentChapterIndex),
                    onChapterComments: { showChapterComments = true },
                    twoPage: model.isTwoPage,
                    animation: settings.pageTurnAnimation
                )
                .id("paged-\(settings.pageTurnAnimation.rawValue)")
            }
        } else if model.attributedChapter != nil {
            ScrollReaderView(
                attributed: model.attributedTextForScroll(),
                resetKey: "\(model.currentChapterIndex)-\(model.renderVersion)",
                renderVersion: model.renderVersion,
                initialRatio: model.scrollRatio,
                onProgress: { model.updateScrollRatio($0) },
                onToggleChrome: toggleChrome,
                ttsHighlightRange: scrollTTSRange,
                onHighlight: { location, length, text in
                    model.addHighlight(location: location, length: length, text: text)
                    showToast("已划线")
                },
                onNote: { location, length, text in
                    noteDraft = NoteDraft(location: location, length: length, text: text)
                }
            )
        } else {
            Color.clear
        }
    }

    private var bodyParagraphTexts: [String] {
        guard let attributed = model.attributedChapter else { return [] }
        let text = attributed.string as NSString
        return model.bodyParagraphRanges().compactMap { range in
            guard range.location >= 0, range.location + range.length <= text.length else { return nil }
            return text.substring(with: range)
        }
    }

    private func paragraphText(at index: Int) -> String {
        guard let attributed = model.attributedChapter else { return "" }
        let text = attributed.string as NSString
        let ranges = model.bodyParagraphRanges()
        guard ranges.indices.contains(index), ranges[index].length > 0,
              ranges[index].location >= 0,
              ranges[index].location + ranges[index].length <= text.length else { return "" }
        return text.substring(with: ranges[index])
    }

    private func updateTTSHighlight(_ range: NSRange?) {
        guard let range,
              tts.bookTitle == model.book.title,
              tts.chapterTitle == model.chapterTitle else {
            model.setTTSHighlight(nil)
            scrollTTSRange = nil
            return
        }
        model.setTTSHighlight(range)
        scrollTTSRange = range
    }

    private func toggleChrome() {
        withAnimation(.easeOut(duration: 0.2)) {
            chromeVisible.toggle()
        }
    }

    // MARK: 玻璃顶栏

    private var chrome: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 14)
                .padding(.top, 6)
            Spacer(minLength: 0)
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            glassButton("chevron.left", action: onClose)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.book.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            bookmarkButton
            glassButton("list.bullet", action: { showCatalog = true })
            glassButton("textformat", action: { showTitleDesigner = true })
            glassButton("textformat.size", action: { showSettings = true })
            ttsButton
            Menu {
                if !model.book.isLocal {
                    Button { showChangeSource = true } label: { Label("换源", systemImage: "arrow.left.arrow.right") }
                }
                Button {
                    let added = model.toggleBookmark()
                    showToast(added ? "已加入书签" : "已移除书签")
                } label: { Label(model.isCurrentChapterBookmarked ? "取消书签" : "加书签", systemImage: "bookmark") }
                Button {
                    showParagraphList = true
                } label: {
                    Label("段评（\(paragraphComments.items.filter { $0.bookId == model.book.id && $0.chapterIndex == model.currentChapterIndex }.count)）",
                          systemImage: "bubble.left.and.text.bubble.right")
                }
                Button {
                    showChapterComments = true
                } label: {
                    Label("章末评论（\(chapterComments.count(bookId: model.book.id, chapterIndex: model.currentChapterIndex))）",
                          systemImage: "text.bubble")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(theme.isDark ? 0.06 : 0.32)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(theme.isDark ? 0.08 : 0.55), lineWidth: 0.5))
                    .contentShape(Circle())
            }

        }
        .padding(8)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(theme.isDark ? 0.09 : 0.45), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(theme.isDark ? 0.30 : 0.10), radius: 14, y: 5)
    }

    private var subtitle: String {
        var pieces: [String] = []
        if !model.chapters.isEmpty {
            pieces.append("第 \(min(model.currentChapterIndex + 1, model.chapters.count)) / \(model.chapters.count) 章")
        }
        if !model.chapterTitle.isEmpty {
            pieces.append(model.chapterTitle)
        }
        pieces.append("\(model.progressPercent)%")
        return pieces.joined(separator: " · ")
    }

    private func glassButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(theme.isDark ? 0.06 : 0.32)))
                .overlay(Circle().strokeBorder(Color.white.opacity(theme.isDark ? 0.08 : 0.55), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var bookmarkButton: some View {
        Button {
            let added = model.toggleBookmark()
            showToast(added ? "已加入书签" : "已移除书签")
        } label: {
            Image(systemName: model.isCurrentChapterBookmarked ? "bookmark.fill" : "bookmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(model.isCurrentChapterBookmarked ? theme.accent : theme.text)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(
                        model.isCurrentChapterBookmarked
                            ? theme.accent.opacity(0.16)
                            : Color.white.opacity(theme.isDark ? 0.06 : 0.32)
                    )
                )
                .overlay(
                    Circle().strokeBorder(
                        Color.white.opacity(theme.isDark ? 0.08 : 0.55), lineWidth: 0.5
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.18)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.18)) {
                if toast == text { toast = nil }
            }
        }
    }

    private var ttsButton: some View {
        Button {
            Task { await model.toggleTTS() }
        } label: {
            Image(systemName: tts.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tts.isSpeaking ? theme.accent : theme.text)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(
                        tts.isSpeaking
                            ? theme.accent.opacity(0.16)
                            : Color.white.opacity(theme.isDark ? 0.06 : 0.32)
                    )
                )
                .overlay(
                    Circle().strokeBorder(
                        tts.isSpeaking ? theme.accent.opacity(0.35) : Color.white.opacity(theme.isDark ? 0.08 : 0.55),
                        lineWidth: 0.5
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 页码

    @ViewBuilder
    private var pageIndicator: some View {
        if model.chapterContent != nil, model.errorMessage == nil,
           settings.showPageNumber || !model.isPaged {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text(pageInfoText)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(theme.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.text.opacity(0.06), lineWidth: 0.5))
                .padding(.bottom, 4)
            }
            .allowsHitTesting(false)
        }
    }

    private var pageInfoText: String {
        if model.isPaged {
            let count = max(model.pageCount, 1)
            let index = min(model.pageIndex + 1, count)
            if model.isTwoPage {
                let right = min(index + 1, count)
                return "\(index)–\(right) / \(count) 页 · \(model.progressPercent)%"
            }
            return "第 \(index) / \(count) 页 · \(model.progressPercent)%"
        }
        let count = max(model.chapters.count, 1)
        return "第 \(model.currentChapterIndex + 1) / \(count) 章 · \(model.progressPercent)%"
    }

    // MARK: 加载 / 错误

    private var needsInitialLoading: Bool {
        if model.isLoadingChapters, model.chapters.isEmpty { return true }
        if model.chapterContent == nil { return true }
        if model.isPaged, model.pages.isEmpty { return true }
        return false
    }

    private var loadingText: String {
        if model.chapters.isEmpty { return "正在加载目录…" }
        if model.chapterContent == nil { return "正在获取正文…" }
        return "正在分页…"
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if let message = model.errorMessage {
            errorOverlay(message)
        } else if needsInitialLoading {
            loadingCard
        } else if model.isLoadingChapter {
            transitionLoadingPill
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(theme.accent)
                .scaleEffect(0.85)
            Text(loadingText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.text.opacity(0.06), lineWidth: 0.5))
    }

    private var transitionLoadingPill: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(theme.accent)
                    .scaleEffect(0.75)
                Text("正在加载 \(model.pendingChapterTitle ?? "章节")…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.text.opacity(0.06), lineWidth: 0.5))
            .padding(.top, 64)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func errorOverlay(_ message: String) -> some View {
        ZStack {
            theme.background.opacity(0.94)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "book.closed")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(theme.accent)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button {
                        Task { await model.retry() }
                    } label: {
                        Text("重试")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 22)
                            .frame(height: 38)
                            .background(Capsule().fill(theme.accent))
                    }
                    .buttonStyle(.plain)

                    Button(action: onClose) {
                        Text("返回")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .padding(.horizontal, 22)
                            .frame(height: 38)
                            .background(Capsule().fill(theme.text.opacity(0.08)))
                            .overlay(Capsule().strokeBorder(theme.text.opacity(0.12), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(26)
            .frame(maxWidth: 330)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(theme.isDark ? Color.white.opacity(0.05) : Color.white.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(theme.text.opacity(0.08), lineWidth: 0.5)
            )
            .padding(.horizontal, 28)
        }
    }
}

// MARK: - 笔记编辑

private struct NoteDraft: Identifiable {
    let id = UUID()
    let location: Int
    let length: Int
    let text: String
}

private struct NoteEditorSheet: View {
    let draft: NoteDraft
    let theme: ReaderTheme
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("原文")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondary)
                Text(draft.text)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(theme.text)
                    .lineSpacing(4)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.text.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

                Text("我的笔记")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondary)
                TextEditor(text: $note)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 120)
                    .background(theme.text.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                Spacer()
            }
            .padding(20)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("写笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(note)
                        dismiss()
                    }
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}

// MARK: - 纸面背景

private struct ReaderPaperBackground: View {
    let theme: ReaderTheme
    var body: some View {
        theme.background
            .ignoresSafeArea()
    }
}

private struct ParagraphTarget: Identifiable {
    let id = UUID()
    let index: Int
}
