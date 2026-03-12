import CryptoKit
import Foundation
import SwiftData

@MainActor
struct CanonicalPostingEngine {
    private let modelContext: ModelContext?
    private let postingCandidateRepository: any PostingCandidateRepository
    private let journalEntryRepository: any CanonicalJournalEntryRepository
    private let chartOfAccountsRepository: any ChartOfAccountsRepository
    private let auditRepository: (any AuditRepository)?
    private let journalSearchIndex: LocalJournalSearchIndex?

    init(
        modelContext: ModelContext? = nil,
        postingCandidateRepository: any PostingCandidateRepository,
        journalEntryRepository: any CanonicalJournalEntryRepository,
        chartOfAccountsRepository: any ChartOfAccountsRepository,
        auditRepository: (any AuditRepository)? = nil,
        journalSearchIndex: LocalJournalSearchIndex? = nil
    ) {
        self.modelContext = modelContext
        self.postingCandidateRepository = postingCandidateRepository
        self.journalEntryRepository = journalEntryRepository
        self.chartOfAccountsRepository = chartOfAccountsRepository
        self.auditRepository = auditRepository
        self.journalSearchIndex = journalSearchIndex
    }

    init(modelContext: ModelContext) {
        self.init(
            modelContext: modelContext,
            postingCandidateRepository: SwiftDataPostingCandidateRepository(modelContext: modelContext),
            journalEntryRepository: SwiftDataCanonicalJournalEntryRepository(modelContext: modelContext),
            chartOfAccountsRepository: SwiftDataChartOfAccountsRepository(modelContext: modelContext),
            auditRepository: SwiftDataAuditRepository(modelContext: modelContext),
            journalSearchIndex: LocalJournalSearchIndex(modelContext: modelContext)
        )
    }

    func persistApprovedCandidateAsync(
        _ candidate: PostingCandidate,
        entryType: CanonicalJournalEntryType = .normal,
        description: String? = nil,
        approvedAt: Date = Date(),
        actor: String = "user"
    ) async throws -> CanonicalJournalEntry {
        guard !candidate.proposedLines.isEmpty else {
            throw PostingWorkflowUseCaseError.candidateHasNoLines(candidate.id)
        }

        let approvedCandidate = candidate.updated(status: .approved)
        let journalId = UUID()
        let voucherMonth = Calendar.current.component(.month, from: candidate.candidateDate)
        let voucherNumber = try await journalEntryRepository.nextVoucherNumber(
            businessId: candidate.businessId,
            taxYear: candidate.taxYear,
            month: voucherMonth
        )
        let journalLines = try await makeJournalLines(from: approvedCandidate, journalId: journalId)
        let entry = CanonicalJournalEntry(
            id: journalId,
            businessId: candidate.businessId,
            taxYear: candidate.taxYear,
            journalDate: candidate.candidateDate,
            voucherNo: voucherNumber.value,
            sourceEvidenceId: candidate.evidenceId,
            sourceCandidateId: candidate.id,
            entryType: entryType,
            description: description ?? approvedCandidate.memo ?? "",
            lines: journalLines,
            approvedAt: approvedAt,
            createdAt: approvedAt,
            updatedAt: approvedAt
        )

        guard entry.isBalanced else {
            throw PostingWorkflowUseCaseError.journalNotBalanced(candidate.id)
        }

        try await journalEntryRepository.save(entry)
        try await postingCandidateRepository.save(approvedCandidate)
        try? rebuildJournalSearchIndex(businessId: entry.businessId, taxYear: entry.taxYear)
        await saveApprovalAuditEvents(
            originalCandidate: candidate,
            approvedCandidate: approvedCandidate,
            journal: entry,
            reason: description,
            actor: actor
        )
        return entry
    }

