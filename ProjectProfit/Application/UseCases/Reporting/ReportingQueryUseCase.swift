import Foundation
import SwiftData

@MainActor
struct ReportingQueryUseCase {
    private let repository: any ReportingRepository
    private let modelContext: ModelContext?

    init(repository: any ReportingRepository, modelContext: ModelContext? = nil) {
        self.repository = repository
        self.modelContext = modelContext
    }

    init(modelContext: ModelContext) {
        self.init(
            repository: SwiftDataReportingRepository(modelContext: modelContext),
            modelContext: modelContext
        )
    }

    func projectSummaries(startDate: Date? = nil, endDate: Date? = nil) -> [ProjectSummary] {
        (try? repository.projectSummaries(startDate: startDate, endDate: endDate)) ?? []
    }

    func overallSummary(startDate: Date? = nil, endDate: Date? = nil) -> OverallSummary {
        (try? repository.overallSummary(startDate: startDate, endDate: endDate))
            ?? OverallSummary(totalIncome: 0, totalExpense: 0, netProfit: 0, profitMargin: 0)
    }

    func categorySummaries(
        type: TransactionType,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> [CategorySummary] {
        (try? repository.categorySummaries(type: type, startDate: startDate, endDate: endDate)) ?? []
    }

    func monthlySummaries(fiscalYear: Int, startMonth: Int) -> [MonthlySummary] {
        (try? repository.monthlySummaries(fiscalYear: fiscalYear, startMonth: startMonth)) ?? []
    }

    func monthlySummaryRows(year: Int) -> [MonthlySummaryRow] {
        guard let modelContext else {
            return []
        }
        return MonthlySummaryRowReadModelQuery(modelContext: modelContext).rows(year: year)
    }
}
