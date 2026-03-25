import Foundation

struct ConsumptionTaxWorksheet: Sendable, Equatable {
    let fiscalYear: Int
    let generatedAt: Date
    let lines: [ConsumptionTaxWorksheetLine]
    let outputTaxTotal: Int
    let rawInputTaxTotal: Int
    let deductibleInputTaxTotal: Int

    var taxPayable: Int {
        outputTaxTotal - deductibleInputTaxTotal
    }

    var isRefund: Bool {
        taxPayable < 0
    }
}

struct ConsumptionTaxWorksheetLine: Identifiable, Sendable, Equatable {
    enum Direction: String, Sendable {
        case output
        case input
    }

    let id: UUID
    let journalId: UUID
    let journalDate: Date
    let direction: Direction
    let taxCode: TaxCode
    let accountId: UUID
    let counterpartyId: UUID?
    let taxableAmount: Int
    let taxAmount: Int
    let deductibleTaxAmount: Int
    let purchaseCreditMethod: InputTaxCreditMethod?
    let taxRateBreakdown: TaxRateBreakdown

    func withDeductibleTaxAmount(_ amount: Int) -> ConsumptionTaxWorksheetLine {
        ConsumptionTaxWorksheetLine(
            id: id,
            journalId: journalId,
            journalDate: journalDate,
            direction: direction,
            taxCode: taxCode,
            accountId: accountId,
            counterpartyId: counterpartyId,
            taxableAmount: taxableAmount,
            taxAmount: taxAmount,
            deductibleTaxAmount: amount,
            purchaseCreditMethod: purchaseCreditMethod,
            taxRateBreakdown: taxRateBreakdown
        )
    }
}
