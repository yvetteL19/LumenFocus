import AppKit
import SwiftUI

extension Color {
    /// A small shared palette that follows the system appearance and contrast settings.
    /// Native controls own foreground contrast; the rest overlay uses AppKit black.
    enum LumenFocus {
        static let textPrimary = Color(nsColor: .labelColor)
        static let textSecondary = Color(nsColor: .secondaryLabelColor)
        static let backgroundPrimary = Color(nsColor: .windowBackgroundColor)
        static let backgroundSecondary = Color(nsColor: .controlBackgroundColor)
        static let border = Color(nsColor: .separatorColor)
        static let ink = Color(nsColor: .labelColor)
    }
}
