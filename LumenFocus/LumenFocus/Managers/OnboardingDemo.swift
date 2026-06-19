//
//  OnboardingDemo.swift
//  LumenFocus
//
//  Plays a 10-second compressed version of the rest experience so first-time
//  users see what they're signing up for. Completely isolated from RestController
//  and AppState — running the demo does not increment statistics or change phase.
//

import Cocoa

/// Onboarding 渐暗体验演示
final class OnboardingDemo {
    static let shared = OnboardingDemo()

    private var window: RestOverlayWindow?
    private var fadeOutTimer: Timer?
    private var teardownTimer: Timer?
    private var isRunning = false

    private init() {}

    /// 在主屏上跑一遍 10 秒压缩版：3s 渐暗 → 4s 暗态 → 3s 渐亮
    /// - Parameters:
    ///   - totalDuration: 总时长（含渐暗渐亮）
    ///   - completion: 演示彻底结束后回调
    func play(totalDuration: TimeInterval = 10, completion: (() -> Void)? = nil) {
        guard !isRunning else {
            Log.rest.warning("OnboardingDemo.play called while already running; ignored")
            return
        }
        guard let main = NSScreen.main else {
            completion?()
            return
        }

        Log.rest.info("OnboardingDemo started (total=\(totalDuration, format: .fixed(precision: 0))s)")
        isRunning = true

        let overlay = RestOverlayWindow(screen: main)
        overlay.orderFrontRegardless()
        window = overlay

        // 渐暗占总时长 30%，渐亮 30%，中段 40%
        let fadeIn = totalDuration * 0.3
        let mid = totalDuration * 0.4

        overlay.fadeIn(duration: fadeIn)

        // 中段结束开始渐亮
        let toFadeOut = Timer(timeInterval: fadeIn + mid, repeats: false) { [weak self] _ in
            self?.window?.fadeOut(duration: totalDuration * 0.3)
        }
        RunLoop.main.add(toFadeOut, forMode: .common)
        fadeOutTimer = toFadeOut

        // 总时长结束销毁窗口
        let toTeardown = Timer(timeInterval: totalDuration + 0.2, repeats: false) { [weak self] _ in
            self?.teardown(completion: completion)
        }
        RunLoop.main.add(toTeardown, forMode: .common)
        teardownTimer = toTeardown
    }

    /// 立即取消演示
    func cancel() {
        teardown(completion: nil)
    }

    private func teardown(completion: (() -> Void)?) {
        Log.rest.info("OnboardingDemo teardown")
        fadeOutTimer?.invalidate()
        teardownTimer?.invalidate()
        fadeOutTimer = nil
        teardownTimer = nil

        if let w = window {
            w.stopAllAnimations()
            w.cleanup()
            w.orderOut(nil)
            w.close()
        }
        window = nil
        isRunning = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            completion?()
        }
    }
}
