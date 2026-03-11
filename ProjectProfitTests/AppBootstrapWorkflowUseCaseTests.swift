import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class AppBootstrapWorkflowUseCaseTests: XCTestCase {
    func testInitializeMatchesDirectBootstrapState() async throws {
        let containerA = try TestModelContainer.create()
        let storeA = ProjectProfit.DataStore(modelContext: ModelContext(containerA))

        let containerB = try TestModelContainer.create()
        let storeB = ProjectProfit.DataStore(modelContext: ModelContext(containerB))

        try await AppBootstrapWorkflowUseCase().initialize(dataStore: storeA)

        storeB.loadData()
        _ = await ProfileSettingsWorkflowUseCase(dataStore: storeB).loadProfile()
        storeB.recalculateAllPartialPeriodProjects()

        XCTAssertEqual(storeA.projects.count, storeB.projects.count)
        XCTAssertEqual(storeA.transactions.count, storeB.transactions.count)
        XCTAssertEqual(storeA.recurringTransactions.count, storeB.recurringTransactions.count)
        XCTAssertEqual(storeA.categories.count, storeB.categories.count)
        XCTAssertEqual(storeA.accounts.count, storeB.accounts.count)
        XCTAssertEqual(storeA.currentTaxYearProfile?.taxYear, storeB.currentTaxYearProfile?.taxYear)
        XCTAssertEqual(storeA.businessProfile != nil, storeB.businessProfile != nil)
        XCTAssertFalse(storeA.isLoading)
    }

    func testInitializeLoadsCanonicalProfileState() async throws {
        let container = try TestModelContainer.create()
        let context = ModelContext(container)
        let businessId = UUID()
        let business = BusinessProfile(
            id: businessId,
            ownerName: "田中太郎",
            businessName: "田中商店"
        )
        let taxYear = TaxYearProfile(
            businessId: businessId,
            taxYear: 2026,
            filingStyle: .blueGeneral,
            yearLockState: .taxClose,
            taxPackVersion: "2026-v1"
        )
        context.insert(BusinessProfileEntityMapper.toEntity(business))
        context.insert(TaxYearProfileEntityMapper.toEntity(taxYear))
        try context.save()

        let store = ProjectProfit.DataStore(modelContext: context)
        try await AppBootstrapWorkflowUseCase().initialize(dataStore: store)

        XCTAssertEqual(store.businessProfile?.id, businessId)
        XCTAssertEqual(store.businessProfile?.businessName, "田中商店")
        XCTAssertEqual(store.currentTaxYearProfile?.taxYear, 2026)
        XCTAssertEqual(store.currentTaxYearProfile?.yearLockState, .taxClose)
    }

    func testInitializeRecalculatesPartialPeriodProjects() async throws {
        let container = try TestModelContainer.create()
        let context = ModelContext(container)
        let setupStore = ProjectProfit.DataStore(modelContext: context)
        setupStore.loadData()

        let projectA = setupStore.addProject(name: "Project A", description: "")
        let projectB = setupStore.addProject(name: "Project B", description: "")
        let transactionDate = Self.makeDate(year: 2024, month: 2, day: 28)
        _ = setupStore.addTransaction(
            type: .expense,
            amount: 10_000,
            date: transactionDate,
            categoryId: "cat-hosting",
            memo: "startup recalc",
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ]
        )

        let storedProjectA = try XCTUnwrap(setupStore.getProject(id: projectA.id))
        storedProjectA.status = .completed
        storedProjectA.completedAt = Self.makeDate(year: 2024, month: 2, day: 15)
        try context.save()

        let bootStore = ProjectProfit.DataStore(modelContext: context)
        try await AppBootstrapWorkflowUseCase().initialize(dataStore: bootStore)

        let transaction = try XCTUnwrap(bootStore.transactions.first)
        let allocationA = try XCTUnwrap(transaction.allocations.first { $0.projectId == projectA.id })
        let allocationB = try XCTUnwrap(transaction.allocations.first { $0.projectId == projectB.id })

        XCTAssertEqual(allocationA.amount, 2586)
        XCTAssertEqual(allocationB.amount, 7414)
        XCTAssertEqual(allocationA.amount + allocationB.amount, 10_000)
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date {
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: year,
            month: month,
            day: day
        )
        return components.date!
    }
}
