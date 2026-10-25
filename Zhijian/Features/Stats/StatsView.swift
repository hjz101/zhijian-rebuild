// StatsView.swift — 阅读统计（栖阅式浅色玻璃）
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var stats = ReadingStatsStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("阅读统计")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(ZJ.textPrimary)
                        .padding(.top, 6)

                    HStack(spacing: 12) {
                        metricCard(title: "今日合计", value: ReadingStatsStore.text(stats.todaySeconds), icon: "book")
                        metricCard(title: "本周", value: ReadingStatsStore.text(stats.weekSeconds), icon: "clock")
                        metricCard(title: "连续", value: "\(stats.streak)天", icon: "flame")
                    }

                    weekCard
                    summaryCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(QiBackground())
            .navigationBarHidden(true)
        }
    }

    private func metricCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ZJ.textSecondary)
            Text(value)
                .font(.system(size: 22, weight: .bold).monospacedDigit())
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
                Text("本周").font(.system(size: 15, weight: .semibold)).foregroundStyle(ZJ.textPrimary)
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
