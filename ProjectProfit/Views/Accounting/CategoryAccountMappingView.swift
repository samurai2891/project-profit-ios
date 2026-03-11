import SwiftUI

struct CategoryAccountMappingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var categorySnapshot: CategorySnapshot = .empty

    private var categoryWorkflowUseCase: CategoryWorkflowUseCase {
        CategoryWorkflowUseCase(modelContext: modelContext)
    }

    private var categoryQueryUseCase: CategoryQueryUseCase {
        CategoryQueryUseCase(modelContext: modelContext)
    }

    private var expenseCategories: [PPCategory] {
        categoryQueryUseCase.categories(
            type: .expense,
            archived: false,
            snapshot: categorySnapshot
        )
    }

    private var incomeCategories: [PPCategory] {
        categoryQueryUseCase.categories(
            type: .income,
            archived: false,
            snapshot: categorySnapshot
        )
    }

    private var expenseAccounts: [PPAccount] {
        categoryQueryUseCase.accounts(
            for: .expense,
            snapshot: categorySnapshot
        )
    }

    private var revenueAccounts: [PPAccount] {
        categoryQueryUseCase.accounts(
            for: .income,
            snapshot: categorySnapshot
        )
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
        .task {
            refreshSnapshot()
        }
    }

    private func mappingRow(category: PPCategory, availableAccounts: [PPAccount]) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.subheadline)
                if let account = categoryQueryUseCase.linkedAccount(
                    for: category,
                    snapshot: categorySnapshot
                ) {
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
                    refreshSnapshot()
                }

                ForEach(availableAccounts, id: \.id) { account in
                    Button("\(account.code) \(account.name)") {
                        _ = categoryWorkflowUseCase.updateLinkedAccount(categoryId: category.id, accountId: account.id)
                        refreshSnapshot()
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(AppColors.primary)
            }
        }
    }

    private func refreshSnapshot() {
        categorySnapshot = categoryQueryUseCase.snapshot()
    }
}
