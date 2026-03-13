import Foundation
import SwiftData

enum FilingPreflightContext: Sendable, Equatable {
    case export
    case closing(targetState: YearLockState)
}

struct FilingPreflightIssue: Identifiable, Sendable, Equatable {
    enum Code: String, Sendable {
        case unbalancedJournal
        case trialBalanceMismatch
        case suspenseBalanceRemaining
        case pendingCandidateExists
        case unmappedCategoryExists
        case closingEntryMissing
        case yearStateTooOpen
    }

    enum Severity: String, Sendable {
        case error
        case warning
        case info
    }

    let id: String
    let code: Code
    let severity: Severity
    let message: String
    let relatedId: UUID?

    init(code: Code, severity: Severity, message: String, relatedId: UUID? = nil) {
        self.code = code
        self.severity = severity
        self.message = message
        self.relatedId = relatedId
        self.id = [code.rawValue, relatedId?.uuidString ?? "none", message].joined(separator: ":")
    }
}

struct FilingPreflightReport: Sendable, Equatable {
    let businessId: UUID
    let taxYear: Int
    let context: FilingPreflightContext
    let issues: [FilingPreflightIssue]
    let generatedAt: Date

    var blockingIssues: [FilingPreflightIssue] {
        issues.filter { $0.severity == .error }
    }

    var isBlocking: Bool {
        !blockingIssues.isEmpty
    }
}

