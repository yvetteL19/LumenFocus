//
//  StatisticsView.swift
//  LumenFocus
//
//  Monthly heatmap (GitHub contributions style, black-and-white), KPI cards,
//  week chart, full CSV export.
//

import SwiftUI
import Charts
import UniformTypeIdentifiers

struct StatisticsView: View {
    @State private var weeklyStats: [DailyStatistics] = []
    @State private var ninetyDay: [DailyStatistics] = []
    @State private var currentStreak: Int = 0
    @State private var longestStreak: Int = 0
    @State private var maxRestCountInWindow: Int = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("统计")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color.LumenFocus.textPrimary)

                HStack(spacing: 12) {
                    StatCard(label: "当前 streak", value: String(format: L("%d 天"), currentStreak))
                    StatCard(label: "最长 streak", value: String(format: L("%d 天"), longestStreak))
                    StatCard(label: "本周护眼", value: String(format: L("%d 次"), weeklyStats.reduce(0) { $0 + $1.restCount }))
                    StatCard(label: "本周用眼", value: StatisticsManager.shared.getWeeklyWorkDurationFormatted())
                }

                if hasAnyRest {
                    weekChartSection
                    heatmapSection
                } else {
                    emptyState
                }

                Spacer(minLength: 12)

                HStack {
                    Text("数据完全本地存储 · 卸载即删除")
                        .font(.system(size: 11))
                        .foregroundColor(Color.LumenFocus.textTertiary)
                    Spacer()
                    Button("导出 CSV") { exportCSV() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.LumenFocus.backgroundPrimary)
        .onAppear { refresh() }
    }

    /// 是否已有任何护眼记录（用于决定显示图表还是空状态）
    private var hasAnyRest: Bool {
        longestStreak > 0 || ninetyDay.contains { $0.restCount > 0 }
    }

    // MARK: - Sections

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(Color.LumenFocus.textTertiary)
            Text("还没有护眼记录")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.LumenFocus.textSecondary)
            Text("完成第一次休息后，这里会出现你的趋势图和热力图。")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundColor(Color.LumenFocus.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var weekChartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("近 7 日")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.LumenFocus.textSecondary)

            Chart(weeklyStats, id: \.date) { stats in
                BarMark(
                    x: .value("日", shortWeekday(stats.date)),
                    y: .value("次数", stats.restCount)
                )
                .foregroundStyle(Color.LumenFocus.ink)
                .cornerRadius(3)
            }
            .frame(height: 140)
        }
    }

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("近 90 日热力图")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.LumenFocus.textSecondary)
                Spacer()
                Text("浅 → 深 = 0 → 最多")
                    .font(.system(size: 11))
                    .foregroundColor(Color.LumenFocus.textTertiary)
            }

            HeatmapGrid(stats: ninetyDay, max: maxRestCountInWindow)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers

    private func shortWeekday(_ dateKey: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateKey) else { return "" }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return symbols[(weekday - 1 + 7) % symbols.count]
    }

    private func refresh() {
        weeklyStats = StatisticsManager.shared.getWeeklyStatistics()
        ninetyDay = StatisticsManager.shared.getRecentStatistics(days: 90)
        currentStreak = StatisticsManager.shared.getCurrentStreak()
        longestStreak = StatisticsManager.shared.getLongestStreak()
        maxRestCountInWindow = max(1, ninetyDay.map(\.restCount).max() ?? 1)
    }

    // MARK: - CSV export

    private func exportCSV() {
        let panel = NSSavePanel()
        let dateLabel = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withYear, .withMonth, .withDay, .withDashSeparatorInDate])
        panel.nameFieldStringValue = "lumenfocus-stats-\(dateLabel).csv"
        if let csv = UTType(filenameExtension: "csv") {
            panel.allowedContentTypes = [csv]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let all = StatisticsManager.shared.getAllStatistics()
        var rows = ["date,rest_count,work_seconds,work_formatted"]
        for s in all {
            let formatted = formattedDuration(s.workDuration)
            rows.append("\(s.date),\(s.restCount),\(s.workDuration),\(formatted)")
        }
        let csv = rows.joined(separator: "\n") + "\n"
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            Log.stats.info("Exported CSV (\(all.count) rows) to \(url.path, privacy: .public)")
        } catch {
            Log.stats.error("CSV export failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h\(m)m" : "\(m)m"
    }
}

