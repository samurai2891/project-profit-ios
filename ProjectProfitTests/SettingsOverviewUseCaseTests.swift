import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class SettingsOverviewUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: SettingsOverviewUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = SettingsOverviewUseCase(
            modelContext: context,
            currentDateProvider: { Self.stableDate(year: 2026, month: 3, day: 11) }
        )
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FiscalYearSettings.userDefaultsKey)
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testSnapshotMatchesCurrentCounts() throws {
        _ = mutations(dataStore).addProject(name: "Settings Project", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 5_000,
            date: Self.stableDate(year: 2025, month: 5, day: 10),
            categoryId: "cat-tools",
            memo: "settings tx",
            allocations: []
        )

        context.insert(
            PPRecurringTransaction(
                name: "定期費用",
                type: .expense,
                amount: 3_000,
                categoryId: "cat-tools"
            )
        )
        try context.save()

        let snapshot = useCase.snapshot(startMonth: 4)

        XCTAssertEqual(snapshot.projectCount, dataStore.projects.count)
        XCTAssertEqual(snapshot.transactionCount, dataStore.transactions.count)
        XCTAssertEqual(snapshot.recurringTransactionCount, 1)
    }

    func testSnapshotMergesTransactionInventoryAndCurrentTaxYear() throws {
        let businessId = UUID()
        context.insert(
            BusinessProfileEntityMapper.toEntity(
                BusinessProfile(
                    id: businessId,
                    ownerName: "設定太郎",
                    businessName: "Settings商店"
                )
            )
        )
        context.insert(PPInventoryRecord(fiscalYear: 2024, openingInventory: 100))

        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 5_000,
            date: Self.stableDate(year: 2025, month: 3, day: 10),
            categoryId: "cat-tools",
            memo: "fy2024",
            allocations: []
        )
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 8_000,
            date: Self.stableDate(year: 2025, month: 4, day: 10),
            categoryId: "cat-tools",
            memo: "fy2025",
            allocations: []
        )

        try context.save()

        let snapshot = useCase.snapshot(startMonth: 4)

        XCTAssertEqual(snapshot.availableBackupYears, [2026, 2025, 2024])
    }

    func testSnapshotIncludesCurrentTaxYearWhenOnlyBootstrapStateExists() {
        let snapshot = useCase.snapshot(startMonth: 4)

        XCTAssertEqual(snapshot.availableBackupYears, [2026])
    }

    private static func stableDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        ))!
    }
}
