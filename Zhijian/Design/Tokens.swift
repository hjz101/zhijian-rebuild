// 设计令牌：颜色 / 间距 / 圆角 / 字体（栖阅式浅色玻璃 + 可切换配色）
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

// MARK: - 可切换配色

struct ZJPalette: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let isDark: Bool
    let accent: Color
    let accentPressed: Color
    let celadon: Color
    let gold: Color
    let bgBase: Color
    let bgElev1: Color
    let bgElev2: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let separator: Color
    let error: Color
    let gradient: [Color]
    let cardBorder: Color
}

enum ZJPaletteStore {
    static let key = "zhijian.app.palette"

    static var currentID: String {
        UserDefaults.standard.string(forKey: key) ?? "qingbai"
    }

    static var current: ZJPalette {
        all.first { $0.id == currentID } ?? all[0]
    }

    static func apply(_ id: String) {
        guard all.contains(where: { $0.id == id }) else { return }
        UserDefaults.standard.set(id, forKey: key)
        NotificationCenter.default.post(name: .zjPaletteChanged, object: nil)
    }

    static let all: [ZJPalette] = [
        ZJPalette(
            id: "qingbai", name: "青白玻璃", subtitle: "清透青白 · 墨色强调（默认）", isDark: false,
            accent: Color(hex: 0x15181D), accentPressed: Color(hex: 0x000000),
            celadon: Color(hex: 0x5C8D86), gold: Color(hex: 0xC79A4A),
            bgBase: Color(hex: 0xF3FAFE), bgElev1: Color.white.opacity(0.72),
            bgElev2: Color(hex: 0xE7F1F8), textPrimary: Color(hex: 0x11151A),
            textSecondary: Color.rgba(17, 21, 26, 0.58), textTertiary: Color.rgba(17, 21, 26, 0.38),
            separator: Color.rgba(17, 21, 26, 0.08), error: Color(hex: 0xC94A3D),
            gradient: [Color(hex: 0xF8FDFF), Color(hex: 0xEAF4FB), Color(hex: 0xF2FAFE)],
            cardBorder: Color.white.opacity(0.65)
        ),
        ZJPalette(
            id: "yuebai", name: "月白宣纸", subtitle: "暖白纸感 · 朱砂点睛", isDark: false,
            accent: Color(hex: 0x2B2620), accentPressed: Color(hex: 0x17130F),
            celadon: Color(hex: 0x6E7F63), gold: Color(hex: 0xB8893F),
            bgBase: Color(hex: 0xF7F4EC), bgElev1: Color(hex: 0xFFFDF8).opacity(0.78),
            bgElev2: Color(hex: 0xEDE6D7), textPrimary: Color(hex: 0x1E1A14),
            textSecondary: Color.rgba(30, 26, 20, 0.60), textTertiary: Color.rgba(30, 26, 20, 0.40),
            separator: Color.rgba(30, 26, 20, 0.09), error: Color(hex: 0xB4552F),
            gradient: [Color(hex: 0xFBF8F1), Color(hex: 0xF1EBDD), Color(hex: 0xF7F3EA)],
            cardBorder: Color.white.opacity(0.72)
        ),
        ZJPalette(
            id: "wulan", name: "雾蓝灰", subtitle: "冷静雾蓝 · 低饱和", isDark: false,
            accent: Color(hex: 0x1E2A38), accentPressed: Color(hex: 0x0E1720),
            celadon: Color(hex: 0x4C7A8C), gold: Color(hex: 0xA98B52),
            bgBase: Color(hex: 0xEEF3F7), bgElev1: Color.white.opacity(0.70),
            bgElev2: Color(hex: 0xDEE8EF), textPrimary: Color(hex: 0x16202A),
            textSecondary: Color.rgba(22, 32, 42, 0.58), textTertiary: Color.rgba(22, 32, 42, 0.38),
            separator: Color.rgba(22, 32, 42, 0.08), error: Color(hex: 0xBF4B45),
            gradient: [Color(hex: 0xF4F8FB), Color(hex: 0xE6EEF4), Color(hex: 0xEDF3F8)],
            cardBorder: Color.white.opacity(0.66)
        ),
        ZJPalette(
            id: "nuansha", name: "暖沙可可", subtitle: "暖沙可可 · 柔和护眼", isDark: false,
            accent: Color(hex: 0x3A2C24), accentPressed: Color(hex: 0x241A14),
            celadon: Color(hex: 0x8A7A5E), gold: Color(hex: 0xB98A4E),
            bgBase: Color(hex: 0xF6EFE7), bgElev1: Color(hex: 0xFFFCF7).opacity(0.76),
            bgElev2: Color(hex: 0xEADDD0), textPrimary: Color(hex: 0x241C16),
            textSecondary: Color.rgba(36, 28, 22, 0.58), textTertiary: Color.rgba(36, 28, 22, 0.38),
            separator: Color.rgba(36, 28, 22, 0.09), error: Color(hex: 0xA9714B),
            gradient: [Color(hex: 0xFBF5EE), Color(hex: 0xF0E4D6), Color(hex: 0xF6EEE5)],
            cardBorder: Color.white.opacity(0.70)
        ),
        ZJPalette(
            id: "anmo", name: "暗墨玻璃", subtitle: "深色 OLED · 夜间", isDark: true,
            accent: Color(hex: 0x4F7385), accentPressed: Color(hex: 0x3F5D6D),
            celadon: Color(hex: 0x7FA6A0), gold: Color(hex: 0xC9A25C),
            bgBase: Color(hex: 0x0E1116), bgElev1: Color(hex: 0x1A2029).opacity(0.86),
            bgElev2: Color(hex: 0x232B36), textPrimary: Color(hex: 0xE8EDF3),
            textSecondary: Color.rgba(232, 237, 243, 0.64), textTertiary: Color.rgba(232, 237, 243, 0.42),
            separator: Color.rgba(255, 255, 255, 0.10), error: Color(hex: 0xE06B5A),
            gradient: [Color(hex: 0x12161D), Color(hex: 0x0B0E13), Color(hex: 0x10151B)],
            cardBorder: Color.white.opacity(0.12)
        )
    ]
}

