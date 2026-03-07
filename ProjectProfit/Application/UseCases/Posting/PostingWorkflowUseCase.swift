import CryptoKit
import Foundation
import SwiftData

enum PostingWorkflowUseCaseError: LocalizedError {
    case candidateNotFound(UUID)
    case candidateHasNoLines(UUID)
    case missingAccount(UUID)
    case invalidAmount(UUID)
    case journalNotBalanced(UUID)
    case journalNotFound(UUID)
    case journalAlreadyCancelled(UUID)
    case journalNotCancelled(UUID)
    case journalNotApproved(UUID)
    case sourceCandidateNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .candidateNotFound:
            return "仕訳候補が見つかりません"
        case .candidateHasNoLines:
            return "仕訳候補に明細がありません"
        case .missingAccount:
            return "仕訳候補に勘定科目が設定されていません"
        case .invalidAmount:
            return "仕訳候補の金額が不正です"
        case .journalNotBalanced:
            return "仕訳候補から生成した仕訳が借貸不一致です"
        case .journalNotFound:
            return "仕訳が見つかりません"
        case .journalAlreadyCancelled:
            return "この仕訳は既に取消済みです"
        case .journalNotCancelled:
            return "取消済みの仕訳だけ再レビューへ戻せます"
        case .journalNotApproved:
            return "未確定の仕訳は取消できません"
        case .sourceCandidateNotFound:
            return "再レビュー元の仕訳候補が見つかりません"
        }
    }
}

@MainActor
struct PostingWorkflowUseCase {
    private let postingCandidateRepository: any PostingCandidateRepository
    private let journalEntryRepository: any CanonicalJournalEntryRepository
    private let auditRepository: (any AuditRepository)?
    private let journalSearchIndex: LocalJournalSearchIndex?

    init(
        postingCandidateRepository: any PostingCandidateRepository,
        journalEntryRepository: any CanonicalJournalEntryRepository,
        auditRepository: (any AuditRepository)? = nil,
        journalSearchIndex: LocalJournalSearchIndex? = nil
    ) {
        self.postingCandidateRepository = postingCandidateRepository
        self.journalEntryRepository = journalEntryRepository
        self.auditRepository = auditRepository
        self.journalSearchIndex = journalSearchIndex
    }

    init(modelContext: ModelContext) {
        self.init(
            postingCandidateRepository: SwiftDataPostingCandidateRepository(modelContext: modelContext),
            journalEntryRepository: SwiftDataCanonicalJournalEntryRepository(modelContext: modelContext),
            auditRepository: SwiftDataAuditRepository(modelContext: modelContext),
            journalSearchIndex: LocalJournalSearchIndex(modelContext: modelContext)
        )
    }

    func candidate(_ id: UUID) async throws -> PostingCandidate? {
        try await postingCandidateRepository.findById(id)
    }

    func candidates(businessId: UUID, status: CandidateStatus) async throws -> [PostingCandidate] {
        try await postingCandidateRepository.findByStatus(businessId: businessId, status: status)
    }

    func pendingCandidates(businessId: UUID) async throws -> [PostingCandidate] {
        let drafts = try await postingCandidateRepository.findByStatus(businessId: businessId, status: .draft)
        let reviewRequired = try await postingCandidateRepository.findByStatus(businessId: businessId, status: .needsReview)
        return (drafts + reviewRequired)
            .sorted {
                if $0.candidateDate == $1.candidateDate {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.candidateDate > $1.candidateDate
            }
    }

    func candidates(evidenceId: UUID) async throws -> [PostingCandidate] {
        try await postingCandidateRepository.findByEvidence(evidenceId: evidenceId)
    }

    func journal(_ id: UUID) async throws -> CanonicalJournalEntry? {
        try await journalEntryRepository.findById(id)
    }

    func journals(businessId: UUID, taxYear: Int) async throws -> [CanonicalJournalEntry] {
        try await journalEntryRepository.findByBusinessAndYear(businessId: businessId, taxYear: taxYear)
    }

    func journals(evidenceId: UUID) async throws -> [CanonicalJournalEntry] {
        try await journalEntryRepository.findByEvidence(evidenceId: evidenceId)
    }

    func saveCandidate(_ candidate: PostingCandidate) async throws {
        try await postingCandidateRepository.save(candidate)
    }

    func deleteCandidate(_ id: UUID) async throws {
        try await postingCandidateRepository.delete(id)
    }

    func approveCandidate(
        candidateId: UUID,
        entryType: CanonicalJournalEntryType = .normal,
        description: String? = nil,
        approvedAt: Date = Date()
    ) async throws -> CanonicalJournalEntry {
        guard let candidate = try await postingCandidateRepository.findById(candidateId) else {
            throw PostingWorkflowUseCaseError.candidateNotFound(candidateId)
        }
        guard !candidate.proposedLines.isEmpty else {
            throw PostingWorkflowUseCaseError.candidateHasNoLines(candidateId)
        }
        let approvedCandidate = candidate.updated(status: .approved)

        let voucherMonth = Calendar.current.component(.month, from: candidate.candidateDate)
        let voucherNumber = try await journalEntryRepository.nextVoucherNumber(
            businessId: candidate.businessId,
            taxYear: candidate.taxYear,
            month: voucherMonth
        )
        let journalId = UUID()
        let journalLines = try makeJournalLines(from: approvedCandidate, journalId: journalId)
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
            reason: description
        )
        return entry
    }

