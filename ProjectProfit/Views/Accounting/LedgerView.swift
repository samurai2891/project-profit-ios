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
        .toolbar {
            if let accountId = selectedAccountId,
               let account = dataStore.accounts.first(where: { $0.id == accountId }) {
                ToolbarItem(placement: .primaryAction) {
                    ExportMenuButton(
                        target: .ledger,
                        fiscalYear: currentFiscalYear(startMonth: FiscalYearSettings.startMonth),
                        dataStore: dataStore,
                        ledgerOptions: ExportCoordinator.LedgerExportOptions(
                            accountId: account.id,
                            accountName: account.name,
                            accountCode: account.code
                        )
                    )
                }
            }
        }
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
                                    .font(.subheadline.weight(.medium).monospacedDigit())
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
                    .font(.caption.weight(.medium).monospacedDigit())
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
                            .frame(width: 70, alignment: .leading)
                        Text("摘要")
                        Spacer()
                        Text("借方")
                            .frame(width: 80, alignment: .trailing)
                        Text("貸方")
                            .frame(width: 80, alignment: .trailing)
                        Text("残高")
                            .frame(width: 85, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        ledgerRow(entry)
                            .listRowBackground(
                                index.isMultiple(of: 2)
                                    ? Color(.systemBackground)
                                    : AppColors.surface.opacity(0.5)
                            )
                    }

                    // 消費税マーク凡例
                    if entries.contains(where: { $0.taxCategory == .reducedRate }) {
                        Section {
                            Text("※は軽減税率対象")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func ledgerRow(_ entry: DataStore.LedgerEntry) -> some View {
        HStack {
            Text(shortDate(entry.date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Text(ledgerDescription(entry))
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            CurrencyText(
                amount: entry.debit,
                font: .subheadline,
                emptyWhenZero: true
            )
            .frame(width: 80, alignment: .trailing)

            CurrencyText(
                amount: entry.credit,
                font: .subheadline,
                emptyWhenZero: true
            )
            .frame(width: 80, alignment: .trailing)

            CurrencyText(
                amount: entry.runningBalance,
                font: .subheadline.weight(.medium)
            )
            .frame(width: 85, alignment: .trailing)
        }
    }

    /// 摘要テキスト: [取引先] メモ ※
    private func ledgerDescription(_ entry: DataStore.LedgerEntry) -> String {
        var parts: [String] = []
        if let cp = entry.counterparty, !cp.isEmpty {
            parts.append("[\(cp)]")
        }
        let memo = entry.memo.isEmpty ? entry.entryType.label : entry.memo
        parts.append(memo)
        if entry.taxCategory == .reducedRate {
            parts.append("※")
        }
        return parts.joined(separator: " ")
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        return f
    }()

    private func shortDate(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
    }
}
