import SwiftData
import SwiftUI

/// 固定資産台帳 — NTA「帳簿の記帳のしかた」p.16-17 準拠レイアウト
struct FixedAssetScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var fiscalYear: Int = Calendar.current.component(.year, from: Date())

    private var assets: [PPFixedAsset] {
        FixedAssetQueryUseCase(modelContext: modelContext).listSnapshot(currentYear: fiscalYear).assets
    }

    private var rows: [DepreciationScheduleRow] {
        DepreciationScheduleBuilder.build(
            assets: assets,
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
            if assets.isEmpty {
                emptyState
            } else {
                scheduleContent
            }
        }
        .navigationTitle("固定資産台帳")
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
            VStack(alignment: .leading, spacing: 20) {
                yearSelector
                if rows.isEmpty {
                    noRowsMessage
                } else {
                    ForEach(rows) { row in
                        assetSection(row)
                    }
                    totalsSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Year Selector

    private var yearSelector: some View {
        HStack {
            Button { fiscalYear -= 1 } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(AppColors.primary)
            }
            Spacer()
            Text("\(String(fiscalYear))年度")
                .font(.headline)
            Spacer()
            Button { fiscalYear += 1 } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppColors.primary)
            }
        }
    }

    // MARK: - No Rows

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

    // MARK: - Asset Section (NTA p.16-17 様式)

    private func assetSection(_ row: DepreciationScheduleRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 資産ヘッダー: 資産名 + メタデータ
            assetHeader(row)

            Divider()

            // テーブルヘッダー
            tableHeader

            Divider()

            // 取得行
            acquisitionRow(row)

            // 当期償却行
            if row.currentYearAmount > 0 {
                depreciationRow(row)
            }

            // 累計行
            accumulatedRow(row)
        }
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func assetHeader(_ row: DepreciationScheduleRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.assetName)
                .font(.subheadline.weight(.bold))

            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
            ], spacing: 4) {
                headerDetail("取得年月日", formatDate(row.acquisitionDate))
                headerDetail("耐用年数", "\(row.usefulLifeYears)年")
                headerDetail("償却方法", row.depreciationMethod.label)
                headerDetail("償却率", depreciationRateText(row))
            }
        }
        .padding(.bottom, 8)
    }

    private func headerDetail(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.medium))
        }
    }

    private func depreciationRateText(_ row: DepreciationScheduleRow) -> String {
        switch row.depreciationMethod {
        case .straightLine:
            guard row.usefulLifeYears > 0 else { return "-" }
            let rate = 1.0 / Double(row.usefulLifeYears)
            return String(format: "%.3f", rate)
        case .decliningBalance:
            guard row.usefulLifeYears > 0 else { return "-" }
            let rate = 2.0 / Double(row.usefulLifeYears)
            return String(format: "%.3f", rate)
        case .immediateExpense:
            return "全額"
        case .threeYearEqual:
            return "0.333"
        case .smallBusiness:
            return "全額"
        }
    }

    // MARK: - Table

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("摘要")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("取得金額")
                .frame(width: 80, alignment: .trailing)
            Text("償却額")
                .frame(width: 80, alignment: .trailing)
            Text("現在金額")
                .frame(width: 80, alignment: .trailing)
            VStack(spacing: 0) {
                Text("事業割合")
                Text("経費算入")
            }
            .frame(width: 72, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }

    private func acquisitionRow(_ row: DepreciationScheduleRow) -> some View {
        HStack(spacing: 0) {
            Text("取得")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatCurrency(row.acquisitionCost))
                .font(.caption.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            Text("")
                .frame(width: 80, alignment: .trailing)
            Text("")
                .frame(width: 80, alignment: .trailing)
            Text("")
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private func depreciationRow(_ row: DepreciationScheduleRow) -> some View {
        let expenseAmount = row.currentYearAmount * row.businessUsePercent / 100
        let bookValueAfterDepreciation = row.acquisitionCost - row.accumulatedAmount

        return HStack(spacing: 0) {
            Text("\(String(fiscalYear))年 減価償却費")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("")
                .frame(width: 80)
            Text(formatCurrency(row.currentYearAmount))
                .font(.caption.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            Text(formatCurrency(bookValueAfterDepreciation))
                .font(.caption.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(row.businessUsePercent)%")
                    .font(.caption2)
                Text(formatCurrency(expenseAmount))
                    .font(.caption2.monospacedDigit())
            }
            .frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private func accumulatedRow(_ row: DepreciationScheduleRow) -> some View {
        HStack(spacing: 0) {
            Text("累計")
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("")
                .frame(width: 80)
            Text(formatCurrency(row.accumulatedAmount))
                .font(.caption.weight(.medium).monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            Text(formatCurrency(row.bookValue))
                .font(.caption.weight(.medium).monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            Text("")
                .frame(width: 72)
        }
        .padding(.vertical, 3)
        .background(AppColors.surface.opacity(0.5))
    }

    // MARK: - Totals

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

            let totalExpense = rows.reduce(0) { $0 + ($1.currentYearAmount * $1.businessUsePercent / 100) }
            HStack {
                Text("必要経費算入額")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatCurrency(totalExpense))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
        }
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