    func syncApprovedCandidate(
        _ candidate: PostingCandidate,
        journalId: UUID,
        entryType: CanonicalJournalEntryType = .normal,
        description: String? = nil,
        approvedAt: Date = Date()
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

        let journalLines = try makeJournalLines(from: approvedCandidate, journalId: journalId)
        let entry = CanonicalJournalEntry(
            id: journalId,
            businessId: candidate.businessId,
            taxYear: candidate.taxYear,
            journalDate: candidate.candidateDate,
            voucherNo: voucherNo,
            sourceEvidenceId: candidate.evidenceId,
            sourceCandidateId: candidate.id,
            entryType: entryType,
            description: description ?? candidate.memo ?? "",
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
                reason: description
            )
            return entry
        } catch {
            try? await postingCandidateRepository.save(candidate)
            throw error
        }
    }

    func rejectCandidate(_ id: UUID) async throws -> PostingCandidate {
        guard let candidate = try await postingCandidateRepository.findById(id) else {
            throw PostingWorkflowUseCaseError.candidateNotFound(id)
        }
        let rejected = candidate.updated(status: .rejected)
        try await postingCandidateRepository.save(rejected)
        await saveAuditEvent(
            AuditEvent(
                businessId: rejected.businessId,
                eventType: .candidateRejected,
                aggregateType: "PostingCandidate",
                aggregateId: rejected.id,
                beforeStateHash: stateHash(candidate),
                afterStateHash: stateHash(rejected),
                actor: "user",
                reason: rejected.memo,
                relatedEvidenceId: rejected.evidenceId,
                relatedJournalId: nil
            )
        )
        return rejected
    }

    func cancelJournal(
        journalId: UUID,
        reason: String? = nil,
        cancelledAt: Date = Date()
    ) async throws -> CanonicalJournalEntry {
        let journal = try await validatedJournalForCancellation(journalId)
        let lockedJournal = journal.updated(lockedAt: cancelledAt)
        let reversal = try await makeReversalJournal(
            from: journal,
            reason: reason,
            cancelledAt: cancelledAt
        )
        try await journalEntryRepository.save(lockedJournal)
        do {
            try await journalEntryRepository.save(reversal)
            try? rebuildJournalSearchIndex(businessId: journal.businessId, taxYear: journal.taxYear)
            await saveAuditEvent(
                AuditEvent(
                    businessId: journal.businessId,
                    eventType: .journalCancelled,
                    aggregateType: "CanonicalJournalEntry",
                    aggregateId: journal.id,
                    beforeStateHash: stateHash(journal),
                    afterStateHash: stateHash(lockedJournal),
                    actor: "user",
                    reason: reason ?? "reversal",
                    relatedEvidenceId: journal.sourceEvidenceId,
                    relatedJournalId: reversal.id
                )
            )
            return reversal
        } catch {
            try? await journalEntryRepository.save(journal)
            throw error
        }
    }

    func cancelAndReopenJournal(
        journalId: UUID,
        reason: String? = nil,
        cancelledAt: Date = Date()
    ) async throws -> (reversal: CanonicalJournalEntry, reopened: PostingCandidate) {
        let journal = try await validatedJournalForCancellation(journalId)
        guard let sourceCandidateId = journal.sourceCandidateId,
              let sourceCandidate = try await postingCandidateRepository.findById(sourceCandidateId)
        else {
            throw PostingWorkflowUseCaseError.sourceCandidateNotFound(journalId)
        }

        let lockedJournal = journal.updated(lockedAt: cancelledAt)
        let reversal = try await makeReversalJournal(
            from: journal,
            reason: reason,
            cancelledAt: cancelledAt
        )
        let reopened = makeReopenedCandidate(
            from: sourceCandidate,
            reason: reason,
            reopenedAt: cancelledAt
        )

        try await journalEntryRepository.save(lockedJournal)
        do {
            try await journalEntryRepository.save(reversal)
            do {
                try await postingCandidateRepository.save(reopened)
            } catch {
                try? await journalEntryRepository.delete(reversal.id)
                try? await journalEntryRepository.save(journal)
                try? rebuildJournalSearchIndex(businessId: journal.businessId, taxYear: journal.taxYear)
                throw error
            }
            try? rebuildJournalSearchIndex(businessId: journal.businessId, taxYear: journal.taxYear)
            await saveAuditEvent(
                AuditEvent(
                    businessId: journal.businessId,
                    eventType: .journalCancelled,
                    aggregateType: "CanonicalJournalEntry",
                    aggregateId: journal.id,
                    beforeStateHash: stateHash(journal),
                    afterStateHash: stateHash(lockedJournal),
                    actor: "user",
                    reason: normalizedReason(reason, fallback: "reversal"),
                    relatedEvidenceId: journal.sourceEvidenceId,
                    relatedJournalId: reversal.id
                )
            )
            await saveAuditEvent(
                AuditEvent(
                    businessId: reopened.businessId,
                    eventType: .candidateCreated,
                    aggregateType: "PostingCandidate",
                    aggregateId: reopened.id,
                    beforeStateHash: nil,
                    afterStateHash: stateHash(reopened),
                    actor: "user",
                    reason: normalizedReason(reason, fallback: "reopen"),
                    relatedEvidenceId: reopened.evidenceId,
                    relatedJournalId: journal.id
                )
            )
            return (reversal, reopened)
        } catch {
            try? await journalEntryRepository.save(journal)
            throw error
        }
    }

    func reopenCandidate(
        fromJournalId journalId: UUID,
        reason: String? = nil,
        reopenedAt: Date = Date()
    ) async throws -> PostingCandidate {
        guard let journal = try await journalEntryRepository.findById(journalId) else {
            throw PostingWorkflowUseCaseError.journalNotFound(journalId)
        }
        guard journal.lockedAt != nil else {
            throw PostingWorkflowUseCaseError.journalNotCancelled(journalId)
        }
        guard let sourceCandidateId = journal.sourceCandidateId,
              let sourceCandidate = try await postingCandidateRepository.findById(sourceCandidateId)
        else {
            throw PostingWorkflowUseCaseError.sourceCandidateNotFound(journalId)
        }

        let reopened = makeReopenedCandidate(
            from: sourceCandidate,
            reason: reason,
            reopenedAt: reopenedAt
        )
        try await postingCandidateRepository.save(reopened)
        await saveAuditEvent(
            AuditEvent(
                businessId: reopened.businessId,
                eventType: .candidateCreated,
                aggregateType: "PostingCandidate",
                aggregateId: reopened.id,
                beforeStateHash: nil,
                afterStateHash: stateHash(reopened),
                actor: "user",
                reason: normalizedReason(reason, fallback: "reopen"),
                relatedEvidenceId: reopened.evidenceId,
                relatedJournalId: journal.id
            )
        )
        return reopened
    }

    private func rebuildJournalSearchIndex(businessId: UUID, taxYear: Int) throws {
        try journalSearchIndex?.rebuild(businessId: businessId, taxYear: taxYear)
    }

    private func validatedJournalForCancellation(_ journalId: UUID) async throws -> CanonicalJournalEntry {
        guard let journal = try await journalEntryRepository.findById(journalId) else {
            throw PostingWorkflowUseCaseError.journalNotFound(journalId)
        }
        guard journal.approvedAt != nil else {
            throw PostingWorkflowUseCaseError.journalNotApproved(journalId)
        }
        guard journal.lockedAt == nil else {
            throw PostingWorkflowUseCaseError.journalAlreadyCancelled(journalId)
        }
        return journal
    }

    private func makeReversalJournal(
        from journal: CanonicalJournalEntry,
        reason: String?,
        cancelledAt: Date
    ) async throws -> CanonicalJournalEntry {
        let voucherMonth = Calendar.current.component(.month, from: journal.journalDate)
        let reversalVoucher = try await journalEntryRepository.nextVoucherNumber(
            businessId: journal.businessId,
            taxYear: journal.taxYear,
            month: voucherMonth
        )
        let reversalId = UUID()
        let reversalLines = journal.lines.map { line in
            JournalLine(
                id: UUID(),
                journalId: reversalId,
                accountId: line.accountId,
                debitAmount: line.creditAmount,
                creditAmount: line.debitAmount,
                taxCodeId: line.taxCodeId,
                legalReportLineId: line.legalReportLineId,
                counterpartyId: line.counterpartyId,
                projectAllocationId: line.projectAllocationId,
                genreTagIds: line.genreTagIds,
                evidenceReferenceId: line.evidenceReferenceId,
                sortOrder: line.sortOrder
            )
        }
        let reversal = CanonicalJournalEntry(
            id: reversalId,
            businessId: journal.businessId,
            taxYear: journal.taxYear,
            journalDate: cancelledAt,
            voucherNo: reversalVoucher.value,
            sourceEvidenceId: journal.sourceEvidenceId,
            sourceCandidateId: journal.sourceCandidateId,
            entryType: .reversal,
            description: makeReversalDescription(for: journal, reason: reason),
            lines: reversalLines,
            approvedAt: cancelledAt,
            lockedAt: cancelledAt,
            createdAt: cancelledAt,
            updatedAt: cancelledAt
        )

        guard reversal.isBalanced else {
            throw PostingWorkflowUseCaseError.journalNotBalanced(journal.id)
        }
        return reversal
    }

    private func makeReopenedCandidate(
        from sourceCandidate: PostingCandidate,
        reason: String?,
        reopenedAt: Date
    ) -> PostingCandidate {
        PostingCandidate(
            evidenceId: sourceCandidate.evidenceId,
            businessId: sourceCandidate.businessId,
            taxYear: sourceCandidate.taxYear,
            candidateDate: sourceCandidate.candidateDate,
            counterpartyId: sourceCandidate.counterpartyId,
            proposedLines: sourceCandidate.proposedLines,
            taxAnalysis: sourceCandidate.taxAnalysis,
            confidenceScore: sourceCandidate.confidenceScore,
            status: .needsReview,
            source: sourceCandidate.source,
            memo: normalizedReason(reason, fallback: sourceCandidate.memo),
            createdAt: reopenedAt,
            updatedAt: reopenedAt
        )
    }

    private func makeJournalLines(from candidate: PostingCandidate, journalId: UUID) throws -> [JournalLine] {
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
                journalLines.append(
                    JournalLine(
                        journalId: journalId,
                        accountId: debitAccountId,
                        debitAmount: line.amount,
                        creditAmount: 0,
                        taxCodeId: line.taxCodeId,
                        legalReportLineId: line.legalReportLineId,
                        counterpartyId: candidate.counterpartyId,
                        projectAllocationId: line.projectAllocationId,
                        genreTagIds: [],
                        evidenceReferenceId: line.evidenceLineReferenceId ?? candidate.evidenceId,
                        sortOrder: sortOrder
                    )
                )
                sortOrder += 1
            }

            if let creditAccountId = line.creditAccountId {
                journalLines.append(
                    JournalLine(
                        journalId: journalId,
                        accountId: creditAccountId,
                        debitAmount: 0,
                        creditAmount: line.amount,
                        taxCodeId: line.taxCodeId,
                        legalReportLineId: line.legalReportLineId,
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

    private func saveApprovalAuditEvents(
        originalCandidate: PostingCandidate,
        approvedCandidate: PostingCandidate,
        journal: CanonicalJournalEntry,
        reason: String?
    ) async {
        await saveAuditEvent(
            AuditEvent(
                businessId: approvedCandidate.businessId,
                eventType: .candidateApproved,
                aggregateType: "PostingCandidate",
                aggregateId: approvedCandidate.id,
                beforeStateHash: stateHash(originalCandidate),
                afterStateHash: stateHash(approvedCandidate),
                actor: "user",
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
                actor: "user",
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

    private func stateHash<T: Encodable>(_ value: T) -> String? {
        do {
            let data = try JSONEncoder().encode(value)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }

    private func makeReversalDescription(for journal: CanonicalJournalEntry, reason: String?) -> String {
        let base = "取消: \(journal.voucherNo)"
        if let normalized = normalizedReason(reason, fallback: nil) {
            return "\(base) \(normalized)"
        }
        if !journal.description.isEmpty {
            return "\(base) \(journal.description)"
        }
        return base
    }

    private func normalizedReason(_ reason: String?, fallback: String?) -> String? {
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        let fallbackTrimmed = fallback?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallbackTrimmed, !fallbackTrimmed.isEmpty {
            return fallbackTrimmed
        }
        return nil
    }
}
