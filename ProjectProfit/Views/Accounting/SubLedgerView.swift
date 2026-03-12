import SwiftData
import SwiftUI

struct SubLedgerView: View {
    @Environment(\.modelContext) private var modelContext

    let type: SubLedgerType

    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var exportErrorMessage: String?
    // 経費帳: 科目フィルタ
    @State private var selectedExpenseAccountId: String?
    // 売掛帳/買掛帳: 取引先フィルタ
    @State private var selectedCounterparty: String?

    private var yearOptions: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 7)...current).reversed()
    }

    private var periodStart: Date { startOfYear(selectedYear) }
    private var periodEnd: Date { endOfYear(selectedYear) }

    private var queryUseCase: SubLedgerQueryUseCase {
        SubLedgerQueryUseCase(modelContext: modelContext)
    }

    /// 全エントリ（フィルタなし） — counterparties/summary の算出元
    private var allSnapshot: SubLedgerSnapshot {
        queryUseCase.snapshot(
            type: type,
            year: selectedYear
        )
    }

    /// 表示用エントリ（フィルタ適用済み）
    private var filteredSnapshot: SubLedgerSnapshot {
        queryUseCase.snapshot(
            type: type,
            year: selectedYear,
            accountFilter: selectedExpenseAccountId,
            counterpartyFilter: selectedCounterparty
        )
    }

    /// サマリー（全エントリから算出）
    private var summary: SubLedgerSummary {
        allSnapshot.summary
    }

    private var entries: [SubLedgerEntry] {
        filteredSnapshot.entries
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState
            } else {
                ledgerContent
            }
        }
        .navigationTitle(type.title)
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportSubLedger()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(entries.isEmpty)
                .accessibilityLabel("CSV共有")
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                ShareSheetView(activityItems: [shareURL])
            }
        }
        .alert("出力エラー", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    // MARK: - Empty State

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

    // MARK: - Content Router

    @ViewBuilder
    private var ledgerContent: some View {
        switch type {
        case .cashBook:
            cashBookContent
        case .expenseBook:
            expenseBookContent
        case .accountsReceivableBook:
            arBookContent
        case .accountsPayableBook:
            apBookContent
        }
    }

    private func exportSubLedger() {
        do {
            shareURL = try ExportCoordinator.export(
                target: .subLedger,
                format: .csv,
                fiscalYear: selectedYear,
                modelContext: modelContext,
                subLedgerOptions: .init(
                    type: type,
                    startDate: periodStart,
                    endDate: periodEnd,
                    accountFilter: selectedExpenseAccountId,
                    counterpartyFilter: selectedCounterparty
                )
            )
            showShareSheet = true
        } catch {
            shareURL = nil
            showShareSheet = false
            exportErrorMessage = error.localizedDescription
        }
    }
}

// MARK: - 現金出納帳 (Cash Book) — NTA p.11-12

extension SubLedgerView {

