import Foundation
import SwiftData

@MainActor
final class SwiftDataFixedAssetRepository: FixedAssetRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fixedAsset(id: UUID) throws -> PPFixedAsset? {
        let predicate = #Predicate<PPFixedAsset> { $0.id == id }
        let descriptor = FetchDescriptor<PPFixedAsset>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    func allFixedAssets() throws -> [PPFixedAsset] {
        let descriptor = FetchDescriptor<PPFixedAsset>(
            sortBy: [SortDescriptor(\.acquisitionDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func insert(_ asset: PPFixedAsset) {
        modelContext.insert(asset)
    }

    func delete(_ asset: PPFixedAsset) {
        modelContext.delete(asset)
    }
}
