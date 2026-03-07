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

    nonisolated func findByDisplayNamePrefix(businessId: UUID, query: String) async throws -> [Counterparty] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        guard !normalizedQuery.isEmpty else { return [] }

        let foldOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        let all = try await findByBusiness(businessId: businessId)

        // Fold once per counterparty, then filter + sort
        let annotated: [(counterparty: Counterparty, foldedName: String)] = all.compactMap { cp in
            let foldedName = cp.displayName.folding(options: foldOptions, locale: .current)
            let foldedKana = cp.kana?.folding(options: foldOptions, locale: .current)
            let foldedLegal = cp.legalName?.folding(options: foldOptions, locale: .current)

            let matches = foldedName.contains(normalizedQuery)
                || (foldedKana?.hasPrefix(normalizedQuery) ?? false)
                || (foldedLegal?.hasPrefix(normalizedQuery) ?? false)
            return matches ? (cp, foldedName) : nil
        }

        return annotated
            .sorted { lhs, rhs in
                let lhsPrefix = lhs.foldedName.hasPrefix(normalizedQuery)
                let rhsPrefix = rhs.foldedName.hasPrefix(normalizedQuery)
                if lhsPrefix != rhsPrefix { return lhsPrefix }
                let lhsExact = lhs.foldedName == normalizedQuery
                let rhsExact = rhs.foldedName == normalizedQuery
                if lhsExact != rhsExact { return lhsExact }
                return lhs.counterparty.displayName < rhs.counterparty.displayName
            }
            .map(\.counterparty)
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
