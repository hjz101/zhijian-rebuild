// StatsView.swift — 阅读统计（时长/目标/趋势，栖阅式玻璃 + Swift Charts 面积图）
import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var stats = ReadingStatsStore.shared
    @State private var showGoalSheet = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(LocalizationManager.tr("stats.title"))
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(ZJ.textPrimary)
                        Spacer()
                        Button { showGoalSheet = true } label: {
                            Image(systemName: "target")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(ZJ.textSecondary)
                                .frame(width: 34, height: 34)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            exportCSV()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(ZJ.textSecondary)
                                .frame(width: 34, height: 34)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    todayGoalCard
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("导出 CSV", systemImage: "square.and.arrow.up") }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ZJ.accent)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(ZJ.accent.opacity(0.1), in: Capsule())
                    }

                    HStack(spacing: 12) {
                        metricCard(title: LocalizationManager.tr("stats.week"), value: ReadingStatsStore.text(stats.weekSeconds), icon: "clock")
                        metricCard(title: LocalizationManager.tr("stats.streak"), value: "\(stats.streak)天", icon: "flame")
                        metricCard(title: "书籍", value: "\(stats.booksTouched)本", icon: "books.vertical")
                    }

                    weekCard
                    trendCard
                    heatmapCard
                    yearlyCard
                    summaryCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(QiBackground())
            .navigationBarHidden(true)
            .sheet(isPresented: $showGoalSheet) {
                StatsGoalSheet()
            }
        }
    }

    private var todayGoalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("今日合计").font(.system(size: 12)).foregroundStyle(ZJ.textSecondary)
                    Text(ReadingStatsStore.text(stats.todaySeconds))
                        .font(.system(size: 28, weight: .bold).monospacedDigit())
                        .foregroundStyle(ZJ.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("目标 \(stats.dailyGoalMinutes) 分").font(.system(size: 11)).foregroundStyle(ZJ.textSecondary)
                    Text(stats.todayRemainingText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(stats.todayProgress >= 1 ? ZJ.celadon : ZJ.accent)
                }
            }
            ProgressView(value: stats.todayProgress)
                .tint(stats.todayProgress >= 1 ? ZJ.celadon : ZJ.accent)
                .scaleEffect(x: 1, y: 1.6, anchor: .center)
            Text("\(Int(stats.todayProgress * 100))% 完成")
                .font(.system(size: 10))
                .foregroundStyle(ZJ.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qiCard()
    }

    private func metricCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ZJ.textSecondary)
            Text(value)
                .font(.system(size: 20, weight: .bold).monospacedDigit())
                .foregroundStyle(ZJ.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(ZJ.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qiCard(cornerRadius: 20, padding: 14)
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(LocalizationManager.tr("stats.week")).font(.system(size: 15, weight: .semibold)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                Text(ReadingStatsStore.text(stats.weekSeconds)).font(.system(size: 12)).foregroundStyle(ZJ.textSecondary)
            }
            let days = stats.recentWeek()
            let maxValue = max(days.map(\.seconds).max() ?? 0, 60)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(day.seconds > 0 ? ZJ.accent : ZJ.textTertiary.opacity(0.18))
                            .frame(width: 22, height: max(6, CGFloat(day.seconds / maxValue) * 96))
                        Text(day.label)
                            .font(.system(size: 10))
                            .foregroundStyle(ZJ.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 124, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qiCard()
    }

    private var trendCard: some View {
        let trend = stats.recentTrend(days: 30)
        let maxValue = max(trend.map(\.seconds).max() ?? 0, 60)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LocalizationManager.tr("stats.trend30")).font(.system(size: 15, weight: .semibold)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                Text("共 \(ReadingStatsStore.text(trend.reduce(0) { $0 + $1.seconds }))")
                    .font(.system(size: 11)).foregroundStyle(ZJ.textSecondary)
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(trend.enumerated()), id: \.offset) { _, item in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(item.seconds > 0 ? ZJ.accent.opacity(0.75) : ZJ.textTertiary.opacity(0.12))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(3, CGFloat(item.seconds / maxValue) * 78))
                }
            }
            .frame(height: 80, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qiCard()
    }

    private func exportCSV() {
        let trend = stats.recentTrend(days: 90)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var lines = ["date,minutes"]
        for item in trend {
            lines.append("\(formatter.string(from: item.date)),\(Int(item.seconds / 60))")
        }
        let csv = lines.joined(separator: "\n")
        let url = AppData.root.appendingPathComponent("reading-stats-export.csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        exportURL = url
    }

    private var heatmapCard: some View {
        // GitHub 风格热力图：近 12 周（周日起始）
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today) // 1 周日
        let daysFromSunday = todayWeekday - 1
        let end = calendar.date(byAdding: .day, value: -daysFromSunday, to: today) ?? today
        let weeks = 12
        let start = calendar.date(byAdding: .day, value: -(weeks * 7 - 1), to: end) ?? end
        let maxMinutes = max(stats.recentTrend(days: 84).map { $0.seconds / 60 }.max() ?? 0, 30)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LocalizationManager.tr("stats.heatmap"))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(heatColor(level: level, maxMinutes: max(30, maxMinutes)))
                            .frame(width: 10, height: 10)
                    }
                }
            }
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { day in
                            if let date = calendar.date(byAdding: .day,
                                                        value: week * 7 + day,
                                                        to: start) {
                                let minutes = stats.seconds(on: date) / 60
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(heatColor(level: level(for: minutes, max: maxMinutes),
                                                   maxMinutes: maxMinutes))
                                    .frame(width: 11, height: 11)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qiCard()
    }

    private func level(for minutes: Double, max: Double) -> Int {
        guard minutes > 0, max > 0 else { return 0 }
        let ratio = minutes / max
        if ratio < 0.25 { return 1 }
        if ratio < 0.5 { return 2 }
        if ratio < 0.75 { return 3 }
        return 4
    }

    private func heatColor(level: Int, maxMinutes: Double) -> Color {
        switch level {
        case 0: return ZJ.textTertiary.opacity(0.10)
        case 1: return ZJ.accent.opacity(0.22)
        case 2: return ZJ.accent.opacity(0.42)
        case 3: return ZJ.accent.opacity(0.66)
        default: return ZJ.accent.opacity(0.92)
        }
    }

    private var yearlyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("年度目标").font(.system(size: 15, weight: .semibold)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                Text("\(stats.booksThisYear) / \(stats.yearlyGoalBooks) 本")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(ZJ.textSecondary)
            }
            ProgressView(value: stats.yearlyProgress).tint(ZJ.celadon)
            Text("今年读过 \(stats.booksTouched) 本书，年度目标 \(stats.yearlyGoalBooks) 本")
                .font(.system(size: 10))
                .foregroundStyle(ZJ.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qiCard()
    }

    private var summaryCard: some View {
        VStack(spacing: 14) {
            HStack {
                summaryItem(title: "总时长", value: ReadingStatsStore.text(stats.totalSeconds))
                Divider().frame(height: 28)
                summaryItem(title: "活跃天", value: "\(stats.activeDays)天")
                Divider().frame(height: 28)
                summaryItem(title: "日均", value: ReadingStatsStore.text(stats.dailyAverage))
            }
            Divider().opacity(0.5)
            HStack {
                Label("书架 \(env.books.books.count) 本", systemImage: "books.vertical")
                    .font(.system(size: 12))
                    .foregroundStyle(ZJ.textSecondary)
                Spacer()
                Label("书源 \(env.sources.sources.count) 个", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12))
                    .foregroundStyle(ZJ.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .qiCard()
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(ZJ.textPrimary)
            Text(title).font(.system(size: 10)).foregroundStyle(ZJ.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StatsGoalSheet: View {
    @ObservedObject private var stats = ReadingStatsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var dailyMinutes = 30
    @State private var yearlyBooks = 24

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    QiSettingsSection(title: "每日目标") {
                        QiSliderRow(title: "阅读时长", value: Binding(
                            get: { Double(dailyMinutes) },
                            set: { dailyMinutes = Int($0) }
                        ), range: 10...180, step: 5) { "\(Int($0)) 分" }
                    }
                    QiSettingsSection(title: "年度目标") {
                        QiSliderRow(title: "每年读完", value: Binding(
                            get: { Double(yearlyBooks) },
                            set: { yearlyBooks = Int($0) }
                        ), range: 5...200, step: 5) { "\(Int($0)) 本" }
                    }
                    QiSettingsSection(title: "数据") {
                        QiRow(icon: "chart.bar", title: "今年已读", value: "\(stats.booksThisYear) 本")
                        QiDivider()
                        Button(role: .destructive) {
                            stats.clearAll()
                            dismiss()
                        } label: {
                            Text("清空统计数据")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(ZJ.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(QiBackground())
            .navigationTitle("阅读目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        stats.dailyGoalMinutes = dailyMinutes
                        stats.yearlyGoalBooks = yearlyBooks
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
            }
            .onAppear {
                dailyMinutes = stats.dailyGoalMinutes
                yearlyBooks = stats.yearlyGoalBooks
            }
        }
    }
}
