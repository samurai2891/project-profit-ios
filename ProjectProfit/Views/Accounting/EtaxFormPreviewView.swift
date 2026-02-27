import SwiftUI

/// e-Taxフォームのプレビュー表示（セクション別フィールド一覧+合計）
struct EtaxFormPreviewView: View {
    let form: EtaxForm

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("プレビュー")
                .font(.headline)

            previewSection(title: "収入金額", fields: form.fields.filter { $0.section == .revenue })
            previewSection(title: "必要経費", fields: form.fields.filter { $0.section == .expenses })
            previewSection(title: "所得金額", fields: form.fields.filter { $0.section == .income })
            previewSection(title: "申告者情報", fields: form.fields.filter { $0.section == .declarantInfo })
            previewSection(title: "棚卸", fields: form.fields.filter { $0.section == .inventory })
            previewSection(title: "固定資産明細", fields: form.fields.filter { $0.section == .fixedAssetSchedule })
            previewSection(title: "貸借対照表", fields: form.fields.filter { $0.section == .balanceSheet })

            summaryRows
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Summary Rows

    private var summaryRows: some View {
        VStack(spacing: 4) {
            HStack {
                Text("合計収入")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(formatCurrency(form.totalRevenue))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            HStack {
                Text("合計経費")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(formatCurrency(form.totalExpenses))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            HStack {
                Text("所得金額")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(formatCurrency(form.netIncome))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(form.netIncome >= 0 ? AppColors.success : .red)
            }
        }
    }

    // MARK: - Section

    @ViewBuilder
    private func previewSection(title: String, fields: [EtaxField]) -> some View {
        if !fields.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(fields) { field in
                    HStack {
                        Text(field.fieldLabel)
                            .font(.caption)
                        Spacer()
                        Text(field.value.previewText)
                            .font(.caption.monospacedDigit())
                    }
                }
            }
            Divider()
        }
    }
}
