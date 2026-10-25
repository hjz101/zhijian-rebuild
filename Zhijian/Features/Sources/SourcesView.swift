import SwiftUI

struct SourcesView: View {
    enum Mode: String, CaseIterable { case search = "搜索", sources = "书源" }
    var initialKeyword: String? = nil
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var env: AppEnvironment
    @State private var mode: Mode = .search
    @State private var keyword = ""
    @State private var results: [(source: BookSource, books: [SourceBook], error: String?)] = []
    @State private var searching = false
    @State private var detail: SourceHit?
    @State private var showImport = false
    @State private var importText = ""
    @State private var showURLImport = false
    @State private var urlText = ""
    @State private var message: String?
    @State private var showHealth = false
    @State private var loginTarget: LoginTarget?
    @State private var page = 1
    @State private var hasMore = false
    @State private var loadingMore = false
    @State private var searchTask: Task<Void, Never>?
    @State private var searchStartedAt: Date?
    @State private var lastDuration: TimeInterval = 0
    @ObservedObject private var loginStore = SourceLoginStore.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(Mode.allCases, id: \.self) { item in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { mode = item }
                        } label: {
                            Text(item.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(mode == item ? .white : ZJ.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(mode == item ? ZJ.accent : Color.clear,
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.horizontal, ZJ.pageMargin)
                .padding(.top, 6)

                Group {
                    if mode == .search { searchPane } else { sourcesPane }
                }
            }
            .background(QiBackground())
            .navigationTitle(mode == .search ? "搜索" : "书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                toolbar
            }
            .sheet(item: $detail) { hit in BookDetailView(book: hit.book, source: hit.source) }
            .sheet(isPresented: $showHealth) { SourceHealthView() }
            .sheet(item: $loginTarget) { target in
                SourceLoginSheet(source: target.source)
            }
            .sheet(isPresented: $showImport) { importSheet }
            .alert("从 URL 导入", isPresented: $showURLImport) {
                TextField("https://…/bookSource.json", text: $urlText)
                Button("取消", role: .cancel) {}
                Button("导入") { importFromURL() }
            } message: { Text("支持 Legado 书源 JSON 地址（单条或数组）") }
            .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好") { message = nil }
            } message: { Text(message ?? "") }
            .onAppear(perform: handleLaunchArgs)
        }
    }

    // MARK: - 搜索

    private var searchPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(ZJ.textTertiary)
                TextField("搜索书名 / 作者", text: $keyword)
                    .submitLabel(.search)
                    .onSubmit(runSearch)
                if !keyword.isEmpty {
                    Button { keyword = ""; results = [] } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(ZJ.textTertiary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(ZJ.bgElev1, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, ZJ.pageMargin).padding(.vertical, 10)

            if searching {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在并发搜索 \(env.engines.enabledSources().count) 个书源…")
                        .font(.footnote).foregroundStyle(ZJ.textSecondary)
                    Spacer()
                    Button("取消") { cancelSearch() }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ZJ.error)
                }
                .padding(.horizontal, ZJ.pageMargin)
                .padding(.top, 18)
            }

            if !results.isEmpty && !searching {
                HStack {
                    Text("共 \(results.reduce(0) { $0 + $1.books.count }) 条 · \(results.count) 个书源")
                        .font(.system(size: 11))
                        .foregroundStyle(ZJ.textSecondary)
                    Spacer()
                    Text(String(format: "%.1fs", lastDuration))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(ZJ.textTertiary)
                    Button("重搜") { runSearch() }
                        .font(.system(size: 11))
                        .foregroundStyle(ZJ.accent)
                }
                .padding(.horizontal, ZJ.pageMargin)
                .padding(.bottom, 4)
            }

            List {
                if results.isEmpty && !searching {
                    Section {
                        ForEach(env.engines.enabledSources()) { s in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(s.bookSourceName).font(.system(size: 15, weight: .medium))
                                    Text(s.bookSourceUrl).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text("\((s.respondTime ?? 0))ms").font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                        }
                    } header: { Text("可用书源（\(env.engines.enabledSources().count)）") }
                } else {
                    ForEach(Array(results.enumerated()), id: \.offset) { _, group in
                        Section {
                            if let error = group.error {
                                Text(error).font(.system(size: 12)).foregroundStyle(.red)
                            }
                            ForEach(group.books, id: \.bookUrl) { b in
                                NavigationLink { BookDetailView(book: b, source: group.source) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(b.name).font(.system(size: 15, weight: .medium))
                                        Text("\(b.author) · \(b.lastChapter ?? "")").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text(group.source.bookSourceName)
                                Spacer()
                                if group.error == nil {
                                    Text("\(group.books.count) 条").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if hasMore && !searching {
                        Section {
                            Button {
                                loadMore()
                            } label: {
                                HStack {
                                    Spacer()
                                    if loadingMore { ProgressView() }
                                    else { Text("加载更多").font(.system(size: 13, weight: .medium)).foregroundStyle(ZJ.accent) }
                                    Spacer()
                                }
                            }
                            .disabled(loadingMore)
                        }
                    }
                }
            }.listStyle(.insetGrouped)
        }
    }

    // MARK: - 书源管理

    private var searchState: some View { EmptyView() }

    private var sourcesPane: some View {
        List {
            Section {
                ForEach(env.sources.sources) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(s.bookSourceName).font(.system(size: 15, weight: .medium))
                            if loginStore.state(for: s.bookSourceUrl) != nil {
                                Text("已登录")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(ZJ.celadon)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(ZJ.celadon.opacity(0.12), in: Capsule())
                            }
                            Spacer()
                            if let loginUrl = s.loginUrl, !loginUrl.isEmpty {
                                Button("登录") { loginTarget = LoginTarget(source: s) }
                                    .font(.system(size: 11, weight: .medium))
                            }
                            Toggle("", isOn: Binding(
                                get: { s.enabled ?? true },
                                set: { _ in env.sources.toggle(s) }
                            )).labelsHidden()
                        }
                        Text(s.bookSourceUrl).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { idx in idx.map { env.sources.sources[$0] }.forEach(env.sources.remove) }
            } header: {
                Text("已导入 \(env.sources.sources.count) 个书源")
            } footer: {
                Text("长按/左滑可删除；支持 Legado 书源 JSON（单条或数组）。")
            }
        }.listStyle(.insetGrouped)
    }

    // MARK: - 工具栏 / 导入

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showImport = true } label: { Label("粘贴 JSON 导入", systemImage: "doc.on.clipboard") }
                Button { showURLImport = true } label: { Label("从 URL 导入", systemImage: "link") }
                Button { importFromClipboard() } label: { Label("从剪贴板导入", systemImage: "clipboard") }
                Divider()
                Button { showHealth = true } label: { Label("书源体检 / 诊断", systemImage: "stethoscope") }
            } label: { Image(systemName: "plus") }
        }
    }

    private var importSheet: some View {
        NavigationStack {
            TextEditor(text: $importText)
                .font(.system(size: 12, design: .monospaced))
                .padding()
                .navigationTitle("导入书源")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showImport = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("导入") { doImport(importText); showImport = false }
                            .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }

    // MARK: - Actions

    private func handleLaunchArgs() {
        if let initialKeyword, !initialKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            keyword = initialKeyword
            mode = .search
            runSearch()
        }
        for arg in ProcessInfo.processInfo.arguments {
            if arg.hasPrefix("-autoSearch=") {
                keyword = String(arg.dropFirst(12)); mode = .search; runSearch()
            }
            if arg == "-showHealth" { showHealth = true }
            if arg == "-showSourceLogin" {
                if let source = env.sources.sources.first(where: {
                    ($0.loginUrl ?? "").isEmpty == false && ($0.loginUi ?? "").isEmpty == false
                }) ?? env.sources.sources.first(where: { ($0.loginUrl ?? "").isEmpty == false }) {
                    loginTarget = LoginTarget(source: source)
                } else {
                }
            }
        }
    }

    private func runSearch() {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return }
        searchTask?.cancel()
        page = 1
        hasMore = false
        searching = true
        searchStartedAt = Date()
        searchTask = Task {
            let outcome = await env.engines.search(kw, page: 1)
            guard !Task.isCancelled else { return }
            results = outcome
            hasMore = outcome.contains { $0.error == nil && !$0.books.isEmpty }
            lastDuration = Date().timeIntervalSince(searchStartedAt ?? Date())
            searching = false
            if ProcessInfo.processInfo.arguments.contains("-autoOpenFirstHit"),
               let first = results.first(where: { !$0.books.isEmpty }) {
                detail = SourceHit(book: first.books[0], source: first.source)
            }
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        searching = false
        loadingMore = false
    }

    private func loadMore() {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty, !loadingMore else { return }
        loadingMore = true
        page += 1
        let targetPage = page
        Task {
            let outcome = await env.engines.search(kw, page: targetPage)
            guard !Task.isCancelled else { loadingMore = false; return }
            let added = merge(outcome)
            hasMore = added > 0
            loadingMore = false
        }
    }

    @discardableResult
    private func merge(_ outcome: [(source: BookSource, books: [SourceBook], error: String?)]) -> Int {
        var added = 0
        for group in outcome {
            let urls = Set(results.first(where: { $0.source.bookSourceUrl == group.source.bookSourceUrl })?.books.map(\.bookUrl) ?? [])
            added += group.books.filter { !urls.contains($0.bookUrl) }.count
            if let index = results.firstIndex(where: { $0.source.bookSourceUrl == group.source.bookSourceUrl }) {
                var existing = results[index].books
                let urls = Set(existing.map(\.bookUrl))
                existing.append(contentsOf: group.books.filter { !urls.contains($0.bookUrl) })
                results[index] = (group.source, existing, group.error ?? results[index].error)
            } else {
                results.append(group)
            }
        }
        return added
    }

    private func importFromClipboard() {
        guard let text = UIPasteboard.general.string else { message = "剪贴板为空"; return }
        doImport(text)
    }

    private func importFromURL() {
        let raw = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), url.scheme?.hasPrefix("http") == true else { message = "URL 无效"; return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let text = String(decoding: data, as: UTF8.self)
                await MainActor.run { doImport(text) }
            } catch { await MainActor.run { message = error.localizedDescription } }
        }
    }

    private func doImport(_ text: String) {
        do {
            try env.sources.importJSON(text)
            message = "导入成功，共 \(env.sources.sources.count) 个书源"
            mode = .sources
        } catch { message = error.localizedDescription }
    }
}

struct SourceHit: Identifiable {
    var id: String { book.bookUrl + source.bookSourceUrl }
    let book: SourceBook
    let source: BookSource
}

private struct LoginTarget: Identifiable {
    let id = UUID()
    let source: BookSource
}
