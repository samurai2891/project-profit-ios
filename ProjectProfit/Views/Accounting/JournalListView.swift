import SwiftData
import SwiftUI

struct JournalListView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.modelContext) private var modelContext

    @State private var showManualEntryForm = false
    @State private var showSearchFilters = false
    @State private var searchForm = JournalSearchFormState()
    @State private var matchingJournalIds: Set<UUID>?
    @State private var isSearching = false
    @State private var isReindexing = false
    @State private var errorMessage: String?

    private var projectedJournals: (entries: [PPJournalEntry], lines: [PPJournalLine]) {
        dataStore.projectedCanonicalJournals()
    }

    private var sortedEntries: [PPJournalEntry] {
        projectedJournals.entries
    }

    private var visibleEntries: [PPJournalEntry] {
        guard let matchingJournalIds else { return sortedEntries }
        return sortedEntries.filter { matchingJournalIds.contains($0.id) }
    }

    private var canCreateManualJournals: Bool {
        dataStore.isLegacyTransactionEditingEnabled
    }

    var body: some View {
        Group {
            if isSearching || isReindexing {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleEntries.isEmpty {
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
                            target: .journal,
                            fiscalYear: currentFiscalYear(startMonth: FiscalYearSettings.startMonth),
                            dataStore: dataStore
                        )
                    }
                    Menu {
                        Button("検索条件") {
                            showSearchFilters = true
                        }
                        Button("再索引") {
                            Task { await rebuildJournalIndex() }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("検索条件")
                    if canCreateManualJournals {
                        Button {
                            showManualEntryForm = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("手動仕訳を追加")
                    }
                }
            }
        }
        .searchable(
            text: Binding(
                get: { searchForm.textQuery },
                set: { searchForm.textQuery = $0 }
            ),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "摘要 / 伝票番号 / 取引先 / ハッシュ"
        )
        .task(id: reloadKey) {
            await refreshSearchResults()
        }
        .sheet(isPresented: $showManualEntryForm) {
            ManualJournalFormView()
        }
        .sheet(isPresented: $showSearchFilters) {
            JournalSearchFilterSheet(
                form: $searchForm,
                projects: dataStore.projects
            )
        }
        .alert("検索エラー", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var reloadKey: String {
        [
            dataStore.businessProfile?.id.uuidString ?? "none",
            searchForm.reloadToken,
            String(sortedEntries.count)
        ].joined(separator: ":")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: searchForm.hasActiveFilters ? "line.3.horizontal.decrease.circle" : "doc.text")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(searchForm.hasActiveFilters ? "検索条件に一致する仕訳がありません" : "仕訳がありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !searchForm.hasActiveFilters, !canCreateManualJournals {
                canonicalCutoverNotice
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    private var journalList: some View {
        List {
            if !canCreateManualJournals {
                Section {
                    canonicalCutoverNotice
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(visibleEntries, id: \.id) { entry in
                NavigationLink(destination: JournalDetailView(entry: entry)) {
                    journalRow(entry)
                }
            }
        }
        .listStyle(.plain)
    }

    private var canonicalCutoverNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("手動仕訳の追加は停止中です", systemImage: "arrow.trianglehead.branch")
                .font(.subheadline.weight(.semibold))
            Text("canonical 正本へ切り替え済みのため、仕訳は証憑タブと承認タブから作成してください。決算整理は決算仕訳画面から管理します。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.warning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func journalRow(_ entry: PPJournalEntry) -> some View {
        let lines = projectedJournals.lines
            .filter { $0.entryId == entry.id }
            .sorted { $0.displayOrder < $1.displayOrder }
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

    private func refreshSearchResults() async {
        guard searchForm.hasActiveFilters,
              let businessId = dataStore.businessProfile?.id
        else {
            matchingJournalIds = nil
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            let criteria = searchForm.makeCriteria(businessId: businessId)
            let canonicalMatches = try await JournalSearchUseCase(modelContext: modelContext).search(criteria: criteria)
            let supplementalMatches = supplementalMatchIds(criteria: criteria)
            matchingJournalIds = Set(canonicalMatches).union(supplementalMatches)
        } catch {
            matchingJournalIds = nil
            errorMessage = error.localizedDescription
        }
    }

    private func supplementalMatchIds(criteria: JournalSearchCriteria) -> Set<UUID> {
        let supplementalEntries = sortedEntries.filter { entry in
            entry.sourceKey.hasPrefix("manual:")
                || entry.sourceKey.hasPrefix("opening:")
                || entry.sourceKey.hasPrefix("closing:")
        }

        return Set(supplementalEntries.compactMap { entry in
            if let dateRange = criteria.dateRange, !dateRange.contains(entry.date) {
                return nil
            }

            let lines = projectedJournals.lines.filter { $0.entryId == entry.id }
            let totalAmount = Decimal(lines.reduce(0) { $0 + max($1.debit, $1.credit) })
            if let amountRange = criteria.amountRange, !amountRange.contains(totalAmount) {
                return nil
            }

            if criteria.counterpartyText != nil
                || criteria.registrationNumber != nil
                || criteria.projectId != nil
                || criteria.fileHash != nil {
                return nil
            }

            if let textQuery = SearchIndexNormalizer.normalizeOptionalText(criteria.textQuery) {
                let searchText = SearchIndexNormalizer.normalizeText(
                    ([entry.memo] + lines.map(\.memo)).joined(separator: " ")
                )
                if !searchText.contains(textQuery) {
                    return nil
                }
            }

            return entry.id
        })
    }

    private func rebuildJournalIndex() async {
        guard let businessId = dataStore.businessProfile?.id else { return }
        isReindexing = true
        defer { isReindexing = false }

        do {
            try SearchIndexRebuilder(modelContext: modelContext)
                .rebuildJournalIndex(businessId: businessId)
            await refreshSearchResults()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
