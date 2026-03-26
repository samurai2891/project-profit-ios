import SwiftData
import SwiftUI

/// 月別総括集計表 — NTA「帳簿の記帳のしかた」p.18-19 準拠
struct MonthlySummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedYear = Calendar.current.component(.year, from: Date())

    private var yearOptions: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 7)...current).reversed()
    }

    private var rows: [MonthlySummaryRow] {
        ReportingQueryUseCase(modelContext: modelContext).monthlySummaryRows(year: selectedYear)
    }

    private let monthLabels = (1...12).map { "\($0)月" }

    var body: some View {
        Group {
            if rows.isEmpty {
                emptyState
            } else {
                summaryTable
            }
        }
        .navigationTitle("月別総括集計表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(yearOptions, id: \.self) { year in
                        Button("\(year)年") { selectedYear = year }
                    }
                } label: {
                    Text("\(selectedYear)年")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tablecells")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("対象期間にデータがありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Summary Table

    private var summaryTable: some View {
        ScrollView(.vertical) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    tableHeader
                    Divider()
                    ForEach(rows) { row in
                        tableRow(row)
                        if row.isSubtotal {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Table Header

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("項目")
                .frame(width: labelWidth, alignment: .leading)
            ForEach(monthLabels, id: \.self) { label in
                Text(label)
                    .frame(width: cellWidth, alignment: .trailing)
            }
            Text("計")
                .frame(width: totalWidth, alignment: .trailing)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }

    // MARK: - Table Row

    private func tableRow(_ row: MonthlySummaryRow) -> some View {
        HStack(spacing: 0) {
            Text(row.label)
                .font(row.isSubtotal ? .caption.weight(.bold) : .caption)
                .frame(width: labelWidth, alignment: .leading)
                .lineLimit(1)

            ForEach(0..<12, id: \.self) { month in
                let amount = row.amounts[month]
                if amount == 0 {
                    Text("")
                        .frame(width: cellWidth)
                } else {
                    Text(formatCurrency(amount))
                        .font(.caption.monospacedDigit())
                        .frame(width: cellWidth, alignment: .trailing)
                }
            }

            if row.total == 0 {
                Text("")
                    .frame(width: totalWidth)
            } else {
                Text(formatCurrency(row.total))
                    .font(.caption.weight(row.isSubtotal ? .bold : .medium).monospacedDigit())
                    .frame(width: totalWidth, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
        .background(row.isSubtotal ? AppColors.surface.opacity(0.5) : Color.clear)
    }

    // MARK: - Layout Constants

    private let labelWidth: CGFloat = 130
    private let cellWidth: CGFloat = 64
    private let totalWidth: CGFloat = 72
}
