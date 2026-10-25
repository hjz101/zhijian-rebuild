// ChapterRulesView.swift — 目录规则（全局 + 按源覆盖）
import SwiftUI

struct ChapterRulesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var store = ChapterRuleStore.shared
    @State private var draft = ChapterRuleConfig()
    @State private var editing: BookSource?
    @State private var preview = ""

    var body: some View {
        Form {
            Section {
                Toggle("目录去重", isOn: $draft.deduplicate)
                Toggle("过滤空标题", isOn: $draft.dropEmpty)
                Toggle("识别卷名（第一卷/卷一）", isOn: $draft.detectVolumes)
                Toggle("自动纠正倒序目录", isOn: $draft.autoReverse)
                Toggle("强制倒序", isOn: $draft.reverseOrder)
                Toggle("按章节编号排序", isOn: $draft.sortNumbered)
            } header: {
                Text("全局目录规则")
            } footer: {
                Text("顺序：去空 → 标题清理 → 卷名识别 → 去重 → 倒序 → 编号排序。")
            }

            Section {
                TextField("标题清理正则（匹配部分删除）", text: $draft.titleCleanupRegex, axis: .vertical)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1...3)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("卷名正则", text: $draft.volumeRegex, axis: .vertical)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1...3)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("高级")
            } footer: {
                Text("标题清理示例：`^(正文|最新章节)\\s*`；卷名正则默认匹配「第X卷/部」。")
            }

            Section("预览") {
                Button("用示例目录预览") { runPreview() }
                Text(preview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(env.sources.sources) { source in
                    Button {
                        editing = source
                    } label: {
                        HStack {
                            Text(source.bookSourceName).foregroundStyle(ZJ.textPrimary)
                            Spacer()
                            Text(store.hasOverride(source.bookSourceUrl) ? "自定义" : "沿用全局")
                                .font(.caption)
                                .foregroundStyle(store.hasOverride(source.bookSourceUrl) ? ZJ.accent : .secondary)
                            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("按书源覆盖")
            } footer: {
                Text("为个别书源设置不同规则；未设置时使用全局。")
            }

            Section {
                Button("恢复默认值") {
                    draft = ChapterRuleConfig()
                    store.updateGlobal(draft)
                    runPreview()
                }
                .foregroundStyle(.red)
            }
        }
        .scrollContentBackground(.hidden)
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
