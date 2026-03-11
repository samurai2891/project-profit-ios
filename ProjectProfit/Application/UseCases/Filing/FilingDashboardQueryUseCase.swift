import Foundation
import SwiftData

struct FilingDashboardSnapshot: Sendable, Equatable {
    let businessId: UUID?
    let yearLockState: YearLockState
    let preflightIssues: [String]
}

@MainActor
struct FilingDashboardQueryUseCase {
    private let businessProfileRepository: any BusinessProfileRepository
    private let taxYearProfileRepository: any TaxYearProfileRepository
    private let preflightReportLoader: (UUID, Int) async throws -> FilingPreflightReport

    init(
        businessProfileRepository: any BusinessProfileRepository,
        taxYearProfileRepository: any TaxYearProfileRepository,
        preflightReportLoader: @escaping (UUID, Int) async throws -> FilingPreflightReport
    ) {
        self.businessProfileRepository = businessProfileRepository
        self.taxYearProfileRepository = taxYearProfileRepository
        self.preflightReportLoader = preflightReportLoader
    }

    init(modelContext: ModelContext) {
        self.init(
            businessProfileRepository: SwiftDataBusinessProfileRepository(modelContext: modelContext),
            taxYearProfileRepository: SwiftDataTaxYearProfileRepository(modelContext: modelContext),
            preflightReportLoader: { businessId, fiscalYear in
                try await FilingPreflightUseCase(modelContext: modelContext).preflightReport(
                    businessId: businessId,
                    taxYear: fiscalYear,
                    context: .export
                )
            }
        )
    }

    func snapshot(fiscalYear: Int) async throws -> FilingDashboardSnapshot {
        let businessId = try await businessProfileRepository.findDefault()?.id
        guard let businessId else {
            return FilingDashboardSnapshot(
                businessId: nil,
                yearLockState: .open,
                preflightIssues: []
            )
        }

        let yearLockState = try await taxYearProfileRepository
            .findByBusinessAndYear(businessId: businessId, taxYear: fiscalYear)?
            .yearLockState ?? .open

        let preflightIssues: [String]
        do {
            let report = try await preflightReportLoader(businessId, fiscalYear)
            preflightIssues = report.blockingIssues.map(\.message)
        } catch {
            preflightIssues = [error.localizedDescription]
        }

        return FilingDashboardSnapshot(
            businessId: businessId,
            yearLockState: yearLockState,
            preflightIssues: preflightIssues
        )
    }
}
