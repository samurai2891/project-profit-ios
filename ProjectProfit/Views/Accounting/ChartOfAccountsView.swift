import SwiftData
import SwiftUI

struct ChartOfAccountsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var accounts: [CanonicalAccount] = []
    @State private var formSnapshot: TransactionFormSnapshot = .empty
    @State private var isLoading = false
    @State private var loadErrorMessage: String?
    @State private var showAddForm = false
    @State private var editingAccount: CanonicalAccount?
    @State private var archiveTargetAccount: CanonicalAccount?

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
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        if legacyMetadata(for: account)?.isSystem != true {
                                            Button {
                                                archiveTargetAccount = account
                                            } label: {
                                                Label(
                                                    account.archivedAt == nil ? "無効化" : "有効化",
                                                    systemImage: account.archivedAt == nil
                                                        ? "archivebox" : "arrow.uturn.backward"
                                                )
                                            }
                                            .tint(account.archivedAt == nil ? AppColors.warning : AppColors.success)
                                        }

                                        Button {
                                            editingAccount = account
                                        } label: {
                                            Label("編集", systemImage: "pencil")
                                        }
                                        .tint(AppColors.primary)
                                    }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("勘定科目を追加")
            }
        }
        .task {
            await loadAccounts()
        }
        .refreshable {
            await loadAccounts()
        }
        .sheet(isPresented: $showAddForm) {
            Task { await loadAccounts() }
        } content: {
            NavigationStack {
                AccountFormView(account: nil) {
                    showAddForm = false
                    Task { await loadAccounts() }
                }
            }
        }
        .sheet(item: $editingAccount) { account in
            NavigationStack {
                AccountFormView(account: account) {
                    editingAccount = nil
                    Task { await loadAccounts() }
                }
            }
        }
        .alert("勘定科目の状態変更", isPresented: Binding(
            get: { archiveTargetAccount != nil },
            set: { if !$0 { archiveTargetAccount = nil } }
        )) {
            Button("キャンセル", role: .cancel) { archiveTargetAccount = nil }
            Button(archiveTargetAccount?.archivedAt == nil ? "無効化" : "有効化") {
                if let account = archiveTargetAccount {
                    Task { await toggleArchive(account) }
                }
            }
        } message: {
            if let account = archiveTargetAccount {
                Text(
                    account.archivedAt == nil
                        ? "「\(account.name)」を無効化しますか？"
                        : "「\(account.name)」を有効化しますか？"
                )
            }
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
        let snapshot: TransactionFormSnapshot
        do {
            snapshot = try TransactionFormQueryUseCase(modelContext: modelContext).snapshot()
        } catch {
            accounts = []
            formSnapshot = .empty
            loadErrorMessage = error.localizedDescription
            return
        }

        formSnapshot = snapshot

        guard let businessId = snapshot.businessId else {
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

    private func toggleArchive(_ account: CanonicalAccount) async {
        let updated = account.updated(
            archivedAt: .some(account.archivedAt == nil ? Date() : nil)
        )
        do {
            try await ChartOfAccountsUseCase(modelContext: modelContext).save(updated)
            await loadAccounts()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    private func legacyMetadata(for account: CanonicalAccount) -> PPAccount? {
        guard let legacyAccountId = account.legacyAccountId else {
            return nil
        }
        return formSnapshot.accounts.first { $0.id == legacyAccountId }
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
