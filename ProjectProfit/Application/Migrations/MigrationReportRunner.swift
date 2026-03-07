import Foundation
import SwiftData

struct MigrationModelDelta: Equatable, Sendable {
    let modelName: String
    let legacyCount: Int
    let canonicalCount: Int
    let executeSupported: Bool
}

struct MigrationOrphanRecord: Equatable, Sendable {
    let area: String
    let identifier: String
    let message: String
}

struct MigrationDryRunReport: Sendable {
    let generatedAt: Date
    let deltas: [MigrationModelDelta]
    let orphanRecords: [MigrationOrphanRecord]
    let warnings: [String]

    var hasIssues: Bool {
        !orphanRecords.isEmpty || !warnings.isEmpty
    }
}

@MainActor
struct MigrationReportRunner {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func dryRun() throws -> MigrationDryRunReport {
        let projects = try fetchAll(PPProject.self)
        let categories = try fetchAll(PPCategory.self)
        let transactions = try fetchAll(PPTransaction.self)
        let recurring = try fetchAll(PPRecurringTransaction.self)
        let accounts = try fetchAll(PPAccount.self)
        let journalEntries = try fetchAll(PPJournalEntry.self)
        let journalLines = try fetchAll(PPJournalLine.self)
        let profiles = try fetchAll(PPAccountingProfile.self)
        let userRules = try fetchAll(PPUserRule.self)
        let fixedAssets = try fetchAll(PPFixedAsset.self)
        let inventoryRecords = try fetchAll(PPInventoryRecord.self)
        let documentRecords = try fetchAll(PPDocumentRecord.self)
        let complianceLogs = try fetchAll(PPComplianceLog.self)
        let transactionLogs = try fetchAll(PPTransactionLog.self)
        let ledgerBooks = try fetchAll(SDLedgerBook.self)
        let ledgerEntries = try fetchAll(SDLedgerEntry.self)

        let businessProfiles = try fetchAll(BusinessProfileEntity.self)
        let taxYearProfiles = try fetchAll(TaxYearProfileEntity.self)
        let evidenceRecords = try fetchAll(EvidenceRecordEntity.self)
        let postingCandidates = try fetchAll(PostingCandidateEntity.self)
        let canonicalJournalEntries = try fetchAll(JournalEntryEntity.self)
        let canonicalJournalLines = try fetchAll(JournalLineEntity.self)
        let counterparties = try fetchAll(CounterpartyEntity.self)
        let canonicalAccounts = try fetchAll(CanonicalAccountEntity.self)
        let distributionRules = try fetchAll(DistributionRuleEntity.self)
        let auditEvents = try fetchAll(AuditEventEntity.self)

        let deltas = [
            MigrationModelDelta(modelName: "Profile", legacyCount: profiles.count, canonicalCount: businessProfiles.count + taxYearProfiles.count, executeSupported: true),
            MigrationModelDelta(modelName: "Transaction", legacyCount: transactions.count, canonicalCount: postingCandidates.count + canonicalJournalEntries.count, executeSupported: true),
            MigrationModelDelta(modelName: "Document", legacyCount: documentRecords.count, canonicalCount: evidenceRecords.count, executeSupported: true),
            MigrationModelDelta(modelName: "Journal", legacyCount: journalEntries.count + journalLines.count, canonicalCount: canonicalJournalEntries.count + canonicalJournalLines.count, executeSupported: true),
            MigrationModelDelta(modelName: "Project", legacyCount: projects.count, canonicalCount: projects.count, executeSupported: false),
            MigrationModelDelta(modelName: "Category", legacyCount: categories.count, canonicalCount: categories.count, executeSupported: false),
            MigrationModelDelta(modelName: "Account", legacyCount: accounts.count, canonicalCount: canonicalAccounts.count, executeSupported: false),
            MigrationModelDelta(modelName: "RecurringRule", legacyCount: recurring.count, canonicalCount: recurring.count, executeSupported: false),
            MigrationModelDelta(modelName: "FixedAsset", legacyCount: fixedAssets.count, canonicalCount: fixedAssets.count, executeSupported: false),
            MigrationModelDelta(modelName: "Inventory", legacyCount: inventoryRecords.count, canonicalCount: inventoryRecords.count, executeSupported: false),
            MigrationModelDelta(modelName: "Counterparty", legacyCount: 0, canonicalCount: counterparties.count, executeSupported: false),
            MigrationModelDelta(modelName: "DistributionRule", legacyCount: 0, canonicalCount: distributionRules.count, executeSupported: false),
            MigrationModelDelta(modelName: "AuditEvent", legacyCount: complianceLogs.count + transactionLogs.count, canonicalCount: auditEvents.count, executeSupported: false),
            MigrationModelDelta(modelName: "LegacyLedger", legacyCount: ledgerBooks.count + ledgerEntries.count, canonicalCount: 0, executeSupported: false),
            MigrationModelDelta(modelName: "UserRule", legacyCount: userRules.count, canonicalCount: userRules.count, executeSupported: false),
        ]

