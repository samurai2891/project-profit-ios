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
        dataStore.categories.filter { $0.type == .expense }
    }

    private var incomeCategories: [PPCategory] {
        dataStore.categories.filter { $0.type == .income }
    }

    var body: some View {
        NavigationStack {
            Form {
                expenseCategorySection
                incomeCategorySection
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
            .alert("カテゴリを削除", isPresented: $showDeleteConfirmation) {
                Button("削除", role: .destructive) {
                    performDelete()
                }
                Button("キャンセル", role: .cancel) {
                    categoryToDelete = nil
                }
            } message: {
                if let category = categoryToDelete {
                    Text("「\(category.name)」を削除しますか？この操作は取り消せません。")
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
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
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

        dataStore.updateCategory(id: category.id, name: trimmedName)
        cancelEditing()
    }

    private func saveNewCategory(name: String, type: CategoryType) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty else {
            errorMessage = "カテゴリ名を入力してください。"
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
            errorMessage = "デフォルトカテゴリは削除できません。"
            categoryToDelete = nil
            return
        }

        dataStore.deleteCategory(id: category.id)
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
