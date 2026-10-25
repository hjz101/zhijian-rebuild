// ParagraphCommentListSheet.swift — 整章段评侧栏（滚动/分页通用）
import SwiftUI

struct ParagraphCommentListSheet: View {
    let bookId: String
    let chapterIndex: Int
    let paragraphs: [String]
    let theme: ReaderTheme

    @ObservedObject private var store = ParagraphCommentStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var target: CommentTarget?

    var body: some View {
        NavigationStack {
            List {
                ForEach(paragraphs.indices, id: \.self) { index in
                    Button {
                        target = CommentTarget(index: index)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(theme.accent)
                                .frame(width: 22, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(paragraphs[index])
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.text)
                                    .lineLimit(2)
                                let count = store.comments(bookId: bookId, chapterIndex: chapterIndex,
                                                           paragraphIndex: index).count
                                Text(count > 0 ? "💬 \(count) 条段评" : "点此写段评")
                                    .font(.system(size: 10))
                                    .foregroundStyle(count > 0 ? theme.accent : theme.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(theme.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("段评 · \(paragraphs.count) 段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .sheet(item: $target) { item in
                ParagraphCommentsSheet(bookId: bookId, chapterIndex: chapterIndex,
                                       paragraphIndex: item.index,
                                       paragraphText: paragraphs[safe: item.index] ?? "",
                                       theme: theme)
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}

private struct CommentTarget: Identifiable {
    let id = UUID()
    let index: Int
}
