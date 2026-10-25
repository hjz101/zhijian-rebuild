// MangaReader.swift — 本地漫画（CBZ/ZIP 图片流）分页阅读
import SwiftUI
import UIKit

struct MangaReaderScreen: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let book: Book
    @State private var pageIndex: Int
    @State private var pages: [URL] = []
    @State private var chromeVisible = true
    @State private var showCatalog = false
    @State private var loadError: String?
    @State private var scrollMode = false

    private var isTwoPage: Bool {
        env.settings.settings.mangaTwoPage
            && !scrollMode
            && UIDevice.current.orientation.isLandscape
            && pages.count > 2
    }

    init(book: Book) {
        self.book = book
        _pageIndex = State(initialValue: max(0, book.currentPageIndex))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if pages.isEmpty {
                if let loadError {
                    ContentUnavailableView("无法打开漫画", systemImage: "photo.on.rectangle", description: Text(loadError))
                } else {
                    ProgressView().tint(.white)
                }
            } else if scrollMode {
                MangaScrollView(pages: pages, pageIndex: $pageIndex)
                    .ignoresSafeArea()
            } else {
                TabView(selection: $pageIndex) {
                    ForEach(pages.indices, id: \.self) { index in
                        if isTwoPage, index % 2 == 0, pages.indices.contains(index + 1) {
                            // 双页：左页 + 右页并排
                            HStack(spacing: 0) {
                                MangaPageView(url: pages[index]) { ratio in
                                    if ratio < 0.16 { go(-1) }
                                    else if ratio > 0.84 { go(1) }
                                    else { chromeVisible.toggle() }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                MangaPageView(url: pages[index + 1]) { ratio in
                                    if ratio < 0.16 { go(-1) }
                                    else if ratio > 0.84 { go(1) }
                                    else { chromeVisible.toggle() }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .tag(index)
                        } else {
                            MangaPageView(url: pages[index]) { ratio in
                                if ratio < 0.16 { go(-1) }
                                else if ratio > 0.84 { go(1) }
                                else { withAnimation(.easeOut(duration: 0.2)) { chromeVisible.toggle() } }
                            }
                            .tag(index)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }
            if chromeVisible && !pages.isEmpty { chrome.transition(.opacity) }
        }
        .preferredColorScheme(.dark)
        .task {
            load()
            if ProcessInfo.processInfo.arguments.contains("-mangaScroll") {
                scrollMode = true
                env.settings.settings.mangaScrollMode = true
            } else if env.settings.settings.mangaDefaultScroll {
                scrollMode = true
            } else {
                scrollMode = env.settings.settings.mangaScrollMode
            }
        }
        .onChange(of: pageIndex) { _, _ in saveProgress() }
        .onDisappear { saveProgress() }
        .sheet(isPresented: $showCatalog) {
            MangaPageCatalog(pageCount: pages.count, current: pageIndex) { index in
                pageIndex = index
                saveProgress()
            }
        }
    }

    private var chrome: some View {
        VStack {
            HStack(spacing: 8) {
                glassButton("chevron.left") { saveProgress(); dismiss() }
                VStack(alignment: .leading, spacing: 1) {
                    Text(book.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text("第 \(min(pageIndex + 1, max(pages.count, 1))) / \(max(pages.count, 1)) 页")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                glassButton("chevron.up") { go(-1) }
                glassButton(scrollMode ? "rectangle.portrait" : "arrow.up.and.down") {
                    scrollMode.toggle()
                    env.settings.settings.mangaScrollMode = scrollMode
                }
                glassButton("square.grid.2x2") { showCatalog = true }
                glassButton("chevron.down") { go(1) }
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.4), radius: 14, y: 5)
            .padding(.horizontal, 14)
            .padding(.top, 6)

            Spacer()

            HStack(spacing: 10) {
                Text("\(pageIndex + 1)").font(.system(size: 10).monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                Slider(value: Binding(
                    get: { Double(pageIndex) },
                    set: { pageIndex = min(max(Int($0.rounded()), 0), max(pages.count - 1, 0)) }
                ), in: 0...Double(max(pages.count - 1, 1)))
                .tint(ZJ.accent)
                Text("\(pages.count)").font(.system(size: 10).monospacedDigit()).foregroundStyle(.white.opacity(0.6))
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
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func load() {
        guard pages.isEmpty else { return }
        let urls = MangaLibrary.shared.pageURLs(bookId: book.id)
        guard !urls.isEmpty else {
            loadError = "漫画图片不存在，请重新导入。"
            return
        }
        pages = urls
        var start = min(max(book.currentPageIndex, 0), urls.count - 1)
        for arg in ProcessInfo.processInfo.arguments where arg.hasPrefix("-mangaPage=") {
            if let value = Int(arg.dropFirst(11)) { start = min(max(value, 0), urls.count - 1) }
        }
        pageIndex = start
    }

    private func go(_ delta: Int) {
        pageIndex = min(max(pageIndex + delta, 0), max(pages.count - 1, 0))
    }

    private func saveProgress() {
        let ratio = pages.count > 1 ? Double(pageIndex) / Double(pages.count - 1) : 0
        env.books.markRead(book.id, chapter: 0, page: pageIndex, ratio: ratio)
    }
}

// MARK: - 单页（缩放 / 单击分区）

private struct MangaPageView: UIViewRepresentable {
    let url: URL
    let onTap: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .black
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 3
        scrollView.bouncesZoom = true
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.imageView = imageView
        imageView.image = UIImage(contentsOfFile: url.path)

        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        single.numberOfTapsRequired = 1
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        double.numberOfTapsRequired = 2
        single.require(toFail: double)
        single.delegate = context.coordinator
        double.delegate = context.coordinator
        scrollView.addGestureRecognizer(single)
        scrollView.addGestureRecognizer(double)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        if let imageView = context.coordinator.imageView, imageView.image == nil {
            imageView.image = UIImage(contentsOfFile: url.path)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: MangaPageView
        weak var imageView: UIImageView?
        private var singleTap: UITapGestureRecognizer?

        init(_ parent: MangaPageView) { self.parent = parent }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? UIScrollView else { return }
            if view.zoomScale > 1.05 { return }
            let ratio = gesture.location(in: view).x / max(view.bounds.width, 1)
            parent.onTap(ratio)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1.05 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / 2.5, height: scrollView.bounds.height / 2.5)
                scrollView.zoom(to: CGRect(origin: CGPoint(x: point.x - size.width / 2,
                                                          y: point.y - size.height / 2), size: size), animated: true)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

// MARK: - 页码目录

private struct MangaPageCatalog: View {
    let pageCount: Int
    let current: Int
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
                                .foregroundStyle(index == current ? .black : .white)
                                .background(index == current ? ZJ.accent : Color.white.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("页码 · \(pageCount) 页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}


// MARK: - 纵向长图

private struct MangaScrollView: View {
    let pages: [URL]
    @Binding var pageIndex: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { index in
                        MangaPageImage(url: pages[index])
                            .id(index)
                            .onAppear {
                                if index != pageIndex { pageIndex = index }
                            }
                    }
                }
            }
            .background(Color.black)
            .onAppear {
                let target = min(max(pageIndex, 0), max(pages.count - 1, 0))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }
}

private struct MangaPageImage: View {
    let url: URL

    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .background(Color.black)
        } else {
            Color.black.frame(height: 300)
        }
    }
}
