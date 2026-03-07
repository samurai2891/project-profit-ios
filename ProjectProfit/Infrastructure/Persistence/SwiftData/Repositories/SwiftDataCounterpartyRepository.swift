import Foundation
import SwiftData

/// SwiftData による Counterparty 永続化実装
@MainActor
final class SwiftDataCounterpartyRepository: CounterpartyRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    nonisolated func findById(_ id: UUID) async throws -> Counterparty? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<CounterpartyEntity>(
                predicate: #Predicate { $0.counterpartyId == id }
            )
            return try modelContext.fetch(descriptor).first.map(CounterpartyEntityMapper.toDomain)
        }
    }

    nonisolated func findByBusiness(businessId: UUID) async throws -> [Counterparty] {
        try await MainActor.run {
            let descriptor = FetchDescriptor<CounterpartyEntity>(
                predicate: #Predicate { $0.businessId == businessId },
                sortBy: [SortDescriptor(\.displayName)]
            )
            return try modelContext.fetch(descriptor).map(CounterpartyEntityMapper.toDomain)
        }
    }

    nonisolated func findByName(businessId: UUID, query: String) async throws -> [Counterparty] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return try await findByBusiness(businessId: businessId)
        }

        return try await findByBusiness(businessId: businessId)
            .filter { counterparty in
                counterparty.displayName.localizedCaseInsensitiveContains(normalizedQuery)
                || (counterparty.kana?.localizedCaseInsensitiveContains(normalizedQuery) ?? false)
                || (counterparty.legalName?.localizedCaseInsensitiveContains(normalizedQuery) ?? false)
            }
    }

    nonisolated func findByRegistrationNumber(_ number: String) async throws -> Counterparty? {
        let normalizedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNumber.isEmpty else { return nil }

        return try await MainActor.run {
            let descriptor = FetchDescriptor<CounterpartyEntity>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor)
                .map(CounterpartyEntityMapper.toDomain)
                .first {
                    $0.corporateNumber == normalizedNumber || $0.invoiceRegistrationNumber == normalizedNumber
                }
        }
    }

    nonisolated func save(_ counterparty: Counterparty) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<CounterpartyEntity>(
                predicate: #Predicate { $0.counterpartyId == counterparty.id }
            )
            let existing = try modelContext.fetch(descriptor)

            if let entity = existing.first {
                CounterpartyEntityMapper.update(entity, from: counterparty)
            } else {
                modelContext.insert(CounterpartyEntityMapper.toEntity(counterparty))
            }
            try modelContext.save()
        }
    }

    nonisolated func delete(_ id: UUID) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<CounterpartyEntity>(
                predicate: #Predicate { $0.counterpartyId == id }
            )
            let results = try modelContext.fetch(descriptor)
            results.forEach(modelContext.delete)
            try modelContext.save()
        }
    }
}
