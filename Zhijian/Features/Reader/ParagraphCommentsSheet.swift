// ParagraphCommentsSheet.swift — 段评（点赞 / 回复 / @）
import SwiftUI

struct ParagraphCommentsSheet: View {
    let bookId: String
    let chapterIndex: Int
    let paragraphIndex: Int
    let paragraphText: String
    let theme: ReaderTheme

    @ObservedObject private var store = ParagraphCommentStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var replyTarget: ParagraphComment?

    private var comments: [ParagraphComment] {
        store.topLevelComments(bookId: bookId, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("第 \(paragraphIndex + 1) 段")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.secondary)
                        Text(paragraphText)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.text)
                            .lineLimit(4)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.text.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                        if comments.isEmpty {
                            Text("还没有段评，来说两句。")
                                .font(.footnote)
                                .foregroundStyle(theme.secondary)
                                .padding(.vertical, 12)
                        } else {
                            ForEach(comments) { comment in
                                commentRow(comment, isReply: false)
                                ForEach(store.replies(bookId: bookId, chapterIndex: chapterIndex,
                                                      paragraphIndex: paragraphIndex, parentId: comment.id)) { reply in
                                    commentRow(reply, isReply: true).padding(.leading, 34)
                                }
                            }
                        }
                    }
                    .padding(16)
                }

                if let replyTarget {
                    HStack {
                        Text("回复 @\(replyTarget.mentions.first ?? "我")")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.accent)
                        Spacer()
                        Button { self.replyTarget = nil } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                }

                HStack(spacing: 8) {
                    TextField(replyTarget == nil ? "写段评…" : "回复…", text: $draft, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(10)
                        .background(theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    Button {
                        store.add(bookId: bookId, chapterIndex: chapterIndex,
                                  paragraphIndex: paragraphIndex, text: draft,
                                  replyToId: replyTarget?.id)
                        draft = ""
                        replyTarget = nil
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(theme.accent, in: Circle())
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
                .background(.regularMaterial)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("段评 · \(comments.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private func commentRow(_ comment: ParagraphComment, isReply: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(theme.accent.opacity(isReply ? 0.55 : 0.85))
                .frame(width: isReply ? 22 : 26, height: isReply ? 22 : 26)
                .overlay(Text("我").font(.system(size: isReply ? 9 : 11, weight: .semibold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 5) {
                if isReply {
                    Text("回复 @\(comment.mentions.first ?? "我")")
                        .font(.system(size: 10)).foregroundStyle(theme.accent)
                }
                Text(comment.text).font(.system(size: 13)).foregroundStyle(theme.text)
                if !comment.mentions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(comment.mentions, id: \.self) { name in
                            Text("@\(name)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(theme.accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(theme.accent.opacity(0.10), in: Capsule())
                        }
                    }
                }
                HStack(spacing: 14) {
                    Button { store.toggleLike(comment.id) } label: {
                        Label("\(comment.likes)", systemImage: comment.likedByMe ? "heart.fill" : "heart")
                            .font(.system(size: 11))
                            .foregroundStyle(comment.likedByMe ? theme.accent : theme.secondary)
                    }
                    .buttonStyle(.plain)
                    Button { replyTarget = comment } label: {
                        Label("回复", systemImage: "arrowshape.turn.up.left")
                            .font(.system(size: 11)).foregroundStyle(theme.secondary)
                    }
                    .buttonStyle(.plain)
                    Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10)).foregroundStyle(theme.secondary)
                    Spacer()
                    Button { store.remove(comment.id) } label: {
                        Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(theme.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(theme.text.opacity(isReply ? 0.03 : 0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}
