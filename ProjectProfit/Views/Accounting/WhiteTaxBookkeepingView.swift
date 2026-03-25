import SwiftData
import SwiftUI

struct WhiteTaxBookkeepingView: View {
    @Environment(\.modelContext) private var modelContext

    static let titleText = "白色簡易帳簿"

    @State private var selectedYear: Int
    @State private var snapshot: WhiteTaxBookkeepingSnapshot

    init() {
        let initialYear = currentTaxYear() - 1
        _selectedYear = State(initialValue: initialYear)
        _snapshot = State(
            initialValue: WhiteTaxBookkeepingSnapshot(
                fiscalYear: initialYear,
                totalRevenue: 0,
                totalExpenses: 0,
                netIncome: 0,
                revenueRows: [],
                inventoryRows: [],
                expenseRows: []
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                yearSelector
                summarySection
                if snapshot.isEmpty {
                    emptyState
                } else {
                    bookkeepingSection(title: "収入金額", rows: snapshot.revenueRows)
                    bookkeepingSection(title: "棚卸", rows: snapshot.inventoryRows)
                    bookkeepingSection(title: "主要な必要経費", rows: snapshot.expenseRows)
                    exportSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .navigationTitle(Self.titleText)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedYear) {
            refreshSnapshot()
        }
    }

    private var yearSelector: some View {
        HStack {
            Button {
                selectedYear -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(AppColors.primary)
            }

            Spacer()

            Text("\(selectedYear)年分")
                .font(.headline)

            Spacer()

            Button {
                selectedYear += 1
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppColors.primary)
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("白色申告サマリー")
                .font(.headline)

            HStack(spacing: 12) {
                summaryCard(title: "収入計", amount: snapshot.totalRevenue)
                summaryCard(title: "必要経費", amount: snapshot.totalExpenses)
            }

            summaryCard(title: "所得金額", amount: snapshot.netIncome, fullWidth: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.book.closed")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("対象年分の白色簡易帳簿データはまだありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func bookkeepingSection(title: String, rows: [WhiteTaxBookkeepingRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 8) {
                ForEach(rows) { row in
                    HStack {
                        Text(row.title)
                            .font(.subheadline)
                        Spacer()
                        Text(formatCurrency(row.amount))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("申告連携")
                .font(.subheadline.weight(.semibold))

            NavigationLink {
                EtaxExportView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(AppColors.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("e-Tax出力を開く")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("白色申告の帳票出力と送信準備へ進む")
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

    private func summaryCard(title: String, amount: Int, fullWidth: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatCurrency(amount))
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func refreshSnapshot() {
        snapshot = WhiteTaxBookkeepingQueryUseCase(modelContext: modelContext).snapshot(taxYear: selectedYear)
    }
}
