import SwiftData
import SwiftUI

struct ChartOfAccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DataStore.self) private var dataStore

    @State private var accounts: [CanonicalAccount] = []
    @State private var isLoading = false
    @State private var loadErrorMessage: String?

    private var groupedAccounts: [(CanonicalAccountType, [CanonicalAccount])] {
        let grouped = Dictionary(grouping: accounts) { $0.accountType }
        return CanonicalAccountType.allCases.compactMap { type in
            guard let items = grouped[type], !items.isEmpty else {
                return nil
            }
            return (type, items.sorted { lhs, rhs in
                if lhs.displayOrder == rhs.displayOrder {
                    return lhs.code < rhs.code
                }
                return lhs.displayOrder < rhs.displayOrder
            })
        }
    }

    var body: some View {
        Group {
            if isLoading && accounts.isEmpty {
                ProgressView("勘定科目を読み込み中...")
            } else if let loadErrorMessage, accounts.isEmpty {
                ContentUnavailableView(
                    "勘定科目を読み込めません",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadErrorMessage)
                )
            } else {
                List {
                    ForEach(groupedAccounts, id: \.0) { accountType, items in
                        Section {
                            ForEach(items, id: \.id) { account in
                                accountRow(account)
                            }
                        } header: {
                            HStack {
                                Text(accountType.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("正常残高: \(headerNormalBalanceLabel(for: accountType))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .overlay {
                    if isLoading && !accounts.isEmpty {
                        ProgressView()
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .navigationTitle("勘定科目一覧")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: dataStore.businessProfile?.id) {
            await loadAccounts()
        }
        .refreshable {
            await loadAccounts()
        }
    }

    @ViewBuilder
    private func accountRow(_ account: CanonicalAccount) -> some View {
        let legacyAccount = legacyMetadata(for: account)

        HStack {
            Text(account.code)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(account.name)
                        .font(.subheadline)
                    if legacyAccount?.isSystem == true {
                        Text("システム")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.primary.opacity(0.6))
                            .clipShape(Capsule())
                    }
                }

                if let subtype = legacyAccount?.subtype {
                    Text(subtype.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let legacyAccountId = account.legacyAccountId {
                    Text(legacyAccountId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if account.archivedAt != nil {
                Text("無効")
                    .font(.caption)
                    .foregroundStyle(AppColors.error)
            }
        }
        .opacity(account.archivedAt == nil ? 1 : 0.5)
    }

    private func loadAccounts() async {
        guard let businessId = dataStore.businessProfile?.id else {
            accounts = []
            loadErrorMessage = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            accounts = try await ChartOfAccountsUseCase(modelContext: modelContext).accounts(businessId: businessId)
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    private func legacyMetadata(for account: CanonicalAccount) -> PPAccount? {
        guard let legacyAccountId = account.legacyAccountId else {
            return nil
        }
        return dataStore.getAccount(id: legacyAccountId)
    }

    private func headerNormalBalanceLabel(for accountType: CanonicalAccountType) -> String {
        switch accountType {
        case .asset, .expense:
            return NormalBalance.debit.label
        case .liability, .equity, .revenue:
            return NormalBalance.credit.label
        }
    }
}
