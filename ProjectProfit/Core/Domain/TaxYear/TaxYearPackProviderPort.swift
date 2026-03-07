import Foundation

/// TaxYearPack の取得ポート（Core/Domain → Infrastructure 境界）
protocol TaxYearPackProviderPort: Sendable {
    /// 指定年分のパックを取得
    func pack(for taxYear: Int) async throws -> TaxYearPack

    /// 利用可能な全年分を返す
    func availableYears() async -> [Int]

    /// 指定年分のパックが存在するか
    func hasPack(for taxYear: Int) async -> Bool
}
