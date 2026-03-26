import XCTest
@testable import ProjectProfit

final class InputTaxDeductionCalculatorTests: XCTestCase {
    func testDeductibleTaxAmountUsesLineBasedCreditRate() {
        let calculator = InputTaxDeductionCalculator()
        let decision = InputTaxDeductionDecision(
            creditMethod: .transitional80,
            calculationMode: .lineBased,
            creditRate: Decimal(string: "0.8")!,
            deemedPurchaseRate: nil,
            requiresReview: false
        )

        let deductible = calculator.deductibleTaxAmount(
            taxAmount: 500,
            decision: decision
        )

        XCTAssertEqual(deductible, Decimal(string: "400")!)
    }

    func testDeductibleTaxAmountUsesSimplifiedRateFromDecision() {
        let calculator = InputTaxDeductionCalculator()
        let decision = InputTaxDeductionDecision(
            creditMethod: .simplifiedEstimate,
            calculationMode: .simplified(deemedPurchaseRate: Decimal(string: "0.6")!),
            creditRate: Decimal(string: "0.6")!,
            deemedPurchaseRate: Decimal(string: "0.6")!,
            requiresReview: false
        )

        let deductible = calculator.deductibleTaxAmount(
            taxAmount: 500,
            decision: decision
        )

        XCTAssertEqual(deductible, Decimal(string: "300")!)
    }

    func testWorksheetDeductibleInputTaxTotalUsesSimplifiedAndTwoTenthsModes() {
        let calculator = InputTaxDeductionCalculator()

        let simplifiedTotal = calculator.worksheetDeductibleInputTaxTotal(
            outputTaxTotal: 1_000,
            provisionalInputDeductibleTotal: 500,
            calculationMode: .simplified(deemedPurchaseRate: Decimal(string: "0.6")!)
        )
        let twoTenthsTotal = calculator.worksheetDeductibleInputTaxTotal(
            outputTaxTotal: 1_000,
            provisionalInputDeductibleTotal: 500,
            calculationMode: .twoTenths(creditRate: Decimal(string: "0.8")!)
        )

        XCTAssertEqual(simplifiedTotal, 600)
        XCTAssertEqual(twoTenthsTotal, 800)
    }

    func testReviewRequiredReturnsZeroForLineAndWorksheetCalculations() {
        let calculator = InputTaxDeductionCalculator()
        let decision = InputTaxDeductionDecision(
            creditMethod: .requiresReview,
            calculationMode: .reviewRequired,
            creditRate: 0,
            deemedPurchaseRate: nil,
            requiresReview: true
        )

        XCTAssertEqual(
            calculator.deductibleTaxAmount(
                taxAmount: 500,
                decision: decision
            ),
            0
        )
        XCTAssertEqual(
            calculator.worksheetDeductibleInputTaxTotal(
                outputTaxTotal: 1_000,
                provisionalInputDeductibleTotal: 500,
                calculationMode: .reviewRequired
            ),
            0
        )
    }

    func testDistributeWorksheetDeductionAllocatesByTaxAmountWeight() {
        let calculator = InputTaxDeductionCalculator()
        let lines = [
            makeInputLine(taxAmount: 200, deductibleTaxAmount: 0),
            makeInputLine(taxAmount: 100, deductibleTaxAmount: 0),
            makeOutputLine(taxAmount: 300)
        ]

        let distributed = calculator.distributeWorksheetDeduction(
            targetDeductibleTaxAmount: 600,
            lines: lines
        )

        XCTAssertEqual(distributed[0].deductibleTaxAmount, 400)
        XCTAssertEqual(distributed[1].deductibleTaxAmount, 200)
        XCTAssertEqual(distributed[2].deductibleTaxAmount, 0)
    }

    private func makeInputLine(taxAmount: Int, deductibleTaxAmount: Int) -> ConsumptionTaxWorksheetLine {
        ConsumptionTaxWorksheetLine(
            id: UUID(),
            journalId: UUID(),
            journalDate: Date(),
            direction: .input,
            taxCode: .standard10,
            accountId: UUID(),
            counterpartyId: nil,
            taxableAmount: taxAmount * 10,
            taxAmount: taxAmount,
            deductibleTaxAmount: deductibleTaxAmount,
            purchaseCreditMethod: .qualifiedInvoice,
            taxRateBreakdown: TaxRateBreakdown(
                totalRate: Decimal(string: "0.10")!,
                nationalRate: Decimal(string: "0.078")!,
                localRate: Decimal(string: "0.022")!
            )
        )
    }

    private func makeOutputLine(taxAmount: Int) -> ConsumptionTaxWorksheetLine {
        ConsumptionTaxWorksheetLine(
            id: UUID(),
            journalId: UUID(),
            journalDate: Date(),
            direction: .output,
            taxCode: .standard10,
            accountId: UUID(),
            counterpartyId: nil,
            taxableAmount: taxAmount * 10,
            taxAmount: taxAmount,
            deductibleTaxAmount: 0,
            purchaseCreditMethod: nil,
            taxRateBreakdown: TaxRateBreakdown(
                totalRate: Decimal(string: "0.10")!,
                nationalRate: Decimal(string: "0.078")!,
                localRate: Decimal(string: "0.022")!
            )
        )
    }
}
