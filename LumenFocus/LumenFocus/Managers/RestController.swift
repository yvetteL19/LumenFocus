import Foundation
import Combine

enum RestStage: Equatable {
    case idle, fadingIn, midRest, fadingOut
}

/// Retained for the renderer. The default experience is an invitation to look away.
enum MidRestActivity: Equatable {
    case breathing, farFocus, free
}

/// Presentation adapter. CycleEngine owns the session and deadline; this class only
/// publishes the corresponding visual stage and forwards explicit user actions.
final class RestController {
    static let shared = RestController()

    static let fadeInDuration: TimeInterval = 2
    static let fadeOutDuration: TimeInterval = 1

    let stage = CurrentValueSubject<RestStage, Never>(.idle)
    let midRestActivity = CurrentValueSubject<MidRestActivity, Never>(.free)
    let didFinish = PassthroughSubject<RestEndReason, Never>()

    private let onCancel: () -> Void
    private let onSnooze: (TimeInterval) -> Void
    private let onStartSound: () -> Void
    private let onStopSound: () -> Void
    private var sessionID: UUID?

    /// Injectable actions keep presentation tests isolated from app singletons and audio.
    init(onCancel: @escaping () -> Void = { TimerManager.shared.cancelCurrentRest() },
         onSnooze: @escaping (TimeInterval) -> Void = { TimerManager.shared.snoozeReminder(by: $0) },
         onStartSound: @escaping () -> Void = { AmbientSoundManager.shared.play(AppSettings.shared.ambientTrack) },
         onStopSound: @escaping () -> Void = { AmbientSoundManager.shared.stop() }) {
        self.onCancel = onCancel
        self.onSnooze = onSnooze
        self.onStartSound = onStartSound
        self.onStopSound = onStopSound
    }

    func cancelRest() {
        guard stage.value != .idle else { return }
        onCancel()
    }

    /// Available throughout the rest, including its fade-out.
    func snooze(by seconds: TimeInterval) {
        guard stage.value != .idle else { return }
        onSnooze(seconds)
    }

    func render(_ progress: CycleRestProgress?) {
        guard let progress else {
            if sessionID != nil { onStopSound() }
            sessionID = nil
            setStage(.idle)
            return
        }

        if sessionID != progress.id {
            if sessionID != nil { onStopSound() }
            sessionID = progress.id
            onStartSound()
        }
        if midRestActivity.value != .free { midRestActivity.send(.free) }
        let next: RestStage
        if progress.elapsed < progress.fadeInDuration {
            next = .fadingIn
        } else if progress.elapsed < progress.fadeInDuration + progress.duration {
            next = .midRest
        } else {
            next = .fadingOut
        }
        setStage(next)
    }

    func publishEnd(_ reason: RestEndReason) {
        didFinish.send(reason)
    }

    private func setStage(_ next: RestStage) {
        if stage.value != next { stage.send(next) }
    }
}
