// 设计令牌：颜色 / 间距 / 圆角 / 字体（对齐 DESIGN-SPEC v1.3）
import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
    static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }
}

enum ZJ {
    // 品牌（栖阅式墨色/玻璃浅色）
    static let accent = Color(hex: 0x15181D)
    static let accentPressed = Color(hex: 0x000000)
    static let celadon = Color(hex: 0x5C8D86)
    static let gold = Color(hex: 0xC79A4A)
    // 浅色玻璃底
    static let bgBase = Color(hex: 0xF3FAFE)
    static let bgElev1 = Color.white.opacity(0.72)
    static let bgElev2 = Color(hex: 0xE7F1F8)
    static let textPrimary = Color(hex: 0x11151A)
    static let textSecondary = Color.rgba(17, 21, 26, 0.58)
    static let textTertiary = Color.rgba(17, 21, 26, 0.38)
    static let separator = Color.rgba(17, 21, 26, 0.08)
    static let error = Color(hex: 0xC94A3D)

    // 间距（4pt 基准）
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s12: CGFloat = 48

    // 圆角
    static let rSm: CGFloat = 12
    static let rMd: CGFloat = 16
    static let rLg: CGFloat = 20
    static let rXl: CGFloat = 24
    static let rFull: CGFloat = 999

    // 页面边距
    static let pageMargin: CGFloat = 20
}

/// 栖阅式浅色玻璃背景：近白青渐变。
struct QiBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(hex: 0xF8FDFF), Color(hex: 0xEAF4FB), Color(hex: 0xF2FAFE)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

extension View {
    func qiCard(cornerRadius: CGFloat = 22, padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.65), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 18, y: 6)
    }
}

// 字体：中文标题用系统字重；阅读正文用宋体/苹方
enum ZJFont {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func reader(_ family: ReaderFontFamily, size: CGFloat) -> UIFont {
        switch family {
        case .songti:
            return UIFont(name: "Songti SC", size: size) ?? UIFont.systemFont(ofSize: size)
        case .pingfang:
            return UIFont.systemFont(ofSize: size, weight: .regular)
        }
    }
}
