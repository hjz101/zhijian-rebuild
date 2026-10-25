// ReaderBackgroundSettingsView.swift — 阅读背景图设置
import SwiftUI
import PhotosUI

struct ReaderBackgroundSettingsView: View {
    @ObservedObject private var store = ReaderBackgroundStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    preview
                    QiSettingsSection(title: "背景图") {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            row(icon: "photo.badge.plus", title: "从相册选择图片",
                                value: store.hasImage ? "已设置" : "未设置")
                        }
                        .buttonStyle(.plain)
                        .onChange(of: photoItem) { _, item in
                            guard let item else { return }
                            Task {
                                if let data = try? await item.loadTransferable(type: Data.self),
                                   let image = UIImage(data: data) {
                                    store.setImage(image)
                                }
                            }
                        }
                        if store.hasImage {
                            QiDivider()
                            Button {
                                store.clear()
                            } label: {
                                row(icon: "trash", title: "移除背景图", value: nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    QiSettingsSection(title: "效果") {
                        QiToggleRow(icon: "photo", title: "启用背景图", isOn: Binding(
                            get: { store.enabled }, set: { store.enabled = $0 }
                        ))
                        QiDivider()
                        QiSliderRow(title: "不透明度", value: Binding(
                            get: { store.opacity }, set: { store.opacity = $0 }
                        ), range: 0.05...0.85, step: 0.05) { String(format: "%.0f%%", $0 * 100) }
                        QiDivider()
                        QiSliderRow(title: "模糊", value: Binding(
                            get: { store.blur }, set: { store.blur = $0 }
                        ), range: 0...24, step: 1) { String(format: "%.0f px", $0) }
                    }

                    Text("背景图会叠加在阅读主题底色之上，并按不透明度压暗，避免影响正文对比度。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ZJ.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(QiBackground())
            .navigationTitle("阅读背景")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }

    private var preview: some View {
        ZStack {
            ReaderBackgroundView(theme: .paper)
            VStack(alignment: .leading, spacing: 8) {
                Text("第一章 入山")
                    .font(.system(size: 18, weight: .bold))
                Text("清晨的雾还没有散，山道两旁的松针上挂着水珠。我背着一只旧布包，沿着石阶往上走。")
                    .font(.system(size: 13))
            }
            .foregroundStyle(Color(hex: 0x1F1C17))
            .padding(18)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ZJPaletteStore.current.cardBorder, lineWidth: 0.8)
        )
    }

    private func row(icon: String, title: String, value: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ZJ.accent)
                .frame(width: 30, height: 30)
                .background(ZJ.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(ZJ.textPrimary)
            Spacer()
            if let value {
                Text(value).font(.system(size: 12)).foregroundStyle(ZJ.textSecondary)
            }
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(ZJ.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}
