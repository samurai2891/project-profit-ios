import Foundation
import SwiftData

@MainActor
struct ProjectQueryUseCase {
    private let queryRepository: any ProjectQueryRepository

    init(
        modelContext: ModelContext,
        queryRepository: (any ProjectQueryRepository)? = nil
    ) {
        self.queryRepository = queryRepository ?? SwiftDataProjectQueryRepository(modelContext: modelContext)
    }

    func listSnapshot() -> ProjectListSnapshot {
        queryRepository.listSnapshot()
    }

    func detailSnapshot(projectId: UUID, startMonth: Int = FiscalYearSettings.startMonth) -> ProjectDetailSnapshot {
        queryRepository.detailSnapshot(projectId: projectId, startMonth: startMonth)
    }
}
