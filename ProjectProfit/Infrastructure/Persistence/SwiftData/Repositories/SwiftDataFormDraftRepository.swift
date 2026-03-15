import Foundation
import SwiftData

@MainActor
final class SwiftDataFormDraftRepository: FormDraftRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    nonisolated func findById(_ id: UUID) async throws -> FormDraft? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<FormDraftEntity>(
                predicate: #Predicate { $0.draftId == id }
            )
            return try modelContext.fetch(descriptor).first.map(FormDraftEntityMapper.toDomain)
        }
    }

    nonisolated func findByKey(_ draftKey: String) async throws -> FormDraft? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<FormDraftEntity>(
                predicate: #Predicate { $0.draftKey == draftKey }
            )
            return try modelContext.fetch(descriptor).first.map(FormDraftEntityMapper.toDomain)
        }
    }

    nonisolated func save(_ draft: FormDraft) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<FormDraftEntity>(
                predicate: #Predicate { $0.draftKey == draft.draftKey }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                FormDraftEntityMapper.update(existing, from: draft)
            } else {
                modelContext.insert(FormDraftEntityMapper.toEntity(draft))
            }
            try modelContext.save()
        }
    }

    nonisolated func deleteByKey(_ draftKey: String) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<FormDraftEntity>(
                predicate: #Predicate { $0.draftKey == draftKey }
            )
            let drafts = try modelContext.fetch(descriptor)
            drafts.forEach(modelContext.delete)
            try modelContext.save()
        }
    }
}
