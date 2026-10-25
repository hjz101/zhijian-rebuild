// ReadingStatsStore.swift — 阅读时长统计（按日）
import Foundation
import Combine

@MainActor
final class ReadingStatsStore: ObservableObject {
    static let shared = ReadingStatsStore()

    @Published private(set) var secondsByDay: [String: Double] = [:]
    private let file = "reading_stats.json"
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {
        secondsByDay = AppData.load([String: Double].self, file) ?? [:]
    }

    func add(seconds: Double) {
        guard seconds >= 1 else { return }
        let key = formatter.string(from: Date())
        secondsByDay[key, default: 0] += seconds
        AppData.save(secondsByDay, file)
    }

    func seconds(on date: Date) -> Double {
        secondsByDay[formatter.string(from: date)] ?? 0
    }

    var todaySeconds: Double { seconds(on: Date()) }

    var weekSeconds: Double {
        let calendar = Calendar.current
        return (0..<7).reduce(0) { result, offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return result }
            return result + seconds(on: day)
        }
    }

    var totalSeconds: Double { secondsByDay.values.reduce(0, +) }

    var activeDays: Int { secondsByDay.values.filter { $0 >= 60 }.count }

    var dailyAverage: Double {
        guard activeDays > 0 else { return 0 }
        return totalSeconds / Double(activeDays)
    }

    var streak: Int {
        let calendar = Calendar.current
        var count = 0
        var day = Date()
        if seconds(on: day) < 60 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  seconds(on: yesterday) >= 60 else { return 0 }
            day = yesterday
        }
        while seconds(on: day) >= 60 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// 最近 7 天（从 6 天前到今天）
    func recentWeek() -> [(label: String, date: Date, seconds: Double)] {
        let calendar = Calendar.current
        let labels = ["日", "一", "二", "三", "四", "五", "六"]
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let index = calendar.component(.weekday, from: date) - 1
            return (labels[max(0, min(labels.count - 1, index))], date, seconds(on: date))
        }
    }

    #if DEBUG
    func seedDemo() {
        let calendar = Calendar.current
        let values: [Double] = [420, 900, 1500, 600, 2400, 1800, 3000]
        for (offset, seconds) in values.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            secondsByDay[formatter.string(from: day)] = seconds
        }
        AppData.save(secondsByDay, file)
    }
    #endif

    static func text(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        if value < 60 { return "\(value)秒" }
        if value < 3600 { return "\(value / 60)分" }
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        return minutes == 0 ? "\(hours)小时" : "\(hours)小时\(minutes)分"
    }
}
