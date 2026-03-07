import Foundation
import SwiftData

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
        try await chartOfAccountsRepository.save(account)
    }

    func delete(_ id: UUID) async throws {
        try await chartOfAccountsRepository.delete(id)
    }
}
