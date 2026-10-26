// WidgetSnapshot.swift — 与宿主共享的数据结构（宿主 Zhijian/Core/Store/WidgetBridge.swift 同款）
import Foundation

struct WidgetSnapshot: Codable {
    var bookTitle: String = ""
    var chapterTitle: String = ""
    var progress: Double = 0
    var totalMinutesToday: Int = 0
    var weekMinutes: Int = 0
    var bookshelfCount: Int = 0
    var updatedAt: Date = Date()
}
