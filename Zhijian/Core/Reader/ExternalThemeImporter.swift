// ExternalThemeImporter.swift — 栖阅生态格式导入（R2-05）
// - `.red`（Red App 主题归档）：ZIP 含 theme.json（{name, light, dark, ...}）+ 背景图
// - `.qibubble`（段评气泡样式）：JSON {colorHex, cornerRadius, icon} 或 {light, dark}
import Foundation

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
    var light: QIBubbleSide?
    var dark: QIBubbleSide?

    struct QIBubbleSide: Codable {
        var colorHex: String?
        var color: String?
        var cornerRadius: Double?
        var icon: String?
    }
}

enum ExternalThemeImporter {
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

    /// 导入 `.qibubble` JSON → 气泡样式参数（应用到 ReadingSettings.bubble*）。
    static func importBubble(data: Data) throws -> (colorHex: String, corner: Double, icon: String) {
        let decoder = JSONDecoder()
        guard let bubble = try? decoder.decode(QIBubbleJSON.self, from: data) else {
            throw ThemeError.bubbleInvalid
        }
        let side = bubble.light ?? bubble.dark
        let color = bubble.colorHex ?? bubble.color ?? side?.colorHex ?? side?.color ?? "#E8663D"
        let corner = bubble.cornerRadius ?? side?.cornerRadius ?? 16
        let icon = bubble.icon ?? side?.icon ?? "💬"
        return (color, corner, icon)
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
        case redInvalid, bubbleInvalid
        var errorDescription: String? {
            switch self {
            case .redInvalid: return ".red 主题解析失败（缺少 theme.json 或字段格式不符）"
            case .bubbleInvalid: return ".qibubble 气泡样式解析失败"
            }
        }
    }
}