extension Notification.Name {
    static let zjPaletteChanged = Notification.Name("zhijian.palette.changed")
}

enum ZJ {
    static var accent: Color { ZJPaletteStore.current.accent }
    static var accentPressed: Color { ZJPaletteStore.current.accentPressed }
    static var celadon: Color { ZJPaletteStore.current.celadon }
    static var gold: Color { ZJPaletteStore.current.gold }
    static var bgBase: Color { ZJPaletteStore.current.bgBase }
    static var bgElev1: Color { ZJPaletteStore.current.bgElev1 }
    static var bgElev2: Color { ZJPaletteStore.current.bgElev2 }
    static var textPrimary: Color { ZJPaletteStore.current.textPrimary }
    static var textSecondary: Color { ZJPaletteStore.current.textSecondary }
    static var textTertiary: Color { ZJPaletteStore.current.textTertiary }
    static var separator: Color { ZJPaletteStore.current.separator }
    static var error: Color { ZJPaletteStore.current.error }

    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s12: CGFloat = 48
    static let rSm: CGFloat = 12
    static let rMd: CGFloat = 16
    static let rLg: CGFloat = 20
    static let rXl: CGFloat = 24
    static let rFull: CGFloat = 999
    static let pageMargin: CGFloat = 20
}

/// 栖阅式玻璃背景：随配色切换。
struct QiBackground: View {
    var body: some View {
        LinearGradient(colors: ZJPaletteStore.current.gradient,
                       startPoint: .topLeading, endPoint: .bottomTrailing)
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
                    .strokeBorder(ZJPaletteStore.current.cardBorder, lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(ZJPaletteStore.current.isDark ? 0.25 : 0.05), radius: 18, y: 6)
    }
}

/// 卡片/按钮按压反馈
struct QiPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

enum ZJFont {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func reader(_ family: ReaderFontFamily, size: CGFloat, customName: String = "") -> UIFont {
        if !customName.isEmpty, let font = UIFont(name: customName, size: size) {
            return font
        }
        switch family {
        case .songti:
            return UIFont(name: "Songti SC", size: size) ?? UIFont.systemFont(ofSize: size)
        case .pingfang:
            return UIFont.systemFont(ofSize: size, weight: .regular)
        }
    }
}
