// GlassTheme.swift — iOS 27 Liquid Glass 材质（拾页设计稿）
// 五层玻璃：漫射 / 色调 / 暗边 / 高光 / 折射；三档通透度。
import SwiftUI

/// 通透度档位（对应 iOS 27 滑块：超透明 ↔ 完全着色，模糊量不变只调颜色权重）
enum GlassTransparency: Int, CaseIterable, Codable, Sendable {
    case ultraClear = 0, standard = 1, colored = 2

    var name: String {
        switch self {
        case .ultraClear: return "超透明"
        case .standard: return "标准"
        case .colored: return "完全着色"
        }
    }

    /// 色调权重（白/黑叠加比例）
    var tintOpacity: Double {
        switch self {
        case .ultraClear: return 0.05
        case .standard: return 0.12
        case .colored: return 0.30
        }
    }

    /// 暗边强度（27 新增，底部内阴影）
    var edgeDarken: Double {
        switch self {
        case .ultraClear: return 0.12
        case .standard: return 0.22
        case .colored: return 0.34
        }
    }

    /// 镜面高光强度（顶部 1.2px）
    var highlightOpacity: Double {
        switch self {
        case .ultraClear: return 0.28
        case .standard: return 0.45
        case .colored: return 0.60
        }
    }
}

/// 全局玻璃配置（三档通透度 + 夜间自动右移一档）
@MainActor
final class GlassSettings: ObservableObject {
    static let shared = GlassSettings()

    @Published var transparency: GlassTransparency {
        didSet { persist() }
    }
    @Published var autoDarkShift: Bool {
        didSet { persist() }
    }
    @Published var showBorder: Bool {
        didSet { persist() }
    }
    @Published var reduceTransparency: Bool {
        didSet { persist() }
    }

    private let file = "glass_settings.json"
    private struct Snapshot: Codable {
        var transparency: GlassTransparency = .standard
        var autoDarkShift = true
        var showBorder = true
        var reduceTransparency = false
    }

    /// 实际生效的通透度（深色模式自动右移一档）
    var effectiveTransparency: GlassTransparency {
        if reduceTransparency { return .standard }
        if autoDarkShift, isDarkMode {
            let shifted = GlassTransparency(rawValue: transparency.rawValue + 1) ?? .colored
            return shifted
        }
        return transparency
    }

    private var isDarkMode: Bool { ZJPaletteStore.current.isDark }

    private init() {
        let snapshot = AppData.load(Snapshot.self, file) ?? Snapshot()
        transparency = snapshot.transparency
        autoDarkShift = snapshot.autoDarkShift
        showBorder = snapshot.showBorder
        reduceTransparency = snapshot.reduceTransparency
    }

    private func persist() {
        AppData.save(Snapshot(transparency: transparency, autoDarkShift: autoDarkShift,
                              showBorder: showBorder, reduceTransparency: reduceTransparency), file)
    }
}

/// Liquid Glass 背景修饰符：漫射（Material）+ 色调 + 暗边 + 高光 + 折射扫光
struct LiquidGlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 22
    var transparency: GlassTransparency = .standard
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // 1 漫射（blur 由系统 Material 提供）
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    // 2 色调（白 8%–30% 对角渐变 / 深色模式用黑）
                    LinearGradient(
                        colors: isDark
                            ? [Color.black.opacity(transparency.tintOpacity * 0.6),
                               Color.white.opacity(transparency.tintOpacity * 0.35)]
                            : [Color.white.opacity(transparency.tintOpacity * 1.2),
                               Color.white.opacity(transparency.tintOpacity * 0.6)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    // 3 暗边：底部内阴影（27 的灵魂）
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.clear,
                                         Color.black.opacity(transparency.edgeDarken)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: cornerRadius > 8 ? 1.2 : 0.8
                        )
                        .padding(-0.4)
                )
                .overlay(
                    // 4 高光：顶部 1.2px 镜面
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(transparency.highlightOpacity),
                                         Color.clear],
                                startPoint: .top, endPoint: .center
                            ),
                            lineWidth: 1.2
                        )
                )
                // 5 折射：118° 扫光
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.0),
                                 Color.white.opacity(0.10),
                                 Color.clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .blendMode(.overlay)
                )
            }
    }
}

extension View {
    /// 液态玻璃卡片（chrome 用）
    func liquidGlass(cornerRadius: CGFloat = 22, transparency: GlassTransparency? = nil) -> some View {
        modifier(LiquidGlassBackground(cornerRadius: cornerRadius,
                                       transparency: transparency ?? GlassSettings.shared.effectiveTransparency))
    }
}
