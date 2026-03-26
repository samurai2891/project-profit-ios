import Foundation
import SwiftData

@MainActor
struct DataRevisionQueryUseCase {
    private let repository: any DataRevisionRepository

    init(repository: any DataRevisionRepository) {
        self.repository = repository
    }

    init(modelContext: ModelContext) {
        self.init(repository: SwiftDataDataRevisionRepository(modelContext: modelContext))
    }

    func dashboardRevisionKey() -> String {
        (try? repository.dashboardRevisionKey()) ?? "dashboard:unavailable"
    }

    func reportRevisionKey() -> String {
        (try? repository.reportRevisionKey()) ?? "report:unavailable"
    }

    func transactionsRevisionKey() -> String {
        (try? repository.transactionsRevisionKey()) ?? "transactions:unavailable"
    }
}
