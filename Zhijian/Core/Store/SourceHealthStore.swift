// SourceHealthStore.swift — 书源体检：四阶段测试 + 诊断日志（Lead）
import Foundation
import Combine

struct SourceHealthStage: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var ok: Bool
    var milliseconds: Int
    var detail: String
}

struct SourceHealthSummary: Codable, Identifiable, Hashable {
    var id: String { sourceUrl }
    var sourceUrl: String
    var sourceName: String
    var ok: Bool
    var count: Int
    var milliseconds: Int
    var error: String?
    var checkedAt: Date
}

struct SourceHealthReport: Identifiable {
    let id = UUID()
    var sourceUrl: String
    var sourceName: String
    var keyword: String
    var ok: Bool
    var stages: [SourceHealthStage]
    var diagnostics: [String]
    var checkedAt: Date
}

@MainActor
final class SourceHealthStore: ObservableObject {
    static let shared = SourceHealthStore()

    @Published private(set) var summaries: [String: SourceHealthSummary] = [:]
    @Published private(set) var reports: [String: SourceHealthReport] = [:]
    @Published private(set) var running: Set<String> = []
    @Published private(set) var batchRunning = false

    private let file = "source_health.json"

    private init() {
        if let list = AppData.load([SourceHealthSummary].self, file) {
            summaries = Dictionary(uniqueKeysWithValues: list.map { ($0.sourceUrl, $0) })
        }
    }

    func summary(for source: BookSource) -> SourceHealthSummary? { summaries[source.bookSourceUrl] }
    func report(for source: BookSource) -> SourceHealthReport? { reports[source.bookSourceUrl] }

    @discardableResult
    func check(_ source: BookSource, keyword: String) async -> SourceHealthReport {
        if running.contains(source.bookSourceUrl) {
            return reports[source.bookSourceUrl] ?? makeEmptyReport(source, keyword: keyword)
        }
        running.insert(source.bookSourceUrl)
        defer { running.remove(source.bookSourceUrl) }

        let start = Date()
        var stages: [SourceHealthStage] = []
        var failure: String?
        var count = 0

        let pipeline = SourcePipeline(source: source,
                                      initialCookies: CookieStore.shared.snapshot(),
                                      onCookiesChanged: { CookieStore.onChange($0) })

        // 1. 搜索
        var books: [SourceBook] = []
        let s0 = Date()
        do {
            books = try await pipeline.search(keyword, page: 1)
            count = books.count
            stages.append(.init(name: "搜索", ok: !books.isEmpty,
                                milliseconds: Int(Date().timeIntervalSince(s0) * 1000),
                                detail: books.isEmpty ? "0 条结果" : "\(books.count) 条 · 首条《\(books.first?.name ?? "")》"))
            if books.isEmpty { failure = "搜索无结果" }
        } catch {
            stages.append(.init(name: "搜索", ok: false,
                                milliseconds: Int(Date().timeIntervalSince(s0) * 1000),
                                detail: error.localizedDescription))
            failure = error.localizedDescription
        }

        // 2. 详情
        var info: SourceBookInfo?
        if failure == nil, let first = books.first {
            let s1 = Date()
            do {
                let value = try await pipeline.bookInfo(first)
                info = value
                stages.append(.init(name: "详情", ok: true,
                                    milliseconds: Int(Date().timeIntervalSince(s1) * 1000),
                                    detail: "\(value.name) · \(value.author) · 目录地址\(value.tocUrl.isEmpty ? "未提供" : "已提供")"))
            } catch {
                stages.append(.init(name: "详情", ok: false,
                                    milliseconds: Int(Date().timeIntervalSince(s1) * 1000),
                                    detail: error.localizedDescription))
                failure = error.localizedDescription
            }
        } else {
            stages.append(.init(name: "详情", ok: false, milliseconds: 0, detail: "已跳过（搜索失败）"))
        }

        // 3. 目录
        var chapters: [SourceChapter] = []
        if failure == nil, let info {
            let s2 = Date()
            do {
                chapters = try await pipeline.toc(info)
                stages.append(.init(name: "目录", ok: !chapters.isEmpty,
                                    milliseconds: Int(Date().timeIntervalSince(s2) * 1000),
                                    detail: chapters.isEmpty ? "0 章" : "\(chapters.count) 章 · 首章《\(chapters.first?.title ?? "")》"))
                if chapters.isEmpty { failure = "目录为空" }
            } catch {
                stages.append(.init(name: "目录", ok: false,
                                    milliseconds: Int(Date().timeIntervalSince(s2) * 1000),
                                    detail: error.localizedDescription))
                failure = error.localizedDescription
            }
        } else {
            stages.append(.init(name: "目录", ok: false, milliseconds: 0, detail: "已跳过（前序阶段失败）"))
        }

        // 4. 正文
        if failure == nil, let info, let chapter = chapters.first {
            let s3 = Date()
            do {
                let content = try await pipeline.content(chapter, book: info)
                let chars = content.characters
                let preview = content.content.replacingOccurrences(of: "\n", with: " ").prefix(60)
                stages.append(.init(name: "正文", ok: chars > 0,
                                    milliseconds: Int(Date().timeIntervalSince(s3) * 1000),
                                    detail: content.isPaywall
                                        ? "被站点拦截（登录/付费）：\(content.paywallHint ?? "")"
                                        : "\(chars) 字 · \(preview)…"))
                if chars == 0 { failure = "正文为空" }
            } catch {
                stages.append(.init(name: "正文", ok: false,
                                    milliseconds: Int(Date().timeIntervalSince(s3) * 1000),
                                    detail: error.localizedDescription))
                failure = error.localizedDescription
            }
        } else {
            stages.append(.init(name: "正文", ok: false, milliseconds: 0, detail: "已跳过（前序阶段失败）"))
        }

        let total = Int(Date().timeIntervalSince(start) * 1000)
        let ok = failure == nil
        let report = SourceHealthReport(
            sourceUrl: source.bookSourceUrl, sourceName: source.bookSourceName,
            keyword: keyword, ok: ok, stages: stages,
            diagnostics: pipeline.diagnosticsSnapshot, checkedAt: Date()
        )
        reports[source.bookSourceUrl] = report
        summaries[source.bookSourceUrl] = SourceHealthSummary(
            sourceUrl: source.bookSourceUrl, sourceName: source.bookSourceName,
            ok: ok, count: count, milliseconds: total, error: failure, checkedAt: Date()
        )
        persist()
        return report
    }

    func checkAll(_ sources: [BookSource], keyword: String) async {
        guard !batchRunning else { return }
        batchRunning = true
        defer { batchRunning = false }
        for source in sources where (source.enabled ?? true) {
            if Task.isCancelled { break }
            _ = await check(source, keyword: keyword)
        }
    }

    private func makeEmptyReport(_ source: BookSource, keyword: String) -> SourceHealthReport {
        SourceHealthReport(sourceUrl: source.bookSourceUrl, sourceName: source.bookSourceName,
                           keyword: keyword, ok: false, stages: [], diagnostics: [], checkedAt: Date())
    }

    private func persist() {
        AppData.save(Array(summaries.values), file)
    }
}
