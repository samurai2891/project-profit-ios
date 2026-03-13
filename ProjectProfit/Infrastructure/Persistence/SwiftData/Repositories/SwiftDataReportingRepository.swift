import Foundation
import SwiftData

@MainActor
final class SwiftDataReportingRepository: ReportingRepository {
    private struct CanonicalSummaryRecord {
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
        let records = try canonicalSummaryRecords(startDate: startDate, endDate: endDate)

        return projects.map { project in
            let projectRecords = records.filter { $0.projectId == project.id }
            let totalIncome = projectRecords
                .filter { $0.type == .income }
                .reduce(0) { $0 + $1.amount }
            let totalExpense = projectRecords
                .filter { $0.type == .expense }
                .reduce(0) { $0 + $1.amount }
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
        let records = try canonicalSummaryRecords(startDate: startDate, endDate: endDate)
        let totalIncome = records
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.amount }
        let totalExpense = records
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amount }
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

        let categoriesById = try Dictionary(uniqueKeysWithValues: fetchCategories().map { ($0.id, $0) })
        let records = try canonicalSummaryRecords(startDate: startDate, endDate: endDate)

        var totals: [String: Int] = [:]
        var grandTotal = 0
        for record in records where record.type == type {
            guard let categoryId = record.categoryId else {
                continue
            }
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
        let range = fiscalYearDateBounds(fiscalYear: fiscalYear, startMonth: startMonth)
        let records = try canonicalSummaryRecords(startDate: range.lowerBound, endDate: range.upperBound)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"

        var monthlyData: [(key: String, income: Int, expense: Int)] = calendarMonths.map { pair in
            let key = String(format: "%d-%02d", pair.year, pair.month)
            return (key: key, income: 0, expense: 0)
        }
        let keySet = Set(monthlyData.map(\.key))

        for record in records {
            let monthKey = formatter.string(from: record.date)
            guard keySet.contains(monthKey),
                  let index = monthlyData.firstIndex(where: { $0.key == monthKey })
            else {
                continue
            }

            switch record.type {
            case .income:
                monthlyData[index].income += record.amount
            case .expense:
                monthlyData[index].expense += record.amount
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

    private func canonicalSummaryRecords(
        startDate: Date?,
        endDate: Date?
    ) throws -> [CanonicalSummaryRecord] {
        let accountsById = try Dictionary(uniqueKeysWithValues: fetchCanonicalAccounts().map { ($0.id, $0) })
        let journals = try fetchJournalEntries().filter { journal in
            guard journal.approvedAt != nil, journal.entryType == .normal else {
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
        let candidatesById = try fetchPostingCandidates(ids: Set(journals.compactMap(\.sourceCandidateId)))

        return journals.flatMap { journal in
            let candidate = journal.sourceCandidateId.flatMap { candidatesById[$0] }
            return journal.lines.compactMap { line -> CanonicalSummaryRecord? in
                guard let account = accountsById[line.accountId] else {
                    return nil
                }

                let type: TransactionType?
                let amount: Int
                switch account.accountType {
                case .revenue where line.creditAmount > 0:
                    type = .income
                    amount = NSDecimalNumber(decimal: line.creditAmount).intValue
                case .expense where line.debitAmount > 0:
                    type = .expense
                    amount = NSDecimalNumber(decimal: line.debitAmount).intValue
                default:
                    type = nil
                    amount = 0
                }

                guard let type, amount != 0 else {
                    return nil
                }

                return CanonicalSummaryRecord(
                    date: journal.journalDate,
                    type: type,
                    amount: amount,
                    projectId: line.projectAllocationId,
                    categoryId: candidate?.legacySnapshot?.categoryId
                )
            }
        }
    }

    private func fetchProjects() throws -> [PPProject] {
        let descriptor = FetchDescriptor<PPProject>(sortBy: [SortDescriptor(\.createdAt)])
        return try modelContext.fetch(descriptor)
    }

    private func fetchCategories() throws -> [PPCategory] {
        let descriptor = FetchDescriptor<PPCategory>(sortBy: [SortDescriptor(\PPCategory.name)])
        return try modelContext.fetch(descriptor)
    }

    private func fetchCanonicalAccounts() throws -> [CanonicalAccount] {
        let descriptor = FetchDescriptor<CanonicalAccountEntity>(sortBy: [SortDescriptor(\.displayOrder)])
        return try modelContext.fetch(descriptor).map(CanonicalAccountEntityMapper.toDomain)
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

    private func fiscalYearDateBounds(fiscalYear: Int, startMonth: Int) -> ClosedRange<Date> {
        let calendar = Calendar(identifier: .gregorian)
        let startYear = fiscalYear
        let startDate = calendar.date(from: DateComponents(year: startYear, month: startMonth, day: 1)) ?? .distantPast
        let endMonth = startMonth == 1 ? 12 : startMonth - 1
        let endYear = startMonth == 1 ? fiscalYear : fiscalYear + 1
        let endMonthStart = calendar.date(from: DateComponents(year: endYear, month: endMonth, day: 1)) ?? .distantFuture
        let endDate = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: endMonthStart) ?? .distantFuture
        return startDate...endDate
    }
}
