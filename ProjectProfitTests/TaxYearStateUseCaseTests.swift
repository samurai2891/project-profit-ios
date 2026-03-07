import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class TaxYearStateUseCaseTests: XCTestCase {
    func testTransitionYearLockPersistsAllowedStateChange() throws {
        let container = try TestModelContainer.create()
        let context = container.mainContext
        let useCase = TaxYearStateUseCase(modelContext: context)
        let businessId = UUID()

        let initial = TaxYearProfile(
            businessId: businessId,
            taxYear: 2026,
            yearLockState: .open
        )
        context.insert(TaxYearProfileEntityMapper.toEntity(initial))
        try context.save()

        let updated = try useCase.transitionYearLock(
            businessId: businessId,
            taxYear: 2026,
            targetState: .softClose
        )

        XCTAssertEqual(updated.yearLockState, .softClose)

        let descriptor = FetchDescriptor<TaxYearProfileEntity>(
            predicate: #Predicate {
                $0.businessId == businessId && $0.taxYear == 2026
            }
        )
        let persisted = try context.fetch(descriptor).first
        XCTAssertEqual(persisted?.yearLockStateRaw, YearLockState.softClose.rawValue)
    }

    func testValidateTransitionRejectsDirectFinalLockJump() {
        let businessId = UUID()
        let current = TaxYearProfile(
            businessId: businessId,
            taxYear: 2026,
            yearLockState: .open
        )
        let proposed = current.updated(yearLockState: .finalLock)

        XCTAssertThrowsError(
            try TaxYearStateUseCase.validateTransition(from: current, to: proposed)
        ) { error in
            XCTAssertEqual(
                error as? TaxYearStateUseCaseError,
                .validationFailed("年度状態を未締めから最終確定へ変更できません")
            )
        }
    }

    func testFilingPreflightIssuesExposeTaxStatusErrors() {
        let profile = TaxYearProfile(
            businessId: UUID(),
            taxYear: 2026,
            filingStyle: .blueGeneral,
            blueDeductionLevel: .sixtyFive,
            bookkeepingBasis: .doubleEntry,
            vatStatus: .taxable,
            vatMethod: .simplified,
            simplifiedBusinessCategory: nil
        )

        let issues = TaxYearStateUseCase.filingPreflightIssues(for: profile)

        XCTAssertTrue(
            issues.contains(where: {
                $0.severity == .error &&
                    $0.field == "simplifiedBusinessCategory"
            })
        )
    }
}
