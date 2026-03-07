import XCTest
@testable import ProjectProfit

final class TaxStatusMachineTests: XCTestCase {

    // MARK: - 消費税ステータス遷移

    func testExemptToTaxable() {
        XCTAssertTrue(TaxStatusMachine.isValidVatTransition(
            from: .exempt, to: .taxable, invoiceStatus: .unknown
        ))
    }

    func testTaxableToExemptWhenNotRegistered() {
        XCTAssertTrue(TaxStatusMachine.isValidVatTransition(
            from: .taxable, to: .exempt, invoiceStatus: .unregistered
        ))
    }

    func testTaxableToExemptBlockedWhenRegistered() {
        XCTAssertFalse(TaxStatusMachine.isValidVatTransition(
            from: .taxable, to: .exempt, invoiceStatus: .registered
        ))
    }

    // MARK: - 控除と記帳方式の整合性

    func test65万RequiresDoubleEntry() {
        XCTAssertTrue(TaxStatusMachine.isValidDeductionForBookkeeping(
            deductionLevel: .sixtyFive,
            bookkeepingBasis: .doubleEntry,
            electronicBookLevel: .none
        ))
        XCTAssertFalse(TaxStatusMachine.isValidDeductionForBookkeeping(
            deductionLevel: .sixtyFive,
            bookkeepingBasis: .singleEntry,
            electronicBookLevel: .none
        ))
    }

    func test55万RequiresDoubleEntry() {
        XCTAssertTrue(TaxStatusMachine.isValidDeductionForBookkeeping(
            deductionLevel: .fiftyFive,
            bookkeepingBasis: .doubleEntry,
            electronicBookLevel: .none
        ))
        XCTAssertFalse(TaxStatusMachine.isValidDeductionForBookkeeping(
            deductionLevel: .fiftyFive,
            bookkeepingBasis: .singleEntry,
            electronicBookLevel: .none
        ))
    }

    func test10万AllowsSingleEntry() {
        XCTAssertTrue(TaxStatusMachine.isValidDeductionForBookkeeping(
            deductionLevel: .ten,
            bookkeepingBasis: .singleEntry,
            electronicBookLevel: .none
        ))
    }

    // MARK: - 年度ロック遷移

    func testValidLockTransitions() {
        XCTAssertTrue(TaxStatusMachine.isValidLockTransition(from: .open, to: .softClose))
        XCTAssertTrue(TaxStatusMachine.isValidLockTransition(from: .softClose, to: .taxClose))
        XCTAssertTrue(TaxStatusMachine.isValidLockTransition(from: .taxClose, to: .filed))
        XCTAssertTrue(TaxStatusMachine.isValidLockTransition(from: .filed, to: .finalLock))
    }

    func testSoftCloseCanReopen() {
        XCTAssertTrue(TaxStatusMachine.isValidLockTransition(from: .softClose, to: .open))
    }

    func testFinalLockCannotRevert() {
        XCTAssertFalse(TaxStatusMachine.isValidLockTransition(from: .finalLock, to: .filed))
        XCTAssertFalse(TaxStatusMachine.isValidLockTransition(from: .finalLock, to: .open))
    }

    func testFiledCannotGoToOpen() {
        XCTAssertFalse(TaxStatusMachine.isValidLockTransition(from: .filed, to: .open))
    }

    // MARK: - プロフィール全体バリデーション

    func testWhiteWithBlueDeductionIsError() {
        let profile = TaxYearProfile(
            businessId: UUID(),
            taxYear: 2025,
            filingStyle: .white,
            blueDeductionLevel: .sixtyFive
        )
        let issues = TaxStatusMachine.validate(profile)
        XCTAssertTrue(issues.contains { $0.field == "blueDeductionLevel" && $0.severity == .error })
    }

    func testCashBasisWith65万IsError() {
        let profile = TaxYearProfile(
            businessId: UUID(),
            taxYear: 2025,
            filingStyle: .blueCashBasis,
            blueDeductionLevel: .sixtyFive
        )
        let issues = TaxStatusMachine.validate(profile)
        XCTAssertTrue(issues.contains { $0.field == "blueDeductionLevel" && $0.severity == .error })
    }

    func testSimplifiedWithoutCategoryIsError() {
        let profile = TaxYearProfile(
            businessId: UUID(),
            taxYear: 2025,
            vatStatus: .taxable,
            vatMethod: .simplified,
            simplifiedBusinessCategory: nil
        )
        let issues = TaxStatusMachine.validate(profile)
        XCTAssertTrue(issues.contains { $0.field == "simplifiedBusinessCategory" && $0.severity == .error })
    }

    func testValidProfileHasNoErrors() {
        let profile = TaxYearProfile(
            businessId: UUID(),
            taxYear: 2025,
            filingStyle: .blueGeneral,
            blueDeductionLevel: .sixtyFive,
            bookkeepingBasis: .doubleEntry,
            vatStatus: .exempt
        )
        let issues = TaxStatusMachine.validate(profile)
        let errors = issues.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty, "Valid profile should have no errors, got: \(errors)")
    }
}