    func persistApprovedCandidateAsync(
        _ candidate: PostingCandidate,
        journalId: UUID,
        entryType: CanonicalJournalEntryType = .normal,
        description: String? = nil,
        approvedAt: Date = Date(),
        actor: String = "user"
    ) async throws -> CanonicalJournalEntry {
        guard !candidate.proposedLines.isEmpty else {
            throw PostingWorkflowUseCaseError.candidateHasNoLines(candidate.id)
        }

        let approvedCandidate = candidate.updated(status: .approved)
        let existingJournal = try await journalEntryRepository.findById(journalId)
        let voucherNo: String
        if let existingJournal {
            voucherNo = existingJournal.voucherNo
        } else {
            let voucherMonth = Calendar.current.component(.month, from: candidate.candidateDate)
            voucherNo = try await journalEntryRepository.nextVoucherNumber(
                businessId: candidate.businessId,
                taxYear: candidate.taxYear,
                month: voucherMonth
            ).value
        }

        let journalLines = try await makeJournalLines(from: approvedCandidate, journalId: journalId)
        let entry = CanonicalJournalEntry(
            id: journalId,
            businessId: candidate.businessId,
            taxYear: candidate.taxYear,
            journalDate: candidate.candidateDate,
            voucherNo: voucherNo,
            sourceEvidenceId: candidate.evidenceId,
            sourceCandidateId: candidate.id,
            entryType: entryType,
            description: description ?? approvedCandidate.memo ?? "",
            lines: journalLines,
            approvedAt: approvedAt,
            createdAt: existingJournal?.createdAt ?? approvedAt,
            updatedAt: approvedAt
        )

        guard entry.isBalanced else {
            throw PostingWorkflowUseCaseError.journalNotBalanced(candidate.id)
        }

        try await postingCandidateRepository.save(approvedCandidate)
        do {
            try await journalEntryRepository.save(entry)
            try? rebuildJournalSearchIndex(businessId: entry.businessId, taxYear: entry.taxYear)
            await saveApprovalAuditEvents(
                originalCandidate: candidate,
                approvedCandidate: approvedCandidate,
                journal: entry,
                reason: description,
                actor: actor
            )
            return entry
        } catch {
            try? await postingCandidateRepository.save(candidate)
            throw error
        }
    }

    func persistApprovedCandidateSync(
        _ candidate: PostingCandidate,
        journalId: UUID,
        entryType: CanonicalJournalEntryType = .normal,
        description: String? = nil,
        approvedAt: Date = Date(),
        actor: String = "user",
        saveChanges: Bool = false
    ) throws -> CanonicalJournalEntry {
        guard let modelContext else {
            throw AppError.invalidInput(message: "同期 posting engine の ModelContext が未設定です")
        }
        guard !candidate.proposedLines.isEmpty else {
            throw PostingWorkflowUseCaseError.candidateHasNoLines(candidate.id)
        }

        let approvedCandidate = candidate.updated(status: .approved)
        let existingJournal = try existingJournal(id: journalId, modelContext: modelContext)
        let voucherNo: String
        if let existingJournal {
            voucherNo = existingJournal.voucherNo
        } else {
            voucherNo = try nextVoucherNumber(
                businessId: candidate.businessId,
                taxYear: candidate.taxYear,
                month: Calendar.current.component(.month, from: candidate.candidateDate),
                modelContext: modelContext
            ).value
        }

        let journalLines = try makeJournalLinesSync(
            from: approvedCandidate,
            journalId: journalId,
            modelContext: modelContext
        )
        let entry = CanonicalJournalEntry(
            id: journalId,
            businessId: candidate.businessId,
            taxYear: candidate.taxYear,
            journalDate: candidate.candidateDate,
            voucherNo: voucherNo,
            sourceEvidenceId: candidate.evidenceId,
            sourceCandidateId: candidate.id,
            entryType: entryType,
            description: description ?? approvedCandidate.memo ?? "",
            lines: journalLines,
            approvedAt: approvedAt,
            createdAt: existingJournal?.createdAt ?? approvedAt,
            updatedAt: approvedAt
        )

        guard entry.isBalanced else {
            throw PostingWorkflowUseCaseError.journalNotBalanced(candidate.id)
        }

        upsertCandidateEntity(approvedCandidate, modelContext: modelContext)
        upsertJournalEntity(entry, modelContext: modelContext)
        appendApprovalAuditEvents(
            originalCandidate: candidate,
            approvedCandidate: approvedCandidate,
            journal: entry,
            reason: description,
            actor: actor,
            modelContext: modelContext
        )

        if saveChanges {
            try modelContext.save()
        }
        try? rebuildJournalSearchIndex(businessId: entry.businessId, taxYear: entry.taxYear)
        return entry
    }

