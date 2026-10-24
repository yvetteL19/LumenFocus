import Foundation
import Combine

/// Connects the pure cycle engine to settings, environment, persistence, and presentation.
/// The timer is only a heartbeat; all elapsed time and deadlines belong to CycleEngine.
final class TimerManager: ObservableObject {
    static let shared = TimerManager()

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let appState = AppState.shared
    private let restController = RestController.shared
    private let workspaceMonitor = WorkspaceMonitor.shared
    private let engine: CycleEngine

    var isRunning: Bool { timer?.isValid == true }

    private init() {
        engine = CycleEngine(configuration: Self.configuration())
        reloadEnvironmentSettings()
        engine.setEnvironment(workspaceMonitor.environment.value)
        setupSubscriptions()
        synchronize()
    }

    func start() {
        appState.clearRestOutcome()
        refreshConfiguration()
        engine.start()
        scheduleHeartbeat()
        synchronize()
    }

    func stop() {
        appState.clearRestOutcome()
        timer?.invalidate()
        timer = nil
        engine.stop()
        synchronize()
        StatisticsManager.shared.flush()
    }

    /// Pauses reminders, not work measurement. Meeting/lock restrictions stay independent.
    func pause(duration: TimeInterval? = nil) {
        appState.clearRestOutcome()
        let now = Date()
        let until: Date
        if let duration {
            until = now.addingTimeInterval(max(0, duration))
        } else {
            until = Calendar.current.date(byAdding: .day, value: 1,
                                          to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        }
        engine.pause(until: until)
        synchronize()
        StatisticsManager.shared.flush()
    }

    func resume() {
        appState.clearRestOutcome()
        if !engine.isStarted { engine.start() }
        engine.resume()
        scheduleHeartbeat()
        synchronize()
    }

    func toggleRestViaShortcut() {
        if engine.snapshot.rest != nil { cancelCurrentRest() }
        else { triggerManualRest() }
    }

    func triggerManualRest() {
        appState.clearRestOutcome()
        // Settings publishers are delivered on the next main-loop turn. An
        // immediate click on Rest now must still use the just-selected duration.
        if !engine.isStarted { engine.start() }
        engine.beginRest(using: Self.configuration())
        scheduleHeartbeat()
        synchronize()
        StatisticsManager.shared.flush()
    }

    func snoozeReminder(by seconds: TimeInterval) {
        appState.clearRestOutcome()
        engine.snooze(by: seconds)
        synchronize()
        StatisticsManager.shared.flush()
    }

    func skipReminder() {
        appState.clearRestOutcome()
        engine.skipReminder()
        synchronize()
        StatisticsManager.shared.flush()
    }

    func cancelCurrentRest() {
        engine.cancelRest()
        synchronize()
        StatisticsManager.shared.flush()
    }

    func snoozeCurrentTrigger(by seconds: TimeInterval) { snoozeReminder(by: seconds) }

    @available(*, deprecated, renamed: "triggerManualRest")
    func triggerTestRest() { triggerManualRest() }

    @available(*, deprecated, renamed: "cancelCurrentRest")
    func cancelRest() { cancelCurrentRest() }

    private static func configuration() -> CycleEngine.Configuration {
        let settings = AppSettings.shared
        return CycleEngine.Configuration(workDuration: TimeInterval(settings.workDurationMinutes * 60),
                                         restDuration: TimeInterval(settings.restDurationSeconds),
                                         automaticallyStartsRest: settings.reminderMode == .immersive,
                                         fadeInDuration: RestController.fadeInDuration,
                                         fadeOutDuration: RestController.fadeOutDuration)
    }

    private func refreshConfiguration() {
        let latest = Self.configuration()
        if engine.configuration != latest { engine.configure(latest) }
    }

    private func setupSubscriptions() {
        // Handle sleep synchronously, before the main run loop is suspended.
        workspaceMonitor.environment
            .sink { [weak self] value in
                guard let self else { return }
                self.engine.setEnvironment(value)
                self.synchronize()
                if value.isAway { StatisticsManager.shared.flush() }
            }
            .store(in: &cancellables)

        let settings = AppSettings.shared
        Publishers.Merge3(settings.$workDurationMinutes.map { _ in () },
                          settings.$restDurationSeconds.map { _ in () },
                          settings.$reminderMode.map { _ in () })
            .dropFirst(3)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.appState.clearRestOutcome()
                self.engine.configure(Self.configuration())
                self.reloadEnvironmentSettings()
                self.synchronize()
            }
            .store(in: &cancellables)

        Publishers.MergeMany([
            settings.$enableSmartDetection.map { _ in () }.eraseToAnyPublisher(),
            settings.$detectIdle.map { _ in () }.eraseToAnyPublisher(),
            settings.$detectVideoCall.map { _ in () }.eraseToAnyPublisher(),
            settings.$detectFullscreen.map { _ in () }.eraseToAnyPublisher(),
            settings.$detectScreenLock.map { _ in () }.eraseToAnyPublisher()
        ])
            .dropFirst(5)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.reloadEnvironmentSettings() }
            .store(in: &cancellables)
    }

    private func reloadEnvironmentSettings() {
        let settings = AppSettings.shared
        workspaceMonitor.configure(enabled: settings.enableSmartDetection,
                                   idle: settings.reminderMode == .immersive && settings.detectIdle,
                                   videoCall: settings.detectVideoCall,
                                   fullscreen: settings.detectFullscreen,
                                   screenLock: settings.detectScreenLock)
    }

    private func scheduleHeartbeat() {
        guard timer == nil else { return }
        let value = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.engine.tick()
            self.synchronize()
        }
        RunLoop.main.add(value, forMode: .common)
        timer = value
    }

    private func synchronize() {
        let events = engine.drainEvents()
        let statistics = StatisticsManager.shared
        for event in events {
            switch event {
            case .workRecorded(let from, let to):
                statistics.recordWork(from: from, to: to)
            case .restEnded(let id, let date, .completed):
                statistics.recordCompletedRest(at: date, id: id)
            case .restEnded, .naturalBreak:
                break
            }
        }
        appState.apply(engine.snapshot)
        appState.refreshStatistics()
        restController.render(engine.snapshot.rest)
        for case .restEnded(_, _, let reason) in events {
            appState.recordRestOutcome(reason)
            restController.publishEnd(reason)
            statistics.flush()
        }
    }
}
