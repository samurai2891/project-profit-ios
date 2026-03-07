import Foundation

/// 事業者プロフィールの永続化インターフェース
protocol BusinessProfileRepository: Sendable {
    func findById(_ id: UUID) async throws -> BusinessProfile?
    func findDefault() async throws -> BusinessProfile?
    func save(_ profile: BusinessProfile) async throws
    func delete(_ id: UUID) async throws
}
