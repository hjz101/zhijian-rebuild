// SourceHealthView.swift — 书源体检/诊断：四阶段测试 + HTTP/JS 日志
import SwiftUI

struct SourceHealthView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SourceHealthStore.shared

    @State private var keyword = "剑来"
    @State private var selected: BookSource?
    @State private var showSelfTest = false
    @State private var showBatchTest = false

    private var sources: [BookSource] {
        env.sources.sources.filter { $0.enabled ?? true }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "stethoscope").foregroundStyle(ZJ.celadon)
                    TextField("测试关键词", text: $keyword)
                        .submitLabel(.search)
                    Button {
                        Task { await store.checkAll(sources, keyword: keyword) }
                    } label: {
                        if store.batchRunning {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("全部体检").font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .disabled(store.batchRunning || sources.isEmpty)
                }
                .padding(10)
                .background(ZJ.bgElev1, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, ZJ.pageMargin)
                .padding(.vertical, 8)

                List {
                    if sources.isEmpty {
                        ContentUnavailableView("没有启用的书源", systemImage: "antenna.radiowaves.left.and.right",
                                               description: Text("先在书源页导入并启用书源"))
                            .listRowBackground(Color.clear)
                    }
                    ForEach(sources) { source in
                        Button { selected = source } label: { row(source) }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .swipeActions {
                                Button {
                                    Task { _ = await store.check(source, keyword: keyword) }
                                } label: { Label("体检", systemImage: "stethoscope") }
                                .tint(ZJ.celadon)
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(ZJ.bgBase.ignoresSafeArea())
            .navigationTitle("书源体检")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showSelfTest = true } label: { Label("引擎自检", systemImage: "checkmark.seal") }
                        Button { showBatchTest = true } label: { Label("批量测试", systemImage: "checklist") }
                    } label: {
                        Text("工具").font(.system(size: 13, weight: .medium))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .sheet(isPresented: $showSelfTest) { EngineSelfTestView() }
            .sheet(isPresented: $showBatchTest) { SourceBatchTestView().environmentObject(env) }
            .sheet(item: $selected) { source in
                SourceHealthDetailView(source: source, keyword: keyword)
                    .environmentObject(env)
            }
            .onAppear(perform: handleLaunchArgs)
        }
    }

    private func handleLaunchArgs() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-showHealthDetail"), let first = sources.first {
            selected = first
        }
        if args.contains("-autoHealthCheck") {
            Task { await store.checkAll(sources, keyword: keyword) }
        }
        if args.contains("-engineSelfTest") {
            showSelfTest = true
        }
        if args.contains("-showBatchTest") {
            showBatchTest = true
        }
    }

    private func row(_ source: BookSource) -> some View {
        let summary = store.summary(for: source)
        let running = store.running.contains(source.bookSourceUrl)
        return HStack(spacing: 10) {
            Circle()
                .fill(summary == nil ? ZJ.textTertiary.opacity(0.4) : (summary!.ok ? ZJ.celadon : Color(hex: 0xD65745)))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(source.bookSourceName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ZJ.textPrimary)
                if running {
                    Text("体检中…").font(.system(size: 11)).foregroundStyle(ZJ.textSecondary)
                } else if let summary {
                    Text(summary.ok
                         ? "\(summary.count) 条结果 · \(summary.milliseconds)ms · \(Self.timeText(summary.checkedAt))"
                         : "失败：\(summary.error ?? "未知")")
                        .font(.system(size: 11))
                        .foregroundStyle(summary.ok ? ZJ.textSecondary : Color(hex: 0xD65745))
                        .lineLimit(2)
                } else {
                    Text("未体检 · 点击查看详情").font(.system(size: 11)).foregroundStyle(ZJ.textTertiary)
                }
            }
            Spacer()
            if running { ProgressView().controlSize(.small) }
            else { Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(ZJ.textTertiary) }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private static func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}

// MARK: - 详情

