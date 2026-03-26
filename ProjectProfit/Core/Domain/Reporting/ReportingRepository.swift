import Foundation

@MainActor
protocol ReportingRepository {
    func projectSummaries(startDate: Date?, endDate: Date?) throws -> [ProjectSummary]
    func overallSummary(startDate: Date?, endDate: Date?) throws -> OverallSummary
    func categorySummaries(type: TransactionType, startDate: Date?, endDate: Date?) throws -> [CategorySummary]
    func monthlySummaries(fiscalYear: Int, startMonth: Int) throws -> [MonthlySummary]
}