    private var cashBookContent: some View {
        List {
            summarySection
            cashBookHeader
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                cashBookRow(entry)
                    .listRowBackground(rowBackground(index))
            }
            taxMarkFooter
        }
        .listStyle(.plain)
    }

    private var cashBookHeader: some View {
        VStack(spacing: 0) {
            // 2段ヘッダー
            HStack(spacing: 0) {
                Text("月日")
                    .frame(width: 44, alignment: .leading)
                Text("摘要")
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 2) {
                    Text("入金")
                    HStack(spacing: 0) {
                        Text("現金売上")
                            .frame(width: 70, alignment: .trailing)
                        Text("その他")
                            .frame(width: 70, alignment: .trailing)
                    }
                }
                VStack(spacing: 2) {
                    Text("出金")
                    HStack(spacing: 0) {
                        Text("現金仕入")
                            .frame(width: 70, alignment: .trailing)
                        Text("その他")
                            .frame(width: 70, alignment: .trailing)
                    }
                }
                Text("残高")
                    .frame(width: 76, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }

    private func cashBookRow(_ entry: SubLedgerEntry) -> some View {
        HStack(spacing: 0) {
            Text(monthDay(entry.date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            Text(entryDescription(entry))
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 入金: 現金売上 / その他
            let isSalesCounter = entry.counterAccountId == AccountingConstants.salesAccountId
            if entry.debit > 0 {
                CurrencyText(amount: entry.debit, font: .caption, emptyWhenZero: true)
                    .frame(width: 70, alignment: .trailing)
                    .opacity(isSalesCounter ? 1 : 0)
                CurrencyText(amount: entry.debit, font: .caption, emptyWhenZero: true)
                    .frame(width: 70, alignment: .trailing)
                    .opacity(isSalesCounter ? 0 : 1)
            } else {
                Text("").frame(width: 70)
                Text("").frame(width: 70)
            }

            // 出金: 現金仕入 / その他
            let isPurchasesCounter = entry.counterAccountId == AccountingConstants.purchasesAccountId
            if entry.credit > 0 {
                CurrencyText(amount: entry.credit, font: .caption, emptyWhenZero: true)
                    .frame(width: 70, alignment: .trailing)
                    .opacity(isPurchasesCounter ? 1 : 0)
                CurrencyText(amount: entry.credit, font: .caption, emptyWhenZero: true)
                    .frame(width: 70, alignment: .trailing)
                    .opacity(isPurchasesCounter ? 0 : 1)
            } else {
                Text("").frame(width: 70)
                Text("").frame(width: 70)
            }

            // 現金残高
            CurrencyText(amount: entry.runningBalance, font: .caption.weight(.medium))
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 経費帳 (Expense Book) — NTA p.15

extension SubLedgerView {

    private var expenseAccounts: [PPAccount] {
        allSnapshot.expenseAccounts
    }

    private var expenseBookContent: some View {
        List {
            summarySection
            expenseAccountPicker
            expenseBookHeader
            if let selectedId = selectedExpenseAccountId {
                expenseBookSection(accountId: selectedId)
            } else {
                ForEach(expenseAccounts, id: \.id) { account in
                    let accountEntries = entries.filter { $0.accountId == account.id }
                    if !accountEntries.isEmpty {
                        Section {
                            ForEach(Array(accountEntries.enumerated()), id: \.element.id) { index, entry in
                                expenseBookRow(entry)
                                    .listRowBackground(rowBackground(index))
                            }
                        } header: {
                            Text(account.name)
                                .font(.subheadline.weight(.bold))
                        }
                    }
                }
            }
            taxMarkFooter
        }
        .listStyle(.plain)
    }

    private var expenseAccountPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "全科目", isSelected: selectedExpenseAccountId == nil) {
                    selectedExpenseAccountId = nil
                }
                ForEach(expenseAccounts, id: \.id) { account in
                    FilterChip(
                        label: account.name,
                        isSelected: selectedExpenseAccountId == account.id
                    ) {
                        selectedExpenseAccountId = account.id
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func expenseBookSection(accountId: String) -> some View {
        let accountEntries = entries.filter { $0.accountId == accountId }
        ForEach(Array(accountEntries.enumerated()), id: \.element.id) { index, entry in
            expenseBookRow(entry)
                .listRowBackground(rowBackground(index))
        }
    }

    private var expenseBookHeader: some View {
        HStack(spacing: 0) {
            Text("月日")
                .frame(width: 44, alignment: .leading)
            Text("摘要")
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 2) {
                Text("金額")
                HStack(spacing: 0) {
                    Text("現金")
                        .frame(width: 76, alignment: .trailing)
                    Text("その他")
                        .frame(width: 76, alignment: .trailing)
                }
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func expenseBookRow(_ entry: SubLedgerEntry) -> some View {
        let isCashPayment = entry.counterAccountId == AccountingConstants.cashAccountId
        let amount = entry.debit > 0 ? entry.debit : entry.credit

        return HStack(spacing: 0) {
            Text(monthDay(entry.date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            Text(entryDescription(entry))
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 現金
            CurrencyText(amount: isCashPayment ? amount : 0, font: .caption, emptyWhenZero: true)
                .frame(width: 76, alignment: .trailing)
            // その他
            CurrencyText(amount: isCashPayment ? 0 : amount, font: .caption, emptyWhenZero: true)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 売掛帳 (Accounts Receivable Book) — NTA p.13

extension SubLedgerView {

    private var arBookContent: some View {
        List {
            summarySection
            counterpartyPicker
            arBookHeader
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                arBookRow(entry)
                    .listRowBackground(rowBackground(index))
            }
            taxMarkFooter
        }
        .listStyle(.plain)
    }

    private var arBookHeader: some View {
        HStack(spacing: 0) {
            Text("月日")
                .frame(width: 44, alignment: .leading)
            Text("摘要")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("売上金額")
                .frame(width: 76, alignment: .trailing)
            Text("受入金額")
                .frame(width: 76, alignment: .trailing)
            Text("差引残高")
                .frame(width: 76, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func arBookRow(_ entry: SubLedgerEntry) -> some View {
        HStack(spacing: 0) {
            Text(monthDay(entry.date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            Text(entryDescription(entry))
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 売上金額（売掛金増 = debit）
            CurrencyText(amount: entry.debit, font: .caption, emptyWhenZero: true)
                .frame(width: 76, alignment: .trailing)
            // 受入金額（売掛金減 = credit）
            CurrencyText(amount: entry.credit, font: .caption, emptyWhenZero: true)
                .frame(width: 76, alignment: .trailing)
            // 差引残高
            CurrencyText(amount: entry.runningBalance, font: .caption.weight(.medium))
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 買掛帳 (Accounts Payable Book) — NTA p.14

extension SubLedgerView {

    private var apBookContent: some View {
        List {
            summarySection
            counterpartyPicker
            apBookHeader
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                apBookRow(entry)
                    .listRowBackground(rowBackground(index))
            }
            taxMarkFooter
        }
        .listStyle(.plain)
    }

    private var apBookHeader: some View {
        HStack(spacing: 0) {
            Text("月日")
                .frame(width: 44, alignment: .leading)
            Text("摘要")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("仕入金額")
                .frame(width: 76, alignment: .trailing)
            Text("支払金額")
                .frame(width: 76, alignment: .trailing)
            Text("差引残高")
                .frame(width: 76, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func apBookRow(_ entry: SubLedgerEntry) -> some View {
        HStack(spacing: 0) {
            Text(monthDay(entry.date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            Text(entryDescription(entry))
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 仕入金額（買掛金増 = credit）
            CurrencyText(amount: entry.credit, font: .caption, emptyWhenZero: true)
                .frame(width: 76, alignment: .trailing)
            // 支払金額（買掛金減 = debit）
            CurrencyText(amount: entry.debit, font: .caption, emptyWhenZero: true)
                .frame(width: 76, alignment: .trailing)
            // 差引残高
            CurrencyText(amount: entry.runningBalance, font: .caption.weight(.medium))
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Shared Components

extension SubLedgerView {

    private var summarySection: some View {
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
                        .font(.caption.weight(.medium).monospacedDigit())
                    Text("貸方 \(formatCurrency(summary.creditTotal))")
                        .font(.caption.weight(.medium).monospacedDigit())
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// 摘要テキスト: [取引先] メモ ※
    private func entryDescription(_ entry: SubLedgerEntry) -> String {
        var parts: [String] = []
        if let cp = entry.counterparty, !cp.isEmpty {
            parts.append("[\(cp)]")
        }
        let memo = entry.memo.isEmpty ? "（摘要なし）" : entry.memo
        parts.append(memo)
        if entry.taxCategory == .reducedRate {
            parts.append("※")
        }
        return parts.joined(separator: " ")
    }

    /// 月日表示 (M/d)
    private func monthDay(_ date: Date) -> String {
        let cal = Calendar.current
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return "\(m)/\(d)"
    }

    /// 交互背景色
    private func rowBackground(_ index: Int) -> Color {
        index.isMultiple(of: 2) ? Color(.systemBackground) : AppColors.surface.opacity(0.5)
    }

    /// 消費税マーク凡例フッター
    @ViewBuilder
    private var taxMarkFooter: some View {
        let hasReducedRate = entries.contains { $0.taxCategory == .reducedRate }
        if hasReducedRate {
            Section {
                Text("※は軽減税率対象")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 取引先一覧（売掛帳/買掛帳共用）
    private var counterparties: [String] {
        let cps = Set(allSnapshot.entries.compactMap(\.counterparty).filter { !$0.isEmpty })
        return cps.sorted()
    }

    /// 取引先セレクター（売掛帳/買掛帳共用）
    private var counterpartyPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "全取引先", isSelected: selectedCounterparty == nil) {
                    selectedCounterparty = nil
                }
                ForEach(counterparties, id: \.self) { cp in
                    FilterChip(label: cp, isSelected: selectedCounterparty == cp) {
                        selectedCounterparty = cp
                    }
                }
                let hasUnknown = allSnapshot.entries.contains { ($0.counterparty ?? "").isEmpty }
                if hasUnknown {
                    FilterChip(label: "不明", isSelected: selectedCounterparty == "") {
                        selectedCounterparty = ""
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - FilterChip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? AppColors.primary.opacity(0.15) : AppColors.surface)
                .foregroundStyle(isSelected ? AppColors.primary : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
