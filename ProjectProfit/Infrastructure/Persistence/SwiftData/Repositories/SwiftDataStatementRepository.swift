import Foundation
import SwiftData

@MainActor
final class SwiftDataStatementRepository: StatementRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    nonisolated func findImport(_ id: UUID) async throws -> StatementImportRecord? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<StatementImportEntity>(
                predicate: #Predicate { $0.importId == id }
            )
            return try modelContext.fetch(descriptor).first.map(StatementImportEntityMapper.toDomain)
        }
    }

    nonisolated func findImports(
        businessId: UUID,
        statementKind: StatementKind?,
        paymentAccountId: String?
    ) async throws -> [StatementImportRecord] {
        try await MainActor.run {
            let descriptor = FetchDescriptor<StatementImportEntity>(
                predicate: #Predicate { $0.businessId == businessId },
                sortBy: [SortDescriptor(\.importedAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor)
                .map(StatementImportEntityMapper.toDomain)
                .filter { record in
                    (statementKind == nil || record.statementKind == statementKind)
                        && (paymentAccountId == nil || record.paymentAccountId == paymentAccountId)
                }
        }
    }

    nonisolated func saveImport(_ record: StatementImportRecord) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<StatementImportEntity>(
                predicate: #Predicate { $0.importId == record.id }
            )
            if let entity = try modelContext.fetch(descriptor).first {
                StatementImportEntityMapper.update(entity, from: record)
            } else {
                modelContext.insert(StatementImportEntityMapper.toEntity(record))
            }
            try modelContext.save()
        }
    }

    nonisolated func deleteImport(_ id: UUID) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<StatementImportEntity>(
                predicate: #Predicate { $0.importId == id }
            )
            let entities = try modelContext.fetch(descriptor)
            entities.forEach(modelContext.delete)
            try modelContext.save()
        }
    }

    nonisolated func findLine(_ id: UUID) async throws -> StatementLineRecord? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<StatementLineEntity>(
                predicate: #Predicate { $0.lineId == id }
            )
            return try modelContext.fetch(descriptor).first.map(StatementLineEntityMapper.toDomain)
        }
    }

    nonisolated func findLines(
        businessId: UUID,
        statementKind: StatementKind?,
        paymentAccountId: String?,
        matchState: StatementMatchState?,
        startDate: Date?,
        endDate: Date?
    ) async throws -> [StatementLineRecord] {
        try await MainActor.run {
            let descriptor = FetchDescriptor<StatementLineEntity>(
                predicate: #Predicate { $0.businessId == businessId },
                sortBy: [
                    SortDescriptor(\.date, order: .reverse),
                    SortDescriptor(\.createdAt, order: .reverse)
                ]
            )
            return try modelContext.fetch(descriptor)
                .map(StatementLineEntityMapper.toDomain)
                .filter { record in
                    let matchesKind = statementKind == nil || record.statementKind == statementKind
                    let matchesAccount = paymentAccountId == nil || record.paymentAccountId == paymentAccountId
                    let matchesState = matchState == nil || record.matchState == matchState
                    let matchesStart = startDate == nil || record.date >= startDate!
                    let matchesEnd = endDate == nil || record.date <= endDate!
                    return matchesKind && matchesAccount && matchesState && matchesStart && matchesEnd
                }
        }
    }

    nonisolated func findLines(importId: UUID) async throws -> [StatementLineRecord] {
        try await MainActor.run {
            let descriptor = FetchDescriptor<StatementLineEntity>(
                predicate: #Predicate { $0.importId == importId },
                sortBy: [
                    SortDescriptor(\.date),
                    SortDescriptor(\.createdAt)
                ]
            )
            return try modelContext.fetch(descriptor).map(StatementLineEntityMapper.toDomain)
        }
    }

    nonisolated func saveLine(_ record: StatementLineRecord) async throws {
        try await saveLines([record])
    }

    nonisolated func saveLines(_ records: [StatementLineRecord]) async throws {
        try await MainActor.run {
            guard !records.isEmpty else { return }
            let importIds = Set(records.map(\.importId))
            let importDescriptor = FetchDescriptor<StatementImportEntity>()
            let imports = try modelContext.fetch(importDescriptor)
            let importById = Dictionary(
                uniqueKeysWithValues: imports
                    .filter { importIds.contains($0.importId) }
                    .map { ($0.importId, $0) }
            )

            for record in records {
                let descriptor = FetchDescriptor<StatementLineEntity>(
                    predicate: #Predicate { $0.lineId == record.id }
                )
                if let entity = try modelContext.fetch(descriptor).first {
                    StatementLineEntityMapper.update(entity, from: record)
                } else {
                    let entity = StatementLineEntityMapper.toEntity(
                        record,
                        statementImport: importById[record.importId]
                    )
                    modelContext.insert(entity)
                }
            }
            try modelContext.save()
        }
    }

    nonisolated func deleteLines(importId: UUID) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<StatementLineEntity>(
                predicate: #Predicate { $0.importId == importId }
            )
            let entities = try modelContext.fetch(descriptor)
            entities.forEach(modelContext.delete)
            try modelContext.save()
        }
    }
}
