import SwiftUI

/// 再利用可能な勘定科目ピッカー
struct AccountPickerView: View {
    let label: String
    let accounts: [PPAccount]
    @Binding var selectedAccountId: String?
    var filterPredicate: ((PPAccount) -> Bool)?

    private var filteredAccounts: [PPAccount] {
        if let filterPredicate {
            return accounts.filter(filterPredicate)
        }
        return accounts
    }

    private var groupedAccounts: [(AccountType, [PPAccount])] {
        let grouped = Dictionary(grouping: filteredAccounts) { $0.accountType }
        return AccountType.allCases.compactMap { type in
            guard let items = grouped[type], !items.isEmpty else { return nil }
            return (type, items.sorted { $0.displayOrder < $1.displayOrder })
        }
    }

    private var selectedAccountName: String {
        if let id = selectedAccountId,
           let account = accounts.first(where: { $0.id == id }) {
            return "\(account.code) \(account.name)"
        }
        return "選択してください"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                Button("未設定") {
                    selectedAccountId = nil
                }

                ForEach(groupedAccounts, id: \.0) { accountType, items in
                    Section(accountType.label) {
                        ForEach(items, id: \.id) { account in
                            Button {
                                selectedAccountId = account.id
                            } label: {
                                HStack {
                                    Text("\(account.code) \(account.name)")
                                    if selectedAccountId == account.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedAccountName)
                        .font(.subheadline)
                        .foregroundStyle(selectedAccountId != nil ? .primary : .secondary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }
            .accessibilityLabel(label)
            .accessibilityValue(selectedAccountName)
        }
    }
}
