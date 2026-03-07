import Foundation
import SwiftData

/// SwiftData による勘定科目表永続化実装
@MainActor
final class SwiftDataChartOfAccountsRepository: ChartOfAccountsRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    nonisolated func findById(_ id: UUID) async throws -> CanonicalAccount? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<CanonicalAccountEntity>(
                predicate: #Predicate { $0.accountId == id }
            )
            return try modelContext.fetch(descriptor).first.map(CanonicalAccountEntityMapper.toDomain)
        }
    }

    nonisolated func findByLegacyId(businessId: UUID, legacyAccountId: String) async throws -> CanonicalAccount? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<CanonicalAccountEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.legacyAccountId == legacyAccountId
                }
            )
            return try modelContext.fetch(descriptor).first.map(CanonicalAccountEntityMapper.toDomain)
        }
    }

    nonisolated func findByCode(businessId: UUID, code: String) async throws -> CanonicalAccount? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<CanonicalAccountEntity>(
                predicate: #Predicate { $0.businessId == businessId && $0.code == code }
            )
            return try modelContext.fetch(descriptor).first.map(CanonicalAccountEntityMapper.toDomain)
        }
    }

    nonisolated func findAllByBusiness(businessId: UUID) async throws -> [CanonicalAccount] {
        try await MainActor.run {
            let descriptor = FetchDescriptor<CanonicalAccountEntity>(
                predicate: #Predicate { $0.businessId == businessId },
                sortBy: [
                    SortDescriptor(\.displayOrder),
                    SortDescriptor(\.code)
                ]
            )
            return try modelContext.fetch(descriptor).map(CanonicalAccountEntityMapper.toDomain)
        }
    }

    nonisolated func findByType(businessId: UUID, accountType: CanonicalAccountType) async throws -> [CanonicalAccount] {
        try await MainActor.run {
            let rawValue = accountType.rawValue
            let descriptor = FetchDescriptor<CanonicalAccountEntity>(
                predicate: #Predicate { $0.businessId == businessId && $0.accountTypeRaw == rawValue },
                sortBy: [
                    SortDescriptor(\.displayOrder),
                    SortDescriptor(\.code)
                ]
            )
            return try modelContext.fetch(descriptor).map(CanonicalAccountEntityMapper.toDomain)
        }
    }

    nonisolated func save(_ account: CanonicalAccount) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<CanonicalAccountEntity>(
                predicate: #Predicate { $0.accountId == account.id }
            )
            let existing = try modelContext.fetch(descriptor)

            if let entity = existing.first {
                CanonicalAccountEntityMapper.update(entity, from: account)
            } else {
                modelContext.insert(CanonicalAccountEntityMapper.toEntity(account))
            }
            try modelContext.save()
        }
    }

    nonisolated func delete(_ id: UUID) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<CanonicalAccountEntity>(
                predicate: #Predicate { $0.accountId == id }
            )
            let entities = try modelContext.fetch(descriptor)
            entities.forEach(modelContext.delete)
            try modelContext.save()
        }
    }
}
