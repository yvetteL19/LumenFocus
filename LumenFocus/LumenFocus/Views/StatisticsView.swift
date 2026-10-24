import SwiftUI
import Charts
import UniformTypeIdentifiers

struct StatisticsView: View {
    @State private var selectedRange: StatisticsRange = .sevenDays
    @State private var presentation = StatisticsPresentation(records: [])
    @State private var exportError: String?
    @State private var showsDailyDetails = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                if presentation.hasRecords {
                    Section {
                        summary
                            .listRowSeparator(.hidden)
                    }
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

                if presentation.hasRecords {
                    Section {
                        DisclosureGroup("每日明细", isExpanded: $showsDailyDetails) {
                            dailyColumnLabels
                            ForEach(Array(presentation.days.reversed())) { day in
                                dailyRow(day)
                            }
                        }
                    }
                }
                Section {
                    DisclosureGroup("关于这些记录") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("仅统计计时工作与完成的休息，不代表健康改善。")
                            Text("提前结束的休息不计入完成次数。无记录不代表当天没有工作。")
                            Text("记录保存在这台 Mac，保留 90 天；可导出保存更久。")
                        }
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8)
                    }
                }
            }
            .listStyle(.inset)
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.LumenFocus.backgroundPrimary)
        .onAppear { refresh() }
        .onChange(of: selectedRange) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: StatisticsManager.didChangeNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in refresh() }
        .alert("导出失败", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("好", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("休息记录")
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Button(action: exportCSV) {
                    Label("导出 CSV", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(!presentation.hasRecords)
                .help(L("导出当前范围内有记录的日期，不补齐无记录日期。"))
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    rangePicker.fixedSize()
                    Spacer(minLength: 0)
                    Text(verbatim: dateRangeLabel)
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: 10) {
                    rangePicker
                    Text(verbatim: dateRangeLabel)
                }
            }
            .font(.system(size: 12))
            .foregroundColor(Color.LumenFocus.textSecondary)
        }
        .foregroundColor(Color.LumenFocus.textPrimary)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var rangePicker: some View {
        Picker("统计范围", selection: $selectedRange) {
            ForEach(StatisticsRange.allCases) { range in
                Text(verbatim: L(range.titleKey)).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var summary: some View {
        HStack(spacing: 12) {
            StatCard(label: "完成休息", value: localizedCompletedBreaks(presentation.completedRestCount))
            StatCard(label: "计时工作", value: formatWorkDuration(presentation.timedWorkSeconds))
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
            Text("LumenFocus 会自动记录工作计时，完整休息也会显示在这里。")
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
                            .accessibilityValue(Text(verbatim: localizedCompletedBreaks(record.restCount)))
                    } else {
                        PointMark(x: .value(L("日"), day.date, unit: .day),
                                  y: .value(L("完成休息"), 0))
                            .symbol {
                                Circle()
                                    .strokeBorder(Color.LumenFocus.ink, lineWidth: 1.5)
                                    .frame(width: 6, height: 6)
                            }
                            .accessibilityLabel(Text(dayLabel(day)))
                            .accessibilityValue(Text(verbatim: localizedCompletedBreaks(0)))
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
                    AxisValueLabel(format: Date.FormatStyle(locale: AppLocalization.locale, calendar: presentation.calendar,
                                                           timeZone: presentation.calendar.timeZone)
                        .month(.defaultDigits).day())
                }
            }
            .chartYAxis {
                AxisMarks(values: presentation.chartTickCounts)
            }
            .frame(height: 155)
            .environment(\.calendar, presentation.calendar)
            .environment(\.timeZone, presentation.calendar.timeZone)
            .accessibilityLabel(Text("每日完成休息"))
            Text("○ 已记录为 0 · — 无记录")
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
            Text(verbatim: day.record.map { localizedCompletedBreaks($0.restCount) } ?? L("无记录"))
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
        formatter.locale = AppLocalization.locale
        formatter.calendar = presentation.calendar
        formatter.timeZone = presentation.calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: presentation.startDate, to: presentation.endDate)
    }

    private func dayLabel(_ day: StatisticsPresentation.Day) -> String {
        day.date.formatted(Date.FormatStyle(locale: AppLocalization.locale, calendar: presentation.calendar,
                                           timeZone: presentation.calendar.timeZone)
            .year().month(.abbreviated).day().weekday(.abbreviated))
    }

    private func rowAccessibilityLabel(_ day: StatisticsPresentation.Day) -> String {
        guard let record = day.record else {
            return String(format: L("%@，无记录"), dayLabel(day))
        }
        return localizedRecordAccessibility(dayLabel: dayLabel(day), count: record.restCount,
                                            workDuration: formatWorkDuration(record.workDuration))
    }

    private func refresh() {
        presentation = StatisticsPresentation(snapshot: StatisticsManager.shared.getSnapshot(), range: selectedRange)
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
        case .working:
            Button("休息一下") { TimerManager.shared.triggerManualRest() }
                .buttonStyle(.bordered)
        case .triggeringRest, .resting:
            Button("休息进行中") {}
                .buttonStyle(.bordered)
                .disabled(true)
        case .stopped, .paused, .autoSuspended:
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
