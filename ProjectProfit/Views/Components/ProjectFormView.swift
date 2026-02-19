import SwiftUI

struct ProjectFormView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    let project: PPProject?

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var status: ProjectStatus = .active

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
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if let project {
            dataStore.updateProject(id: project.id, name: trimmedName, description: description, status: status)
        } else {
            dataStore.addProject(name: trimmedName, description: description)
        }
        dismiss()
    }
}
