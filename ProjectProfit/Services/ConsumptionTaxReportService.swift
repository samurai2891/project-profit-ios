import Foundation

@MainActor
enum ConsumptionTaxReportService {

    // MARK: - Canonical Worksheet

    static func generateWorksheet(
        fiscalYear: Int,
        taxYearProfile: TaxYearProfile,
        journalEntries: [CanonicalJournalEntry],
        accounts: [CanonicalAccount],
        counterparties: [Counterparty] = [],
        pack: TaxYearPack? = nil,
        startMonth: Int = 1
    ) -> ConsumptionTaxWorksheet {
        let (startDate, endDate) = fiscalYearRange(year: fiscalYear, startMonth: startMonth)
        let accountById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let counterpartyById = Dictionary(uniqueKeysWithValues: counterparties.map { ($0.id, $0) })
        let evaluator = TaxRuleEvaluator(profile: taxYearProfile, pack: pack)

        let relevantEntries = journalEntries
            .filter { $0.journalDate >= startDate && $0.journalDate <= endDate }
            .sorted { lhs, rhs in
                if lhs.journalDate != rhs.journalDate {
                    return lhs.journalDate < rhs.journalDate
                }
                return lhs.voucherNo < rhs.voucherNo
            }

        var worksheetLines: [ConsumptionTaxWorksheetLine] = []

        for entry in relevantEntries {
            let inputTaxPool = actualTaxPool(
                for: entry,
                legacyAccountId: AccountingConstants.inputTaxAccountId,
                accountById: accountById
            )
            let outputTaxPool = actualTaxPool(
                for: entry,
                legacyAccountId: AccountingConstants.outputTaxAccountId,
                accountById: accountById
            )

            let revenueLines = entry.lines.filter {
                guard let taxCode = TaxCode.resolve(id: $0.taxCodeId) else { return false }
                guard let account = accountById[$0.accountId], account.accountType == .revenue else { return false }
                return taxCode.isTaxable || taxCode == .exempt || taxCode == .nonTaxable
            }
            worksheetLines.append(
                contentsOf: makeWorksheetLines(
                    journalLines: revenueLines,
                    direction: .output,
                    entry: entry,
                    taxPool: outputTaxPool,
                    evaluator: evaluator,
                    accountById: accountById,
                    counterpartyById: counterpartyById,
                    pack: pack
                )
            )

            let expenseLines = entry.lines.filter {
                guard let taxCode = TaxCode.resolve(id: $0.taxCodeId) else { return false }
                guard let account = accountById[$0.accountId], account.accountType == .expense else { return false }
                return taxCode.isTaxable || taxCode == .exempt || taxCode == .nonTaxable
            }
            worksheetLines.append(
                contentsOf: makeWorksheetLines(
                    journalLines: expenseLines,
                    direction: .input,
                    entry: entry,
                    taxPool: inputTaxPool,
                    evaluator: evaluator,
                    accountById: accountById,
                    counterpartyById: counterpartyById,
                    pack: pack
                )
            )
        }

        let outputTaxTotal = worksheetLines
            .filter { $0.direction == .output }
            .reduce(0) { $0 + $1.taxAmount }
        let rawInputTaxTotal = worksheetLines
            .filter { $0.direction == .input }
            .reduce(0) { $0 + $1.taxAmount }
        let deductibleInputTaxTotal = worksheetLines
            .filter { $0.direction == .input }
            .reduce(0) { $0 + $1.deductibleTaxAmount }

        return ConsumptionTaxWorksheet(
            fiscalYear: fiscalYear,
            generatedAt: Date(),
            lines: worksheetLines,
            outputTaxTotal: outputTaxTotal,
            rawInputTaxTotal: rawInputTaxTotal,
            deductibleInputTaxTotal: deductibleInputTaxTotal
        )
    }

    static func generateSummary(from worksheet: ConsumptionTaxWorksheet) -> ConsumptionTaxSummary {
        ConsumptionTaxSummary(
            fiscalYear: worksheet.fiscalYear,
            generatedAt: worksheet.generatedAt,
            outputTaxTotal: worksheet.outputTaxTotal,
            inputTaxTotal: worksheet.deductibleInputTaxTotal,
            rawInputTaxTotal: worksheet.rawInputTaxTotal,
            taxPayable: worksheet.taxPayable
        )
    }

    static func generateSummary(
        fiscalYear: Int,
        taxYearProfile: TaxYearProfile,
        journalEntries: [CanonicalJournalEntry],
        accounts: [CanonicalAccount],
        counterparties: [Counterparty] = [],
        pack: TaxYearPack? = nil,
        startMonth: Int = 1
    ) -> ConsumptionTaxSummary {
        generateSummary(
            from: generateWorksheet(
                fiscalYear: fiscalYear,
                taxYearProfile: taxYearProfile,
                journalEntries: journalEntries,
                accounts: accounts,
                counterparties: counterparties,
                pack: pack,
                startMonth: startMonth
            )
        )
    }

