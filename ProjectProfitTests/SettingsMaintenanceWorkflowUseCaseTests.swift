import Foundation
import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class SettingsMaintenanceWorkflowUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var workflowUseCase: SettingsMaintenanceWorkflowUseCase!
    private var tempDirectory: URL!
    private var trackedProfileIds: Set<String> = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try TestModelContainer.create()
        context = container.mainContext
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        workflowUseCase = SettingsMaintenanceWorkflowUseCase(
            modelContext: context,
            reloadStoreState: {
                self.dataStore.loadData()
                self.dataStore.recalculateAllPartialPeriodProjects()
            }
        )
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SettingsMaintenanceWorkflowUseCaseTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        ReceiptImageStore.setBaseDirectoryOverride(tempDirectory)
        UserDefaults.standard.removeObject(forKey: FiscalYearSettings.userDefaultsKey)
    }

    override func tearDownWithError() throws {
        for profileId in trackedProfileIds {
            _ = ProfileSecureStore.delete(profileId: profileId)
        }
        trackedProfileIds.removeAll()
        UserDefaults.standard.removeObject(forKey: FiscalYearSettings.userDefaultsKey)
        ReceiptImageStore.setBaseDirectoryOverride(nil)
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        workflowUseCase = nil
        dataStore = nil
        context = nil
        container = nil
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testApplyRestoreReloadsStoreState() throws {
        let seeded = try seedSnapshotState(
            profileId: "profile-restore",
            transactionId: UUID(uuidString: "70000000-0000-0000-0000-000000000001")!,
            transactionDate: Date(timeIntervalSince1970: 1_745_452_800),
            receiptFileName: "receipt-workflow.jpg",
            documentId: UUID(uuidString: "70000000-0000-0000-0000-000000000002")!,
            documentFileName: "document-workflow.pdf",
            securePostalCode: "1600022"
        )
        dataStore.loadData()

        let archiveURL = try workflowUseCase.exportBackup(scope: .full).archiveURL
        SettingsMaintenanceUseCase(
            modelContext: context,
            resetStoreState: { self.dataStore.loadData() }
        ).deleteAllData()

        XCTAssertEqual(dataStore.transactions.count, 0)
        XCTAssertNotNil(dataStore.businessProfile)

        let result = try workflowUseCase.applyRestore(snapshotURL: archiveURL)

        XCTAssertTrue(result.report.canApply)
        XCTAssertEqual(dataStore.transactions.map(\.id), [seeded.transaction.id])
        XCTAssertNotNil(dataStore.businessProfile)
        XCTAssertNotNil(dataStore.currentTaxYearProfile)
        XCTAssertTrue(ReceiptImageStore.documentFileExists(fileName: seeded.document.storedFileName))
    }

    func testExecuteMigrationReloadsStoreStateAndUpdatesDryRunReport() throws {
        seedCanonicalProfile(businessId: UUID(), taxYear: 2025)
        dataStore.loadData()

        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1_200,
            date: Self.stableDate(year: 2025, month: 6, day: 1),
            categoryId: "cat-other-expense",
            memo: "legacy migration",
            allocations: []
        )

        let beforeReport = try workflowUseCase.dryRunMigration()
        let beforeTransactionDelta = try XCTUnwrap(beforeReport.deltas.first { $0.modelName == "Transaction" })

        let result = try workflowUseCase.executeMigration()
        let afterReport = try workflowUseCase.dryRunMigration()
        let afterTransactionDelta = try XCTUnwrap(afterReport.deltas.first { $0.modelName == "Transaction" })

        XCTAssertGreaterThanOrEqual(result.transactionsMigrated, 1)
        XCTAssertEqual(dataStore.transactions.count, 1)
        XCTAssertGreaterThan(afterTransactionDelta.canonicalCount, beforeTransactionDelta.canonicalCount)
    }

    func testExecuteMigrationFailsWithoutBusinessProfile() {
        SettingsMaintenanceUseCase(
            modelContext: context
        ).deleteAllData()

        XCTAssertThrowsError(try workflowUseCase.executeMigration()) { error in
            XCTAssertEqual(error.localizedDescription, "事業者情報が未設定です")
        }
    }

    private func seedCanonicalProfile(businessId: UUID, taxYear: Int) {
        let business = BusinessProfile(
            id: businessId,
            ownerName: "テスト事業者",
            businessName: "Workflow商店"
        )
        let taxProfile = TaxYearProfile(
            businessId: businessId,
            taxYear: taxYear,
            filingStyle: .blueGeneral,
            yearLockState: .taxClose,
            taxPackVersion: "\(taxYear)-v1"
        )
        context.insert(BusinessProfileEntityMapper.toEntity(business))
        context.insert(TaxYearProfileEntityMapper.toEntity(taxProfile))
        try? context.save()
    }

    private func seedSnapshotState(
        profileId: String,
        transactionId: UUID,
        transactionDate: Date,
        receiptFileName: String,
        documentId: UUID,
        documentFileName: String,
        securePostalCode: String
    ) throws -> (business: BusinessProfile, taxYear: TaxYearProfile, transaction: PPTransaction, document: PPDocumentRecord) {
        let categoryId = "cat-other-expense"
        if try context.fetch(FetchDescriptor<PPCategory>()).isEmpty {
            context.insert(PPCategory(id: categoryId, name: "経費", type: .expense, icon: "tag"))
        }

        let businessId = UUID()
        let business = BusinessProfile(
            id: businessId,
            ownerName: "Owner \(profileId)",
            businessName: "事業 \(profileId)"
        )
        let taxYear = TaxYearProfile(
            businessId: businessId,
            taxYear: fiscalYear(for: transactionDate, startMonth: FiscalYearSettings.startMonth),
            filingStyle: .blueGeneral,
            yearLockState: .taxClose,
            taxPackVersion: "\(fiscalYear(for: transactionDate, startMonth: FiscalYearSettings.startMonth))-v1"
        )
        context.insert(BusinessProfileEntityMapper.toEntity(business))
        context.insert(TaxYearProfileEntityMapper.toEntity(taxYear))
        trackedProfileIds.insert(business.id.uuidString)
        XCTAssertTrue(
            ProfileSecureStore.save(
                ProfileSensitivePayload(
                    ownerNameKana: "オーナー",
                    postalCode: securePostalCode,
                    address: "東京都",
                    phoneNumber: "0312345678",
                    dateOfBirth: nil,
                    businessCategory: "IT",
                    myNumberFlag: true,
                    includeSensitiveInExport: true
                ),
                profileId: business.id.uuidString
            )
        )

        let transaction = PPTransaction(
            id: transactionId,
            type: .expense,
            amount: 1_500,
            date: transactionDate,
            categoryId: categoryId,
            memo: "tx-\(profileId)",
            receiptImagePath: receiptFileName
        )
        context.insert(transaction)

        let document = PPDocumentRecord(
            id: documentId,
            transactionId: transaction.id,
            documentType: .receipt,
            storedFileName: documentFileName,
            originalFileName: documentFileName,
            mimeType: "application/pdf",
            fileSize: Data("document-\(profileId)".utf8).count,
            contentHash: ReceiptImageStore.sha256Hex(data: Data("document-\(profileId)".utf8)),
            issueDate: transactionDate
        )
        context.insert(document)

        try ReceiptImageStore.storeImageData(Data("receipt-\(profileId)".utf8), fileName: receiptFileName)
        try ReceiptImageStore.storeDocumentData(Data("document-\(profileId)".utf8), fileName: documentFileName)

        try context.save()
        return (business, taxYear, transaction, document)
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
