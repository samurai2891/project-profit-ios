import SwiftUI

struct ChartOfAccountsView: View {
    @Environment(DataStore.self) private var dataStore

    private var groupedAccounts: [(AccountType, [PPAccount])] {
        let grouped = Dictionary(grouping: dataStore.accounts) { $0.accountType }
        return AccountType.allCases.compactMap { type in
            guard let items = grouped[type], !items.isEmpty else { return nil }
            return (type, items.sorted { $0.displayOrder < $1.displayOrder })
        }
    }

    var body: some View {
        List {
            ForEach(groupedAccounts, id: \.0) { accountType, accounts in
                Section {
                    ForEach(accounts, id: \.id) { account in
                        accountRow(account)
                    }
                } header: {
                    HStack {
                        Text(accountType.label)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("正常残高: \(accountType.normalBalance.label)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("勘定科目一覧")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func accountRow(_ account: PPAccount) -> some View {
        HStack {
            Text(account.code)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(account.name)
                        .font(.subheadline)
                    if account.isSystem {
                        Text("システム")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.primary.opacity(0.6))
                            .clipShape(Capsule())
                    }
                }

                if let subtype = account.subtype {
                    Text(subtype.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !account.isActive {
                Text("無効")
                    .font(.caption)
                    .foregroundStyle(AppColors.error)
            }
        }
        .opacity(account.isActive ? 1 : 0.5)
    }
}
