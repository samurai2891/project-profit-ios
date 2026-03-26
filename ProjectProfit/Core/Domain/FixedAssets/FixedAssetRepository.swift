import Foundation

@MainActor
protocol FixedAssetRepository {
    func fixedAsset(id: UUID) throws -> PPFixedAsset?
    func allFixedAssets() throws -> [PPFixedAsset]
    func insert(_ asset: PPFixedAsset)
    func delete(_ asset: PPFixedAsset)
}
