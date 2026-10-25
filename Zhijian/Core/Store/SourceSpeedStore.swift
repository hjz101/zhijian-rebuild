// SourceSpeedStore.swift — 源响应速度统计（P3-06：换源排序 / 体检展示）
import Foundation
import Combine

@MainActor
final class SourceSpeedStore: ObservableObject {
    static let shared = SourceSpeedStore()

    @Published private(set) var entries: [String: SourceSpeedEntry] = [:]
    private let file = "source_speed.json"

    struct SourceSpeedEntry: Codable {
        var count: Int
        var totalMs: Double
        var lastMs: Int
        var updatedAt: Date
    }

    private init() {
        if let payload = AppData.load([String: SourceSpeedEntry].self, file) {
            entries = payload
        }
    }

    func record(sourceURL: String, elapsedMs: Double) {
        var entry = entries[sourceURL] ?? SourceSpeedEntry(count: 0, totalMs: 0, lastMs: 0, updatedAt: Date())
        entry.count += 1
        entry.totalMs += elapsedMs
        entry.lastMs = Int(elapsedMs)
        entry.updatedAt = Date()
        entries[sourceURL] = entry
        AppData.save(entries, file)
    }

    func average(for sourceURL: String) -> Double {
        guard let entry = entries[sourceURL], entry.count > 0 else { return 0 }
        return entry.totalMs / Double(entry.count)
    }

    func reset() {
        entries.removeAll()
        AppData.save(entries, file)
    }

    func sortedSources(_ sources: [BookSource]) -> [BookSource] {
        sources.sorted { lhs, rhs in
            let l = average(for: lhs.bookSourceUrl)
            let r = average(for: rhs.bookSourceUrl)
            if l == 0 && r == 0 { return lhs.bookSourceName < rhs.bookSourceName }
            if l == 0 { return false }
            if r == 0 { return true }
            return l < r
        }
    }
}
