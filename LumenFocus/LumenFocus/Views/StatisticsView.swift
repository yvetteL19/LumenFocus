import SwiftUI
import Charts
import UniformTypeIdentifiers

struct StatisticsView: View {
    @State private var weeklyStats: [DailyStatistics] = []
    @State private var ninetyDay: [DailyStatistics] = []
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("统计")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color.LumenFocus.textPrimary)
                Text("仅统计计时工作与完成的休息，不代表健康改善。")
                    .font(.system(size: 12))
                    .foregroundColor(Color.LumenFocus.textSecondary)

                Text("近 7 天")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.LumenFocus.textSecondary)
                HStack(spacing: 12) {
                    StatCard(label: "完成休息", value: String(format: L("%d 次"), weeklyStats.reduce(0) { $0 + $1.restCount }))
                    StatCard(label: "计时工作", value: formatWorkDuration(weeklyStats.reduce(0) { $0 + $1.workDuration }))
                    StatCard(label: "记录天数", value: String(weeklyStats.count))
                }

                if ninetyDay.isEmpty {
                    emptyState
                } else {
                    weekChartSection
                    heatmapSection
                }

                HStack {
                    Text("本地保存最近 90 天统计 · 导出文件由你管理")
                        .font(.system(size: 11))
                        .foregroundColor(Color.LumenFocus.textSecondary)
                    Spacer()
                    Button("导出 CSV") { exportCSV() }
                        .buttonStyle(.bordered)
                        .disabled(ninetyDay.isEmpty)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.LumenFocus.backgroundPrimary)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: StatisticsManager.didChangeNotification)) { _ in refresh() }
        .alert("导出失败", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("好", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(Color.LumenFocus.textTertiary)
            Text("还没有活动记录")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.LumenFocus.textSecondary)
            Text("开始计时或完成一次休息后，这里会显示你的记录。")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundColor(Color.LumenFocus.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var weekChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if weeklyStats.isEmpty {
                Text("无记录")
                    .foregroundColor(Color.LumenFocus.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(weeklyStats, id: \.date) { stats in
                    if let date = StatisticsDates.parse(stats.date) {
                        BarMark(x: .value(L("日"), date, unit: .day),
                                y: .value(L("完成休息"), stats.restCount))
                            .foregroundStyle(Color.LumenFocus.ink)
                            .cornerRadius(3)
                            .accessibilityLabel(Text(stats.date))
                            .accessibilityValue(Text(String(format: L("%d 次"), stats.restCount)))
                    }
                }
                .chartXScale(domain: weekDomain)
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                } }
                .frame(height: 140)
            }
        }
    }

    private var weekDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return start...end
    }

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("近 90 天记录")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.LumenFocus.textSecondary)
            HeatmapGrid(stats: ninetyDay)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("浅 → 深 = 完成休息由少到多")
                .font(.system(size: 11))
                .foregroundColor(Color.LumenFocus.textSecondary)
        }
    }

    private func refresh() {
        weeklyStats = StatisticsManager.shared.getWeeklyStatistics()
        ninetyDay = StatisticsManager.shared.getRecentStatistics(days: 90)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "lumenfocus-stats-\(StatisticsDates.key(Date())).csv"
        if let csv = UTType(filenameExtension: "csv") { panel.allowedContentTypes = [csv] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let all = StatisticsManager.shared.getAllStatistics()
        let rows = ["date,completed_rest_count,timed_work_seconds"] + all.map {
            "\($0.date),\($0.restCount),\($0.workDuration)"
        }
        do {
            try (rows.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            Log.stats.info("Exported statistics CSV (\(all.count) recorded days)")
        } catch {
            exportError = error.localizedDescription
            Log.stats.error("CSV export failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

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

private struct HeatmapGrid: View {
    let stats: [DailyStatistics]

    private struct Day {
        let key: String
        let record: DailyStatistics?
    }

    var body: some View {
        let cells = calendarCells()
        let columns = (cells.count + 6) / 7
        VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<7, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = column * 7 + row
                        let day = index < cells.count ? cells[index] : nil
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color(for: day))
                            .frame(width: 14, height: 14)
                            .help(tooltip(for: day))
                            .accessibilityLabel(Text(tooltip(for: day)))
                            .accessibilityHidden(day == nil)
                    }
                }
            }
        }
    }

    /// Calendar placeholders remain nil records, including days before first use.
    private func calendarCells() -> [Day?] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let first = calendar.date(byAdding: .day, value: -89, to: today) else { return [] }
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let byDay = Dictionary(stats.map { ($0.date, $0) }, uniquingKeysWith: { _, newer in newer })
        var cells: [Day?] = Array(repeating: nil, count: leading)
        for offset in 0..<90 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            let key = StatisticsDates.key(date)
            cells.append(Day(key: key, record: byDay[key]))
        }
        return cells
    }

    private func color(for day: Day?) -> Color {
        guard let day else { return .clear }
        let ink = Color.LumenFocus.ink
        guard let record = day.record else { return ink.opacity(0.05) }
        guard record.restCount > 0 else { return ink.opacity(0.15) }
        let largest = max(1, stats.map(\.restCount).max() ?? 1)
        return ink.opacity(0.3 + 0.7 * Double(record.restCount) / Double(largest))
    }

    private func tooltip(for day: Day?) -> String {
        guard let day else { return "" }
        guard let record = day.record else { return "\(day.key) · \(L("无记录"))" }
        return String(format: L("%@ · %d 次"), day.key, record.restCount)
    }
}

private enum StatisticsDates {
    static func key(_ date: Date) -> String { formatter().string(from: date) }
    static func parse(_ key: String) -> Date? { formatter().date(from: key) }

    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar.current
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
