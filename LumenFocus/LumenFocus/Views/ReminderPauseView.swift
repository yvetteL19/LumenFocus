import SwiftUI

/// Identical pause choices in settings and the menu-bar popover.
struct ReminderPauseMenu: View {
    var titleKey = "暂停提醒"
    var onSelect: () -> Void = {}

    var body: some View {
        Menu {
            ForEach(ReminderPresentation.pauseChoices, id: \.self) { minutes in
                Button {
                    onSelect()
                    TimerManager.shared.pause(duration: TimeInterval(minutes * 60))
                } label: {
                    Text(verbatim: ReminderPresentation.pauseOptionTitle(minutes: minutes))
                }
            }
            Divider()
            Button {
                onSelect()
                ReminderPauseWindowManager.shared.show()
            } label: {
                Text("自定义…")
            }
        } label: {
            Text(verbatim: L(titleKey))
                .fixedSize(horizontal: false, vertical: true)
        }
        .menuStyle(.borderlessButton)
    }
}

struct ReminderPauseView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var minutesText = "60"
    @FocusState private var isEditingMinutes: Bool
    var onConfirm: (TimeInterval) -> Void
    var onCancel: () -> Void

    private var minutes: Int? {
        guard let value = Int(minutesText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...1440).contains(value) else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("自定义暂停")
                .font(.title2)
            HStack(spacing: 12) {
                Text("暂停时长")
                Spacer(minLength: 8)
                TextField("分钟", text: $minutesText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .focused($isEditingMinutes)
                    .accessibilityLabel(Text("暂停时长（分钟）"))
                Text("分钟")
            }
            Text("请输入 1 到 1440 之间的整数分钟。")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: L(settings.remindersEnabled ? "暂停结束后重新计时。" : "提醒已停止"))
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("暂停") {
                    guard settings.remindersEnabled, let minutes else { return }
                    onConfirm(TimeInterval(minutes * 60))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.LumenFocus.ink)
                .disabled(minutes == nil || !settings.remindersEnabled)
            }
        }
        .padding(24)
        .frame(minWidth: 380, minHeight: 220)
        .onAppear { isEditingMinutes = true }
    }
}
