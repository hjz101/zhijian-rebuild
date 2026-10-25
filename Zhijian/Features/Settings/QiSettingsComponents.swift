// QiSettingsComponents.swift — 栖阅式设置页通用组件（玻璃分组卡片 / 行 / 滑块）
import SwiftUI

struct QiSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ZJ.textSecondary)
                    .padding(.leading, 6)
            }
            VStack(spacing: 0) { content() }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(ZJPaletteStore.current.cardBorder, lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.04), radius: 16, y: 6)
        }
    }
}

struct QiRow<Accessory: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ZJ.accent)
                .frame(width: 30, height: 30)
                .background(ZJ.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                if let subtitle {
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(ZJ.textSecondary)
                }
            }
            Spacer()
            if let value {
                Text(value).font(.system(size: 12)).foregroundStyle(ZJ.textSecondary)
            }
            accessory()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

extension QiRow where Accessory == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil, value: String? = nil) {
        self.init(icon: icon, title: title, subtitle: subtitle, value: value) { EmptyView() }
    }
}

struct QiSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var display: (Double) -> String = { "\(Int($0))" }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                Text(display(value))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(ZJ.textSecondary)
            }
            Slider(value: $value, in: range, step: step)
                .tint(ZJ.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct QiToggleRow: View {
    let icon: String?
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ZJ.accent)
                    .frame(width: 30, height: 30)
                    .background(ZJ.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(ZJ.textPrimary)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(ZJ.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

struct QiDivider: View {
    var body: some View {
        Rectangle().fill(ZJ.separator).frame(height: 0.5).padding(.leading, 56)
    }
}
