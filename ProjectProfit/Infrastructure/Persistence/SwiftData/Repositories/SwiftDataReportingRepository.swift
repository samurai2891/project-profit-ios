import Foundation
import SwiftData

@MainActor
final class SwiftDataReportingRepository: ReportingRepository {
    private struct CanonicalSupplementalSummaryRecord {
        let date: Date
        let type: TransactionType
        let amount: Int
        let projectId: UUID?
        let categoryId: String?
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func projectSummaries(startDate: Date?, endDate: Date?) throws -> [ProjectSummary] {
        let projects = try fetchProjects()
        let transactions = try fetchTransactions()
        let supplementalRecords = try canonicalSupplementalSummaryRecords(
            transactions: transactions,
            startDate: startDate,
            endDate: endDate
        )

        return projects.map { project in
            var totalIncome = 0
            var totalExpense = 0

            for transaction in transactions {
                if let startDate, transaction.date < startDate { continue }
                if let endDate, transaction.date > endDate { continue }
                if let allocation = transaction.allocations.first(where: { $0.projectId == project.id }) {
                    switch transaction.type {
                    case .income:
                        totalIncome += allocation.amount
                    case .expense:
                        totalExpense += allocation.amount
                    case .transfer:
                        break
                    }
                }
            }

            for record in supplementalRecords where record.projectId == project.id {
                switch record.type {
                case .income:
                    totalIncome += record.amount
                case .expense:
                    totalExpense += record.amount
                case .transfer:
                    break
                }
            }

            let profit = totalIncome - totalExpense
            let profitMargin = totalIncome > 0 ? Double(profit) / Double(totalIncome) * 100 : 0

            return ProjectSummary(
                id: project.id,
                projectName: project.name,
                status: project.status,
                totalIncome: totalIncome,
                totalExpense: totalExpense,
                profit: profit,
                profitMargin: profitMargin
            )
        }
    }

    func overallSummary(startDate: Date?, endDate: Date?) throws -> OverallSummary {
        let transactions = try fetchTransactions()
        let supplementalRecords = try canonicalSupplementalSummaryRecords(
            transactions: transactions,
            startDate: startDate,
            endDate: endDate
        )

        var totalIncome = 0
        var totalExpense = 0

        for transaction in transactions {
            if let startDate, transaction.date < startDate { continue }
            if let endDate, transaction.date > endDate { continue }
            switch transaction.type {
            case .income:
                totalIncome += transaction.amount
            case .expense:
                totalExpense += transaction.amount
            case .transfer:
                break
            }
        }

        for record in supplementalRecords {
            switch record.type {
            case .income:
                totalIncome += record.amount
            case .expense:
                totalExpense += record.amount
            case .transfer:
                break
            }
        }

        let netProfit = totalIncome - totalExpense
        let profitMargin = totalIncome > 0 ? Double(netProfit) / Double(totalIncome) * 100 : 0
        return OverallSummary(
            totalIncome: totalIncome,
            totalExpense: totalExpense,
            netProfit: netProfit,
            profitMargin: profitMargin
        )
    }

    func categorySummaries(type: TransactionType, startDate: Date?, endDate: Date?) throws -> [CategorySummary] {
        guard type != .transfer else {
            return []
        }

        let transactions = try fetchTransactions()
        let categoriesById = try Dictionary(uniqueKeysWithValues: fetchCategories().map { ($0.id, $0) })
        let supplementalRecords = try canonicalSupplementalSummaryRecords(
            transactions: transactions,
            startDate: startDate,
            endDate: endDate
        )

        var totals: [String: Int] = [:]
        var grandTotal = 0

        for transaction in transactions {
            guard transaction.type == type else { continue }
            if let startDate, transaction.date < startDate { continue }
            if let endDate, transaction.date > endDate { continue }
            totals[transaction.categoryId, default: 0] += transaction.amount
            grandTotal += transaction.amount
        }

        for record in supplementalRecords {
            guard record.type == type, let categoryId = record.categoryId else { continue }
            totals[categoryId, default: 0] += record.amount
            grandTotal += record.amount
        }

        return totals.map { categoryId, total in
            let categoryName = categoriesById[categoryId]?.name ?? "不明"
            let percentage = grandTotal > 0 ? Double(total) / Double(grandTotal) * 100 : 0
            return CategorySummary(
                categoryId: categoryId,
                categoryName: categoryName,
                total: total,
                percentage: percentage
            )
        }
        .sorted { $0.total > $1.total }
    }

