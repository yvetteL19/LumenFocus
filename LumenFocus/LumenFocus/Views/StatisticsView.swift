import SwiftUI
import Charts
import UniformTypeIdentifiers

struct StatisticsView: View {
    @State private var selectedRange: StatisticsRange = .sevenDays
    @State private var presentation = StatisticsPresentation(records: [])
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                Section {
                    summary
                        .listRowSeparator(.hidden)
                } header: {
                    Text("区间摘要")
                }

                Section {
                    if presentation.hasActivity {
                        chart
                            .listRowSeparator(.hidden)
                    } else {
                        emptyState
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("每日完成休息")
                }

                Section {
                    dailyColumnLabels
                    ForEach(Array(presentation.days.reversed())) { day in
                        dailyRow(day)
                    }
                } header: {
                    Text("每日明细")
                }
            }
            .listStyle(.inset)
            .padding(.horizontal, 12)
            Divider()
            Text("本地保存最近 90 天统计 · 导出文件由你管理")
                .font(.system(size: 11))
                .foregroundColor(Color.LumenFocus.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.LumenFocus.backgroundPrimary)
        .onAppear { refresh() }
        .onChange(of: selectedRange) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: StatisticsManager.didChangeNotification)) { _ in refresh() }
        .alert("导出失败", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("好", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("统计")
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Button(action: exportCSV) {
                    Label("导出 CSV", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(!presentation.hasRecords)
                .help(L("导出当前范围内有记录的日期，不补齐无记录日期。"))
            }
            Text("仅统计计时工作与完成的休息，不代表健康改善。")
                .font(.system(size: 12))
                .foregroundColor(Color.LumenFocus.textSecondary)
            HStack(spacing: 16) {
                Picker("统计范围", selection: $selectedRange) {
                    ForEach(StatisticsRange.allCases) { range in
                        Text(verbatim: L(range.titleKey)).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 290)
                Spacer(minLength: 0)
                Text(verbatim: dateRangeLabel)
                    .font(.system(size: 12))
                    .foregroundColor(Color.LumenFocus.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .foregroundColor(Color.LumenFocus.textPrimary)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                StatCard(label: "完成休息", value: presentation.hasRecords
                    ? String(format: L("%d 次"), presentation.completedRestCount) : L("无记录"))
                StatCard(label: "计时工作", value: presentation.hasRecords
                    ? formatWorkDuration(presentation.timedWorkSeconds) : L("无记录"))
                StatCard(label: "有活动的天数", value: String(format: L("%d / %d 天"),
                                                           presentation.activeDayCount, selectedRange.rawValue))
            }
            Text("有计时工作或完成休息的日期计为活动日。无记录不代表当天没有工作。")
                .font(.system(size: 11))
                .foregroundColor(Color.LumenFocus.textSecondary)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(Color.LumenFocus.textSecondary)
                .accessibilityHidden(true)
            Text("这段时间还没有活动记录")
                .font(.system(size: 15, weight: .medium))
            Text("开始计时或完成一次休息后，这里会显示你的记录。")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundColor(Color.LumenFocus.textSecondary)
            StatisticsRestAction()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart(presentation.days) { day in
                if let record = day.record {
                    if record.restCount > 0 {
                        BarMark(x: .value(L("日"), day.date, unit: .day),
                                y: .value(L("完成休息"), record.restCount))
                            .foregroundStyle(Color.LumenFocus.ink)
                            .cornerRadius(2)
                            .accessibilityLabel(Text(dayLabel(day)))
                            .accessibilityValue(Text(String(format: L("%d 次"), record.restCount)))
                    } else {
                        PointMark(x: .value(L("日"), day.date, unit: .day),
                                  y: .value(L("完成休息"), 0))
                            .symbol {
                                Circle()
                                    .strokeBorder(Color.LumenFocus.ink, lineWidth: 1.5)
                                    .frame(width: 6, height: 6)
                            }
                            .accessibilityLabel(Text(dayLabel(day)))
                            .accessibilityValue(Text(String(format: L("%d 次"), 0)))
                    }
                } else {
                    PointMark(x: .value(L("日"), day.date, unit: .day),
                              y: .value(L("完成休息"), 0))
                        .symbol {
                            Rectangle()
                                .fill(Color.LumenFocus.textSecondary)
                                .frame(width: 5, height: 1)
                        }
                        .accessibilityLabel(Text(dayLabel(day)))
                        .accessibilityValue(Text("无记录"))
                }
            }
            .chartXScale(domain: presentation.startDate...presentation.endDateExclusive)
            .chartYScale(domain: 0...(presentation.chartTickCounts.last ?? 1),
                         range: .plotDimension(startPadding: 6, endPadding: 6))
            .chartXAxis {
                AxisMarks(values: presentation.chartTickDates) { _ in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                }
            }
            .chartYAxis {
                AxisMarks(values: presentation.chartTickCounts)
            }
            .frame(height: 155)
            .accessibilityLabel(Text("每日完成休息"))
            Text("○ 已记录为 0 · — 无记录。逐日数据见下方明细。")
                .font(.system(size: 11))
                .foregroundColor(Color.LumenFocus.textSecondary)
        }
        .padding(.vertical, 8)
    }

    private var dailyColumnLabels: some View {
        HStack(spacing: 16) {
            Text("日期").frame(maxWidth: .infinity, alignment: .leading)
            Text("完成休息").frame(width: 110, alignment: .trailing)
            Text("计时工作").frame(width: 150, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(Color.LumenFocus.textSecondary)
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }

    private func dailyRow(_ day: StatisticsPresentation.Day) -> some View {
        HStack(spacing: 16) {
            Text(verbatim: dayLabel(day))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: day.record.map { String(format: L("%d 次"), $0.restCount) } ?? L("无记录"))
                .frame(width: 110, alignment: .trailing)
            Text(verbatim: day.record.map { formatWorkDuration($0.workDuration) } ?? "—")
                .frame(width: 150, alignment: .trailing)
        }
        .font(.system(size: 12))
        .monospacedDigit()
        .foregroundColor(day.record == nil ? Color.LumenFocus.textSecondary : Color.LumenFocus.textPrimary)
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(rowAccessibilityLabel(day)))
    }

    private var dateRangeLabel: String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: presentation.startDate, to: presentation.endDate)
    }

    private func dayLabel(_ day: StatisticsPresentation.Day) -> String {
        day.date.formatted(.dateTime.year().month(.abbreviated).day().weekday(.abbreviated))
    }

    private func rowAccessibilityLabel(_ day: StatisticsPresentation.Day) -> String {
        guard let record = day.record else {
            return String(format: L("%@，无记录"), dayLabel(day))
        }
        return String(format: L("%@，完成休息 %d 次，计时工作 %@"),
                      dayLabel(day), record.restCount, formatWorkDuration(record.workDuration))
    }

    private func refresh() {
        presentation = StatisticsPresentation(records: StatisticsManager.shared.getAllStatistics(), range: selectedRange)
    }

    private func exportCSV() {
        // Capture exactly what is visible before the modal panel runs its event loop.
        let export = presentation
        guard export.hasRecords else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = export.csvFilename
        panel.message = L("导出当前范围内有记录的日期，不补齐无记录日期。")
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try export.csvContents.write(to: url, atomically: true, encoding: .utf8)
            Log.stats.info("Exported statistics CSV (\(export.exportRecords.count) recorded days)")
        } catch {
            exportError = error.localizedDescription
            Log.stats.error("CSV export failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Observe the live timer only for this action, not the whole history list.
private struct StatisticsRestAction: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        switch appState.currentPhase {
        case .working, .reminderDue:
            Button("现在休息") { TimerManager.shared.triggerManualRest() }
                .buttonStyle(.bordered)
        case .triggeringRest, .resting:
            Button("休息进行中") {}
                .buttonStyle(.bordered)
                .disabled(true)
        case .paused, .autoSuspended:
            EmptyView()
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
                .monospacedDigit()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.LumenFocus.backgroundSecondary)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
    }
}
