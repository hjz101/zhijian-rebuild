// ReadingStatsStore.swift — 阅读统计（时长/书籍/连续天数/目标）
import Foundation
import Combine

struct ReadingStatsData: Codable {
    var secondsByDay: [String: Double] = [:]
    var booksByDay: [String: [String]] = [:]
    var dailyGoalMinutes: Int = 30
    var yearlyGoalBooks: Int = 24
}

@MainActor
final class ReadingStatsStore: ObservableObject {
    static let shared = ReadingStatsStore()

    @Published private(set) var data = ReadingStatsData()
    private let file = "reading_stats.json"
    private let legacyFile = "reading_stats.json"
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {
        if let payload = AppData.load(ReadingStatsData.self, file) {
            data = payload
        } else if let legacy = AppData.load([String: Double].self, legacyFile) {
            // 从旧版「纯时长」结构迁移
            data.secondsByDay = legacy
            persist()
        }
    }

    // MARK: - 写入

    func add(seconds: Double, bookId: String? = nil) {
        guard seconds >= 1 else { return }
        let key = formatter.string(from: Date())
        data.secondsByDay[key, default: 0] += seconds
        if let bookId {
            var books = data.booksByDay[key] ?? []
            if !books.contains(bookId) { books.append(bookId) }
            data.booksByDay[key] = books
        }
        persist()
    }

    // MARK: - 目标

    var dailyGoalMinutes: Int {
        get { data.dailyGoalMinutes }
        set { data.dailyGoalMinutes = max(5, min(600, newValue)); persist() }
    }

    var yearlyGoalBooks: Int {
        get { data.yearlyGoalBooks }
        set { data.yearlyGoalBooks = max(1, min(999, newValue)); persist() }
    }

    var dailyGoalSeconds: Double { Double(data.dailyGoalMinutes) * 60 }

    var todayProgress: Double {
        guard dailyGoalSeconds > 0 else { return 0 }
        return min(1, todaySeconds / dailyGoalSeconds)
    }

    var todayRemainingText: String {
        let remaining = dailyGoalSeconds - todaySeconds
        return remaining <= 0 ? "今日目标已达成" : "还差 \(Self.text(remaining))"
    }

    /// 年度已读书籍数（本年度内出现过阅读记录的书籍去重）
    var booksThisYear: Int {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        var ids = Set<String>()
        for (day, books) in data.booksByDay {
            guard let date = formatter.date(from: day),
                  calendar.component(.year, from: date) == year else { continue }
            ids.formUnion(books)
        }
        return ids.count
    }

    var yearlyProgress: Double {
        guard data.yearlyGoalBooks > 0 else { return 0 }
        return min(1, Double(booksThisYear) / Double(data.yearlyGoalBooks))
    }

    // MARK: - 读取

    func seconds(on date: Date) -> Double {
        data.secondsByDay[formatter.string(from: date)] ?? 0
    }

    var todaySeconds: Double { seconds(on: Date()) }

    var weekSeconds: Double {
        let calendar = Calendar.current
        return (0..<7).reduce(0) { result, offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return result }
            return result + seconds(on: day)
        }
    }

    /// 上周（第 7~13 天前）总时长
    var previousWeekSeconds: Double {
        let calendar = Calendar.current
        return (7..<14).reduce(0) { result, offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return result }
            return result + seconds(on: day)
        }
    }

    /// 本周阅读的书籍数（去重）
    var weekBooks: Int {
        let calendar = Calendar.current
        var bookSet = Set<String>()
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            bookSet.formUnion(data.booksByDay[formatter.string(from: day)] ?? [])
        }
        return bookSet.count
    }

    var totalSeconds: Double { data.secondsByDay.values.reduce(0, +) }

    var activeDays: Int { data.secondsByDay.values.filter { $0 >= 60 }.count }

    var dailyAverage: Double {
        guard activeDays > 0 else { return 0 }
        return totalSeconds / Double(activeDays)
    }

    var booksTouched: Int {
        var ids = Set<String>()
        for books in data.booksByDay.values { ids.formUnion(books) }
        return ids.count
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

    /// 最近 N 天趋势
    func recentTrend(days: Int = 30) -> [(date: Date, seconds: Double)] {
        let calendar = Calendar.current
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return (date, seconds(on: date))
        }
    }

    func clearAll() {
        data = ReadingStatsData()
        persist()
    }

    private func persist() {
        AppData.save(data, file)
    }

    #if DEBUG
    func seedDemo() {
        let calendar = Calendar.current
        let values: [Double] = [420, 900, 1500, 600, 2400, 1800, 3000, 1200, 0, 780, 2100, 1500, 900, 2400, 600]
        let bookIds = ["demo-local-001", "demo-pdf-001", "demo-manga-001", "demo-epub-001"]
        for (offset, seconds) in values.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let key = formatter.string(from: day)
            data.secondsByDay[key] = seconds
            if seconds > 0 {
                data.booksByDay[key] = Array(bookIds.prefix((offset % bookIds.count) + 1))
            }
        }
        persist()
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
