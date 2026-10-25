// ChangeSourceSheet.swift — 换源：按书名在其它启用书源聚合搜索并切换
import SwiftUI

struct ChangeSourceSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let model: ReaderViewModel
    let theme: ReaderTheme

    @State private var keyword: String
    @State private var results: [(source: BookSource, books: [SourceBook], error: String?)] = []
    @State private var searching = false
    @State private var switching: String?

    init(model: ReaderViewModel, theme: ReaderTheme) {
        self.model = model
        self.theme = theme
        _keyword = State(initialValue: model.book.title)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.secondary)
                    TextField("书名 / 作者", text: $keyword)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                    Button("搜索") { Task { await search() } }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
                .padding(10)
                .background(theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if searching { ProgressView("正在搜索其它书源…").padding(.top, 24) }

                List {
                    if results.isEmpty && !searching {
                        Text("没有找到其它书源的可换来源。")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondary)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(Array(results.enumerated()), id: \.offset) { _, group in
                        Section {
                            if let error = group.error {
                                Text(error).font(.system(size: 12)).foregroundStyle(.red)
                                    .listRowBackground(Color.clear)
                            }
                            ForEach(group.books, id: \.bookUrl) { candidate in
                                Button {
                                    switching = candidate.bookUrl + group.source.bookSourceUrl
                                    Task {
                                        await model.changeSource(to: candidate, source: group.source)
                                        switching = nil
                                        dismiss()
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(candidate.name)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundStyle(theme.text)
                                            Text("\(candidate.author) · \(candidate.lastChapter ?? "")")
                                                .font(.system(size: 11))
                                                .foregroundStyle(theme.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if switching == candidate.bookUrl + group.source.bookSourceUrl {
                                            ProgressView()
                                        } else {
                                            Image(systemName: "arrow.left.arrow.right")
                                                .font(.system(size: 12))
                                                .foregroundStyle(theme.accent)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                            }
                        } header: {
                            Text(group.source.bookSourceName)
                                .foregroundStyle(theme.secondary)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("换源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }.tint(theme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.background)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .task { await search() }
    }

    private func search() async {
        searching = true
        let groups = await env.engines.search(keyword)
        results = groups
            .filter { $0.source.bookSourceUrl != model.currentSourceURL }
            .filter { !$0.books.isEmpty || $0.error != nil }
            .map { (source: $0.source, books: $0.books, error: $0.error) }
        searching = false
    }
}
