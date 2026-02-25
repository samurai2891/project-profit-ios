import SwiftUI

struct JournalDetailView: View {
    @Environment(DataStore.self) private var dataStore
    let entry: PPJournalEntry

    private var lines: [PPJournalLine] {
        dataStore.getJournalLines(for: entry.id)
    }

    private var debitTotal: Int {
        lines.reduce(0) { $0 + $1.debit }
    }

    private var creditTotal: Int {
        lines.reduce(0) { $0 + $1.credit }
    }

    private var isBalanced: Bool {
        debitTotal == creditTotal
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                linesSection
                totalsSection
            }
            .padding(20)
        }
        .navigationTitle("仕訳詳細")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formatDate(entry.date))
                    .font(.headline)
                Spacer()
                Text(entry.entryType.label)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }

            if !entry.memo.isEmpty {
                Text(entry.memo)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                statusLabel("投稿状態", value: entry.isPosted ? "投稿済" : "未投稿",
                           color: entry.isPosted ? AppColors.success : AppColors.warning)
                statusLabel("貸借", value: isBalanced ? "一致" : "不一致",
                           color: isBalanced ? AppColors.success : AppColors.error)
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statusLabel(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(label): \(value)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Lines

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("仕訳明細")
                .font(.subheadline.weight(.medium))

            ForEach(lines, id: \.id) { line in
                lineRow(line)
            }
        }
    }

    private func lineRow(_ line: PPJournalLine) -> some View {
        let accountName = dataStore.accounts.first(where: { $0.id == line.accountId })?.name ?? line.accountId

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(accountName)
                    .font(.subheadline)
                if !line.memo.isEmpty {
                    Text(line.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if line.debit > 0 {
                    HStack(spacing: 4) {
                        Text("借方")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(formatCurrency(line.debit))
                            .font(.subheadline.weight(.medium))
                    }
                }
                if line.credit > 0 {
                    HStack(spacing: 4) {
                        Text("貸方")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(formatCurrency(line.credit))
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Totals

    private var totalsSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("借方合計")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatCurrency(debitTotal))
                    .font(.title3.weight(.semibold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("貸方合計")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatCurrency(creditTotal))
                    .font(.title3.weight(.semibold))
            }
        }
        .padding(16)
        .background(isBalanced ? AppColors.success.opacity(0.1) : AppColors.error.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
