import SwiftData
import SwiftUI

struct BooksWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext

    enum WorkflowDestinationID: String, Equatable {
        case reconciliation
        case journalBrowser
        case analytics
    }

    enum LegacyLedgerDestinationID: String, Equatable {
        case transportationExpense
        case compatibilityHome
    }

    enum ReleaseBookDestinationID: String, Equatable {
        case journalBook
        case generalLedger
        case cashBook
        case depositBook
        case accountsReceivableBook
        case accountsPayableBook
        case expenseBook
        case fixedAssetLedger
        case inventoryLedger
        case whiteTaxBookkeeping
    }

    struct WorkflowItem: Equatable {
        let icon: String
        let title: String
        let subtitle: String
        let destinationID: WorkflowDestinationID
    }

    struct LegacyLedgerItem: Equatable {
        let icon: String
        let title: String
        let subtitle: String
        let destinationID: LegacyLedgerDestinationID
    }

    struct ReleaseBookItem: Equatable {
        let icon: String
        let title: String
        let subtitle: String
        let destinationID: ReleaseBookDestinationID
    }

    static let reconciliationTitle = BankCardReconciliationView.titleText
    static let reconciliationSubtitle = "明細取込と未照合チェック"
    static let analyticsTitle = "分析レポート"
    static let analyticsSubtitle = "収益・費用・月別推移を確認"
    static let releaseBookItems: [ReleaseBookItem] = [
        ReleaseBookItem(
            icon: "book.pages",
            title: "仕訳帳",
            subtitle: "仕訳一覧から日付・摘要・勘定を確認",
            destinationID: .journalBook
        ),
        ReleaseBookItem(
            icon: "book.closed.fill",
            title: "総勘定元帳",
            subtitle: "勘定科目別の取引履歴",
            destinationID: .generalLedger
        ),
        ReleaseBookItem(
            icon: "banknote",
            title: "現金出納帳",
            subtitle: "現金勘定の増減明細",
            destinationID: .cashBook
        ),
        ReleaseBookItem(
            icon: "building.columns",
            title: "預金出納帳",
            subtitle: "預金勘定の入出金と残高推移",
            destinationID: .depositBook
        ),
        ReleaseBookItem(
            icon: "creditcard.and.123",
            title: "売掛帳",
            subtitle: "売掛金の増減明細",
            destinationID: .accountsReceivableBook
        ),
        ReleaseBookItem(
            icon: "cart.badge.minus",
            title: "買掛帳",
            subtitle: "買掛金の増減明細",
            destinationID: .accountsPayableBook
        ),
        ReleaseBookItem(
            icon: "chart.bar.xaxis",
            title: "経費帳",
            subtitle: "費用科目の明細",
            destinationID: .expenseBook
        ),
        ReleaseBookItem(
            icon: "shippingbox",
            title: "固定資産台帳",
            subtitle: "固定資産の取得・償却状況",
            destinationID: .fixedAssetLedger
        ),
        ReleaseBookItem(
            icon: "cart",
            title: "棚卸台帳",
            subtitle: "棚卸高・仕入高・売上原価の管理",
            destinationID: .inventoryLedger
        ),
        ReleaseBookItem(
            icon: "text.book.closed",
            title: "白色簡易帳簿",
            subtitle: "白色申告向けの収支集計を確認",
            destinationID: .whiteTaxBookkeeping
        ),
    ]
    static let workflowItems: [WorkflowItem] = [
        WorkflowItem(
            icon: "building.columns.circle",
            title: reconciliationTitle,
            subtitle: reconciliationSubtitle,
            destinationID: .reconciliation
        ),
        WorkflowItem(
            icon: "book.closed",
            title: "仕訳ブラウザ",
            subtitle: "Canonical仕訳の検索・確認",
            destinationID: .journalBrowser
        ),
        WorkflowItem(
            icon: "chart.line.uptrend.xyaxis",
            title: analyticsTitle,
            subtitle: analyticsSubtitle,
            destinationID: .analytics
        ),
    ]
    static let legacyLedgerItems: [LegacyLedgerItem] = [
        LegacyLedgerItem(
            icon: "tram",
            title: "交通費精算書（互換）",
            subtitle: "旧台帳の交通費精算書を参照",
            destinationID: .transportationExpense
        ),
        LegacyLedgerItem(
            icon: "books.vertical",
            title: "旧台帳一覧",
            subtitle: "互換台帳を読み取り専用で参照",
            destinationID: .compatibilityHome
        ),
    ]

    @State private var snapshot = AccountingHomeSnapshot(
        unpostedJournalCount: 0,
        suspenseBalance: 0,
        totalAccounts: 0,
        totalJournalEntries: 0,
        isBootstrapped: false
    )

    static let titleText = "帳簿ワークスペース"
    static let descriptionText = "未照合の確認から仕訳・帳簿・分析・申告準備まで、この画面から今やる作業を順にたどれます。"

    private var queryUseCase: AccountingHomeQueryUseCase {
        AccountingHomeQueryUseCase(modelContext: modelContext)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                introductionCard
                statusCard
                workflowSection
                releaseBooksSection
                reportsSection
                assetManagementSection
                filingSection
                legacyLedgerSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .navigationTitle(Self.titleText)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshSnapshot()
        }
        .refreshable {
            refreshSnapshot()
        }
    }

    private var introductionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(Self.titleText, systemImage: "books.vertical")
                .font(.headline)
                .foregroundStyle(AppColors.primary)

            Text(Self.descriptionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusAccentColor)
                Text("会計ステータス")
                    .font(.headline)
            }

            Text(statusSummary)
                .font(.subheadline)
                .foregroundStyle(statusSummaryColor)

            HStack(spacing: 20) {
                statusMetric(label: "未投稿仕訳", value: "\(snapshot.unpostedJournalCount)件")
                statusMetric(label: "仮勘定残高", value: formatCurrency(snapshot.suspenseBalance))
            }

            HStack(spacing: 20) {
                statusMetric(label: "勘定科目", value: "\(snapshot.totalAccounts)")
                statusMetric(label: "仕訳数", value: "\(snapshot.totalJournalEntries)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var workflowSection: some View {
        section(
            title: "帳簿ワークフロー",
            rows: Self.workflowItems.map(workflowRow)
        )
    }

    private var releaseBooksSection: some View {
        section(
            title: "帳簿・台帳",
            rows: Self.releaseBookItems.map(releaseBookRow)
        )
    }

    private var reportsSection: some View {
        section(
            title: "帳票・集計",
            rows: [
                WorkspaceRow(
                    icon: "calendar.badge.clock",
                    title: "月別総括集計表",
                    subtitle: "月別の売上・仕入・経費集計",
                    destination: AnyView(MonthlySummaryView())
                ),
                WorkspaceRow(
                    icon: "tablecells",
                    title: "試算表",
                    subtitle: "勘定科目の残高一覧",
                    destination: AnyView(TrialBalanceView())
                ),
                WorkspaceRow(
                    icon: "chart.bar.doc.horizontal",
                    title: "損益計算書",
                    subtitle: "収益と費用の集計",
                    destination: AnyView(ProfitLossView())
                ),
                WorkspaceRow(
                    icon: "chart.pie",
                    title: "貸借対照表",
                    subtitle: "資産・負債・資本の状況",
                    destination: AnyView(BalanceSheetView())
                ),
            ]
        )
    }

    private var assetManagementSection: some View {
        section(
            title: "資産・補助管理",
            rows: [
                WorkspaceRow(
                    icon: "tablecells.badge.ellipsis",
                    title: "減価償却明細表",
                    subtitle: "全固定資産の減価償却スケジュール",
                    destination: AnyView(FixedAssetScheduleView())
                ),
                WorkspaceRow(
                    icon: "archivebox",
                    title: "書類台帳",
                    subtitle: "法定書類の保存管理",
                    destination: AnyView(LegalDocumentLedgerView())
                ),
            ]
        )
    }

    private var filingSection: some View {
        section(
            title: "設定・申告",
            rows: [
                WorkspaceRow(
                    icon: "list.bullet.rectangle",
                    title: "勘定科目一覧",
                    subtitle: "勘定科目の管理",
                    destination: AnyView(ChartOfAccountsView())
                ),
                WorkspaceRow(
                    icon: "arrow.left.arrow.right",
                    title: "カテゴリ紐付け",
                    subtitle: "カテゴリと勘定科目の対応設定",
                    destination: AnyView(CategoryAccountMappingView())
                ),
                WorkspaceRow(
                    icon: "doc.badge.gearshape",
                    title: "決算仕訳",
                    subtitle: "締め処理前の最終確認と仕訳生成",
                    destination: AnyView(ClosingEntryView())
                ),
                WorkspaceRow(
                    icon: "square.and.arrow.up",
                    title: "e-Tax出力",
                    subtitle: "確定申告データの出力",
                    destination: AnyView(EtaxExportView())
                ),
            ]
        )
    }

    private func workflowRow(_ item: Self.WorkflowItem) -> WorkspaceRow {
        WorkspaceRow(
            icon: item.icon,
            title: item.title,
            subtitle: item.subtitle,
            destination: workflowDestination(for: item.destinationID)
        )
    }

    private func workflowDestination(for destinationID: Self.WorkflowDestinationID) -> AnyView {
        switch destinationID {
        case .reconciliation:
            AnyView(BankCardReconciliationView())
        case .journalBrowser:
            AnyView(JournalBrowserView())
        case .analytics:
            AnyView(ReportView())
        }
    }

    private func releaseBookRow(_ item: Self.ReleaseBookItem) -> WorkspaceRow {
        WorkspaceRow(
            icon: item.icon,
            title: item.title,
            subtitle: item.subtitle,
            destination: releaseBookDestination(for: item.destinationID)
        )
    }

    private func releaseBookDestination(for destinationID: Self.ReleaseBookDestinationID) -> AnyView {
        switch destinationID {
        case .journalBook:
            AnyView(JournalBrowserView())
        case .generalLedger:
            AnyView(LedgerView())
        case .cashBook:
            AnyView(SubLedgerView(type: .cashBook))
        case .depositBook:
            AnyView(SubLedgerView(type: .depositBook))
        case .accountsReceivableBook:
            AnyView(SubLedgerView(type: .accountsReceivableBook))
        case .accountsPayableBook:
            AnyView(SubLedgerView(type: .accountsPayableBook))
        case .expenseBook:
            AnyView(SubLedgerView(type: .expenseBook))
        case .fixedAssetLedger:
            AnyView(FixedAssetListView())
        case .inventoryLedger:
            AnyView(InventoryInputView())
        case .whiteTaxBookkeeping:
            AnyView(WhiteTaxBookkeepingView())
        }
    }

    private var legacyLedgerSection: some View {
        section(
            title: "旧台帳アーカイブ",
            rows: Self.legacyLedgerItems.map(legacyLedgerRow)
        )
    }

    private func legacyLedgerRow(_ item: Self.LegacyLedgerItem) -> WorkspaceRow {
        WorkspaceRow(
            icon: item.icon,
            title: item.title,
            subtitle: item.subtitle,
            destination: legacyLedgerDestination(for: item.destinationID)
        )
    }

    private func legacyLedgerDestination(for destinationID: Self.LegacyLedgerDestinationID) -> AnyView {
        switch destinationID {
        case .transportationExpense:
            AnyView(
                LegacyLedgerFilteredContainerView(
                    title: "交通費精算書",
                    emptyMessage: "交通費精算書はまだ作成されていません",
                    ledgerTypes: [.transportationExpense]
                )
            )
        case .compatibilityHome:
            AnyView(LegacyLedgerHomeContainerView())
        }
    }

    private func section(title: String, rows: [WorkspaceRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 8) {
                ForEach(rows) { row in
                    NavigationLink {
                        row.destination
                    } label: {
                        rowView(row)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rowView(_ row: WorkspaceRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.icon)
                .font(.body)
                .foregroundStyle(AppColors.primary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(row.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statusMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
    }

    private func refreshSnapshot() {
        snapshot = queryUseCase.snapshot()
    }

    private var hasWarnings: Bool {
        snapshot.unpostedJournalCount > 0 || snapshot.suspenseBalance != 0
    }

    private var statusSymbol: String {
        if !snapshot.isBootstrapped {
            return "exclamationmark.triangle.fill"
        }
        return hasWarnings ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var statusAccentColor: Color {
        if !snapshot.isBootstrapped {
            return AppColors.warning
        }
        return hasWarnings ? AppColors.warning : AppColors.success
    }

    private var statusSummaryColor: Color {
        if !snapshot.isBootstrapped || hasWarnings {
            return AppColors.warning
        }
        return .secondary
    }

    private var statusSummary: String {
        if !snapshot.isBootstrapped {
            return "会計機能が未初期化です"
        }
        if !hasWarnings {
            return "正常"
        }

        var warnings: [String] = []
        if snapshot.unpostedJournalCount > 0 {
            warnings.append("未投稿仕訳: \(snapshot.unpostedJournalCount)件")
        }
        if snapshot.suspenseBalance != 0 {
            warnings.append("仮勘定残高: \(formatCurrency(snapshot.suspenseBalance))")
        }
        return warnings.joined(separator: " / ")
    }
}

private struct WorkspaceRow: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let destination: AnyView

    init(icon: String, title: String, subtitle: String, destination: AnyView) {
        self.id = title
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.destination = destination
    }
}

private struct LegacyLedgerHomeContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var ledgerStore: LedgerDataStore?

    var body: some View {
        Group {
            if let ledgerStore {
                LedgerHomeView()
                    .environment(ledgerStore)
            } else {
                ProgressView("読み込み中...")
            }
        }
        .task {
            if ledgerStore == nil {
                ledgerStore = LedgerDataStore(
                    modelContext: modelContext,
                    accessMode: .readOnly
                )
            }
        }
    }
}

private struct LegacyLedgerFilteredContainerView: View {
    @Environment(\.modelContext) private var modelContext

    let title: String
    let emptyMessage: String
    let ledgerTypes: [LedgerType]

    @State private var ledgerStore: LedgerDataStore?

    private func filteredBooks(from ledgerStore: LedgerDataStore) -> [SDLedgerBook] {
        ledgerStore.books.filter { book in
            guard let ledgerType = book.ledgerType else {
                return false
            }
            return ledgerTypes.contains(ledgerType)
        }
    }

    var body: some View {
        Group {
            if let ledgerStore {
                let books = filteredBooks(from: ledgerStore)
                if books.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "book.closed")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(emptyMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(books, id: \.id) { book in
                            NavigationLink(destination: LedgerBookDetailView(bookId: book.id)) {
                                legacyBookRow(book: book, ledgerStore: ledgerStore)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .environment(ledgerStore)
                }
            } else {
                ProgressView("読み込み中...")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if ledgerStore == nil {
                ledgerStore = LedgerDataStore(
                    modelContext: modelContext,
                    accessMode: .readOnly
                )
            }
        }
    }

    private func legacyBookRow(book: SDLedgerBook, ledgerStore: LedgerDataStore) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(book.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if book.includeInvoice {
                    Text("インボイス")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.primary.opacity(0.15))
                        .foregroundStyle(AppColors.primary)
                        .clipShape(Capsule())
                }
            }

            HStack {
                Text(book.ledgerType?.displayName ?? "不明")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let balance = ledgerStore.finalBalance(for: book.id) {
                    Text("残高: \(formatCurrency(balance))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text("更新: \(book.updatedAt, format: .dateTime.month().day().hour().minute())")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
