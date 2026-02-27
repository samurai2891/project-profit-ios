import SwiftUI

struct AccountingHomeView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var viewModel: AccountingHomeViewModel?

    var body: some View {
        Group {
            if let viewModel {
                accountingContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            if viewModel == nil {
                viewModel = AccountingHomeViewModel(dataStore: dataStore)
            }
        }
    }

    private func accountingContent(viewModel: AccountingHomeViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard(viewModel: viewModel)
                navigationLinks
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear { viewModel.refresh() }
    }

    // MARK: - Status Card

    private func statusCard(viewModel: AccountingHomeViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: viewModel.hasWarnings ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(viewModel.hasWarnings ? AppColors.warning : AppColors.success)
                Text("会計ステータス")
                    .font(.headline)
            }

            Text(viewModel.statusSummary)
                .font(.subheadline)
                .foregroundStyle(viewModel.hasWarnings ? AppColors.warning : .secondary)

            HStack(spacing: 20) {
                statusMetric(label: "勘定科目", value: "\(viewModel.totalAccounts)")
                statusMetric(label: "仕訳数", value: "\(viewModel.totalJournalEntries)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
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

    // MARK: - Navigation Links

    private var navigationLinks: some View {
        VStack(spacing: 8) {
            navigationRow(
                icon: "list.bullet.rectangle",
                title: "勘定科目一覧",
                subtitle: "勘定科目の管理",
                destination: ChartOfAccountsView()
            )
            navigationRow(
                icon: "arrow.left.arrow.right",
                title: "カテゴリ紐付け",
                subtitle: "カテゴリと勘定科目の対応設定",
                destination: CategoryAccountMappingView()
            )
            navigationRow(
                icon: "doc.text",
                title: "仕訳帳",
                subtitle: "仕訳一覧の確認",
                destination: JournalListView()
            )
            navigationRow(
                icon: "book.closed",
                title: "総勘定元帳",
                subtitle: "勘定科目別の取引履歴",
                destination: LedgerView()
            )
            navigationRow(
                icon: "banknote",
                title: "現金出納帳",
                subtitle: "現金勘定の増減明細",
                destination: SubLedgerView(type: .cashBook)
            )
            navigationRow(
                icon: "creditcard.and.123",
                title: "売掛帳",
                subtitle: "売掛金の増減明細",
                destination: SubLedgerView(type: .accountsReceivableBook)
            )
            navigationRow(
                icon: "cart.badge.minus",
                title: "買掛帳",
                subtitle: "買掛金の増減明細",
                destination: SubLedgerView(type: .accountsPayableBook)
            )
            navigationRow(
                icon: "chart.bar.xaxis",
                title: "経費帳",
                subtitle: "費用科目の明細",
                destination: SubLedgerView(type: .expenseBook)
            )
            navigationRow(
                icon: "calendar.badge.clock",
                title: "月別総括集計表",
                subtitle: "月別の売上・仕入・経費集計",
                destination: MonthlySummaryView()
            )
            navigationRow(
                icon: "tablecells",
                title: "試算表",
                subtitle: "勘定科目の残高一覧",
                destination: TrialBalanceView()
            )
            navigationRow(
                icon: "chart.bar.doc.horizontal",
                title: "損益計算書",
                subtitle: "収益と費用の集計",
                destination: ProfitLossView()
            )
            navigationRow(
                icon: "chart.pie",
                title: "貸借対照表",
                subtitle: "資産・負債・資本の状況",
                destination: BalanceSheetView()
            )
            navigationRow(
                icon: "shippingbox",
                title: "固定資産台帳",
                subtitle: "固定資産の管理と減価償却",
                destination: FixedAssetListView()
            )
            navigationRow(
                icon: "tablecells.badge.ellipsis",
                title: "減価償却明細表",
                subtitle: "全固定資産の減価償却スケジュール",
                destination: FixedAssetScheduleView()
            )
            navigationRow(
                icon: "cart",
                title: "棚卸入力",
                subtitle: "在庫・仕入高・売上原価の管理",
                destination: InventoryInputView()
            )
            navigationRow(
                icon: "doc.badge.gearshape",
                title: "決算仕訳",
                subtitle: "年度末の収益・費用勘定の振替",
                destination: ClosingEntryView()
            )
            navigationRow(
                icon: "square.and.arrow.up",
                title: "e-Tax出力",
                subtitle: "確定申告データの出力",
                destination: EtaxExportView()
            )
            navigationRow(
                icon: "archivebox",
                title: "書類台帳",
                subtitle: "法定書類の保存管理",
                destination: LegalDocumentLedgerView()
            )
        }
    }

    private func navigationRow<Destination: View>(
        icon: String,
        title: String,
        subtitle: String,
        destination: Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
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
        .buttonStyle(.plain)
    }
}
