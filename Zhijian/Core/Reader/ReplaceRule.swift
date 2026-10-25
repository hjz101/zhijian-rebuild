// ReplaceRule.swift — 正文清洗规则（正则/替换/作用域/顺序/超时）
import Foundation
import Combine

struct ReplaceRule: Codable, Identifiable, Hashable, Sendable {
    enum Scope: String, Codable, CaseIterable, Sendable {
        case content, title, both
        var name: String {
            switch self {
            case .content: return "正文"
            case .title: return "标题"
            case .both: return "正文 + 标题"
            }
        }
    }

    var id: String = UUID().uuidString
    var name: String = ""
    var pattern: String = ""
    var replacement: String = ""
    /// 是否按正则解释 pattern；false 时按字面量替换
    var isRegex: Bool = true
    var scope: Scope = .content
    var enabled: Bool = true
    /// 执行顺序（小的先执行）
    var order: Int = 0
    /// 单条规则超时（秒），默认 1s，防止灾难性回溯
    var timeout: Double = 1.0
    /// 规则分组（空 = 默认）
    var group: String = ""

    init(id: String = UUID().uuidString, name: String = "", pattern: String = "",
         replacement: String = "", isRegex: Bool = true, scope: Scope = .content,
         enabled: Bool = true, order: Int = 0, timeout: Double = 1.0, group: String = "") {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.replacement = replacement
        self.isRegex = isRegex
        self.scope = scope
        self.enabled = enabled
        self.order = order
        self.timeout = timeout
        self.group = group
    }

    enum CodingKeys: String, CodingKey {
        case id, name, pattern, replacement, isRegex, scope, enabled, order, timeout, group
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        replacement = try c.decodeIfPresent(String.self, forKey: .replacement) ?? ""
        isRegex = try c.decodeIfPresent(Bool.self, forKey: .isRegex) ?? true
        scope = try c.decodeIfPresent(Scope.self, forKey: .scope) ?? .content
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        timeout = try c.decodeIfPresent(Double.self, forKey: .timeout) ?? 1.0
    }
}

struct ReplaceRulePackage: Codable, Sendable {
    var version: Int = 1
    var exportedAt: Date = Date()
    var rules: [ReplaceRule]
}

enum ReplaceRuleEngine {
    struct Result: Sendable {
        var text: String
        var applied: Int
        var failures: [String]
    }

    /// 按顺序应用规则；单条超时/正则非法时跳过并记录。
    static func apply(_ rules: [ReplaceRule], to text: String, scope: ReplaceRule.Scope) -> Result {
        var value = text
        var applied = 0
        var failures: [String] = []
        let sorted = rules.filter { $0.enabled && !$0.pattern.isEmpty }
            .sorted { $0.order < $1.order }

        for rule in sorted where rule.scope == scope || rule.scope == .both {
            guard let regex = makeRegex(rule) else {
                failures.append("\(rule.name.isEmpty ? rule.pattern : rule.name)：正则非法")
                continue
            }
            let start = Date()
            var output = ""
            var cursor = value.startIndex
            var matched = false
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
                if Date().timeIntervalSince(start) > max(0.05, rule.timeout) {
                    failures.append("\(rule.name.isEmpty ? rule.pattern : rule.name)：执行超时，已跳过")
                    break
                }
                guard let range = Range(match.range, in: value) else { continue }
                output += value[cursor..<range.lowerBound]
                output += expandedReplacement(rule.replacement, match: match, in: value)
                cursor = range.upperBound
                matched = true
            }
            if failures.last?.hasPrefix(rule.name) == true { continue }
            output += value[cursor...]
            if matched {
                value = output
                applied += 1
            }
        }
        return Result(text: value, applied: applied, failures: failures)
    }

    private static var regexCache: [String: NSRegularExpression] = [:]
    private static let regexLock = NSLock()

    /// 正则编译缓存（替换规则每次应用都编译，缓存避免重复编译）
    private static func makeRegex(_ rule: ReplaceRule) -> NSRegularExpression? {
        let pattern = rule.isRegex ? rule.pattern : NSRegularExpression.escapedPattern(for: rule.pattern)
        regexLock.lock()
        if let cached = regexCache[pattern] {
            regexLock.unlock()
            return cached
        }
        regexLock.unlock()
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        regexLock.lock()
        if regexCache.count > 300 { regexCache.removeAll() }
        regexCache[pattern] = regex
        regexLock.unlock()
        return regex
    }

    private static func expandedReplacement(_ template: String, match: NSTextCheckingResult, in text: String) -> String {
        var result = template
        for index in stride(from: match.numberOfRanges - 1, through: 0, by: -1) {
            let range = match.range(at: index)
            let value = range.location == NSNotFound ? "" : (text as NSString).substring(with: range)
            result = result.replacingOccurrences(of: "$\(index)", with: value)
        }
        result = result.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
        return result
    }
}

@MainActor
final class ReplaceRuleStore: ObservableObject {
    static let shared = ReplaceRuleStore()

    @Published private(set) var rules: [ReplaceRule] = []
    private let file = "replace_rules.json"

    private init() {
        rules = AppData.load([ReplaceRule].self, file) ?? []
    }

    func add(_ rule: ReplaceRule) {
        rules.append(rule)
        normalizeOrder()
        persist()
    }

    func update(_ rule: ReplaceRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { add(rule); return }
        rules[index] = rule
        persist()
    }

    func remove(_ rule: ReplaceRule) {
        rules.removeAll { $0.id == rule.id }
        persist()
    }

    func toggle(_ rule: ReplaceRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index].enabled.toggle()
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
        normalizeOrder()
        persist()
    }

    func replaceAll(_ list: [ReplaceRule]) {
        rules = list
        normalizeOrder()
        persist()
    }

    func importJSON(_ text: String) throws -> Int {
        let data = Data(text.utf8)
        let incoming: [ReplaceRule]
        if let package = try? JSONDecoder().decode(ReplaceRulePackage.self, from: data) {
            incoming = package.rules
        } else {
            incoming = try JSONDecoder().decode([ReplaceRule].self, from: data)
        }
        guard !incoming.isEmpty else { throw RuleImportError.empty }
        for rule in incoming where !rule.pattern.isEmpty {
            if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                rules[index] = rule
            } else {
                rules.append(rule)
            }
        }
        normalizeOrder()
        persist()
        return incoming.count
    }

    func exportJSON() throws -> URL {
        let package = ReplaceRulePackage(rules: rules)
        let data = try JSONEncoder().encode(package)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zhijian-replace-rules.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func cleanContent(_ text: String) -> String {
        ReplaceRuleEngine.apply(rules, to: text, scope: .content).text
    }

    func cleanTitle(_ text: String) -> String {
        ReplaceRuleEngine.apply(rules, to: text, scope: .title).text
    }

    private func normalizeOrder() {
        for index in rules.indices { rules[index].order = index }
    }

    private func persist() {
        AppData.save(rules, file)
    }

    enum RuleImportError: LocalizedError {
        case empty
        var errorDescription: String? { "没有可导入的替换规则" }
    }
}
