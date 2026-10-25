// HighlightRulesSheet.swift — 自动高亮规则（关键词/正则）
import SwiftUI

struct HighlightRulesSheet: View {
    @ObservedObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: HighlightRule?
    @State private var showEditor = false
    @State private var showPackage = false

    private var theme: ReaderTheme { settingsStore.settings.theme }
    private var rules: [HighlightRule] { settingsStore.settings.highlightRules }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if rules.isEmpty {
                        Text("暂无规则。添加关键词或正则后，阅读器会自动高亮匹配文本。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rules) { rule in
                        Button {
                            editing = rule
                            showEditor = true
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(hexString: rule.colorHex) ?? theme.accent)
                                    .frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.name).foregroundStyle(theme.text)
                                    Text(rule.pattern + (rule.isRegex ? "  ·  正则" : ""))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { rule.enabled },
                                    set: { newValue in
                                        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
                                        settingsStore.settings.highlightRules[index].enabled = newValue
                                    }
                                ))
                                .labelsHidden()
                                .tint(theme.accent)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        settingsStore.settings.highlightRules.remove(atOffsets: offsets)
                    }
                } footer: {
                    Text("关键词按字面匹配；正则使用 NSRegularExpression。高亮只影响正文，不改变分页断点。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background.ignoresSafeArea())
            .sheet(isPresented: $showPackage) {
                HighlightPackageView()
                    .environmentObject(AppEnvironment.shared)
            }
            .navigationTitle("自动高亮规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPackage = true
                    } label: {
                        Image(systemName: "shippingbox")
                    }
                }
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = HighlightRule(name: "", pattern: "", colorHex: "#D9A441")
                        showEditor = true
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showEditor) {
                if let rule = editing {
                    HighlightRuleEditorView(rule: rule) { saved in
                        var current = settingsStore.settings.highlightRules
                        if let index = current.firstIndex(where: { $0.id == saved.id }) {
                            current[index] = saved
                        } else {
                            current.append(saved)
                        }
                        settingsStore.settings.highlightRules = current
                        showEditor = false
                    } onCancel: {
                        showEditor = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}

struct HighlightRuleEditorView: View {
    @State private var draft: HighlightRule
    private let onSave: (HighlightRule) -> Void
    private let onCancel: () -> Void
    private let palette = ["#D9A441", "#7FA88A", "#D65745", "#5C7FA3", "#B07CC6"]

    init(rule: HighlightRule, onSave: @escaping (HighlightRule) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: rule)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称（如：人名 / 地名）", text: $draft.name)
                    TextField("关键词或正则", text: $draft.pattern)
                    Toggle("作为正则表达式", isOn: $draft.isRegex)
                }
                Section("颜色") {
                    HStack(spacing: 14) {
                        ForEach(palette, id: \.self) { hex in
                            colorSwatch(hex)
                        }
                    }
                }
                Section {
                    Toggle("启用", isOn: $draft.enabled)
                }
            }
            .navigationTitle(draft.name.isEmpty ? "新高亮规则" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { onCancel() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        var value = draft
                        if value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            value.name = value.pattern
                        }
                        onSave(value)
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func colorSwatch(_ hex: String) -> some View {
        Button {
            draft.colorHex = hex
        } label: {
            Circle()
                .fill(Color(hexString: hex) ?? .orange)
                .frame(width: 30, height: 30)
                .overlay {
                    if draft.colorHex == hex {
                        Circle().strokeBorder(Color.primary, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

extension Color {
    init?(hexString: String) {
        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(hex: number)
    }
}
