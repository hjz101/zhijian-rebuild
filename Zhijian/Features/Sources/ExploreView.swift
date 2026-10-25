// ExploreView.swift — 发现 / Explore（分类、筛选、分页、加书架）
import SwiftUI

struct ExploreView: View {
    @EnvironmentObject private var env: AppEnvironment
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

    private var exploreSources: [BookSource] {
        env.sources.sources.filter {
            ($0.enabled ?? true) && ($0.enabledExplore ?? true)
                && !($0.exploreUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            sourceBar
            categoryBar

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
                List {
                    ForEach(books, id: \.bookUrl) { book in
                        Button {
                            detail = SourceHit(book: book, source: selectedSource ?? BookSource())
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                AsyncImage(url: coverURL(book)) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else {
                                        RoundedRectangle(cornerRadius: 6).fill(ZJ.bgElev1)
                                    }
                                }
                                .frame(width: 52, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.name).font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(ZJ.textPrimary).lineLimit(1)
                                    Text(book.author).font(.system(size: 12)).foregroundStyle(ZJ.textSecondary)
                                    if !book.intro.isEmpty {
                                        Text(book.intro).font(.system(size: 11)).foregroundStyle(ZJ.textTertiary).lineLimit(2)
                                    }
                                    HStack(spacing: 6) {
                                        if !book.kind.isEmpty {
                                            Text(book.kind).font(.system(size: 10)).foregroundStyle(ZJ.accent)
                                        }
                                        if !book.lastChapter.isEmpty {
                                            Text(book.lastChapter).font(.system(size: 10)).foregroundStyle(ZJ.textTertiary).lineLimit(1)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }

                    if hasMore {
                        HStack {
                            Spacer()
                            if loadingMore {
                                ProgressView()
                            } else {
                                Button("加载更多") { loadMore() }
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(ZJ.accent)
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(ZJ.bgBase.ignoresSafeArea())
        .navigationTitle("发现")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { hit in
            BookDetailView(book: hit.book, source: hit.source)
                .environmentObject(env)
        }
        .task { await bootstrap() }
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
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundStyle(selectedSource?.bookSourceUrl == source.bookSourceUrl ? .white : ZJ.textSecondary)
                        .background(selectedSource?.bookSourceUrl == source.bookSourceUrl ? ZJ.accent : ZJ.bgElev1, in: Capsule())
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
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .foregroundStyle(selectedCategory?.id == category.id ? ZJ.accent : ZJ.textSecondary)
                            .background(selectedCategory?.id == category.id ? ZJ.accent.opacity(0.12) : ZJ.bgElev1, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, ZJ.pageMargin)
        }
        .padding(.bottom, 6)
    }

    private func bootstrap() async {
        if ProcessInfo.processInfo.arguments.contains("-autoExplore") {
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
        guard let source = selectedSource, let category = selectedCategory else { return }
        if reset { loading = true }
        defer { if reset { loading = false } }
        do {
            let pipeline = makePipeline(source)
            let result = try await pipeline.explore(category: category, page: page)
            if reset {
                books = result
            } else {
                let existing = Set(books.map { $0.bookUrl })
                books.append(contentsOf: result.filter { !existing.contains($0.bookUrl) })
            }
            hasMore = !result.isEmpty
            error = nil
        } catch {
            if reset { books = [] }
            self.error = error.localizedDescription
            hasMore = false
        }
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
