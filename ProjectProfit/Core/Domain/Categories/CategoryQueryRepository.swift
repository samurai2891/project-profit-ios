import Foundation

struct CategorySnapshot {
    let categories: [PPCategory]
    let accounts: [PPAccount]

    static let empty = CategorySnapshot(
        categories: [],
        accounts: []
    )
}

@MainActor
protocol CategoryQueryRepository {
    func snapshot() throws -> CategorySnapshot
}
