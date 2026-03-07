import SwiftUI
import SwiftData

/// Canonical仕訳ブラウザ（CanonicalJournalEntry ベース）
struct JournalBrowserView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var journals: [CanonicalJournalEntry] = []
    @State private var searchText = ""
    @State private var selectedEntryType: CanonicalJournalEntryType?
    @State private var isLoading = true

    private var filteredJournals: [CanonicalJournalEntry] {
        var result = journals

        if let entryType = selectedEntryType {
            result = result.filter { $0.entryType == entryType }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { journal in
                journal.description.lowercased().contains(query)
                    || journal.voucherNo.lowercased().contains(query)
            }
        }

        return result
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredJournals.isEmpty {
                emptyState
            } else {
                journalList
            }
        }
        .navigationTitle("仕訳一覧")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "伝票番号・摘要で検索")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                entryTypeFilterMenu
            }
        }
        .task {
            await loadJournals()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: searchText.isEmpty && selectedEntryType == nil
                ? "doc.text"
                : "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty && selectedEntryType == nil
                ? "仕訳がありません"
                : "条件に一致する仕訳がありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Journal List

    private var journalList: some View {
        List {
            ForEach(filteredJournals) { journal in
                journalRow(journal)
            }
        }
        .listStyle(.plain)
    }

    private func journalRow(_ journal: CanonicalJournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formatDate(journal.journalDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(journal.voucherNo)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Spacer()

                entryTypeBadge(journal.entryType)
            }

            Text(journal.description.isEmpty ? "（摘要なし）" : journal.description)
                .font(.subheadline)
                .lineLimit(1)

            HStack {
                HStack(spacing: 4) {
                    Text("借方")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(formatDecimalCurrency(journal.totalDebit))
                        .font(.caption.weight(.medium).monospacedDigit())
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("貸方")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(formatDecimalCurrency(journal.totalCredit))
                        .font(.caption.weight(.medium).monospacedDigit())
                }
            }

            if journal.lockedAt != nil {
                Label("確定済", systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(AppColors.success)
            }
        }
        .padding(.vertical, 4)
    }

    private func entryTypeBadge(_ type: CanonicalJournalEntryType) -> some View {
        Text(type.displayName)
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(badgeColor(for: type))
            .clipShape(Capsule())
    }

    private func badgeColor(for type: CanonicalJournalEntryType) -> Color {
        switch type {
        case .normal: AppColors.primary
        case .opening: AppColors.success
        case .closing: AppColors.error
        case .depreciation: AppColors.warning
        case .recurring: AppColors.primary.opacity(0.7)
        case .inventoryAdjustment: AppColors.warning.opacity(0.8)
        case .taxAdjustment: AppColors.error.opacity(0.7)
        case .reversal: AppColors.muted
        }
    }

    private var entryTypeFilterMenu: some View {
        Menu {
            Button("すべて") {
                selectedEntryType = nil
            }
            ForEach(CanonicalJournalEntryType.allCases, id: \.self) { type in
                Button(type.displayName) {
                    selectedEntryType = type
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: - Data Loading

    private func loadJournals() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let descriptor = FetchDescriptor<JournalEntryEntity>(
                sortBy: [SortDescriptor(\.journalDate, order: .reverse)]
            )
            let entities = try modelContext.fetch(descriptor)
            journals = entities.map { CanonicalJournalEntryEntityMapper.toDomain($0) }
        } catch {
            journals = []
        }
    }

    private func formatDecimalCurrency(_ value: Decimal) -> String {
        let intValue = NSDecimalNumber(decimal: value).intValue
        return formatCurrency(intValue)
    }
}
