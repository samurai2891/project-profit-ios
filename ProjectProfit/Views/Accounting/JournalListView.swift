import SwiftUI

struct JournalListView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var showManualEntryForm = false

    private var sortedEntries: [PPJournalEntry] {
        dataStore.journalEntries.sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if sortedEntries.isEmpty {
                emptyState
            } else {
                journalList
            }
        }
        .navigationTitle("仕訳帳")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    if !sortedEntries.isEmpty {
                        ExportMenuButton(
                            csvGenerator: {
                                CSVExportService.exportJournalCSV(
                                    entries: dataStore.journalEntries,
                                    lines: dataStore.journalLines,
                                    accounts: dataStore.accounts
                                )
                            },
                            pdfGenerator: {
                                let fiscalYear = currentFiscalYear(startMonth: FiscalYearSettings.startMonth)
                                return PDFExportService.exportJournalPDF(
                                    entries: dataStore.journalEntries,
                                    lines: dataStore.journalLines,
                                    accounts: dataStore.accounts,
                                    fiscalYear: fiscalYear
                                )
                            },
                            fileNamePrefix: "仕訳帳"
                        )
                    }
                    Button {
                        showManualEntryForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("手動仕訳を追加")
                }
            }
        }
        .sheet(isPresented: $showManualEntryForm) {
            ManualJournalFormView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("仕訳がありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var journalList: some View {
        List {
            ForEach(sortedEntries, id: \.id) { entry in
                NavigationLink(destination: JournalDetailView(entry: entry)) {
                    journalRow(entry)
                }
            }
        }
        .listStyle(.plain)
    }

    private func journalRow(_ entry: PPJournalEntry) -> some View {
        let lines = dataStore.getJournalLines(for: entry.id)
        let debitTotal = lines.reduce(0) { $0 + $1.debit }
        let creditTotal = lines.reduce(0) { $0 + $1.credit }

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formatDate(entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                entryTypeBadge(entry.entryType)
            }

            Text(entry.memo.isEmpty ? "（摘要なし）" : entry.memo)
                .font(.subheadline)
                .lineLimit(1)

            HStack {
                HStack(spacing: 4) {
                    Text("借方")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(formatCurrency(debitTotal))
                        .font(.caption.weight(.medium).monospacedDigit())
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("貸方")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(formatCurrency(creditTotal))
                        .font(.caption.weight(.medium).monospacedDigit())
                }
            }

            if !entry.isPosted {
                Text("未投稿")
                    .font(.caption2)
                    .foregroundStyle(AppColors.warning)
            }
        }
        .padding(.vertical, 4)
    }

    private func entryTypeBadge(_ type: JournalEntryType) -> some View {
        Text(type.label)
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(badgeColor(for: type))
            .clipShape(Capsule())
    }

    private func badgeColor(for type: JournalEntryType) -> Color {
        switch type {
        case .auto: AppColors.primary
        case .manual: AppColors.warning
        case .opening: AppColors.success
        case .closing: AppColors.error
        }
    }
}