struct SourceHealthDetailView: View {
    let source: BookSource
    let keyword: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SourceHealthStore.shared
    @State private var running = false
    @State private var showDiagnostics = false
    @State private var copied = false

    private var report: SourceHealthReport? { store.report(for: source) }
    private var summary: SourceHealthSummary? { store.summary(for: source) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    stages
                    diagnostics
                }
                .padding(ZJ.pageMargin)
            }
            .background(ZJ.bgBase.ignoresSafeArea())
            .navigationTitle(source.bookSourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task {
                        running = true
                        _ = await store.check(source, keyword: keyword)
                        running = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if running { ProgressView().tint(.white) }
                        Text(running ? "体检中…" : "运行四阶段体检（关键词：\(keyword)）")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(ZJ.accent, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, ZJ.pageMargin)
                    .padding(.bottom, 8)
                }
                .disabled(running)
            }
            .onAppear { showDiagnostics = false }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("书源地址").font(.system(size: 11, weight: .semibold)).foregroundStyle(ZJ.textTertiary)
            Text(source.bookSourceUrl).font(.system(size: 11, design: .monospaced)).foregroundStyle(ZJ.textSecondary).lineLimit(2)
            if let report {
                Text(report.ok ? "链路正常" : "链路失败")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(report.ok ? ZJ.celadon : Color(hex: 0xD65745))
                Text("关键词：\(report.keyword) · \(report.checkedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(ZJ.textTertiary)
            } else {
                Text("尚未体检").font(.system(size: 13)).foregroundStyle(ZJ.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ZJ.bgElev1, in: RoundedRectangle(cornerRadius: 14))
    }

    private var stages: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("阶段").font(.system(size: 13, weight: .semibold)).foregroundStyle(ZJ.textPrimary)
            if let report {
                ForEach(report.stages) { stage in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: stage.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(stage.ok ? ZJ.celadon : Color(hex: 0xD65745))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(stage.name).font(.system(size: 13, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                                Spacer()
                                Text("\(stage.milliseconds)ms").font(.system(size: 10).monospacedDigit()).foregroundStyle(ZJ.textTertiary)
                            }
                            Text(stage.detail).font(.system(size: 11)).foregroundStyle(ZJ.textSecondary)
                        }
                    }
                    .padding(12)
                    .background(ZJ.bgElev1, in: RoundedRectangle(cornerRadius: 12))
                }
            } else {
                Text("运行体检查看搜索 / 详情 / 目录 / 正文四个阶段的耗时与错误。")
                    .font(.system(size: 12)).foregroundStyle(ZJ.textSecondary)
            }
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("诊断日志").font(.system(size: 13, weight: .semibold)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                if let report, !report.diagnostics.isEmpty {
                    Button(copied ? "已复制" : "复制") {
                        UIPasteboard.general.string = report.diagnostics.joined(separator: "\n")
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(ZJ.accent)
                }
            }
            if let report, !report.diagnostics.isEmpty {
                Button { withAnimation { showDiagnostics.toggle() } } label: {
                    HStack {
                        Text(showDiagnostics ? "收起完整诊断（HTTP 流水 / JS console）" : "展开完整诊断（HTTP 流水 / JS console）")
                            .font(.system(size: 11)).foregroundStyle(ZJ.textSecondary)
                        Spacer()
                        Image(systemName: showDiagnostics ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10)).foregroundStyle(ZJ.textTertiary)
                    }
                }
                if showDiagnostics {
                    ScrollView(.horizontal) {
                        Text(report.diagnostics.joined(separator: "\n"))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ZJ.textSecondary)
                            .padding(10)
                    }
                    .frame(maxHeight: 260)
                    .background(ZJ.bgElev1, in: RoundedRectangle(cornerRadius: 12))
                }
            } else {
                Text("暂无日志").font(.system(size: 11)).foregroundStyle(ZJ.textTertiary)
            }
        }
    }
}
