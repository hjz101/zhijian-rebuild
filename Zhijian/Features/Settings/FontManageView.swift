// FontManageView.swift — 自定义字体导入与管理
import SwiftUI
import UniformTypeIdentifiers

struct FontManageView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var store = CustomFontStore.shared
    @State private var showImporter = false
    @State private var alert: String?

    private var fontTypes: [UTType] {
        var types: [UTType] = [.data]
        for ext in ["ttf", "otf", "ttc"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                QiSettingsSection(title: "已导入字体") {
                    if store.fonts.isEmpty {
                        Text("尚未导入字体，可添加 TTF / OTF / TTC 文件")
                            .font(.system(size: 12))
                            .foregroundStyle(ZJ.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                    }
                    ForEach(Array(store.fonts.enumerated()), id: \.element.id) { index, font in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(font.displayName)
                                    .font(.custom(font.postScriptName, size: 15))
                                    .foregroundStyle(ZJ.textPrimary)
                                Text(font.postScriptName)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(ZJ.textTertiary)
                            }
                            Spacer()
                            if env.settings.settings.customFontName == font.postScriptName {
                                Text("使用中")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(ZJ.accent)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(ZJ.accent.opacity(0.10), in: Capsule())
                            }
                            Button {
                                env.settings.settings.customFontName = font.postScriptName
                            } label: {
                                Text("应用").font(.system(size: 12, weight: .medium)).foregroundStyle(ZJ.accent)
                            }
                            .buttonStyle(.plain)
                            Button {
                                store.remove(font)
                                if env.settings.settings.customFontName == font.postScriptName {
                                    env.settings.settings.customFontName = ""
                                }
                            } label: {
                                Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(ZJ.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        if index < store.fonts.count - 1 { QiDivider() }
                    }
                }

                QiSettingsSection(title: "系统字体") {
                    ForEach(ReaderFontFamily.allCases) { family in
                        Button {
                            env.settings.settings.fontFamily = family
                            env.settings.settings.customFontName = ""
                        } label: {
                            HStack {
                                Text(family.name).font(.system(size: 14, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                                Spacer()
                                if env.settings.settings.customFontName.isEmpty,
                                   env.settings.settings.fontFamily == family {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(ZJ.accent)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if family != ReaderFontFamily.allCases.last { QiDivider() }
                    }
                }

                QiSettingsSection(title: "导入") {
                    Button { showImporter = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "textformat")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(ZJ.accent)
                                .frame(width: 30, height: 30)
                                .background(ZJ.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text("导入字体文件").font(.system(size: 14, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(ZJ.textTertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Text("字体文件保存在 Application Support/Zhijian/Fonts，切换字体后会重新分页但保留阅读进度。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ZJ.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(QiBackground())
        .navigationTitle("字体管理")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: fontTypes,
                      allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                var imported = 0
                for url in urls {
                    do { _ = try store.importFont(url: url); imported += 1 }
                    catch { present("导入失败：\(error.localizedDescription)") }
                }
                if imported > 0 { present("已导入 \(imported) 个字体") }
            } catch {
                present("导入失败：\(error.localizedDescription)")
            }
        }
        .alert(alert ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button("好", role: .cancel) { alert = nil }
        }
    }

    private func present(_ text: String) {
        alert = text
    }
}
