import SwiftUI

struct LedgerView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var selectedAccountId: String?

    private var activeAccounts: [PPAccount] {
        dataStore.accounts.filter(\.isActive).sorted { $0.displayOrder < $1.displayOrder }
    }

    private var groupedAccounts: [(AccountType, [PPAccount])] {
        let grouped = Dictionary(grouping: activeAccounts) { $0.accountType }
        return AccountType.allCases.compactMap { type in
            guard let items = grouped[type], !items.isEmpty else { return nil }
            return (type, items)
        }
    }

    var body: some View {
        Group {
            if let accountId = selectedAccountId {
                ledgerDetail(accountId: accountId)
            } else {
                accountSelector
            }
        }
        .navigationTitle("総勘定元帳")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Account Selector

    private var accountSelector: some View {
        List {
            ForEach(groupedAccounts, id: \.0) { accountType, accounts in
                Section(accountType.label) {
                    ForEach(accounts, id: \.id) { account in
                        Button {
                            selectedAccountId = account.id
                        } label: {
                            HStack {
                                Text(account.code)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .leading)
                                Text(account.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()

                                let balance = dataStore.getAccountBalance(accountId: account.id)
                                Text(formatCurrency(balance.balance))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(balance.balance >= 0 ? .primary : AppColors.error)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Ledger Detail

    private func ledgerDetail(accountId: String) -> some View {
        let entries = dataStore.getLedgerEntries(accountId: accountId)
        let account = dataStore.accounts.first { $0.id == accountId }
        let accountName = account.map { "\($0.code) \($0.name)" } ?? accountId

        return VStack(spacing: 0) {
            // Account header
            HStack {
                Button {
                    selectedAccountId = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("戻る")
                    }
                    .font(.subheadline)
                    .foregroundStyle(AppColors.primary)
                }

                Spacer()

                Text(accountName)
                    .font(.subheadline.weight(.medium))

                Spacer()

                let balance = dataStore.getAccountBalance(accountId: accountId)
                Text("残高: \(formatCurrency(balance.balance))")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppColors.surface)

            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("取引がありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Column headers
                    HStack {
                        Text("日付")
                            .frame(width: 60, alignment: .leading)
                        Text("摘要")
                        Spacer()
                        Text("借方")
                            .frame(width: 65, alignment: .trailing)
                        Text("貸方")
                            .frame(width: 65, alignment: .trailing)
                        Text("残高")
                            .frame(width: 70, alignment: .trailing)
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                    ForEach(entries) { entry in
                        ledgerRow(entry)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func ledgerRow(_ entry: DataStore.LedgerEntry) -> some View {
        HStack {
            Text(shortDate(entry.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(entry.memo.isEmpty ? entry.entryType.label : entry.memo)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Text(entry.debit > 0 ? formatCurrency(entry.debit) : "")
                .font(.caption)
                .frame(width: 65, alignment: .trailing)

            Text(entry.credit > 0 ? formatCurrency(entry.credit) : "")
                .font(.caption)
                .frame(width: 65, alignment: .trailing)

            Text(formatCurrency(entry.runningBalance))
                .font(.caption.weight(.medium))
                .frame(width: 70, alignment: .trailing)
        }
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
}
