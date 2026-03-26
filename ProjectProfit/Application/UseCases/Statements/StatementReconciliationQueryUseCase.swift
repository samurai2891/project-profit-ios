import Foundation
import SwiftData

@MainActor
struct StatementReconciliationQueryUseCase {
    private let statementRepository: any StatementRepository
    private let transactionFormQueryUseCase: TransactionFormQueryUseCase
    private let matchService: StatementMatchService

    init(
        modelContext: ModelContext,
        statementRepository: (any StatementRepository)? = nil,
        transactionFormQueryUseCase: TransactionFormQueryUseCase? = nil,
        matchService: StatementMatchService? = nil
    ) {
        self.statementRepository = statementRepository ?? SwiftDataStatementRepository(modelContext: modelContext)
        self.transactionFormQueryUseCase = transactionFormQueryUseCase ?? TransactionFormQueryUseCase(modelContext: modelContext)
        self.matchService = matchService ?? StatementMatchService(modelContext: modelContext)
    }

    func snapshot(filter: StatementReconciliationFilter) async throws -> StatementReconciliationSnapshot {
        let formSnapshot = try transactionFormQueryUseCase.snapshot()
        guard let businessId = formSnapshot.businessId else {
            return StatementReconciliationSnapshot(
                imports: [],
                lines: [],
                availablePaymentAccounts: [],
                unmatchedCount: 0
            )
        }

        try await matchService.promoteCandidateMatches(businessId: businessId)
        let imports = try await statementRepository.findImports(
            businessId: businessId,
            statementKind: filter.statementKind,
            paymentAccountId: filter.paymentAccountId
        )
        let lines = try await statementRepository.findLines(
            businessId: businessId,
            statementKind: filter.statementKind,
            paymentAccountId: filter.paymentAccountId,
            matchState: filter.matchState,
            startDate: filter.startDate,
            endDate: filter.endDate
        )
        let unmatchedLines = try await statementRepository.findLines(
            businessId: businessId,
            statementKind: filter.statementKind,
            paymentAccountId: filter.paymentAccountId,
            matchState: .unmatched,
            startDate: filter.startDate,
            endDate: filter.endDate
        )

        let availablePaymentAccounts = formSnapshot.accounts.filter { account in
            guard account.isActive else { return false }
            switch filter.statementKind {
            case .some(.bank):
                return account.subtype == .ordinaryDeposit
            case .some(.card):
                return account.subtype == .creditCard
            case .none:
                return account.subtype == .ordinaryDeposit || account.subtype == .creditCard
            }
        }

        return StatementReconciliationSnapshot(
            imports: imports,
            lines: lines,
            availablePaymentAccounts: availablePaymentAccounts,
            unmatchedCount: unmatchedLines.count
        )
    }

    func candidateOptions(for line: StatementLineRecord) async throws -> [PostingCandidate] {
        try await matchService.candidateOptions(for: line)
    }

    func journalOptions(for line: StatementLineRecord) async throws -> [CanonicalJournalEntry] {
        try await matchService.journalOptions(for: line)
    }
}