        let projectIds = Set(projects.map(\.id))
        let categoryIds = Set(categories.map(\.id))
        let accountIds = Set(accounts.map(\.id))
        let transactionIds = Set(transactions.map(\.id))
        let journalEntryIds = Set(journalEntries.map(\.id))
        let documentIds = Set(documentRecords.map(\.id))
        let evidenceIds = Set(evidenceRecords.map(\.evidenceId))
        let candidateIds = Set(postingCandidates.map(\.candidateId))
        let canonicalJournalIds = Set(canonicalJournalEntries.map(\.journalId))
        let counterpartyIds = Set(counterparties.map(\.counterpartyId))
        let canonicalAccountIds = Set(canonicalAccounts.map(\.accountId))

        var orphans: [MigrationOrphanRecord] = []

        for transaction in transactions {
            if !categoryIds.contains(transaction.categoryId) {
                orphans.append(.init(area: "legacy.transaction", identifier: transaction.id.uuidString, message: "missing category \(transaction.categoryId)"))
            }
            if let paymentAccountId = transaction.paymentAccountId, !accountIds.contains(paymentAccountId) {
                orphans.append(.init(area: "legacy.transaction", identifier: transaction.id.uuidString, message: "missing payment account \(paymentAccountId)"))
            }
            if let transferToAccountId = transaction.transferToAccountId, !accountIds.contains(transferToAccountId) {
                orphans.append(.init(area: "legacy.transaction", identifier: transaction.id.uuidString, message: "missing transfer account \(transferToAccountId)"))
            }
            for allocation in transaction.allocations where !projectIds.contains(allocation.projectId) {
                orphans.append(.init(area: "legacy.transaction", identifier: transaction.id.uuidString, message: "missing allocation project \(allocation.projectId.uuidString)"))
            }
            if let imagePath = transaction.receiptImagePath, !ReceiptImageStore.imageExists(fileName: imagePath) {
                orphans.append(.init(area: "legacy.transaction", identifier: transaction.id.uuidString, message: "missing receipt image \(imagePath)"))
            }
        }

        for recurringRule in recurring {
            if !categoryIds.contains(recurringRule.categoryId) {
                orphans.append(.init(area: "legacy.recurring", identifier: recurringRule.id.uuidString, message: "missing category \(recurringRule.categoryId)"))
            }
            if let imagePath = recurringRule.receiptImagePath, !ReceiptImageStore.imageExists(fileName: imagePath) {
                orphans.append(.init(area: "legacy.recurring", identifier: recurringRule.id.uuidString, message: "missing receipt image \(imagePath)"))
            }
        }

        for line in journalLines where !journalEntryIds.contains(line.entryId) {
            orphans.append(.init(area: "legacy.journalLine", identifier: line.id.uuidString, message: "missing journal entry \(line.entryId.uuidString)"))
        }