    private func makeJournalLines(from candidate: PostingCandidate, journalId: UUID) async throws -> [JournalLine] {
        var journalLines: [JournalLine] = []
        var sortOrder = 0

        for line in candidate.proposedLines {
            guard line.amount > 0 else {
                throw PostingWorkflowUseCaseError.invalidAmount(line.id)
            }
            guard line.debitAccountId != nil || line.creditAccountId != nil else {
                throw PostingWorkflowUseCaseError.missingAccount(line.id)
            }

            if let debitAccountId = line.debitAccountId {
                let legalReportLineId = try await resolvedLegalReportLineId(
                    accountId: debitAccountId,
                    fallback: line.legalReportLineId
                )
                journalLines.append(
                    JournalLine(
                        journalId: journalId,
                        accountId: debitAccountId,
                        debitAmount: line.amount,
                        creditAmount: 0,
                        taxCodeId: line.taxCodeId,
                        legalReportLineId: legalReportLineId,
                        counterpartyId: candidate.counterpartyId,
                        projectAllocationId: line.projectAllocationId,
                        genreTagIds: [],
                        evidenceReferenceId: line.evidenceLineReferenceId ?? candidate.evidenceId,
                        sortOrder: sortOrder,
                        withholdingTaxCodeId: line.withholdingTaxCodeId,
                        withholdingTaxAmount: line.withholdingTaxAmount,
                        withholdingTaxBaseAmount: line.withholdingTaxBaseAmount
                    )
                )
                sortOrder += 1
            }

            if let creditAccountId = line.creditAccountId {
                let legalReportLineId = try await resolvedLegalReportLineId(
                    accountId: creditAccountId,
                    fallback: line.legalReportLineId
                )
                journalLines.append(
                    JournalLine(
                        journalId: journalId,
                        accountId: creditAccountId,
                        debitAmount: 0,
                        creditAmount: line.amount,
                        taxCodeId: line.taxCodeId,
                        legalReportLineId: legalReportLineId,
                        counterpartyId: candidate.counterpartyId,
                        projectAllocationId: line.projectAllocationId,
                        genreTagIds: [],
                        evidenceReferenceId: line.evidenceLineReferenceId ?? candidate.evidenceId,
                        sortOrder: sortOrder
                    )
                )
                sortOrder += 1
            }
        }

        return journalLines
    }

