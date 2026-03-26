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
        case taxPrerequisiteMissing
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
    private struct PreflightSnapshot {
        let canonicalAccounts: [CanonicalAccount]
        let canonicalJournals: [CanonicalJournalEntry]
        let projectedEntries: [PPJournalEntry]
        let linesByEntryId: [UUID: [PPJournalLine]]
        let suspenseBalance: Int
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func preflightReport(
        businessId: UUID,
        taxYear: Int,
        context: FilingPreflightContext
    ) throws -> FilingPreflightReport {
        let snapshot = try buildPreflightSnapshot(businessId: businessId, taxYear: taxYear)
        var issues = journalBalanceIssues(
            entries: snapshot.projectedEntries,
            linesByEntryId: snapshot.linesByEntryId
        )

        let trialBalance = AccountingReportService.generateTrialBalance(
            fiscalYear: taxYear,
            accounts: snapshot.canonicalAccounts,
            journals: snapshot.canonicalJournals,
            startMonth: 1
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

        if snapshot.suspenseBalance != 0 {
            issues.append(
                FilingPreflightIssue(
                    code: .suspenseBalanceRemaining,
                    severity: .error,
                    message: "仮勘定の残高が残っています (\(formatCurrency(snapshot.suspenseBalance)))"
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
            let taxIssues = try TaxYearStateUseCase(modelContext: modelContext).filingPreflightIssues(
                businessId: businessId,
                taxYear: taxYear
            )
            issues.append(contentsOf: taxIssues.compactMap { issue in
                guard issue.severity == .error else {
                    return nil
                }
                return FilingPreflightIssue(
                    code: .taxPrerequisiteMissing,
                    severity: .error,
                    message: issue.message
                )
            })
            if requiresClosingEntry(targetState),
               !snapshot.projectedEntries.contains(where: { $0.entryType == .closing })
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

    private func buildPreflightSnapshot(
        businessId: UUID,
        taxYear: Int
    ) throws -> PreflightSnapshot {
        let canonicalAccountDescriptor = FetchDescriptor<CanonicalAccountEntity>(
            predicate: #Predicate { $0.businessId == businessId }
        )
        let canonicalAccounts = try modelContext.fetch(canonicalAccountDescriptor)
            .map(CanonicalAccountEntityMapper.toDomain)

        let startDate = startOfTaxYear(taxYear)
        let endDate = endOfTaxYear(taxYear)
        let journalDescriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate { $0.businessId == businessId },
            sortBy: [
                SortDescriptor(\.journalDate, order: .reverse),
                SortDescriptor(\.voucherNo, order: .reverse)
            ]
        )
        let canonicalJournals = try modelContext.fetch(journalDescriptor)
            .map(CanonicalJournalEntryEntityMapper.toDomain)
            .filter { $0.journalDate >= startDate && $0.journalDate <= endDate }

        let legacyDescriptor = FetchDescriptor<PPJournalEntry>(
            predicate: #Predicate<PPJournalEntry> { entry in
                entry.date >= startDate && entry.date <= endDate && (
                    entry.sourceKey.starts(with: "manual:")
                        || entry.sourceKey.starts(with: "opening:")
                        || entry.sourceKey.starts(with: "closing:")
                )
            }
        )
        let legacyEntries = try modelContext.fetch(legacyDescriptor)
        let legacyEntryIds = Set(legacyEntries.map(\.id))
        let legacyLines: [PPJournalLine]
        if legacyEntryIds.isEmpty {
            legacyLines = []
        } else {
            let legacyLineDescriptor = FetchDescriptor<PPJournalLine>()
            legacyLines = try modelContext.fetch(legacyLineDescriptor)
                .filter { legacyEntryIds.contains($0.entryId) }
        }
        let projected = LegacyProjectedJournalAssembler.assemble(
            businessId: businessId,
            canonicalAccounts: canonicalAccounts,
            canonicalJournals: canonicalJournals,
            legacyEntries: legacyEntries,
            legacyLines: legacyLines,
            supplementalSourcePrefixes: ["manual:", "opening:", "closing:", "depreciation:"]
        )

        let linesByEntryId = Dictionary(grouping: projected.lines, by: \.entryId)
        let suspenseBalance = projected.lines.reduce(into: 0) { result, line in
            guard line.accountId == AccountingConstants.suspenseAccountId else { return }
            result += line.debit - line.credit
        }

        return PreflightSnapshot(
            canonicalAccounts: canonicalAccounts,
            canonicalJournals: canonicalJournals,
            projectedEntries: projected.entries,
            linesByEntryId: linesByEntryId,
            suspenseBalance: suspenseBalance
        )
    }

    private func journalBalanceIssues(
        entries: [PPJournalEntry],
        linesByEntryId: [UUID: [PPJournalLine]]
    ) -> [FilingPreflightIssue] {
        entries.compactMap { entry in
            let lines = linesByEntryId[entry.id] ?? []
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
        let startDate = startOfTaxYear(taxYear)
        let endDate = endOfTaxYear(taxYear)
        let descriptor = FetchDescriptor<PostingCandidateEntity>(
            predicate: #Predicate { $0.businessId == businessId }
        )
        return try modelContext.fetch(descriptor)
            .map(PostingCandidateEntityMapper.toDomain)
            .filter {
                ($0.status == .draft || $0.status == .needsReview)
                    && $0.candidateDate >= startDate
                    && $0.candidateDate <= endDate
            }
    }

    private func fetchUnmappedCategories() throws -> [PPCategory] {
        try modelContext.fetch(
            FetchDescriptor<PPCategory>(
                predicate: #Predicate {
                    $0.archivedAt == nil
                }
            )
        )
        .filter { $0.linkedAccountId?.isEmpty != false }
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

    private func isBalanced(_ lines: [PPJournalLine]) -> Bool {
        let debitTotal = lines.reduce(0) { $0 + $1.debit }
        let creditTotal = lines.reduce(0) { $0 + $1.credit }
        return debitTotal == creditTotal && debitTotal > 0
    }

    private func fiscalYearDateRange(year: Int, startMonth: Int) -> (Date, Date) {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1)) ?? .distantPast
        let end = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: start) ?? .distantFuture
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
        return (start, endOfDay)
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
