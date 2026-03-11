import SwiftUI

struct CategoryAccountMappingView: View {
    @Environment(DataStore.self) private var dataStore

    private var categoryWorkflowUseCase: CategoryWorkflowUseCase {
        CategoryWorkflowUseCase(dataStore: dataStore)
    }

    private var expenseCategories: [PPCategory] {
        dataStore.categories.filter { $0.type == .expense }
    }

    private var incomeCategories: [PPCategory] {
        dataStore.categories.filter { $0.type == .income }
    }

    private var expenseAccounts: [PPAccount] {
        dataStore.accounts.filter { $0.accountType == .expense && $0.isActive }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    private var revenueAccounts: [PPAccount] {
        dataStore.accounts.filter { $0.accountType == .revenue && $0.isActive }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    var body: some View {
        List {
            Section("経費カテゴリ") {
                ForEach(expenseCategories, id: \.id) { category in
                    mappingRow(category: category, availableAccounts: expenseAccounts)
                }
            }

            Section("収益カテゴリ") {
                ForEach(incomeCategories, id: \.id) { category in
                    mappingRow(category: category, availableAccounts: revenueAccounts)
                }
            }
        }
        .navigationTitle("カテゴリ紐付け")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func mappingRow(category: PPCategory, availableAccounts: [PPAccount]) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.subheadline)
                if let linkedId = category.linkedAccountId,
                   let account = dataStore.accounts.first(where: { $0.id == linkedId }) {
                    Text("\(account.code) \(account.name)")
                        .font(.caption)
                        .foregroundStyle(AppColors.primary)
                } else {
                    Text("未設定")
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                }
            }

            Spacer()

            Menu {
                Button("未設定") {
                    _ = categoryWorkflowUseCase.updateLinkedAccount(categoryId: category.id, accountId: nil)
                }

                ForEach(availableAccounts, id: \.id) { account in
                    Button("\(account.code) \(account.name)") {
                        _ = categoryWorkflowUseCase.updateLinkedAccount(categoryId: category.id, accountId: account.id)
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(AppColors.primary)
            }
        }
    }
}
