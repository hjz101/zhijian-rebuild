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
    // 品牌
    static let accent = Color(hex: 0xE8663D)
    static let accentPressed = Color(hex: 0xD4572F)
    static let celadon = Color(hex: 0x4E8F86)
    static let gold = Color(hex: 0xD9A441)
    // 深色底
    static let bgBase = Color(hex: 0x0B0E13)
    static let bgElev1 = Color(hex: 0x121722)
    static let bgElev2 = Color(hex: 0x1A2130)
    static let textPrimary = Color(hex: 0xF5F7FA)
    static let textSecondary = Color.rgba(245, 247, 250, 0.64)
    static let textTertiary = Color.rgba(245, 247, 250, 0.40)
    static let separator = Color.rgba(255, 255, 255, 0.10)
    static let error = Color(hex: 0xD65745)

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
