import Foundation
import SwiftData

@MainActor
final class SwiftDataSettingsOverviewRepository: SettingsOverviewRepository {
    private let modelContext: ModelContext
    private let currentDateProvider: () -> Date

    init(
        modelContext: ModelContext,
        currentDateProvider: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.currentDateProvider = currentDateProvider
    }

    func snapshot(startMonth: Int) throws -> SettingsOverviewSnapshot {
        let projects = try modelContext.fetch(FetchDescriptor<PPProject>())
        let transactions = try modelContext.fetch(FetchDescriptor<PPTransaction>())
        let recurrings = try modelContext.fetch(FetchDescriptor<PPRecurringTransaction>())
        let inventoryRecords = try modelContext.fetch(FetchDescriptor<PPInventoryRecord>())

        let years = Set(
            transactions.map { fiscalYear(for: $0.date, startMonth: startMonth) }
                + inventoryRecords.map(\.fiscalYear)
                + [currentTaxYear()].compactMap { $0 }
        )
        let sortedYears = years.sorted(by: >)

        return SettingsOverviewSnapshot(
            projectCount: projects.count,
            transactionCount: transactions.count,
            recurringTransactionCount: recurrings.count,
            availableBackupYears: sortedYears.isEmpty
                ? [currentFiscalYear(startMonth: startMonth)]
                : sortedYears
        )
    }

    private func currentTaxYear() -> Int? {
        let businessDescriptor = FetchDescriptor<BusinessProfileEntity>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let businessId = try? modelContext.fetch(businessDescriptor).first?.businessId else {
            return nil
        }

        let year = Calendar.current.component(.year, from: currentDateProvider())
        let taxDescriptor = FetchDescriptor<TaxYearProfileEntity>(
            predicate: #Predicate {
                $0.businessId == businessId && $0.taxYear == year
            }
        )
        _ = try? modelContext.fetch(taxDescriptor).first
        return year
    }
}