    func monthlySummaries(fiscalYear: Int, startMonth: Int) throws -> [MonthlySummary] {
        let calendarMonths = fiscalYearCalendarMonths(fiscalYear: fiscalYear, startMonth: startMonth)
        let transactions = try fetchTransactions()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"

        var monthlyData: [(key: String, income: Int, expense: Int)] = calendarMonths.map { pair in
            let key = String(format: "%d-%02d", pair.year, pair.month)
            return (key: key, income: 0, expense: 0)
        }
        let keySet = Set(monthlyData.map(\.key))

        for transaction in transactions {
            let monthKey = formatter.string(from: transaction.date)
            guard keySet.contains(monthKey),
                  let index = monthlyData.firstIndex(where: { $0.key == monthKey })
            else {
                continue
            }

            switch transaction.type {
            case .income:
                monthlyData[index].income += transaction.amount
            case .expense:
                monthlyData[index].expense += transaction.amount
            case .transfer:
                break
            }
        }

        return monthlyData.map { entry in
            MonthlySummary(
                month: entry.key,
                income: entry.income,
                expense: entry.expense,
                profit: entry.income - entry.expense
            )
        }
    }

    private func canonicalSupplementalSummaryRecords(
        transactions: [PPTransaction],
        startDate: Date?,
        endDate: Date?
    ) throws -> [CanonicalSupplementalSummaryRecord] {
        let legacyTransactionIds = Set(transactions.map(\.id))
        let journals = try fetchJournalEntries().filter { journal in
            guard let sourceCandidateId = journal.sourceCandidateId else {
                return false
            }
            guard !legacyTransactionIds.contains(sourceCandidateId) else {
                return false
            }
            if let startDate, journal.journalDate < startDate {
                return false
            }
            if let endDate, journal.journalDate > endDate {
                return false
            }
            return true
        }
        guard !journals.isEmpty else {
            return []
        }

        let candidatesById = try fetchPostingCandidates(ids: Set(journals.compactMap(\.sourceCandidateId)))

        return journals.flatMap { journal -> [CanonicalSupplementalSummaryRecord] in
            guard let candidateId = journal.sourceCandidateId,
                  let candidate = candidatesById[candidateId],
                  let transactionType = candidate.legacySnapshot?.type
            else {
                return []
            }

            let relevantLines: [PostingCandidateLine]
            switch transactionType {
            case .income:
                relevantLines = candidate.proposedLines.filter { $0.creditAccountId != nil }
            case .expense:
                relevantLines = candidate.proposedLines.filter { $0.debitAccountId != nil }
            case .transfer:
                relevantLines = []
            }

            let categoryId = candidate.legacySnapshot?.categoryId
            return relevantLines.compactMap { line in
                let amount = NSDecimalNumber(decimal: line.amount).intValue
                guard amount != 0 else {
                    return nil
                }
                return CanonicalSupplementalSummaryRecord(
                    date: journal.journalDate,
                    type: transactionType,
                    amount: amount,
                    projectId: line.projectAllocationId,
                    categoryId: categoryId
                )
            }
        }
    }

    private func fetchProjects() throws -> [PPProject] {
        let descriptor = FetchDescriptor<PPProject>(sortBy: [SortDescriptor(\.createdAt)])
        return try modelContext.fetch(descriptor)
    }

    private func fetchTransactions() throws -> [PPTransaction] {
        let descriptor = FetchDescriptor<PPTransaction>(sortBy: [SortDescriptor(\.date)])
        return try modelContext.fetch(descriptor)
    }

    private func fetchCategories() throws -> [PPCategory] {
        let descriptor = FetchDescriptor<PPCategory>(sortBy: [SortDescriptor(\PPCategory.name)])
        return try modelContext.fetch(descriptor)
    }

    private func fetchJournalEntries() throws -> [CanonicalJournalEntry] {
        let descriptor = FetchDescriptor<JournalEntryEntity>(sortBy: [SortDescriptor(\.journalDate)])
        return try modelContext.fetch(descriptor).map(CanonicalJournalEntryEntityMapper.toDomain)
    }

    private func fetchPostingCandidates(ids: Set<UUID>) throws -> [UUID: PostingCandidate] {
        guard !ids.isEmpty else {
            return [:]
        }

        let descriptor = FetchDescriptor<PostingCandidateEntity>()
        let entities = try modelContext.fetch(descriptor)
        return entities.reduce(into: [UUID: PostingCandidate]()) { result, entity in
            guard ids.contains(entity.candidateId) else {
                return
            }
            result[entity.candidateId] = PostingCandidateEntityMapper.toDomain(entity)
        }
    }
}
