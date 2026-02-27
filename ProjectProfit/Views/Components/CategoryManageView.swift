import SwiftData
import SwiftUI

// MARK: - CategoryManageView

struct CategoryManageView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    @State private var editingCategoryID: String? = nil
    @State private var editingName: String = ""
    @State private var newExpenseCategoryName: String = ""
    @State private var newIncomeCategoryName: String = ""
    @State private var isAddingExpenseCategory: Bool = false
    @State private var isAddingIncomeCategory: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var categoryToDelete: PPCategory? = nil
    @State private var errorMessage: String? = nil

    private var expenseCategories: [PPCategory] {
        dataStore.categories.filter { $0.type == .expense && $0.archivedAt == nil }
    }

    private var incomeCategories: [PPCategory] {
        dataStore.categories.filter { $0.type == .income && $0.archivedAt == nil }
    }

    private var archivedCategories: [PPCategory] {
        dataStore.categories.filter { $0.archivedAt != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                expenseCategorySection
                incomeCategorySection
                if !archivedCategories.isEmpty {
                    archivedCategorySection
                }
            }
            .navigationTitle("カテゴリ管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.primary)
                }
            }
            .alert("エラー", isPresented: showErrorBinding) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("カテゴリをアーカイブ", isPresented: $showDeleteConfirmation) {
                Button("アーカイブ", role: .destructive) {
                    performDelete()
                }
                Button("キャンセル", role: .cancel) {
                    categoryToDelete = nil
                }
            } message: {
                if let category = categoryToDelete {
                    Text("「\(category.name)」をアーカイブしますか？新規取引では選択できなくなりますが、既存の取引はそのまま保持されます。")
                }
            }
        }
    }

    // MARK: - Expense Category Section

    private var expenseCategorySection: some View {
        Section {
            ForEach(expenseCategories) { category in
                categoryRow(for: category)
            }

            if isAddingExpenseCategory {
                addCategoryRow(
                    name: $newExpenseCategoryName,
                    onSave: { saveNewCategory(name: newExpenseCategoryName, type: .expense) },
                    onCancel: { cancelAddExpenseCategory() }
                )
            }

            if !isAddingExpenseCategory {
                addButton {
                    isAddingExpenseCategory = true
                }
            }
        } header: {
            Text("経費カテゴリ")
        }
    }

    // MARK: - Income Category Section

    private var incomeCategorySection: some View {
        Section {
            ForEach(incomeCategories) { category in
                categoryRow(for: category)
            }

            if isAddingIncomeCategory {
                addCategoryRow(
                    name: $newIncomeCategoryName,
                    onSave: { saveNewCategory(name: newIncomeCategoryName, type: .income) },
                    onCancel: { cancelAddIncomeCategory() }
                )
            }

            if !isAddingIncomeCategory {
                addButton {
                    isAddingIncomeCategory = true
                }
            }
        } header: {
            Text("収益カテゴリ")
        }
    }

    // MARK: - Category Row

    private func categoryRow(for category: PPCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.title3)
                .foregroundStyle(AppColors.primary)
                .frame(width: 28, alignment: .center)

            if editingCategoryID == category.id {
                editingRow(for: category)
            } else {
                displayRow(for: category)
            }
        }
        .padding(.vertical, 2)
    }

    private func displayRow(for category: PPCategory) -> some View {
        HStack {
            Text(category.name)
                .foregroundStyle(.primary)

            Spacer()

            Button {
                startEditing(category)
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(AppColors.primary)
            }
            .buttonStyle(.borderless)

            if !category.isDefault {
                Button {
                    categoryToDelete = category
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "archivebox")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func editingRow(for category: PPCategory) -> some View {
        HStack {
            TextField("カテゴリ名", text: $editingName)
                .textFieldStyle(.roundedBorder)

            Button {
                saveEdit(for: category)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.primary)
            }
            .buttonStyle(.borderless)
            .disabled(editingName.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                cancelEditing()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Add Category Row

    private func addCategoryRow(
        name: Binding<String>,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle")
                .font(.title3)
                .foregroundStyle(AppColors.primary)
                .frame(width: 28, alignment: .center)

            TextField("新しいカテゴリ名", text: name)
                .textFieldStyle(.roundedBorder)

            Button {
                onSave()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.primary)
            }
            .buttonStyle(.borderless)
            .disabled(name.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Add Button

    private func addButton(action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("カテゴリを追加")
            }
            .foregroundStyle(AppColors.primary)
        }
    }

    // MARK: - Archived Category Section

    private var archivedCategorySection: some View {
        Section {
            ForEach(archivedCategories) { category in
                HStack(spacing: 12) {
                    Image(systemName: category.icon)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .center)

                    Text(category.name)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        dataStore.unarchiveCategory(id: category.id)
                    } label: {
                        Text("復元")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppColors.primary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("アーカイブ済み")
        }
    }

    // MARK: - Actions

    private func startEditing(_ category: PPCategory) {
        editingCategoryID = category.id
        editingName = category.name
    }

    private func cancelEditing() {
        editingCategoryID = nil
        editingName = ""
    }

    private func saveEdit(for category: PPCategory) {
        let trimmedName = editingName.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty else {
            errorMessage = "カテゴリ名を入力してください。"
            return
        }

        let sameTypeCategories = dataStore.categories.filter { $0.type == category.type }
        if sameTypeCategories.contains(where: { $0.id != category.id && $0.name == trimmedName }) {
            errorMessage = "同じ名前のカテゴリが既に存在します"
            return
        }

        dataStore.updateCategory(id: category.id, name: trimmedName)
        cancelEditing()
    }

    private func saveNewCategory(name: String, type: CategoryType) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty else {
            errorMessage = "カテゴリ名を入力してください。"
            return
        }

        let sameTypeCategories = dataStore.categories.filter { $0.type == type }
        if sameTypeCategories.contains(where: { $0.name == trimmedName }) {
            errorMessage = "同じ名前のカテゴリが既に存在します"
            return
        }

        dataStore.addCategory(name: trimmedName, type: type, icon: "tag")

        switch type {
        case .expense:
            cancelAddExpenseCategory()
        case .income:
            cancelAddIncomeCategory()
        }
    }

    private func cancelAddExpenseCategory() {
        isAddingExpenseCategory = false
        newExpenseCategoryName = ""
    }

    private func cancelAddIncomeCategory() {
        isAddingIncomeCategory = false
        newIncomeCategoryName = ""
    }

    private func performDelete() {
        guard let category = categoryToDelete else { return }

        guard !category.isDefault else {
            errorMessage = "デフォルトカテゴリはアーカイブできません。"
            categoryToDelete = nil
            return
        }

        dataStore.archiveCategory(id: category.id)
        categoryToDelete = nil
    }

    // MARK: - Helpers

    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

// MARK: - Preview

#Preview {
    CategoryManageView()
        .environment(DataStore(modelContext: try! ModelContext(ModelContainer(for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self))))
}
