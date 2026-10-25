// SourceEditorView.swift — 书源编辑（单条 JSON + 分组 + 启停）
import SwiftUI

struct SourceEditorView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let source: BookSource
    @State private var json = ""
    @State private var group = ""
    @State private var enabled = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    QiSettingsSection(title: "基本信息") {
                        HStack(spacing: 12) {
                            Text("名称").font(.system(size: 13)).foregroundStyle(ZJ.textSecondary)
                                .frame(width: 48, alignment: .leading)
                            Text(source.bookSourceName).font(.system(size: 14, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        QiDivider()
                        HStack(spacing: 12) {
                            Text("地址").font(.system(size: 13)).foregroundStyle(ZJ.textSecondary)
                                .frame(width: 48, alignment: .leading)
                            Text(source.bookSourceUrl).font(.system(size: 11).monospaced()).foregroundStyle(ZJ.textSecondary).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        QiDivider()
                        HStack(spacing: 12) {
                            Text("分组").font(.system(size: 13)).foregroundStyle(ZJ.textSecondary)
                                .frame(width: 48, alignment: .leading)
                            TextField("未分组", text: $group)
                                .font(.system(size: 13))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        if !env.sources.groups.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(env.sources.groups, id: \.self) { item in
                                        Button(item) { group = item }
                                            .font(.system(size: 11))
                                            .foregroundStyle(ZJ.accent)
                                            .padding(.horizontal, 9).padding(.vertical, 4)
                                            .background(ZJ.accent.opacity(0.08), in: Capsule())
                                    }
                                }
                                .padding(.horizontal, 14)
                            }
                            .padding(.bottom, 10)
                        }
                        QiDivider()
                        QiToggleRow(icon: "power", title: "启用该书源", isOn: $enabled)
                    }

                    QiSettingsSection(title: "书源 JSON") {
                        TextEditor(text: $json)
                            .font(.system(size: 11, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 260)
                            .padding(10)
                            .background(ZJ.bgElev2.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    if let error {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(ZJ.error)
                            .padding(.horizontal, 4)
                    }

                    QiSettingsSection(title: "操作") {
                        actionRow("复制单条书源 JSON", icon: "doc.on.doc") {
                            UIPasteboard.general.string = json
                        }
                        QiDivider()
                        actionRow("校验并保存", icon: "checkmark.circle") { save() }
                        QiDivider()
                        actionRow("导出该书源", icon: "square.and.arrow.up") { export() }
                        QiDivider()
                        Button(role: .destructive) {
                            env.sources.remove(source)
                            dismiss()
                        } label: {
                            Text("删除书源")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(ZJ.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(QiBackground())
            .navigationTitle("编辑书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }.fontWeight(.semibold)
                }
            }
            .onAppear {
                group = source.bookSourceGroup ?? ""
                enabled = source.enabled ?? true
                json = Self.encode(source)
            }
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

    private func save() {
        do {
            guard let parsed = try BookSourceLoader.load(json).first else {
                error = "JSON 未解析出书源"
                return
            }
            var updated = parsed
            updated.bookSourceGroup = group.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.enabled = enabled
            env.sources.update(updated)
            error = nil
            dismiss()
        } catch {
            self.error = "JSON 无效：\(error.localizedDescription)"
        }
    }

    private func export() {
        do {
            let url = try env.sources.exportJSON(only: source)
            UIPasteboard.general.string = try String(contentsOf: url, encoding: .utf8)
        } catch {
            self.error = "导出失败：\(error.localizedDescription)"
        }
    }

    private static func encode(_ source: BookSource) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        guard let data = try? encoder.encode(source) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
