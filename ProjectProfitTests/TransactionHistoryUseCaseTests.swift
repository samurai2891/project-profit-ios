import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class TransactionHistoryUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: TransactionHistoryUseCase!

    override func setUp() {
        super.setUp()
        FeatureFlags.clearOverrides()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = TransactionHistoryUseCase(modelContext: context)
    }

    override func tearDown() {
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        FeatureFlags.clearOverrides()
        super.tearDown()
    }

    func testFilteredTransactionsMatchesDataStoreForCombinedFiltersAndSort() {
        let alpha = mutations(dataStore).addProject(name: "Alpha", description: "")
        let beta = mutations(dataStore).addProject(name: "Beta", description: "")

        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 12_000,
            date: makeDate(2025, 1, 10),
            categoryId: "cat-sales",
            memo: "Alpha invoice",
            allocations: [(projectId: alpha.id, ratio: 100)],
            counterparty: "Alpha Client"
        )
        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 9_000,
            date: makeDate(2025, 1, 20),
            categoryId: "cat-sales",
            memo: "Beta invoice",
            allocations: [(projectId: beta.id, ratio: 100)],
            counterparty: "Beta Client"
        )
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 4_000,
            date: makeDate(2025, 1, 25),
            categoryId: "cat-hosting",
            memo: "Alpha hosting",
            allocations: [(projectId: alpha.id, ratio: 100)],
            counterparty: "Infra Vendor"
        )

        let filter = TransactionFilter(
            startDate: makeDate(2025, 1, 1),
            endDate: makeDate(2025, 1, 31),
            projectId: alpha.id,
            categoryId: "cat-sales",
            type: .income,
            searchText: "invoice",
            amountMin: 10_000,
            amountMax: 15_000,
            counterparty: "Alpha"
        )
        let sort = TransactionSort(field: .amount, order: .desc)

        let expected = dataStore.getFilteredTransactions(filter: filter, sort: sort).map(\.id)
        let actual = useCase.filteredTransactions(filter: filter, sort: sort).map(\.id)

        XCTAssertEqual(actual, expected)
    }

    func testFilteredTransactionsMatchesDataStoreForSearchAndCounterpartyFiltering() {
        let project = mutations(dataStore).addProject(name: "Alpha", description: "")

        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 3_000,
            date: makeDate(2025, 2, 1),
            categoryId: "cat-supplies",
            memo: "Stationery order",
            allocations: [(projectId: project.id, ratio: 100)],
            counterparty: "Tokyo Store"
        )
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 5_000,
            date: makeDate(2025, 2, 2),
            categoryId: "cat-supplies",
            memo: "Other memo",
            allocations: [(projectId: project.id, ratio: 100)],
            counterparty: "Osaka Vendor"
        )

        let filter = TransactionFilter(
            searchText: "stationery",
            counterparty: "tokyo"
        )

        let expected = dataStore.getFilteredTransactions(filter: filter).map(\.id)
        let actual = useCase.filteredTransactions(filter: filter).map(\.id)

        XCTAssertEqual(actual, expected)
    }

    func testDisplayHelpersResolveCurrentValues() throws {
        let project = mutations(dataStore).addProject(name: "Client A", description: "")
        let recurring = mutations(dataStore).addRecurring(
            name: "家賃",
            type: .expense,
            amount: 80_000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )
        let transaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 8_000,
            date: makeDate(2025, 3, 3),
            categoryId: "cat-hosting",
            memo: "Server",
            allocations: [(projectId: project.id, ratio: 100)],
            recurringId: recurring.id
        )

        context.insert(
            PPDocumentRecord(
                transactionId: transaction.id,
                documentType: .receipt,
                storedFileName: "doc.pdf",
                originalFileName: "doc.pdf",
                fileSize: 10,
                issueDate: makeDate(2025, 3, 3)
            )
        )
        try context.save()

        XCTAssertEqual(useCase.categoryName(for: transaction.categoryId), "ホスティング")
        XCTAssertEqual(useCase.categoryIcon(for: transaction.categoryId), "server.rack")
        XCTAssertEqual(useCase.projectNames(for: transaction.allocations), ["Client A"])
        XCTAssertEqual(
            useCase.projectAllocations(for: transaction).map(\.name),
            ["Client A"]
        )
        XCTAssertEqual(useCase.recurringDisplayName(for: recurring.id), "家賃 (毎月)")
        XCTAssertEqual(useCase.documentCount(for: transaction.id), 1)
    }

    func testExportCSVMatchesCurrentGeneratorAndFileNaming() throws {
        let project = mutations(dataStore).addProject(name: "Client A", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .income,
            amount: 11_000,
            date: makeDate(2025, 4, 10),
            categoryId: "cat-sales",
            memo: "April sale",
            allocations: [(projectId: project.id, ratio: 100)],
            counterparty: "Sample Client"
        )
        let transactions = [transaction]

        let url = try useCase.exportCSV(transactions: transactions)
        let exportedData = try Data(contentsOf: url)
        let expected = generateCSV(
            transactions: transactions,
            getCategory: { [category = dataStore.getCategory(id: "cat-sales")] id in
                id == "cat-sales" ? category : nil
            },
            getProject: { [project] id in
                id == project.id ? project : nil
            }
        )

        XCTAssertEqual(exportedData, try XCTUnwrap(expected.data(using: .utf8)))
        XCTAssertEqual(Array(exportedData.prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertEqual(
            url.lastPathComponent,
            ExportCoordinator.makeFileName(target: .transactions, fiscalYear: 2025, format: .csv)
        )
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