@MainActor
struct FilingPreflightUseCase {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func preflightReport(
        businessId: UUID,
        taxYear: Int,
        context: FilingPreflightContext
    ) throws -> FilingPreflightReport {
        let snapshot = try makeProjectedSnapshot(businessId: businessId, taxYear: taxYear)
        let canonicalAccounts = try modelContext.fetch(
            FetchDescriptor<CanonicalAccountEntity>(
                predicate: #Predicate { $0.businessId == businessId }
            )
        ).map(CanonicalAccountEntityMapper.toDomain)
        let canonicalJournals = try modelContext.fetch(
            FetchDescriptor<JournalEntryEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.taxYear == taxYear
                }
            )
        ).map(CanonicalJournalEntryEntityMapper.toDomain)

        var issues = journalBalanceIssues(snapshot: snapshot)

        let trialBalance = AccountingReportService.generateTrialBalance(
            fiscalYear: taxYear,
            accounts: canonicalAccounts,
            journals: canonicalJournals,
            startMonth: FiscalYearSettings.startMonth
        )
        if !trialBalance.isBalanced {
            issues.append(
                FilingPreflightIssue(
                    code: .trialBalanceMismatch,
                    severity: .error,
                    message: "試算表が貸借不一致です"
                )
            )
        }

        let suspenseAccountId = canonicalAccounts.first {
            $0.legacyAccountId == AccountingConstants.suspenseAccountId
        }?.id
        if let suspenseAccountId,
           let suspenseRow = trialBalance.rows.first(where: { $0.id == suspenseAccountId }),
           suspenseRow.balance != 0
        {
            issues.append(
                FilingPreflightIssue(
                    code: .suspenseBalanceRemaining,
                    severity: .error,
                    message: "仮勘定の残高が残っています (\(formatCurrency(decimalInt(suspenseRow.balance))))"
                )
            )
        }

        let pendingCandidates = try fetchPendingCandidates(businessId: businessId, taxYear: taxYear)
        if !pendingCandidates.isEmpty {
            issues.append(
                FilingPreflightIssue(
                    code: .pendingCandidateExists,
                    severity: .error,
                    message: "未承認の仕訳候補が \(pendingCandidates.count) 件あります",
                    relatedId: pendingCandidates.first?.id
                )
            )
        }

        let unmappedCategories = try fetchUnmappedCategories()
        if !unmappedCategories.isEmpty {
            issues.append(
                FilingPreflightIssue(
                    code: .unmappedCategoryExists,
                    severity: .error,
                    message: "勘定科目未設定のカテゴリが \(unmappedCategories.count) 件あります"
                )
            )
        }

        switch context {
        case .export:
            let yearState = try yearLockState(businessId: businessId, taxYear: taxYear)
            if !meetsExportGate(yearState) {
                issues.append(
                    FilingPreflightIssue(
                        code: .yearStateTooOpen,
                        severity: .error,
                        message: "帳票出力は税務締め以降でのみ実行できます"
                    )
                )
            }
        case .closing(let targetState):
            if requiresClosingEntry(targetState),
               !snapshot.entries.contains(where: { $0.entryType == .closing })
            {
                issues.append(
                    FilingPreflightIssue(
                        code: .closingEntryMissing,
                        severity: .error,
                        message: "税務締め以降へ進む前に決算仕訳の生成が必要です"
                    )
                )
            }
        }

        return FilingPreflightReport(
            businessId: businessId,
            taxYear: taxYear,
            context: context,
            issues: issues,
            generatedAt: Date()
        )
    }

    private func makeProjectedSnapshot(
        businessId: UUID,
        taxYear: Int
    ) throws -> (entries: [PPJournalEntry], lines: [PPJournalLine]) {
        let canonicalAccountDescriptor = FetchDescriptor<CanonicalAccountEntity>(
            predicate: #Predicate { $0.businessId == businessId }
        )
        let canonicalAccounts = try modelContext.fetch(canonicalAccountDescriptor)
            .map(CanonicalAccountEntityMapper.toDomain)
        let accountsById = Dictionary(uniqueKeysWithValues: canonicalAccounts.map { ($0.id, $0) })

        let journalDescriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate {
                $0.businessId == businessId && $0.taxYear == taxYear
            },
            sortBy: [
                SortDescriptor(\.journalDate, order: .reverse),
                SortDescriptor(\.voucherNo, order: .reverse)
            ]
        )
        let canonicalJournals = try modelContext.fetch(journalDescriptor)
            .map(CanonicalJournalEntryEntityMapper.toDomain)

        let projectedEntries = canonicalJournals.map { journal in
            PPJournalEntry(
                id: journal.id,
                sourceKey: "canonical:\(journal.id.uuidString)",
                date: journal.journalDate,
                entryType: projectedLegacyEntryType(for: journal),
                memo: journal.description,
                isPosted: journal.approvedAt != nil,
                createdAt: journal.createdAt,
                updatedAt: journal.updatedAt
            )
        }
        let projectedLines = canonicalJournals.flatMap { journal in
            journal.lines.sorted { $0.sortOrder < $1.sortOrder }.map { line in
                let legacyAccountId = accountsById[line.accountId]?.legacyAccountId ?? line.accountId.uuidString
                return PPJournalLine(
                    id: line.id,
                    entryId: journal.id,
                    accountId: legacyAccountId,
                    debit: NSDecimalNumber(decimal: line.debitAmount).intValue,
                    credit: NSDecimalNumber(decimal: line.creditAmount).intValue,
                    memo: "",
                    displayOrder: line.sortOrder,
                    createdAt: journal.createdAt,
                    updatedAt: journal.updatedAt
                )
            }
        }

        let legacyDescriptor = FetchDescriptor<PPJournalEntry>()
        let legacyEntries = try modelContext.fetch(legacyDescriptor)
        let legacySupplementalEntries = legacyEntries.filter { entry in
            let isSupplemental = entry.sourceKey.hasPrefix("manual:")
                || entry.sourceKey.hasPrefix("opening:")
                || entry.sourceKey.hasPrefix("closing:")
            guard isSupplemental else {
                return false
            }
            return fiscalYear(for: entry.date, startMonth: FiscalYearSettings.startMonth) == taxYear
        }
        let legacyLineDescriptor = FetchDescriptor<PPJournalLine>()
        let legacyLines = try modelContext.fetch(legacyLineDescriptor)
        let legacySupplementalLines = legacyLines.filter { line in
            legacySupplementalEntries.contains { $0.id == line.entryId }
        }

        let mergedEntries = (projectedEntries + legacySupplementalEntries)
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.date > rhs.date
            }
        let mergedLines = projectedLines + legacySupplementalLines
        return (mergedEntries, mergedLines)
    }

    private func journalBalanceIssues(
        snapshot: (entries: [PPJournalEntry], lines: [PPJournalLine])
    ) -> [FilingPreflightIssue] {
        snapshot.entries.compactMap { entry in
            let lines = snapshot.lines.filter { $0.entryId == entry.id }
            guard !isBalanced(lines) else {
                return nil
            }
            return FilingPreflightIssue(
                code: .unbalancedJournal,
                severity: .error,
                message: "仕訳「\(entry.memo.isEmpty ? entry.sourceKey : entry.memo)」が貸借不一致です",
                relatedId: entry.id
            )
        }
    }

    private func fetchPendingCandidates(businessId: UUID, taxYear: Int) throws -> [PostingCandidate] {
        let descriptor = FetchDescriptor<PostingCandidateEntity>(
            predicate: #Predicate { $0.businessId == businessId }
        )
        return try modelContext.fetch(descriptor)
            .map(PostingCandidateEntityMapper.toDomain)
            .filter { $0.taxYear == taxYear && ($0.status == .draft || $0.status == .needsReview) }
    }

    private func fetchUnmappedCategories() throws -> [PPCategory] {
        try modelContext.fetch(FetchDescriptor<PPCategory>())
            .filter { $0.archivedAt == nil && ($0.linkedAccountId?.isEmpty != false) }
    }

    private func yearLockState(businessId: UUID, taxYear: Int) throws -> YearLockState {
        let descriptor = FetchDescriptor<TaxYearProfileEntity>(
            predicate: #Predicate {
                $0.businessId == businessId && $0.taxYear == taxYear
            }
        )
        guard let entity = try modelContext.fetch(descriptor).first else {
            return .open
        }
        return YearLockState(rawValue: entity.yearLockStateRaw) ?? .open
    }

    private func requiresClosingEntry(_ state: YearLockState) -> Bool {
        switch state {
        case .taxClose, .filed, .finalLock:
            return true
        case .open, .softClose:
            return false
        }
    }

    private func meetsExportGate(_ state: YearLockState) -> Bool {
        switch state {
        case .taxClose, .filed, .finalLock:
            return true
        case .open, .softClose:
            return false
        }
    }

    private func projectedLegacyEntryType(for entry: CanonicalJournalEntry) -> JournalEntryType {
        switch entry.entryType {
        case .opening:
            return .opening
        case .closing:
            return .closing
        case .normal, .depreciation, .inventoryAdjustment, .recurring, .taxAdjustment, .reversal:
            return .auto
        }
    }

    private func isBalanced(_ lines: [PPJournalLine]) -> Bool {
        let debitTotal = lines.reduce(0) { $0 + $1.debit }
        let creditTotal = lines.reduce(0) { $0 + $1.credit }
        return debitTotal == creditTotal && debitTotal > 0
    }

    private func formatCurrency(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "JPY"
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private func decimalInt(_ value: Decimal) -> Int {
    NSDecimalNumber(decimal: value).intValue
}
