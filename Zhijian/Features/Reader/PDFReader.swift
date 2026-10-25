// PDFReader.swift — 本地 PDF 阅读（PDFKit）
import SwiftUI
import PDFKit

struct PDFReaderScreen: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let book: Book
    @State private var document: PDFDocument?
    @State private var pageIndex: Int
    @State private var pageCount = 0
    @State private var chromeVisible = true
    @State private var showCatalog = false
    @State private var loadError: String?
    @State private var pageTexts: [String] = []
    @State private var ttsHighlightPage = 0
    @State private var ttsHighlightText = ""

    init(book: Book) {
        self.book = book
        _pageIndex = State(initialValue: max(0, book.currentPageIndex))
    }

    private var theme: ReaderTheme { env.settings.settings.theme }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            if let document {
                PDFKitView(document: document,
                           pageIndex: $pageIndex,
                           highlightPage: ttsHighlightPage,
                           highlightText: ttsHighlightText,
                           theme: theme,
                           onTap: { ratio in
                               if ratio < 0.18 { go(-1) }
                               else if ratio > 0.82 { go(1) }
                               else { withAnimation(.easeOut(duration: 0.2)) { chromeVisible.toggle() } }
                           })
                    .ignoresSafeArea(edges: .bottom)
            } else if let loadError {
                ContentUnavailableView("无法打开 PDF", systemImage: "doc.richtext", description: Text(loadError))
            } else {
                ProgressView().tint(theme.accent)
            }

            if chromeVisible { chrome.transition(.opacity) }

            PDFTTSEvents(tts: env.tts) { updateTTSHighlight() }
                .frame(width: 0, height: 0)
            PDFTTSBar(tts: env.tts)
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .task {
            load()
            if ProcessInfo.processInfo.arguments.contains("-pdfTTS") {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await toggleTTS()
            }
        }
        .onChange(of: pageIndex) { _, _ in saveProgress() }
        .onDisappear { saveProgress() }
        .sheet(isPresented: $showCatalog) {
            PDFPageCatalog(pageCount: pageCount, current: pageIndex, theme: theme) { page in
                pageIndex = page
                saveProgress()
            }
        }
    }

    private var chrome: some View {
        VStack {
            HStack(spacing: 8) {
                glassButton("chevron.left") { saveProgress(); dismiss() }
                VStack(alignment: .leading, spacing: 1) {
                    Text(book.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.text).lineLimit(1)
                    Text("第 \(min(pageIndex + 1, max(pageCount, 1))) / \(max(pageCount, 1)) 页")
                        .font(.system(size: 10)).foregroundStyle(theme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                glassButton("chevron.up") { go(-1) }
                glassButton("square.grid.2x2") { showCatalog = true }
                glassButton(env.tts.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2") {
                    Task { await toggleTTS() }
                }
                glassButton("chevron.down") { go(1) }
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(theme.isDark ? 0.09 : 0.45), lineWidth: 0.5))
            .shadow(color: .black.opacity(theme.isDark ? 0.3 : 0.1), radius: 14, y: 5)
            .padding(.horizontal, 14)
            .padding(.top, 6)

            Spacer()

            HStack(spacing: 10) {
                Text("\(pageIndex + 1)").font(.system(size: 10).monospacedDigit()).foregroundStyle(theme.secondary)
                Slider(value: Binding(
                    get: { Double(pageIndex) },
                    set: { pageIndex = min(max(Int($0.rounded()), 0), max(pageCount - 1, 0)) }
                ), in: 0...Double(max(pageCount - 1, 1)))
                .tint(theme.accent)
                Text("\(pageCount)").font(.system(size: 10).monospacedDigit()).foregroundStyle(theme.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
    }

    private func glassButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(theme.isDark ? 0.06 : 0.32)))
                .overlay(Circle().strokeBorder(Color.white.opacity(theme.isDark ? 0.08 : 0.55), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func load() {
        guard document == nil else { return }
        guard let url = PDFLibrary.shared.url(bookId: book.id) else {
            loadError = "PDF 文件不存在，请重新导入。"
            return
        }
        guard let doc = PDFDocument(url: url) else {
            loadError = "PDF 解析失败"
            return
        }
        document = doc
        pageCount = doc.pageCount
        pageTexts = (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
        var start = min(max(book.currentPageIndex, 0), max(doc.pageCount - 1, 0))
        for arg in ProcessInfo.processInfo.arguments where arg.hasPrefix("-pdfPage=") {
            if let value = Int(arg.dropFirst(9)) { start = min(max(value, 0), max(doc.pageCount - 1, 0)) }
        }
        pageIndex = start
    }

    private func go(_ delta: Int) {
        pageIndex = min(max(pageIndex + delta, 0), max(pageCount - 1, 0))
    }

    private func toggleTTS() async {
        if env.tts.isSpeaking {
            env.tts.stop()
            ttsHighlightText = ""
            return
        }
        guard pageTexts.indices.contains(pageIndex), !pageTexts[pageIndex].isEmpty else { return }
        let text = pageTexts[pageIndex]
        if let controller = env.tts as? TTSController {
            controller.play(text: text, bookTitle: book.title, chapterTitle: "第 \(pageIndex + 1) 页")
        } else {
            await env.tts.speak(text)
        }
    }

    private func updateTTSHighlight() {
        guard env.tts.isSpeaking,
              env.tts.bookTitle == book.title else {
            if !ttsHighlightText.isEmpty { ttsHighlightText = "" }
            return
        }
        let sentence = env.tts.currentSentence
        guard !sentence.isEmpty else { return }
        var target = pageIndex
        if !(pageTexts.indices.contains(target) && pageTexts[target].contains(sentence)),
           let found = pageTexts.firstIndex(where: { $0.contains(sentence) }) {
            target = found
        }
        if target != pageIndex { pageIndex = target }
        ttsHighlightPage = target
        ttsHighlightText = sentence
    }

    private func saveProgress() {
        let ratio = pageCount > 1 ? Double(pageIndex) / Double(pageCount - 1) : 0
        env.books.markRead(book.id, chapter: 0, page: pageIndex, ratio: ratio)
    }
}

// MARK: - PDFKit

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var pageIndex: Int
    let highlightPage: Int
    let highlightText: String
    let theme: ReaderTheme
    let onTap: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.usePageViewController(false)
        view.backgroundColor = UIColor(theme.background)
        view.pageShadowsEnabled = false
        // 顶部给玻璃控制层留出空间，底部给页码滑杆留出空间
        view.pageBreakMargins = UIEdgeInsets(top: 64, left: 8, bottom: 112, right: 8)
        context.coordinator.pdfView = view
        context.coordinator.observe()
        if document.pageCount > 0 {
            let target = document.page(at: min(max(pageIndex, 0), document.pageCount - 1))!
            DispatchQueue.main.async { view.go(to: target) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak view] in
                view?.go(to: target)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak coordinator = context.coordinator] in
            coordinator?.isReady = true
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        view.backgroundColor = UIColor(theme.background)
        context.coordinator.applyHighlight(page: highlightPage, text: highlightText, in: view, document: document)

        guard document.pageCount > 0,
              let target = document.page(at: min(max(pageIndex, 0), document.pageCount - 1)) else { return }
        if let current = view.currentPage {
            let currentIndex = document.index(for: current)
            if currentIndex == pageIndex { return }
        }
        view.go(to: target)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        private var observer: NSObjectProtocol?
        var isReady = false
        private var lastHighlightKey = ""

        init(_ parent: PDFKitView) { self.parent = parent }

        func observe() {
            observer = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged, object: pdfView, queue: .main
            ) { [weak self] _ in
                guard let self, self.isReady, let pdfView = self.pdfView,
                      let page = pdfView.currentPage,
                      let index = pdfView.document?.index(for: page) else { return }
                if index != self.parent.pageIndex { self.parent.pageIndex = index }
            }
        }

        func applyHighlight(page: Int, text: String, in view: PDFView, document: PDFDocument) {
            let key = "\(page)|\(text)"
            guard key != lastHighlightKey else { return }
            lastHighlightKey = key
            guard !text.isEmpty,
                  let target = document.page(at: min(max(page, 0), max(document.pageCount - 1, 0))),
                  let pageText = target.string,
                  let range = pageText.range(of: text) else {
                view.highlightedSelections = nil
                return
            }
            if let selection = target.selection(for: NSRange(range, in: pageText)) {
                selection.color = UIColor(red: 0.85, green: 0.64, blue: 0.25, alpha: 0.38)
                view.highlightedSelections = [selection]
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let ratio = gesture.location(in: view).x / max(view.bounds.width, 1)
            parent.onTap(ratio)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

// MARK: - 页码目录

private struct PDFPageCatalog: View {
    let pageCount: Int
    let current: Int
    let theme: ReaderTheme
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 10)], spacing: 10) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Button {
                            onSelect(index); dismiss()
                        } label: {
                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: index == current ? .semibold : .regular).monospacedDigit())
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .foregroundStyle(index == current ? .white : theme.text)
                                .background(index == current ? theme.accent : theme.text.opacity(0.06),
                                            in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("页码 · \(pageCount) 页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.background)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}


// MARK: - TTS 观察桥

private struct PDFTTSEvents: View {
    @ObservedObject var tts: TTSController
    let onChange: () -> Void

    var body: some View {
        Color.clear
            .onChange(of: tts.currentSentence) { _, _ in onChange() }
            .onChange(of: tts.isSpeaking) { _, _ in onChange() }
    }
}

private struct PDFTTSBar: View {
    @ObservedObject var tts: TTSController

    var body: some View {
        VStack {
            Spacer()
            if tts.isSpeaking || tts.isPaused {
                TTSPlayerBar(tts: tts)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.74)))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 84)
            }
        }
        .animation(.easeOut(duration: 0.2), value: tts.isSpeaking)
    }
}
