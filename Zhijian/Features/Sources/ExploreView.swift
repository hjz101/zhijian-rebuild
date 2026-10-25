// ExploreView.swift — 发现 / Explore（分类、筛选、分页、加书架）
import SwiftUI

struct ExploreView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loginStore = SourceLoginStore.shared

    @State private var selectedSource: BookSource?
    @State private var categories: [SourcePipeline.ExploreCategory] = []
    @State private var selectedCategory: SourcePipeline.ExploreCategory?
    @State private var books: [SourceBook] = []
    @State private var page = 1
    @State private var loading = false
    @State private var loadingMore = false
    @State private var error: String?
    @State private var hasMore = true
    @State private var detail: SourceHit?
    @State private var notice: String?
    var initialSource: BookSource? = nil

    private var exploreSources: [BookSource] {
        env.sources.sources.filter {
            ($0.enabled ?? true) && ($0.enabledExplore ?? true)
                && !($0.exploreUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
        VStack(spacing: 0) {
            sourceBar
            categoryBar
            if let notice {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ZJ.gold)
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(ZJ.textSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button {
                        self.notice = nil
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ZJ.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(ZJ.gold.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            }

            if loading && books.isEmpty {
                Spacer()
                ProgressView("正在加载发现页…")
                Spacer()
            } else if let error, books.isEmpty {
                Spacer()
                ContentUnavailableView("发现页加载失败", systemImage: "antenna.radiowaves.left.and.right",
                                       description: Text(error))
                Spacer()
            } else if books.isEmpty {
                Spacer()
                ContentUnavailableView("暂无发现内容", systemImage: "square.grid.2x2",
                                       description: Text("选择一个有 exploreUrl 的书源和分类"))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(books, id: \.bookUrl) { book in
                            Button {
                                detail = SourceHit(book: book, source: selectedSource ?? BookSource())
                            } label: {
                                exploreCard(book)
                            }
                            .buttonStyle(QiPressStyle())
                        }

                        if hasMore {
                            Button {
                                loadMore()
                            } label: {
                                HStack {
                                    Spacer()
                                    if loadingMore { ProgressView() }
                                    else { Text("加载更多").font(.system(size: 13, weight: .medium)).foregroundStyle(ZJ.accent) }
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(loadingMore)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(QiBackground().ignoresSafeArea())
        .navigationTitle("发现")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
        .sheet(item: $detail) { hit in
            BookDetailView(book: hit.book, source: hit.source)
                .environmentObject(env)
        }
        .task { await bootstrap() }
        }
    }

    private var sourceBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(exploreSources) { source in
                    Button {
                        selectedSource = source
                        Task { await loadCategories() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(source.bookSourceName).font(.system(size: 12, weight: .medium))
                            if loginStore.state(for: source.bookSourceUrl) != nil {
                                Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 9))
                            }
                        }
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .foregroundStyle(selectedSource?.bookSourceUrl == source.bookSourceUrl ? .white : ZJ.textSecondary)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule().fill(selectedSource?.bookSourceUrl == source.bookSourceUrl ? ZJ.accent : Color.clear)
                        )
                        .overlay(Capsule().strokeBorder(ZJPaletteStore.current.cardBorder, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ZJ.pageMargin)
        }
        .padding(.vertical, 6)
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { category in
                    Button {
                        selectedCategory = category
                        Task { await loadFirstPage() }
                    } label: {
                        Text(category.title)
                            .font(.system(size: 11))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(selectedCategory?.id == category.id ? ZJ.accent : ZJ.textSecondary)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule().fill(selectedCategory?.id == category.id ? ZJ.accent.opacity(0.14) : Color.clear)
                            )
                            .overlay(Capsule().strokeBorder(ZJPaletteStore.current.cardBorder, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ZJ.pageMargin)
        }
        .padding(.bottom, 6)
    }

    private func exploreCard(_ book: SourceBook) -> some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: coverURL(book)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [ZJ.bgElev2, Color.white.opacity(0.5)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text(String(book.name.prefix(1)))
                            .font(.system(size: 24, design: .serif))
                            .foregroundStyle(ZJ.textSecondary)
                    }
                }
            }
            .frame(width: 64, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 5) {
                Text(book.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ZJ.textPrimary)
                    .lineLimit(2)
                Text(book.author)
                    .font(.system(size: 12))
                    .foregroundStyle(ZJ.textSecondary)
                    .lineLimit(1)
                if !book.intro.isEmpty {
                    Text(book.intro)
                        .font(.system(size: 11))
                        .foregroundStyle(ZJ.textTertiary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if !book.kind.isEmpty { tag(book.kind) }
                    if !book.lastChapter.isEmpty {
                        Text(book.lastChapter)
                            .font(.system(size: 10))
                            .foregroundStyle(ZJ.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ZJ.textTertiary)
                .padding(.top, 6)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(ZJPaletteStore.current.cardBorder, lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(ZJ.accent)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(ZJ.accent.opacity(0.10), in: Capsule())
    }

    private func bootstrap() async {
        if let initialSource {
            selectedSource = initialSource
        } else if ProcessInfo.processInfo.arguments.contains("-autoExplore") {
            selectedSource = exploreSources.first
        } else if selectedSource == nil {
            selectedSource = exploreSources.first
        }
        await loadCategories()
    }

    private func loadCategories() async {
        guard let source = selectedSource else { categories = []; return }
        loading = true
        error = nil
        defer { loading = false }
        let pipeline = makePipeline(source)
        do {
            categories = try await pipeline.exploreCategories()
            selectedCategory = categories.first
            if selectedCategory != nil { await loadFirstPage() }
            if categories.isEmpty {
                error = "该书源没有可用的 exploreUrl"
            }
        } catch {
            categories = []
            self.error = error.localizedDescription
        }
    }

    private func loadFirstPage() async {
        page = 1
        books = []
        hasMore = true
        await fetchPage(reset: true)
    }

    private func loadMore() {
        guard !loadingMore, hasMore, selectedCategory != nil else { return }
        loadingMore = true
        Task {
            page += 1
            await fetchPage(reset: false)
            loadingMore = false
        }
    }

    private func fetchPage(reset: Bool) async {
        guard let source = selectedSource, selectedCategory != nil else { return }
        if reset { loading = true }
        defer { if reset { loading = false } }
        let pipeline = makePipeline(source)
        var attempts = 0
        while true {
            guard let category = selectedCategory else { return }
            do {
                let result = try await pipeline.explore(category: category, page: page)
                if reset {
                    books = result
                } else {
                    let existing = Set(books.map { $0.bookUrl })
                    books.append(contentsOf: result.filter { !existing.contains($0.bookUrl) })
                }
                hasMore = !result.isEmpty
                error = nil
                return
            } catch {
                // 分类接口失效（站点改版/未登录）时自动尝试后面的分类，避免整页报错。
                if reset, attempts < 3,
                   let index = categories.firstIndex(where: { $0.id == category.id }),
                   index + 1 < categories.count {
                    attempts += 1
                    let next = categories[index + 1]
                    selectedCategory = next
                    let reason = Self.shortReason(error)
                    notice = "「\(category.title)」加载失败（\(reason)），已切换到「\(next.title)」"
                    continue
                }
                if reset { books = [] }
                self.error = error.localizedDescription
                hasMore = false
                return
            }
        }
    }

    private static func shortReason(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.contains("404") { return "接口 404" }
        if text.contains("超时") || text.lowercased().contains("timeout") { return "请求超时" }
        if text.contains("登录") { return "需要登录" }
        return String(text.prefix(28))
    }

    private func makePipeline(_ source: BookSource) -> SourcePipeline {
        SourcePipeline(source: source,
                       initialCookies: CookieStore.shared.snapshot(),
                       loginInfo: loginStore.loginInfo(for: source.bookSourceUrl),
                       loginHeader: loginStore.loginHeader(for: source.bookSourceUrl),
                       onCookiesChanged: { CookieStore.onChange($0) })
    }

    private func coverURL(_ book: SourceBook) -> URL? {
        let raw = book.coverUrl ?? ""
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
        if raw.hasPrefix("//") { return URL(string: "https:" + raw) }
        let base = RuleURLResolver.sourceBaseURL(selectedSource?.bookSourceUrl ?? "")
        return URL(string: raw, relativeTo: URL(string: base))
    }
}
