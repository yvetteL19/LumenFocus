import Foundation

enum StatisticsRange: Int, CaseIterable, Identifiable {
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .sevenDays: return "近 7 天"
        case .thirtyDays: return "近 30 天"
        case .ninetyDays: return "近 90 天"
        }
    }
}

/// One calendar range shared by the summary, chart, daily rows and CSV export.
/// Missing dates remain nil; an existing zero-valued record is still a record.
struct StatisticsPresentation {
    struct Day: Identifiable, Equatable {
        let id: String
        let date: Date
        let record: DailyStatistics?

        var hasActivity: Bool {
            guard let record else { return false }
            return record.restCount > 0 || record.workDuration > 0
        }
    }

    let range: StatisticsRange
    /// Freeze labels and chart bucketing to the same calendar as the repository snapshot.
    let calendar: Calendar
    /// Oldest first, including placeholders for dates without a stored record.
    let days: [Day]
    let startDate: Date
    let endDate: Date
    let endDateExclusive: Date

    init(snapshot: StatisticsManager.Snapshot, range: StatisticsRange = .sevenDays) {
        self.init(records: snapshot.records, range: range,
                  now: snapshot.referenceDate, calendar: snapshot.calendar)
    }

    init(records: [DailyStatistics], range: StatisticsRange = .sevenDays,
         now: Date = Date(), calendar: Calendar = .current) {
        self.range = range
        // Match the repository's Gregorian date-key convention even before the
        // first snapshot arrives, regardless of the system's display calendar.
        var storageCalendar = Calendar(identifier: .gregorian)
        storageCalendar.timeZone = calendar.timeZone
        self.calendar = storageCalendar
        let today = storageCalendar.startOfDay(for: now)
        let start = storageCalendar.date(byAdding: .day, value: -(range.rawValue - 1), to: today) ?? today
        startDate = start
        endDate = today
        endDateExclusive = storageCalendar.date(byAdding: .day, value: 1, to: today) ?? today

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = storageCalendar
        formatter.timeZone = storageCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        // The repository has unique keys. Keeping the last copy here also avoids
        // accidental double-counting if a caller supplies a repeated snapshot.
        let byDate = Dictionary(records.map { ($0.date, $0) }, uniquingKeysWith: { _, latest in latest })
        days = (0..<range.rawValue).compactMap { offset in
            guard let date = storageCalendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = formatter.string(from: date)
            return Day(id: key, date: date, record: byDate[key])
        }
    }

    var completedRestCount: Int { exportRecords.reduce(0) { $0 + $1.restCount } }
    var timedWorkSeconds: Int { exportRecords.reduce(0) { $0 + $1.workDuration } }
    var activeDayCount: Int { days.filter(\.hasActivity).count }
    var hasRecords: Bool { days.contains { $0.record != nil } }
    var hasActivity: Bool { days.contains(where: \.hasActivity) }

    /// Existing zero records are preserved. Calendar placeholders are never exported.
    var exportRecords: [DailyStatistics] { days.compactMap(\.record) }

    var csvFilename: String {
        "lumenfocus-stats-\(days.first?.id ?? "")-\(days.last?.id ?? "").csv"
    }

    var csvContents: String {
        let header = "date,completed_rest_count,timed_work_seconds"
        let rows = exportRecords.map { "\($0.date),\($0.restCount),\($0.workDuration)" }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    /// Keep labels evenly spaced, with both boundary dates visible.
    var chartTickDates: [Date] {
        guard days.count > 7 else { return days.map(\.date) }
        return (0...5).map { tick in
            let index = Int((Double(tick) * Double(days.count - 1) / 5).rounded())
            return days[index].date
        }
    }

    var chartTickCounts: [Int] {
        let highest = days.compactMap { $0.record?.restCount }.max() ?? 0
        let step = max(1, Int(ceil(Double(highest) / 4)))
        let upper = max(1, Int(ceil(Double(highest) / Double(step))))
        return (0...upper).map { $0 * step }
    }
}
