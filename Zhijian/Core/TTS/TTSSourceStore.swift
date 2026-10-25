// TTSSourceStore.swift — HTTP TTS 源的 JSON 持久化 / 导入 / 导出
import Foundation
import Combine

/// HTTP TTS 源仓库（Application Support/Zhijian/tts_sources.json）。
///
/// 兼容 Legado / 栖阅 `tts_sources.json` 数组，也兼容 `{"sources":[...]}` 包装；
/// 缺少 `id` 时自动生成，数字 id 会转成字符串。
@MainActor
final class TTSSourceStore: ObservableObject {
    static let shared = TTSSourceStore()

    @Published private(set) var sources: [HttpTTS] = []
    private let file = "tts_sources.json"

    private init() {
        sources = AppData.load([HttpTTS].self, file) ?? []
    }

    // MARK: 查询

    var enabledSources: [HttpTTS] {
        sources.filter { $0.enabled ?? true }
    }

    func source(id: String?) -> HttpTTS? {
        guard let id, !id.isEmpty else { return nil }
        return sources.first { $0.id == id }
    }

    // MARK: 增删改

    func add(_ source: HttpTTS) {
        var item = source
        if item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.id = UUID().uuidString
        }
        if let index = sources.firstIndex(where: { $0.id == item.id }) {
            sources[index] = item
        } else {
            sources.append(item)
        }
        persist()
    }

    func update(_ source: HttpTTS) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else {
            add(source)
            return
        }
        sources[index] = source
        persist()
    }

    func remove(id: String) {
        sources.removeAll { $0.id == id }
        persist()
    }

    func remove(_ source: HttpTTS) {
        remove(id: source.id)
    }

    func toggle(_ source: HttpTTS) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index].enabled = !(sources[index].enabled ?? true)
        persist()
    }

    func replaceAll(_ list: [HttpTTS]) {
        sources = list
        persist()
    }

    func makeBlank() -> HttpTTS {
        HttpTTS(
            id: UUID().uuidString,
            name: "新的 HTTP TTS",
            url: "",
            contentType: "audio/",
            concurrentRate: "1/1000",
            enabledCookieJar: false,
            loginUrl: "",
            loginUi: "",
            loginCheckJs: "",
            header: "",
            jsLib: "",
            enabled: true
        )
    }

    // MARK: 导入 / 导出

    @discardableResult
    func importJSON(_ text: String) throws -> Int {
        let list = try Self.decodeSources(from: Data(text.utf8))
        guard !list.isEmpty else { throw TTSSourceImportError.empty }
        var imported = 0
        for item in list {
            if let index = sources.firstIndex(where: { $0.id == item.id }) {
                sources[index] = item
            } else {
                sources.append(item)
            }
            imported += 1
        }
        persist()
        return imported
    }

    func importJSONFile(_ url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        let list = try Self.decodeSources(from: data)
        guard !list.isEmpty else { throw TTSSourceImportError.empty }
        for item in list {
            if let index = sources.firstIndex(where: { $0.id == item.id }) {
                sources[index] = item
            } else {
                sources.append(item)
            }
        }
        persist()
        return list.count
    }

    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(sources)
    }

    func exportJSON() throws -> String {
        String(decoding: try exportData(), as: UTF8.self)
    }

    /// 导出到临时目录，供 ShareLink / 文件选择器使用。
    func exportFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ZhijianTTS", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent("tts-sources-\(formatter.string(from: Date())).json")
        try exportData().write(to: url, options: .atomic)
        return url
    }

    // MARK: 解析

    static func decodeSources(from data: Data) throws -> [HttpTTS] {
        // 1) 标准模型直接解码
        if let direct = try? JSONDecoder().decode([HttpTTS].self, from: data) {
            return direct.map(normalize)
        }
        // 2) 宽松解析（数字 id、缺失 id、wrapper 对象、未知字段）
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw TTSSourceImportError.invalidJSON("不是合法 JSON")
        }
        let rawArray: [Any]
        if let array = object as? [Any] {
            rawArray = array
        } else if let dictionary = object as? [String: Any] {
            if let array = dictionary["sources"] as? [Any] {
                rawArray = array
            } else if let array = dictionary["ttsSources"] as? [Any] {
                rawArray = array
            } else if let array = dictionary["data"] as? [Any] {
                rawArray = array
            } else {
                rawArray = [dictionary]
            }
        } else {
            throw TTSSourceImportError.invalidJSON("顶层必须是数组或包含 sources 的对象")
        }

        var result: [HttpTTS] = []
        for element in rawArray {
            guard let dictionary = element as? [String: Any] else { continue }
            if let source = source(from: dictionary) { result.append(source) }
        }
        guard !result.isEmpty else { throw TTSSourceImportError.empty }
        return result.map(normalize)
    }

    private static func source(from dictionary: [String: Any]) -> HttpTTS? {
        let url = string(dictionary, ["url", "sourceUrl"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = string(dictionary, ["name", "sourceName"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty || !name.isEmpty else { return nil }

        var id = string(dictionary, ["id", "numericId", "sourceId"])
        if id.isEmpty { id = UUID().uuidString }

        return HttpTTS(
            id: id,
            name: name.isEmpty ? "未命名 TTS" : name,
            url: url,
            contentType: optionalString(dictionary, "contentType"),
            concurrentRate: optionalString(dictionary, "concurrentRate"),
            enabledCookieJar: bool(dictionary, "enabledCookieJar"),
            loginUrl: optionalString(dictionary, "loginUrl"),
            loginUi: optionalString(dictionary, "loginUi"),
            loginCheckJs: optionalString(dictionary, "loginCheckJs"),
            header: optionalString(dictionary, "header"),
            jsLib: optionalString(dictionary, "jsLib"),
            enabled: bool(dictionary, "enabled") ?? true
        )
    }

    private static func normalize(_ source: HttpTTS) -> HttpTTS {
        var item = source
        if item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.id = UUID().uuidString
        }
        if item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.name = "未命名 TTS"
        }
        if item.enabled == nil { item.enabled = true }
        return item
    }

    private static func string(_ dictionary: [String: Any], _ keys: [String]) -> String {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
        }
        return ""
    }

    private static func optionalString(_ dictionary: [String: Any], _ key: String) -> String? {
        guard let value = dictionary[key], !(value is NSNull) else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if let dictionary = value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dictionary),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return nil
    }

    private static func bool(_ dictionary: [String: Any], _ key: String) -> Bool? {
        guard let value = dictionary[key], !(value is NSNull) else { return nil }
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return ["true", "1", "yes"].contains(string.lowercased()) }
        return nil
    }

    private func persist() {
        AppData.save(sources, file)
    }
}

enum TTSSourceImportError: LocalizedError {
    case invalidJSON(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail): return "TTS 源 JSON 无效：\(detail)"
        case .empty: return "没有解析到可用的 TTS 源"
        }
    }
}
