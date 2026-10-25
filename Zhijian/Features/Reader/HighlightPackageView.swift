// HighlightPackageView.swift — 高亮规则包导入导出
import SwiftUI
import UniformTypeIdentifiers

struct HighlightPackageView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var exportURL: URL?
    @State private var showExport = false
    @State private var alert: String?

    private var types: [UTType] {
        var result: [UTType] = [.json, .data]
        if let custom = UTType(filenameExtension: "qihighlight") { result.append(custom) }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    QiSettingsSection(title: "当前规则") {
                        if env.settings.settings.highlightRules.isEmpty {
                            Text("暂无高亮规则")
                                .font(.system(size: 12)).foregroundStyle(ZJ.textSecondary)
                                .padding(.horizontal, 14).padding(.vertical, 14)
                        }
                        ForEach(Array(env.settings.settings.highlightRules.enumerated()), id: \.element.id) { index, rule in
                            HStack(spacing: 10) {
                                Circle().fill(Color(hexString: rule.colorHex) ?? ZJ.gold)
                                    .frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.name.isEmpty ? rule.pattern : rule.name)
                                        .font(.system(size: 13, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                                        .lineLimit(1)
                                    Text("\(rule.isRegex ? "正则" : "字面量") · \(rule.enabled ? "启用" : "停用")")
                                        .font(.system(size: 10)).foregroundStyle(ZJ.textTertiary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            if index < env.settings.settings.highlightRules.count - 1 { QiDivider() }
                        }
                    }

                    QiSettingsSection(title: "导入 / 导出") {
                        action("导出高亮规则", icon: "square.and.arrow.up") { exportRules() }
                        QiDivider()
                        action("导入高亮规则", icon: "doc.badge.plus") { showImporter = true }
                    }

                    Text("格式：`[{name, pattern, colorHex, enabled, isRegex}]`，也可直接导入栖阅 `.qihighlight` 的 JSON。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ZJ.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(QiBackground())
            .navigationTitle("高亮规则包")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: types,
                          allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    let rules = try JSONDecoder().decode([HighlightRule].self, from: data)
                    var settings = env.settings.settings
                    settings.highlightRules = rules
                    env.settings.settings = settings
                    present("已导入 \(rules.count) 条规则")
                } catch {
                    present("导入失败：\(error.localizedDescription)")
                }
            }
            .sheet(isPresented: $showExport) {
                if let url = exportURL {
                    NavigationStack {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.badge.arrow.up").font(.system(size: 44)).foregroundStyle(ZJ.accent)
                            ShareLink(item: url) { Label("分享 / 存储", systemImage: "square.and.arrow.up") }
                                .buttonStyle(.borderedProminent).tint(ZJ.accent)
                            Button("完成") { showExport = false }.foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .navigationTitle("导出高亮规则")
                    }
                }
            }
            .alert(alert ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
                Button("好", role: .cancel) { alert = nil }
            }
        }
    }

    private func action(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
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

    private func exportRules() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
            let data = try encoder.encode(env.settings.settings.highlightRules)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("zhijian-highlights.json")
            try data.write(to: url, options: .atomic)
            exportURL = url
            showExport = true
        } catch {
            present("导出失败：\(error.localizedDescription)")
        }
    }

    private func present(_ text: String) {
        alert = text
    }
}
