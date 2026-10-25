// SourceBatchTestStore.swift — 书源批量测试：多关键词 × 多源、可选深度四阶段、报告导出
import Foundation
import Combine

struct SourceBatchRow: Identifiable, Hashable, Sendable {
    let id: UUID
    var sourceName: String
    var sourceUrl: String
    var keyword: String
    var ok: Bool
    var count: Int
    var milliseconds: Int
    var detail: String
}

@MainActor
final class SourceBatchTestStore: ObservableObject {
    static let shared = SourceBatchTestStore()

    @Published private(set) var rows: [SourceBatchRow] = []
    @Published private(set) var running = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published var deepTest = false
    @Published var concurrency = 2

    private init() {}

    var reportText: String {
        var lines = ["# 指尖阅读 · 书源批量测试报告", "时间：\(Date().formatted(date: .abbreviated, time: .standard))",
                     "模式：\(deepTest ? "深度四阶段" : "仅搜索")", ""]
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        for row in rows {
            let status = row.ok ? "PASS" : "FAIL"
            lines.append("[\(status)] \(row.sourceName) | \(row.keyword) | \(row.count) 条 | \(row.milliseconds)ms | \(row.detail)")
        }
        lines.append("")
        lines.append("合计：\(rows.count) 项，通过 \(rows.filter(\.ok).count)，失败 \(rows.filter { !$0.ok }.count)")
        return lines.joined(separator: "\n")
    }

    func clear() {
        rows = []; completed = 0; total = 0
    }

    func run(sources: [BookSource], keywords: [String]) async {
        guard !running else { return }
        let enabled = sources.filter { $0.enabled ?? true }
        let keys = keywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !enabled.isEmpty, !keys.isEmpty else { return }

        rows = []
        completed = 0
        total = enabled.count * keys.count
        running = true
        defer { running = false }

        var jobs: [(BookSource, String)] = []
        for source in enabled { for keyword in keys { jobs.append((source, keyword)) } }

        let deep = deepTest
        let initialCookies = CookieStore.shared.snapshot()
        let loginStates = enabled.reduce(into: [String: (info: [String: String], header: [String: String])]()) { result, source in
            result[source.bookSourceUrl] = (SourceLoginStore.shared.loginInfo(for: source.bookSourceUrl),
                                            SourceLoginStore.shared.loginHeader(for: source.bookSourceUrl))
        }
        let limit = max(1, min(concurrency, 4))

        await withTaskGroup(of: SourceBatchRow.self) { group in
            var next = 0
            func addNext() {
                guard next < jobs.count else { return }
                let job = jobs[next]
                next += 1
                let login = loginStates[job.0.bookSourceUrl] ?? ([:], [:])
                group.addTask { await Self.runOne(source: job.0, keyword: job.1, deep: deep,
                                                  initialCookies: initialCookies,
                                                  loginInfo: login.info, loginHeader: login.header) }
            }
            for _ in 0..<min(limit, jobs.count) { addNext() }
            for await row in group {
                rows.append(row)
                completed += 1
                addNext()
            }
        }
    }

    private nonisolated static func runOne(source: BookSource, keyword: String, deep: Bool,
                                           initialCookies: [String: [String: String]],
                                           loginInfo: [String: String],
                                           loginHeader: [String: String]) async -> SourceBatchRow {
        let start = Date()
        let pipeline = SourcePipeline(source: source, initialCookies: initialCookies,
                                      loginInfo: loginInfo, loginHeader: loginHeader,
                                      onCookiesChanged: { CookieStore.onChange($0) })
        do {
            let books = try await pipeline.search(keyword, page: 1)
            var detail = books.first.map { "首条《\($0.name)》" } ?? "0 条"
            if deep, let first = books.first {
                let info = try await pipeline.bookInfo(first)
                let toc = try await pipeline.toc(info)
                detail += " · 目录 \(toc.count) 章"
                if let chapter = toc.first {
                    let content = try await pipeline.content(chapter, book: info)
                    detail += " · 正文 \(content.characters) 字"
                }
            }
            return SourceBatchRow(id: UUID(), sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl,
                                  keyword: keyword, ok: !books.isEmpty, count: books.count,
                                  milliseconds: Int(Date().timeIntervalSince(start) * 1000),
                                  detail: detail)
        } catch {
            return SourceBatchRow(id: UUID(), sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl,
                                  keyword: keyword, ok: false, count: 0,
                                  milliseconds: Int(Date().timeIntervalSince(start) * 1000),
                                  detail: error.localizedDescription)
        }
    }
}
