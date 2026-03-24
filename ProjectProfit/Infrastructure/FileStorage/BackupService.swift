import Foundation
import SwiftData

struct BackupExportResult: Sendable {
    let archiveURL: URL
    let manifest: SnapshotManifest
}

enum SnapshotServiceError: LocalizedError {
    case payloadEncodingFailed
    case payloadDecodingFailed
    case manifestMissing
    case payloadMissing
    case securePayloadMissing
    case checksumMismatch(String)
    case restorePreflightFailed([String])

    var errorDescription: String? {
        switch self {
        case .payloadEncodingFailed:
            return "スナップショットのエンコードに失敗しました。"
        case .payloadDecodingFailed:
            return "スナップショットのデコードに失敗しました。"
        case .manifestMissing:
            return "manifest.json が見つかりません。"
        case .payloadMissing:
            return "payload.json が見つかりません。"
        case .securePayloadMissing:
            return "secure payload が見つかりません。"
        case let .checksumMismatch(path):
            return "チェックサムが一致しません: \(path)"
        case let .restorePreflightFailed(issues):
            return issues.joined(separator: "\n")
        }
    }
}

@MainActor
struct BackupService {
    private let modelContext: ModelContext
    private let searchIndexRebuilder: SearchIndexRebuilder

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.searchIndexRebuilder = SearchIndexRebuilder(modelContext: modelContext)
    }

    func export(scope: BackupScope) throws -> BackupExportResult {
        let stageDirectory = try makeTemporaryDirectory(prefix: "snapshot-stage")
        defer { try? FileManager.default.removeItem(at: stageDirectory) }

        let payload = try makeSnapshotPayload(scope: scope)
        let secureProfiles = loadSecureProfiles(payload: payload)
        let payloadData = try Self.encoder.encode(payload)
        let secureData = try Self.encoder.encode(secureProfiles)

        try write(data: payloadData, to: stageDirectory.appendingPathComponent(Self.payloadFileName))

        let settingsDirectory = stageDirectory.appendingPathComponent("settings", isDirectory: true)
        try FileManager.default.createDirectory(at: settingsDirectory, withIntermediateDirectories: true)
        try write(data: secureData, to: settingsDirectory.appendingPathComponent(Self.securePayloadFileName))

        let stagedFiles = try stageReferencedFiles(payload: payload, in: stageDirectory)
        let manifest = SnapshotManifest(
            snapshotId: UUID(),
            createdAt: Date(),
            scope: scope,
            fiscalStartMonth: FiscalYearSettings.startMonth,
            payloadChecksum: ReceiptImageStore.sha256Hex(data: payloadData),
            securePayloadChecksum: ReceiptImageStore.sha256Hex(data: secureData),
            fileRecords: stagedFiles.records,
            counts: makeCounts(payload: payload, secureProfiles: secureProfiles, fileRecords: stagedFiles.records),
            warnings: stagedFiles.warnings
        )
        let manifestData = try Self.encoder.encode(manifest)
        try write(data: manifestData, to: stageDirectory.appendingPathComponent(Self.manifestFileName))

        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectProfit_\(scope.label)_\(Self.timestampString(from: manifest.createdAt)).aar")
        try SnapshotArchiveStore.archiveDirectory(stageDirectory, to: archiveURL)
        return BackupExportResult(archiveURL: archiveURL, manifest: manifest)
    }

    func rebuildDerivedIndexes() throws {
        try searchIndexRebuilder.rebuildAll()
    }

    private func makeSnapshotPayload(scope: BackupScope) throws -> AppSnapshotPayload {
        let fiscalStartMonth = FiscalYearSettings.startMonth
        let allProjects = try fetchAll(PPProject.self)
        let allCategories = try fetchAll(PPCategory.self)
        let allRecurring = try fetchAll(PPRecurringTransaction.self)
        let allTransactions = try fetchAll(PPTransaction.self)
        let allAccounts = try fetchAll(PPAccount.self)
        let allJournalEntries = try fetchAll(PPJournalEntry.self)
        let allJournalLines = try fetchAll(PPJournalLine.self)
        let allUserRules = try fetchAll(PPUserRule.self)
        let allFixedAssets = try fetchAll(PPFixedAsset.self)
        let allInventory = try fetchAll(PPInventoryRecord.self)
        let allDocuments = try fetchAll(PPDocumentRecord.self)
        let allComplianceLogs = try fetchAll(PPComplianceLog.self)
        let allTransactionLogs = try fetchAll(PPTransactionLog.self)
        let allLedgerBooks = try fetchAll(SDLedgerBook.self)
        let allLedgerEntries = try fetchAll(SDLedgerEntry.self)

        let transactions = allTransactions.filter { includes(date: $0.date, scope: scope, fiscalStartMonth: fiscalStartMonth) }
        let transactionIds = Set(transactions.map(\.id))

        let journalEntries = allJournalEntries.filter { includes(date: $0.date, scope: scope, fiscalStartMonth: fiscalStartMonth) }
        let journalEntryIds = Set(journalEntries.map(\.id))
        let journalLines = allJournalLines.filter { journalEntryIds.contains($0.entryId) }

        let inventoryRecords = allInventory.filter { includes(fiscalYear: $0.fiscalYear, scope: scope) }
        let documentRecords = allDocuments.filter {
            if let transactionId = $0.transactionId, transactionIds.contains(transactionId) {
                return true
            }
            return includes(date: $0.issueDate, scope: scope, fiscalStartMonth: fiscalStartMonth)
        }
        let documentIds = Set(documentRecords.map(\.id))
        let complianceLogs = allComplianceLogs.filter {
            ($0.documentId.map(documentIds.contains) ?? false) || ($0.transactionId.map(transactionIds.contains) ?? false)
        }
        let transactionLogs = allTransactionLogs.filter { transactionIds.contains($0.transactionId) }

        let taxYearProfiles = try fetchAll(TaxYearProfileEntity.self)
            .map(TaxYearProfileEntityMapper.toDomain)
            .filter { includes(fiscalYear: $0.taxYear, scope: scope) }
        let businessProfiles = try fetchAll(BusinessProfileEntity.self)
            .map(BusinessProfileEntityMapper.toDomain)
        let evidenceDocuments = try fetchAll(EvidenceRecordEntity.self)
            .map(EvidenceRecordEntityMapper.toDomain)
            .filter { includes(fiscalYear: $0.taxYear, scope: scope) }
        let evidenceIds = Set(evidenceDocuments.map(\.id))

        let postingCandidates = try fetchAll(PostingCandidateEntity.self)
            .map(PostingCandidateEntityMapper.toDomain)
            .filter { includes(fiscalYear: $0.taxYear, scope: scope) }
        let candidateIds = Set(postingCandidates.map(\.id))

        let canonicalJournals = try fetchAll(JournalEntryEntity.self)
            .map(CanonicalJournalEntryEntityMapper.toDomain)
            .filter { includes(fiscalYear: $0.taxYear, scope: scope) }
        let journalIds = Set(canonicalJournals.map(\.id))

        let counterparties = try fetchAll(CounterpartyEntity.self)
            .map(CounterpartyEntityMapper.toDomain)
        let canonicalAccounts = try fetchAll(CanonicalAccountEntity.self)
            .map(CanonicalAccountEntityMapper.toDomain)
        let distributionRules = try fetchAll(DistributionRuleEntity.self)
            .map(DistributionRuleEntityMapper.toDomain)
        let auditEvents = try fetchAll(AuditEventEntity.self)
            .map(AuditEventEntityMapper.toDomain)
            .filter { event in
                switch scope {
                case .full:
                    return true
                case .taxYear(_):
                    if evidenceIds.contains(event.aggregateId) || candidateIds.contains(event.aggregateId) || journalIds.contains(event.aggregateId) {
                        return true
                    }
                    if let relatedEvidenceId = event.relatedEvidenceId, evidenceIds.contains(relatedEvidenceId) {
                        return true
                    }
                    if let relatedJournalId = event.relatedJournalId, journalIds.contains(relatedJournalId) {
                        return true
                    }
                    return false
                }
            }

        let recurringTransactions: [PPRecurringTransaction]
        switch scope {
        case .full:
            recurringTransactions = allRecurring
        case .taxYear(_):
            let recurringIds = Set(transactions.compactMap(\.recurringId))
            recurringTransactions = allRecurring.filter { recurringIds.contains($0.id) }
        }

        let transactionProjectIds = transactions.flatMap { $0.allocations.map(\.projectId) }
        let evidenceProjectIds = evidenceDocuments.flatMap(\.linkedProjectIds)
        let postingCandidateProjectIds = postingCandidates.flatMap { $0.proposedLines.compactMap(\.projectAllocationId) }
        let canonicalJournalProjectIds = canonicalJournals.flatMap { $0.lines.compactMap(\.projectAllocationId) }
        let combinedProjectIds = transactionProjectIds
            + evidenceProjectIds
            + postingCandidateProjectIds
            + canonicalJournalProjectIds
        let projectIdsInScope = Set(combinedProjectIds)
        let categoryIdsInScope = Set(transactions.map(\.categoryId) + recurringTransactions.map(\.categoryId))
        let legacyAccountIds = transactions.compactMap(\.paymentAccountId)
            + transactions.compactMap(\.transferToAccountId)
            + recurringTransactions.compactMap(\.paymentAccountId)
            + recurringTransactions.compactMap(\.transferToAccountId)
            + journalLines.map(\.accountId)
        let legacyAccountIdsInScope = Set(legacyAccountIds)

        let postingCandidateAccountIds = postingCandidates.flatMap { candidate in
            candidate.proposedLines.compactMap(\.debitAccountId) + candidate.proposedLines.compactMap(\.creditAccountId)
        }
        let canonicalAccountIds = canonicalJournals.flatMap { $0.lines.map(\.accountId) } + postingCandidateAccountIds
        let canonicalAccountIdsInScope = Set(canonicalAccountIds)
        let counterpartyIds = evidenceDocuments.compactMap(\.linkedCounterpartyId)
            + postingCandidates.compactMap(\.counterpartyId)
            + canonicalJournals.flatMap { $0.lines.compactMap(\.counterpartyId) }
        let counterpartyIdsInScope = Set(counterpartyIds)
        let businessIds = taxYearProfiles.map(\.businessId)
            + evidenceDocuments.map(\.businessId)
            + postingCandidates.map(\.businessId)
            + canonicalJournals.map(\.businessId)
        let businessIdsInScope = Set(businessIds)

        let scopedProjects: [PPProject] = switch scope {
        case .full:
            allProjects
        case .taxYear(_):
            allProjects.filter { projectIdsInScope.contains($0.id) }
        }
        let scopedCategories: [PPCategory] = switch scope {
        case .full:
            allCategories
        case .taxYear(_):
            allCategories.filter { categoryIdsInScope.contains($0.id) }
        }
        let scopedLegacyAccounts: [PPAccount] = switch scope {
        case .full:
            allAccounts
        case .taxYear(_):
            allAccounts.filter { legacyAccountIdsInScope.contains($0.id) }
        }
        let scopedUserRules: [PPUserRule] = switch scope {
        case .full:
            allUserRules
        case .taxYear(_):
            []
        }
        let scopedFixedAssets: [PPFixedAsset] = switch scope {
        case .full:
            allFixedAssets
        case .taxYear(_):
            []
        }
        let scopedLedgerBooks: [SDLedgerBook] = switch scope {
        case .full:
            allLedgerBooks
        case .taxYear(_):
            []
        }
        let scopedLedgerEntries: [SDLedgerEntry] = switch scope {
        case .full:
            allLedgerEntries
        case .taxYear(_):
            []
        }
        let scopedBusinessProfiles: [BusinessProfile] = switch scope {
        case .full:
            businessProfiles
        case .taxYear(_):
            businessProfiles.filter { businessIdsInScope.contains($0.id) }
        }
        let scopedCounterparties: [Counterparty] = switch scope {
        case .full:
            counterparties
        case .taxYear(_):
            counterparties.filter { counterpartyIdsInScope.contains($0.id) }
        }
        let scopedCanonicalAccounts: [CanonicalAccount] = switch scope {
        case .full:
            canonicalAccounts
        case .taxYear(_):
            canonicalAccounts.filter { canonicalAccountIdsInScope.contains($0.id) }
        }
        let scopedDistributionRules: [DistributionRule] = switch scope {
        case .full:
            distributionRules
        case .taxYear(_):
            []
        }

        return AppSnapshotPayload(
            fiscalStartMonth: fiscalStartMonth,
            legacy: LegacySnapshotSection(
                projects: scopedProjects.map(LegacyProjectSnapshot.init),
                categories: scopedCategories.map(LegacyCategorySnapshot.init),
                recurringTransactions: recurringTransactions.map(LegacyRecurringTransactionSnapshot.init),
                transactions: transactions.map(LegacyTransactionSnapshot.init),
                accounts: scopedLegacyAccounts.map(LegacyAccountSnapshot.init),
                journalEntries: journalEntries.map(LegacyJournalEntrySnapshot.init),
                journalLines: journalLines.map(LegacyJournalLineSnapshot.init),
                // Legacy profile snapshots are restore-compat only. New backups use canonical profiles as the single source of truth.
                accountingProfiles: [],
                userRules: scopedUserRules.map(LegacyUserRuleSnapshot.init),
                fixedAssets: scopedFixedAssets.map(LegacyFixedAssetSnapshot.init),
                inventoryRecords: inventoryRecords.map(LegacyInventoryRecordSnapshot.init),
                documentRecords: documentRecords.map(LegacyDocumentRecordSnapshot.init),
                complianceLogs: complianceLogs.map(LegacyComplianceLogSnapshot.init),
                transactionLogs: transactionLogs.map(LegacyTransactionLogSnapshot.init),
                ledgerBooks: scopedLedgerBooks.map(LegacyLedgerBookSnapshot.init),
                ledgerEntries: scopedLedgerEntries.map(LegacyLedgerEntrySnapshot.init)
            ),
            canonical: CanonicalSnapshotSection(
                businessProfiles: scopedBusinessProfiles,
                taxYearProfiles: taxYearProfiles,
                evidenceDocuments: evidenceDocuments,
                postingCandidates: postingCandidates,
                journalEntries: canonicalJournals,
                counterparties: scopedCounterparties,
                accounts: scopedCanonicalAccounts,
                distributionRules: scopedDistributionRules,
                auditEvents: auditEvents
            )
        )
    }

    private func loadSecureProfiles(payload: AppSnapshotPayload) -> [SnapshotSecureProfile] {
        // Secure profile payloads are exported only for canonical business profiles.
        return payload.canonical.businessProfiles.compactMap { profile in
            let canonicalProfileId = profile.id.uuidString
            guard let payload = ProfileSecureStore.load(profileId: canonicalProfileId) else {
                return nil
            }
            return SnapshotSecureProfile(profileId: canonicalProfileId, payload: payload)
        }
    }

    private func stageReferencedFiles(
        payload: AppSnapshotPayload,
        in stageDirectory: URL
    ) throws -> (records: [SnapshotFileRecord], warnings: [String]) {
        let filesRoot = stageDirectory.appendingPathComponent("files", isDirectory: true)
        let receiptRoot = filesRoot.appendingPathComponent("ReceiptImages", isDirectory: true)
        let documentRoot = filesRoot.appendingPathComponent("DocumentFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: receiptRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documentRoot, withIntermediateDirectories: true)

        var records: [SnapshotFileRecord] = []
        var warnings: [String] = []

        for fileName in Set(payload.legacy.transactions.compactMap(\.receiptImagePath) + payload.legacy.recurringTransactions.compactMap(\.receiptImagePath)) {
            guard let data = ReceiptImageStore.loadImageData(fileName: fileName) else {
                warnings.append("missing receipt image: \(fileName)")
                continue
            }
            let targetURL = receiptRoot.appendingPathComponent(fileName)
            try write(data: data, to: targetURL)
            records.append(SnapshotFileRecord(
                category: .receiptImage,
                fileName: fileName,
                relativePath: "files/ReceiptImages/\(fileName)",
                byteCount: data.count,
                sha256: ReceiptImageStore.sha256Hex(data: data)
            ))
        }

        let documentFileNames = Set(payload.legacy.documentRecords.map(\.storedFileName) + payload.canonical.evidenceDocuments.map(\.originalFilePath))
        for fileName in documentFileNames {
            guard let data = ReceiptImageStore.loadDocumentData(fileName: fileName) else {
                warnings.append("missing document file: \(fileName)")
                continue
            }
            let targetURL = documentRoot.appendingPathComponent(fileName)
            try write(data: data, to: targetURL)
            records.append(SnapshotFileRecord(
                category: .documentFile,
                fileName: fileName,
                relativePath: "files/DocumentFiles/\(fileName)",
                byteCount: data.count,
                sha256: ReceiptImageStore.sha256Hex(data: data)
            ))
        }

        return (records, warnings)
    }

    private func makeCounts(
        payload: AppSnapshotPayload,
        secureProfiles: [SnapshotSecureProfile],
        fileRecords: [SnapshotFileRecord]
    ) -> [String: Int] {
        [
            "legacy.projects": payload.legacy.projects.count,
            "legacy.categories": payload.legacy.categories.count,
            "legacy.recurring": payload.legacy.recurringTransactions.count,
            "legacy.transactions": payload.legacy.transactions.count,
            "legacy.accounts": payload.legacy.accounts.count,
            "legacy.journalEntries": payload.legacy.journalEntries.count,
            "legacy.journalLines": payload.legacy.journalLines.count,
            "legacy.accountingProfiles": payload.legacy.accountingProfiles.count,
            "legacy.userRules": payload.legacy.userRules.count,
            "legacy.fixedAssets": payload.legacy.fixedAssets.count,
            "legacy.inventoryRecords": payload.legacy.inventoryRecords.count,
            "legacy.documentRecords": payload.legacy.documentRecords.count,
            "legacy.complianceLogs": payload.legacy.complianceLogs.count,
            "legacy.transactionLogs": payload.legacy.transactionLogs.count,
            "legacy.ledgerBooks": payload.legacy.ledgerBooks.count,
            "legacy.ledgerEntries": payload.legacy.ledgerEntries.count,
            "canonical.businessProfiles": payload.canonical.businessProfiles.count,
            "canonical.taxYearProfiles": payload.canonical.taxYearProfiles.count,
            "canonical.evidenceDocuments": payload.canonical.evidenceDocuments.count,
            "canonical.postingCandidates": payload.canonical.postingCandidates.count,
            "canonical.journalEntries": payload.canonical.journalEntries.count,
            "canonical.counterparties": payload.canonical.counterparties.count,
            "canonical.accounts": payload.canonical.accounts.count,
            "canonical.distributionRules": payload.canonical.distributionRules.count,
            "canonical.auditEvents": payload.canonical.auditEvents.count,
            "settings.secureProfiles": secureProfiles.count,
            "files.total": fileRecords.count,
        ]
    }

    private func includes(date: Date, scope: BackupScope, fiscalStartMonth: Int) -> Bool {
        switch scope {
        case .full:
            return true
        case let .taxYear(targetYear):
            return fiscalYear(for: date, startMonth: fiscalStartMonth) == targetYear
        }
    }

    private func includes(fiscalYear: Int, scope: BackupScope) -> Bool {
        switch scope {
        case .full:
            return true
        case let .taxYear(targetYear):
            return fiscalYear == targetYear
        }
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try modelContext.fetch(FetchDescriptor<T>())
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }

    static let manifestFileName = "manifest.json"
    static let payloadFileName = "payload.json"
    static let securePayloadFileName = "profile-secure.json"

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
