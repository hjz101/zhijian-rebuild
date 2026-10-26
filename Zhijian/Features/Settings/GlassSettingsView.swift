// GlassSettingsView.swift — iOS 27 Liquid Glass 通透度设置（设计稿屏 04）
import SwiftUI

struct GlassSettingsView: View {
    @ObservedObject private var glass = GlassSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    previewCard

                    QiSettingsSection(title: "通透度") {
                        HStack(spacing: 8) {
                            ForEach(GlassTransparency.allCases, id: \.self) { level in
                                Button {
                                    glass.transparency = level
                                } label: {
                                    Text(level.name)
                                        .font(.system(size: 11, weight: glass.transparency == level ? .semibold : .regular))
                                        .foregroundStyle(glass.transparency == level ? .white : ZJ.textSecondary)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(glass.transparency == level ? ZJ.accent : ZJ.bgElev2.opacity(0.6), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        Text("超透明 ↔ 完全着色：模糊量不变，只调颜色权重（对齐 iOS 27）。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(ZJ.textTertiary)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }

                    QiSettingsSection(title: "选项") {
                        QiToggleRow(icon: "moon", title: "深色模式下自动降通透", isOn: $glass.autoDarkShift)
                        QiDivider()
                        QiToggleRow(icon: "rectangle.inset.filled", title: "显示边框", isOn: $glass.showBorder)
                        QiDivider()
                        QiToggleRow(icon: "circle.lefthalf.filled", title: "降低透明度", isOn: $glass.reduceTransparency)
                        Text("降低透明度或增强对比度开启时，滑块不可用——系统优先保证可读性。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(ZJ.textTertiary)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(QiBackground())
            .navigationTitle("液态玻璃")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("预览").font(.system(size: 12, weight: .semibold)).foregroundStyle(ZJ.textSecondary)
            HStack(spacing: 10) {
                ForEach(GlassTransparency.allCases, id: \.self) { level in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .liquidGlass(cornerRadius: 14, transparency: level)
                            .frame(width: 88, height: 64)
                            .overlay(
                                VStack {
                                    Text(level.name).font(.system(size: 9)).foregroundStyle(ZJ.textPrimary)
                                    Circle().fill(ZJ.accent).frame(width: 12, height: 12)
                                }
                            )
                        Text(glass.transparency == level ? "当前" : "").font(.system(size: 9)).foregroundStyle(ZJ.accent)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .qiCard()
    }
}
