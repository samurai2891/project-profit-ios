import Foundation
import SwiftData

enum ChartOfAccountsUseCaseError: LocalizedError {
    case missingLegalReportLine
    case invalidLegalReportLine(String)

    var errorDescription: String? {
        switch self {
        case .missingLegalReportLine:
            return "決算書表示行を設定してください"
        case .invalidLegalReportLine:
            return "決算書表示行の値が不正です"
        }
    }
}

@MainActor
struct ChartOfAccountsUseCase {
    private let chartOfAccountsRepository: any ChartOfAccountsRepository

    init(chartOfAccountsRepository: any ChartOfAccountsRepository) {
        self.chartOfAccountsRepository = chartOfAccountsRepository
    }

    init(modelContext: ModelContext) {
        self.init(chartOfAccountsRepository: SwiftDataChartOfAccountsRepository(modelContext: modelContext))
    }

    func account(_ id: UUID) async throws -> CanonicalAccount? {
        try await chartOfAccountsRepository.findById(id)
    }

    func account(businessId: UUID, legacyAccountId: String) async throws -> CanonicalAccount? {
        try await chartOfAccountsRepository.findByLegacyId(businessId: businessId, legacyAccountId: legacyAccountId)
    }

    func account(businessId: UUID, code: String) async throws -> CanonicalAccount? {
        try await chartOfAccountsRepository.findByCode(businessId: businessId, code: code)
    }

    func accounts(businessId: UUID) async throws -> [CanonicalAccount] {
        try await chartOfAccountsRepository.findAllByBusiness(businessId: businessId)
    }

    func accounts(businessId: UUID, type: CanonicalAccountType) async throws -> [CanonicalAccount] {
        try await chartOfAccountsRepository.findByType(businessId: businessId, accountType: type)
    }

    func save(_ account: CanonicalAccount) async throws {
        guard let legalReportLineId = account.defaultLegalReportLineId else {
            throw ChartOfAccountsUseCaseError.missingLegalReportLine
        }
        guard LegalReportLine(rawValue: legalReportLineId) != nil else {
            throw ChartOfAccountsUseCaseError.invalidLegalReportLine(legalReportLineId)
        }
        try await chartOfAccountsRepository.save(account)
    }

    func delete(_ id: UUID) async throws {
        try await chartOfAccountsRepository.delete(id)
    }
}
