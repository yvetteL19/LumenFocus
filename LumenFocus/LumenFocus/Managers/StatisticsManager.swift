import Foundation

/// Recorded timer activity, not a measurement of screen exposure or eye health.
struct DailyStatistics: Codable, Equatable {
    var date: String
    var restCount: Int
    var workDuration: Int

    init(date: String, restCount: Int = 0, workDuration: Int = 0) {
        self.date = date
        self.restCount = restCount
        self.workDuration = workDuration
    }
}

/// The sole statistics repository. Call from the app's main thread.
/// Work intervals must be nonoverlapping; completed rest session IDs are idempotent.
final class StatisticsManager {
    static let shared = StatisticsManager()
    static let didChangeNotification = Notification.Name("LumenFocus.statisticsDidChange")

    private struct Store: Codable {
        var records: [DailyStatistics]
        var fractionalWorkSeconds: [String: Double]
        var completedRestIDs: [String: String]
    }

    private enum Keys {
        static let store = "statisticsStoreV2"
        static let migrationVersion = "statisticsMigrationVersion"
        static let legacyStatistics = "dailyStatisticsData"
        static let legacyMigration = "hasMigratedToStatisticsManager"
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let retentionDays: Int
    private let formatter: DateFormatter
    private var records: [String: DailyStatistics] = [:]
    private var fractionalWorkSeconds: [String: Double] = [:]
    private var completedRestIDs: [String: String] = [:]
    private var currentDayKey: String
    private var lastFlushAt: Date
    private var isDirty = false
    private var pendingLegacyKeys: [String] = []

    /// Inject a separate defaults suite and clock in tests; initialization never touches the shared singleton.
    init(defaults: UserDefaults = .standard, calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init, retentionDays: Int = 90) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.retentionDays = max(1, retentionDays)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        self.formatter = formatter
        let initialDate = now()
        self.currentDayKey = formatter.string(from: initialDate)
        self.lastFlushAt = initialDate

        let savedData = defaults.data(forKey: Keys.store)
        if let data = savedData,
           let store = try? JSONDecoder().decode(Store.self, from: data) {
            for record in store.records { merge(record) }
            fractionalWorkSeconds = store.fractionalWorkSeconds.filter {
                records[$0.key] != nil && $0.value.isFinite && (0..<1).contains($0.value)
            }
            completedRestIDs = store.completedRestIDs.filter {
                UUID(uuidString: $0.key) != nil && parseDate($0.value) != nil
            }
        } else {
            // Preserve the original bytes before recovering from legacy records.
            // Unique keys also preserve earlier recovery attempts for manual inspection.
            if let savedData {
                defaults.set(savedData, forKey: "statisticsStoreV2.recovery.\(UUID().uuidString)")
            }
            migrateLegacyData()
        }
        pruneHistory(at: initialDate)
        flush()
    }

