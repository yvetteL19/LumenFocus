import SwiftUI

/// Work and rest use the same native control. A saved custom value remains selectable.
struct ReminderDurationPicker: View {
    @Binding private var value: Int
    private let titleKey: String
    private let presets: [Int]
    private let secondsPerUnit: Int

    init(workMinutes: Binding<Int>) {
        _value = workMinutes
        titleKey = "提醒间隔"
        presets = Array(stride(from: AppSettings.workDurationRange.lowerBound,
                               through: AppSettings.workDurationRange.upperBound, by: 5))
        secondsPerUnit = 60
    }

    init(restSeconds: Binding<Int>) {
        _value = restSeconds
        titleKey = "休息时长"
        presets = [20, 30, 60, 120, 300, 600, 900]
        secondsPerUnit = 1
    }

    var body: some View {
        Picker(selection: $value) {
            ForEach(Array(Set(presets + [value])).sorted(), id: \.self) { duration in
                Text(verbatim: restDurationText(duration * secondsPerUnit)).tag(duration)
            }
        } label: {
            Text(verbatim: L(titleKey))
        }
        .pickerStyle(.menu)
    }
}

func restDurationText(_ seconds: Int) -> String {
    ReminderPresentation.durationText(seconds: seconds)
}
