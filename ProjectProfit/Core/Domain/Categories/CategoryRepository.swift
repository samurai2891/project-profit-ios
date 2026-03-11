import Foundation

@MainActor
protocol CategoryRepository {
    func category(id: String) throws -> PPCategory?
    func insert(_ category: PPCategory)
    func delete(_ category: PPCategory)
}
