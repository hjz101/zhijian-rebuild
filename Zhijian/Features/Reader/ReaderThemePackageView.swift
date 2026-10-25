// ReaderThemePackageView.swift — 阅读主题包（导入/导出/应用）
import SwiftUI
import UniformTypeIdentifiers

struct ReaderThemePackageView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var store = ReaderThemePackageStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var exportURL: URL?
    @State private var showExport = false
    @State private var newName = ""
    @State private var showSave = false
    @State private var alert: String?

    private var types: [UTType] {
        var result: [UTType] = [.json, .zip, .data]
        if let zj = UTType(filenameExtension: "zjtheme") { result.append(zj) }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    QiSettingsSection(title: "主题包") {
                        if store.all.isEmpty {
                            Text("暂无主题包")
                                .font(.system(size: 12)).foregroundStyle(ZJ.textSecondary)
                                .padding(.horizontal, 14).padding(.vertical, 14)
                        }
                        ForEach(Array(store.all.enumerated()), id: \.element.id) { index, preset in
                            row(preset)
                            if index < store.all.count - 1 { QiDivider() }
                        }
                    }

                    QiSettingsSection(title: "操作") {
                        action("从当前设置创建主题包", icon: "plus.circle") { showSave = true }
                        QiDivider()
                        action("导入 .zjtheme / JSON", icon: "doc.badge.plus") { showImporter = true }
                        QiDivider()
                        action("导出当前主题包", icon: "square.and.arrow.up") { exportCurrent() }
                    }

                    Text("主题包包含主题名、背景/文字/强调色与字号/行距/段距/页边距；导入后可一键应用到阅读设置。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ZJ.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(QiBackground())
            .navigationTitle("阅读主题包")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: types,
                          allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let preset = try store.importPackage(url: url)
                    store.apply(preset, to: env.settings)
                    present("已导入并应用：\(preset.name)")
                } catch {
                    present("导入失败：\(error.localizedDescription)")
                }
            }
            .sheet(isPresented: $showExport) {
                if let url = exportURL {
                    NavigationStack {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.badge.arrow.up").font(.system(size: 44)).foregroundStyle(ZJ.accent)
                            Text(url.lastPathComponent).font(.system(size: 12)).foregroundStyle(ZJ.textSecondary)
                            ShareLink(item: url) { Label("分享 / 存储主题包", systemImage: "square.and.arrow.up") }
                                .buttonStyle(.borderedProminent).tint(ZJ.accent)
                            Button("完成") { showExport = false }.foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .navigationTitle("导出主题包")
                    }
                }
            }
            .alert("新建主题包", isPresented: $showSave) {
                TextField("名称", text: $newName)
                Button("取消", role: .cancel) { newName = "" }
                Button("创建") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    let preset = store.makePreset(from: env.settings.settings, name: name)
                    store.upsert(preset)
                    store.select(preset)
                    newName = ""
                    present("已创建：\(name)")
                }
            }
            .alert(alert ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
                Button("好", role: .cancel) { alert = nil }
            }
        }
    }

    private func row(_ preset: ReaderThemePreset) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(preset.backgroundColor)
                .frame(width: 44, height: 44)
                .overlay(
                    Text("文").font(.system(size: 16, weight: .semibold)).foregroundStyle(preset.textColor)
                )
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(preset.accentColor.opacity(0.5), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name).font(.system(size: 14, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                Text("\(preset.themeName) · \(Int(preset.fontSize))pt · 行距 \(Int(preset.lineHeight))")
                    .font(.system(size: 10)).foregroundStyle(ZJ.textTertiary)
            }
            Spacer()
            Button {
                store.apply(preset, to: env.settings)
                present("已应用：\(preset.name)")
            } label: {
                Text("应用").font(.system(size: 12, weight: .medium)).foregroundStyle(ZJ.accent)
            }
            .buttonStyle(.plain)
            if !preset.isBuiltIn {
                Button {
                    store.remove(preset)
                } label: {
                    Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(ZJ.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

    private func exportCurrent() {
        let preset = store.selected ?? store.makePreset(from: env.settings.settings, name: "指尖阅读主题")
        do {
            exportURL = try store.exportPackage(preset)
            showExport = true
        } catch {
            present("导出失败：\(error.localizedDescription)")
        }
    }

    private func present(_ text: String) {
        alert = text
    }
}