    // MARK: - Legacy Compatibility

    /// 旧 `PPJournalEntry` / `PPJournalLine` ベースの集計を維持する互換 API。
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

        let inputTaxTotal = relevantLines
            .filter { $0.accountId == AccountingConstants.inputTaxAccountId }
            .reduce(0) { $0 + $1.debit }

        let outputTaxTotal = relevantLines
            .filter { $0.accountId == AccountingConstants.outputTaxAccountId }
            .reduce(0) { $0 + $1.credit }

        return ConsumptionTaxSummary(
            fiscalYear: fiscalYear,
            generatedAt: Date(),
            outputTaxTotal: outputTaxTotal,
            inputTaxTotal: inputTaxTotal,
            rawInputTaxTotal: inputTaxTotal,
            taxPayable: outputTaxTotal - inputTaxTotal
        )
    }

    // MARK: - Helpers

    private static func makeWorksheetLines(
        journalLines: [JournalLine],
        direction: ConsumptionTaxWorksheetLine.Direction,
        entry: CanonicalJournalEntry,
        taxPool: Int,
        evaluator: TaxRuleEvaluator,
        accountById: [UUID: CanonicalAccount],
        counterpartyById: [UUID: Counterparty],
        pack: TaxYearPack?
    ) -> [ConsumptionTaxWorksheetLine] {
        let taxableBusinessLines = journalLines.compactMap { line -> (JournalLine, TaxCode)? in
            guard let taxCode = TaxCode.resolve(id: line.taxCodeId) else { return nil }
            return (line, taxCode)
        }
        guard !taxableBusinessLines.isEmpty else { return [] }

        let taxableTotal = taxableBusinessLines.reduce(0) { partial, entry in
            partial + decimalToInt(entry.0.amount)
        }

        var remainingTaxPool = taxPool
        var worksheetLines: [ConsumptionTaxWorksheetLine] = []

        for (index, item) in taxableBusinessLines.enumerated() {
            let line = item.0
            let taxCode = item.1
            let taxableAmount = decimalToInt(line.amount)

            let allocatedTaxAmount: Int
            if !taxCode.isTaxable {
                allocatedTaxAmount = 0
            } else if index == taxableBusinessLines.count - 1 {
                allocatedTaxAmount = remainingTaxPool
            } else if taxableTotal > 0 {
                allocatedTaxAmount = taxPool * taxableAmount / taxableTotal
                remainingTaxPool -= allocatedTaxAmount
            } else {
                allocatedTaxAmount = 0
            }

            let purchaseCreditMethod: InputTaxCreditMethod?
            let deductibleTaxAmount: Int
            if direction == .input, taxCode.isTaxable {
                let counterpartyStatus = line.counterpartyId
                    .flatMap { counterpartyById[$0]?.invoiceIssuerStatus }
                    ?? .unknown
                let grossAmount = Decimal(taxableAmount + allocatedTaxAmount)
                let creditMethod = evaluator.evaluateInputTaxCreditMethod(
                    transactionDate: entry.journalDate,
                    counterpartyInvoiceStatus: counterpartyStatus,
                    amount: grossAmount
                )
                purchaseCreditMethod = creditMethod
                deductibleTaxAmount = decimalToInt(Decimal(allocatedTaxAmount) * creditMethod.creditRate)
            } else {
                purchaseCreditMethod = nil
                deductibleTaxAmount = 0
            }

            worksheetLines.append(
                ConsumptionTaxWorksheetLine(
                    id: line.id,
                    journalId: entry.id,
                    journalDate: entry.journalDate,
                    direction: direction,
                    taxCode: taxCode,
                    accountId: line.accountId,
                    counterpartyId: line.counterpartyId,
                    taxableAmount: taxableAmount,
                    taxAmount: allocatedTaxAmount,
                    deductibleTaxAmount: deductibleTaxAmount,
                    purchaseCreditMethod: purchaseCreditMethod,
                    taxRateBreakdown: taxCode.rateBreakdown(using: pack)
                )
            )
        }

        return worksheetLines
    }

    private static func actualTaxPool(
        for entry: CanonicalJournalEntry,
        legacyAccountId: String,
        accountById: [UUID: CanonicalAccount]
    ) -> Int {
        entry.lines.reduce(0) { partial, line in
            guard accountById[line.accountId]?.legacyAccountId == legacyAccountId else {
                return partial
            }
            return partial + decimalToInt(line.amount)
        }
    }

    private static func decimalToInt(_ value: Decimal) -> Int {
        NSDecimalNumber(decimal: value).intValue
    }

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
