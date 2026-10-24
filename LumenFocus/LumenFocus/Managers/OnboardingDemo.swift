import Cocoa
import Combine

/// A short preview of the same mask and keyboard exit, without creating a recorded rest.
final class OnboardingDemo {
    static let shared = OnboardingDemo()
    private var window: RestOverlayWindow?
    private var timer: Timer?
    private var completionHandler: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        WorkspaceMonitor.shared.environment
            .sink { [weak self] environment in
                if environment.isAway { self?.cancel() }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.cancel() }
            .store(in: &cancellables)
    }

    func play(totalDuration: TimeInterval = 10, completion: (() -> Void)? = nil) {
        guard window == nil, let screen = NSScreen.main else { completion?(); return }
        let total = max(3, totalDuration)
        let fadeIn = min(RestController.fadeInDuration, total / 3)
        let fadeOut = min(RestController.fadeOutDuration, total / 3)
        let rest = total - fadeIn - fadeOut
        let overlay = RestOverlayWindow(screenFrame: screen.frame, onEnd: { [weak self] in self?.cancel() })
        window = overlay
        completionHandler = completion
        overlay.updateCountdown(seconds: Int(ceil(rest)))
        overlay.makeKeyAndOrderFront(nil)
        overlay.fadeIn(duration: fadeIn)
        let started = ProcessInfo.processInfo.systemUptime
        var isFadingOut = false
        let value = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let window = self.window else { return }
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            if elapsed >= total { self.cancel(); return }
            window.updateCountdown(seconds: Int(ceil(max(0, rest - max(0, elapsed - fadeIn)))))
            if elapsed >= total - fadeOut && !isFadingOut {
                isFadingOut = true
                window.fadeOut(duration: fadeOut)
            }
        }
        RunLoop.main.add(value, forMode: .common)
        timer = value
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        window?.cleanup()
        window?.orderOut(nil)
        window?.close()
        window = nil
        let completion = completionHandler
        completionHandler = nil
        if let completion { DispatchQueue.main.async(execute: completion) }
    }
}
