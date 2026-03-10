import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class SettingsMaintenanceUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: SettingsMaintenanceUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = SettingsMaintenanceUseCase(dataStore: dataStore)
    }

    override func tearDown() {
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testDeleteAllDataClearsDataAndReseedsDefaultCategories() throws {
        let project = dataStore.addProject(name: "P1", description: "")
        dataStore.addCategory(name: "Custom", type: .expense, icon: "star")
        dataStore.addTransaction(
            type: .expense,
            amount: 5_000,
            date: Date(),
            categoryId: "cat-tools",
            memo: "delete all",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        dataStore.addRecurring(
            name: "Monthly",
            type: .expense,
            amount: 3_000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        XCTAssertTrue(
            ProfileSecureStore.save(
                ProfileSensitivePayload.fromLegacyProfile(
                    ownerNameKana: "テスト",
                    postalCode: "1000001",
                    address: "東京都千代田区1-1-1",
                    phoneNumber: "0312345678",
                    dateOfBirth: nil,
                    businessCategory: "テスト業",
                    myNumberFlag: false,
                    includeSensitiveInExport: true
                ),
                profileId: businessId.uuidString
            )
        )
        defer { _ = ProfileSecureStore.delete(profileId: businessId.uuidString) }

        useCase.deleteAllData()

        XCTAssertEqual(dataStore.projects.count, 0)
        XCTAssertEqual(dataStore.transactions.count, 0)
        XCTAssertEqual(dataStore.recurringTransactions.count, 0)
        XCTAssertEqual(dataStore.categories.count, DEFAULT_CATEGORIES.count)
        XCTAssertNil(dataStore.businessProfile)
        XCTAssertNil(dataStore.currentTaxYearProfile)
        XCTAssertNil(ProfileSecureStore.load(profileId: businessId.uuidString))
    }

    func testDeleteAllDataIsIdempotent() {
        useCase.deleteAllData()
        useCase.deleteAllData()

        XCTAssertEqual(dataStore.projects.count, 0)
        XCTAssertEqual(dataStore.transactions.count, 0)
        XCTAssertEqual(dataStore.recurringTransactions.count, 0)
        XCTAssertEqual(dataStore.categories.count, DEFAULT_CATEGORIES.count)
    }
}
