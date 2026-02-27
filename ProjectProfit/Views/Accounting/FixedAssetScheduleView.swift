import SwiftUI

struct FixedAssetScheduleView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var fiscalYear: Int = Calendar.current.component(.year, from: Date())

    private var rows: [DepreciationScheduleRow] {
        DepreciationScheduleBuilder.build(
            assets: dataStore.fixedAssets,
            fiscalYear: fiscalYear
        )
    }

    private var totalCurrentYear: Int {
        rows.reduce(0) { $0 + $1.currentYearAmount }
    }

    private var totalBookValue: Int {
        rows.reduce(0) { $0 + $1.bookValue }
    }

    var body: some View {
        Group {
            if dataStore.fixedAssets.isEmpty {
                emptyState
            } else {
                scheduleContent
            }
        }
        .navigationTitle("減価償却明細表")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tablecells")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("固定資産がありません")
                .font(.headline)
            Text("固定資産台帳から資産を追加してください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Schedule Content

    private var scheduleContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                yearSelector
                if rows.isEmpty {
                    noRowsMessage
                } else {
                    ForEach(rows) { row in
                        assetCard(row)
                    }
                    totalsSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Year Selector

    private var yearSelector: some View {
        HStack {
            Button {
                fiscalYear -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(AppColors.primary)
            }
            Spacer()
            Text("\(String(fiscalYear))年度")
                .font(.headline)
            Spacer()
            Button {
                fiscalYear += 1
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppColors.primary)
            }
        }
    }

    // MARK: - No Rows Message

    private var noRowsMessage: some View {
        VStack(spacing: 8) {
            Text("この年度の対象資産はありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Asset Card

    private func assetCard(_ row: DepreciationScheduleRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.assetName)
                .font(.subheadline.weight(.medium))

            Divider()

            detailRow("取得日", formatDate(row.acquisitionDate))
            detailRow("取得価額", formatCurrency(row.acquisitionCost))
            detailRow("耐用年数", "\(row.usefulLifeYears)年")
            detailRow("償却方法", row.depreciationMethod.label)

            Divider()

            detailRow("当期償却額", formatCurrency(row.currentYearAmount))
            detailRow("累計償却額", formatCurrency(row.accumulatedAmount))
            detailRow(
                "帳簿価額",
                formatCurrency(row.bookValue),
                valueFont: .subheadline.weight(.semibold)
            )
        }
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func detailRow(
        _ label: String,
        _ value: String,
        valueFont: Font = .subheadline
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(valueFont.monospacedDigit())
        }
    }

    // MARK: - Totals Section

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("合計")
                .font(.subheadline.weight(.medium))

            HStack {
                Text("当期償却額")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatCurrency(totalCurrentYear))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }

            HStack {
                Text("帳簿価額")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatCurrency(totalBookValue))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
        }
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
