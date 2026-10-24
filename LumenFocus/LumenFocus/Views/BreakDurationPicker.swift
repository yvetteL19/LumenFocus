import SwiftUI

/// The same compact duration choice is used in initial setup and preferences.
struct BreakDurationPicker: View {
    @Binding var seconds: Int

    var body: some View {
        Picker("休息时长", selection: $seconds) {
            ForEach(restDurationChoices(including: seconds), id: \.self) { duration in
                Text(verbatim: restDurationText(duration)).tag(duration)
            }
        }
        .pickerStyle(.menu)
    }
}

func restDurationChoices(including current: Int) -> [Int] {
    Array(Set([20, 30, 60, 120, 300, 600, 900, current])).sorted()
}

func restDurationText(_ seconds: Int) -> String {
    ReminderPresentation.durationText(seconds: seconds)
}
