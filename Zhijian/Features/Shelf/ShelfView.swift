import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var showImporter = false
    @State private var importError: String?
    @State private var opening: Book?

    private var importTypes: [UTType] {
        var types: [UTType] = [.plainText, .text, .pdf]
        if let epub = UTType(filenameExtension: "epub") { types.append(epub) }
        if let cbz = UTType(filenameExtension: "cbz") { types.append(cbz) }
        if let zip = UTType(filenameExtension: "zip") { types.append(zip) }
        return types
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if env.books.books.isEmpty {
                    ContentUnavailableView("书架空空的", systemImage: "books.vertical",
                                           description: Text("导入 TXT，或到「书源」搜索一本书"))
                        .padding(.top, 80)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 18)], spacing: 22) {
                        ForEach(env.books.books) { book in
                            Button { opening = book } label: { BookCard(book: book) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { env.books.remove(book) } label: { Label("移出书架", systemImage: "trash") }
                                }
                        }
                    }.padding(ZJ.pageMargin)
                }
            }
            .background(ZJ.bgBase.ignoresSafeArea())
            .navigationTitle("书架")
            .onAppear(perform: handleLaunchArgs)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: { Image(systemName: "square.and.arrow.down") }
                }
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
                ReaderScreen(book: book)
                    .environmentObject(env)
            }
        }
    }
}

private struct BookCard: View {
    let book: Book
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10).fill(ZJ.bgElev2)
                    .aspectRatio(0.72, contentMode: .fit)
                    .overlay {
                        if let cover = book.coverURL, let url = URL(string: cover) {
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().scaledToFill()
                                } else {
                                    Text(String(book.title.prefix(1)))
                                        .font(.system(size: 34, weight: .semibold, design: .serif))
                                        .foregroundStyle(ZJ.textSecondary)
                                }
                            }
                        } else {
                            Text(String(book.title.prefix(1)))
                                .font(.system(size: 34, weight: .semibold, design: .serif))
                                .foregroundStyle(ZJ.textSecondary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if book.totalChapters > 0 {
                    Text("\(book.currentChapterIndex + 1)/\(book.totalChapters)")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.45), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            Text(book.title).font(.system(size: 13, weight: .medium)).foregroundStyle(ZJ.textPrimary).lineLimit(1)
            Text(book.author).font(.system(size: 11)).foregroundStyle(ZJ.textTertiary).lineLimit(1)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}


private extension ShelfView {
    func handleLaunchArgs() {
        let args = ProcessInfo.processInfo.arguments
        if let arg = args.first(where: { $0.hasPrefix("-autoOpenBookTitle=") }) {
            let title = String(arg.dropFirst(19))
            if let book = env.books.books.first(where: { $0.title.contains(title) }) { opening = book }
        } else if args.contains("-autoOpenFirstBook"), let book = env.books.books.first {
            opening = book
        }
    }
}
