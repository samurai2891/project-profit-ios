import Foundation

/// 年分別税務プロフィールの永続化インターフェース
protocol TaxYearProfileRepository: Sendable {
    func findById(_ id: UUID) async throws -> TaxYearProfile?
    func findByBusinessAndYear(businessId: UUID, taxYear: Int) async throws -> TaxYearProfile?
    func findAllByBusiness(businessId: UUID) async throws -> [TaxYearProfile]
    func save(_ profile: TaxYearProfile) async throws
    func delete(_ id: UUID) async throws
}
