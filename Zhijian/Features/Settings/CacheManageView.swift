// CacheManageView.swift — 章节磁盘缓存管理
import SwiftUI

struct CacheManageView: View {
    @ObservedObject private var cache = ChapterCacheStore.shared
    @State private var summaries: [CachedBookSummary] = []
    @State private var showClearAll = false

    var body: some View {
        List {
            Section {
                HStack {
                    Label("缓存大小", systemImage: "internaldrive")
                    Spacer()
                    Text(cache.formattedSize).foregroundStyle(.secondary)
                }
                HStack {
                    Label("章节文件", systemImage: "doc.text")
                    Spacer()
                    Text("\(cache.chapterFileCount) 个").foregroundStyle(.secondary)
                }
                HStack {
                    Label("缓存书籍", systemImage: "books.vertical")
                    Spacer()
                    Text("\(cache.bookCount) 本").foregroundStyle(.secondary)
                }
            } footer: {
                Text(LocalizationManager.tr("cache.desc"))
            }

            Section("图片缓存") {
                HStack {
                    Label("正文图片", systemImage: "photo")
                    Spacer()
                    Text("\(ReaderImageStore.shared.fileCount) 张 · \(ReaderImageStore.shared.formattedSize)")
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    ReaderImageStore.shared.clear()
                } label: {
                    Label("清理正文图片缓存", systemImage: "trash")
                }
                .disabled(ReaderImageStore.shared.fileCount == 0)
            }

            Section("按书清理") {
                if summaries.isEmpty {
                    Text("暂无缓存").foregroundStyle(.secondary)
                }
                ForEach(summaries) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).foregroundStyle(ZJ.textPrimary)
                            Text("\(item.files) 个文件 · \(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            ChapterCacheStore.shared.remove(bookId: item.bookId)
                            reload()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Button("清理全部缓存", role: .destructive) { showClearAll = true }
            }
        }
        .scrollContentBackground(.hidden)
        .background(QiBackground())
        .navigationTitle("章节缓存")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            reload()
        }
        .confirmationDialog("清理全部缓存？", isPresented: $showClearAll, titleVisibility: .visible) {
            Button("清理", role: .destructive) {
                ChapterCacheStore.shared.clearAll()
                reload()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已缓存章节将被删除，下次阅读会重新下载。")
        }
    }

    private func reload() {
        cache.refreshStats()
        summaries = cache.summaries()
    }
}
