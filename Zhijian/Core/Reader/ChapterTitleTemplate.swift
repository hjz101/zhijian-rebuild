// ChapterTitleTemplate.swift — HTML 章节标题模板（元素/样式/布局）
import Foundation
import Combine

struct ChapterTitleElement: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case text, line, ornament, image
        var name: String {
            switch self {
            case .text: return "文字"
            case .line: return "线条"
            case .ornament: return "装饰"
            case .image: return "图片"
            }
        }
    }

    var id: String = UUID().uuidString
    var kind: Kind = .text
    /// 支持 `__TEXT__` 占位符（替换为章节标题）
    var text: String = "__TEXT__"
    /// 相对容器宽度的比例（0–1）
    var x: Double = 0
    var y: Double = 0
    var width: Double = 1
    var height: Double = 0.22
    /// 字号（相对设计宽度 320pt 的 pt 值）
    var fontSize: Double = 20
    var fontWeight: Int = 600
    var colorHex: String = "#1E1A14"
    var letterSpacing: Double = 0.5
    var alignment: String = "center"
    var opacity: Double = 1
    /// 装饰字符（ornament 使用）
    var ornament: String = "❖"
    /// 图片 base64（image 使用，demo 用 CSS 绘制也可）
    var imageBase64: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, kind, text, x, y, width, height, fontSize, fontWeight, colorHex
        case letterSpacing, alignment, opacity, ornament, imageBase64
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .text
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? "__TEXT__"
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 1
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 0.22
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 20
        fontWeight = try c.decodeIfPresent(Int.self, forKey: .fontWeight) ?? 600
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#1E1A14"
        letterSpacing = try c.decodeIfPresent(Double.self, forKey: .letterSpacing) ?? 0.5
        alignment = try c.decodeIfPresent(String.self, forKey: .alignment) ?? "center"
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        ornament = try c.decodeIfPresent(String.self, forKey: .ornament) ?? "❖"
        imageBase64 = try c.decodeIfPresent(String.self, forKey: .imageBase64)
    }
}

struct ChapterTitleTemplate: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String = "自定义标题"
    var isBuiltIn: Bool = false
    /// 设计宽度（px），渲染时按页面宽度等比缩放
    var designWidth: Double = 320
    /// 标题区高度（相对设计宽度的比例）
    var heightRatio: Double = 0.34
    var backgroundHex: String = "#00000000"
    var elements: [ChapterTitleElement] = []

    enum CodingKeys: String, CodingKey {
        case id, name, isBuiltIn, designWidth, heightRatio, backgroundHex, elements
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "自定义标题"
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        designWidth = try c.decodeIfPresent(Double.self, forKey: .designWidth) ?? 320
        heightRatio = try c.decodeIfPresent(Double.self, forKey: .heightRatio) ?? 0.34
        backgroundHex = try c.decodeIfPresent(String.self, forKey: .backgroundHex) ?? "#00000000"
        elements = try c.decodeIfPresent([ChapterTitleElement].self, forKey: .elements) ?? []
    }
}

enum ChapterTitleTemplates {
    static let builtIns: [ChapterTitleTemplate] = {
        var plain = ChapterTitleTemplate()
        plain.id = "builtin-plain"
        plain.name = "简约墨字"
        plain.isBuiltIn = true
        plain.heightRatio = 0.30
        var text = ChapterTitleElement()
        text.kind = .text
        text.text = "__TEXT__"
        text.x = 0.04; text.y = 0.18; text.width = 0.92; text.height = 0.30
        text.fontSize = 22; text.fontWeight = 700; text.letterSpacing = 1.2
        plain.elements = [text]

        var lined = ChapterTitleTemplate()
        lined.id = "builtin-lined"
        lined.name = "墨线留白"
        lined.isBuiltIn = true
        lined.heightRatio = 0.42
        var t2 = text; t2.y = 0.14
        var rule = ChapterTitleElement()
        rule.kind = .line
        rule.x = 0.18; rule.y = 0.55; rule.width = 0.64; rule.height = 0.012
        rule.colorHex = "#B08968"; rule.opacity = 0.8
        lined.elements = [t2, rule]

        var ornament = ChapterTitleTemplate()
        ornament.id = "builtin-ornament"
        ornament.name = "花饰题头"
        ornament.isBuiltIn = true
        ornament.heightRatio = 0.50
        var t3 = text; t3.y = 0.24; t3.fontSize = 24
        var deco = ChapterTitleElement()
        deco.kind = .ornament
        deco.ornament = "·  ❖  ·"
        deco.x = 0.1; deco.y = 0.60; deco.width = 0.8; deco.height = 0.16
        deco.fontSize = 13; deco.colorHex = "#A9714B"; deco.letterSpacing = 4
        var line = rule; line.y = 0.80; line.x = 0.24; line.width = 0.52
        ornament.elements = [t3, deco, line]

        return [plain, lined, ornament]
    }()
}

@MainActor
final class ChapterTitleTemplateStore: ObservableObject {
    static let shared = ChapterTitleTemplateStore()

    @Published private(set) var custom: [ChapterTitleTemplate] = []
    @Published private(set) var selectedID: String = "builtin-plain"
    @Published private(set) var enabled = false
    private let file = "chapter_title_templates.json"

    private struct Payload: Codable {
        var custom: [ChapterTitleTemplate]
        var selectedID: String
        var enabled: Bool
    }

    private init() {
        if let payload = AppData.load(Payload.self, file) {
            custom = payload.custom
            selectedID = payload.selectedID
            enabled = payload.enabled
        }
    }

    var all: [ChapterTitleTemplate] { ChapterTitleTemplates.builtIns + custom }

    var selected: ChapterTitleTemplate? {
        all.first { $0.id == selectedID }
    }

    func select(_ id: String) {
        selectedID = id
        persist()
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        persist()
    }

    func upsert(_ template: ChapterTitleTemplate) {
        if let index = custom.firstIndex(where: { $0.id == template.id }) {
            custom[index] = template
        } else {
            var copy = template
            copy.isBuiltIn = false
            custom.append(copy)
        }
        persist()
    }

    func remove(_ template: ChapterTitleTemplate) {
        guard !template.isBuiltIn else { return }
        custom.removeAll { $0.id == template.id }
        if selectedID == template.id { selectedID = "builtin-plain" }
        persist()
    }

    func duplicate(_ template: ChapterTitleTemplate) -> ChapterTitleTemplate {
        var copy = template
        copy.id = UUID().uuidString
        copy.name = template.name + " 副本"
        copy.isBuiltIn = false
        custom.append(copy)
        persist()
        return copy
    }

    func importJSON(_ text: String) throws -> Int {
        let data = Data(text.utf8)
        let incoming: [ChapterTitleTemplate]
        if let list = try? JSONDecoder().decode([ChapterTitleTemplate].self, from: data) {
            incoming = list
        } else {
            incoming = [try JSONDecoder().decode(ChapterTitleTemplate.self, from: data)]
        }
        for template in incoming {
            var copy = template
            copy.isBuiltIn = false
            if let index = custom.firstIndex(where: { $0.id == copy.id }) { custom[index] = copy }
            else { custom.append(copy) }
        }
        persist()
        return incoming.count
    }

    func exportJSON() throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        let data = try encoder.encode(all)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zhijian-chapter-titles.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func persist() {
        AppData.save(Payload(custom: custom, selectedID: selectedID, enabled: enabled), file)
    }
}
