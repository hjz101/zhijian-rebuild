// ReaderCustomPalette.swift — 自定义阅读配色（THEME-V2 阶段一）
import SwiftUI

/// 自定义阅读画布配色：覆盖内置主题，含 chrome（surface）色。
struct ReaderCustomPalette: Codable, Hashable, Sendable {
    var backgroundHex: String = "#F4EFE4"
    var textHex: String = "#1F1C17"
    var secondaryHex: String = "#6B6459"
    var accentHex: String = "#C2552E"
    var surfaceHex: String = "#EDE5D6"
    var isDark: Bool = false

    var background: Color { Color(hexString: backgroundHex) ?? Color(hex: 0xF4EFE4) }
    var text: Color { Color(hexString: textHex) ?? Color(hex: 0x1F1C17) }
    var secondary: Color { Color(hexString: secondaryHex) ?? Color(hex: 0x6B6459) }
    var accent: Color { Color(hexString: accentHex) ?? Color(hex: 0xC2552E) }
    var surface: Color { Color(hexString: surfaceHex) ?? Color(hex: 0xEDE5D6) }
}

extension ReadingSettings {
    /// 解析实际使用的阅读配色：自定义优先，否则用内置主题。
    func resolvedPalette(_ theme: ReaderTheme) -> (background: Color, text: Color, secondary: Color, accent: Color, surface: Color, isDark: Bool) {
        if let p = customPalette {
            return (p.background, p.text, p.secondary, p.accent, p.surface, p.isDark)
        }
        return (theme.background, theme.text, theme.secondary, theme.accent, theme.surface, theme.isDark)
    }
}
