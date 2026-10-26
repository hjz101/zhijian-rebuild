// WidgetBridge.swift — 小组件共享数据层（App Group UserDefaults）
// 宿主 App 写入书架/进度/统计摘要，Widget extension 只读。
import Foundation

struct WidgetSnapshot: Codable {
    var bookTitle: String = ""
    var chapterTitle: String = ""
    var progress: Double = 0        // 0...1 章节进度
    var totalMinutesToday: Int = 0
    var weekMinutes: Int = 0
    var bookshelfCount: Int = 0
    var updatedAt: Date = Date()
}

enum WidgetBridge {
    static let appGroupID = "group.com.zhijian.reader"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults = sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: "widget.snapshot")
        }
    }

    static func load() -> WidgetSnapshot? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: "widget.snapshot") else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
