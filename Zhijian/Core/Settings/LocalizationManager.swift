// LocalizationManager.swift — 多语言骨架（⑥ i18n：中文/英文，逐步迁移文案）
import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Sendable {
    case zh, en
    var name: String { self == .zh ? "简体中文" : "English" }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "zhijian.app.language") }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "zhijian.app.language") ?? "zh"
        language = AppLanguage(rawValue: raw) ?? .zh
    }

    /// 文案表（当前覆盖高频 UI 文案；其余逐步迁移）
    static func tr(_ key: String) -> String {
        let language = shared.language
        switch key {
        case "shelf.title": return language == .zh ? "书架" : "Shelf"
        case "stats.title": return language == .zh ? "阅读统计" : "Reading Stats"
        case "settings.title": return language == .zh ? "设置" : "Settings"
        case "discover.title": return language == .zh ? "发现" : "Discover"
        case "continue": return language == .zh ? "继续" : "Continue"
        case "recent": return language == .zh ? "最近阅读" : "Recent"
        default: return key
        }
    }
}
