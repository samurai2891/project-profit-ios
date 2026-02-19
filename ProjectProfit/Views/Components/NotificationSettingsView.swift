import SwiftUI

// MARK: - NotificationSettingsView

struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let currentTiming: NotificationTiming
    let onSave: (NotificationTiming) -> Void

    @State private var selectedTiming: NotificationTiming

    init(currentTiming: NotificationTiming, onSave: @escaping (NotificationTiming) -> Void) {
        self.currentTiming = currentTiming
        self.onSave = onSave
        self._selectedTiming = State(initialValue: currentTiming)
    }

    private let timingOptions: [(timing: NotificationTiming, label: String)] = [
        (.none, "通知なし"),
        (.sameDay, "当日に通知"),
        (.dayBefore, "前日に通知"),
        (.both, "前日と当日に通知"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(timingOptions, id: \.timing) { option in
                        timingRow(option.timing, label: option.label)
                    }
                } header: {
                    Text("通知タイミング")
                }
            }
            .navigationTitle("通知設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(selectedTiming)
                        dismiss()
                    }
                    .foregroundStyle(AppColors.primary)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Timing Row

    private func timingRow(_ timing: NotificationTiming, label: String) -> some View {
        Button {
            selectedTiming = timing
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)

                Spacer()

                if selectedTiming == timing {
                    Image(systemName: "checkmark")
                        .foregroundStyle(AppColors.primary)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NotificationSettingsView(
        currentTiming: .sameDay,
        onSave: { timing in
            print("Selected timing: \(timing)")
        }
    )
}
