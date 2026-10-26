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
    @State private var exploreSource: BookSource?
    @State private var editingSource: BookSource?
    @State private var sourceGroupFilter: String?
    @State private var sourceSortMode: Int = 0 // 0 默认 / 1 名称 / 2 URL
    @State private var exportURL: URL?
    @State private var showExport = false
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
            .fullScreenCover(item: $exploreSource) { source in
                ExploreView(initialSource: source).environmentObject(env)
            }
            .sheet(item: $editingSource) { source in
                SourceEditorView(source: source).environmentObject(env)
            }
            .sheet(isPresented: $showExport) {
                if let url = exportURL {
                    NavigationStack {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.badge.arrow.up")
                                .font(.system(size: 44)).foregroundStyle(ZJ.accent)
                            Text("已生成 \(env.sources.sources.count) 个书源 JSON")
                                .font(.system(size: 13)).foregroundStyle(ZJ.textSecondary)
                            // QR 码分享（栖阅对齐：JSON/URL/剪贴板/QR）
                            if let qr = try? QRCodeGenerator.generate(text: (try? String(contentsOf: url, encoding: .utf8)) ?? "") {
                                Image(uiImage: qr)
                                    .interpolation(.none)
                                    .resizable()
                                    .frame(width: 120, height: 120)
                                    .padding(8)
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                            } else {
                                Text("QR 生成失败（书源数据过大）").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            ShareLink(item: url) {
                                Label("分享 / 存储", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderedProminent).tint(ZJ.accent)
                            Button("完成") { showExport = false }.foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .navigationTitle("导出书源")
                    }
                }
            }
            .sheet(isPresented: $showImport) { importSheet }
            .alert("从 URL 导入", isPresented: $showURLImport) {
                TextField("https://…/bookSource.json", text: $urlText)
                Button("取消", role: .cancel) {}
                Button(LocalizationManager.tr("sources.import")) { importFromURL() }
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
        ScrollView {
            VStack(spacing: 12) {
                if !env.sources.groups.isEmpty {
                    HStack(spacing: 0) {
                        groupChips
                        Spacer(minLength: 0)
                        Menu {
                            Picker("排序", selection: $sourceSortMode) {
                                Text("默认").tag(0)
                                Text("按名称").tag(1)
                                Text("按 URL").tag(2)
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ZJ.textSecondary)
                                .frame(width: 32, height: 26)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(.trailing, 12)
                    }
                } else if sourceSortMode != 0 {
                    HStack {
                        Spacer()
                        Menu {
                            Picker("排序", selection: $sourceSortMode) {
                                Text("默认").tag(0)
                                Text("按名称").tag(1)
                                Text("按 URL").tag(2)
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ZJ.textSecondary)
                                .frame(width: 32, height: 26)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(.trailing, 12)
                    }
                }
                if env.sources.sources.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(ZJ.textTertiary)
                        Text("尚未导入书源").font(.system(size: 15, weight: .semibold)).foregroundStyle(ZJ.textPrimary)
                        Text("点右上角 + 粘贴或从 URL 导入 Legado 书源")
                            .font(.system(size: 12)).foregroundStyle(ZJ.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 70)
                }

                ForEach(filteredSources) { source in
                    sourceCard(source)
                }

                Text("长按可删除；支持 Legado 书源 JSON（单条或数组）。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ZJ.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
            }
            .padding(.horizontal, ZJ.pageMargin)
            .padding(.vertical, 10)
        }
    }

    private func sourceCard(_ source: BookSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(source.bookSourceName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ZJ.textPrimary)
                if loginStore.state(for: source.bookSourceUrl) != nil {
                    Text("已登录")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ZJ.celadon)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(ZJ.celadon.opacity(0.12), in: Capsule())
                }
                if let group = source.bookSourceGroup, !group.isEmpty {
                    Text(group)
                        .font(.system(size: 9))
                        .foregroundStyle(ZJ.textSecondary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(ZJ.bgElev2.opacity(0.7), in: Capsule())
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { source.enabled ?? true },
                    set: { _ in env.sources.toggle(source) }
                ))
                .labelsHidden()
                .tint(ZJ.accent)
            }

            Text(source.bookSourceUrl)
                .font(.system(size: 10.5))
                .foregroundStyle(ZJ.textTertiary)
                .lineLimit(1)

            HStack(spacing: 8) {
                if let loginUrl = source.loginUrl, !loginUrl.isEmpty {
                    chipButton("登录", icon: "person.badge.key") {
                        loginTarget = LoginTarget(source: source)
                    }
                }
                if !(source.exploreUrl ?? "").isEmpty {
                    chipButton("发现", icon: "square.grid.2x2") {
                        exploreSource = source
                    }
                }
                chipButton(LocalizationManager.tr("sources.health"), icon: "stethoscope") {
                    showHealth = true
                }
                Spacer()
                Text("\((source.respondTime ?? 0))ms")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(ZJ.textTertiary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ZJPaletteStore.current.cardBorder, lineWidth: 0.8)
        )
        .contextMenu {
            Button { editingSource = source } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive) { env.sources.remove(source) } label: {
                Label("删除书源", systemImage: "trash")
            }
        }
        .onTapGesture { editingSource = source }
    }

    private var filteredSources: [BookSource] {
        var list: [BookSource]
        if let group = sourceGroupFilter {
            list = env.sources.sources.filter { $0.bookSourceGroup == group }
        } else {
            list = env.sources.sources
        }
        switch sourceSortMode {
        case 1: list.sort { $0.bookSourceName.localizedStandardCompare($1.bookSourceName) == .orderedAscending }
        case 2: list.sort { $0.bookSourceUrl.localizedStandardCompare($1.bookSourceUrl) == .orderedAscending }
        default: break
        }
        return list
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                groupChip("全部", active: sourceGroupFilter == nil) { sourceGroupFilter = nil }
                ForEach(env.sources.groups, id: \.self) { group in
                    groupChip(group, active: sourceGroupFilter == group) { sourceGroupFilter = group }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func groupChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? .white : ZJ.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(active ? ZJ.accent : Color.white.opacity(0.5), in: Capsule())
                .overlay(Capsule().strokeBorder(ZJPaletteStore.current.cardBorder, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    private func chipButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(ZJ.accent)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(ZJ.accent.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
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
                Divider()
                Button { exportAll() } label: { Label("导出全部书源", systemImage: "square.and.arrow.up") }
                Button {
                    let removed = env.sources.deduplicate()
                    message = removed > 0 ? "已去重 \(removed) 个书源" : "没有重复书源"
                } label: { Label(LocalizationManager.tr("sources.duplicate"), systemImage: "rectangle.stack.badge.minus") }
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
                        Button(LocalizationManager.tr("sources.import")) { doImport(importText); showImport = false }
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
            if arg == "-showSourceList" { mode = .sources }
            if arg == "-exportAllSources" {
                mode = .sources
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    exportAll()
                }
            }
            if arg == "-editFirstSource" {
                mode = .sources
                editingSource = env.sources.sources.first
            }
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

    private func exportAll() {
        do {
            exportURL = try env.sources.exportJSON()
            showExport = true
        } catch {
            message = "导出失败：\(error.localizedDescription)"
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
