import SwiftData
import SwiftUI

// MARK: - CategoryListView

struct CategoryListView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var editingCategoryID: String?
    @State private var editingName = ""
    @State private var newCategoryName = ""
    @State private var newCategoryType: CategoryType = .expense
    @State private var showAddSheet = false
    @State private var showArchiveConfirmation = false
    @State private var categoryToArchive: PPCategory?
    @State private var errorMessage: String?

    // MARK: - Filtered Data

    private var expenseCategories: [PPCategory] {
        filterCategories(type: .expense, archived: false)
    }

    private var incomeCategories: [PPCategory] {
        filterCategories(type: .income, archived: false)
    }

    private var archivedCategories: [PPCategory] {
        let archived = dataStore.categories.filter { $0.archivedAt != nil }
        return applySearchFilter(to: archived)
    }

    var body: some View {
        List {
            if expenseCategories.isEmpty && incomeCategories.isEmpty && archivedCategories.isEmpty {
                ContentUnavailableView(
                    "カテゴリが登録されていません",
                    systemImage: "chart.pie",
                    description: Text("右上の＋ボタンからカテゴリを追加できます")
                )
            } else {
                expenseCategorySection
                incomeCategorySection
                if !archivedCategories.isEmpty {
                    archivedCategorySection
                }
            }
        }
        .navigationTitle("カテゴリ管理")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "カテゴリ名で検索")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("カテゴリを追加")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            CategoryAddSheet(
                onSave: { name, type in
                    saveNewCategory(name: name, type: type)
                }
            )
        }
        .alert("カテゴリをアーカイブ", isPresented: $showArchiveConfirmation) {
            Button("アーカイブ", role: .destructive) {
                performArchive()
            }
            Button("キャンセル", role: .cancel) {
                categoryToArchive = nil
            }
        } message: {
            if let category = categoryToArchive {
                Text("「\(category.name)」をアーカイブしますか？新規取引では選択できなくなりますが、既存の取引はそのまま保持されます。")
            }
        }
        .alert("エラー", isPresented: showErrorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Expense Category Section

    private var expenseCategorySection: some View {
        Section {
            ForEach(expenseCategories) { category in
                categoryRow(for: category)
            }
        } header: {
            HStack {
                Text("経費カテゴリ")
                Spacer()
                Text("\(expenseCategories.count)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Income Category Section

    private var incomeCategorySection: some View {
        Section {
            ForEach(incomeCategories) { category in
                categoryRow(for: category)
            }
        } header: {
            HStack {
                Text("収益カテゴリ")
                Spacer()
                Text("\(incomeCategories.count)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Archived Section

    private var archivedCategorySection: some View {
        Section {
            ForEach(archivedCategories) { category in
                HStack(spacing: 12) {
                    Image(systemName: category.icon)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .foregroundStyle(.secondary)
                        Text(category.type == .expense ? "経費" : "収益")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

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
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .foregroundStyle(.primary)
                if category.isDefault {
                    Text("デフォルト")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.primary.opacity(0.6))
                        .clipShape(Capsule())
                }
            }

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
                    categoryToArchive = category
                    showArchiveConfirmation = true
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

    // MARK: - Actions

    private func filterCategories(type: CategoryType, archived: Bool) -> [PPCategory] {
        let base = dataStore.categories.filter {
            $0.type == type && (archived ? $0.archivedAt != nil : $0.archivedAt == nil)
        }
        return applySearchFilter(to: base)
    }

    private func applySearchFilter(to categories: [PPCategory]) -> [PPCategory] {
        guard !searchText.isEmpty else { return categories }
        let query = searchText.lowercased()
        return categories.filter { $0.name.lowercased().contains(query) }
    }

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
    }

    private func performArchive() {
        guard let category = categoryToArchive else { return }

        guard !category.isDefault else {
            errorMessage = "デフォルトカテゴリはアーカイブできません。"
            categoryToArchive = nil
            return
        }

        dataStore.archiveCategory(id: category.id)
        categoryToArchive = nil
    }

    // MARK: - Helpers

    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

// MARK: - CategoryAddSheet

private struct CategoryAddSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: CategoryType = .expense

    let onSave: (String, CategoryType) -> Void

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本情報") {
                    TextField("カテゴリ名（必須）", text: $name)

                    Picker("種別", selection: $type) {
                        Text("経費").tag(CategoryType.expense)
                        Text("収益").tag(CategoryType.income)
                    }
                }
            }
            .navigationTitle("カテゴリを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(name, type)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
