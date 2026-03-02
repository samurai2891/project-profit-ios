import Foundation

/// バンドル内 JSON からTaxYearPackをロードする実装
final class BundledTaxYearPackProvider: TaxYearPackProviderPort, @unchecked Sendable {

    private let bundle: Bundle
    private var cache: [Int: TaxYearPack] = [:]

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func pack(for taxYear: Int) async throws -> TaxYearPack {
        if let cached = cache[taxYear] {
            return cached
        }

        guard let url = bundle.url(
            forResource: "profile",
            withExtension: "json",
            subdirectory: "TaxYearPacks/\(taxYear)"
        ) else {
            throw TaxYearPackError.packNotFound(taxYear: taxYear)
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pack = try decoder.decode(TaxYearPack.self, from: data)
        cache[taxYear] = pack
        return pack
    }

    func availableYears() async -> [Int] {
        // TaxYearPacks ディレクトリ内のサブフォルダ名から年分を取得
        guard let resourcePath = bundle.resourcePath else { return [] }
        let packsPath = (resourcePath as NSString).appendingPathComponent("TaxYearPacks")
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: packsPath) else {
            return []
        }
        return contents.compactMap { Int($0) }.sorted()
    }

    func hasPack(for taxYear: Int) async -> Bool {
        let years = await availableYears()
        return years.contains(taxYear)
    }
}

/// TaxYearPack ロードエラー
enum TaxYearPackError: Error, LocalizedError {
    case packNotFound(taxYear: Int)
    case invalidPackData(taxYear: Int, reason: String)

    var errorDescription: String? {
        switch self {
        case .packNotFound(let year):
            return "\(year)年分の税制パックが見つかりません"
        case .invalidPackData(let year, let reason):
            return "\(year)年分の税制パックが不正です: \(reason)"
        }
    }
}
