import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class RecurringQueryUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        FeatureFlags.clearOverrides()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
    }

    override func tearDown() {
        FeatureFlags.clearOverrides()
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testFormSnapshotMatchesRecurringFormData() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let project = mutations(dataStore).addProject(name: "定期案件", description: "desc")
        let canonicalAccountId = UUID()
        try await SwiftDataChartOfAccountsRepository(modelContext: context).save(
            CanonicalAccount(
                id: canonicalAccountId,
                businessId: businessId,
                legacyAccountId: "acct-bank",
                code: "102",
                name: "普通預金",
                accountType: .asset,
                normalBalance: .debit,
                defaultLegalReportLineId: LegalReportLine.deposits.rawValue
            )
        )
        let counterparty = Counterparty(
            businessId: businessId,
            displayName: "定期取引先",
            defaultAccountId: canonicalAccountId,
            defaultProjectId: project.id
        )
        try await CounterpartyMasterUseCase(modelContext: context).save(counterparty)

        let useCase = RecurringQueryUseCase(modelContext: context)
        let snapshot = useCase.formSnapshot()
        let paymentAccounts = useCase.paymentAccounts(snapshot: snapshot)
        let defaults = try XCTUnwrap(
            useCase.counterpartyDefaults(
                for: counterparty.id,
                type: .expense,
                snapshot: snapshot
            )
        )

        XCTAssertEqual(snapshot.businessId, businessId)
        XCTAssertTrue(snapshot.activeCategories.contains(where: { $0.id == "cat-tools" }))
        XCTAssertTrue(snapshot.projects.contains(where: { $0.id == project.id }))
        XCTAssertEqual(snapshot.counterparties.map(\.displayName), ["定期取引先"])
        XCTAssertTrue(paymentAccounts.allSatisfy { $0.isPaymentAccount && $0.isActive })
        XCTAssertEqual(defaults.paymentAccountId, "acct-bank")
        XCTAssertEqual(defaults.projectId, project.id)
    }

    func testListSnapshotMatchesRecurringSummaryData() {
        let project = mutations(dataStore).addProject(name: "一覧案件", description: "desc")
        _ = mutations(dataStore).addRecurring(
            name: "有効な定期取引",
            type: .expense,
            amount: 12_000,
            categoryId: "cat-tools",
            memo: "",
            allocationMode: .manual,
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )
        _ = mutations(dataStore).addRecurring(
            name: "年次収益",
            type: .income,
            amount: 24_000,
            categoryId: "cat-sales",
            memo: "",
            allocationMode: .manual,
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .yearly,
            dayOfMonth: 1
        )
        if let created = dataStore.recurringTransactions.first(where: { $0.name == "年次収益" }) {
            mutations(dataStore).updateRecurring(id: created.id, isActive: false)
        }

        let snapshot = RecurringQueryUseCase(modelContext: context).listSnapshot()

        XCTAssertEqual(snapshot.recurringTransactions.count, 2)
        XCTAssertEqual(snapshot.projectNamesById[project.id], "一覧案件")
        XCTAssertEqual(snapshot.categoryNamesById["cat-tools"], "ツール")
        XCTAssertEqual(snapshot.recurringTransactions.first?.name, "年次収益")
    }

    func testHistoryEntriesMatchRecurringHistoryViewOrderingAndLabels() {
        let project = mutations(dataStore).addProject(name: "履歴案件", description: "desc")
        let recurring = mutations(dataStore).addRecurring(
            name: "履歴対象",
            type: .expense,
            amount: 5_000,
            categoryId: "cat-tools",
            memo: "",
            allocationMode: .manual,
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 5_000,
            date: date(2026, 2, 10),
            categoryId: "cat-tools",
            memo: "older",
            allocations: [(projectId: project.id, ratio: 100)],
            recurringId: recurring.id
        )
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 6_000,
            date: date(2026, 3, 10),
            categoryId: "cat-tools",
            memo: "newer",
            allocations: [(projectId: project.id, ratio: 100)],
            recurringId: recurring.id
        )

        let entries = RecurringQueryUseCase(modelContext: context).historyEntries(recurringId: recurring.id)

        XCTAssertEqual(entries.map(\.amount), [6_000, 5_000])
        XCTAssertEqual(entries.first?.categoryName, "ツール")
        XCTAssertEqual(entries.first?.projectNames, ["履歴案件"])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }
}
