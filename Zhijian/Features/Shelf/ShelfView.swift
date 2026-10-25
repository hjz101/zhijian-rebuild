import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var showImporter = false
    @State private var importError: String?
    @State private var opening: Book?
    @State private var showSources = false
    @State private var showExplore = false
    @State private var editing = false
    @State private var query = ""
    @State private var sourceSearchKeyword = ""
    @AppStorage("shelf.listMode") private var listMode = false
    @AppStorage("shelf.columns") private var columns = 3
    @State private var selectedGroup: String? = nil
    @State private var showGroupSheet = false
    @State private var moveTarget: Book?
    @AppStorage("shelf.sort") private var sortKey = "recent"

    private var importTypes: [UTType] {
        var types: [UTType] = [.plainText, .text, .pdf]
        if let epub = UTType(filenameExtension: "epub") { types.append(epub) }
        if let cbz = UTType(filenameExtension: "cbz") { types.append(cbz) }
        if let zip = UTType(filenameExtension: "zip") { types.append(zip) }
        return types
    }

    private var allGroups: [String] {
        Array(Set(env.books.books.compactMap { $0.groupName }.filter { !$0.isEmpty })).sorted()
    }

    private var books: [Book] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = env.books.books
        if let group = selectedGroup {
            list = list.filter { $0.groupName == group }
        }
        if !keyword.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(keyword)
                    || $0.author.localizedCaseInsensitiveContains(keyword)
            }
        }
        switch sortKey {
        case "added":
            return list.sorted { $0.addedAt > $1.addedAt }
        case "title":
            return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        default:
            return list.sorted {
                ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    searchBar
                    groupBar
                    if books.isEmpty {
                        emptyState
                    } else if listMode {
                        bookList
                    } else {
                        grid
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(QiBackground())
            .navigationBarHidden(true)
            .onAppear(perform: handleLaunchArgs)
            .sheet(isPresented: $showGroupSheet) {
                ShelfGroupSheet().environmentObject(env)
            }
            .sheet(item: $moveTarget) { book in
                GroupPickerSheet(book: book).environmentObject(env)
            }
            .sheet(isPresented: $showSources) {
                SourcesView(initialKeyword: sourceSearchKeyword).environmentObject(env)
            }
            .fullScreenCover(isPresented: $showExplore) {
                ExploreView().environmentObject(env)
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: importTypes,
                          allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    if url.pathExtension.lowercased() == "epub" {
                        _ = try LocalImportService.shared.importEPUB(url: url, into: env.books)
                    } else if url.pathExtension.lowercased() == "pdf" {
                        _ = try LocalImportService.shared.importPDF(url: url, into: env.books)
                    } else if ["cbz", "zip"].contains(url.pathExtension.lowercased()) {
                        _ = try LocalImportService.shared.importManga(url: url, into: env.books)
                    } else {
                        _ = try LocalImportService.shared.importTXT(url: url, into: env.books)
                    }
                } catch { importError = error.localizedDescription }
            }
            .alert("导入失败", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("好") { importError = nil }
            } message: { Text(importError ?? "") }
            .fullScreenCover(item: $opening) { book in
                ReaderScreen(book: book).environmentObject(env)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("书架")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(ZJ.textPrimary)
            Spacer()
            Menu {
                Picker("排序", selection: $sortKey) {
                    Text("最近阅读").tag("recent")
                    Text("添加时间").tag("added")
                    Text("书名").tag("title")
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ZJ.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Button(editing ? "完成" : "编辑") {
                withAnimation(.easeInOut(duration: 0.2)) { editing.toggle() }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(ZJ.textSecondary)
        }
        .padding(.top, 6)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ZJ.textTertiary)
                TextField("搜索书名或作者", text: $query)
                    .font(.system(size: 14))
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(ZJ.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 0.8)
            )

            iconButton("sparkles") { showExplore = true }
            iconButton("antenna.radiowaves.left.and.right") { showSources = true }
            iconButton("plus") { showImporter = true }
        }
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ZJ.textPrimary)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: max(2, min(5, columns))), spacing: 20) {
            ForEach(books) { book in
                ZStack(alignment: .topTrailing) {
                    Button {
                        if !editing { opening = book }
                    } label: {
                        BookCard(book: book)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { moveTarget = book } label: {
                            Label("移动到分组", systemImage: "folder")
                        }
                        if book.groupName != nil {
                            Button { env.books.setGroup(book.id, group: nil) } label: {
                                Label("移出分组", systemImage: "folder.badge.minus")
                            }
                        }
                        Button(role: .destructive) { env.books.remove(book) } label: {
                            Label("移出书架", systemImage: "trash")
                        }
                    }
                    if editing {
                        Button {
                            env.books.remove(book)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(ZJ.error)
                                .background(Circle().fill(.white))
                        }
                        .padding(6)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var groupBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("全部", active: selectedGroup == nil) { selectedGroup = nil }
                ForEach(allGroups, id: \.self) { group in
                    chip(group, active: selectedGroup == group) { selectedGroup = group }
                }
                Button { showGroupSheet = true } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ZJ.textSecondary)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? .white : ZJ.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(active ? ZJ.accent : Color.white.opacity(0.55), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private var bookList: some View {
        LazyVStack(spacing: 10) {
            ForEach(books) { book in
                Button {
                    if !editing { opening = book }
                } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(ZJ.bgElev2)
                            .frame(width: 52, height: 72)
                            .overlay {
                                if let cover = book.coverURL, let url = URL(string: cover) {
                                    AsyncImage(url: url) { phase in
                                        if case .success(let image) = phase {
                                            image.resizable().scaledToFill()
                                        } else {
                                            Text(String(book.title.prefix(1)))
                                                .font(.system(size: 22, design: .serif))
                                                .foregroundStyle(ZJ.textSecondary)
                                        }
                                    }
                                } else {
                                    Text(String(book.title.prefix(1)))
                                        .font(.system(size: 22, design: .serif))
                                        .foregroundStyle(ZJ.textSecondary)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title).font(.system(size: 15, weight: .medium))
                                .foregroundStyle(ZJ.textPrimary).lineLimit(1)
                            Text(book.author).font(.system(size: 11)).foregroundStyle(ZJ.textSecondary)
                            Text(book.lastChapter ?? "尚未开始").font(.system(size: 10)).foregroundStyle(ZJ.textTertiary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(ZJ.textTertiary)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.6), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { moveTarget = book } label: {
                        Label("移动到分组", systemImage: "folder")
                    }
                    if book.groupName != nil {
                        Button { env.books.setGroup(book.id, group: nil) } label: {
                            Label("移出分组", systemImage: "folder.badge.minus")
                        }
                    }
                    Button(role: .destructive) { env.books.remove(book) } label: {
                        Label("移出书架", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(ZJ.textTertiary)
            Text(query.isEmpty ? "书架是空的" : "没有匹配的书籍")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ZJ.textPrimary)
            Text(query.isEmpty ? "去搜索添加一些书籍吧" : "本地书架没有匹配，试试在线书源")
                .font(.system(size: 13))
                .foregroundStyle(ZJ.textSecondary)
            if !query.isEmpty {
                Button {
                    sourceSearchKeyword = query
                    showSources = true
                } label: {
                    Label("在书源中搜索「\(query)」", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(ZJ.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 150)
    }

    private func handleLaunchArgs() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-showExplore") || args.contains("-autoExplore") { showExplore = true }
        if args.contains(where: {
            $0 == "-showSources" || $0 == "-showHealth" || $0 == "-showSourceLogin" || $0.hasPrefix("-autoSearch=")
                || $0 == "-showBatchTest" || $0 == "-engineSelfTest"
        }) {
            showSources = true
        }
        if args.contains("-autoOpenFirstBook"), let book = env.books.books.first {
            opening = book
        }
        if let arg = args.first(where: { $0.hasPrefix("-autoOpenBookTitle=") }) {
            let title = String(arg.dropFirst(19))
            if let book = env.books.books.first(where: { $0.title == title }) { opening = book }
        }
    }
}

private struct BookCard: View {
    let book: Book

    private var progress: Double {
        guard book.totalChapters > 0 else { return 0 }
        return min(1, Double(book.currentChapterIndex + 1) / Double(book.totalChapters))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ZJ.bgElev2)
                    .aspectRatio(0.72, contentMode: .fit)
                    .overlay {
                        if let cover = book.coverURL, let url = URL(string: cover) {
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().scaledToFill()
                                } else {
                                    coverPlaceholder
                                }
                            }
                        } else {
                            coverPlaceholder
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            }
            Text(book.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ZJ.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(book.author)
                .font(.system(size: 11))
                .foregroundStyle(ZJ.textSecondary)
                .lineLimit(1)
            if progress > 0 {
                ProgressView(value: progress)
                    .tint(ZJ.accent)
                    .scaleEffect(x: 1, y: 0.6, anchor: .center)
            }
        }
    }

    private var coverPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [ZJ.bgElev2, Color.white.opacity(0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(String(book.title.prefix(1)))
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .foregroundStyle(ZJ.textSecondary)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
