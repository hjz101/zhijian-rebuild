// ChapterCommentsSheet.swift — 章末评论（分页 / 点赞 / 回复 / @）
import SwiftUI

struct ChapterCommentsSheet: View {
    let bookId: String
    let chapterIndex: Int
    let chapterTitle: String
    let theme: ReaderTheme

    @ObservedObject private var store = ChapterCommentStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var visibleCount: Int
    @State private var replyTarget: ChapterComment?

    init(bookId: String, chapterIndex: Int, chapterTitle: String, theme: ReaderTheme) {
        self.bookId = bookId
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.theme = theme
        var initial = 20
        for arg in ProcessInfo.processInfo.arguments where arg.hasPrefix("-chapterCommentsPageSize=") {
            if let value = Int(arg.dropFirst(25)), value > 0 { initial = value }
        }
        _visibleCount = State(initialValue: initial)
    }

    private var comments: [ChapterComment] {
        store.topLevelComments(bookId: bookId, chapterIndex: chapterIndex, limit: visibleCount)
    }

    private var total: Int { store.totalCount(bookId: bookId, chapterIndex: chapterIndex) }
    private var topLevelTotal: Int { store.topLevelCount(bookId: bookId, chapterIndex: chapterIndex) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("第 \(chapterIndex + 1) 章")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.secondary)
                            Text(chapterTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.text)
                        }
                        .padding(.bottom, 4)

                        if comments.isEmpty {
                            Text("还没有章末评论，读完这章来说两句。")
                                .font(.footnote)
                                .foregroundStyle(theme.secondary)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(comments) { comment in
                                commentRow(comment, isReply: false)
                                ForEach(store.replies(bookId: bookId, chapterIndex: chapterIndex, parentId: comment.id)) { reply in
                                    commentRow(reply, isReply: true)
                                        .padding(.leading, 34)
                                }
                            }
                            if topLevelTotal > comments.count {
                                Button {
                                    visibleCount += 20
                                } label: {
                                    Text("加载更多（已显示 \(comments.count)/\(topLevelTotal) 条）")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(theme.accent)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
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
                        Button {
                            self.replyTarget = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                }

                HStack(spacing: 8) {
                    TextField(replyTarget == nil ? "写章末评论…" : "回复…", text: $draft, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(10)
                        .background(theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    Button {
                        store.add(bookId: bookId, chapterIndex: chapterIndex,
                                  chapterTitle: chapterTitle, text: draft,
                                  replyToId: replyTarget?.id)
                        if replyTarget == nil {
                            visibleCount = max(visibleCount, topLevelTotal + 1)
                        }
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
            .navigationTitle("章末评论 · \(total)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    private func commentRow(_ comment: ChapterComment, isReply: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(theme.accent.opacity(isReply ? 0.55 : 0.85))
                .frame(width: isReply ? 22 : 28, height: isReply ? 22 : 28)
                .overlay(Text("我").font(.system(size: isReply ? 9 : 11, weight: .semibold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 5) {
                if isReply {
                    Text("回复 @\(comment.mentions.first ?? "我")")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.accent)
                }
                Text(comment.text)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.text)
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
                    Button {
                        store.toggleLike(comment.id)
                    } label: {
                        Label("\(comment.likes)", systemImage: comment.likedByMe ? "heart.fill" : "heart")
                            .font(.system(size: 11))
                            .foregroundStyle(comment.likedByMe ? theme.accent : theme.secondary)
                    }
                    .buttonStyle(.plain)
                    Button {
                        replyTarget = comment
                    } label: {
                        Label("回复", systemImage: "arrowshape.turn.up.left")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondary)
                    }
                    .buttonStyle(.plain)
                    Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondary)
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
