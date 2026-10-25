// SourceBatchTestView.swift — 批量测试 UI（多关键词 × 多源 / 深度 / 导出）
import SwiftUI

struct SourceBatchTestView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SourceBatchTestStore.shared
    @State private var keywordsText = "剑来\n斗罗大陆"
    @State private var copied = false

    private var sources: [BookSource] { env.sources.sources.filter { $0.enabled ?? true } }
    private var keywords: [String] {
        keywordsText.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("关键词（每行一个）").font(.system(size: 11, weight: .semibold)).foregroundStyle(ZJ.textTertiary)
                    TextEditor(text: $keywordsText)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(height: 74)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(ZJ.bgElev1, in: RoundedRectangle(cornerRadius: 10))
                    HStack(spacing: 14) {
                        Toggle("深度测试（搜索→详情→目录→正文）", isOn: $store.deepTest)
                            .font(.system(size: 12))
                            .tint(ZJ.accent)
                        Spacer()
                        Stepper("并发 \(store.concurrency)", value: $store.concurrency, in: 1...4)
                            .font(.system(size: 12))
                    }
                    HStack {
                        Text("\(sources.count) 个启用书源 × \(keywords.count) 个关键词 = \(sources.count * keywords.count) 项")
                            .font(.system(size: 11)).foregroundStyle(ZJ.textSecondary)
                        Spacer()
                        if store.running {
                            Text("\(store.completed)/\(store.total)").font(.system(size: 11).monospacedDigit()).foregroundStyle(ZJ.accent)
                        }
                    }
                }
                .padding(ZJ.pageMargin)

                if store.rows.isEmpty && !store.running {
                    ContentUnavailableView("还没有测试结果", systemImage: "checklist",
                                           description: Text("设置关键词后点击「开始批量测试」"))
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(store.rows) { row in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: row.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(row.ok ? ZJ.celadon : Color(hex: 0xD65745))
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(row.sourceName).font(.system(size: 13, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                                        Text("· \(row.keyword)").font(.system(size: 11)).foregroundStyle(ZJ.textTertiary)
                                        Spacer()
                                        Text("\(row.milliseconds)ms").font(.system(size: 10).monospacedDigit()).foregroundStyle(ZJ.textTertiary)
                                    }
                                    Text(row.detail).font(.system(size: 11)).foregroundStyle(ZJ.textSecondary).lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(ZJ.bgBase.ignoresSafeArea())
            .navigationTitle("批量测试")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !store.rows.isEmpty {
                        ShareLink(item: store.reportText) { Image(systemName: "square.and.arrow.up") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button {
                        Task { await store.run(sources: sources, keywords: keywords) }
                    } label: {
                        HStack(spacing: 8) {
                            if store.running { ProgressView().tint(.white) }
                            Text(store.running ? "测试中…" : "开始批量测试")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(ZJ.accent, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(store.running || sources.isEmpty || keywords.isEmpty)

                    if !store.rows.isEmpty {
                        Button {
                            UIPasteboard.general.string = store.reportText
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                        } label: {
                            Text(copied ? "已复制" : "复制报告")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ZJ.textSecondary)
                                .padding(.horizontal, 12).padding(.vertical, 12)
                                .background(ZJ.bgElev1, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(.horizontal, ZJ.pageMargin)
                .padding(.bottom, 8)
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-autoBatchTest") {
                    Task { await store.run(sources: sources, keywords: keywords) }
                }
            }
        }
    }
}