        for record in documentRecords {
            if let transactionId = record.transactionId, !transactionIds.contains(transactionId) {
                orphans.append(.init(area: "legacy.document", identifier: record.id.uuidString, message: "missing transaction \(transactionId.uuidString)"))
            }
            if !ReceiptImageStore.documentFileExists(fileName: record.storedFileName) {
                orphans.append(.init(area: "legacy.document", identifier: record.id.uuidString, message: "missing document file \(record.storedFileName)"))
            }
        }

        for log in complianceLogs {
            if let documentId = log.documentId, !documentIds.contains(documentId) {
                orphans.append(.init(area: "legacy.compliance", identifier: log.id.uuidString, message: "missing document \(documentId.uuidString)"))
            }
            if let transactionId = log.transactionId, !transactionIds.contains(transactionId) {
                orphans.append(.init(area: "legacy.compliance", identifier: log.id.uuidString, message: "missing transaction \(transactionId.uuidString)"))
            }
        }

        for log in transactionLogs where !transactionIds.contains(log.transactionId) {
            orphans.append(.init(area: "legacy.transactionLog", identifier: log.id.uuidString, message: "missing transaction \(log.transactionId.uuidString)"))
        }

        for evidence in evidenceRecords {
            let domain = EvidenceRecordEntityMapper.toDomain(evidence)
            if !ReceiptImageStore.documentFileExists(fileName: domain.originalFilePath) {
                orphans.append(.init(area: "canonical.evidence", identifier: domain.id.uuidString, message: "missing evidence file \(domain.originalFilePath)"))
            }
            if let linkedCounterpartyId = domain.linkedCounterpartyId, !counterpartyIds.contains(linkedCounterpartyId) {
                orphans.append(.init(area: "canonical.evidence", identifier: domain.id.uuidString, message: "missing counterparty \(linkedCounterpartyId.uuidString)"))
            }
            for projectId in domain.linkedProjectIds where !projectIds.contains(projectId) {
                orphans.append(.init(area: "canonical.evidence", identifier: domain.id.uuidString, message: "missing project \(projectId.uuidString)"))
            }
        }

        for candidate in postingCandidates {
            if let evidenceId = candidate.evidenceId, !evidenceIds.contains(evidenceId) {
                orphans.append(.init(area: "canonical.candidate", identifier: candidate.candidateId.uuidString, message: "missing evidence \(evidenceId.uuidString)"))
            }
            if let counterpartyId = candidate.counterpartyId, !counterpartyIds.contains(counterpartyId) {
                orphans.append(.init(area: "canonical.candidate", identifier: candidate.candidateId.uuidString, message: "missing counterparty \(counterpartyId.uuidString)"))
            }
        }

        for journal in canonicalJournalEntries {
            if let evidenceId = journal.sourceEvidenceId, !evidenceIds.contains(evidenceId) {
                orphans.append(.init(area: "canonical.journal", identifier: journal.journalId.uuidString, message: "missing evidence \(evidenceId.uuidString)"))
            }
            if let candidateId = journal.sourceCandidateId, !candidateIds.contains(candidateId) {
                orphans.append(.init(area: "canonical.journal", identifier: journal.journalId.uuidString, message: "missing candidate \(candidateId.uuidString)"))
            }
        }

        for line in canonicalJournalLines {
            if !canonicalJournalIds.contains(line.journalEntry?.journalId ?? UUID()) {
                orphans.append(.init(area: "canonical.journalLine", identifier: line.lineId.uuidString, message: "missing journal relationship"))
            }
            if !canonicalAccountIds.contains(line.accountId) {
                orphans.append(.init(area: "canonical.journalLine", identifier: line.lineId.uuidString, message: "missing account mapping"))
            }
        }

        let warnings = deltas.compactMap { delta -> String? in
            guard delta.executeSupported, delta.legacyCount > 0, delta.canonicalCount == 0 else {
                return nil
            }
            return "\(delta.modelName) canonical data is empty while legacy data exists"
        }

        return MigrationDryRunReport(
            generatedAt: Date(),
            deltas: deltas,
            orphanRecords: orphans,
            warnings: warnings
        )
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try modelContext.fetch(FetchDescriptor<T>())
    }
}
