// ReaderThemePackage.swift — 主题/预设包（.zjtheme zip：theme.json + 资源）
import Foundation
import SwiftUI
import Combine

struct ReaderThemePreset: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String = "自定义主题"
    var themeName: String = "paper"
    var backgroundHex: String = "#F4EFE4"
    var textHex: String = "#1F1C17"
    var secondaryHex: String = "#6B6459"
    var accentHex: String = "#C2552E"
    var surfaceHex: String = "#EDE5D6"
    var fontName: String = ""
    var fontSize: Double = 20
    var lineHeight: Double = 10
    var paragraphSpacing: Double = 10
    var horizontalPadding: Double = 22
    var isBuiltIn: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, themeName, backgroundHex, textHex, secondaryHex, accentHex, surfaceHex
        case fontName, fontSize, lineHeight, paragraphSpacing, horizontalPadding, isBuiltIn
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "自定义主题"
        themeName = try c.decodeIfPresent(String.self, forKey: .themeName) ?? "paper"
        backgroundHex = try c.decodeIfPresent(String.self, forKey: .backgroundHex) ?? "#F4EFE4"
        textHex = try c.decodeIfPresent(String.self, forKey: .textHex) ?? "#1F1C17"
        secondaryHex = try c.decodeIfPresent(String.self, forKey: .secondaryHex) ?? "#6B6459"
        accentHex = try c.decodeIfPresent(String.self, forKey: .accentHex) ?? "#C2552E"
        surfaceHex = try c.decodeIfPresent(String.self, forKey: .surfaceHex) ?? "#EDE5D6"
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? ""
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 20
        lineHeight = try c.decodeIfPresent(Double.self, forKey: .lineHeight) ?? 10
        paragraphSpacing = try c.decodeIfPresent(Double.self, forKey: .paragraphSpacing) ?? 10
        horizontalPadding = try c.decodeIfPresent(Double.self, forKey: .horizontalPadding) ?? 22
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }

    var isDarkHint: Bool {
        // 背景偏暗即视为深色
        let ui = UIColor(Color(hexString: backgroundHex) ?? Color(hex: 0xF4EFE4))
        var brightness: CGFloat = 0
        ui.getWhite(&brightness, alpha: nil)
        return brightness < 0.5
    }
    var backgroundColor: Color { Color(hexString: backgroundHex) ?? Color(hex: 0xF4EFE4) }
    var surfaceColor: Color { Color(hexString: surfaceHex) ?? Color(hex: 0xEDE5D6) }
    var textColor: Color { Color(hexString: textHex) ?? Color(hex: 0x1F1C17) }
    var secondaryColor: Color { Color(hexString: secondaryHex) ?? Color(hex: 0x6B6459) }
    var accentColor: Color { Color(hexString: accentHex) ?? Color(hex: 0xC2552E) }
}

enum ReaderThemePresets {
    static let builtIns: [ReaderThemePreset] = {
        var paper = ReaderThemePreset()
        paper.id = "preset-paper"
        paper.name = "米宣纸"
        paper.themeName = "paper"
        paper.backgroundHex = "#F4EFE4"
        paper.textHex = "#1F1C17"
        paper.secondaryHex = "#6B6459"
        paper.accentHex = "#C2552E"
        paper.isBuiltIn = true

        var ink = ReaderThemePreset()
        ink.id = "preset-ink"
        ink.name = "深墨夜读"
        ink.themeName = "ink"
        ink.backgroundHex = "#12161C"
        ink.textHex = "#C9C6BF"
        ink.secondaryHex = "#8A8F99"
        ink.accentHex = "#E8663D"
        ink.isBuiltIn = true

        var moss = ReaderThemePreset()
        moss.id = "preset-moss"
        moss.name = "护眼绿"
        moss.themeName = "moss"
        moss.backgroundHex = "#E6EDDF"
        moss.textHex = "#26301F"
        moss.secondaryHex = "#5E6B52"
        moss.accentHex = "#4E8F86"
        moss.isBuiltIn = true

        return [paper, ink, moss]
    }()
}

@MainActor
final class ReaderThemePackageStore: ObservableObject {
    static let shared = ReaderThemePackageStore()

    @Published private(set) var presets: [ReaderThemePreset] = []
    @Published private(set) var selectedID: String? = nil
    private let file = "reader_theme_presets.json"

