import Foundation
import SwiftData
import os

/// レガシーデータのCanonicalモデルへの移行実行
///
/// PPTransaction → PostingCandidateEntity
/// PPJournalEntry/PPJournalLine → JournalEntryEntity/JournalLineEntity
/// PPDocumentRecord → EvidenceRecordEntity
///
/// 冪等性: memo / sourceRaw にレガシーIDを埋め込み、既存レコードとの重複を検出する。
@MainActor
struct LegacyDataMigrationExecutor {
    private let modelContext: ModelContext
    private static let logger = Logger(subsystem: "com.projectprofit", category: "Migration")

    private static let legacyMigrationSource = "legacy_migration"
    private static let legacyMemoPrefix = "legacy:"

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    struct MigrationResult: Sendable {
        let transactionsMigrated: Int
        let journalsMigrated: Int
        let documentsMigrated: Int
        let errors: [String]

        var totalMigrated: Int {
            transactionsMigrated + journalsMigrated + documentsMigrated
        }

        var hasErrors: Bool { !errors.isEmpty }
    }

    // MARK: - Public

    /// 全レガシーデータを移行（冪等）
    func execute(businessId: UUID) throws -> MigrationResult {
        var errors: [String] = []

        let txCount = migrateTransactions(businessId: businessId, errors: &errors)
        let journalCount = migrateJournals(businessId: businessId, errors: &errors)
        let docCount = migrateDocuments(businessId: businessId, errors: &errors)

        try modelContext.save()

        let result = MigrationResult(
            transactionsMigrated: txCount,
            journalsMigrated: journalCount,
            documentsMigrated: docCount,
            errors: errors
        )

        Self.logger.info(
            "Migration completed: tx=\(txCount), journal=\(journalCount), doc=\(docCount), errors=\(errors.count)"
        )
        return result
    }

    // MARK: - Transaction Migration

    /// PPTransaction → PostingCandidateEntity
    ///
    /// 重複検出: sourceRaw == "legacy_migration" かつ memo が "legacy:<uuid>" のレコードを既存と判定
    private func migrateTransactions(businessId: UUID, errors: inout [String]) -> Int {
        let transactions: [PPTransaction]
        do {
            transactions = try modelContext.fetch(FetchDescriptor<PPTransaction>())
        } catch {
            errors.append("取引の取得に失敗: \(error.localizedDescription)")
            return 0
        }

        let existingLegacyIds = fetchExistingLegacyCandidateIds()

        var migrated = 0
        for transaction in transactions where transaction.deletedAt == nil {
            if existingLegacyIds.contains(transaction.id) { continue }

            let proposedLine = PostingCandidateLine(
                debitAccountId: nil,
                creditAccountId: nil,
                amount: Decimal(transaction.amount),
                memo: transaction.memo
            )
            let proposedLinesJSON = CanonicalJSONCoder.encode([proposedLine], fallback: "[]")

            let candidate = PostingCandidateEntity(
                candidateId: UUID(),
                businessId: businessId,
                taxYear: Calendar.current.component(.year, from: transaction.date),
                candidateDate: transaction.date,
                counterpartyId: nil,
                proposedLinesJSON: proposedLinesJSON,
                confidenceScore: 1.0,
                statusRaw: CandidateStatus.approved.rawValue,
                sourceRaw: Self.legacyMigrationSource,
                memo: Self.legacyMemoPrefix + transaction.id.uuidString,
                createdAt: transaction.createdAt,
                updatedAt: transaction.updatedAt
            )
            modelContext.insert(candidate)
            migrated += 1
        }

        return migrated
    }

    // MARK: - Journal Migration

    /// PPJournalEntry/PPJournalLine → JournalEntryEntity/JournalLineEntity
    ///
    /// 重複検出: entryDescription が "legacy:<uuid>" で始まるレコードを既存と判定
    private func migrateJournals(businessId: UUID, errors: inout [String]) -> Int {
        let legacyEntries: [PPJournalEntry]
        let legacyLines: [PPJournalLine]
        do {
            legacyEntries = try modelContext.fetch(FetchDescriptor<PPJournalEntry>())
            legacyLines = try modelContext.fetch(FetchDescriptor<PPJournalLine>())
        } catch {
            errors.append("仕訳の取得に失敗: \(error.localizedDescription)")
            return 0
        }

        let existingLegacyIds = fetchExistingLegacyJournalIds()
        let linesByEntry = Dictionary(grouping: legacyLines) { $0.entryId }

        var migrated = 0
        for entry in legacyEntries {
            if existingLegacyIds.contains(entry.id) { continue }

            let entryTypeRaw = mapJournalEntryType(entry.entryType)
            let descriptionWithLegacyKey = Self.legacyMemoPrefix + entry.id.uuidString
                + (entry.memo.isEmpty ? "" : " " + entry.memo)

            let lines = linesByEntry[entry.id] ?? []
            let lineEntities = lines.enumerated().map { index, line in
                JournalLineEntity(
                    lineId: UUID(),
                    accountId: UUID(uuidString: line.accountId) ?? UUID(),
                    debitAmount: Decimal(line.debit),
                    creditAmount: Decimal(line.credit),
                    sortOrder: index
                )
            }

            let entryEntity = JournalEntryEntity(
                journalId: UUID(),
                businessId: businessId,
                taxYear: Calendar.current.component(.year, from: entry.date),
                journalDate: entry.date,
                voucherNo: "",
                entryTypeRaw: entryTypeRaw,
                entryDescription: descriptionWithLegacyKey,
                approvedAt: entry.isPosted ? entry.updatedAt : nil,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt,
                lines: lineEntities
            )
            modelContext.insert(entryEntity)

            for lineEntity in lineEntities {
                lineEntity.journalEntry = entryEntity
                modelContext.insert(lineEntity)
            }

            migrated += 1
        }

        return migrated
    }

