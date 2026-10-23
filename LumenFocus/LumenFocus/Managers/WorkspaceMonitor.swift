import Foundation
import AppKit
import Combine
import CoreGraphics

struct PauseSignal: Equatable {
    let reason: AutoSuspendReason
    let detail: String?
}

/// Remembers the user's last external app while LumenFocus's own windows are open.
/// Pure value logic so app activation and runtime preference changes can be tested.
struct ForegroundAppRuleResolver {
    struct Application: Equatable {
        let bundleID: String
        let name: String?
    }

    private(set) var lastExternalApplication: Application?

    private static let videoCallBundleIDs: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2", "com.apple.FaceTime",
        "com.google.GoogleMeet", "com.cisco.webexmeetingsapp", "com.webex.meetingmanager",
        "com.skype.skype", "com.tencent.meeting", "com.alibaba.DingTalkMac",
        "com.tencent.WeWorkMac", "com.electron.discord", "com.bluejeansnet.BlueJeans"
    ]
    private static let fullscreenAppBundleIDs: Set<String> = [
        "com.apple.iWork.Keynote", "com.microsoft.PowerPoint", "com.apple.QuickTimePlayerX",
        "com.colliderli.iina", "io.mpv", "org.videolan.vlc"
    ]

    mutating func resolve(bundleID: String?, name: String?, ownBundleID: String,
                          enabled: Bool, videoCall: Bool, fullscreen: Bool) -> PauseSignal? {
        if let bundleID, bundleID != ownBundleID {
            lastExternalApplication = Application(bundleID: bundleID, name: name)
        }
        guard enabled, let application = lastExternalApplication else { return nil }
        if videoCall && Self.videoCallBundleIDs.contains(application.bundleID) {
            return PauseSignal(reason: .videoCall, detail: application.name)
        }
        if fullscreen && Self.fullscreenAppBundleIDs.contains(application.bundleID) {
            return PauseSignal(reason: .fullscreen, detail: application.name)
        }
        return nil
    }
}

/// Uses local app/idle signals, not a claim that a real call or fullscreen session was detected.
/// Physical lock/sleep is separate from optional reminder suppression and is always observed.
final class WorkspaceMonitor {
    static let shared = WorkspaceMonitor()

    let environment = CurrentValueSubject<CycleEnvironment, Never>(.available)
    let pauseSignal = CurrentValueSubject<PauseSignal?, Never>(nil)
    var idleThresholdSeconds: TimeInterval = 60

    private var enabled: Bool
    private var enableIdle: Bool
    private var enableVideoCall: Bool
    private var enableFullscreen: Bool
    private var enableScreenLock: Bool
    private var pollingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var sessionLocked = false
    private var screensSleeping = false
    private var systemSleeping = false
    private var foregroundRules = ForegroundAppRuleResolver()

    private init() {
        let settings = AppSettings.shared
        enabled = settings.enableSmartDetection
        enableIdle = settings.detectIdle
        enableVideoCall = settings.detectVideoCall
        enableFullscreen = settings.detectFullscreen
        enableScreenLock = settings.detectScreenLock
        setupObservers()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.reevaluate() }
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
        reevaluate()
    }

    func configure(enabled: Bool, idle: Bool, videoCall: Bool, fullscreen: Bool, screenLock: Bool) {
        self.enabled = enabled
        enableIdle = idle
        enableVideoCall = videoCall
        enableFullscreen = fullscreen
        enableScreenLock = screenLock
        reevaluate()
    }

    func reevaluate() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.reevaluate() }
            return
        }
        let away = sessionLocked || screensSleeping || systemSleeping
        var next = CycleEnvironment(reason: nil, detail: nil, isAway: away)
        if away {
            // Physical absence is safety/lifecycle handling, never an optional heuristic.
            next.reason = .screenLocked
        } else {
            let frontmost = NSWorkspace.shared.frontmostApplication
            let rule = foregroundRules.resolve(bundleID: frontmost?.bundleIdentifier,
                                               name: frontmost?.localizedName,
                                               ownBundleID: Bundle.main.bundleIdentifier ?? "Yvette.LumenFocus",
                                               enabled: enabled, videoCall: enableVideoCall,
                                               fullscreen: enableFullscreen)
            next.reason = rule?.reason
            next.detail = rule?.detail
            if enabled && next.reason == nil && enableIdle && currentIdleSeconds() >= idleThresholdSeconds {
                next.reason = .idle
            }
        }
        publish(next)
    }

    private func setupObservers() {
        observe(NSWorkspace.sessionDidResignActiveNotification) { $0.sessionLocked = true }
        observe(NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionLocked = false }
        observe(NSWorkspace.screensDidSleepNotification) { $0.screensSleeping = true }
        observe(NSWorkspace.screensDidWakeNotification) { $0.screensSleeping = false }
        observe(NSWorkspace.willSleepNotification) { $0.systemSleeping = true }
        observe(NSWorkspace.didWakeNotification) { $0.systemSleeping = false }
        observe(NSWorkspace.didActivateApplicationNotification) { _ in }
        observe(NSWorkspace.didDeactivateApplicationNotification) { _ in }
    }

    private func observe(_ name: Notification.Name, update: @escaping (WorkspaceMonitor) -> Void) {
        NSWorkspace.shared.notificationCenter.publisher(for: name)
            .sink { [weak self] _ in
                guard let self else { return }
                let action = { [weak self] in
                    guard let self else { return }
                    update(self)
                    self.reevaluate()
                }
                if Thread.isMainThread { action() }
                else { DispatchQueue.main.async(execute: action) }
            }
            .store(in: &cancellables)
    }

    private func publish(_ next: CycleEnvironment) {
        guard environment.value != next else { return }
        // Application names are for the live UI, never a persistent activity log.
        Log.workspace.debug("Environment changed; away=\(next.isAway)")
        environment.send(next)
        let signal = next.suppressesReminder
            ? PauseSignal(reason: next.reason ?? .screenLocked, detail: next.detail) : nil
        if signal != pauseSignal.value { pauseSignal.send(signal) }
    }

    private func currentIdleSeconds() -> TimeInterval {
        guard let anyInputType = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputType)
    }
}
