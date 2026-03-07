import Foundation
import SwiftData

@MainActor
struct CounterpartyMasterUseCase {
    private let counterpartyRepository: any CounterpartyRepository

    init(counterpartyRepository: any CounterpartyRepository) {
        self.counterpartyRepository = counterpartyRepository
    }

    init(modelContext: ModelContext) {
        self.init(counterpartyRepository: SwiftDataCounterpartyRepository(modelContext: modelContext))
    }

    func loadCounterparties(businessId: UUID) async throws -> [Counterparty] {
        try await counterpartyRepository.findByBusiness(businessId: businessId)
    }

    func searchCounterparties(businessId: UUID, query: String) async throws -> [Counterparty] {
        try await counterpartyRepository.findByName(businessId: businessId, query: query)
    }

    func findByRegistrationNumber(_ number: String) async throws -> Counterparty? {
        try await counterpartyRepository.findByRegistrationNumber(number)
    }

    func save(_ counterparty: Counterparty) async throws {
        try await counterpartyRepository.save(counterparty)
    }

    func delete(_ id: UUID) async throws {
        try await counterpartyRepository.delete(id)
    }
}