    private func makeJournalLinesSync(
        from candidate: PostingCandidate,
        journalId: UUID,
        modelContext: ModelContext
    ) throws -> [JournalLine] {
        var journalLines: [JournalLine] = []
        var sortOrder = 0

        for line in candidate.proposedLines {
            guard line.amount > 0 else {
                throw PostingWorkflowUseCaseError.invalidAmount(line.id)
            }
            guard line.debitAccountId != nil || line.creditAccountId != nil else {
                throw PostingWorkflowUseCaseError.missingAccount(line.id)
            }

            if let debitAccountId = line.debitAccountId {
                let legalReportLineId = try resolvedLegalReportLineIdSync(
                    accountId: debitAccountId,
                    fallback: line.legalReportLineId,
                    modelContext: modelContext
                )
                journalLines.append(
                    JournalLine(
                        journalId: journalId,
                        accountId: debitAccountId,
                        debitAmount: line.amount,
                        creditAmount: 0,
                        taxCodeId: line.taxCodeId,
                        legalReportLineId: legalReportLineId,
                        counterpartyId: candidate.counterpartyId,
                        projectAllocationId: line.projectAllocationId,
                        genreTagIds: [],
                        evidenceReferenceId: line.evidenceLineReferenceId ?? candidate.evidenceId,
                        sortOrder: sortOrder,
                        withholdingTaxCodeId: line.withholdingTaxCodeId,
                        withholdingTaxAmount: line.withholdingTaxAmount,
                        withholdingTaxBaseAmount: line.withholdingTaxBaseAmount
                    )
                )
                sortOrder += 1
            }

            if let creditAccountId = line.creditAccountId {
                let legalReportLineId = try resolvedLegalReportLineIdSync(
                    accountId: creditAccountId,
                    fallback: line.legalReportLineId,
                    modelContext: modelContext
                )
                journalLines.append(
                    JournalLine(
                        journalId: journalId,
                        accountId: creditAccountId,
                        debitAmount: 0,
                        creditAmount: line.amount,
                        taxCodeId: line.taxCodeId,
                        legalReportLineId: legalReportLineId,
                        counterpartyId: candidate.counterpartyId,
                        projectAllocationId: line.projectAllocationId,
                        genreTagIds: [],
                        evidenceReferenceId: line.evidenceLineReferenceId ?? candidate.evidenceId,
                        sortOrder: sortOrder
                    )
                )
                sortOrder += 1
            }
        }

        return journalLines
    }

    private func resolvedLegalReportLineId(
        accountId: UUID,
        fallback: String?
    ) async throws -> String {
        guard let account = try await chartOfAccountsRepository.findById(accountId) else {
            throw PostingWorkflowUseCaseError.accountNotFound(accountId)
        }

        if let accountLineId = account.defaultLegalReportLineId,
           LegalReportLine(rawValue: accountLineId) != nil {
            return accountLineId
        }

        if let fallback, LegalReportLine(rawValue: fallback) != nil {
            return fallback
        }

        throw PostingWorkflowUseCaseError.missingLegalReportLine(accountId)
    }

    private func resolvedLegalReportLineIdSync(
        accountId: UUID,
        fallback: String?,
        modelContext: ModelContext
    ) throws -> String {
        let descriptor = FetchDescriptor<CanonicalAccountEntity>(
            predicate: #Predicate { $0.accountId == accountId }
        )
        guard let account = try modelContext.fetch(descriptor).first.map(CanonicalAccountEntityMapper.toDomain) else {
            throw PostingWorkflowUseCaseError.accountNotFound(accountId)
        }

        if let accountLineId = account.defaultLegalReportLineId,
           LegalReportLine(rawValue: accountLineId) != nil {
            return accountLineId
        }

        if let fallback, LegalReportLine(rawValue: fallback) != nil {
            return fallback
        }

        throw PostingWorkflowUseCaseError.missingLegalReportLine(accountId)
    }

