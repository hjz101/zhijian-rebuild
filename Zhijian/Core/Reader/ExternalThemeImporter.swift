// ExternalThemeImporter.swift — 栖阅生态格式导入（R2-05 / THEME-V2 阶段三）
// - `.red`（Red App 主题归档）：ZIP 含 theme.json（{name, light, dark, ...}）+ 背景图
// - `.qibubble`（段评气泡样式）：JSON {colorHex, cornerRadius, icon} 或 {light, dark}
// - `.qitheme`（栖阅 AppTheme 归档）：ZIP 含 AppTheme JSON（54 字段，映射阅读子集 + chrome）
import Foundation
import SwiftUI

/// 兼容栖阅 `.qitheme` 的 AppTheme JSON（54 字段，我们映射阅读相关子集）。
struct QIAppThemeJSON: Codable {
    var name: String?
    var primaryTextColorHex: String?
    var secondaryTextColorHex: String?
    var tertiaryTextColorHex: String?
    var darkPrimaryTextColorHex: String?
    var darkSecondaryTextColorHex: String?
    var accentColorHex: String?
    var darkAccentColorHex: String?
    var defaultBackground: String?
    var readerThemeLight: QIReaderThemeJSON?
    var readerThemeDark: QIReaderThemeJSON?

    struct QIReaderThemeJSON: Codable {
        var textColorHex: String?
        var backgroundColorHex: String?
        var backgroundImageName: String?
    }
}

/// 兼容栖阅报告中的 Red App 主题 JSON 结构。
struct RedThemeJSON: Codable {
    var name: String?
    var light: RedThemeSide?
    var dark: RedThemeSide?
    var backgroundColor: String?
    var textColor: String?
    var accentColor: String?

    struct RedThemeSide: Codable {
        var backgroundColor: String?
        var textColor: String?
        var secondaryTextColor: String?
        var accentColor: String?
        var backgroundImage: String?
    }
}

struct QIBubbleJSON: Codable {
    var colorHex: String?
    var color: String?
    var cornerRadius: Double?
    var icon: String?
    var skin: Int?
    var light: QIBubbleSide?
    var dark: QIBubbleSide?

    struct QIBubbleSide: Codable {
        var colorHex: String?
        var color: String?
        var cornerRadius: Double?
        var icon: String?
        var skin: Int?
    }
}

enum ExternalThemeImporter {
    /// 导入 `.qitheme`（ZIP，AppTheme JSON）→ ReaderThemePreset（含 chrome 色）。
    static func importQITheme(data: Data, fallbackName: String) throws -> ReaderThemePreset {
        let zip = try ZipReader(data: data)
        guard let name = zip.fileNames.first(where: { $0.hasSuffix(".json") && ($0.contains("theme") || $0.contains("Theme")) }),
              let json = try? zip.read(name) else {
            throw ThemeError.qiThemeInvalid
        }
        let decoder = JSONDecoder()
        let appTheme: QIAppThemeJSON
        if let parsed = try? decoder.decode(QIAppThemeJSON.self, from: json) {
            appTheme = parsed
        } else if let parsed = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                  let nested = try? JSONSerialization.data(withJSONObject: parsed["appTheme"] ?? parsed),
                  let decoded = try? decoder.decode(QIAppThemeJSON.self, from: nested) {
            appTheme = decoded
        } else {
            throw ThemeError.qiThemeInvalid
        }
        var preset = ReaderThemePreset()
        preset.name = appTheme.name ?? fallbackName
        preset.themeName = "paper"
        let light = appTheme.readerThemeLight
        preset.backgroundHex = normalizeHex(light?.backgroundColorHex ?? appTheme.defaultBackground ?? "#F4EFE4")
        preset.textHex = normalizeHex(light?.textColorHex ?? appTheme.primaryTextColorHex ?? "#1F1C17")
        preset.secondaryHex = normalizeHex(appTheme.secondaryTextColorHex ?? "#6B6459")
        preset.accentHex = normalizeHex(appTheme.accentColorHex ?? "#C2552E")
        // chrome（surface）：用 background 加深/变暗近似
        preset.surfaceHex = surfaceFrom(backgroundHex: preset.backgroundHex)
        return preset
    }

