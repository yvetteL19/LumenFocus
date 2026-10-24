import AppKit

/// A replacement process must not load records or register shortcuts before its
/// predecessor finishes saving. Subscription precedes the final liveness check.
final class RelaunchHandoff {
    private let center: NotificationCenter
    private let isRunning: (pid_t) -> Bool
    private let terminatedPID: (Notification) -> pid_t?
    private var observer: NSObjectProtocol?
    private var ready: (() -> Void)?
    private var waitingFor: pid_t?

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter,
         isRunning: @escaping (pid_t) -> Bool = { NSRunningApplication(processIdentifier: $0)?.isTerminated == false },
         terminatedPID: @escaping (Notification) -> pid_t? = {
             ($0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
         }) {
        self.center = center
        self.isRunning = isRunning
        self.terminatedPID = terminatedPID
    }

    func wait(for processID: pid_t, then onReady: @escaping () -> Void) {
        if let observer { center.removeObserver(observer) }
        waitingFor = processID
        ready = onReady
        observer = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                      object: nil, queue: .main) { [weak self] notification in
            guard let self, self.terminatedPID(notification) == self.waitingFor else { return }
            self.finish()
        }
        if !isRunning(processID) { finish() }
    }

    private func finish() {
        guard waitingFor != nil else { return }
        waitingFor = nil
        if let observer { center.removeObserver(observer) }
        observer = nil
        let callback = ready
        ready = nil
        callback?()
    }

    deinit {
        if let observer { center.removeObserver(observer) }
    }
}
