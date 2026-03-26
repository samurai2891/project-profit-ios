import XCTest
@testable import ProjectProfit

final class TaxRuleEvaluatorTests: XCTestCase {
    private let businessId = UUID()

    func testEvaluateDecisionReturnsNotApplicableForExemptProfile() {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            vatStatus: .exempt,
            vatMethod: .general
        )

        let decision = TaxRuleEvaluator(profile: profile).evaluateInputTaxDeductionDecision(
            transactionDate: makeDate(year: 2025, month: 4, day: 1),
            counterpartyInvoiceStatus: .registered,
            amount: 11_000
        )

        XCTAssertEqual(decision.creditMethod, .notApplicable)
        XCTAssertEqual(decision.calculationMode, .lineBased)
        XCTAssertEqual(decision.creditRate, 0)
        XCTAssertFalse(decision.requiresReview)
    }

    func testEvaluateDecisionReturnsQualifiedInvoiceForRegisteredCounterparty() {
        let profile = taxableGeneralProfile()

        let decision = TaxRuleEvaluator(profile: profile).evaluateInputTaxDeductionDecision(
            transactionDate: makeDate(year: 2025, month: 4, day: 1),
            counterpartyInvoiceStatus: .registered,
            amount: 11_000
        )

        XCTAssertEqual(decision.creditMethod, .qualifiedInvoice)
        XCTAssertEqual(decision.calculationMode, .lineBased)
        XCTAssertEqual(decision.creditRate, 1)
        XCTAssertFalse(decision.requiresReview)
    }

    func testEvaluateDecisionReturnsSmallAmountSpecialForUnregisteredSmallAmount() {
        let profile = taxableGeneralProfile()

        let decision = TaxRuleEvaluator(profile: profile).evaluateInputTaxDeductionDecision(
            transactionDate: makeDate(year: 2025, month: 4, day: 1),
            counterpartyInvoiceStatus: .unregistered,
            amount: 9_999
        )

        XCTAssertEqual(decision.creditMethod, .smallAmountSpecial)
        XCTAssertEqual(decision.creditRate, 1)
    }

    func testEvaluateDecisionReturnsTransitionalRatesAndNotDeductibleForUnregisteredCounterparty() {
        let profile = taxableGeneralProfile()
        let evaluator = TaxRuleEvaluator(profile: profile)

        let transitional80 = evaluator.evaluateInputTaxDeductionDecision(
            transactionDate: makeDate(year: 2026, month: 9, day: 30),
            counterpartyInvoiceStatus: .unregistered,
            amount: 20_000
        )
        let transitional50 = evaluator.evaluateInputTaxDeductionDecision(
            transactionDate: makeDate(year: 2026, month: 10, day: 1),
            counterpartyInvoiceStatus: .unregistered,
            amount: 20_000
        )
        let notDeductible = evaluator.evaluateInputTaxDeductionDecision(
            transactionDate: makeDate(year: 2030, month: 1, day: 1),
            counterpartyInvoiceStatus: .unregistered,
            amount: 20_000
        )

        XCTAssertEqual(transitional80.creditMethod, .transitional80)
        XCTAssertEqual(transitional80.creditRate, Decimal(string: "0.8")!)
        XCTAssertEqual(transitional50.creditMethod, .transitional50)
        XCTAssertEqual(transitional50.creditRate, Decimal(string: "0.5")!)
        XCTAssertEqual(notDeductible.creditMethod, .notDeductible)
        XCTAssertEqual(notDeductible.creditRate, 0)
    }

    func testEvaluateDecisionReturnsRequiresReviewForUnknownCounterpartyStatus() {
        let profile = taxableGeneralProfile()

        let decision = TaxRuleEvaluator(profile: profile).evaluateInputTaxDeductionDecision(
            transactionDate: makeDate(year: 2025, month: 4, day: 1),
            counterpartyInvoiceStatus: .unknown,
            amount: 11_000
        )

        XCTAssertEqual(decision.creditMethod, .requiresReview)
        XCTAssertEqual(decision.calculationMode, .lineBased)
        XCTAssertTrue(decision.requiresReview)
        XCTAssertEqual(decision.creditRate, 0)
    }

    func testEvaluateDecisionUsesPackDeemedPurchaseRateForSimplifiedTaxation() {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            vatStatus: .taxable,
            vatMethod: .simplified,
            simplifiedBusinessCategory: 2
        )
        let pack = TaxYearPack(
            taxYear: 2025,
            version: "2025-v1",
            simplifiedDeemedPurchaseRates: [2: Decimal(string: "0.55")!]
        )

        let decision = TaxRuleEvaluator(profile: profile, pack: pack).evaluateInputTaxDeductionDecision(
            transactionDate: makeDate(year: 2025, month: 4, day: 1),
            counterpartyInvoiceStatus: .registered,
            amount: 11_000
        )

        XCTAssertEqual(decision.creditMethod, .simplifiedEstimate)
        XCTAssertEqual(
            decision.calculationMode,
            .simplified(deemedPurchaseRate: Decimal(string: "0.55")!)
        )
        XCTAssertEqual(decision.creditRate, Decimal(string: "0.55")!)
        XCTAssertEqual(decision.deemedPurchaseRate, Decimal(string: "0.55")!)
        XCTAssertFalse(decision.requiresReview)
    }

    func testEvaluateDecisionReturnsRequiresReviewWhenSimplifiedCategoryIsMissing() {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            vatStatus: .taxable,
            vatMethod: .simplified,
            simplifiedBusinessCategory: nil
        )

        let decision = TaxRuleEvaluator(profile: profile).evaluateInputTaxDeductionDecision(
            transactionDate: makeDate(year: 2025, month: 4, day: 1),
            counterpartyInvoiceStatus: .registered,
            amount: 11_000
        )

        XCTAssertEqual(decision.creditMethod, .requiresReview)
        XCTAssertEqual(decision.calculationMode, .reviewRequired)
        XCTAssertEqual(decision.creditRate, 0)
        XCTAssertTrue(decision.requiresReview)
    }

    func testEvaluateDecisionReturnsTwoTenthsMode() {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            vatStatus: .taxable,
            vatMethod: .twoTenths
        )

        let decision = TaxRuleEvaluator(profile: profile).evaluateInputTaxDeductionDecision(
            transactionDate: makeDate(year: 2025, month: 4, day: 1),
            counterpartyInvoiceStatus: .registered,
            amount: 11_000
        )

        XCTAssertEqual(decision.creditMethod, .twoTenthsEstimate)
        XCTAssertEqual(
            decision.calculationMode,
            .twoTenths(creditRate: Decimal(string: "0.8")!)
        )
        XCTAssertEqual(decision.creditRate, Decimal(string: "0.8")!)
        XCTAssertFalse(decision.requiresReview)
    }

    private func taxableGeneralProfile() -> TaxYearProfile {
        TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            vatStatus: .taxable,
            vatMethod: .general
        )
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }
}
