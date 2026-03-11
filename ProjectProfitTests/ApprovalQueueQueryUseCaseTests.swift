import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ApprovalQueueQueryUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    func testCurrentBusinessIdAndReloadKeyUseDefaultBusinessProfile() throws {
        let businessId = UUID()
        try seedBusinessProfile(id: businessId)

        let useCase = ApprovalQueueQueryUseCase(modelContext: context)

        XCTAssertEqual(useCase.currentBusinessId(), businessId)
        XCTAssertEqual(
            useCase.reloadKey(selectedFilterRawValue: "pending"),
            "\(businessId.uuidString):pending"
        )
    }

    func testReloadKeyFallsBackToNoneWithoutBusinessProfile() {
        let useCase = ApprovalQueueQueryUseCase(modelContext: context)

        XCTAssertNil(useCase.currentBusinessId())
        XCTAssertEqual(useCase.reloadKey(selectedFilterRawValue: "draft"), "none:draft")
        XCTAssertFalse(useCase.isYearLocked(date: date(2026, 3, 11)))
        XCTAssertTrue(useCase.canonicalAccounts().isEmpty)
    }

    func testIsYearLockedMatchesStoredTaxYearProfile() throws {
        let businessId = UUID()
        try seedBusinessProfile(id: businessId)
        try seedTaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            state: .finalLock
        )

        let useCase = ApprovalQueueQueryUseCase(
            modelContext: context,
            startMonth: 4
        )

        XCTAssertTrue(useCase.isYearLocked(date: date(2026, 3, 11)))
        XCTAssertFalse(useCase.isYearLocked(date: date(2026, 4, 1)))
    }

    func testCanonicalAccountsAndProjectsPreserveCurrentOrdering() async throws {
        let businessId = UUID()
        try seedBusinessProfile(id: businessId)

        let laterProject = PPProject(
            name: "後発案件",
            createdAt: date(2025, 2, 10),
            updatedAt: date(2025, 2, 10)
        )
        let earlierProject = PPProject(
            name: "先発案件",
            createdAt: date(2025, 1, 10),
            updatedAt: date(2025, 1, 10)
        )
        context.insert(earlierProject)
        context.insert(laterProject)
        try context.save()

        let repo = SwiftDataChartOfAccountsRepository(modelContext: context)
        try await repo.save(
            CanonicalAccount(
                businessId: businessId,
                code: "500",
                name: "旅費交通費",
                accountType: .expense,
                normalBalance: .debit,
                defaultLegalReportLineId: LegalReportLine.travelTransport.rawValue,
                displayOrder: 2,
                createdAt: date(2025, 1, 1),
                updatedAt: date(2025, 1, 1)
            )
        )
        try await repo.save(
            CanonicalAccount(
                businessId: businessId,
                code: "100",
                name: "普通預金",
                accountType: .asset,
                normalBalance: .debit,
                defaultLegalReportLineId: LegalReportLine.deposits.rawValue,
                displayOrder: 0,
                createdAt: date(2025, 1, 1),
                updatedAt: date(2025, 1, 1)
            )
        )

        let useCase = ApprovalQueueQueryUseCase(modelContext: context)

        XCTAssertEqual(useCase.availableProjects().map(\.name), ["後発案件", "先発案件"])
        XCTAssertEqual(useCase.projectName(id: earlierProject.id), "先発案件")
        XCTAssertEqual(useCase.canonicalAccounts().map(\.code), ["100", "500"])
    }

    private func seedBusinessProfile(id: UUID) throws {
        context.insert(
            BusinessProfileEntity(
                businessId: id,
                ownerName: "テスト事業者",
                createdAt: date(2025, 1, 1),
                updatedAt: date(2025, 1, 1)
            )
        )
        try context.save()
    }

    private func seedTaxYearProfile(
        businessId: UUID,
        taxYear: Int,
        state: YearLockState
    ) throws {
        context.insert(
            TaxYearProfileEntity(
                businessId: businessId,
                taxYear: taxYear,
                yearLockStateRaw: state.rawValue,
                taxPackVersion: "\(taxYear)-v1",
                createdAt: date(2025, 1, 1),
                updatedAt: date(2025, 1, 1)
            )
        )
        try context.save()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }
}
