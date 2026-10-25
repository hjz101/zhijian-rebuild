// AppearanceSettingsView.swift — 界面配色与外观
import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected = ZJPaletteStore.currentID
    @State private var refresh = UUID()

    private var palette: ZJPalette { ZJPaletteStore.all.first { $0.id == selected } ?? ZJPaletteStore.all[0] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("界面配色")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.top, 4)
                    Text("影响书架、统计、设置与卡片；阅读正文仍由阅读主题控制。")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)

                    ForEach(ZJPaletteStore.all) { item in
                        paletteRow(item)
                    }

                    previewCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(
                LinearGradient(colors: palette.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
            .navigationTitle("外观")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onChange(of: selected) { _, value in
                ZJPaletteStore.apply(value)
                refresh = UUID()
            }
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .id(refresh)
    }

    private func paletteRow(_ item: ZJPalette) -> some View {
        Button {
            selected = item.id
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: item.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 46, height: 46)
                    Circle()
                        .fill(item.accent)
                        .frame(width: 16, height: 16)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    Text(item.subtitle).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if selected == item.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(palette.accent)
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected == item.id ? palette.accent.opacity(0.45) : palette.cardBorder,
                                  lineWidth: selected == item.id ? 1.2 : 0.8)
            )
        }
        .buttonStyle(.plain)
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
            HStack(spacing: 8) {
                tag("书源", palette)
                tag("TTS", palette)
                tag("段评", palette)
            }
        }
        .qiCard()
    }

    private func tag(_ text: String, _ item: ZJPalette) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(item.accent)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(item.accent.opacity(0.10), in: Capsule())
    }
}
