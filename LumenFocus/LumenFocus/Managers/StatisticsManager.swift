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

    struct Snapshot {
        let records: [DailyStatistics]
        let calendar: Calendar
        let referenceDate: Date
    }

    private struct CalendarContext {
        let effectiveFrom: Date
        let calendar: Calendar
        let formatter: DateFormatter

        init(effectiveFrom: Date, calendar: Calendar) {
            self.effectiveFrom = effectiveFrom
            // Unversioned yyyy-MM-dd keys use the existing Gregorian convention.
            // Never reinterpret them using a user's display-calendar preference,
            // including when a new repository instance is created after relaunch.
            var storageCalendar = Calendar(identifier: .gregorian)
            storageCalendar.timeZone = calendar.timeZone
            self.calendar = storageCalendar
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = storageCalendar
            formatter.timeZone = storageCalendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            self.formatter = formatter
        }
    }

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
    private let calendarProvider: () -> Calendar
    private var calendarContexts: [CalendarContext]
    private var lastCalendarObservationDate: Date
    private var calendar: Calendar { calendarContexts[calendarContexts.count - 1].calendar }
    private var formatter: DateFormatter { calendarContexts[calendarContexts.count - 1].formatter }
    private let now: () -> Date
    private let retentionDays: Int
    private var records: [String: DailyStatistics] = [:]
    private var fractionalWorkSeconds: [String: Double] = [:]
    private var completedRestIDs: [String: String] = [:]
    private var currentDayKey: String
    private var lastFlushAt: Date
    private var isDirty = false
    private var pendingLegacyKeys: [String] = []
    private var timeZoneObserver: NSObjectProtocol?

    /// Diagnostics for ensuring processed intervals do not retain an ever-growing timeline.
    var retainedCalendarContextCount: Int { calendarContexts.count }

    /// Calendar inputs supply time zones only; stored date keys always use Gregorian dates.
    /// An explicit calendar provides a fixed zone, while calendarProvider can change it in tests.
    /// Inject a separate defaults suite and clock; initialization never touches the shared singleton.
    init(defaults: UserDefaults = .standard, calendar: Calendar? = nil,
         calendarProvider: (() -> Calendar)? = nil,
         now: @escaping () -> Date = Date.init, retentionDays: Int = 90) {
        self.defaults = defaults
        // An explicit calendar's time zone remains fixed for existing callers and tests.
        // Production resolves the system time zone whenever the repository is used.
        // Keys have no calendar-identifier metadata: preserve the Gregorian convention
        // without guessing at or rewriting historical years.
        let provider = calendarProvider ?? { calendar ?? Calendar.current }
        self.calendarProvider = provider
        self.now = now
        self.retentionDays = max(1, retentionDays)
        let initialDate = now()
        let initialContext = CalendarContext(effectiveFrom: .distantPast, calendar: provider())
        self.calendarContexts = [initialContext]
        self.lastCalendarObservationDate = initialDate
        self.currentDayKey = initialContext.formatter.string(from: initialDate)
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
        timeZoneObserver = NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange,
                                                                  object: nil, queue: .main) { [weak self] _ in
            self?.refreshToday()
        }
    }

    deinit {
        if let timeZoneObserver { NotificationCenter.default.removeObserver(timeZoneObserver) }
    }

    /// Split at observed time-zone changes, then at each context's local midnight.
    /// Already recorded date labels are never moved to a different calendar day.
    func recordWork(from start: Date, to end: Date) {
        guard start.timeIntervalSinceReferenceDate.isFinite,
              end.timeIntervalSinceReferenceDate.isFinite, end > start else { return }
        let referenceDate = now()
        refreshDay(at: referenceDate)
        for (index, context) in calendarContexts.enumerated() {
            let nextBoundary = calendarContexts.indices.contains(index + 1)
                ? calendarContexts[index + 1].effectiveFrom : end
            let segmentStart = max(start, context.effectiveFrom)
            let segmentEnd = min(end, nextBoundary)
            guard segmentEnd > segmentStart else { continue }
            recordWork(from: segmentStart, to: segmentEnd, context: context, relativeTo: referenceDate)
        }
        discardCalendarContexts(through: end)
        if referenceDate.timeIntervalSince(lastFlushAt) >= 60 || referenceDate < lastFlushAt {
            flush()
        }
    }

    private func recordWork(from start: Date, to end: Date, context: CalendarContext, relativeTo referenceDate: Date) {
        let calendar = context.calendar
        guard let cutoff = calendar.date(byAdding: .day, value: -(retentionDays - 1),
                                         to: calendar.startOfDay(for: referenceDate)),
              let tomorrow = calendar.date(byAdding: .day, value: 1,
                                           to: calendar.startOfDay(for: referenceDate)) else { return }
        var cursor = max(start, cutoff)
        let boundedEnd = min(end, tomorrow)
        while cursor < boundedEnd {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart), nextDay > cursor else { break }
            let segmentEnd = min(boundedEnd, nextDay)
            let key = context.formatter.string(from: cursor)
            let accumulated = (fractionalWorkSeconds[key] ?? 0) + segmentEnd.timeIntervalSince(cursor)
            let wholeSeconds = Int(accumulated.rounded(.down))
            fractionalWorkSeconds[key] = accumulated - Double(wholeSeconds)
            var record = records[key] ?? DailyStatistics(date: key)
            record.workDuration += wholeSeconds
            records[key] = record
            isDirty = true
            cursor = segmentEnd
        }
    }

    /// A completion is counted once per UUID, including after relaunch, within retained history.
    func recordCompletedRest(at date: Date, id: UUID) {
        let referenceDate = now()
        refreshDay(at: referenceDate)
        guard isRetained(date, relativeTo: referenceDate), completedRestIDs[id.uuidString] == nil else { return }
        let context = calendarContexts.last { $0.effectiveFrom <= date } ?? calendarContexts[0]
        let key = context.formatter.string(from: date)
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
        refreshDay(at: referenceDate)
        pruneHistory(at: referenceDate)
        if persistSnapshot(at: referenceDate) {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    private func persistSnapshot(at referenceDate: Date) -> Bool {
        guard isDirty else { return false }
        let store = Store(records: sortedRecords(), fractionalWorkSeconds: fractionalWorkSeconds,
                          completedRestIDs: completedRestIDs)
        guard let data = try? JSONEncoder().encode(store) else { return false }
        defaults.set(data, forKey: Keys.store)
        defaults.set(2, forKey: Keys.migrationVersion)
        // Remove old stores only after the new complete snapshot has been written.
        for key in pendingLegacyKeys { defaults.removeObject(forKey: key) }
        pendingLegacyKeys.removeAll()
        lastFlushAt = referenceDate
        isDirty = false
        return true
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

    /// Read records and their current calendar boundary atomically for presentation.
    func getSnapshot() -> Snapshot {
        let referenceDate = now()
        refreshDay(at: referenceDate)
        return Snapshot(records: sortedRecords(), calendar: calendar, referenceDate: referenceDate)
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
        flush()
    }

    private func refreshDay(at date: Date) {
        // A wall-clock rollback starts a new attribution timeline. Persisted
        // historical labels, including future-dated labels, stay untouched.
        if date < lastCalendarObservationDate {
            calendarContexts = [CalendarContext(effectiveFrom: .distantPast, calendar: calendar)]
        }
        lastCalendarObservationDate = date
        var nextCalendar = calendar
        nextCalendar.timeZone = calendarProvider().timeZone
        let calendarChanged = nextCalendar != calendar
        if calendarChanged {
            // The notification/first observation is the explicit switch boundary.
            // Keep earlier contexts for a pending work interval spanning this time.
            calendarContexts.append(CalendarContext(effectiveFrom: date, calendar: nextCalendar))
        }
        let key = formatter.string(from: date)
        guard calendarChanged || key != currentDayKey else { return }
        currentDayKey = key
        pruneHistory(at: date)
        _ = persistSnapshot(at: date)
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
        // No accepted work interval can use a context before all calendars' retention
        // cutoffs. This also cleans up old transitions during long periods without work.
        let earliestCutoff = calendarContexts.compactMap { context in
            context.calendar.date(byAdding: .day, value: -(retentionDays - 1),
                                  to: context.calendar.startOfDay(for: date))
        }.min()
        if let earliestCutoff { discardCalendarContexts(through: earliestCutoff) }
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

    private func discardCalendarContexts(through boundary: Date) {
        guard let index = calendarContexts.lastIndex(where: { $0.effectiveFrom <= boundary }), index > 0 else { return }
        calendarContexts.removeFirst(index)
        // Work arrives chronologically from CycleEngine. Keep the context in force
        // at the watermark plus any later changes needed by pending intervals.
        let earliest = calendarContexts[0]
        calendarContexts[0] = CalendarContext(effectiveFrom: .distantPast, calendar: earliest.calendar)
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
