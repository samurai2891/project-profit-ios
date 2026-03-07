import Foundation
import SwiftData

struct RestoreConflict: Equatable, Sendable {
    let modelName: String
    let existingCount: Int
    let incomingCount: Int
}

struct RestoreDryRunReport: Sendable {
    let manifest: SnapshotManifest
    let issues: [String]
    let warnings: [String]
    let conflicts: [RestoreConflict]

    var canApply: Bool {
        issues.isEmpty
    }
}

struct RestoreApplyResult: Sendable {
    let report: RestoreDryRunReport
    let rollbackArchiveURL: URL
}

@MainActor
struct RestoreService {
    let modelContext: ModelContext
    private let backupService: BackupService
    private let searchIndexRebuilder: SearchIndexRebuilder

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.backupService = BackupService(modelContext: modelContext)
        self.searchIndexRebuilder = SearchIndexRebuilder(modelContext: modelContext)
    }

    func dryRun(snapshotURL: URL) throws -> RestoreDryRunReport {
        let extracted = try extractSnapshot(snapshotURL: snapshotURL)
        defer { try? FileManager.default.removeItem(at: extracted.directory) }
        let payload = extracted.payload
        let manifest = extracted.manifest
        let secureProfiles = extracted.secureProfiles

        var issues: [String] = []
        var warnings = manifest.warnings

        let payloadChecksum = ReceiptImageStore.sha256Hex(data: extracted.payloadData)
        if payloadChecksum != manifest.payloadChecksum {
            issues.append("payload checksum mismatch")
        }

        let secureChecksum = ReceiptImageStore.sha256Hex(data: extracted.secureData)
        if secureChecksum != manifest.securePayloadChecksum {
            issues.append("secure payload checksum mismatch")
        }

        let fileRecordByPath = Dictionary(uniqueKeysWithValues: manifest.fileRecords.map { ($0.relativePath, $0) })
        for record in manifest.fileRecords {
            let fileURL = extracted.directory.appendingPathComponent(record.relativePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                issues.append("missing file in snapshot: \(record.relativePath)")
                continue
            }
            let data = try Data(contentsOf: fileURL)
            let digest = ReceiptImageStore.sha256Hex(data: data)
            if digest != record.sha256 {
                issues.append("checksum mismatch: \(record.relativePath)")
            }
        }

        issues.append(contentsOf: payloadIntegrityIssues(payload: payload, fileRecordByPath: fileRecordByPath))

        let conflicts = try existingConflicts(for: payload, scope: manifest.scope)
        if secureProfiles.isEmpty,
           (!payload.legacy.accountingProfiles.isEmpty || !payload.canonical.businessProfiles.isEmpty) {
            warnings.append("secure profile payload is empty")
        }

        return RestoreDryRunReport(
            manifest: manifest,
            issues: issues,
            warnings: warnings,
            conflicts: conflicts
        )
    }

    func apply(snapshotURL: URL) throws -> RestoreApplyResult {
        let report = try dryRun(snapshotURL: snapshotURL)
        guard report.canApply else {
            throw SnapshotServiceError.restorePreflightFailed(report.issues)
        }

        let extracted = try extractSnapshot(snapshotURL: snapshotURL)
        defer { try? FileManager.default.removeItem(at: extracted.directory) }
        let rollback = try backupService.export(scope: report.manifest.scope)
        let filesToDelete = try clearScope(report.manifest.scope)

        do {
            try restoreFiles(from: extracted.directory, records: report.manifest.fileRecords)
            try restoreSecureProfiles(extracted.secureProfiles)
            try restorePayload(extracted.payload)
            try modelContext.save()
            try searchIndexRebuilder.rebuildAll()
        } catch {
            cleanupFiles(filesToDelete)
            throw error
        }

        return RestoreApplyResult(report: report, rollbackArchiveURL: rollback.archiveURL)
    }

    private func extractSnapshot(snapshotURL: URL) throws -> ExtractedSnapshot {
        let directory = try makeTemporaryDirectory(prefix: "snapshot-restore")
        try SnapshotArchiveStore.extractArchive(at: snapshotURL, to: directory)
        let manifestURL = directory.appendingPathComponent(BackupService.manifestFileName)
        let payloadURL = directory.appendingPathComponent(BackupService.payloadFileName)
        let secureURL = directory
            .appendingPathComponent("settings", isDirectory: true)
            .appendingPathComponent(BackupService.securePayloadFileName)

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw SnapshotServiceError.manifestMissing
        }
        guard FileManager.default.fileExists(atPath: payloadURL.path) else {
            throw SnapshotServiceError.payloadMissing
        }
        guard FileManager.default.fileExists(atPath: secureURL.path) else {
            throw SnapshotServiceError.securePayloadMissing
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let payloadData = try Data(contentsOf: payloadURL)
        let secureData = try Data(contentsOf: secureURL)
        let manifest = try BackupService.decoder.decode(SnapshotManifest.self, from: manifestData)
        let payload = try BackupService.decoder.decode(AppSnapshotPayload.self, from: payloadData)
        let secureProfiles = try BackupService.decoder.decode([SnapshotSecureProfile].self, from: secureData)

        return ExtractedSnapshot(
            directory: directory,
            manifest: manifest,
            payload: payload,
            secureProfiles: secureProfiles,
            payloadData: payloadData,
            secureData: secureData
        )
    }

    private func payloadIntegrityIssues(
        payload: AppSnapshotPayload,
        fileRecordByPath: [String: SnapshotFileRecord]
    ) -> [String] {
        var issues: [String] = []

        let projectIds = Set(payload.legacy.projects.map(\.id))
        let categoryIds = Set(payload.legacy.categories.map(\.id))
        let accountIds = Set(payload.legacy.accounts.map(\.id))
        let transactionIds = Set(payload.legacy.transactions.map(\.id))
        let journalEntryIds = Set(payload.legacy.journalEntries.map(\.id))
        let documentIds = Set(payload.legacy.documentRecords.map(\.id))
        let evidenceIds = Set(payload.canonical.evidenceDocuments.map(\.id))
        let candidateIds = Set(payload.canonical.postingCandidates.map(\.id))
        let canonicalJournalIds = Set(payload.canonical.journalEntries.map(\.id))
        let counterpartyIds = Set(payload.canonical.counterparties.map(\.id))
        let canonicalAccountIds = Set(payload.canonical.accounts.map(\.id))

        for transaction in payload.legacy.transactions {
            if !categoryIds.contains(transaction.categoryId) {
                issues.append("transaction category missing: \(transaction.id.uuidString)")
            }
            if let paymentAccountId = transaction.paymentAccountId,
               !accountIds.contains(paymentAccountId) {
                issues.append("transaction paymentAccount missing: \(transaction.id.uuidString)")
            }
            if let transferToAccountId = transaction.transferToAccountId,
               !accountIds.contains(transferToAccountId) {
                issues.append("transaction transferAccount missing: \(transaction.id.uuidString)")
            }
            for allocation in transaction.allocations where !projectIds.contains(allocation.projectId) {
                issues.append("transaction allocation project missing: \(transaction.id.uuidString)")
            }
            if let imagePath = transaction.receiptImagePath,
               fileRecordByPath["files/ReceiptImages/\(imagePath)"] == nil {
                issues.append("transaction receipt image missing from snapshot: \(imagePath)")
            }
        }

        for recurring in payload.legacy.recurringTransactions {
            if !categoryIds.contains(recurring.categoryId) {
                issues.append("recurring category missing: \(recurring.id.uuidString)")
            }
            if let imagePath = recurring.receiptImagePath,
               fileRecordByPath["files/ReceiptImages/\(imagePath)"] == nil {
                issues.append("recurring receipt image missing from snapshot: \(imagePath)")
            }
        }

        for line in payload.legacy.journalLines where !journalEntryIds.contains(line.entryId) {
            issues.append("journal line entry missing: \(line.id.uuidString)")
        }

        for document in payload.legacy.documentRecords {
            if let transactionId = document.transactionId, !transactionIds.contains(transactionId) {
                issues.append("document transaction missing: \(document.id.uuidString)")
            }
            if fileRecordByPath["files/DocumentFiles/\(document.storedFileName)"] == nil {
                issues.append("document file missing from snapshot: \(document.storedFileName)")
            }
        }

        for log in payload.legacy.complianceLogs {
            if let documentId = log.documentId, !documentIds.contains(documentId) {
                issues.append("compliance log document missing: \(log.id.uuidString)")
            }
            if let transactionId = log.transactionId, !transactionIds.contains(transactionId) {
                issues.append("compliance log transaction missing: \(log.id.uuidString)")
            }
        }

        for candidate in payload.canonical.postingCandidates {
            if let evidenceId = candidate.evidenceId, !evidenceIds.contains(evidenceId) {
                issues.append("candidate evidence missing: \(candidate.id.uuidString)")
            }
            if let counterpartyId = candidate.counterpartyId, !counterpartyIds.contains(counterpartyId) {
                issues.append("candidate counterparty missing: \(candidate.id.uuidString)")
            }
        }

        for evidence in payload.canonical.evidenceDocuments {
            if !fileRecordByPath.keys.contains("files/DocumentFiles/\(evidence.originalFilePath)") {
                issues.append("evidence file missing from snapshot: \(evidence.originalFilePath)")
            }
            if let linkedCounterpartyId = evidence.linkedCounterpartyId,
               !counterpartyIds.contains(linkedCounterpartyId) {
                issues.append("evidence counterparty missing: \(evidence.id.uuidString)")
            }
            for projectId in evidence.linkedProjectIds where !projectIds.contains(projectId) {
                issues.append("evidence project missing: \(evidence.id.uuidString)")
            }
        }

        for journal in payload.canonical.journalEntries {
            if let evidenceId = journal.sourceEvidenceId, !evidenceIds.contains(evidenceId) {
                issues.append("canonical journal evidence missing: \(journal.id.uuidString)")
            }
            if let candidateId = journal.sourceCandidateId, !candidateIds.contains(candidateId) {
                issues.append("canonical journal candidate missing: \(journal.id.uuidString)")
            }
            for line in journal.lines {
                if !canonicalAccountIds.contains(line.accountId) {
                    issues.append("canonical journal account missing: \(journal.id.uuidString)")
                }
                if let projectAllocationId = line.projectAllocationId,
                   !projectIds.contains(projectAllocationId) {
                    issues.append("canonical journal project missing: \(journal.id.uuidString)")
                }
            }
        }

        for audit in payload.canonical.auditEvents {
            if let relatedEvidenceId = audit.relatedEvidenceId, !evidenceIds.contains(relatedEvidenceId) {
                issues.append("audit related evidence missing: \(audit.id.uuidString)")
            }
            if let relatedJournalId = audit.relatedJournalId, !canonicalJournalIds.contains(relatedJournalId) {
                issues.append("audit related journal missing: \(audit.id.uuidString)")
            }
        }

        return issues
    }

    private func existingConflicts(
        for payload: AppSnapshotPayload,
        scope: BackupScope
    ) throws -> [RestoreConflict] {
        let fiscalStartMonth = FiscalYearSettings.startMonth
        switch scope {
        case .full:
            return try [
                RestoreConflict(modelName: "PPTransaction", existingCount: fetchAll(PPTransaction.self).count, incomingCount: payload.legacy.transactions.count),
                RestoreConflict(modelName: "PPDocumentRecord", existingCount: fetchAll(PPDocumentRecord.self).count, incomingCount: payload.legacy.documentRecords.count),
                RestoreConflict(modelName: "EvidenceRecordEntity", existingCount: fetchAll(EvidenceRecordEntity.self).count, incomingCount: payload.canonical.evidenceDocuments.count),
                RestoreConflict(modelName: "JournalEntryEntity", existingCount: fetchAll(JournalEntryEntity.self).count, incomingCount: payload.canonical.journalEntries.count),
            ]
        case let .taxYear(year):
            let legacyTransactions = try fetchAll(PPTransaction.self).filter { fiscalYear(for: $0.date, startMonth: fiscalStartMonth) == year }
            let legacyDocuments = try fetchAll(PPDocumentRecord.self).filter {
                if let transactionId = $0.transactionId {
                    return legacyTransactions.contains(where: { $0.id == transactionId })
                }
                return fiscalYear(for: $0.issueDate, startMonth: fiscalStartMonth) == year
            }
            let evidence = try fetchAll(EvidenceRecordEntity.self).filter { $0.taxYear == year }
            let canonicalJournals = try fetchAll(JournalEntryEntity.self).filter { $0.taxYear == year }
            return [
                RestoreConflict(modelName: "PPTransaction", existingCount: legacyTransactions.count, incomingCount: payload.legacy.transactions.count),
                RestoreConflict(modelName: "PPDocumentRecord", existingCount: legacyDocuments.count, incomingCount: payload.legacy.documentRecords.count),
                RestoreConflict(modelName: "EvidenceRecordEntity", existingCount: evidence.count, incomingCount: payload.canonical.evidenceDocuments.count),
                RestoreConflict(modelName: "JournalEntryEntity", existingCount: canonicalJournals.count, incomingCount: payload.canonical.journalEntries.count),
            ]
        }
    }

    private func clearScope(_ scope: BackupScope) throws -> [SnapshotFileRecord] {
        switch scope {
        case .full:
            let fileRecords = collectExistingFileRecords()
            let secureProfileIds = try collectExistingSecureProfileIds()
            try deleteAll(PPProject.self)
            try deleteAll(PPTransaction.self)
            try deleteAll(PPCategory.self)
            try deleteAll(PPRecurringTransaction.self)
            try deleteAll(PPAccount.self)
            try deleteAll(PPJournalLine.self)
            try deleteAll(PPJournalEntry.self)
            try deleteAll(PPAccountingProfile.self)
            try deleteAll(PPUserRule.self)
            try deleteAll(PPFixedAsset.self)
            try deleteAll(PPInventoryRecord.self)
            try deleteAll(PPComplianceLog.self)
            try deleteAll(PPDocumentRecord.self)
            try deleteAll(PPTransactionLog.self)
            try deleteAll(SDLedgerEntry.self)
            try deleteAll(SDLedgerBook.self)
            try deleteAll(BusinessProfileEntity.self)
            try deleteAll(TaxYearProfileEntity.self)
            try deleteAll(EvidenceRecordEntity.self)
            try deleteAll(PostingCandidateEntity.self)
            try deleteAll(JournalLineEntity.self)
            try deleteAll(JournalEntryEntity.self)
            try deleteAll(CounterpartyEntity.self)
            try deleteAll(CanonicalAccountEntity.self)
            try deleteAll(DistributionRuleEntity.self)
            try deleteAll(AuditEventEntity.self)
            try deleteAll(EvidenceSearchIndexEntity.self)
            try deleteAll(JournalSearchIndexEntity.self)
            try modelContext.save()
            clearSecureProfiles(profileIds: secureProfileIds)
            clearAllFiles()
            return fileRecords
        case let .taxYear(year):
            let fiscalStartMonth = FiscalYearSettings.startMonth
            let transactions = try fetchAll(PPTransaction.self).filter { fiscalYear(for: $0.date, startMonth: fiscalStartMonth) == year }
            let transactionIds = Set(transactions.map(\.id))
            let journalEntries = try fetchAll(PPJournalEntry.self).filter { fiscalYear(for: $0.date, startMonth: fiscalStartMonth) == year }
            let journalEntryIds = Set(journalEntries.map(\.id))
            let documents = try fetchAll(PPDocumentRecord.self).filter {
                if let transactionId = $0.transactionId, transactionIds.contains(transactionId) {
                    return true
                }
                return fiscalYear(for: $0.issueDate, startMonth: fiscalStartMonth) == year
            }
            let documentIds = Set(documents.map(\.id))
            let evidence = try fetchAll(EvidenceRecordEntity.self).filter { $0.taxYear == year }
            let evidenceIds = Set(evidence.map(\.evidenceId))
            let candidates = try fetchAll(PostingCandidateEntity.self).filter { $0.taxYear == year }
            let candidateIds = Set(candidates.map(\.candidateId))
            let canonicalJournals = try fetchAll(JournalEntryEntity.self).filter { $0.taxYear == year }
            let canonicalJournalIds = Set(canonicalJournals.map(\.journalId))
            let inventoryRecords = try fetchAll(PPInventoryRecord.self).filter { $0.fiscalYear == year }
            let taxYearProfiles = try fetchAll(TaxYearProfileEntity.self).filter { $0.taxYear == year }
            let journalLines = try fetchAll(PPJournalLine.self).filter { journalEntryIds.contains($0.entryId) }
            let complianceLogs = try fetchAll(PPComplianceLog.self).filter {
                ($0.documentId.map(documentIds.contains) ?? false) || ($0.transactionId.map(transactionIds.contains) ?? false)
            }
            let transactionLogs = try fetchAll(PPTransactionLog.self).filter { transactionIds.contains($0.transactionId) }
            let auditEvents = try fetchAll(AuditEventEntity.self).filter {
                evidenceIds.contains($0.aggregateId)
                    || candidateIds.contains($0.aggregateId)
                    || canonicalJournalIds.contains($0.aggregateId)
                    || ($0.relatedEvidenceId.map(evidenceIds.contains) ?? false)
                    || ($0.relatedJournalId.map(canonicalJournalIds.contains) ?? false)
            }
            let evidenceIndex = try fetchAll(EvidenceSearchIndexEntity.self).filter { $0.taxYear == year }
            let journalIndex = try fetchAll(JournalSearchIndexEntity.self).filter { $0.taxYear == year }
            let files = fileRecordsToDelete(
                transactions: transactions,
                documents: documents,
                evidence: evidence.map(EvidenceRecordEntityMapper.toDomain)
            )

            documents.forEach(modelContext.delete)
            complianceLogs.forEach(modelContext.delete)
            transactionLogs.forEach(modelContext.delete)
            journalLines.forEach(modelContext.delete)
            journalEntries.forEach(modelContext.delete)
            transactions.forEach(modelContext.delete)
            inventoryRecords.forEach(modelContext.delete)
            taxYearProfiles.forEach(modelContext.delete)
            evidence.forEach(modelContext.delete)
            candidates.forEach(modelContext.delete)
            canonicalJournals.forEach(modelContext.delete)
            auditEvents.forEach(modelContext.delete)
            evidenceIndex.forEach(modelContext.delete)
            journalIndex.forEach(modelContext.delete)
            try modelContext.save()
            cleanupFiles(files)
            return files
        }
    }

    private func restorePayload(_ payload: AppSnapshotPayload) throws {
        UserDefaults.standard.set(payload.fiscalStartMonth, forKey: FiscalYearSettings.userDefaultsKey)

        try upsertLegacyProjects(payload.legacy.projects)
        try upsertLegacyCategories(payload.legacy.categories)
        try upsertLegacyRecurringTransactions(payload.legacy.recurringTransactions)
        try upsertLegacyTransactions(payload.legacy.transactions)
        try upsertLegacyAccounts(payload.legacy.accounts)
        try upsertLegacyJournalEntries(payload.legacy.journalEntries)
        try upsertLegacyJournalLines(payload.legacy.journalLines)
        try upsertLegacyAccountingProfiles(payload.legacy.accountingProfiles)
        try upsertLegacyUserRules(payload.legacy.userRules)
        try upsertLegacyFixedAssets(payload.legacy.fixedAssets)
        try upsertLegacyInventory(payload.legacy.inventoryRecords)
        try upsertLegacyDocuments(payload.legacy.documentRecords)
        try upsertLegacyComplianceLogs(payload.legacy.complianceLogs)
        try upsertLegacyTransactionLogs(payload.legacy.transactionLogs)
        try upsertLedgerBooks(payload.legacy.ledgerBooks)
        try upsertLedgerEntries(payload.legacy.ledgerEntries)

        try upsertBusinessProfiles(payload.canonical.businessProfiles)
        try upsertTaxYearProfiles(payload.canonical.taxYearProfiles)
        try upsertEvidenceDocuments(payload.canonical.evidenceDocuments)
        try upsertPostingCandidates(payload.canonical.postingCandidates)
        try upsertCanonicalJournals(payload.canonical.journalEntries)
        try upsertCounterparties(payload.canonical.counterparties)
        try upsertCanonicalAccounts(payload.canonical.accounts)
        try upsertDistributionRules(payload.canonical.distributionRules)
        try upsertAuditEvents(payload.canonical.auditEvents)
    }

    private func restoreFiles(from directory: URL, records: [SnapshotFileRecord]) throws {
        for record in records {
            let fileURL = directory.appendingPathComponent(record.relativePath)
            let data = try Data(contentsOf: fileURL)
            switch record.category {
            case .receiptImage:
                try ReceiptImageStore.storeImageData(data, fileName: record.fileName)
            case .documentFile:
                try ReceiptImageStore.storeDocumentData(data, fileName: record.fileName)
            case .settings:
                continue
            }
        }
    }

    private func restoreSecureProfiles(_ secureProfiles: [SnapshotSecureProfile]) throws {
        for profile in secureProfiles {
            guard ProfileSecureStore.save(profile.payload, profileId: profile.profileId) else {
                throw SnapshotServiceError.restorePreflightFailed(["secure profile save failed: \(profile.profileId)"])
            }
        }
    }

    private func collectExistingSecureProfileIds() throws -> Set<String> {
        let businessIds = try fetchAll(BusinessProfileEntity.self).map { $0.businessId.uuidString }
        let legacyIds = try fetchAll(PPAccountingProfile.self).map(\.id)
        return Set(businessIds + legacyIds)
    }

    private func clearSecureProfiles(profileIds: Set<String>) {
        for profileId in profileIds {
            _ = ProfileSecureStore.delete(profileId: profileId)
        }
    }

    private func clearAllFiles() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: ReceiptImageStore.imageDirectoryURL.path) {
            try? fileManager.removeItem(at: ReceiptImageStore.imageDirectoryURL)
        }
        if fileManager.fileExists(atPath: ReceiptImageStore.documentDirectoryURL.path) {
            try? fileManager.removeItem(at: ReceiptImageStore.documentDirectoryURL)
        }
    }

    private func collectExistingFileRecords() -> [SnapshotFileRecord] {
        let transactions = (try? fetchAll(PPTransaction.self)) ?? []
        let recurring = (try? fetchAll(PPRecurringTransaction.self)) ?? []
        let documents = (try? fetchAll(PPDocumentRecord.self)) ?? []
        let evidence = ((try? fetchAll(EvidenceRecordEntity.self)) ?? []).map(EvidenceRecordEntityMapper.toDomain)
        return fileRecordsToDelete(transactions: transactions, documents: documents, evidence: evidence, recurring: recurring)
    }

    private func fileRecordsToDelete(
        transactions: [PPTransaction],
        documents: [PPDocumentRecord],
        evidence: [EvidenceDocument],
        recurring: [PPRecurringTransaction] = []
    ) -> [SnapshotFileRecord] {
        var records: [SnapshotFileRecord] = []
        for fileName in Set(transactions.compactMap(\.receiptImagePath) + recurring.compactMap(\.receiptImagePath)) {
            records.append(SnapshotFileRecord(category: .receiptImage, fileName: fileName, relativePath: "", byteCount: 0, sha256: ""))
        }
        for fileName in Set(documents.map(\.storedFileName) + evidence.map(\.originalFilePath)) {
            records.append(SnapshotFileRecord(category: .documentFile, fileName: fileName, relativePath: "", byteCount: 0, sha256: ""))
        }
        return records
    }

    private func cleanupFiles(_ files: [SnapshotFileRecord]) {
        for record in files {
            switch record.category {
            case .receiptImage:
                ReceiptImageStore.deleteImage(fileName: record.fileName)
            case .documentFile:
                ReceiptImageStore.deleteDocumentFile(fileName: record.fileName)
            case .settings:
                continue
            }
        }
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        try fetchAll(type).forEach(modelContext.delete)
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try modelContext.fetch(FetchDescriptor<T>())
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct ExtractedSnapshot {
    let directory: URL
    let manifest: SnapshotManifest
    let payload: AppSnapshotPayload
    let secureProfiles: [SnapshotSecureProfile]
    let payloadData: Data
    let secureData: Data
}

private extension BackupScope {
    var taxYear: Int? {
        switch self {
        case .full:
            return nil
        case let .taxYear(year):
            return year
        }
    }
}
