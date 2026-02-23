import SwiftUI

struct ProjectFormView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    let project: PPProject?

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var status: ProjectStatus = .active
    @State private var startDate: Date = Date()
    @State private var hasStartDate: Bool = true
    @State private var completedAt: Date = Date()
    @State private var hasCompletedAt: Bool = false
    @State private var hasPlannedEndDate: Bool = false
    @State private var plannedEndDate: Date = Date()

    private var isEditMode: Bool { project != nil }

    init(project: PPProject? = nil) {
        self.project = project
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("プロジェクト名") {
                    TextField("例: ウェブサイト制作", text: $name)
                        .accessibilityLabel("プロジェクト名")
                        .accessibilityValue(name.isEmpty ? "未入力" : name)
                }

                Section("説明") {
                    TextField("プロジェクトの概要を入力...", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("プロジェクトの説明")
                        .accessibilityValue(description.isEmpty ? "未入力" : description)
                }

                Section("開始日") {
                    Toggle("開始日を設定", isOn: $hasStartDate)
                        .accessibilityLabel("開始日を設定")
                        .accessibilityHint("オンにすると開始日を指定できます")

                    if hasStartDate {
                        DatePicker(
                            "開始日",
                            selection: $startDate,
                            displayedComponents: .date
                        )
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                        .accessibilityLabel("開始日")
                        .accessibilityValue(formatDate(startDate))

                        Text("開始月の取引は日割り計算で再配分されます")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isEditMode && status != .completed {
                    Section("終了予定日") {
                        Toggle("終了予定日を設定", isOn: $hasPlannedEndDate)
                            .accessibilityLabel("終了予定日を設定")
                            .accessibilityHint("オンにすると終了予定日を指定できます")

                        if hasPlannedEndDate {
                            DatePicker(
                                "終了予定日",
                                selection: $plannedEndDate,
                                displayedComponents: .date
                            )
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                            .accessibilityLabel("終了予定日")
                            .accessibilityValue(formatDate(plannedEndDate))

                            Text("予定完了月の取引は日割り計算で推定配分されます")
                                .font(.caption)
                                .foregroundStyle(.orange)

                            Text("予定完了日を過ぎてもプロジェクトは自動的に完了しません")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if isEditMode {
                    Section("ステータス") {
                        Picker("ステータス", selection: $status) {
                            ForEach(ProjectStatus.allCases, id: \.self) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("ステータス")
                        .accessibilityValue(status.label)
                        .accessibilityHint("タップしてステータスを変更")
                    }

                    if status == .completed {
                        Section("完了日") {
                            Toggle("完了日を設定", isOn: $hasCompletedAt)
                                .accessibilityLabel("完了日を設定")
                                .accessibilityHint("オンにすると完了日を指定できます")

                            if hasCompletedAt {
                                DatePicker(
                                    "完了日",
                                    selection: $completedAt,
                                    displayedComponents: .date
                                )
                                .environment(\.locale, Locale(identifier: "ja_JP"))
                                .accessibilityLabel("完了日")
                                .accessibilityValue(formatDate(completedAt))

                                Text("完了月の取引は日割り計算で再配分されます")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditMode ? "プロジェクトを編集" : "新規プロジェクト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .accessibilityLabel("キャンセル")
                        .accessibilityHint("タップして入力を取り消し")
                }
                ToolbarItem(placement: .confirmationAction) {
                    let isEmpty = name.trimmingCharacters(in: .whitespaces).isEmpty
                    Button("保存") { save() }
                        .disabled(isEmpty)
                        .accessibilityLabel("保存")
                        .accessibilityHint(isEmpty ? "プロジェクト名を入力してください" : "タップしてプロジェクトを保存")
                }
            }
            .onAppear {
                if let project {
                    name = project.name
                    description = project.projectDescription
                    status = project.status
                    if let date = project.startDate {
                        startDate = date
                        hasStartDate = true
                    } else {
                        hasStartDate = false
                    }
                    if let date = project.completedAt {
                        completedAt = date
                        hasCompletedAt = true
                    }
                    if let date = project.plannedEndDate {
                        plannedEndDate = date
                        hasPlannedEndDate = true
                    }
                }
            }
            .onChange(of: status) { _, newStatus in
                if newStatus == .completed && !hasCompletedAt {
                    hasCompletedAt = true
                    completedAt = hasPlannedEndDate ? plannedEndDate : Date()
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let resolvedStartDate: Date?? = hasStartDate ? .some(startDate) : .some(nil)
        let resolvedPlannedEndDate: Date?? = hasPlannedEndDate ? .some(plannedEndDate) : .some(nil)

        if let project {
            if status == .completed && hasCompletedAt {
                dataStore.updateProject(id: project.id, name: trimmedName, description: description, status: status, startDate: resolvedStartDate, completedAt: completedAt, plannedEndDate: .some(nil))
            } else {
                dataStore.updateProject(id: project.id, name: trimmedName, description: description, status: status, startDate: resolvedStartDate, plannedEndDate: resolvedPlannedEndDate)
            }
        } else {
            dataStore.addProject(name: trimmedName, description: description, startDate: hasStartDate ? startDate : nil, plannedEndDate: hasPlannedEndDate ? plannedEndDate : nil)
        }
        dismiss()
    }
}
