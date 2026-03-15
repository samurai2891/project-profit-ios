import Foundation
import SwiftData

struct DistributionTemplateManagementSnapshot {
    let businessId: UUID?
    let sortedProjects: [PPProject]
}

@MainActor
struct DistributionTemplateManagementQueryUseCase {
    private let transactionFormQueryUseCase: TransactionFormQueryUseCase

    init(transactionFormQueryUseCase: TransactionFormQueryUseCase) {
        self.transactionFormQueryUseCase = transactionFormQueryUseCase
    }

    init(modelContext: ModelContext) {
        self.init(transactionFormQueryUseCase: TransactionFormQueryUseCase(modelContext: modelContext))
    }

    func snapshot() throws -> DistributionTemplateManagementSnapshot {
        let formSnapshot = try transactionFormQueryUseCase.snapshot()
        return DistributionTemplateManagementSnapshot(
            businessId: formSnapshot.businessId,
            sortedProjects: formSnapshot.projects.sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        )
    }

    func projectName(id: UUID, snapshot: DistributionTemplateManagementSnapshot) -> String? {
        snapshot.sortedProjects.first { $0.id == id }?.name
    }
}
