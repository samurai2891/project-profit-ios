import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class SettingsMaintenanceUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: SettingsMaintenanceUseCase!
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = SettingsMaintenanceUseCase(modelContext: context)
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SettingsMaintenanceUseCaseTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        ReceiptImageStore.setBaseDirectoryOverride(tempDirectory)
    }

    override func tearDownWithError() throws {
        ReceiptImageStore.setBaseDirectoryOverride(nil)
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testDeleteAllDataClearsDataAndReseedsDefaultCategories() throws {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        try! dataStore.addCategory(name: "Custom", type: .expense, icon: "star")
        mutations(dataStore).addTransaction(
            type: .expense,
            amount: 5_000,
            date: Date(),
            categoryId: "cat-tools",
            memo: "delete all",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addRecurring(
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

        XCTAssertTrue(try context.fetch(FetchDescriptor<PPProject>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PPTransaction>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PPRecurringTransaction>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PPCategory>()).count, DEFAULT_CATEGORIES.count)
        XCTAssertNil(try WorkflowPersistenceSupport.defaultBusinessProfile(modelContext: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<TaxYearProfileEntity>()).isEmpty)
        XCTAssertNil(ProfileSecureStore.load(profileId: businessId.uuidString))
    }

    func testDeleteAllDataQuarantinesActiveDocumentsAndKeepsComplianceLogs() throws {
        let project = mutations(dataStore).addProject(name: "Doc", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1_000,
            date: Date(),
            categoryId: "cat-tools",
            memo: "doc delete all",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        let addResult = dataStore.addDocumentRecord(
            transactionId: transaction.id,
            documentType: .invoice,
            originalFileName: "delete-all.pdf",
            fileData: Data("delete-all".utf8),
            mimeType: "application/pdf",
            issueDate: Date()
        )

        guard case .success(let document) = addResult else {
            XCTFail("Expected document to be created")
            return
        }

        useCase.deleteAllData()

        let storedRecord = try XCTUnwrap(context.fetch(FetchDescriptor<PPDocumentRecord>()).first)
        XCTAssertEqual(storedRecord.id, document.id)
        XCTAssertEqual(storedRecord.deletionStatus, .quarantined)
        XCTAssertEqual(storedRecord.deletionReason, "設定の全データ削除")
        XCTAssertFalse(ReceiptImageStore.documentFileExists(fileName: document.storedFileName))
        XCTAssertTrue(ReceiptImageStore.quarantinedDocumentFileURL(fileName: try XCTUnwrap(storedRecord.quarantineFileName)) != nil)
        XCTAssertFalse(try context.fetch(FetchDescriptor<PPComplianceLog>()).isEmpty)
    }

    func testDeleteAllDataPreservesExistingQuarantineFiles() throws {
        let project = mutations(dataStore).addProject(name: "Doc2", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 2_000,
            date: Date(),
            categoryId: "cat-tools",
            memo: "doc restore",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        let addResult = dataStore.addDocumentRecord(
            transactionId: transaction.id,
            documentType: .invoice,
            originalFileName: "already-quarantined.pdf",
            fileData: Data("already-quarantined".utf8),
            mimeType: "application/pdf",
            issueDate: Date()
        )

        guard case .success(let document) = addResult else {
            XCTFail("Expected document to be created")
            return
        }

        _ = dataStore.requestDocumentDeletion(id: document.id)
        _ = dataStore.confirmDocumentDeletion(id: document.id, reason: "保守確認", approvedBy: "管理者B")
        let quarantinedBeforeDeleteAll = try XCTUnwrap(dataStore.getDocumentRecord(id: document.id))
        let quarantineFileName = try XCTUnwrap(quarantinedBeforeDeleteAll.quarantineFileName)

        useCase.deleteAllData()

        let storedRecord = try XCTUnwrap(context.fetch(FetchDescriptor<PPDocumentRecord>()).first)
        XCTAssertEqual(storedRecord.id, document.id)
        XCTAssertEqual(storedRecord.quarantineFileName, quarantineFileName)
        XCTAssertTrue(ReceiptImageStore.quarantinedDocumentFileURL(fileName: quarantineFileName) != nil)
    }

    func testDeleteAllDataStopsWhenDocumentQuarantineFails() throws {
        let project = mutations(dataStore).addProject(name: "Doc3", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 3_000,
            date: Date(),
            categoryId: "cat-tools",
            memo: "doc failure",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        let addResult = dataStore.addDocumentRecord(
            transactionId: transaction.id,
            documentType: .invoice,
            originalFileName: "delete-all-failure.pdf",
            fileData: Data("delete-all-failure".utf8),
            mimeType: "application/pdf",
            issueDate: Date()
        )

        guard case .success(let document) = addResult else {
            XCTFail("Expected document to be created")
            return
        }

        ReceiptImageStore.deleteDocumentFile(fileName: document.storedFileName)

        useCase.deleteAllData()

        XCTAssertFalse(try context.fetch(FetchDescriptor<PPProject>()).isEmpty)
        let storedRecord = try XCTUnwrap(context.fetch(FetchDescriptor<PPDocumentRecord>()).first)
        XCTAssertEqual(storedRecord.id, document.id)
        XCTAssertEqual(storedRecord.deletionStatus, .active)
    }

    func testDeleteAllDataIsIdempotent() {
        useCase.deleteAllData()
        useCase.deleteAllData()

        XCTAssertEqual(try? context.fetch(FetchDescriptor<PPProject>()).count, 0)
        XCTAssertEqual(try? context.fetch(FetchDescriptor<PPTransaction>()).count, 0)
        XCTAssertEqual(try? context.fetch(FetchDescriptor<PPRecurringTransaction>()).count, 0)
        XCTAssertEqual(try? context.fetch(FetchDescriptor<PPCategory>()).count, DEFAULT_CATEGORIES.count)
    }
}
