// ReplaceRulesView.swift — 替换净化规则管理（导入/导出/排序/启停）
import SwiftUI
import UniformTypeIdentifiers

struct ReplaceRulesView: View {
    @ObservedObject private var store = ReplaceRuleStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var editing: ReplaceRule?
    @State private var showEditor = false
    @State private var showImporter = false
    @State private var showPaste = false
    @State private var pasteText = ""
    @State private var exportURL: URL?
    @State private var showExport = false
    @State private var alert: String?
    @State private var sampleText = "正文第一段。\n本站域名 www.example.com 请勿相信。\n【广告】点击下载 App。\n正文第二段。"
    @State private var preview = ""
    @State private var showPreview = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                QiSettingsSection(title: "概览") {
                    Button {
                        showPreview = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "eye")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(ZJ.accent)
                                .frame(width: 30, height: 30)
                                .background(ZJ.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text("清洗预览").font(.system(size: 14, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(ZJ.textTertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    QiDivider()
                    QiRow(icon: "list.bullet", title: "规则数",
                          value: "\(store.rules.count) 条 · \(store.rules.filter(\.enabled).count) 启用")
                }

                QiSettingsSection(title: "替换规则") {
                    if store.rules.isEmpty {
                        Text("暂无规则，点右上角 + 新建")
                            .font(.system(size: 12))
                            .foregroundStyle(ZJ.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                    }
                    ForEach(Array(store.rules.enumerated()), id: \.element.id) { index, rule in
                        HStack(spacing: 12) {
                            Button {
                                editing = rule
                                showEditor = true
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rule.name.isEmpty ? rule.pattern : rule.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(ZJ.textPrimary)
                                        .lineLimit(1)
                                    Text("\(rule.scope.name) · \(rule.isRegex ? "正则" : "字面量") · \(rule.replacement.isEmpty ? "删除" : "替换")")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(ZJ.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Toggle("", isOn: Binding(
                                get: { rule.enabled },
                                set: { _ in store.toggle(rule) }
                            ))
                            .labelsHidden()
                            .tint(ZJ.accent)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contextMenu {
                            Button { editing = rule; showEditor = true } label: { Label("编辑", systemImage: "pencil") }
                            Button(role: .destructive) { store.remove(rule) } label: { Label("删除", systemImage: "trash") }
                        }
                        if index < store.rules.count - 1 { QiDivider() }
                    }
                    footer("按顺序执行；支持 $1 捕获组、\\n 换行；单条规则超时自动跳过。")
                }

                QiSettingsSection(title: "导入 / 导出") {
                    actionRow("从文件导入 JSON", icon: "doc.badge.plus") { showImporter = true }
                    QiDivider()
                    actionRow("粘贴 JSON 导入", icon: "doc.on.clipboard") { showPaste = true }
                    QiDivider()
                    actionRow("导出规则 JSON", icon: "square.and.arrow.up") { export() }
                    footer("兼容 `[ReplaceRule]` 数组或 `{version, rules}` 包装；导入按 id 覆盖/追加。")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(QiBackground())
        .navigationTitle("替换净化")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = ReplaceRule(name: "", pattern: "", replacement: "", order: store.rules.count)
                    showEditor = true
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let rule = editing {
                ReplaceRuleEditorView(rule: rule) { saved in
                    store.update(saved)
                    showEditor = false
                } onCancel: { showEditor = false }
            }
        }
        .sheet(isPresented: $showPreview) {
            NavigationStack {
                ReplaceRulePreviewView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("完成") { showPreview = false } }
                    }
            }
            .environmentObject(ReplaceRuleStore.shared)
        }
        .sheet(isPresented: $showExport) {
            if let url = exportURL {
                NavigationStack {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.badge.arrow.up").font(.system(size: 44)).foregroundStyle(ZJ.accent)
                        ShareLink(item: url) { Label("分享 / 存储 JSON", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.borderedProminent).tint(ZJ.accent)
                        Button("完成") { showExport = false }.foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .navigationTitle("导出规则")
                }
            }
        }
        .sheet(isPresented: $showPaste) {
            NavigationStack {
                TextEditor(text: $pasteText)
                    .font(.system(size: 12, design: .monospaced))
                    .padding()
                    .navigationTitle("粘贴规则 JSON")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { showPaste = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("导入") {
                                do {
                                    let count = try store.importJSON(pasteText)
                                    showPaste = false
                                    present("导入 \(count) 条规则")
                                } catch { present("导入失败：\(error.localizedDescription)") }
                            }
                        }
                    }
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.json, .data],
                      allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let text = try String(contentsOf: url, encoding: .utf8)
                let count = try store.importJSON(text)
                present("导入 \(count) 条规则")
            } catch {
                present("导入失败：\(error.localizedDescription)")
            }
        }
        .alert(alert ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button("好", role: .cancel) { alert = nil }
        }
    }

    private func actionRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ZJ.accent)
                    .frame(width: 30, height: 30)
                    .background(ZJ.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(ZJ.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func export() {
        do {
            exportURL = try store.exportJSON()
            showExport = true
        } catch {
            present("导出失败：\(error.localizedDescription)")
        }
    }

    private func present(_ text: String) {
        alert = text
    }
}

struct ReplaceRuleEditorView: View {
    @State private var draft: ReplaceRule
    @State private var sample = "本站域名 www.example.com 请勿相信。\n【广告】点击下载 App。\n正文内容。"
    private let onSave: (ReplaceRule) -> Void
    private let onCancel: () -> Void

    init(rule: ReplaceRule, onSave: @escaping (ReplaceRule) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: rule)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var preview: String {
        guard !draft.pattern.isEmpty else { return sample }
        return ReplaceRuleEngine.apply([draft], to: sample, scope: draft.scope).text
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称（如：删除广告行）", text: $draft.name)
                    TextField("匹配内容 / 正则", text: $draft.pattern, axis: .vertical)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1...4)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("替换为（留空 = 删除）", text: $draft.replacement, axis: .vertical)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1...3)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("规则")
                } footer: {
                    Text("替换支持 $1…$9 捕获组与 \\n；正则会启用 1s 超时保护。")
                }

                Section("作用域") {
                    Picker("作用于", selection: $draft.scope) {
                        ForEach(ReplaceRule.Scope.allCases, id: \.self) { scope in
                            Text(scope.name).tag(scope)
                        }
                    }
                    Toggle("使用正则表达式", isOn: $draft.isRegex)
                    Toggle("启用", isOn: $draft.enabled)
                }

                Section("预览") {
                    Text(preview)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(draft.name.isEmpty ? "新建替换规则" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { onCancel() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { onSave(draft) }
                        .fontWeight(.semibold)
                        .disabled(draft.pattern.isEmpty)
                }
            }
        }
    }
}

struct ReplaceRulePreviewView: View {
    @ObservedObject private var store = ReplaceRuleStore.shared
    @State private var text = "正文第一段。\n本站域名 www.example.com 请勿相信。\n【广告】点击下载 App。\n正文第二段。\n第12章 标题（重复）"
    @State private var title = "第12章 标题（重复）"

    private var cleaned: ReplaceRuleEngine.Result {
        ReplaceRuleEngine.apply(store.rules, to: text, scope: .content)
    }

    var body: some View {
        List {
            Section("输入") {
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 110)
            }
            Section("清洗后（\(cleaned.applied) 条生效）") {
                Text(cleaned.text)
                    .font(.system(size: 13))
            }
            if !cleaned.failures.isEmpty {
                Section("失败") {
                    ForEach(cleaned.failures, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
                }
            }
            Section("标题清洗") {
                TextField("标题", text: $title)
                Text(store.cleanTitle(title)).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("清洗预览")
        .navigationBarTitleDisplayMode(.inline)
    }
}
