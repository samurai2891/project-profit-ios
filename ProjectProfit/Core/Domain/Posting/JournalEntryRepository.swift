import Foundation

/// 確定仕訳リポジトリプロトコル
protocol CanonicalJournalEntryRepository: Sendable {
    func findById(_ id: UUID) async throws -> CanonicalJournalEntry?
    func findByBusinessAndYear(businessId: UUID, taxYear: Int) async throws -> [CanonicalJournalEntry]
    func findByDateRange(businessId: UUID, from: Date, to: Date) async throws -> [CanonicalJournalEntry]
    func findByEvidence(evidenceId: UUID) async throws -> [CanonicalJournalEntry]
    func save(_ entry: CanonicalJournalEntry) async throws
    func delete(_ id: UUID) async throws

    /// 次の伝票番号を取得
    func nextVoucherNumber(businessId: UUID, taxYear: Int, month: Int) async throws -> VoucherNumber
}

/// 仕訳候補リポジトリプロトコル
protocol PostingCandidateRepository: Sendable {
    func findById(_ id: UUID) async throws -> PostingCandidate?
    func findByEvidence(evidenceId: UUID) async throws -> [PostingCandidate]
    func findByStatus(businessId: UUID, status: CandidateStatus) async throws -> [PostingCandidate]
    func save(_ candidate: PostingCandidate) async throws
    func delete(_ id: UUID) async throws
}
