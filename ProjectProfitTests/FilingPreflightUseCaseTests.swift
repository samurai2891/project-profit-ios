import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class FilingPreflightUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var businessId: UUID!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        businessId = dataStore.businessProfile?.id
        XCTAssertNotNil(businessId)
    }

    override func tearDown() {
        businessId = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testExportPreflightFailsBelowTaxClose() throws {
        seedTaxYearProfile(year: 2025, state: .softClose)

        let report = try FilingPreflightUseCase(modelContext: context).preflightReport(
            businessId: businessId,
            taxYear: 2025,
            context: .export
        )

        XCTAssertTrue(report.issues.contains { $0.code == .yearStateTooOpen })
        XCTAssertTrue(report.issues.contains { $0.message == "帳票出力は税務締め以降でのみ実行できます" })
    }

    func testExportPreflightDetectsPendingCandidate() throws {
        seedTaxYearProfile(year: 2025, state: .taxClose)
        let candidate = PostingCandidate(
            businessId: businessId,
            taxYear: 2025,
            candidateDate: makeDate(year: 2025, month: 6, day: 1),
            proposedLines: [
                PostingCandidateLine(
                    debitAccountId: UUID(),
                    creditAccountId: UUID(),
                    amount: Decimal(string: "1000")!
                )
            ],
            status: .needsReview,
            source: .manual
        )
        try context.save()
        let entity = PostingCandidateEntityMapper.toEntity(candidate)
        context.insert(entity)
        try context.save()

        let report = try FilingPreflightUseCase(modelContext: context).preflightReport(
            businessId: businessId,
            taxYear: 2025,
            context: .export
        )

        XCTAssertTrue(report.issues.contains { $0.code == .pendingCandidateExists })
    }

    func testExportPreflightDetectsSuspenseBalance() throws {
        _ = dataStore.addManualJournalEntry(
            date: makeDate(year: 2025, month: 6, day: 1),
            memo: "仮勘定残",
            lines: [
                (accountId: AccountingConstants.suspenseAccountId, debit: 1200, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 1200, memo: ""),
            ]
        )
        seedTaxYearProfile(year: 2025, state: .taxClose)

        let report = try FilingPreflightUseCase(modelContext: context).preflightReport(
            businessId: businessId,
            taxYear: 2025,
            context: .export
        )

        XCTAssertTrue(report.issues.contains { $0.code == .suspenseBalanceRemaining })
    }

    func testClosingPreflightRequiresClosingEntryForTaxClose() throws {
        let report = try FilingPreflightUseCase(modelContext: context).preflightReport(
            businessId: businessId,
            taxYear: 2025,
            context: .closing(targetState: .taxClose)
        )

        XCTAssertTrue(report.issues.contains { $0.code == .closingEntryMissing })
    }

    func testClosingPreflightDetectsUnbalancedJournal() throws {
        _ = dataStore.addManualJournalEntry(
            date: makeDate(year: 2025, month: 6, day: 1),
            memo: "未確定仕訳",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 1200, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 1000, memo: ""),
            ]
        )

        let report = try FilingPreflightUseCase(modelContext: context).preflightReport(
            businessId: businessId,
            taxYear: 2025,
            context: .closing(targetState: .softClose)
        )

        XCTAssertTrue(report.issues.contains { $0.code == .unbalancedJournal })
    }

    private func seedTaxYearProfile(year: Int, state: YearLockState) {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: year,
            yearLockState: state,
            taxPackVersion: "\(year)-v1"
        )
        context.insert(TaxYearProfileEntityMapper.toEntity(profile))
        try! context.save()
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
