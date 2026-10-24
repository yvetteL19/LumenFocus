import Foundation
import AppKit
import Combine

/// Observes physical lock/sleep only. No foreground-app identity or input activity is read.
final class WorkspaceMonitor {
    static let shared = WorkspaceMonitor()
    let environment = CurrentValueSubject<CycleEnvironment, Never>(.available)

    private var cancellables = Set<AnyCancellable>()
    private var sessionLocked = false
    private var screensSleeping = false
    private var systemSleeping = false

    private init() { setupObservers() }

    func reevaluate() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.reevaluate() }
            return
        }
        let away = sessionLocked || screensSleeping || systemSleeping
        let next = away ? CycleEnvironment(reason: .screenLocked, detail: nil, isAway: true) : .available
        if environment.value != next { environment.send(next) }
    }

    private func setupObservers() {
        observe(NSWorkspace.sessionDidResignActiveNotification) { $0.sessionLocked = true }
        observe(NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionLocked = false }
        observe(NSWorkspace.screensDidSleepNotification) { $0.screensSleeping = true }
        observe(NSWorkspace.screensDidWakeNotification) { $0.screensSleeping = false }
        observe(NSWorkspace.willSleepNotification) { $0.systemSleeping = true }
        observe(NSWorkspace.didWakeNotification) { $0.systemSleeping = false }
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
}
