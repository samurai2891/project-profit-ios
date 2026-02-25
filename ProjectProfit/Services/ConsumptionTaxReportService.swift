import Foundation

@MainActor
enum ConsumptionTaxReportService {

    // MARK: - Summary Generation

    /// 指定年度の消費税集計レポートを生成する
    /// - Parameters:
    ///   - fiscalYear: 対象年度
    ///   - journalEntries: 全仕訳伝票
    ///   - journalLines: 全仕訳明細行
    ///   - accounts: 全勘定科目（将来の拡張用に受け取る）
    /// - Returns: 消費税集計結果
    static func generateSummary(
        fiscalYear: Int,
        journalEntries: [PPJournalEntry],
        journalLines: [PPJournalLine],
        accounts: [PPAccount],
        startMonth: Int = 1
    ) -> ConsumptionTaxSummary {
        let (startDate, endDate) = fiscalYearRange(year: fiscalYear, startMonth: startMonth)
        let postedEntryIds = postedEntryIdsInRange(
            entries: journalEntries, start: startDate, end: endDate
        )

        let relevantLines = journalLines.filter { postedEntryIds.contains($0.entryId) }

        // 仮払消費税（借方合計）
        let inputTaxTotal = relevantLines
            .filter { $0.accountId == AccountingConstants.inputTaxAccountId }
            .reduce(0) { $0 + $1.debit }

        // 仮受消費税（貸方合計）
        let outputTaxTotal = relevantLines
            .filter { $0.accountId == AccountingConstants.outputTaxAccountId }
            .reduce(0) { $0 + $1.credit }

        return ConsumptionTaxSummary(
            fiscalYear: fiscalYear,
            generatedAt: Date(),
            outputTaxTotal: outputTaxTotal,
            inputTaxTotal: inputTaxTotal,
            taxPayable: outputTaxTotal - inputTaxTotal
        )
    }

    // MARK: - Helpers

    private static func fiscalYearRange(year: Int, startMonth: Int) -> (start: Date, end: Date) {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1))!
        let end = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: start)!
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end)!
        return (start, endOfDay)
    }

    private static func postedEntryIdsInRange(
        entries: [PPJournalEntry],
        start: Date,
        end: Date
    ) -> Set<UUID> {
        Set(
            entries
                .filter { $0.isPosted && $0.date >= start && $0.date <= end }
                .map(\.id)
        )
    }
}
