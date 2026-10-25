// 设计令牌：颜色 / 间距 / 圆角 / 字体
// 外观重构（借鉴 origo-x）：App 主题 = 中性基底（亮/暗）+ 单一强调色 seed 动态生成整套色板。
// 用户可任意选择强调色（色盘/hex/18 色快捷/5 套预设），亮暗可跟随系统。
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
    init?(hexString: String) {
        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }
        self.init(hex: UInt32(number), alpha: 1)
    }
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - App 外观模型（seed + 亮暗）

enum AppAppearanceMode: String, CaseIterable, Sendable {
    case system, light, dark
    var name: String {
        switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" }
    }
}

struct ZJPalettePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let seedHex: String
    let isDark: Bool
}

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
    static let seedKey = "zhijian.app.accentSeed"
    static let modeKey = "zhijian.app.appearanceMode"
    static let legacyKey = "zhijian.app.palette" // v2.1 之前整组配色

    // MARK: - 预设（5 套场景，作为强调色快捷入口）

    static let presets: [ZJPalettePreset] = [
        ZJPalettePreset(id: "qingbai", name: "青白玻璃", subtitle: "墨黑强调 · 浅色", seedHex: "#15181D", isDark: false),
        ZJPalettePreset(id: "yuebai", name: "月白宣纸", subtitle: "朱砂点睛 · 浅色", seedHex: "#B4552F", isDark: false),
        ZJPalettePreset(id: "wulan", name: "雾蓝灰", subtitle: "深蓝灰 · 浅色", seedHex: "#1E2A38", isDark: false),
        ZJPalettePreset(id: "nuansha", name: "暖沙可可", subtitle: "可可 · 浅色", seedHex: "#8A6A4F", isDark: false),
        ZJPalettePreset(id: "anmo", name: "暗墨玻璃", subtitle: "灰蓝 · 深色", seedHex: "#4F7385", isDark: true)
    ]

    static var appearanceMode: AppAppearanceMode {
        get {
            let raw = UserDefaults.standard.string(forKey: modeKey) ?? ""
            return AppAppearanceMode(rawValue: raw) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
            NotificationCenter.default.post(name: .zjPaletteChanged, object: nil)
        }
    }

    static var seedHex: String {
        get {
            // 迁移旧整组配色 key → 对应预设 seed
            if let legacy = UserDefaults.standard.string(forKey: legacyKey),
               let preset = presets.first(where: { $0.id == legacy }) {
                UserDefaults.standard.set(preset.seedHex, forKey: seedKey)
                UserDefaults.standard.removeObject(forKey: legacyKey)
                return preset.seedHex
            }
            return UserDefaults.standard.string(forKey: seedKey) ?? "15181D"
        }
        set { UserDefaults.standard.set(newValue, forKey: seedKey) }
    }

    static var isDarkEffective: Bool {
        switch appearanceMode {
        case .dark: return true
        case .light: return false
        case .system: return UITraitCollection.current.userInterfaceStyle == .dark
        }
    }

    static var currentID: String {
        let hex = seedHex.uppercased()
        return presets.first(where: { $0.seedHex.uppercased() == hex })?.id ?? "custom"
    }

    static func apply(seedHex: String, mode: AppAppearanceMode? = nil) {
        self.seedHex = seedHex
        if let mode { self.appearanceMode = mode }
        NotificationCenter.default.post(name: .zjPaletteChanged, object: nil)
    }

    static func applyPreset(_ id: String) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        apply(seedHex: preset.seedHex, mode: preset.isDark ? .dark : .light)
    }

    // MARK: - 动态生成色板

    static var current: ZJPalette {
        let dark = isDarkEffective
        return palette(seedHex: seedHex, dark: dark)
    }

    static func palette(seedHex: String, dark: Bool) -> ZJPalette {
        let seed = Color(hexString: seedHex) ?? Color(hex: 0x15181D)
        let ui = UIColor(seed)
        var hue: CGFloat = 0, sat: CGFloat = 0, bright: CGFloat = 0, alpha: CGFloat = 0
        ui.getHue(&hue, saturation: &sat, brightness: &bright, alpha: &alpha)

        // 强调色：深色模式用更亮的 seed，浅色模式用更深的 seed 保证对比（origo seed→scheme 思路）
        let accentBright: CGFloat = dark ? min(bright + 0.18, 0.95) : max(bright - 0.10, 0.18)
        let accent = Color(hue: hue, saturation: dark ? max(sat - 0.10, 0.15) : sat, brightness: accentBright)
        let accentPressed = Color(hue: hue, saturation: sat, brightness: max(accentBright - 0.14, 0.12))
        let celadon = Color(hue: fmod(hue + 0.10, 1.0), saturation: min(sat + 0.05, 0.5), brightness: dark ? 0.62 : 0.42)
        let gold = Color(hue: fmod(hue + 0.16, 1.0), saturation: min(sat + 0.05, 0.55), brightness: dark ? 0.72 : 0.55)

        if dark {
            return ZJPalette(
                id: currentID, name: "自定义", subtitle: "深色 · \(seedHex)", isDark: true,
                accent: accent, accentPressed: accentPressed, celadon: celadon, gold: gold,
                bgBase: Color(hex: 0x0E1116), bgElev1: Color(hex: 0x1A2029).opacity(0.86),
                bgElev2: Color(hex: 0x232B36), textPrimary: Color(hex: 0xE8EDF3),
                textSecondary: Color.rgba(232, 237, 243, 0.64), textTertiary: Color.rgba(232, 237, 243, 0.42),
                separator: Color.rgba(255, 255, 255, 0.10), error: Color(hex: 0xE06B5A),
                gradient: [Color(hex: 0x12161D), Color(hex: 0x0B0E13), Color(hex: 0x10151B)],
                cardBorder: Color.white.opacity(0.12)
            )
        } else {
            return ZJPalette(
                id: currentID, name: "自定义", subtitle: "浅色 · \(seedHex)", isDark: false,
                accent: accent, accentPressed: accentPressed, celadon: celadon, gold: gold,
                bgBase: Color(hex: 0xF3FAFE), bgElev1: Color.white.opacity(0.72),
                bgElev2: Color(hex: 0xE7F1F8), textPrimary: Color(hex: 0x11151A),
                textSecondary: Color.rgba(17, 21, 26, 0.58), textTertiary: Color.rgba(17, 21, 26, 0.38),
                separator: Color.rgba(17, 21, 26, 0.08), error: Color(hex: 0xC94A3D),
                gradient: [Color(hex: 0xF8FDFF), Color(hex: 0xEAF4FB), Color(hex: 0xF2FAFE)],
                cardBorder: Color.white.opacity(0.65)
            )
        }
    }
}

extension Color {
    init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, opacity: CGFloat = 1) {
        self.init(UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: opacity))
    }
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

/// 玻璃背景：随外观（亮暗 + 强调色）切换。
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