    /// Split elapsed work at local midnight, retaining subsecond remainders per day.
    func recordWork(from start: Date, to end: Date) {
        guard start.timeIntervalSinceReferenceDate.isFinite,
              end.timeIntervalSinceReferenceDate.isFinite, end > start else { return }
        let referenceDate = now()
        refreshDay(at: referenceDate)
        guard let cutoff = retentionCutoff(at: referenceDate),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)) else { return }
        var cursor = max(start, cutoff)
        let boundedEnd = min(end, tomorrow)
        while cursor < boundedEnd {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart), nextDay > cursor else { break }
            let segmentEnd = min(boundedEnd, nextDay)
            let key = formatter.string(from: cursor)
            let accumulated = (fractionalWorkSeconds[key] ?? 0) + segmentEnd.timeIntervalSince(cursor)
            let wholeSeconds = Int(accumulated.rounded(.down))
            fractionalWorkSeconds[key] = accumulated - Double(wholeSeconds)
            var record = records[key] ?? DailyStatistics(date: key)
            record.workDuration += wholeSeconds
            records[key] = record
            isDirty = true
            cursor = segmentEnd
        }
        if referenceDate.timeIntervalSince(lastFlushAt) >= 60 || referenceDate < lastFlushAt {
            flush()
        }
    }

    /// A completion is counted once per UUID, including after relaunch, within retained history.
    func recordCompletedRest(at date: Date, id: UUID) {
        let referenceDate = now()
        refreshDay(at: referenceDate)
        guard isRetained(date, relativeTo: referenceDate), completedRestIDs[id.uuidString] == nil else { return }
        let key = formatter.string(from: date)
        var record = records[key] ?? DailyStatistics(date: key)
        record.restCount += 1
        records[key] = record
        completedRestIDs[id.uuidString] = key
        isDirty = true
        // A completed session is a meaningful event worth persisting immediately.
        flush()
    }

    /// Persist a single snapshot only when changed. Call at pause, sleep and app termination.
    func flush() {
        let referenceDate = now()
        pruneHistory(at: referenceDate)
        guard isDirty else { return }
        let store = Store(records: sortedRecords(), fractionalWorkSeconds: fractionalWorkSeconds,
                          completedRestIDs: completedRestIDs)
        guard let data = try? JSONEncoder().encode(store) else { return }
        defaults.set(data, forKey: Keys.store)
        defaults.set(2, forKey: Keys.migrationVersion)
        // Remove old stores only after the new complete snapshot has been written.
        for key in pendingLegacyKeys { defaults.removeObject(forKey: key) }
        pendingLegacyKeys.removeAll()
        lastFlushAt = referenceDate
        isDirty = false
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Refresh the date boundary and enforce retention without manufacturing a persisted zero day.
    @discardableResult
    func refreshToday() -> DailyStatistics {
        refreshDay(at: now())
        return records[currentDayKey] ?? DailyStatistics(date: currentDayKey)
    }

    func getTodayStatistics() -> DailyStatistics { refreshToday() }

    /// Only dates with recorded activity are returned. Missing dates are not measured zeroes.
    func getWeeklyStatistics() -> [DailyStatistics] { getRecentStatistics(days: 7) }
    func getWeeklyRestCount() -> Int { getWeeklyStatistics().reduce(0) { $0 + $1.restCount } }
    func getWeeklyWorkDuration() -> Int { getWeeklyStatistics().reduce(0) { $0 + $1.workDuration } }
    func getWeeklyWorkDurationFormatted() -> String { formatWorkDuration(getWeeklyWorkDuration()) }

    /// Average across recorded days, including working days with zero completed breaks.
    func getDailyAverageRestCount() -> Int {
        let weekly = getWeeklyStatistics()
        guard !weekly.isEmpty else { return 0 }
        return weekly.reduce(0) { $0 + $1.restCount } / weekly.count
    }

    func getRecentStatistics(days: Int) -> [DailyStatistics] {
        guard days > 0 else { return [] }
        let referenceDate = now()
        refreshDay(at: referenceDate)
        let span = min(days, retentionDays)
        guard let cutoff = calendar.date(byAdding: .day, value: -(span - 1),
                                         to: calendar.startOfDay(for: referenceDate)) else { return [] }
        let cutoffKey = formatter.string(from: cutoff)
        return sortedRecords().filter { $0.date >= cutoffKey && $0.date <= currentDayKey }
    }

    func getAllStatistics() -> [DailyStatistics] {
        refreshDay(at: now())
        return sortedRecords()
    }

    /// Compatibility queries: a day with any completed break, not a medical target.
    var dailyStreakThreshold: Int { 1 }

    func getCurrentStreak() -> Int {
        let referenceDate = now()
        refreshDay(at: referenceDate)
        var date = calendar.startOfDay(for: referenceDate)
        if (records[formatter.string(from: date)]?.restCount ?? 0) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return 0 }
            date = yesterday
        }
        var count = 0
        while count < retentionDays, (records[formatter.string(from: date)]?.restCount ?? 0) > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return count
    }

    func getLongestStreak() -> Int {
        let dates = getAllStatistics().filter { $0.restCount > 0 }.compactMap { parseDate($0.date) }
        var longest = 0
        var current = 0
        var previous: Date?
        for date in dates {
            if let previous, calendar.dateComponents([.day], from: previous, to: date).day == 1 {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previous = date
        }
        return longest
    }

    func cleanupOldData() {
        pruneHistory(at: now())
        flush()
    }

    private func refreshDay(at date: Date) {
        let key = formatter.string(from: date)
        guard key != currentDayKey else { return }
        currentDayKey = key
        pruneHistory(at: date)
        flush()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func retentionCutoff(at date: Date) -> Date? {
        calendar.date(byAdding: .day, value: -(retentionDays - 1), to: calendar.startOfDay(for: date))
    }

    private func isRetained(_ date: Date, relativeTo referenceDate: Date) -> Bool {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              let cutoff = retentionCutoff(at: referenceDate) else { return false }
        let day = calendar.startOfDay(for: date)
        return day >= cutoff && day <= calendar.startOfDay(for: referenceDate)
    }

    private func pruneHistory(at date: Date) {
        guard let cutoff = retentionCutoff(at: date) else { return }
        let kept = records.filter { entry in
            guard let recordedDate = parseDate(entry.key) else { return false }
            // A clock adjustment must not erase previously recorded future-dated days.
            return recordedDate >= cutoff
        }
        let keptIDs = completedRestIDs.filter { entry in
            guard let recordedDate = parseDate(entry.value) else { return false }
            return recordedDate >= cutoff
        }
        if kept.count != records.count || keptIDs.count != completedRestIDs.count { isDirty = true }
        records = kept
        completedRestIDs = keptIDs
        fractionalWorkSeconds = fractionalWorkSeconds.filter { records[$0.key] != nil }
    }

    private func sortedRecords() -> [DailyStatistics] { records.values.sorted { $0.date < $1.date } }

    private func parseDate(_ key: String) -> Date? {
        guard key.count == 10, let date = formatter.date(from: key), formatter.string(from: date) == key else { return nil }
        return date
    }

    /// Legacy stores overlap. A per-field maximum preserves data without double-counting it.
    private func merge(_ record: DailyStatistics) {
        guard parseDate(record.date) != nil else { return }
        let previous = records[record.date] ?? DailyStatistics(date: record.date)
        records[record.date] = DailyStatistics(date: record.date,
            restCount: max(previous.restCount, max(0, record.restCount)),
            workDuration: max(previous.workDuration, max(0, record.workDuration)))
    }

    private func migrateLegacyData() {
        if let data = defaults.data(forKey: Keys.legacyStatistics) {
            if let oldRecords = try? JSONDecoder().decode([DailyStatistics].self, from: data) {
                for record in oldRecords where record.restCount > 0 || record.workDuration > 0 { merge(record) }
            } else {
                defaults.set(data, forKey: "statisticsLegacy.recovery.\(UUID().uuidString)")
            }
        }
        pendingLegacyKeys = [Keys.legacyStatistics, Keys.legacyMigration]
        for (key, _) in defaults.dictionaryRepresentation() {
            let prefix: String
            if key.hasPrefix("restCount_") { prefix = "restCount_" }
            else if key.hasPrefix("workDuration_") { prefix = "workDuration_" }
            else { continue }
            pendingLegacyKeys.append(key)
            let day = String(key.dropFirst(prefix.count))
            guard parseDate(day) != nil else { continue }
            let value = max(0, defaults.integer(forKey: key))
            guard value > 0 else { continue }
            merge(DailyStatistics(date: day, restCount: prefix == "restCount_" ? value : 0,
                                  workDuration: prefix == "workDuration_" ? value : 0))
        }
        isDirty = true
    }
}
