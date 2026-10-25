// EPUBRichReader.swift — EPUB 富文本阅读（WKWebView 渲染原始 XHTML/CSS/图片）
import SwiftUI
import WebKit

struct EPUBRichReaderScreen: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let book: Book

    @State private var chapters: [EPUBImporter.RenderChapter] = []
    @State private var index: Int
    @State private var showCatalog = false
    @State private var showSettings = false
    @State private var chromeVisible = true
    @State private var scrollRatio: Double = 0
    @State private var pageNumber = 1
    @State private var pageCount = 1
    @State private var pageTurnToken = 0
    @State private var pageTurnDelta = 0
    @State private var ttsHighlightText = ""
    @State private var viewerImage: ImageViewerItem?
    private let initialPage: Int
    @State private var loadError: String?
    @State private var renderVersion = 0
    @State private var persistTask: Task<Void, Never>?

    init(book: Book) {
        self.book = book
        var start = max(0, book.currentChapterIndex)
        for arg in ProcessInfo.processInfo.arguments where arg.hasPrefix("-epubChapter=") {
            if let value = Int(arg.dropFirst(13)) { start = max(0, value) }
        }
        _index = State(initialValue: start)
        var page = 1
        for arg in ProcessInfo.processInfo.arguments where arg.hasPrefix("-epubPage=") {
            if let value = Int(arg.dropFirst(10)) { page = max(1, value) }
        }
        initialPage = page
    }

    private var theme: ReaderTheme { env.settings.settings.theme }
    private var current: EPUBImporter.RenderChapter? {
        chapters.indices.contains(index) ? chapters[index] : nil
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            if let current, let url = EPUBContentStore.shared.chapterURL(bookId: book.id, href: current.href) {
                EPUBWebView(
                    chapterURL: url,
                    rootURL: EPUBContentStore.shared.rootURL(bookId: book.id),
                    theme: theme,
                    settings: env.settings.settings,
                    renderVersion: renderVersion,
                    paged: env.settings.settings.pageMode == .paged,
                    pageTurnToken: pageTurnToken,
                    pageTurnDelta: pageTurnDelta,
                    initialPage: initialPage,
                    highlightText: ttsHighlightText,
                    onImageTap: { url in
                        viewerImage = ImageViewerItem(url: url, title: "图片")
                    },
                    onProgress: { ratio, page, pages in
                        scrollRatio = ratio
                        pageNumber = page
                        pageCount = pages
                        schedulePersist()
                    },
                    onTap: { ratio in
                        if env.settings.settings.pageMode == .paged {
                            if ratio < 0.18 { turnPage(-1) }
                            else if ratio > 0.82 { turnPage(1) }
                            else { withAnimation(.easeOut(duration: 0.2)) { chromeVisible.toggle() } }
                        } else {
                            if ratio < 0.18 { go(-1) }
                            else if ratio > 0.82 { go(1) }
                            else { withAnimation(.easeOut(duration: 0.2)) { chromeVisible.toggle() } }
                        }
                    },
                    onReady: { loadError = nil }
                )
                .ignoresSafeArea(edges: .bottom)
            } else if let loadError {
                ContentUnavailableView("无法打开 EPUB", systemImage: "book.closed", description: Text(loadError))
            } else {
                ProgressView().tint(theme.accent)
            }

            if chromeVisible {
                chrome
                    .transition(.opacity)
            }

            EPUBTTSEvents(tts: env.tts) {
                updateTTSHighlight()
            }
            .frame(width: 0, height: 0)

            EPUBTTSBar(tts: env.tts)
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .task {
            loadManifest()
            if ProcessInfo.processInfo.arguments.contains("-autoTTS") {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await toggleTTS()
            }
            if ProcessInfo.processInfo.arguments.contains("-showEpubImage"),
               let current,
               let chapterURL = EPUBContentStore.shared.chapterURL(bookId: book.id, href: current.href),
               let html = try? String(contentsOf: chapterURL, encoding: .utf8),
               let src = Self.firstImageSource(in: html),
               let url = URL(string: src, relativeTo: chapterURL) {
                viewerImage = ImageViewerItem(url: url, title: "图片")
            }
        }
        .sheet(isPresented: $showCatalog) {
            EPUBCatalogSheet(chapters: chapters, current: index, theme: theme) { target in
                index = target
                saveProgress()
            }
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(settingsStore: env.settings)
        }
        .onChange(of: env.tts.currentSentence) { _, _ in updateTTSHighlight() }
        .onChange(of: env.tts.isSpeaking) { _, _ in updateTTSHighlight() }
        .onChange(of: index) { _, _ in updateTTSHighlight() }
        .fullScreenCover(item: $viewerImage) { item in
            ImageViewerScreen(item: item)
        }
        .onDisappear { saveProgress() }
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                glassButton("chevron.left") { saveProgress(); dismiss() }
                VStack(alignment: .leading, spacing: 1) {
                    Text(book.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(env.settings.settings.pageMode == .paged
                         ? "第 \(pageNumber) / \(pageCount) 页 · 第 \(min(index + 1, max(chapters.count, 1))) / \(max(chapters.count, 1)) 章"
                         : "第 \(min(index + 1, max(chapters.count, 1))) / \(max(chapters.count, 1)) 章 · \(Int(scrollRatio * 100))%")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                glassButton("chevron.up") { go(-1) }
                glassButton("list.bullet") { showCatalog = true }
                glassButton("textformat.size") { showSettings = true }
                glassButton(env.tts.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2") {
                    Task { await toggleTTS() }
                }
                glassButton("chevron.down") { go(1) }
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(theme.isDark ? 0.09 : 0.45), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(theme.isDark ? 0.30 : 0.10), radius: 14, y: 5)
            .padding(.horizontal, 14)
            .padding(.top, 6)
            Spacer(minLength: 0)
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

    private func loadManifest() {
        guard chapters.isEmpty else { return }
        if let manifest = EPUBContentStore.shared.manifest(bookId: book.id) {
            chapters = manifest.chapters
            index = min(max(index, 0), max(manifest.chapters.count - 1, 0))
        } else {
            loadError = "EPUB 内容未解包，请重新导入。"
        }
    }

    private func go(_ delta: Int) {
        let target = index + delta
        guard chapters.indices.contains(target) else { return }
        saveProgress()
        index = target
        scrollRatio = 0
        renderVersion += 1
        saveProgress()
    }

    private static func firstImageSource(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)<img[^>]+src\s*=\s*["']([^"']+)["']"#),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
              match.numberOfRanges > 1 else { return nil }
        return (html as NSString).substring(with: match.range(at: 1))
    }

    private func updateTTSHighlight() {
        guard env.tts.isSpeaking,
              env.tts.bookTitle == book.title,
              env.tts.chapterTitle == (current?.title ?? "") else {
            if !ttsHighlightText.isEmpty { ttsHighlightText = "" }
            return
        }
        let sentence = env.tts.currentSentence
        if sentence != ttsHighlightText { ttsHighlightText = sentence }
    }

    private func turnPage(_ delta: Int) {
        if delta < 0 && pageNumber <= 1 { go(-1); return }
        if delta > 0 && pageNumber >= pageCount { go(1); return }
        pageTurnDelta = delta
        pageTurnToken += 1
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            saveProgress()
        }
    }

    private func saveProgress() {
        env.books.markRead(book.id, chapter: index, page: 0, ratio: scrollRatio)
    }

    private func toggleTTS() async {
        if env.tts.isSpeaking { env.tts.stop(); return }
        let text = LocalLibrary.shared.record(for: book.id)?.chapters[safe: index]?.text ?? ""
        guard !text.isEmpty else { return }
        await env.tts.play(text: text, bookTitle: book.title, chapterTitle: current?.title ?? "")
    }
}

