import Foundation
import Combine

enum RestStage: Equatable {
    case idle, fadingIn, midRest, fadingOut
}

/// Presentation adapter. CycleEngine owns the session and deadline; this class only
/// publishes the corresponding visual stage and forwards explicit user actions.
final class RestController {
    static let shared = RestController()

    static let fadeInDuration: TimeInterval = 2
    static let fadeOutDuration: TimeInterval = 1

    let stage = CurrentValueSubject<RestStage, Never>(.idle)
    let didFinish = PassthroughSubject<RestEndReason, Never>()

    private let onCancel: () -> Void

    /// Pure visual feedback: no sounds are played, including for migrated preferences.
    init(onCancel: @escaping () -> Void = { TimerManager.shared.cancelCurrentRest() }) {
        self.onCancel = onCancel
    }

    func cancelRest() {
        guard stage.value != .idle else { return }
        onCancel()
    }

    func render(_ progress: CycleRestProgress?) {
        guard let progress else {
            setStage(.idle)
            return
        }

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
