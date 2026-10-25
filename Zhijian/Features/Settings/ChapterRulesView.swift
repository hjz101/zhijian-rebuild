// ChapterRulesView.swift — 目录规则（全局 + 按源覆盖）
import SwiftUI

struct ChapterRulesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var store = ChapterRuleStore.shared
    @State private var draft = ChapterRuleConfig()
    @State private var editing: BookSource?
    @State private var preview = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                QiSettingsSection(title: "全局目录规则") {
                    QiToggleRow(icon: "square.stack.3d.down.right", title: "目录去重", isOn: $draft.deduplicate)
                    QiDivider()
                    QiToggleRow(icon: "text.badge.xmark", title: "过滤空标题", isOn: $draft.dropEmpty)
                    QiDivider()
                    QiToggleRow(icon: "book.closed", title: "识别卷名（第一卷/卷一）", isOn: $draft.detectVolumes)
                    QiDivider()
                    QiToggleRow(icon: "arrow.up.arrow.down", title: "自动纠正倒序目录", isOn: $draft.autoReverse)
                    QiDivider()
                    QiToggleRow(icon: "arrow.uturn.backward", title: "强制倒序", isOn: $draft.reverseOrder)
                    QiDivider()
                    QiToggleRow(icon: "number", title: "按章节编号排序", isOn: $draft.sortNumbered)
                    footer("顺序：去空 → 标题清理 → 卷名识别 → 去重 → 倒序 → 编号排序。")
                }

                QiSettingsSection(title: "高级") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("标题清理正则（匹配部分删除）")
                            .font(.system(size: 11))
                            .foregroundStyle(ZJ.textSecondary)
                        TextField("^(正文|最新章节)\\s*", text: $draft.titleCleanupRegex, axis: .vertical)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1...3)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(10)
                            .background(ZJ.bgElev2.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    QiDivider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("卷名正则")
                            .font(.system(size: 11))
                            .foregroundStyle(ZJ.textSecondary)
                        TextField("卷名正则", text: $draft.volumeRegex, axis: .vertical)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1...3)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(10)
                            .background(ZJ.bgElev2.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    footer("标题清理示例：`^(正文|最新章节)\\s*`；卷名正则默认匹配「第X卷/部」。")
                }

                QiSettingsSection(title: "预览") {
                    Button { runPreview() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "eye").font(.system(size: 13, weight: .semibold))
                            Text("用示例目录预览").font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(ZJ.accent, in: Capsule())
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                    }
                    .buttonStyle(.plain)
                    Text(preview)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(ZJ.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                QiSettingsSection(title: "按书源覆盖") {
                    if env.sources.sources.isEmpty {
                        Text("尚未导入书源")
                            .font(.system(size: 12))
                            .foregroundStyle(ZJ.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                    }
                    ForEach(Array(env.sources.sources.enumerated()), id: \.element.bookSourceUrl) { index, source in
                        Button {
                            editing = source
                        } label: {
                            HStack(spacing: 12) {
                                Text(source.bookSourceName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(ZJ.textPrimary)
                                Spacer()
                                Text(store.hasOverride(source.bookSourceUrl) ? "自定义" : "沿用全局")
                                    .font(.system(size: 11))
                                    .foregroundStyle(store.hasOverride(source.bookSourceUrl) ? ZJ.accent : ZJ.textSecondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(ZJ.textTertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < env.sources.sources.count - 1 { QiDivider() }
                    }
                    footer("为个别书源设置不同规则；未设置时使用全局。")
                }

                QiSettingsSection(title: "重置") {
                    Button {
                        draft = ChapterRuleConfig()
                        store.updateGlobal(draft)
                        runPreview()
                    } label: {
                        Text("恢复默认值")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ZJ.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(QiBackground())
        .navigationTitle("目录规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    store.updateGlobal(draft)
                    runPreview()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            draft = store.global
            runPreview()
        }
        .sheet(item: $editing) { source in
            ChapterRuleSourceEditor(source: source)
                .environmentObject(env)
        }
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(ZJ.textTertiary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func runPreview() {
        let sample = [
            SourceChapter(index: 0, title: "第3章 风起", url: "3", updateTime: "", isVolume: false),
            SourceChapter(index: 1, title: "第1章 入山", url: "1", updateTime: "", isVolume: false),
            SourceChapter(index: 2, title: "第2章 书庐", url: "2", updateTime: "", isVolume: false),
            SourceChapter(index: 3, title: "第2章 书庐", url: "2", updateTime: "", isVolume: false),
            SourceChapter(index: 4, title: "", url: "empty", updateTime: "", isVolume: false),
            SourceChapter(index: 5, title: "第二卷 远行", url: "v2", updateTime: "", isVolume: false)
        ]
        let result = ChapterRuleEngine.apply(sample, config: draft)
        let titles = result.chapters.prefix(8).map { ($0.isVolume ? "【卷】" : "") + $0.title }
        preview = "去重 \(result.removedDuplicates) · 去空 \(result.removedEmpty) · 卷名 \(result.detectedVolumes) · 反序 \(result.reversed ? "是" : "否")\n" + titles.joined(separator: " / ")
    }
}

private struct ChapterRuleSourceEditor: View {
    let source: BookSource
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ChapterRuleStore.shared
    @State private var config = ChapterRuleConfig()
    @State private var useGlobal = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("单独配置该书源", isOn: $useGlobal.inverted)
                        .onChange(of: useGlobal) { _, isGlobal in
                            if isGlobal { store.setOverride(nil, for: source.bookSourceUrl) }
                        }
                } footer: {
                    Text(useGlobal ? "当前沿用全局规则。" : "保存后仅对该书源生效。")
                }

                if !useGlobal {
                    Section("规则") {
                        Toggle("目录去重", isOn: $config.deduplicate)
                        Toggle("过滤空标题", isOn: $config.dropEmpty)
                        Toggle("识别卷名", isOn: $config.detectVolumes)
                        Toggle("自动纠正倒序", isOn: $config.autoReverse)
                        Toggle("强制倒序", isOn: $config.reverseOrder)
                        Toggle("按编号排序", isOn: $config.sortNumbered)
                        TextField("标题清理正则", text: $config.titleCleanupRegex, axis: .vertical)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            }
            .navigationTitle(source.bookSourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        if useGlobal {
                            store.setOverride(nil, for: source.bookSourceUrl)
                        } else {
                            store.setOverride(config, for: source.bookSourceUrl)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                useGlobal = !store.hasOverride(source.bookSourceUrl)
                config = store.config(for: source.bookSourceUrl)
            }
        }
    }
}

private extension Binding where Value == Bool {
    var inverted: Binding<Bool> {
        Binding(get: { !wrappedValue }, set: { wrappedValue = !$0 })
    }
}
