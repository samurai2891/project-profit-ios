import Foundation
import SwiftData

/// SwiftData による CanonicalJournalEntry 永続化実装
@MainActor
final class SwiftDataCanonicalJournalEntryRepository: CanonicalJournalEntryRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    nonisolated func findById(_ id: UUID) async throws -> CanonicalJournalEntry? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<JournalEntryEntity>(
                predicate: #Predicate { $0.journalId == id }
            )
            return try modelContext.fetch(descriptor).first.map(CanonicalJournalEntryEntityMapper.toDomain)
        }
    }

    nonisolated func findByBusinessAndYear(businessId: UUID, taxYear: Int) async throws -> [CanonicalJournalEntry] {
        try await MainActor.run {
            let descriptor = FetchDescriptor<JournalEntryEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.taxYear == taxYear
                },
                sortBy: [
                    SortDescriptor(\.journalDate, order: .reverse),
                    SortDescriptor(\.voucherNo, order: .reverse)
                ]
            )
            return try modelContext.fetch(descriptor).map(CanonicalJournalEntryEntityMapper.toDomain)
        }
    }

    nonisolated func findByDateRange(businessId: UUID, from: Date, to: Date) async throws -> [CanonicalJournalEntry] {
        try await MainActor.run {
            let descriptor = FetchDescriptor<JournalEntryEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.journalDate >= from && $0.journalDate <= to
                },
                sortBy: [SortDescriptor(\.journalDate)]
            )
            return try modelContext.fetch(descriptor).map(CanonicalJournalEntryEntityMapper.toDomain)
        }
    }

    nonisolated func findByEvidence(evidenceId: UUID) async throws -> [CanonicalJournalEntry] {
        try await MainActor.run {
            let descriptor = FetchDescriptor<JournalEntryEntity>(
                predicate: #Predicate { $0.sourceEvidenceId == evidenceId },
                sortBy: [SortDescriptor(\.journalDate, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).map(CanonicalJournalEntryEntityMapper.toDomain)
        }
    }

    nonisolated func save(_ entry: CanonicalJournalEntry) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<JournalEntryEntity>(
                predicate: #Predicate { $0.journalId == entry.id }
            )
            let existing = try modelContext.fetch(descriptor)

            if let entity = existing.first {
                let previousLines = entity.lines
                CanonicalJournalEntryEntityMapper.update(entity, from: entry)
                entity.lines = []
                previousLines.forEach(modelContext.delete)
                entity.lines = CanonicalJournalEntryEntityMapper.makeLineEntities(from: entry.lines, journalEntry: entity)
            } else {
                modelContext.insert(CanonicalJournalEntryEntityMapper.toEntity(entry))
            }
            try modelContext.save()
        }
    }

    nonisolated func delete(_ id: UUID) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<JournalEntryEntity>(
                predicate: #Predicate { $0.journalId == id }
            )
            let results = try modelContext.fetch(descriptor)
            results.forEach(modelContext.delete)
            try modelContext.save()
        }
    }

    nonisolated func nextVoucherNumber(businessId: UUID, taxYear: Int, month: Int) async throws -> VoucherNumber {
        try await MainActor.run {
            let descriptor = FetchDescriptor<JournalEntryEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.taxYear == taxYear
                },
                sortBy: [SortDescriptor(\.voucherNo, order: .reverse)]
            )
            let sequence = try modelContext.fetch(descriptor)
                .compactMap { VoucherNumber(rawValue: $0.voucherNo) }
                .filter { $0.taxYear == taxYear && $0.month == month }
                .compactMap(\.sequence)
                .max() ?? 0
            return VoucherNumber(taxYear: taxYear, month: month, sequence: sequence + 1)
        }
    }
}
