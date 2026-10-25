// LegadoModels.swift — 书源/规则/书籍的最小完备模型（对齐 Legado BookSource 35 字段）
import Foundation

// MARK: - 规则字段

enum RuleValue: Codable, Hashable, Sendable {
    case string(String)
    case object([String: RuleValue])
    case array([RuleValue])
    case number(Double)
    case boolean(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode(Bool.self) { self = .boolean(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode([String: RuleValue].self) { self = .object(v); return }
        if let v = try? c.decode([RuleValue].self) { self = .array(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .boolean(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    var ruleString: String? {
        guard let s = stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
    var textValue: String {
        switch self {
        case .string(let v): return v
        case .number(let v): return v == v.rounded() && abs(v) < 1e15 ? String(Int64(v)) : String(v)
        case .boolean(let v): return v ? "true" : "false"
        case .null: return ""
        case .array, .object:
            guard let d = try? JSONEncoder().encode(self), let s = String(data: d, encoding: .utf8) else { return "" }
            return s
        }
    }
    var isEmpty: Bool {
        switch self {
        case .null: return true
        case .string(let v): return v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let v): return v.isEmpty
        case .object(let v): return v.isEmpty
        default: return false
        }
    }
}

// MARK: - 规则组（字段名与 Legado 一致）

struct SearchRule: Codable, Hashable, Sendable {
    var bookList: RuleValue?
    var name: RuleValue?
    var author: RuleValue?
    var kind: RuleValue?
    var intro: RuleValue?
    var lastChapter: RuleValue?
    var coverUrl: RuleValue?
    var wordCount: RuleValue?
    var bookUrl: RuleValue?
    var checkKeyWord: RuleValue?
    var updateTime: RuleValue?
}

struct BookInfoRule: Codable, Hashable, Sendable {
    var `init`: RuleValue?
    var name: RuleValue?
    var author: RuleValue?
    var intro: RuleValue?
    var kind: RuleValue?
    var lastChapter: RuleValue?
    var coverUrl: RuleValue?
    var wordCount: RuleValue?
    var updateTime: RuleValue?
    var tocUrl: RuleValue?
    var canReName: RuleValue?
    var downloadUrls: RuleValue?
}

struct TocRule: Codable, Hashable, Sendable {
    var chapterList: RuleValue?
    var chapterName: RuleValue?
    var chapterUrl: RuleValue?
    var isVolume: RuleValue?
    var isVip: RuleValue?
    var isPay: RuleValue?
    var updateTime: RuleValue?
    var preUpdateJs: RuleValue?
    var nextTocUrl: RuleValue?
    var formatJs: RuleValue?
}

struct ContentRule: Codable, Hashable, Sendable {
    var content: RuleValue?
    var title: RuleValue?
    var subContent: RuleValue?
    var nextContentUrl: RuleValue?
    var replaceRegex: RuleValue?
    var webJs: RuleValue?
    var sourceRegex: RuleValue?
    var imageStyle: RuleValue?
    var imageDecode: RuleValue?
    var payAction: RuleValue?
    var callBackJs: RuleValue?
}

struct ExploreRule: Codable, Hashable, Sendable {
    var bookList: RuleValue?
    var name: RuleValue?
    var author: RuleValue?
    var kind: RuleValue?
    var intro: RuleValue?
    var lastChapter: RuleValue?
    var coverUrl: RuleValue?
    var wordCount: RuleValue?
    var bookUrl: RuleValue?
    var updateTime: RuleValue?
}

struct ReviewRule: Codable, Hashable, Sendable {
    var reviewUrl: RuleValue?
    var avatarRule: RuleValue?
    var contentRule: RuleValue?
    var postTimeRule: RuleValue?
    var inlineHotReview: RuleValue?
    var reviewQuoteUrl: RuleValue?
    var voteUpUrl: RuleValue?
    var voteDownUrl: RuleValue?
    var postReviewUrl: RuleValue?
    var postQuoteUrl: RuleValue?
    var deleteUrl: RuleValue?
}

// MARK: - 书源

struct BookSource: Codable, Hashable, Sendable, Identifiable {
    var bookSourceName: String = ""
    var bookSourceUrl: String = ""
    var bookSourceGroup: String?
    var bookSourceType: Int?
    var bookSourceComment: String?
    var enabled: Bool?
    var enabledExplore: Bool?
    var enabledCookieJar: Bool?
    var searchUrl: String?
    var exploreUrl: String?
    var header: RuleValue?
    var loginUrl: String?
    var loginUi: String?
    var loginCheckJs: String?
    var jsLib: String?
    var concurrentRate: String?
    var respondTime: Int?
    var weight: Int?
    var customOrder: Int?
    var lastUpdateTime: Int64?
    var variableComment: String?
    var providerType: String?
    var customButton: RuleValue?
    var eventListener: RuleValue?
    var coverDecodeJs: String?
    var bookUrlPattern: String?
    var exploreScreen: RuleValue?
    var ruleSearch: SearchRule?
    var ruleBookInfo: BookInfoRule?
    var ruleToc: TocRule?
    var ruleContent: ContentRule?
    var ruleExplore: ExploreRule?
    var ruleReview: ReviewRule?

    var id: String { bookSourceUrl }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys, _ d: String = "") -> String { (try? c.decodeIfPresent(String.self, forKey: k)) ?? d }
        bookSourceName = s(.bookSourceName)
        bookSourceUrl = s(.bookSourceUrl)
        bookSourceGroup = try? c.decodeIfPresent(String.self, forKey: .bookSourceGroup)
        bookSourceType = try? c.decodeIfPresent(Int.self, forKey: .bookSourceType)
        bookSourceComment = try? c.decodeIfPresent(String.self, forKey: .bookSourceComment)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        enabledExplore = try? c.decodeIfPresent(Bool.self, forKey: .enabledExplore)
        enabledCookieJar = try? c.decodeIfPresent(Bool.self, forKey: .enabledCookieJar)
        searchUrl = try? c.decodeIfPresent(String.self, forKey: .searchUrl)
        exploreUrl = try? c.decodeIfPresent(String.self, forKey: .exploreUrl)
        header = try? c.decodeIfPresent(RuleValue.self, forKey: .header)
        loginUrl = try? c.decodeIfPresent(String.self, forKey: .loginUrl)
        loginUi = try? c.decodeIfPresent(String.self, forKey: .loginUi)
        loginCheckJs = try? c.decodeIfPresent(String.self, forKey: .loginCheckJs)
        jsLib = try? c.decodeIfPresent(String.self, forKey: .jsLib)
        concurrentRate = try? c.decodeIfPresent(String.self, forKey: .concurrentRate)
        respondTime = try? c.decodeIfPresent(Int.self, forKey: .respondTime)
        weight = try? c.decodeIfPresent(Int.self, forKey: .weight)
        customOrder = try? c.decodeIfPresent(Int.self, forKey: .customOrder)
        lastUpdateTime = try? c.decodeIfPresent(Int64.self, forKey: .lastUpdateTime)
        variableComment = try? c.decodeIfPresent(String.self, forKey: .variableComment)
        providerType = try? c.decodeIfPresent(String.self, forKey: .providerType)
        customButton = try? c.decodeIfPresent(RuleValue.self, forKey: .customButton)
        eventListener = try? c.decodeIfPresent(RuleValue.self, forKey: .eventListener)
        coverDecodeJs = try? c.decodeIfPresent(String.self, forKey: .coverDecodeJs)
        bookUrlPattern = try? c.decodeIfPresent(String.self, forKey: .bookUrlPattern)
        exploreScreen = try? c.decodeIfPresent(RuleValue.self, forKey: .exploreScreen)
        ruleSearch = try? c.decodeIfPresent(SearchRule.self, forKey: .ruleSearch)
        ruleBookInfo = try? c.decodeIfPresent(BookInfoRule.self, forKey: .ruleBookInfo)
        ruleToc = try? c.decodeIfPresent(TocRule.self, forKey: .ruleToc)
        ruleContent = try? c.decodeIfPresent(ContentRule.self, forKey: .ruleContent)
        ruleExplore = try? c.decodeIfPresent(ExploreRule.self, forKey: .ruleExplore)
        ruleReview = try? c.decodeIfPresent(ReviewRule.self, forKey: .ruleReview)
    }

    var headerMap: [String: String] {
        guard let header, !header.isEmpty else { return [:] }
        if case .object(let obj) = header {
            return obj.mapValues { $0.textValue }
        }
        guard let parsed = LenientJSON.parse(header.textValue) as? [String: Any] else { return [:] }
        return parsed.reduce(into: [:]) { $0[$1.key] = RuleEngine.text($1.value) }
    }
}

enum BookSourceLoader {
    enum LoadError: LocalizedError { case empty, invalidJSON
        var errorDescription: String? {
            switch self { case .empty: return "书源内容为空"; case .invalidJSON: return "书源 JSON 解析失败" }
        }
    }
    static func load(_ text: String) throws -> [BookSource] {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw LoadError.empty }
        guard let data = raw.data(using: .utf8) else { throw LoadError.invalidJSON }
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([BookSource].self, from: data) { return list }
        if let one = try? decoder.decode(BookSource.self, from: data) { return [one] }
        // Legado 有时把书源包在 {"bookSources":[…]} 里
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arr = obj["bookSources"] as? [[String: Any]],
           let d = try? JSONSerialization.data(withJSONObject: arr),
           let list = try? decoder.decode([BookSource].self, from: d) {
            return list
        }
        throw LoadError.invalidJSON
    }
}
