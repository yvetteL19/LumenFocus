import Foundation

/// AppKit display rectangles are measured in points, including displays left of
/// or below the main display. Backing scale must never be applied a second time.
enum DisplayLayout {
    struct Screen: Equatable {
        let id: UInt32
        let frame: CGRect
        let visibleFrame: CGRect
    }

    struct Update: Equatable {
        let removedIDs: Set<UInt32>
        let insertedIDs: Set<UInt32>
        let resizedIDs: Set<UInt32>
        let primaryID: UInt32?
    }

    static func update(existingFrames: [UInt32: CGRect], screens: [Screen],
                       retaining primaryID: UInt32?, pointer: CGPoint) -> Update {
        let existing = Set(existingFrames.keys)
        let current = Set(screens.map(\.id))
        let primary = screens.first { $0.id == primaryID }
            ?? screens.first { $0.frame.contains(pointer) }
            ?? screens.first
        return Update(removedIDs: existing.subtracting(current),
                      insertedIDs: current.subtracting(existing),
                      resizedIDs: Set(screens.compactMap { screen in
                          guard let old = existingFrames[screen.id], old != screen.frame else { return nil }
                          return screen.id
                      }), primaryID: primary?.id)
    }

    static func contentBounds(for screenFrame: CGRect) -> CGRect {
        CGRect(origin: .zero, size: screenFrame.size)
    }

}