// MARK: - WKWebView

private struct EPUBWebView: UIViewRepresentable {
    let chapterURL: URL
    let rootURL: URL
    let theme: ReaderTheme
    let settings: ReadingSettings
    let renderVersion: Int
    let paged: Bool
    let pageTurnToken: Int
    let pageTurnDelta: Int
    let initialPage: Int
    let highlightText: String
    let onImageTap: (URL) -> Void
    let onProgress: (Double, Int, Int) -> Void
    let onTap: (Double) -> Void
    let onReady: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "epub")
        controller.addUserScript(WKUserScript(source: Self.bridgeJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.isPagingEnabled = paged
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.alwaysBounceVertical = !paged
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.webView = webView
        context.coordinator.load(url: chapterURL, force: true)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        webView.scrollView.isPagingEnabled = paged
        webView.scrollView.alwaysBounceVertical = !paged
        context.coordinator.load(url: chapterURL, force: false)
        context.coordinator.applyPageTurn(token: pageTurnToken, delta: pageTurnDelta)
        context.coordinator.applyHighlight(highlightText)
    }

    static let bridgeJS = """
    (function(){
      function post(obj){ try { window.webkit.messageHandlers.epub.postMessage(obj); } catch(e){} }
      var last = -1;
      var paged = document.documentElement.classList.contains('zj-paged');
      function layoutPages(){
        if (!paged) { return; }
        var page = document.getElementById('zj-page');
        if (!page) { return; }
        var pageHeight = Math.max(200, window.innerHeight - 242);
        page.style.columnCount = '1';
        page.style.columnWidth = 'auto';
        page.style.columnGap = '0';
        page.style.width = Math.max(1, window.innerWidth - 48) + 'px';
        page.style.height = 'auto';
        var contentHeight = page.scrollHeight;
        var pages = Math.max(1, Math.ceil(contentHeight / pageHeight));
        var pageWidth = Math.max(1, window.innerWidth - 48);
        page.style.width = String(pages * pageWidth + (pages - 1) * 48) + 'px';
        page.style.height = pageHeight + 'px';
        page.style.columnCount = String(pages);
        page.style.columnGap = '48px';
        page.style.columnFill = 'auto';
      }
      function progress(){
        var maxX = document.documentElement.scrollWidth - window.innerWidth;
        var maxY = document.documentElement.scrollHeight - window.innerHeight;
        var r = paged ? (maxX > 0 ? window.scrollX / maxX : 0) : (maxY > 0 ? window.scrollY / maxY : 0);
        var pages = paged ? Math.max(1, Math.round((document.documentElement.scrollWidth + 24) / Math.max(window.innerWidth,1))) : 1;
        var page = paged ? Math.min(pages, Math.round(window.scrollX / Math.max(window.innerWidth,1)) + 1) : 1;
        if (Math.abs(r - last) > 0.01 || pages > 1) { last = r; post({type:'progress', ratio:r, page:page, pages:pages}); }
      }
      window.addEventListener('scroll', progress, {passive:true});
      window.addEventListener('resize', progress);
      document.addEventListener('click', function(e){
        var img = e.target.closest ? e.target.closest('img') : null;
        if (img) { e.preventDefault(); post({type:'image', src: img.currentSrc || img.src || ''}); return; }
        var a = e.target.closest ? e.target.closest('a') : null;
        if (a) { e.preventDefault(); post({type:'link', href:a.href || ''}); return; }
        post({type:'tap', ratio: (e.clientX || 0) / Math.max(window.innerWidth, 1)});
      }, true);
      layoutPages();
      progress();
      setTimeout(function(){ layoutPages(); progress(); }, 350);
      setTimeout(function(){ layoutPages(); progress(); }, 900);
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: EPUBWebView
        weak var webView: WKWebView?
        private var loadedKey: String?
        private var loading: String?
        private var requestedScroll: Double = 0
        private var requestedPage: Int = 1
        private var lastPageTurnToken: Int = 0
        private var lastHighlightText = ""

        init(_ parent: EPUBWebView) { self.parent = parent }

        func load(url: URL, force: Bool) {
            let styleKey = "\(parent.theme.rawValue)|\(parent.settings.fontSize)|\(parent.settings.lineHeight)|\(parent.settings.fontFamily.rawValue)|\(parent.paged)"
            let key = url.path + "#" + styleKey
            guard force || loadedKey != key else { return }
            guard loading != key else { return }
            loading = key
            guard let html = Self.composeHTML(chapterURL: url, theme: parent.theme, settings: parent.settings, paged: parent.paged) else {
                loading = nil
                return
            }
            loadedKey = key
            webView?.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loading = nil
            if parent.paged {
                let targetPage = max(requestedPage, parent.initialPage)
                requestedPage = targetPage
                let js = "window.scrollTo(Math.max(0, (window.innerWidth) * \(max(targetPage - 1, 0))), 0);"
                webView.evaluateJavaScript(js, completionHandler: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak webView] in
                    webView?.evaluateJavaScript(js, completionHandler: nil)
                }
            } else if requestedScroll > 0 {
                let js = "window.scrollTo(0, Math.max(0, (document.documentElement.scrollHeight - window.innerHeight) * \(requestedScroll)));"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
            applyHighlight(parent.highlightText)
            parent.onReady()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "progress":
                if let ratio = body["ratio"] as? Double {
                    requestedScroll = min(max(ratio, 0), 1)
                    let page = (body["page"] as? NSNumber)?.intValue ?? 1
                    let pages = (body["pages"] as? NSNumber)?.intValue ?? 1
                    requestedPage = page
                    parent.onProgress(requestedScroll, page, pages)
                }
            case "tap":
                if let ratio = body["ratio"] as? Double { parent.onTap(ratio) }
            case "image":
                if let src = body["src"] as? String, let url = URL(string: src) {
                    parent.onImageTap(url)
                }
            case "link":
                if let href = body["href"] as? String, let url = URL(string: href), !url.isFileURL {
                    UIApplication.shared.open(url)
                }
            default: break
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url, !url.isFileURL {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func applyHighlight(_ text: String) {
            guard text != lastHighlightText else { return }
            lastHighlightText = text
            let literal = Self.javaScriptLiteral(text)
            let js = """
            (function(){
              document.querySelectorAll('mark.zj-tts').forEach(function(m){
                var p = m.parentNode; while (m.firstChild) { p.insertBefore(m.firstChild, m); } p.removeChild(m);
              });
              var needle = \(literal);
              if (!needle) { return; }
              function attempt(value){
                var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
                var node;
                while ((node = walker.nextNode())) {
                  var idx = node.nodeValue.indexOf(value);
                  if (idx >= 0) {
                    var range = document.createRange();
                    range.setStart(node, idx); range.setEnd(node, idx + value.length);
                    var mark = document.createElement('mark');
                    mark.className = 'zj-tts';
                    mark.style.background = 'rgba(217,164,65,0.38)';
                    mark.style.color = 'inherit';
                    try { range.surroundContents(mark); } catch (e) { return false; }
                    mark.scrollIntoView({block:'center', inline:'center'});
                    return true;
                  }
                }
                return false;
              }
              if (!attempt(needle)) { attempt(needle.substring(0, Math.min(18, needle.length))); }
            })();
            """
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        static func javaScriptLiteral(_ text: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [text]),
                  let json = String(data: data, encoding: .utf8) else { return "\"\"" }
            return String(json.dropFirst().dropLast())
        }

        func applyPageTurn(token: Int, delta: Int) {
            guard token != lastPageTurnToken, token > 0 else { return }
            lastPageTurnToken = token
            let js = "window.scrollBy({left: window.innerWidth * \(delta), top: 0, behavior: 'smooth'});"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        // MARK: HTML 组装

        static func composeHTML(chapterURL: URL, theme: ReaderTheme, settings: ReadingSettings, paged: Bool) -> String? {
            guard let raw = try? String(contentsOf: chapterURL, encoding: .utf8) else { return nil }
            let body: String
            if let match = raw.range(of: #"(?is)<body[^>]*>(.*)</body>"#, options: .regularExpression) {
                var inner = String(raw[match])
                if let open = inner.range(of: ">", options: []) {
                    inner = String(inner[open.upperBound...])
                }
                if let close = inner.range(of: "</body>", options: .backwards) {
                    inner = String(inner[..<close.lowerBound])
                }
                body = inner
            } else {
                body = raw
            }
            let css = css(theme: theme, settings: settings, paged: paged)
            return """
            <!doctype html>
            <html class="\(paged ? "zj-paged" : "")"><head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
            <style>\(css)</style>
            </head><body><div id="zj-page">\(body)</div></body></html>
            """
        }

        static func css(theme: ReaderTheme, settings: ReadingSettings, paged: Bool) -> String {
            let bg = UIColor(theme.background).hexString
            let fg = UIColor(theme.text).hexString
            let accent = UIColor(theme.accent).hexString
            let font = settings.fontFamily == .songti
                ? "'Songti SC','STSong','Noto Serif CJK SC',serif"
                : "-apple-system,'PingFang SC',sans-serif"
            let line = 1.6 + settings.lineHeight / 40.0
            return """
            html,body{background:\(bg) !important;color:\(fg) !important;margin:0 !important;padding:0 !important;}
            body{font-family:\(font) !important;font-size:\(Int(settings.fontSize))px !important;line-height:\(line) !important;
                 padding:122px 24px 120px 24px !important;box-sizing:border-box !important;-webkit-text-size-adjust:100% !important;
                 word-wrap:break-word !important;overflow-wrap:break-word !important;}
            body *{color:\(fg) !important;max-width:100% !important;}
            p{margin:0 0 1em 0 !important;text-align:justify !important;}
            h1,h2,h3,h4{line-height:1.45 !important;margin:0 0 0.8em 0 !important;font-weight:600 !important;}
            h1{font-size:1.45em !important;text-align:center !important;margin-top:0.2em !important;}
            img{max-width:100% !important;height:auto !important;border-radius:6px !important;margin:0.8em auto !important;display:block !important;}
            a{color:\(accent) !important;text-decoration:none !important;}
            ::selection{background:\(accent)55 !important;}
            .zj-paged, .zj-paged body{height:100% !important;}
            .zj-paged body{padding:0 !important;margin:0 !important;overflow-x:auto !important;overflow-y:hidden !important;}
            .zj-paged #zj-page{box-sizing:border-box !important;margin:122px 0 120px 24px !important;max-width:none !important;}
            .zj-paged #zj-page img{max-height:calc(100vh - 270px) !important;}
            """
        }
    }
}

// MARK: - 目录

private struct EPUBCatalogSheet: View {
    let chapters: [EPUBImporter.RenderChapter]
    let current: Int
    let theme: ReaderTheme
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(chapters.enumerated()), id: \.offset) { offset, chapter in
                    Button {
                        onSelect(offset)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(offset + 1)")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(offset == current ? theme.accent : theme.secondary)
                                .frame(minWidth: 28, alignment: .trailing)
                            Text(chapter.title)
                                .font(.system(size: 14, weight: offset == current ? .semibold : .regular))
                                .foregroundStyle(offset == current ? theme.accent : theme.text)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("目录 · \(chapters.count) 章")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() }.tint(theme.accent) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.background)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}

// MARK: - 工具

extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}


// MARK: - TTS 观察桥（EPUB 视图不直接观察嵌套的 TTSController）

private struct EPUBTTSEvents: View {
    @ObservedObject var tts: TTSController
    let onChange: () -> Void

    var body: some View {
        Color.clear
            .onChange(of: tts.currentSentence) { _, _ in onChange() }
            .onChange(of: tts.isSpeaking) { _, _ in onChange() }
    }
}

private struct EPUBTTSBar: View {
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
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: tts.isSpeaking)
    }
}
