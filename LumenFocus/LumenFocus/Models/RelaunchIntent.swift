import Foundation

/// A short-lived handoff stored inside the application's own container. App Sandbox
/// ignores NSWorkspace.OpenConfiguration.arguments, so relaunch cannot use argv.
struct RelaunchIntent: Codable, Equatable {
    let token: UUID
    let previousPID: Int32
    let previousLaunchDate: Date
    let bundleIdentifier: String
    let createdAt: Date
    let expiresAt: Date

    func matchesPredecessor(bundleIdentifier: String?, launchDate: Date?) -> Bool {
        self.bundleIdentifier == bundleIdentifier && previousLaunchDate == launchDate
    }
}

final class RelaunchIntentStore {
    static let shared = RelaunchIntentStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "LumenFocus", isDirectory: true)
        .appendingPathComponent("Runtime", isDirectory: true))

    static let lifetime: TimeInterval = 30
    // LaunchServices does not promise subsecond precision for NSRunningApplication.launchDate.
    private static let launchDatePrecision: TimeInterval = 1
    private let directory: URL
    private let now: () -> Date
    private let fileManager: FileManager
    private var fileURL: URL { directory.appendingPathComponent("relaunch-intent.json") }

    init(directory: URL, now: @escaping () -> Date = Date.init, fileManager: FileManager = .default) {
        self.directory = directory
        self.now = now
        self.fileManager = fileManager
    }

    func prepare(previousPID: Int32, previousLaunchDate: Date, bundleIdentifier: String) throws -> RelaunchIntent {
        let date = now()
        guard previousPID > 0, !bundleIdentifier.isEmpty,
              previousLaunchDate <= date, date.timeIntervalSinceReferenceDate.isFinite else {
            throw CocoaError(.coderInvalidValue)
        }
        let intent = RelaunchIntent(token: UUID(), previousPID: previousPID,
                                    previousLaunchDate: previousLaunchDate, bundleIdentifier: bundleIdentifier,
                                    createdAt: date, expiresAt: date.addingTimeInterval(Self.lifetime))
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(intent).write(to: fileURL, options: .atomic)
        return intent
    }

    /// Only a process launched after the request may consume it. Renaming first
    /// makes consumption exclusive even if two copies launch at the same time.
    func consume(currentPID: Int32, currentLaunchDate: Date, bundleIdentifier: String) -> RelaunchIntent? {
        guard let pending = read(fileURL) else {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        guard isValid(pending, bundleIdentifier: bundleIdentifier) else {
            cancel(token: pending.token)
            return nil
        }
        guard currentPID > 0, pending.previousPID != currentPID,
              currentLaunchDate.timeIntervalSince(pending.createdAt) >= -Self.launchDatePrecision,
              currentLaunchDate <= now() else { return nil }

        let claimedURL = directory.appendingPathComponent("relaunch-claimed-\(UUID().uuidString).json")
        do { try fileManager.moveItem(at: fileURL, to: claimedURL) } catch { return nil }
        defer { try? fileManager.removeItem(at: claimedURL) }
        guard let claimed = read(claimedURL), claimed.token == pending.token,
              isValid(claimed, bundleIdentifier: bundleIdentifier) else { return nil }
        return claimed
    }

    /// A failed attempt must not clear a newer retry's request.
    func cancel(token: UUID) {
        guard read(fileURL)?.token == token else { return }
        try? fileManager.removeItem(at: fileURL)
    }

    private func read(_ url: URL) -> RelaunchIntent? {
        guard let data = try? Data(contentsOf: url), data.count <= 4096 else { return nil }
        return try? JSONDecoder().decode(RelaunchIntent.self, from: data)
    }

    private func isValid(_ intent: RelaunchIntent, bundleIdentifier: String) -> Bool {
        let date = now()
        return intent.previousPID > 0 && !bundleIdentifier.isEmpty
            && intent.bundleIdentifier == bundleIdentifier
            && intent.previousLaunchDate <= intent.createdAt
            && intent.createdAt <= date && date < intent.expiresAt
            && intent.expiresAt.timeIntervalSince(intent.createdAt) == Self.lifetime
    }
}
