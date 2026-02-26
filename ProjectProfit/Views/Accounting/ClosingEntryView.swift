import SwiftUI

struct ClosingEntryView: View {
    @Environment(DataStore.self) private var dataStore

    @State private var selectedYear: Int
    @State private var showDeleteConfirmation = false
    @State private var showRegenerateConfirmation = false
    @State private var showLockConfirmation = false
    @State private var showUnlockConfirmation = false

    init() {
        let currentYear = Calendar.current.component(.year, from: Date())
        _selectedYear = State(initialValue: currentYear)
    }

    private var closingEntry: PPJournalEntry? {
        let sourceKey = PPJournalEntry.closingSourceKey(year: selectedYear)
        return dataStore.journalEntries.first { $0.sourceKey == sourceKey }
    }

    private var closingLines: [PPJournalLine] {
        guard let entry = closingEntry else { return [] }
        return dataStore.journalLines
            .filter { $0.entryId == entry.id }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    private var isYearLocked: Bool {
        dataStore.accountingProfile?.isYearLocked(selectedYear) ?? false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                yearPicker
                statusSection
                if closingEntry != nil {
                    closingLinesSection
                }
                actionButtons
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .navigationTitle("決算仕訳")
        .alert("決算仕訳を削除しますか？", isPresented: $showDeleteConfirmation) {
            Button("削除", role: .destructive) {
                dataStore.deleteClosingEntry(for: selectedYear)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("\(selectedYear)年の決算仕訳を削除します。")
        }
        .alert("決算仕訳を再生成しますか？", isPresented: $showRegenerateConfirmation) {
            Button("再生成", role: .destructive) {
                dataStore.regenerateClosingEntry(for: selectedYear)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("既存の決算仕訳を削除して、最新データで再生成します。")
        }
        .alert("\(selectedYear)年度をロックしますか？", isPresented: $showLockConfirmation) {
            Button("ロック", role: .destructive) {
                dataStore.lockFiscalYear(selectedYear)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("ロック中は、この年度の取引・仕訳・固定資産・棚卸の更新ができません。")
        }
        .alert("\(selectedYear)年度のロックを解除しますか？", isPresented: $showUnlockConfirmation) {
            Button("解除") {
                dataStore.unlockFiscalYear(selectedYear)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("ロック解除後は、この年度の更新が可能になります。")
        }
    }

    // MARK: - Year Picker

    private var yearPicker: some View {
        HStack {
            Text("年度")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("年度", selection: $selectedYear) {
                let currentYear = Calendar.current.component(.year, from: Date())
                ForEach((currentYear - 5)...(currentYear), id: \.self) { year in
                    Text("\(year)年").tag(year)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: closingEntry != nil ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(closingEntry != nil ? AppColors.success : .secondary)
                Text(closingEntry != nil ? "決算仕訳 生成済み" : "決算仕訳 未生成")
                    .font(.headline)
            }

            if isYearLocked {
                Label("この年度はロック済みです", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(AppColors.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Closing Lines

    private var closingLinesSection: some View {
        let lines = closingLines
        return VStack(alignment: .leading, spacing: 8) {
            Text("仕訳明細")
                .font(.subheadline.weight(.medium))

            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                HStack {
                    Text(accountName(for: line.accountId))
                        .font(.subheadline)
                    Spacer()
                    if line.debit > 0 {
                        Text("借方 ¥\(line.debit.formatted())")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(AppColors.primary)
                    }
                    if line.credit > 0 {
                        Text("貸方 ¥\(line.credit.formatted())")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(AppColors.muted)
                    }
                }
                .padding(.vertical, 4)

                if index < lines.count - 1 {
                    Divider()
                }
            }
        }
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func accountName(for accountId: String) -> String {
        dataStore.accounts.first(where: { $0.id == accountId })?.name ?? accountId
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button {
                if isYearLocked {
                    showUnlockConfirmation = true
                } else {
                    showLockConfirmation = true
                }
            } label: {
                Label(
                    isYearLocked ? "年度ロックを解除" : "この年度をロック",
                    systemImage: isYearLocked ? "lock.open" : "lock"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if closingEntry == nil {
                Button {
                    dataStore.generateClosingEntry(for: selectedYear)
                } label: {
                    Label("決算仕訳を生成", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isYearLocked)
            } else {
                Button {
                    showRegenerateConfirmation = true
                } label: {
                    Label("再生成", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isYearLocked)

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("削除", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isYearLocked)
            }
        }
    }
}
