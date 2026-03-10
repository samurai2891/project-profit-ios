import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class RecurringWorkflowUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: RecurringWorkflowUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = RecurringWorkflowUseCase(dataStore: dataStore)
    }

    override func tearDown() {
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testCreateRecurringPersistsUpsertInput() {
        let project = dataStore.addProject(name: "UseCase PJ", description: "desc")
        let categoryId = try! XCTUnwrap(dataStore.activeCategories.first(where: { $0.type == .expense })?.id)
        let endDate = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31))
        let input = makeInput(
            categoryId: categoryId,
            allocations: [RecurringAllocationInput(projectId: project.id, ratio: 100)],
            frequency: .yearly,
            monthOfYear: 4,
            endDate: endDate,
            yearlyAmortizationMode: .monthlySpread,
            receiptImagePath: "receipt.png",
            paymentAccountId: "acct-cash",
            transferToAccountId: "acct-savings",
            taxDeductibleRate: 80,
            counterparty: "取引先A"
        )

        let recurring = useCase.createRecurring(input: input)

        XCTAssertEqual(recurring.name, input.name)
        XCTAssertEqual(recurring.categoryId, categoryId)
        XCTAssertEqual(recurring.frequency, .yearly)
        XCTAssertEqual(recurring.monthOfYear, 4)
        XCTAssertEqual(recurring.yearlyAmortizationMode, .monthlySpread)
        XCTAssertEqual(recurring.receiptImagePath, "receipt.png")
        XCTAssertEqual(recurring.paymentAccountId, "acct-cash")
        XCTAssertEqual(recurring.transferToAccountId, "acct-savings")
        XCTAssertEqual(recurring.taxDeductibleRate, 80)
        XCTAssertEqual(recurring.counterparty, "取引先A")
        XCTAssertEqual(recurring.allocations.count, 1)
        XCTAssertEqual(recurring.allocations.first?.projectId, project.id)
        XCTAssertEqual(dataStore.recurringTransactions.count, 1)
    }

    func testUpdateRecurringReplacesEditableFields() {
        let project = dataStore.addProject(name: "Initial PJ", description: "desc")
        let replacementProject = dataStore.addProject(name: "Updated PJ", description: "desc")
        let categoryId = try! XCTUnwrap(dataStore.activeCategories.first(where: { $0.type == .expense })?.id)
        let recurring = useCase.createRecurring(
            input: makeInput(
                categoryId: categoryId,
                allocations: [RecurringAllocationInput(projectId: project.id, ratio: 100)],
                frequency: .yearly,
                monthOfYear: 9,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1)),
                receiptImagePath: "old.png",
                paymentAccountId: "acct-old",
                transferToAccountId: "acct-old-transfer",
                taxDeductibleRate: 50,
                counterparty: "旧取引先"
            )
        )
        let updatedInput = makeInput(
            name: "更新後の定期取引",
            amount: 12_000,
            categoryId: categoryId,
            allocations: [RecurringAllocationInput(projectId: replacementProject.id, ratio: 100)],
            frequency: .monthly,
            monthOfYear: nil,
            isActive: false,
            endDate: nil,
            yearlyAmortizationMode: .lumpSum,
            receiptImagePath: nil,
            paymentAccountId: nil,
            transferToAccountId: nil,
            taxDeductibleRate: nil,
            counterparty: nil
        )

        useCase.updateRecurring(id: recurring.id, input: updatedInput)

        let updated = try! XCTUnwrap(dataStore.getRecurring(id: recurring.id))
        XCTAssertEqual(updated.name, "更新後の定期取引")
        XCTAssertEqual(updated.amount, 12_000)
        XCTAssertEqual(updated.frequency, .monthly)
        XCTAssertNil(updated.monthOfYear)
        XCTAssertFalse(updated.isActive)
        XCTAssertNil(updated.endDate)
        XCTAssertNil(updated.receiptImagePath)
        XCTAssertNil(updated.paymentAccountId)
        XCTAssertNil(updated.transferToAccountId)
        XCTAssertNil(updated.taxDeductibleRate)
        XCTAssertNil(updated.counterparty)
        XCTAssertEqual(updated.allocations.map(\.projectId), [replacementProject.id])
    }

    func testDeleteRecurringRemovesPersistedRecurring() {
        let project = dataStore.addProject(name: "Delete PJ", description: "desc")
        let categoryId = try! XCTUnwrap(dataStore.activeCategories.first(where: { $0.type == .expense })?.id)
        let recurring = useCase.createRecurring(
            input: makeInput(
                categoryId: categoryId,
                allocations: [RecurringAllocationInput(projectId: project.id, ratio: 100)]
            )
        )

        useCase.deleteRecurring(id: recurring.id)

        XCTAssertNil(dataStore.getRecurring(id: recurring.id))
        XCTAssertTrue(dataStore.recurringTransactions.isEmpty)
    }

    func testSetRecurringActiveUpdatesActiveState() {
        let recurring = makeRecurring()

        useCase.setRecurringActive(id: recurring.id, isActive: false)

        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.isActive, false)
    }

    func testSetRecurringSkippedAddsAndRemovesTargetDateWithoutDuplicates() {
        let recurring = makeRecurring()
        let targetDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 12))!

        useCase.setRecurringSkipped(id: recurring.id, date: targetDate, isSkipped: true)
        useCase.setRecurringSkipped(id: recurring.id, date: targetDate, isSkipped: true)

        let skipped = try! XCTUnwrap(dataStore.getRecurring(id: recurring.id))
        XCTAssertEqual(skipped.skipDates.count, 1)
        XCTAssertTrue(Calendar.current.isDate(skipped.skipDates[0], inSameDayAs: targetDate))

        useCase.setRecurringSkipped(id: recurring.id, date: targetDate, isSkipped: false)

        XCTAssertTrue(dataStore.getRecurring(id: recurring.id)?.skipDates.isEmpty == true)
    }

    func testSetNotificationTimingUpdatesRecurring() {
        let recurring = makeRecurring()

        useCase.setNotificationTiming(id: recurring.id, timing: .dayBefore)

        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.notificationTiming, .dayBefore)
    }

    private func makeRecurring() -> PPRecurringTransaction {
        let project = dataStore.addProject(name: "Recurring PJ", description: "desc")
        let categoryId = try! XCTUnwrap(dataStore.activeCategories.first(where: { $0.type == .expense })?.id)
        return useCase.createRecurring(
            input: makeInput(
                categoryId: categoryId,
                allocations: [RecurringAllocationInput(projectId: project.id, ratio: 100)]
            )
        )
    }

    private func makeInput(
        name: String = "月額サーバー代",
        type: TransactionType = .expense,
        amount: Int = 5_000,
        categoryId: String,
        memo: String = "[定期] 月額サーバー代",
        allocationMode: AllocationMode = .manual,
        allocations: [RecurringAllocationInput],
        frequency: RecurringFrequency = .monthly,
        dayOfMonth: Int = 15,
        monthOfYear: Int? = nil,
        isActive: Bool = true,
        endDate: Date? = nil,
        yearlyAmortizationMode: YearlyAmortizationMode = .lumpSum,
        receiptImagePath: String? = nil,
        paymentAccountId: String? = nil,
        transferToAccountId: String? = nil,
        taxDeductibleRate: Int? = nil,
        counterpartyId: UUID? = nil,
        counterparty: String? = nil
    ) -> RecurringUpsertInput {
        RecurringUpsertInput(
            name: name,
            type: type,
            amount: amount,
            categoryId: categoryId,
            memo: memo,
            allocationMode: allocationMode,
            allocations: allocations,
            frequency: frequency,
            dayOfMonth: dayOfMonth,
            monthOfYear: monthOfYear,
            isActive: isActive,
            endDate: endDate,
            yearlyAmortizationMode: yearlyAmortizationMode,
            receiptImagePath: receiptImagePath,
            paymentAccountId: paymentAccountId,
            transferToAccountId: transferToAccountId,
            taxDeductibleRate: taxDeductibleRate,
            counterpartyId: counterpartyId,
            counterparty: counterparty
        )
    }
}
