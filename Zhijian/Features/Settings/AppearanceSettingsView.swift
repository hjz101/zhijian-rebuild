// AppearanceSettingsView.swift — 外观（origo-x 思路：强调色 seed 驱动整套色板）
import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var seedHex = ZJPaletteStore.seedHex
    @State private var mode = ZJPaletteStore.appearanceMode
    @State private var refresh = UUID()
    @AppStorage("appIcon.followPalette") private var iconFollowsPalette = true

    private var palette: ZJPalette {
        let dark = mode == .dark || (mode == .system && UITraitCollection.current.userInterfaceStyle == .dark)
        return ZJPaletteStore.palette(seedHex: seedHex, dark: dark)
    }

    /// origo-x 18 色快捷（近似）
    private let quickColors: [String] = [
        "#1976D2", "#3F51B5", "#6750A4", "#8E24AA", "#D81B60", "#E53935",
        "#F4511E", "#FB8C00", "#F9A825", "#7CB342", "#2E7D32", "#00897B",
        "#0097A7", "#0288D1", "#5E6C84", "#795548", "#B26A00", "#7D5260"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("外观")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.top, 4)
                    Text("选择一个强调色，整套界面色板由它生成（借鉴 origo-x 的 seed 方案）。阅读正文仍由阅读主题控制。")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)

                    modeSection
                    presetSection
                    customSection
                    iconSection
                    previewCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(LinearGradient(colors: palette.gradient, startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
            .navigationTitle("外观")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .onAppear {
                AppIconController.apply(paletteID: ZJPaletteStore.currentID, enabled: iconFollowsPalette)
            }
            .onChange(of: seedHex) { _, value in
                withAnimation(.easeInOut(duration: 0.28)) {
                    ZJPaletteStore.apply(seedHex: value, mode: mode)
                    refresh = UUID()
                }
                AppIconController.apply(paletteID: ZJPaletteStore.currentID, enabled: iconFollowsPalette)
            }
            .onChange(of: mode) { _, value in
                withAnimation(.easeInOut(duration: 0.28)) {
                    ZJPaletteStore.apply(seedHex: seedHex, mode: value)
                    refresh = UUID()
                }
                AppIconController.apply(paletteID: ZJPaletteStore.currentID, enabled: iconFollowsPalette)
            }
            .onChange(of: iconFollowsPalette) { _, enabled in
                AppIconController.apply(paletteID: ZJPaletteStore.currentID, enabled: enabled)
            }
        }
        .preferredColorScheme(mode == .dark ? .dark : (mode == .light ? .light : nil))
        .id(refresh)
    }

    private var modeSection: some View {
        QiSettingsSection(title: "外观模式") {
            HStack(spacing: 8) {
                ForEach(AppAppearanceMode.allCases, id: \.self) { m in
                    Button(m.name) { mode = m }
                        .font(.system(size: 12, weight: mode == m ? .semibold : .regular))
                        .foregroundStyle(mode == m ? .white : palette.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(mode == m ? palette.accent : palette.bgElev2.opacity(0.6), in: Capsule())
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    private var presetSection: some View {
        QiSettingsSection(title: "预设场景") {
            ForEach(ZJPaletteStore.presets) { item in
                Button {
                    ZJPaletteStore.applyPreset(item.id)
                    seedHex = ZJPaletteStore.seedHex
                    mode = ZJPaletteStore.appearanceMode
                    refresh = UUID()
                } label: {
                    HStack(spacing: 12) {
                        Circle().fill(Color(hexString: item.seedHex) ?? palette.accent).frame(width: 20, height: 20)
                        Text(item.name).font(.system(size: 14, weight: .medium)).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(item.subtitle).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                        if ZJPaletteStore.currentID == item.id && seedHex.uppercased() == item.seedHex.uppercased() {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.accent)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customSection: some View {
        QiSettingsSection(title: "强调色（自定义）") {
            HStack(spacing: 8) {
                ColorPicker("强调色", selection: Binding(
                    get: { Color(hexString: seedHex) ?? palette.accent },
                    set: { seedHex = $0.hexString }
                ))
                .labelsHidden()
                Text(seedHex).font(.system(size: 12, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(quickColors, id: \.self) { hex in
                    Button {
                        seedHex = hex
                    } label: {
                        Circle().fill(Color(hexString: hex) ?? palette.accent).frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(seedHex.uppercased() == hex.uppercased() ? palette.textPrimary : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 10)
        }
    }

    private var iconSection: some View {
        QiSettingsSection(title: "App 图标") {
            QiToggleRow(icon: "app.badge", title: "图标跟随配色", isOn: $iconFollowsPalette)
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("预览").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textSecondary)
            HStack(spacing: 10) {
                Circle().fill(palette.accent).frame(width: 34, height: 34)
                    .overlay(Image(systemName: "book.closed.fill").font(.system(size: 14)).foregroundStyle(palette.bgBase))
                VStack(alignment: .leading, spacing: 2) {
                    Text("山居书简").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    Text("第 12 章 · 已读 36%").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Text("继续").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.bgBase)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(palette.accent, in: Capsule())
            }
            ProgressView(value: 0.36).tint(palette.accent)
        }
        .qiCard()
    }
}
