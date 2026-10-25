// ChapterRule.swift — 目录/章节修正规则（去重、去空、卷名、倒序、编号排序）
import Foundation
import Combine

struct ChapterRuleConfig: Codable, Hashable, Sendable {
    var deduplicate: Bool = true
    var dropEmpty: Bool = true
    var detectVolumes: Bool = true
    var autoReverse: Bool = true
    var reverseOrder: Bool = false
    var sortNumbered: Bool = true
    /// 标题清理正则（匹配部分删除），如 `^(正文|最新章节)\s*`
    var titleCleanupRegex: String = ""
    /// 卷名正则
    var volumeRegex: String = #"^\s*(第[0-9一二三四五六七八九十百千零〇两]+[卷部]|卷[0-9一二三四五六七八九十百千零〇两]+)"#
}

struct ChapterRuleOverrides: Codable, Sendable {
    var global: ChapterRuleConfig = ChapterRuleConfig()
    var overrides: [String: ChapterRuleConfig] = [:]
}

enum ChapterRuleEngine {
    struct Result: Sendable {
        var chapters: [SourceChapter]
        var removedDuplicates: Int
        var removedEmpty: Int
        var detectedVolumes: Int
        var reversed: Bool
    }

    static func apply(_ input: [SourceChapter], config: ChapterRuleConfig) -> Result {
        var list = input
        var removedEmpty = 0
        var removedDuplicates = 0
        var detectedVolumes = 0
        var reversed = false

        if config.dropEmpty {
            let before = list.count
            list = list.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            removedEmpty = before - list.count
        }

        if !config.titleCleanupRegex.isEmpty,
           let regex = try? NSRegularExpression(pattern: config.titleCleanupRegex) {
            for index in list.indices {
                let range = NSRange(location: 0, length: (list[index].title as NSString).length)
                list[index].title = regex.stringByReplacingMatches(in: list[index].title, range: range, withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if config.detectVolumes, let volumeRegex = try? NSRegularExpression(pattern: config.volumeRegex, options: [.caseInsensitive]) {
            let chapterRegex = try? NSRegularExpression(pattern: #"第\s*[0-9一二三四五六七八九十百千零〇两]+\s*[章节回话]"#)
            for index in list.indices where !list[index].isVolume {
                let title = list[index].title
                let ns = title as NSString
                let range = NSRange(location: 0, length: ns.length)
                let isVolume = volumeRegex.firstMatch(in: title, range: range) != nil
                let isChapter = chapterRegex?.firstMatch(in: title, range: range) != nil
                if isVolume && !isChapter {
                    list[index].isVolume = true
                    detectedVolumes += 1
                }
            }
        }

        if config.deduplicate {
            var seen = Set<String>()
            var unique: [SourceChapter] = []
            unique.reserveCapacity(list.count)
            for chapter in list {
                let key = normalizeKey(chapter)
                if seen.contains(key) {
                    removedDuplicates += 1
                    continue
                }
                seen.insert(key)
                unique.append(chapter)
            }
            list = unique
        }

        if config.reverseOrder {
            list.reverse()
            reversed = true
        } else if config.autoReverse {
            let numbers = list.compactMap { chapterNumber($0.title) }
            if numbers.count >= 3, let first = numbers.first, let last = numbers.last, first > last {
                list.reverse()
                reversed = true
            }
        }

        if config.sortNumbered {
            list = SourcePipeline.normalizedTOC(list)
        }

        return Result(chapters: list, removedDuplicates: removedDuplicates,
                      removedEmpty: removedEmpty, detectedVolumes: detectedVolumes, reversed: reversed)
    }

    private static func normalizeKey(_ chapter: SourceChapter) -> String {
        let title = chapter.title
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .lowercased()
        return title.isEmpty ? chapter.url : title
    }

    private static func chapterNumber(_ title: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"第\s*([0-9一二三四五六七八九十百千零〇两]+)\s*[章节回话]"#) else { return nil }
        let ns = title as NSString
        guard let match = regex.firstMatch(in: title, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return SourcePipeline.parseTOCNumber(ns.substring(with: match.range(at: 1)))
    }
}

@MainActor
final class ChapterRuleStore: ObservableObject {
    static let shared = ChapterRuleStore()

    @Published private(set) var global = ChapterRuleConfig()
    @Published private(set) var overrides: [String: ChapterRuleConfig] = [:]
    private let file = "chapter_rules.json"

    private init() {
        if let payload = AppData.load(ChapterRuleOverrides.self, file) {
            global = payload.global
            overrides = payload.overrides
        }
    }

    func config(for sourceUrl: String) -> ChapterRuleConfig {
        overrides[sourceUrl] ?? global
    }

    func hasOverride(_ sourceUrl: String) -> Bool { overrides[sourceUrl] != nil }

    func updateGlobal(_ config: ChapterRuleConfig) {
        global = config
        persist()
    }

    func setOverride(_ config: ChapterRuleConfig?, for sourceUrl: String) {
        if let config { overrides[sourceUrl] = config } else { overrides.removeValue(forKey: sourceUrl) }
        persist()
    }

    private func persist() {
        AppData.save(ChapterRuleOverrides(global: global, overrides: overrides), file)
    }
}
