// ZhijianWidget.swift — 指尖阅读桌面小组件（阅读进度 + 今日统计）
// 集成：在 Xcode 中新建 Widget Extension target（File → New → Target → Widget Extension），
// 将本目录三个文件加入；勾选 App Group = group.com.zhijian.reader（与宿主一致）。
import WidgetKit
import SwiftUI

struct ReadingEntry: TimelineEntry {
    let date: Date
    let bookTitle: String
    let chapterTitle: String
    let progress: Double
    let todayMinutes: Int
    let weekMinutes: Int
}

struct ReadingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadingEntry {
        ReadingEntry(date: Date(), bookTitle: "——", chapterTitle: "", progress: 0, todayMinutes: 0, weekMinutes: 0)
    }
    func getSnapshot(in context: Context, completion: @escaping (ReadingEntry) -> Void) {
        completion(currentEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadingEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
    private func currentEntry() -> ReadingEntry {
        let defaults = UserDefaults(suiteName: "group.com.zhijian.reader")
        let data = defaults?.data(forKey: "widget.snapshot")
        let snapshot = data.flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
        return ReadingEntry(date: Date(),
                            bookTitle: snapshot?.bookTitle ?? "——",
                            chapterTitle: snapshot?.chapterTitle ?? "",
                            progress: snapshot?.progress ?? 0,
                            todayMinutes: snapshot?.totalMinutesToday ?? 0,
                            weekMinutes: snapshot?.weekMinutes ?? 0)
    }
}

struct ReadingWidgetView: View {
    var entry: ReadingEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                Label("指尖阅读", systemImage: "book.closed.fill").font(.system(size: 11, weight: .semibold))
                Text(entry.bookTitle).font(.system(size: 15, weight: .bold)).lineLimit(1)
                ProgressView(value: entry.progress).tint(.orange)
                Text("今日 \\(entry.todayMinutes) 分").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        default:
            HStack(spacing: 14) {
                Image(systemName: "book.closed.fill").font(.system(size: 30)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Label("指尖阅读", systemImage: "book.closed.fill").font(.system(size: 11, weight: .semibold))
                    Text(entry.bookTitle).font(.system(size: 17, weight: .bold)).lineLimit(1)
                    if !entry.chapterTitle.isEmpty {
                        Text(entry.chapterTitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    ProgressView(value: entry.progress).tint(.orange)
                    HStack(spacing: 8) {
                        Text("今日 \\(entry.todayMinutes) 分")
                        Text("本周 \\(entry.weekMinutes) 分")
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }
}

struct ReadingWidget: Widget {
    let kind = "ZhijianReadingWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReadingProvider()) { entry in
            ReadingWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("阅读进度")
        .description("查看当前阅读进度与今日时长")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ZhijianWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadingWidget()
    }
}
