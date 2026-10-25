import SwiftUI

struct BookDetailView: View {
    let book: SourceBook
    let source: BookSource
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var info: SourceBookInfo?
    @State private var chapters: [SourceChapter] = []
    @State private var loading = true
    @State private var error: String?
    @State private var added = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        RoundedRectangle(cornerRadius: 12).fill(ZJ.bgElev2)
                            .frame(width: 92, height: 128)
                            .overlay(
                                AsyncImage(url: resolvedCoverURL) { phase in
                                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                                    else { Text(String(book.name.prefix(1))).font(.system(size: 34, weight: .semibold, design: .serif)).foregroundStyle(ZJ.textSecondary) }
                                }
                            ).clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(info?.name ?? book.name).font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(ZJ.textPrimary)
                            Text(info?.author ?? book.author).font(.system(size: 13)).foregroundStyle(ZJ.textSecondary)
                            Text(source.bookSourceName).font(.system(size: 11)).foregroundStyle(ZJ.accent)
                            if let kind = info?.kind, !kind.isEmpty { Text(kind).font(.system(size: 11)).foregroundStyle(ZJ.textTertiary) }
                        }
                    }
                    let introText = info?.intro ?? book.intro ?? ""
                    if !introText.isEmpty {
                        Text(introText).font(.system(size: 14)).foregroundStyle(ZJ.textSecondary).lineSpacing(4)
                    }
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    if let error { Text(error).font(.system(size: 13)).foregroundStyle(.red) }
                    if !chapters.isEmpty {
                        Text("目录（\(chapters.count) 章）").font(.system(size: 16, weight: .semibold)).foregroundStyle(ZJ.textPrimary)
                        ForEach(chapters.prefix(30), id: \.url) { c in
                            HStack {
                                Text(c.title).font(.system(size: 14)).foregroundStyle(ZJ.textSecondary).lineLimit(2)
                                Spacer()
                            }.padding(.vertical, 3)
                        }
                    }
                }.padding(ZJ.pageMargin)
            }
            .background(ZJ.bgBase.ignoresSafeArea())
            .navigationTitle("书籍详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(added ? "已在书架" : "加入书架") { addToShelf() }.disabled(added)
                }
            }
            .task {
                await load()
                if ProcessInfo.processInfo.arguments.contains("-autoAddHit"), !chapters.isEmpty {
                    addToShelf()
                }
            }
        }
    }

    private var resolvedCoverURL: URL? {
        let raw = info?.coverUrl ?? book.coverUrl ?? ""
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
        if raw.hasPrefix("//") { return URL(string: "https:" + raw) }
        let base = source.bookSourceUrl.split(separator: "#").first.map(String.init) ?? source.bookSourceUrl
        if let url = URL(string: base), let abs = URL(string: raw, relativeTo: url) { return abs }
        return URL(string: raw)
    }

    private func load() async {
        loading = true; error = nil
        do {
            let pipeline = SourcePipeline(source: source,
                                          initialCookies: CookieStore.shared.snapshot(),
                                          loginInfo: SourceLoginStore.shared.loginInfo(for: source.bookSourceUrl),
                                          loginHeader: SourceLoginStore.shared.loginHeader(for: source.bookSourceUrl),
                                          onCookiesChanged: { CookieStore.onChange($0) })
            let i = try await pipeline.bookInfo(book)
            let toc = try await pipeline.toc(i)
            info = i; chapters = toc
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func addToShelf() {
        var b = Book.remote(book, source: source)
        b.totalChapters = chapters.count
        b.lastChapter = info?.lastChapter ?? book.lastChapter
        b.intro = info?.intro ?? book.intro
        b.kind = info?.kind ?? book.kind
        b.coverURL = resolvedCoverURL?.absoluteString
        env.books.add(b)
        added = true
    }
}
