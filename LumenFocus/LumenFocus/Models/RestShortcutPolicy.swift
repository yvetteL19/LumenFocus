import Foundation

/// A nonactivating overlay can consume the modifier keys before Carbon delivers
/// the matching hot-key press. Treat those callbacks as one user gesture.
struct RestShortcutPolicy {
    enum Action: Equatable { case start, cancel, ignore }

    private var suppressStartsUntil: TimeInterval?
    private var awaitingRelease = false
    private let cancellationWindow: TimeInterval = 1

    mutating func restDidEnd(at elapsed: TimeInterval) {
        suppressStartsUntil = elapsed + cancellationWindow
    }

    mutating func pressed(isResting: Bool, at elapsed: TimeInterval) -> Action {
        guard !awaitingRelease else { return .ignore }
        // A held shortcut must never alternate start/cancel on repeat events.
        awaitingRelease = true
        if isResting { return .cancel }
        if let deadline = suppressStartsUntil, elapsed < deadline { return .ignore }
        return .start
    }

    mutating func released() {
        awaitingRelease = false
        // Releasing and pressing again is an explicit new gesture, even quickly.
        suppressStartsUntil = nil
    }
}
