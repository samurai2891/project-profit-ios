import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class WhiteTaxBookkeepingQueryUseCaseTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = container.mainContext
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
    }

    override func tearDown() {
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testWhiteTaxBookkeepingSnapshotReflectsCanonicalProfitLoss() {
        let project = mutations(dataStore).addProject(name: "White Book", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 300_000,
            date: makeDate(year: 2025, month: 4, day: 10),
            categoryId: "cat-sales",
            memo: "売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: AccountingConstants.cashAccountId
        )
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 80_000,
            date: makeDate(year: 2025, month: 4, day: 15),
            categoryId: "cat-rent",
            memo: "家賃",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: AccountingConstants.cashAccountId
        )

        let snapshot = WhiteTaxBookkeepingQueryUseCase(modelContext: context).snapshot(taxYear: 2025)

        XCTAssertEqual(snapshot.totalRevenue, 300_000)
        XCTAssertEqual(snapshot.totalExpenses, 80_000)
        XCTAssertEqual(snapshot.netIncome, 220_000)
        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertTrue(snapshot.revenueRows.contains { $0.id == "shushi_revenue_total" && $0.amount == 300_000 })
        XCTAssertTrue(snapshot.expenseRows.contains { $0.id == "shushi_expense_rent" && $0.amount == 80_000 })
    }

    func testWhiteTaxBookkeepingSnapshotIsEmptyForYearWithoutData() {
        let snapshot = WhiteTaxBookkeepingQueryUseCase(modelContext: context).snapshot(taxYear: 2030)

        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertEqual(snapshot.totalRevenue, 0)
        XCTAssertEqual(snapshot.totalExpenses, 0)
        XCTAssertEqual(snapshot.netIncome, 0)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