// MARK: - Stat card

private struct StatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: L(label))
                .font(.system(size: 11))
                .foregroundColor(Color.LumenFocus.textSecondary)
            Text(verbatim: value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.LumenFocus.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.LumenFocus.backgroundSecondary)
        .cornerRadius(8)
    }
}

// MARK: - Heatmap

private struct HeatmapGrid: View {
    let stats: [DailyStatistics]
    let max: Int

    private let cellSize: CGFloat = 14
    private let spacing: CGFloat = 3

    var body: some View {
        // 把 90 天数据切成 7×N 网格：行是周日~周六，列是周
        let grouped = groupByWeek(stats)
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<7, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(grouped.indices, id: \.self) { col in
                        let week = grouped[col]
                        let stats = row < week.count ? week[row] : nil
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colorFor(stats))
                            .frame(width: cellSize, height: cellSize)
                            .help(tooltip(for: stats))
                    }
                }
            }
        }
    }

    /// 按周分组（每个内层数组是周日~周六 7 天，靠 weekday 对齐）
    private func groupByWeek(_ stats: [DailyStatistics]) -> [[DailyStatistics?]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current

        // 把 stats 按 date 解析成 (Date, DailyStatistics) 列表
        let dated: [(Date, DailyStatistics)] = stats.compactMap { s in
            guard let d = formatter.date(from: s.date) else { return nil }
            return (d, s)
        }
        guard let first = dated.first?.0 else { return [] }

        // 找到第一周的起点（周日）
        let firstWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: first))!
        let last = dated.last?.0 ?? Date()
        let lastWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: last))!
        let totalWeeks = (calendar.dateComponents([.weekOfYear], from: firstWeekStart, to: lastWeekStart).weekOfYear ?? 0) + 1

        var statsByKey: [String: DailyStatistics] = [:]
        for s in stats { statsByKey[s.date] = s }

        var weeks: [[DailyStatistics?]] = []
        for w in 0..<totalWeeks {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: w, to: firstWeekStart) else { continue }
            var week: [DailyStatistics?] = []
            for d in 0..<7 {
                if let day = calendar.date(byAdding: .day, value: d, to: weekStart) {
                    let key = formatter.string(from: day)
                    week.append(statsByKey[key])
                } else {
                    week.append(nil)
                }
            }
            weeks.append(week)
        }
        return weeks
    }

    private func colorFor(_ stats: DailyStatistics?) -> Color {
        // Use an opacity ramp over the dynamic "ink" so the heatmap reads in
        // both Light and Dark Mode (light = faint ink, busy = solid ink).
        let ink = Color.LumenFocus.ink
        guard let s = stats else { return ink.opacity(0.06) }
        if s.restCount == 0 { return ink.opacity(0.12) }
        let ratio = Double(s.restCount) / Double(max)
        switch ratio {
        case 0..<0.25:   return ink.opacity(0.35)
        case 0.25..<0.5: return ink.opacity(0.55)
        case 0.5..<0.75: return ink.opacity(0.78)
        default:         return ink
        }
    }

    private func tooltip(for stats: DailyStatistics?) -> String {
        guard let s = stats else { return "" }
        return String(format: L("%@ · %d 次"), s.date, s.restCount)
    }
}

// MARK: - ISO8601 helper

private extension ISO8601DateFormatter {
    static func string(from date: Date, timeZone: TimeZone, formatOptions: Options) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = formatOptions
        return formatter.string(from: date)
    }
}
