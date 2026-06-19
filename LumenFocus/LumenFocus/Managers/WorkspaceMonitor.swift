//
//  WorkspaceMonitor.swift
//  LumenFocus
//
//  Aggregates environment signals (idle / fullscreen / video call / screen lock)
//  into a single publisher TimerManager subscribes to.
//
//  Sandbox-safe: uses only NSWorkspace notifications, frontmost-app bundle ID,
//  and CGEventSource idle timing — all permitted without extra entitlements.
//

import Foundation
import AppKit
import Combine
import CoreGraphics

/// 环境感知信号
struct PauseSignal: Equatable {
    let reason: AutoSuspendReason
    /// 用户可见的简短说明（如「Zoom 会议中」「Keynote 演示」）
    let detail: String?
}

/// 工作区环境监视器
final class WorkspaceMonitor {
    static let shared = WorkspaceMonitor()

    /// 当前应否自动暂停。`nil` 表示无暂停信号；非 nil 表示对应原因
    let pauseSignal = CurrentValueSubject<PauseSignal?, Never>(nil)

    // MARK: - Tunables (公开以便设置项控制 / 测试覆盖)

    /// idle 阈值：无键鼠输入超过多少秒算 idle
    var idleThresholdSeconds: TimeInterval = 60

    /// 评估周期（轮询间隔）
    private let evaluationInterval: TimeInterval = 10

    // MARK: - Configurable signal switches

    var enableIdle = true
    var enableVideoCall = true
    var enableFullscreen = true
    var enableScreenLock = true

    // MARK: - Bundle ID whitelists

    /// 已知的视频通话 / 屏幕共享应用前台时自动暂停
    private let videoCallBundleIDs: Set<String> = [
        "us.zoom.xos",                  // Zoom
        "com.microsoft.teams",          // Teams (classic)
        "com.microsoft.teams2",         // Teams (new)
        "com.apple.FaceTime",
        "com.google.GoogleMeet",        // Meet
        "com.cisco.webexmeetingsapp",
        "com.webex.meetingmanager",
        "com.skype.skype",
        "com.tencent.meeting",          // 腾讯会议
        "com.alibaba.DingTalkMac",      // 钉钉
        "com.tencent.WeWorkMac",        // 企业微信
        "com.electron.discord",
        "com.bluejeansnet.BlueJeans",
    ]

    /// 已知的全屏体验应用前台时避让（演示 / 视频播放）
    private let fullscreenAppBundleIDs: Set<String> = [
        "com.apple.iWork.Keynote",
        "com.microsoft.PowerPoint",
        "com.apple.QuickTimePlayerX",
        "com.colliderli.iina",          // IINA
        "io.mpv",                       // mpv
        "org.videolan.vlc",
    ]

    // MARK: - Private

    private var pollingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var sessionLocked = false

    private init() {
        setupSessionObservers()
        setupAppActivationObservers()
        startPolling()
    }

    // MARK: - Public

    /// 触发一次评估（设置项变化时主动调用）
    func reevaluate() {
        evaluate()
    }

    // MARK: - Setup

    private func setupSessionObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        nc.publisher(for: NSWorkspace.sessionDidResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sessionLocked = true
                if self.enableScreenLock {
                    Log.workspace.info("Session locked → autosuspend")
                    self.publish(PauseSignal(reason: .screenLocked, detail: nil))
                }
            }
            .store(in: &cancellables)

        nc.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sessionLocked = false
                Log.workspace.info("Session unlocked")
                self.evaluate()
            }
            .store(in: &cancellables)

        nc.publisher(for: NSWorkspace.screensDidSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.enableScreenLock {
                    self.publish(PauseSignal(reason: .screenLocked, detail: nil))
                }
            }
            .store(in: &cancellables)

        nc.publisher(for: NSWorkspace.screensDidWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)
    }

    private func setupAppActivationObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        nc.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)

        nc.publisher(for: NSWorkspace.didDeactivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)
    }

    private func startPolling() {
        let timer = Timer(timeInterval: evaluationInterval, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
        evaluate()
    }

    // MARK: - Evaluation (priority: lock > video call > fullscreen > idle)

    private func evaluate() {
        // 屏幕锁定优先级最高，由 session 通知直接驱动
        if sessionLocked && enableScreenLock {
            publish(PauseSignal(reason: .screenLocked, detail: nil))
            return
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           let bundleID = frontmost.bundleIdentifier {

            if enableVideoCall && videoCallBundleIDs.contains(bundleID) {
                publish(PauseSignal(reason: .videoCall, detail: frontmost.localizedName))
                return
            }
            if enableFullscreen && fullscreenAppBundleIDs.contains(bundleID) {
                publish(PauseSignal(reason: .fullscreen, detail: frontmost.localizedName))
                return
            }
        }

        if enableIdle {
            let idle = currentIdleSeconds()
            if idle >= idleThresholdSeconds {
                publish(PauseSignal(reason: .idle, detail: nil))
                return
            }
        }

        publish(nil)
    }

    private func publish(_ next: PauseSignal?) {
        guard next != pauseSignal.value else { return }
        Log.workspace.debug("PauseSignal: \(String(describing: self.pauseSignal.value), privacy: .public) → \(String(describing: next), privacy: .public)")
        pauseSignal.send(next)
    }

    /// 系统范围内距离最后一次键鼠输入的秒数
    private func currentIdleSeconds() -> TimeInterval {
        // kCGAnyInputEventType = ~0；Swift 中需手动构造
        guard let anyInputType = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputType)
    }
}