    private struct Payload: Codable {
        var presets: [ReaderThemePreset]
        var selectedID: String?
    }

    private init() {
        if let payload = AppData.load(Payload.self, file) {
            presets = payload.presets
            selectedID = payload.selectedID
        }
    }

    var all: [ReaderThemePreset] { ReaderThemePresets.builtIns + presets }

    var selected: ReaderThemePreset? { all.first { $0.id == selectedID } }

    func upsert(_ preset: ReaderThemePreset) {
        var copy = preset
        copy.isBuiltIn = false
        if let index = presets.firstIndex(where: { $0.id == copy.id }) { presets[index] = copy }
        else { presets.append(copy) }
        persist()
    }

    func remove(_ preset: ReaderThemePreset) {
        guard !preset.isBuiltIn else { return }
        presets.removeAll { $0.id == preset.id }
        if selectedID == preset.id { selectedID = nil }
        persist()
    }

    func select(_ preset: ReaderThemePreset?) {
        selectedID = preset?.id
        persist()
    }

    /// 从当前阅读设置与配色生成一个预设。
    func makePreset(from settings: ReadingSettings, name: String) -> ReaderThemePreset {
        var preset = ReaderThemePreset()
        preset.name = name
        preset.themeName = settings.theme.rawValue
        preset.fontName = settings.customFontName
        preset.fontSize = settings.fontSize
        preset.lineHeight = settings.lineHeight
        preset.paragraphSpacing = settings.paragraphSpacing
        preset.horizontalPadding = settings.horizontalPadding
        preset.backgroundHex = settings.theme.backgroundHex
        preset.textHex = settings.theme.textHex
        preset.secondaryHex = settings.theme.secondaryHex
        preset.accentHex = settings.theme.accentHex
        return preset
    }

    /// 导出为 `.zjtheme`（ZIP：theme.json + README）。
    func exportPackage(_ preset: ReaderThemePreset) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        let json = try encoder.encode(preset)
        var writer = ZipWriter()
        writer.add(json, name: "theme.json")
        writer.addText("指尖阅读阅读主题包\n导入：设置 → 阅读 → 主题包 → 导入\n",
                       name: "README.txt")
        let data = writer.build()
        let safe = preset.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safe).zjtheme")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 导入 `.zjtheme` 或裸 JSON。
    func importPackage(url: URL) throws -> ReaderThemePreset {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        if let preset = try? decoder.decode(ReaderThemePreset.self, from: data) {
            upsert(preset)
            return preset
        }
        let reader = try ZipReader(data: data)
        guard let name = reader.entryNames.first(where: { $0.hasSuffix("theme.json") }),
              let json = try? reader.read(name) else {
            throw ThemeError.invalidPackage
        }
        let preset = try decoder.decode(ReaderThemePreset.self, from: json)
        upsert(preset)
        return preset
    }

    /// 应用预设到阅读设置。
    func apply(_ preset: ReaderThemePreset, to store: SettingsStore) {
        var settings = store.settings
        settings.theme = ReaderTheme(rawValue: preset.themeName) ?? .paper
        settings.fontSize = preset.fontSize
        settings.lineHeight = preset.lineHeight
        settings.paragraphSpacing = preset.paragraphSpacing
        settings.horizontalPadding = preset.horizontalPadding
        // 外部主题（.red/.qitheme/.zjtheme）带 chrome 色 → 走自定义配色，完整呈现背景/正文/强调/surface
        settings.customPalette = ReaderCustomPalette(
            backgroundHex: preset.backgroundHex,
            textHex: preset.textHex,
            secondaryHex: preset.secondaryHex,
            accentHex: preset.accentHex,
            surfaceHex: preset.surfaceHex,
            isDark: preset.isDarkHint
        )
        if !preset.fontName.isEmpty, CustomFontStore.shared.fonts.contains(where: { $0.postScriptName == preset.fontName }) {
            settings.customFontName = preset.fontName
        }
        store.settings = settings
        selectedID = preset.id
        persist()
    }

    private func persist() {
        AppData.save(Payload(presets: presets, selectedID: selectedID), file)
    }

    enum ThemeError: LocalizedError {
        case invalidPackage
        var errorDescription: String? { "主题包无效：缺少 theme.json 或内容格式不正确" }
    }
}
