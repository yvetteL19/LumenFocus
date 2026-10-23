import SwiftUI

/// Retained as a source-compatible view; an on-screen moving target is not distant focus.
/// The default rest experience uses the same simple off-screen instruction.
struct FarFocusDotView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("看向屏幕之外")
                .font(.system(size: 24, weight: .medium))
            Text("找一个远处的物体，轻松眨眼。")
                .font(.system(size: 17))
        }
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .padding(24)
        .accessibilityElement(children: .combine)
    }
}