    private static func surfaceFrom(backgroundHex: String) -> String {
        guard let color = Color(hexString: backgroundHex) else { return backgroundHex }
        let ui = UIColor(color)
        var hue: CGFloat = 0, sat: CGFloat = 0, bright: CGFloat = 0, alpha: CGFloat = 0
        ui.getHue(&hue, saturation: &sat, brightness: &bright, alpha: &alpha)
        let darker = bright > 0.5 ? max(bright - 0.08, 0.2) : min(bright + 0.08, 0.9)
        return Color(hue: hue, saturation: sat, brightness: darker).hexString
    }

    /// 导入 `.red` 归档或裸 JSON → ReaderThemePreset（取 light 侧映射到米宣纸风格）。
    static func importRed(data: Data, fallbackName: String) throws -> ReaderThemePreset {
        let decoder = JSONDecoder()
        // 裸 JSON 直接解析
        if let red = try? decoder.decode(RedThemeJSON.self, from: data) {
            return makePreset(from: red, fallbackName: fallbackName)
        }
        // ZIP 归档：找 theme.json
        let zip = try ZipReader(data: data)
        guard let name = zip.fileNames.first(where: { $0.hasSuffix("theme.json") }),
              let json = try? zip.read(name) else {
            throw ThemeError.redInvalid
        }
        guard let red = try? decoder.decode(RedThemeJSON.self, from: json) else {
            throw ThemeError.redInvalid
        }
        return makePreset(from: red, fallbackName: fallbackName)
    }

    /// 导入 `.qibubble` JSON → 气泡样式参数（颜色/圆角/图标/皮肤）。
    static func importBubble(data: Data) throws -> (colorHex: String, corner: Double, icon: String, skin: Int) {
        let decoder = JSONDecoder()
        guard let bubble = try? decoder.decode(QIBubbleJSON.self, from: data) else {
            throw ThemeError.bubbleInvalid
        }
        let side = bubble.light ?? bubble.dark
        let color = bubble.colorHex ?? bubble.color ?? side?.colorHex ?? side?.color ?? "#E8663D"
        let corner = bubble.cornerRadius ?? side?.cornerRadius ?? 16
        let icon = bubble.icon ?? side?.icon ?? "💬"
        let skin = bubble.skin ?? side?.skin ?? 0
        return (color, corner, icon, skin)
    }

    private static func makePreset(from red: RedThemeJSON, fallbackName: String) -> ReaderThemePreset {
        var preset = ReaderThemePreset()
        preset.name = red.name ?? fallbackName
        preset.themeName = "paper"
        let side = red.light
        preset.backgroundHex = normalizeHex(side?.backgroundColor ?? red.backgroundColor ?? "#F4EFE4")
        preset.textHex = normalizeHex(side?.textColor ?? red.textColor ?? "#1F1C17")
        preset.secondaryHex = normalizeHex(side?.secondaryTextColor ?? "#6B6459")
        preset.accentHex = normalizeHex(side?.accentColor ?? red.accentColor ?? "#C2552E")
        return preset
    }

    /// 兼容 `#AARRGGBB` → `#RRGGBB`。
    static func normalizeHex(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#"), value.count == 9 { value = "#" + String(value.dropFirst(3)) }
        return value
    }

    enum ThemeError: LocalizedError {
        case redInvalid, bubbleInvalid, qiThemeInvalid
        var errorDescription: String? {
            switch self {
            case .redInvalid: return ".red 主题解析失败（缺少 theme.json 或字段格式不符）"
            case .bubbleInvalid: return ".qibubble 气泡样式解析失败"
            case .qiThemeInvalid: return ".qitheme 主题解析失败（缺少 AppTheme JSON）"
            }
        }
    }
}