    // MARK: - Document Migration

    /// PPDocumentRecord → EvidenceRecordEntity
    ///
    /// 重複検出: originalFilename が "legacy:<uuid>" で始まるレコードを既存と判定
    private func migrateDocuments(businessId: UUID, errors: inout [String]) -> Int {
        let documents: [PPDocumentRecord]
        do {
            documents = try modelContext.fetch(FetchDescriptor<PPDocumentRecord>())
        } catch {
            errors.append("書類の取得に失敗: \(error.localizedDescription)")
            return 0
        }

        let existingLegacyIds = fetchExistingLegacyEvidenceIds()

        var migrated = 0
        for doc in documents {
            if existingLegacyIds.contains(doc.id) { continue }

            let legalDocType = mapLegalDocumentType(doc.documentType)

            let entity = EvidenceRecordEntity(
                evidenceId: UUID(),
                businessId: businessId,
                taxYear: Calendar.current.component(.year, from: doc.issueDate),
                sourceTypeRaw: EvidenceSourceType.manualNoFile.rawValue,
                legalDocumentTypeRaw: legalDocType.rawValue,
                storageCategoryRaw: StorageCategory.paperScan.rawValue,
                receivedAt: doc.createdAt,
                issueDate: doc.issueDate,
                originalFilename: Self.legacyMemoPrefix + doc.id.uuidString,
                mimeType: doc.mimeType ?? "",
                fileHash: doc.contentHash ?? "",
                originalFilePath: doc.storedFileName,
                searchTokensJSON: "[]",
                linkedProjectIdsJSON: "[]",
                complianceStatusRaw: ComplianceStatus.pendingReview.rawValue,
                createdAt: doc.createdAt,
                updatedAt: doc.updatedAt
            )
            modelContext.insert(entity)
            migrated += 1
        }

        return migrated
    }

    // MARK: - Deduplication Helpers

    /// PostingCandidateEntity の memo から既にmigrated済みのレガシートランザクションIDを抽出
    private func fetchExistingLegacyCandidateIds() -> Set<UUID> {
        do {
            let candidates = try modelContext.fetch(FetchDescriptor<PostingCandidateEntity>())
            let ids = candidates
                .filter { $0.sourceRaw == Self.legacyMigrationSource }
                .compactMap { extractLegacyId(from: $0.memo) }
            return Set(ids)
        } catch {
            return []
        }
    }

    /// JournalEntryEntity の entryDescription から既にmigrated済みのレガシー仕訳IDを抽出
    private func fetchExistingLegacyJournalIds() -> Set<UUID> {
        do {
            let entries = try modelContext.fetch(FetchDescriptor<JournalEntryEntity>())
            let ids = entries.compactMap { extractLegacyId(from: $0.entryDescription) }
            return Set(ids)
        } catch {
            return []
        }
    }

    /// EvidenceRecordEntity の originalFilename から既にmigrated済みのレガシー書類IDを抽出
    private func fetchExistingLegacyEvidenceIds() -> Set<UUID> {
        do {
            let evidences = try modelContext.fetch(FetchDescriptor<EvidenceRecordEntity>())
            let ids = evidences.compactMap { extractLegacyId(from: $0.originalFilename) }
            return Set(ids)
        } catch {
            return []
        }
    }

    /// "legacy:<uuid>..." 形式の文字列からUUIDを抽出
    private func extractLegacyId(from value: String?) -> UUID? {
        guard let value, value.hasPrefix(Self.legacyMemoPrefix) else { return nil }
        let uuidPart = String(value.dropFirst(Self.legacyMemoPrefix.count).prefix(36))
        return UUID(uuidString: uuidPart)
    }

    // MARK: - Type Mapping

    /// レガシー JournalEntryType → Canonical entryTypeRaw
    private func mapJournalEntryType(_ legacy: JournalEntryType) -> String {
        switch legacy {
        case .auto:
            return CanonicalJournalEntryType.normal.rawValue
        case .manual:
            return CanonicalJournalEntryType.normal.rawValue
        case .opening:
            return CanonicalJournalEntryType.opening.rawValue
        case .closing:
            return CanonicalJournalEntryType.closing.rawValue
        }
    }

    /// レガシー LegalDocumentType → Canonical CanonicalLegalDocumentType
    private func mapLegalDocumentType(_ legacy: LegalDocumentType) -> CanonicalLegalDocumentType {
        switch legacy {
        case .receipt:
            return .receipt
        case .invoice:
            return .invoice
        case .quotation:
            return .estimate
        case .contract:
            return .contract
        case .deliveryNote:
            return .deliveryNote
        case .checkStub, .passbook, .promissoryNote, .shippingSlip, .financialStatement, .other:
            return .other
        }
    }
}
