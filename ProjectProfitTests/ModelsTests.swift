import SwiftData
import SwiftUI
import XCTest
@testable import ProjectProfit

final class ModelsTests: XCTestCase {

    // MARK: - ProjectStatus Tests

    func testProjectStatusAllCases() {
        let allCases = ProjectStatus.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.active))
        XCTAssertTrue(allCases.contains(.completed))
        XCTAssertTrue(allCases.contains(.paused))
    }

    func testProjectStatusRawValues() {
        XCTAssertEqual(ProjectStatus.active.rawValue, "active")
        XCTAssertEqual(ProjectStatus.completed.rawValue, "completed")
        XCTAssertEqual(ProjectStatus.paused.rawValue, "paused")
    }

    func testProjectStatusLabels() {
        XCTAssertEqual(ProjectStatus.active.label, "進行中")
        XCTAssertEqual(ProjectStatus.completed.label, "完了")
        XCTAssertEqual(ProjectStatus.paused.label, "保留")
    }

    func testProjectStatusColor() {
        // Verify each status returns a non-nil Color (Color is a value type, so it always exists).
        // We compare against the expected Color(hex:) values to ensure correctness.
        XCTAssertEqual(ProjectStatus.active.color, Color(hex: "16A34A"))
        XCTAssertEqual(ProjectStatus.completed.color, Color(hex: "2563EB"))
        XCTAssertEqual(ProjectStatus.paused.color, Color(hex: "F59E0B"))
    }

    func testProjectStatusCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for status in ProjectStatus.allCases {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(ProjectStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }

    func testProjectStatusDecodingFromRawString() throws {
        let decoder = JSONDecoder()

        let activeData = Data("\"active\"".utf8)
        XCTAssertEqual(try decoder.decode(ProjectStatus.self, from: activeData), .active)

        let completedData = Data("\"completed\"".utf8)
        XCTAssertEqual(try decoder.decode(ProjectStatus.self, from: completedData), .completed)

        let pausedData = Data("\"paused\"".utf8)
        XCTAssertEqual(try decoder.decode(ProjectStatus.self, from: pausedData), .paused)
    }

    func testProjectStatusDecodingInvalidValueFails() {
        let decoder = JSONDecoder()
        let invalidData = Data("\"unknown\"".utf8)
        XCTAssertThrowsError(try decoder.decode(ProjectStatus.self, from: invalidData))
    }

    // MARK: - TransactionType Tests

    func testTransactionTypeRawValues() {
        XCTAssertEqual(TransactionType.income.rawValue, "income")
        XCTAssertEqual(TransactionType.expense.rawValue, "expense")
        XCTAssertEqual(TransactionType.transfer.rawValue, "transfer")
    }

    func testTransactionTypeLabels() {
        XCTAssertEqual(TransactionType.income.label, "収益")
        XCTAssertEqual(TransactionType.expense.label, "経費")
        XCTAssertEqual(TransactionType.transfer.label, "振替")
    }

    func testTransactionTypeAllCases() {
        let allCases = TransactionType.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.income))
        XCTAssertTrue(allCases.contains(.expense))
        XCTAssertTrue(allCases.contains(.transfer))
    }

    func testTransactionTypeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for type in TransactionType.allCases {
            let data = try encoder.encode(type)
            let decoded = try decoder.decode(TransactionType.self, from: data)
            XCTAssertEqual(decoded, type)
        }
    }

    func testTransactionTypeTransferDecodingFromRawString() throws {
        let decoder = JSONDecoder()
        let data = Data("\"transfer\"".utf8)
        let decoded = try decoder.decode(TransactionType.self, from: data)
        XCTAssertEqual(decoded, .transfer)
    }

    // MARK: - CategoryType Tests

    func testCategoryTypeRawValues() {
        XCTAssertEqual(CategoryType.income.rawValue, "income")
        XCTAssertEqual(CategoryType.expense.rawValue, "expense")
    }

    func testCategoryTypeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for type in [CategoryType.income, .expense] {
            let data = try encoder.encode(type)
            let decoded = try decoder.decode(CategoryType.self, from: data)
            XCTAssertEqual(decoded, type)
        }
    }

    // MARK: - RecurringFrequency Tests

    func testRecurringFrequencyRawValues() {
        XCTAssertEqual(RecurringFrequency.monthly.rawValue, "monthly")
        XCTAssertEqual(RecurringFrequency.yearly.rawValue, "yearly")
    }

    func testRecurringFrequencyLabels() {
        XCTAssertEqual(RecurringFrequency.monthly.label, "毎月")
        XCTAssertEqual(RecurringFrequency.yearly.label, "毎年")
    }

    func testRecurringFrequencyCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for frequency in [RecurringFrequency.monthly, .yearly] {
            let data = try encoder.encode(frequency)
            let decoded = try decoder.decode(RecurringFrequency.self, from: data)
            XCTAssertEqual(decoded, frequency)
        }
    }

    // MARK: - NotificationTiming Tests

    func testNotificationTimingRawValues() {
        XCTAssertEqual(NotificationTiming.none.rawValue, "none")
        XCTAssertEqual(NotificationTiming.sameDay.rawValue, "sameDay")
        XCTAssertEqual(NotificationTiming.dayBefore.rawValue, "dayBefore")
        XCTAssertEqual(NotificationTiming.both.rawValue, "both")
    }

    func testNotificationTimingLabels() {
        XCTAssertEqual(NotificationTiming.none.label, "通知なし")
        XCTAssertEqual(NotificationTiming.sameDay.label, "当日に通知")
        XCTAssertEqual(NotificationTiming.dayBefore.label, "前日に通知")
        XCTAssertEqual(NotificationTiming.both.label, "前日と当日に通知")
    }

    func testNotificationTimingCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for timing in [NotificationTiming.none, .sameDay, .dayBefore, .both] {
            let data = try encoder.encode(timing)
            let decoded = try decoder.decode(NotificationTiming.self, from: data)
            XCTAssertEqual(decoded, timing)
        }
    }

    // MARK: - Allocation Tests

    func testAllocationInitialization() {
        let projectId = UUID()
        let allocation = Allocation(projectId: projectId, ratio: 50, amount: 10000)

        XCTAssertEqual(allocation.projectId, projectId)
        XCTAssertEqual(allocation.ratio, 50)
        XCTAssertEqual(allocation.amount, 10000)
    }

    func testAllocationInitializationWithZeroValues() {
        let projectId = UUID()
        let allocation = Allocation(projectId: projectId, ratio: 0, amount: 0)

        XCTAssertEqual(allocation.ratio, 0)
        XCTAssertEqual(allocation.amount, 0)
    }

    func testAllocationCodable() throws {
        let projectId = UUID()
        let allocation = Allocation(projectId: projectId, ratio: 75, amount: 5000)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(allocation)
        let decoded = try decoder.decode(Allocation.self, from: data)

        XCTAssertEqual(decoded.projectId, projectId)
        XCTAssertEqual(decoded.ratio, 75)
        XCTAssertEqual(decoded.amount, 5000)
    }

    func testAllocationCodableRoundTripMultiple() throws {
        let allocations = [
            Allocation(projectId: UUID(), ratio: 30, amount: 3000),
            Allocation(projectId: UUID(), ratio: 70, amount: 7000),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(allocations)
        let decoded = try decoder.decode([Allocation].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].ratio, 30)
        XCTAssertEqual(decoded[0].amount, 3000)
        XCTAssertEqual(decoded[1].ratio, 70)
        XCTAssertEqual(decoded[1].amount, 7000)
    }

    func testAllocationHashable() {
        let projectId = UUID()
        let allocation1 = Allocation(projectId: projectId, ratio: 50, amount: 10000)
        let allocation2 = Allocation(projectId: projectId, ratio: 50, amount: 10000)

        XCTAssertEqual(allocation1.hashValue, allocation2.hashValue)

        var set = Set<Allocation>()
        set.insert(allocation1)
        set.insert(allocation2)
        XCTAssertEqual(set.count, 1)
    }

    func testAllocationHashableDifferentValues() {
        let allocation1 = Allocation(projectId: UUID(), ratio: 50, amount: 10000)
        let allocation2 = Allocation(projectId: UUID(), ratio: 50, amount: 10000)

        // Different projectIds should produce different hashes (with very high probability)
        var set = Set<Allocation>()
        set.insert(allocation1)
        set.insert(allocation2)
        XCTAssertEqual(set.count, 2)
    }

    func testAllocationEquatable() {
        let projectId = UUID()
        let allocation1 = Allocation(projectId: projectId, ratio: 50, amount: 10000)
        let allocation2 = Allocation(projectId: projectId, ratio: 50, amount: 10000)
        let allocation3 = Allocation(projectId: projectId, ratio: 60, amount: 10000)

        XCTAssertEqual(allocation1, allocation2)
        XCTAssertNotEqual(allocation1, allocation3)
    }

    // MARK: - PPProject Tests

    func testPPProjectInitWithDefaults() {
        let project = PPProject(name: "Test Project")

        XCTAssertEqual(project.name, "Test Project")
        XCTAssertEqual(project.projectDescription, "")
        XCTAssertEqual(project.status, .active)
        XCTAssertNotNil(project.id)
        XCTAssertNotNil(project.createdAt)
        XCTAssertNotNil(project.updatedAt)
    }

    func testPPProjectInitWithCustomValues() {
        let fixedId = UUID()
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let project = PPProject(
            id: fixedId,
            name: "Custom Project",
            projectDescription: "A detailed description",
            status: .completed,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        XCTAssertEqual(project.id, fixedId)
        XCTAssertEqual(project.name, "Custom Project")
        XCTAssertEqual(project.projectDescription, "A detailed description")
        XCTAssertEqual(project.status, .completed)
        XCTAssertEqual(project.createdAt, fixedDate)
        XCTAssertEqual(project.updatedAt, fixedDate)
    }

    func testPPProjectInitWithPausedStatus() {
        let project = PPProject(name: "Paused Project", status: .paused)

        XCTAssertEqual(project.name, "Paused Project")
        XCTAssertEqual(project.status, .paused)
    }

    func testPPProjectDefaultStatusIsActive() {
        let project = PPProject(name: "New Project")
        XCTAssertEqual(project.status, .active)
    }

    func testPPProjectDefaultDescriptionIsEmpty() {
        let project = PPProject(name: "New Project")
        XCTAssertTrue(project.projectDescription.isEmpty)
    }

    func testPPProjectDateDefaults() {
        let beforeCreation = Date()
        let project = PPProject(name: "Timed Project")
        let afterCreation = Date()

        XCTAssertGreaterThanOrEqual(project.createdAt, beforeCreation)
        XCTAssertLessThanOrEqual(project.createdAt, afterCreation)
        XCTAssertGreaterThanOrEqual(project.updatedAt, beforeCreation)
        XCTAssertLessThanOrEqual(project.updatedAt, afterCreation)
    }

    // MARK: - PPTransaction Tests

    func testPPTransactionInitWithDefaults() {
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let transaction = PPTransaction(
            type: .income,
            amount: 50000,
            date: fixedDate,
            categoryId: "cat-sales"
        )

        XCTAssertEqual(transaction.type, .income)
        XCTAssertEqual(transaction.amount, 50000)
        XCTAssertEqual(transaction.date, fixedDate)
        XCTAssertEqual(transaction.categoryId, "cat-sales")
        XCTAssertEqual(transaction.memo, "")
        XCTAssertTrue(transaction.allocations.isEmpty)
        XCTAssertNil(transaction.recurringId)
        XCTAssertNil(transaction.paymentAccountId)
        XCTAssertNil(transaction.transferToAccountId)
        XCTAssertNil(transaction.taxDeductibleRate)
        XCTAssertNil(transaction.bookkeepingMode)
        XCTAssertNil(transaction.journalEntryId)
        XCTAssertNotNil(transaction.id)
        XCTAssertNotNil(transaction.createdAt)
        XCTAssertNotNil(transaction.updatedAt)
    }

    func testPPTransactionInitWithCustomValues() {
        let fixedId = UUID()
        let fixedDate = Date(timeIntervalSince1970: 2_000_000)
        let createdAt = Date(timeIntervalSince1970: 1_500_000)
        let updatedAt = Date(timeIntervalSince1970: 1_800_000)
        let recurringId = UUID()
        let projectId = UUID()
        let allocations = [Allocation(projectId: projectId, ratio: 100, amount: 20000)]

        let transaction = PPTransaction(
            id: fixedId,
            type: .expense,
            amount: 20000,
            date: fixedDate,
            categoryId: "cat-hosting",
            memo: "Server costs",
            allocations: allocations,
            recurringId: recurringId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        XCTAssertEqual(transaction.id, fixedId)
        XCTAssertEqual(transaction.type, .expense)
        XCTAssertEqual(transaction.amount, 20000)
        XCTAssertEqual(transaction.date, fixedDate)
        XCTAssertEqual(transaction.categoryId, "cat-hosting")
        XCTAssertEqual(transaction.memo, "Server costs")
        XCTAssertEqual(transaction.allocations.count, 1)
        XCTAssertEqual(transaction.allocations[0].projectId, projectId)
        XCTAssertEqual(transaction.allocations[0].ratio, 100)
        XCTAssertEqual(transaction.allocations[0].amount, 20000)
        XCTAssertEqual(transaction.recurringId, recurringId)
        XCTAssertEqual(transaction.createdAt, createdAt)
        XCTAssertEqual(transaction.updatedAt, updatedAt)
    }

    func testPPTransactionDefaultMemoIsEmpty() {
        let transaction = PPTransaction(
            type: .income,
            amount: 1000,
            date: Date(),
            categoryId: "cat-sales"
        )
        XCTAssertTrue(transaction.memo.isEmpty)
    }

    func testPPTransactionDefaultAllocationsIsEmpty() {
        let transaction = PPTransaction(
            type: .expense,
            amount: 500,
            date: Date(),
            categoryId: "cat-tools"
        )
        XCTAssertTrue(transaction.allocations.isEmpty)
    }

    func testPPTransactionDefaultRecurringIdIsNil() {
        let transaction = PPTransaction(
            type: .income,
            amount: 1000,
            date: Date(),
            categoryId: "cat-sales"
        )
        XCTAssertNil(transaction.recurringId)
    }

    func testPPTransactionWithAccountingFields() {
        let journalId = UUID()
        let transaction = PPTransaction(
            type: .expense,
            amount: 10000,
            date: Date(),
            categoryId: "cat-communication",
            paymentAccountId: "acct-bank",
            transferToAccountId: nil,
            taxDeductibleRate: 60,
            bookkeepingMode: .doubleEntry,
            journalEntryId: journalId
        )

        XCTAssertEqual(transaction.paymentAccountId, "acct-bank")
        XCTAssertNil(transaction.transferToAccountId)
        XCTAssertEqual(transaction.taxDeductibleRate, 60)
        XCTAssertEqual(transaction.bookkeepingMode, .doubleEntry)
        XCTAssertEqual(transaction.journalEntryId, journalId)
    }

    func testPPTransactionTransferWithBothAccounts() {
        let transaction = PPTransaction(
            type: .transfer,
            amount: 50000,
            date: Date(),
            categoryId: "cat-other-expense",
            paymentAccountId: "acct-bank",
            transferToAccountId: "acct-cash"
        )

        XCTAssertEqual(transaction.type, .transfer)
        XCTAssertEqual(transaction.paymentAccountId, "acct-bank")
        XCTAssertEqual(transaction.transferToAccountId, "acct-cash")
    }

    func testPPTransactionEffectiveTaxDeductibleRate() {
        let full = PPTransaction(type: .expense, amount: 10000, date: Date(), categoryId: "cat-communication")
        XCTAssertEqual(full.effectiveTaxDeductibleRate, 100)

        let partial = PPTransaction(type: .expense, amount: 10000, date: Date(), categoryId: "cat-communication", taxDeductibleRate: 60)
        XCTAssertEqual(partial.effectiveTaxDeductibleRate, 60)
    }

    func testPPTransactionDeductibleAmount() {
        let full = PPTransaction(type: .expense, amount: 10000, date: Date(), categoryId: "cat-communication")
        XCTAssertEqual(full.deductibleAmount, 10000)

        let partial = PPTransaction(type: .expense, amount: 10000, date: Date(), categoryId: "cat-communication", taxDeductibleRate: 60)
        XCTAssertEqual(partial.deductibleAmount, 6000)

        let zero = PPTransaction(type: .expense, amount: 10000, date: Date(), categoryId: "cat-communication", taxDeductibleRate: 0)
        XCTAssertEqual(zero.deductibleAmount, 0)
    }

    func testPPTransactionTaxDeductibleRateClamped() {
        let over = PPTransaction(type: .expense, amount: 10000, date: Date(), categoryId: "cat-food", taxDeductibleRate: 150)
        XCTAssertEqual(over.taxDeductibleRate, 100)

        let under = PPTransaction(type: .expense, amount: 10000, date: Date(), categoryId: "cat-food", taxDeductibleRate: -10)
        XCTAssertEqual(under.taxDeductibleRate, 0)
    }

    func testPPTransactionDeductibleAmountTruncation() {
        let transaction = PPTransaction(type: .expense, amount: 999, date: Date(), categoryId: "cat-food", taxDeductibleRate: 50)
        XCTAssertEqual(transaction.deductibleAmount, 499)
    }

    // MARK: - PPCategory Tests

    func testPPCategoryInitialization() {
        let category = PPCategory(
            id: "cat-hosting",
            name: "ホスティング",
            type: .expense,
            icon: "server.rack"
        )

        XCTAssertEqual(category.id, "cat-hosting")
        XCTAssertEqual(category.name, "ホスティング")
        XCTAssertEqual(category.type, .expense)
        XCTAssertEqual(category.icon, "server.rack")
        XCTAssertFalse(category.isDefault)
        XCTAssertNil(category.linkedAccountId)
    }

    func testPPCategoryWithLinkedAccountId() {
        let category = PPCategory(
            id: "cat-sales",
            name: "売上",
            type: .income,
            icon: "yensign.circle",
            linkedAccountId: "acct-sales"
        )

        XCTAssertEqual(category.linkedAccountId, "acct-sales")
    }

    func testPPCategoryInitWithDefaultFlag() {
        let category = PPCategory(
            id: "cat-sales",
            name: "売上",
            type: .income,
            icon: "yensign.circle",
            isDefault: true
        )

        XCTAssertEqual(category.id, "cat-sales")
        XCTAssertEqual(category.name, "売上")
        XCTAssertEqual(category.type, .income)
        XCTAssertEqual(category.icon, "yensign.circle")
        XCTAssertTrue(category.isDefault)
    }

    func testPPCategoryDefaultIsDefaultIsFalse() {
        let category = PPCategory(
            id: "cat-test",
            name: "Test",
            type: .expense,
            icon: "star"
        )
        XCTAssertFalse(category.isDefault)
    }

    // MARK: - PPRecurringTransaction Tests

    func testPPRecurringTransactionInitWithDefaults() {
        let recurring = PPRecurringTransaction(
            name: "Monthly Server",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting"
        )

        XCTAssertEqual(recurring.name, "Monthly Server")
        XCTAssertEqual(recurring.type, .expense)
        XCTAssertEqual(recurring.amount, 5000)
        XCTAssertEqual(recurring.categoryId, "cat-hosting")
        XCTAssertEqual(recurring.memo, "")
        XCTAssertTrue(recurring.allocations.isEmpty)
        XCTAssertEqual(recurring.frequency, .monthly)
        XCTAssertEqual(recurring.dayOfMonth, 1)
        XCTAssertNil(recurring.monthOfYear)
        XCTAssertTrue(recurring.isActive)
        XCTAssertNil(recurring.lastGeneratedDate)
        XCTAssertTrue(recurring.skipDates.isEmpty)
        XCTAssertEqual(recurring.notificationTiming, .none)
        XCTAssertNotNil(recurring.id)
        XCTAssertNotNil(recurring.createdAt)
        XCTAssertNotNil(recurring.updatedAt)
    }

    func testPPRecurringTransactionInitWithCustomValues() {
        let fixedId = UUID()
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let lastGenDate = Date(timeIntervalSince1970: 900_000)
        let skipDate = Date(timeIntervalSince1970: 800_000)
        let projectId = UUID()
        let allocations = [Allocation(projectId: projectId, ratio: 100, amount: 3000)]

        let recurring = PPRecurringTransaction(
            id: fixedId,
            name: "Yearly Subscription",
            type: .expense,
            amount: 3000,
            categoryId: "cat-tools",
            memo: "Annual plan",
            allocations: allocations,
            frequency: .yearly,
            dayOfMonth: 15,
            monthOfYear: 6,
            isActive: false,
            lastGeneratedDate: lastGenDate,
            skipDates: [skipDate],
            notificationTiming: .both,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        XCTAssertEqual(recurring.id, fixedId)
        XCTAssertEqual(recurring.name, "Yearly Subscription")
        XCTAssertEqual(recurring.type, .expense)
        XCTAssertEqual(recurring.amount, 3000)
        XCTAssertEqual(recurring.categoryId, "cat-tools")
        XCTAssertEqual(recurring.memo, "Annual plan")
        XCTAssertEqual(recurring.allocations.count, 1)
        XCTAssertEqual(recurring.frequency, .yearly)
        XCTAssertEqual(recurring.dayOfMonth, 15)
        XCTAssertEqual(recurring.monthOfYear, 6)
        XCTAssertFalse(recurring.isActive)
        XCTAssertEqual(recurring.lastGeneratedDate, lastGenDate)
        XCTAssertEqual(recurring.skipDates.count, 1)
        XCTAssertEqual(recurring.notificationTiming, .both)
        XCTAssertEqual(recurring.createdAt, fixedDate)
        XCTAssertEqual(recurring.updatedAt, fixedDate)
    }

    func testPPRecurringTransactionDayOfMonthClampedToMinimum() {
        let recurring = PPRecurringTransaction(
            name: "Low Day",
            type: .income,
            amount: 1000,
            categoryId: "cat-sales",
            dayOfMonth: 0
        )
        XCTAssertEqual(recurring.dayOfMonth, 1)
    }

    func testPPRecurringTransactionDayOfMonthClampedToMinimumNegative() {
        let recurring = PPRecurringTransaction(
            name: "Negative Day",
            type: .income,
            amount: 1000,
            categoryId: "cat-sales",
            dayOfMonth: -5
        )
        XCTAssertEqual(recurring.dayOfMonth, 1)
    }

    func testPPRecurringTransactionDayOfMonthClampedToMaximum() {
        let recurring = PPRecurringTransaction(
            name: "High Day",
            type: .income,
            amount: 1000,
            categoryId: "cat-sales",
            dayOfMonth: 31
        )
        XCTAssertEqual(recurring.dayOfMonth, 28)
    }

    func testPPRecurringTransactionDayOfMonthClampedToMaximumLarge() {
        let recurring = PPRecurringTransaction(
            name: "Very High Day",
            type: .expense,
            amount: 2000,
            categoryId: "cat-hosting",
            dayOfMonth: 100
        )
        XCTAssertEqual(recurring.dayOfMonth, 28)
    }

    func testPPRecurringTransactionDayOfMonthBoundaryValues() {
        let day1 = PPRecurringTransaction(
            name: "Day 1",
            type: .income,
            amount: 1000,
            categoryId: "cat-sales",
            dayOfMonth: 1
        )
        XCTAssertEqual(day1.dayOfMonth, 1)

        let day28 = PPRecurringTransaction(
            name: "Day 28",
            type: .income,
            amount: 1000,
            categoryId: "cat-sales",
            dayOfMonth: 28
        )
        XCTAssertEqual(day28.dayOfMonth, 28)

        let day29 = PPRecurringTransaction(
            name: "Day 29",
            type: .income,
            amount: 1000,
            categoryId: "cat-sales",
            dayOfMonth: 29
        )
        XCTAssertEqual(day29.dayOfMonth, 28)
    }

    func testPPRecurringTransactionMonthlyFrequencyIgnoresMonthOfYear() {
        let recurring = PPRecurringTransaction(
            name: "Monthly Recurring",
            type: .expense,
            amount: 1000,
            categoryId: "cat-tools",
            frequency: .monthly,
            monthOfYear: 6
        )
        XCTAssertNil(recurring.monthOfYear)
    }

    func testPPRecurringTransactionYearlyFrequencyKeepsMonthOfYear() {
        let recurring = PPRecurringTransaction(
            name: "Yearly Recurring",
            type: .expense,
            amount: 1000,
            categoryId: "cat-tools",
            frequency: .yearly,
            monthOfYear: 12
        )
        XCTAssertEqual(recurring.monthOfYear, 12)
    }

    func testRecurringTransaction_monthOfYear_validRange() {
        for month in 1...12 {
            let recurring = PPRecurringTransaction(
                name: "Month \(month)",
                type: .expense,
                amount: 1000,
                categoryId: "cat-tools",
                frequency: .yearly,
                monthOfYear: month
            )
            XCTAssertEqual(recurring.monthOfYear, month, "Month \(month) should be valid")
        }
    }

    func testRecurringTransaction_monthOfYear_invalidRange_becomesNil() {
        let invalidValues = [0, -1, 13, 100, -100]
        for value in invalidValues {
            let recurring = PPRecurringTransaction(
                name: "Invalid Month \(value)",
                type: .expense,
                amount: 1000,
                categoryId: "cat-tools",
                frequency: .yearly,
                monthOfYear: value
            )
            XCTAssertNil(recurring.monthOfYear, "Month \(value) should become nil")
        }
    }

    func testPPRecurringTransactionDefaultFrequencyIsMonthly() {
        let recurring = PPRecurringTransaction(
            name: "Default Frequency",
            type: .income,
            amount: 500,
            categoryId: "cat-sales"
        )
        XCTAssertEqual(recurring.frequency, .monthly)
    }

    func testPPRecurringTransactionDefaultIsActiveIsTrue() {
        let recurring = PPRecurringTransaction(
            name: "Active Check",
            type: .income,
            amount: 500,
            categoryId: "cat-sales"
        )
        XCTAssertTrue(recurring.isActive)
    }

    func testPPRecurringTransactionDefaultNotificationTimingIsNone() {
        let recurring = PPRecurringTransaction(
            name: "Notification Check",
            type: .income,
            amount: 500,
            categoryId: "cat-sales"
        )
        XCTAssertEqual(recurring.notificationTiming, .none)
    }

    // MARK: - ProjectSummary Tests

    func testProjectSummaryInitialization() {
        let id = UUID()
        let summary = ProjectSummary(
            id: id,
            projectName: "Test Project",
            status: .active,
            totalIncome: 100000,
            totalExpense: 60000,
            profit: 40000,
            profitMargin: 40.0
        )

        XCTAssertEqual(summary.id, id)
        XCTAssertEqual(summary.projectName, "Test Project")
        XCTAssertEqual(summary.status, .active)
        XCTAssertEqual(summary.totalIncome, 100000)
        XCTAssertEqual(summary.totalExpense, 60000)
        XCTAssertEqual(summary.profit, 40000)
        XCTAssertEqual(summary.profitMargin, 40.0, accuracy: 0.001)
    }

    func testProjectSummaryProjectIdComputedProperty() {
        let id = UUID()
        let summary = ProjectSummary(
            id: id,
            projectName: "Computed Property Test",
            status: .completed,
            totalIncome: 50000,
            totalExpense: 30000,
            profit: 20000,
            profitMargin: 40.0
        )

        XCTAssertEqual(summary.projectId, id)
        XCTAssertEqual(summary.projectId, summary.id)
    }

    func testProjectSummaryIdentifiable() {
        let id = UUID()
        let summary = ProjectSummary(
            id: id,
            projectName: "Identifiable Test",
            status: .paused,
            totalIncome: 0,
            totalExpense: 0,
            profit: 0,
            profitMargin: 0.0
        )

        // Identifiable conformance means id should be accessible
        XCTAssertEqual(summary.id, id)
    }

    func testProjectSummaryWithZeroValues() {
        let summary = ProjectSummary(
            id: UUID(),
            projectName: "Empty Project",
            status: .active,
            totalIncome: 0,
            totalExpense: 0,
            profit: 0,
            profitMargin: 0.0
        )

        XCTAssertEqual(summary.totalIncome, 0)
        XCTAssertEqual(summary.totalExpense, 0)
        XCTAssertEqual(summary.profit, 0)
        XCTAssertEqual(summary.profitMargin, 0.0, accuracy: 0.001)
    }

    func testProjectSummaryWithNegativeProfit() {
        let summary = ProjectSummary(
            id: UUID(),
            projectName: "Losing Project",
            status: .active,
            totalIncome: 30000,
            totalExpense: 50000,
            profit: -20000,
            profitMargin: -66.67
        )

        XCTAssertEqual(summary.profit, -20000)
        XCTAssertEqual(summary.profitMargin, -66.67, accuracy: 0.01)
    }

    // MARK: - TransactionFilter Tests

    func testTransactionFilterDefaultValues() {
        let filter = TransactionFilter()

        XCTAssertNil(filter.startDate)
        XCTAssertNil(filter.endDate)
        XCTAssertNil(filter.projectId)
        XCTAssertNil(filter.categoryId)
        XCTAssertNil(filter.type)
    }

    func testTransactionFilterWithCustomValues() {
        let startDate = Date(timeIntervalSince1970: 1_000_000)
        let endDate = Date(timeIntervalSince1970: 2_000_000)
        let projectId = UUID()

        var filter = TransactionFilter()
        filter.startDate = startDate
        filter.endDate = endDate
        filter.projectId = projectId
        filter.categoryId = "cat-sales"
        filter.type = .income

        XCTAssertEqual(filter.startDate, startDate)
        XCTAssertEqual(filter.endDate, endDate)
        XCTAssertEqual(filter.projectId, projectId)
        XCTAssertEqual(filter.categoryId, "cat-sales")
        XCTAssertEqual(filter.type, .income)
    }

    func testTransactionFilterPartialValues() {
        var filter = TransactionFilter()
        filter.type = .expense

        XCTAssertNil(filter.startDate)
        XCTAssertNil(filter.endDate)
        XCTAssertNil(filter.projectId)
        XCTAssertNil(filter.categoryId)
        XCTAssertEqual(filter.type, .expense)
    }

    // MARK: - TransactionSort Tests

    func testTransactionSortDefaultValues() {
        let sort = TransactionSort()

        XCTAssertEqual(sort.field, .date)
        XCTAssertEqual(sort.order, .desc)
    }

    func testTransactionSortCustomValues() {
        var sort = TransactionSort()
        sort.field = .amount
        sort.order = .asc

        XCTAssertEqual(sort.field, .amount)
        XCTAssertEqual(sort.order, .asc)
    }

    func testTransactionSortFieldRawValues() {
        XCTAssertEqual(TransactionSort.SortField.date.rawValue, "date")
        XCTAssertEqual(TransactionSort.SortField.amount.rawValue, "amount")
    }

    func testTransactionSortOrderRawValues() {
        XCTAssertEqual(TransactionSort.SortOrder.asc.rawValue, "asc")
        XCTAssertEqual(TransactionSort.SortOrder.desc.rawValue, "desc")
    }

    func testTransactionSortFieldDateAndAmount() {
        var sort = TransactionSort()

        sort.field = .date
        XCTAssertEqual(sort.field, .date)

        sort.field = .amount
        XCTAssertEqual(sort.field, .amount)
    }

    func testTransactionSortOrderAscAndDesc() {
        var sort = TransactionSort()

        sort.order = .asc
        XCTAssertEqual(sort.order, .asc)

        sort.order = .desc
        XCTAssertEqual(sort.order, .desc)
    }

    // MARK: - PPProject completedAt

    func testProjectInitDefaultCompletedAtNil() {
        let project = PPProject(name: "Test")
        XCTAssertNil(project.completedAt)
    }

    func testProjectInitWithCompletedAt() {
        let date = Date()
        let project = PPProject(name: "Test", completedAt: date)
        XCTAssertEqual(project.completedAt, date)
    }

    func testProjectCompletedStatusWithDate() {
        let date = Date()
        let project = PPProject(name: "Test", status: .completed, completedAt: date)
        XCTAssertEqual(project.status, .completed)
        XCTAssertNotNil(project.completedAt)
    }

    // MARK: - PPProject startDate

    func testProjectInitDefaultStartDateNil() {
        let project = PPProject(name: "Test")
        XCTAssertNil(project.startDate)
    }

    func testProjectInitWithStartDate() {
        let date = Date()
        let project = PPProject(name: "Test", startDate: date)
        XCTAssertEqual(project.startDate, date)
    }

    func testProjectInitWithStartDateAndCompletedAt() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = Date(timeIntervalSince1970: 2_000_000)
        let project = PPProject(name: "Test", startDate: start, completedAt: end)
        XCTAssertEqual(project.startDate, start)
        XCTAssertEqual(project.completedAt, end)
    }

    // MARK: - AccountType Tests

    func testAccountTypeAllCases() {
        let allCases = AccountType.allCases
        XCTAssertEqual(allCases.count, 5)
        XCTAssertTrue(allCases.contains(.asset))
        XCTAssertTrue(allCases.contains(.liability))
        XCTAssertTrue(allCases.contains(.equity))
        XCTAssertTrue(allCases.contains(.revenue))
        XCTAssertTrue(allCases.contains(.expense))
    }

    func testAccountTypeRawValues() {
        XCTAssertEqual(AccountType.asset.rawValue, "asset")
        XCTAssertEqual(AccountType.liability.rawValue, "liability")
        XCTAssertEqual(AccountType.equity.rawValue, "equity")
        XCTAssertEqual(AccountType.revenue.rawValue, "revenue")
        XCTAssertEqual(AccountType.expense.rawValue, "expense")
    }

    func testAccountTypeLabels() {
        XCTAssertEqual(AccountType.asset.label, "資産")
        XCTAssertEqual(AccountType.liability.label, "負債")
        XCTAssertEqual(AccountType.equity.label, "資本")
        XCTAssertEqual(AccountType.revenue.label, "収益")
        XCTAssertEqual(AccountType.expense.label, "費用")
    }

    func testAccountTypeNormalBalance() {
        XCTAssertEqual(AccountType.asset.normalBalance, .debit)
        XCTAssertEqual(AccountType.liability.normalBalance, .credit)
        XCTAssertEqual(AccountType.equity.normalBalance, .credit)
        XCTAssertEqual(AccountType.revenue.normalBalance, .credit)
        XCTAssertEqual(AccountType.expense.normalBalance, .debit)
    }

    func testAccountTypeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for accountType in AccountType.allCases {
            let data = try encoder.encode(accountType)
            let decoded = try decoder.decode(AccountType.self, from: data)
            XCTAssertEqual(decoded, accountType)
        }
    }

    func testAccountTypeDecodingInvalidValueFails() {
        let decoder = JSONDecoder()
        let invalidData = Data("\"unknown\"".utf8)
        XCTAssertThrowsError(try decoder.decode(AccountType.self, from: invalidData))
    }

    // MARK: - NormalBalance Tests

    func testNormalBalanceRawValues() {
        XCTAssertEqual(NormalBalance.debit.rawValue, "debit")
        XCTAssertEqual(NormalBalance.credit.rawValue, "credit")
    }

    func testNormalBalanceLabels() {
        XCTAssertEqual(NormalBalance.debit.label, "借方")
        XCTAssertEqual(NormalBalance.credit.label, "貸方")
    }

    func testNormalBalanceCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let debitData = try encoder.encode(NormalBalance.debit)
        XCTAssertEqual(try decoder.decode(NormalBalance.self, from: debitData), .debit)

        let creditData = try encoder.encode(NormalBalance.credit)
        XCTAssertEqual(try decoder.decode(NormalBalance.self, from: creditData), .credit)
    }

    func testNormalBalanceDecodingInvalidValueFails() {
        let decoder = JSONDecoder()
        let invalidData = Data("\"unknown\"".utf8)
        XCTAssertThrowsError(try decoder.decode(NormalBalance.self, from: invalidData))
    }

    // MARK: - AccountSubtype Tests

    func testAccountSubtypeAllCases() {
        let allCases = AccountSubtype.allCases
        // 4B-1: prepaidExpenses, accruedExpenses, ownerCapital を追加 (23 + 3 = 26)
        // Batch 13: accumulatedDepreciation 追加 (26 + 1 = 27)
        XCTAssertEqual(allCases.count, 27)
    }

    func testAccountSubtypeRawValues() {
        XCTAssertEqual(AccountSubtype.cash.rawValue, "cash")
        XCTAssertEqual(AccountSubtype.ordinaryDeposit.rawValue, "ordinaryDeposit")
        XCTAssertEqual(AccountSubtype.accountsReceivable.rawValue, "accountsReceivable")
        XCTAssertEqual(AccountSubtype.creditCard.rawValue, "creditCard")
        XCTAssertEqual(AccountSubtype.accountsPayable.rawValue, "accountsPayable")
        XCTAssertEqual(AccountSubtype.ownerContributions.rawValue, "ownerContributions")
        XCTAssertEqual(AccountSubtype.ownerDrawings.rawValue, "ownerDrawings")
        XCTAssertEqual(AccountSubtype.suspense.rawValue, "suspense")
        XCTAssertEqual(AccountSubtype.openingBalance.rawValue, "openingBalance")
        XCTAssertEqual(AccountSubtype.salesRevenue.rawValue, "salesRevenue")
        XCTAssertEqual(AccountSubtype.otherIncome.rawValue, "otherIncome")
        XCTAssertEqual(AccountSubtype.rentExpense.rawValue, "rentExpense")
        XCTAssertEqual(AccountSubtype.utilitiesExpense.rawValue, "utilitiesExpense")
        XCTAssertEqual(AccountSubtype.travelExpense.rawValue, "travelExpense")
        XCTAssertEqual(AccountSubtype.communicationExpense.rawValue, "communicationExpense")
        XCTAssertEqual(AccountSubtype.advertisingExpense.rawValue, "advertisingExpense")
        XCTAssertEqual(AccountSubtype.entertainmentExpense.rawValue, "entertainmentExpense")
        XCTAssertEqual(AccountSubtype.depreciationExpense.rawValue, "depreciationExpense")
        XCTAssertEqual(AccountSubtype.repairExpense.rawValue, "repairExpense")
        XCTAssertEqual(AccountSubtype.suppliesExpense.rawValue, "suppliesExpense")
        XCTAssertEqual(AccountSubtype.welfareExpense.rawValue, "welfareExpense")
        XCTAssertEqual(AccountSubtype.outsourcingExpense.rawValue, "outsourcingExpense")
        XCTAssertEqual(AccountSubtype.miscExpense.rawValue, "miscExpense")
    }

    func testAccountSubtypeLabels() {
        XCTAssertEqual(AccountSubtype.cash.label, "現金")
        XCTAssertEqual(AccountSubtype.ordinaryDeposit.label, "普通預金")
        XCTAssertEqual(AccountSubtype.accountsReceivable.label, "売掛金")
        XCTAssertEqual(AccountSubtype.creditCard.label, "クレジットカード")
        XCTAssertEqual(AccountSubtype.accountsPayable.label, "買掛金")
        XCTAssertEqual(AccountSubtype.ownerContributions.label, "事業主借")
        XCTAssertEqual(AccountSubtype.ownerDrawings.label, "事業主貸")
        XCTAssertEqual(AccountSubtype.suspense.label, "仮勘定")
        XCTAssertEqual(AccountSubtype.openingBalance.label, "期首残高")
        XCTAssertEqual(AccountSubtype.salesRevenue.label, "売上（収入）金額")
        XCTAssertEqual(AccountSubtype.otherIncome.label, "雑収入")
        XCTAssertEqual(AccountSubtype.rentExpense.label, "地代家賃")
        XCTAssertEqual(AccountSubtype.utilitiesExpense.label, "水道光熱費")
        XCTAssertEqual(AccountSubtype.travelExpense.label, "旅費交通費")
        XCTAssertEqual(AccountSubtype.communicationExpense.label, "通信費")
        XCTAssertEqual(AccountSubtype.advertisingExpense.label, "広告宣伝費")
        XCTAssertEqual(AccountSubtype.entertainmentExpense.label, "接待交際費")
        XCTAssertEqual(AccountSubtype.depreciationExpense.label, "減価償却費")
        XCTAssertEqual(AccountSubtype.repairExpense.label, "修繕費")
        XCTAssertEqual(AccountSubtype.suppliesExpense.label, "消耗品費")
        XCTAssertEqual(AccountSubtype.welfareExpense.label, "福利厚生費")
        XCTAssertEqual(AccountSubtype.outsourcingExpense.label, "外注工賃")
        XCTAssertEqual(AccountSubtype.miscExpense.label, "雑費")
    }

    func testAccountSubtypeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for subtype in AccountSubtype.allCases {
            let data = try encoder.encode(subtype)
            let decoded = try decoder.decode(AccountSubtype.self, from: data)
            XCTAssertEqual(decoded, subtype)
        }
    }

    func testAccountSubtypeDecodingInvalidValueFails() {
        let decoder = JSONDecoder()
        let invalidData = Data("\"unknown\"".utf8)
        XCTAssertThrowsError(try decoder.decode(AccountSubtype.self, from: invalidData))
    }

    // MARK: - JournalEntryType Tests

    func testJournalEntryTypeAllCases() {
        let allCases = JournalEntryType.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.auto))
        XCTAssertTrue(allCases.contains(.manual))
        XCTAssertTrue(allCases.contains(.opening))
        XCTAssertTrue(allCases.contains(.closing))
    }

    func testJournalEntryTypeRawValues() {
        XCTAssertEqual(JournalEntryType.auto.rawValue, "auto")
        XCTAssertEqual(JournalEntryType.manual.rawValue, "manual")
        XCTAssertEqual(JournalEntryType.opening.rawValue, "opening")
        XCTAssertEqual(JournalEntryType.closing.rawValue, "closing")
    }

    func testJournalEntryTypeLabels() {
        XCTAssertEqual(JournalEntryType.auto.label, "自動仕訳")
        XCTAssertEqual(JournalEntryType.manual.label, "手動仕訳")
        XCTAssertEqual(JournalEntryType.opening.label, "期首残高仕訳")
        XCTAssertEqual(JournalEntryType.closing.label, "決算仕訳")
    }

    func testJournalEntryTypeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for entryType in JournalEntryType.allCases {
            let data = try encoder.encode(entryType)
            let decoded = try decoder.decode(JournalEntryType.self, from: data)
            XCTAssertEqual(decoded, entryType)
        }
    }

    func testJournalEntryTypeDecodingInvalidValueFails() {
        let decoder = JSONDecoder()
        let invalidData = Data("\"unknown\"".utf8)
        XCTAssertThrowsError(try decoder.decode(JournalEntryType.self, from: invalidData))
    }

    // MARK: - BookkeepingMode Tests

    func testBookkeepingModeAllCases() {
        let allCases = BookkeepingMode.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.singleEntry))
        XCTAssertTrue(allCases.contains(.doubleEntry))
    }

    func testBookkeepingModeRawValues() {
        XCTAssertEqual(BookkeepingMode.singleEntry.rawValue, "singleEntry")
        XCTAssertEqual(BookkeepingMode.doubleEntry.rawValue, "doubleEntry")
    }

    func testBookkeepingModeLabels() {
        XCTAssertEqual(BookkeepingMode.singleEntry.label, "簡易簿記")
        XCTAssertEqual(BookkeepingMode.doubleEntry.label, "複式簿記")
    }

    func testBookkeepingModeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for mode in BookkeepingMode.allCases {
            let data = try encoder.encode(mode)
            let decoded = try decoder.decode(BookkeepingMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    func testBookkeepingModeDecodingInvalidValueFails() {
        let decoder = JSONDecoder()
        let invalidData = Data("\"unknown\"".utf8)
        XCTAssertThrowsError(try decoder.decode(BookkeepingMode.self, from: invalidData))
    }
}
