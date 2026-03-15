import Foundation
import SwiftData

@MainActor
struct PostingIntakeStore {
    private let modelContext: ModelContext
    private let projectRepository: any ProjectRepository
    private let postingCandidateRepository: any PostingCandidateRepository
    private let evidenceRepository: any EvidenceRepository

    init(
        modelContext: ModelContext,
        projectRepository: (any ProjectRepository)? = nil,
        postingCandidateRepository: (any PostingCandidateRepository)? = nil,
        evidenceRepository: (any EvidenceRepository)? = nil
    ) {
        self.modelContext = modelContext
        self.projectRepository = projectRepository ?? SwiftDataProjectRepository(modelContext: modelContext)
        self.postingCandidateRepository = postingCandidateRepository ?? SwiftDataPostingCandidateRepository(modelContext: modelContext)
        self.evidenceRepository = evidenceRepository ?? SwiftDataEvidenceRepository(modelContext: modelContext)
    }

    func createProject(
        name: String,
        description: String = ""
    ) throws -> PPProject {
        let project = PPProject(name: name, projectDescription: description)
        projectRepository.insert(project)
        try WorkflowPersistenceSupport.save(modelContext: modelContext)
        return project
    }

    func saveCandidate(_ candidate: PostingCandidate) async throws {
        try await postingCandidateRepository.save(candidate)
    }

    func saveEvidence(_ evidence: EvidenceDocument) async throws {
        try await evidenceRepository.save(evidence)
    }

    func existingEvidenceId(
        businessId: UUID,
        fileHash: String
    ) throws -> UUID? {
        let descriptor = FetchDescriptor<EvidenceRecordEntity>(
            predicate: #Predicate {
                $0.businessId == businessId &&
                    $0.fileHash == fileHash &&
                    $0.deletedAt == nil
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).first?.evidenceId
    }
}
