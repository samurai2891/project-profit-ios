import SwiftUI

struct SubLedgerView: View {
    @Environment(DataStore.self) private var dataStore

    let type: SubLedgerType

    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var showShareSheet = false
    @State private var csvText = ""

    private var yearOptions: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 7)...current).reversed()
    }

    private var periodStart: Date {
        startOfYear(selectedYear)
    }

    private var periodEnd: Date {
        endOfYear(selectedYear)
    }

    private var entries: [SubLedgerEntry] {
        dataStore.getSubLedgerEntries(type: type, startDate: periodStart, endDate: periodEnd)
    }

    private var summary: SubLedgerSummary {
        dataStore.getSubLedgerSummary(type: type, startDate: periodStart, endDate: periodEnd)
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState
            } else {
                ledgerList
            }
        }
        .navigationTitle(type.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(yearOptions, id: \.self) { year in
                        Button("\(year)年") {
                            selectedYear = year
                        }
                    }
                } label: {
                    Text("\(selectedYear)年")
                        .font(.subheadline.weight(.medium))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    csvText = dataStore.exportSubLedgerCSV(type: type, startDate: periodStart, endDate: periodEnd)
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(entries.isEmpty)
                .accessibilityLabel("CSV共有")
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheetView(activityItems: [csvText])
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("対象期間にデータがありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(type.subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var ledgerList: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(type.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(selectedYear)年")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("借方 \(formatCurrency(summary.debitTotal))")
                            .font(.caption.weight(.medium))
                        Text("貸方 \(formatCurrency(summary.creditTotal))")
                            .font(.caption.weight(.medium))
                    }
                }
                .padding(.vertical, 4)
            }

            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(formatDate(entry.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(entry.accountCode) \(entry.accountName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.memo.isEmpty ? "（摘要なし）" : entry.memo)
                        .font(.subheadline)
                        .lineLimit(1)
                    HStack {
                        Text("借方 \(entry.debit > 0 ? formatCurrency(entry.debit) : "-")")
                            .font(.caption)
                        Spacer()
                        Text("貸方 \(entry.credit > 0 ? formatCurrency(entry.credit) : "-")")
                            .font(.caption)
                        Spacer()
                        Text("残高 \(formatCurrency(entry.runningBalance))")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
    }
}