    private func existingJournal(
        id: UUID,
        modelContext: ModelContext
    ) throws -> CanonicalJournalEntry? {
        let descriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate { $0.journalId == id }
        )
        return try modelContext.fetch(descriptor).first.map(CanonicalJournalEntryEntityMapper.toDomain)
    }

    private func upsertCandidateEntity(_ candidate: PostingCandidate, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<PostingCandidateEntity>(
            predicate: #Predicate { $0.candidateId == candidate.id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            PostingCandidateEntityMapper.update(existing, from: candidate)
        } else {
            modelContext.insert(PostingCandidateEntityMapper.toEntity(candidate))
        }
    }

    private func upsertJournalEntity(_ entry: CanonicalJournalEntry, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate { $0.journalId == entry.id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            let previousLines = existing.lines
            CanonicalJournalEntryEntityMapper.update(existing, from: entry)
            existing.lines = []
            previousLines.forEach(modelContext.delete)
            existing.lines = CanonicalJournalEntryEntityMapper.makeLineEntities(
                from: entry.lines,
                journalEntry: existing
            )
        } else {
            modelContext.insert(CanonicalJournalEntryEntityMapper.toEntity(entry))
        }
    }

    private func appendApprovalAuditEvents(
        originalCandidate: PostingCandidate,
        approvedCandidate: PostingCandidate,
        journal: CanonicalJournalEntry,
        reason: String?,
        actor: String,
        modelContext: ModelContext
    ) {
        modelContext.insert(
            AuditEventEntityMapper.toEntity(
                AuditEvent(
                    businessId: approvedCandidate.businessId,
                    eventType: .candidateApproved,
                    aggregateType: "PostingCandidate",
                    aggregateId: approvedCandidate.id,
                    beforeStateHash: stateHash(originalCandidate),
                    afterStateHash: stateHash(approvedCandidate),
                    actor: actor,
                    reason: reason ?? approvedCandidate.memo,
                    relatedEvidenceId: approvedCandidate.evidenceId,
                    relatedJournalId: journal.id
                )
            )
        )
        modelContext.insert(
            AuditEventEntityMapper.toEntity(
                AuditEvent(
                    businessId: journal.businessId,
                    eventType: .journalApproved,
                    aggregateType: "CanonicalJournalEntry",
                    aggregateId: journal.id,
                    beforeStateHash: nil,
                    afterStateHash: stateHash(journal),
                    actor: actor,
                    reason: reason ?? journal.description,
                    relatedEvidenceId: journal.sourceEvidenceId,
                    relatedJournalId: journal.id
                )
            )
        )
    }

    private func saveApprovalAuditEvents(
        originalCandidate: PostingCandidate,
        approvedCandidate: PostingCandidate,
        journal: CanonicalJournalEntry,
        reason: String?,
        actor: String
    ) async {
        await saveAuditEvent(
            AuditEvent(
                businessId: approvedCandidate.businessId,
                eventType: .candidateApproved,
                aggregateType: "PostingCandidate",
                aggregateId: approvedCandidate.id,
                beforeStateHash: stateHash(originalCandidate),
                afterStateHash: stateHash(approvedCandidate),
                actor: actor,
                reason: reason ?? approvedCandidate.memo,
                relatedEvidenceId: approvedCandidate.evidenceId,
                relatedJournalId: journal.id
            )
        )
        await saveAuditEvent(
            AuditEvent(
                businessId: journal.businessId,
                eventType: .journalApproved,
                aggregateType: "CanonicalJournalEntry",
                aggregateId: journal.id,
                beforeStateHash: nil,
                afterStateHash: stateHash(journal),
                actor: actor,
                reason: reason ?? journal.description,
                relatedEvidenceId: journal.sourceEvidenceId,
                relatedJournalId: journal.id
            )
        )
    }

    private func saveAuditEvent(_ event: AuditEvent) async {
        guard let auditRepository else {
            return
        }
        do {
            try await auditRepository.save(event)
        } catch {
            assertionFailure("Audit save failed: \(error.localizedDescription)")
        }
    }

    private func rebuildJournalSearchIndex(businessId: UUID, taxYear: Int) throws {
        try journalSearchIndex?.rebuild(businessId: businessId, taxYear: taxYear)
    }

    private func nextVoucherNumber(
        businessId: UUID,
        taxYear: Int,
        month: Int,
        modelContext: ModelContext
    ) throws -> VoucherNumber {
        let descriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate {
                $0.businessId == businessId
                    && $0.taxYear == taxYear
            }
        )
        let entries = try modelContext.fetch(descriptor)
        let prefix = String(format: "%04d-%03d-", taxYear, month)
        let maxSequence = entries.reduce(0) { currentMax, entry in
            guard entry.voucherNo.hasPrefix(prefix),
                  let sequence = Int(entry.voucherNo.replacingOccurrences(of: prefix, with: "")) else {
                return currentMax
            }
            return max(currentMax, sequence)
        }
        return VoucherNumber(taxYear: taxYear, month: month, sequence: maxSequence + 1)
    }

    private func stateHash<T: Encodable>(_ value: T) -> String? {
        do {
            let data = try JSONEncoder().encode(value)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }
}
