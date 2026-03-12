import Foundation
import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class BackupRestoreServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var tempDirectory: URL!
    private var trackedProfileIds: Set<String> = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try TestModelContainer.create()
        context = container.mainContext
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BackupRestoreServiceTests-\(UUID().uuidString)", isDirectory: true)
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
        tempDirectory = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    func testExportFullWritesManifestChecksumsAndSecurePayload() throws {
        UserDefaults.standard.set(4, forKey: FiscalYearSettings.userDefaultsKey)
        let seeded = try seedSnapshotState(
            profileId: "profile-export",
            transactionId: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            transactionDate: Date(timeIntervalSince1970: 1_745_452_800),
            receiptFileName: "receipt-export.jpg",
            documentId: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            documentFileName: "document-export.pdf",
            securePostalCode: "1600022"
        )

        let result = try BackupService(modelContext: context).export(scope: .full)
        let extracted = try extractSnapshot(from: result.archiveURL)
        defer { try? FileManager.default.removeItem(at: extracted.directory) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.archiveURL.path))
        XCTAssertEqual(extracted.manifest.scope, .full)
        XCTAssertEqual(extracted.payload.fiscalStartMonth, 4)
        XCTAssertEqual(extracted.payload.legacy.transactions.map(\.id), [seeded.transaction.id])
        XCTAssertEqual(extracted.payload.legacy.documentRecords.map(\.id), [seeded.document.id])
        XCTAssertTrue(extracted.payload.legacy.accountingProfiles.isEmpty)
        XCTAssertEqual(extracted.payload.canonical.businessProfiles.map(\.id), [seeded.business.id])
        XCTAssertEqual(extracted.payload.canonical.taxYearProfiles.map(\.taxYear), [seeded.taxYear.taxYear])
        XCTAssertEqual(extracted.secureProfiles.map(\.profileId), [seeded.business.id.uuidString])
        XCTAssertEqual(extracted.manifest.payloadChecksum, ReceiptImageStore.sha256Hex(data: extracted.payloadData))
        XCTAssertEqual(extracted.manifest.securePayloadChecksum, ReceiptImageStore.sha256Hex(data: extracted.secureData))
        XCTAssertEqual(
            Set(extracted.manifest.fileRecords.map(\.fileName)),
            Set([seeded.transaction.receiptImagePath!, seeded.document.storedFileName])
        )
    }

    func testExportTaxYearFiltersTransactionsAndDocumentsByFiscalYear() throws {
        UserDefaults.standard.set(4, forKey: FiscalYearSettings.userDefaultsKey)
        _ = try seedSnapshotState(
            profileId: "profile-taxyear",
            transactionId: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            transactionDate: stableDate(year: 2025, month: 2, day: 15),
            receiptFileName: "receipt-2024.jpg",
            documentId: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            documentFileName: "document-2024.pdf",
            securePostalCode: "1010001"
        )
        let included = try seedSnapshotState(
            profileId: "profile-taxyear-b",
            transactionId: UUID(uuidString: "20000000-0000-0000-0000-000000000003")!,
            transactionDate: stableDate(year: 2025, month: 4, day: 15),
            receiptFileName: "receipt-2025.jpg",
            documentId: UUID(uuidString: "20000000-0000-0000-0000-000000000004")!,
            documentFileName: "document-2025.pdf",
            securePostalCode: "1010002"
        )

        let result = try BackupService(modelContext: context).export(scope: .taxYear(2025))
        let extracted = try extractSnapshot(from: result.archiveURL)
        defer { try? FileManager.default.removeItem(at: extracted.directory) }

        XCTAssertEqual(extracted.payload.legacy.transactions.map(\.id), [included.transaction.id])
        XCTAssertEqual(extracted.payload.legacy.documentRecords.map(\.id), [included.document.id])
        XCTAssertEqual(extracted.manifest.scope, .taxYear(2025))
    }

    func testRestoreDryRunReportsPayloadChecksumMismatch() throws {
        _ = try seedSnapshotState(
            profileId: "profile-dryrun",
            transactionId: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            transactionDate: Date(timeIntervalSince1970: 1_745_452_800),
            receiptFileName: "receipt-dryrun.jpg",
            documentId: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
            documentFileName: "document-dryrun.pdf",
            securePostalCode: "1500001"
        )

        let archive = try BackupService(modelContext: context).export(scope: .full).archiveURL
        let tamperedArchive = try tamperPayloadChecksum(of: archive)

        let report = try RestoreService(modelContext: context).dryRun(snapshotURL: tamperedArchive)

        XCTAssertFalse(report.canApply)
        XCTAssertTrue(report.issues.contains("payload checksum mismatch"))
    }

    func testApplyFullRestoreReplacesDataRestoresFilesAndCreatesRollbackArchive() throws {
        UserDefaults.standard.set(4, forKey: FiscalYearSettings.userDefaultsKey)
        let original = try seedSnapshotState(
            profileId: "profile-restore-a",
            transactionId: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
            transactionDate: Date(timeIntervalSince1970: 1_745_452_800),
            receiptFileName: "receipt-restore-a.jpg",
            documentId: UUID(uuidString: "40000000-0000-0000-0000-000000000002")!,
            documentFileName: "document-restore-a.pdf",
            securePostalCode: "5300001"
        )
        let archive = try BackupService(modelContext: context).export(scope: .full).archiveURL

        ReceiptImageStore.deleteImage(fileName: original.transaction.receiptImagePath!)
        ReceiptImageStore.deleteDocumentFile(fileName: original.document.storedFileName)
        _ = ProfileSecureStore.delete(profileId: original.business.id.uuidString)

        UserDefaults.standard.set(1, forKey: FiscalYearSettings.userDefaultsKey)

        let replacement = try seedSnapshotState(
            profileId: "profile-restore-b",
            transactionId: UUID(uuidString: "40000000-0000-0000-0000-000000000003")!,
            transactionDate: Date(timeIntervalSince1970: 1_748_131_200),
            receiptFileName: "receipt-restore-b.jpg",
            documentId: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
            documentFileName: "document-restore-b.pdf",
            securePostalCode: "5300002"
        )

        let result = try RestoreService(modelContext: context).apply(snapshotURL: archive)

        let businessProfiles = try context.fetch(FetchDescriptor<BusinessProfileEntity>())
        let taxYearProfiles = try context.fetch(FetchDescriptor<TaxYearProfileEntity>())
        let legacyProfiles = try context.fetch(FetchDescriptor<PPAccountingProfile>())
        let transactions = try context.fetch(FetchDescriptor<PPTransaction>())
        let documents = try context.fetch(FetchDescriptor<PPDocumentRecord>())

        XCTAssertTrue(result.report.canApply)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.rollbackArchiveURL.path))
        XCTAssertEqual(FiscalYearSettings.startMonth, 4)
        XCTAssertEqual(businessProfiles.map(\.businessId), [original.business.id])
        XCTAssertEqual(taxYearProfiles.map(\.taxYear), [original.taxYear.taxYear])
        XCTAssertTrue(legacyProfiles.isEmpty)
        XCTAssertEqual(transactions.map(\.id), [original.transaction.id])
        XCTAssertEqual(documents.map(\.id), [original.document.id])
        XCTAssertTrue(ReceiptImageStore.imageExists(fileName: original.transaction.receiptImagePath!))
        XCTAssertTrue(ReceiptImageStore.documentFileExists(fileName: original.document.storedFileName))
        XCTAssertFalse(ReceiptImageStore.imageExists(fileName: replacement.transaction.receiptImagePath!))
        XCTAssertFalse(ReceiptImageStore.documentFileExists(fileName: replacement.document.storedFileName))
        XCTAssertEqual(ProfileSecureStore.load(profileId: original.business.id.uuidString)?.postalCode, "5300001")
        XCTAssertNil(ProfileSecureStore.load(profileId: replacement.business.id.uuidString))
    }

    func testApplyLegacyProfileOnlySnapshotRestoresCanonicalProfilesAndNormalizesSecurePayloadIds() throws {
        UserDefaults.standard.set(4, forKey: FiscalYearSettings.userDefaultsKey)
        let seeded = try seedSnapshotState(
            profileId: "profile-legacy-restore",
            transactionId: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
            transactionDate: Date(timeIntervalSince1970: 1_745_452_800),
            receiptFileName: "receipt-legacy-restore.jpg",
            documentId: UUID(uuidString: "50000000-0000-0000-0000-000000000002")!,
            documentFileName: "document-legacy-restore.pdf",
            securePostalCode: "5410041"
        )
        let archive = try BackupService(modelContext: context).export(scope: .full).archiveURL
        let legacyProfileId = "legacy-profile-restore"
        trackedProfileIds.insert(legacyProfileId)

        let mutatedArchive = try rewriteAsLegacyProfileOnlySnapshot(
            archiveURL: archive,
            legacyProfileId: legacyProfileId,
            transactionDate: seeded.transaction.date
        )

        let result = try RestoreService(modelContext: context).apply(snapshotURL: mutatedArchive)

        let businessProfiles = try context.fetch(FetchDescriptor<BusinessProfileEntity>())
        let taxYearProfiles = try context.fetch(FetchDescriptor<TaxYearProfileEntity>())
        let legacyProfiles = try context.fetch(FetchDescriptor<PPAccountingProfile>())

        XCTAssertTrue(result.report.canApply)
        XCTAssertEqual(businessProfiles.count, 1)
        XCTAssertEqual(taxYearProfiles.map(\.taxYear), [seeded.taxYear.taxYear])
        XCTAssertTrue(legacyProfiles.isEmpty)
        XCTAssertEqual(businessProfiles.first?.ownerName, "Legacy Owner")
        XCTAssertEqual(businessProfiles.first?.businessName, "Legacy商店")

        let canonicalProfileId = try XCTUnwrap(businessProfiles.first?.businessId.uuidString)
        XCTAssertEqual(ProfileSecureStore.load(profileId: canonicalProfileId)?.postalCode, "5410041")
        XCTAssertNil(ProfileSecureStore.load(profileId: legacyProfileId))
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
        if try context.fetch(FetchDescriptor<PPCategory>()).isEmpty {
            context.insert(PPCategory(id: "cat-expense", name: "経費", type: .expense, icon: "tag"))
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
            amount: 1500,
            date: transactionDate,
            categoryId: "cat-expense",
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

    private func stableDate(year: Int, month: Int, day: Int) -> Date {
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

    private func extractSnapshot(from archiveURL: URL) throws -> (directory: URL, manifest: SnapshotManifest, payload: AppSnapshotPayload, secureProfiles: [SnapshotSecureProfile], payloadData: Data, secureData: Data) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ExtractedSnapshot-\(UUID().uuidString)", isDirectory: true)
        try SnapshotArchiveStore.extractArchive(at: archiveURL, to: directory)

        let manifestData = try Data(contentsOf: directory.appendingPathComponent(BackupService.manifestFileName))
        let payloadData = try Data(contentsOf: directory.appendingPathComponent(BackupService.payloadFileName))
        let secureData = try Data(contentsOf: directory.appendingPathComponent("settings").appendingPathComponent(BackupService.securePayloadFileName))

        return (
            directory: directory,
            manifest: try BackupService.decoder.decode(SnapshotManifest.self, from: manifestData),
            payload: try BackupService.decoder.decode(AppSnapshotPayload.self, from: payloadData),
            secureProfiles: try BackupService.decoder.decode([SnapshotSecureProfile].self, from: secureData),
            payloadData: payloadData,
            secureData: secureData
        )
    }

    private func tamperPayloadChecksum(of archiveURL: URL) throws -> URL {
        let extracted = try extractSnapshot(from: archiveURL)
        let payloadURL = extracted.directory.appendingPathComponent(BackupService.payloadFileName)
        var payloadData = try Data(contentsOf: payloadURL)
        payloadData.append(contentsOf: [0x0A])
        try payloadData.write(to: payloadURL, options: .atomic)

        let tamperedURL = FileManager.default.temporaryDirectory.appendingPathComponent("tampered-\(UUID().uuidString).aar")
        try SnapshotArchiveStore.archiveDirectory(extracted.directory, to: tamperedURL)
        try FileManager.default.removeItem(at: extracted.directory)
        return tamperedURL
    }

    private func rewriteAsLegacyProfileOnlySnapshot(
        archiveURL: URL,
        legacyProfileId: String,
        transactionDate: Date
    ) throws -> URL {
        let extracted = try extractSnapshot(from: archiveURL)
        let securePayload = ProfileSensitivePayload(
            ownerNameKana: "レガシーオーナー",
            postalCode: "5410041",
            address: "大阪府大阪市中央区1-1-1",
            phoneNumber: "0612345678",
            dateOfBirth: nil,
            businessCategory: "IT",
            myNumberFlag: true,
            includeSensitiveInExport: true
        )
        let restoredFiscalYear = fiscalYear(for: transactionDate, startMonth: FiscalYearSettings.startMonth)
        let legacyProfile = PPAccountingProfile(
            id: legacyProfileId,
            fiscalYear: restoredFiscalYear,
            bookkeepingMode: .singleEntry,
            businessName: "Legacy商店",
            ownerName: "Legacy Owner",
            taxOfficeCode: "1234",
            isBlueReturn: false,
            defaultPaymentAccountId: "acct-cash",
            openingDate: Date(timeIntervalSince1970: 1_600_000_000),
            lockedAt: Date(timeIntervalSince1970: 1_600_000_150),
            createdAt: Date(timeIntervalSince1970: 1_600_000_100),
            updatedAt: Date(timeIntervalSince1970: 1_600_000_200)
        )
        legacyProfile.ownerNameKana = securePayload.ownerNameKana
        legacyProfile.postalCode = securePayload.postalCode
        legacyProfile.address = securePayload.address
        legacyProfile.phoneNumber = securePayload.phoneNumber
        legacyProfile.dateOfBirth = securePayload.dateOfBirth
        legacyProfile.businessCategory = securePayload.businessCategory
        legacyProfile.myNumberFlag = securePayload.myNumberFlag
        let legacySnapshot = LegacyAccountingProfileSnapshot(legacyProfile)

        let payload = AppSnapshotPayload(
            fiscalStartMonth: extracted.payload.fiscalStartMonth,
            legacy: LegacySnapshotSection(
                projects: extracted.payload.legacy.projects,
                categories: extracted.payload.legacy.categories,
                recurringTransactions: extracted.payload.legacy.recurringTransactions,
                transactions: extracted.payload.legacy.transactions,
                accounts: extracted.payload.legacy.accounts,
                journalEntries: extracted.payload.legacy.journalEntries,
                journalLines: extracted.payload.legacy.journalLines,
                accountingProfiles: [legacySnapshot],
                userRules: extracted.payload.legacy.userRules,
                fixedAssets: extracted.payload.legacy.fixedAssets,
                inventoryRecords: extracted.payload.legacy.inventoryRecords,
                documentRecords: extracted.payload.legacy.documentRecords,
                complianceLogs: extracted.payload.legacy.complianceLogs,
                transactionLogs: extracted.payload.legacy.transactionLogs,
                ledgerBooks: extracted.payload.legacy.ledgerBooks,
                ledgerEntries: extracted.payload.legacy.ledgerEntries
            ),
            canonical: CanonicalSnapshotSection(
                businessProfiles: [],
                taxYearProfiles: [],
                evidenceDocuments: extracted.payload.canonical.evidenceDocuments,
                postingCandidates: extracted.payload.canonical.postingCandidates,
                journalEntries: extracted.payload.canonical.journalEntries,
                counterparties: extracted.payload.canonical.counterparties,
                accounts: extracted.payload.canonical.accounts,
                distributionRules: extracted.payload.canonical.distributionRules,
                auditEvents: extracted.payload.canonical.auditEvents
            )
        )

        let secureProfiles = [SnapshotSecureProfile(profileId: legacyProfileId, payload: securePayload)]
        let payloadData = try BackupService.encoder.encode(payload)
        let secureData = try BackupService.encoder.encode(secureProfiles)
        try payloadData.write(to: extracted.directory.appendingPathComponent(BackupService.payloadFileName), options: .atomic)
        try secureData.write(
            to: extracted.directory
                .appendingPathComponent("settings", isDirectory: true)
                .appendingPathComponent(BackupService.securePayloadFileName),
            options: .atomic
        )

        let updatedManifest = SnapshotManifest(
            snapshotId: extracted.manifest.snapshotId,
            createdAt: extracted.manifest.createdAt,
            scope: extracted.manifest.scope,
            fiscalStartMonth: extracted.manifest.fiscalStartMonth,
            payloadChecksum: ReceiptImageStore.sha256Hex(data: payloadData),
            securePayloadChecksum: ReceiptImageStore.sha256Hex(data: secureData),
            fileRecords: extracted.manifest.fileRecords,
            counts: extracted.manifest.counts.merging([
                "legacy.accountingProfiles": 1,
                "canonical.businessProfiles": 0,
                "canonical.taxYearProfiles": 0,
                "settings.secureProfiles": 1
            ]) { _, new in new },
            warnings: extracted.manifest.warnings
        )
        let manifestData = try BackupService.encoder.encode(updatedManifest)
        try manifestData.write(
            to: extracted.directory.appendingPathComponent(BackupService.manifestFileName),
            options: .atomic
        )

        let mutatedURL = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-only-\(UUID().uuidString).aar")
        try SnapshotArchiveStore.archiveDirectory(extracted.directory, to: mutatedURL)
        try FileManager.default.removeItem(at: extracted.directory)
        return mutatedURL
    }
}
