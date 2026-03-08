import Foundation

/// バンドル内 JSON からTaxYearPackをロードする実装
final class BundledTaxYearPackProvider: TaxYearPackProviderPort, @unchecked Sendable {

    private let bundle: Bundle
    private let fileManager = FileManager.default
    private var cache: [Int: TaxYearPack] = [:]

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func pack(for taxYear: Int) async throws -> TaxYearPack {
        if let cached = cache[taxYear] {
            return cached
        }

        guard let url = profileURL(for: taxYear) else {
            throw TaxYearPackError.packNotFound(taxYear: taxYear)
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pack: TaxYearPack
        do {
            pack = try decoder.decode(TaxYearPack.self, from: data)
        } catch {
            throw TaxYearPackError.invalidPackData(
                taxYear: taxYear,
                reason: error.localizedDescription
            )
        }
        cache[taxYear] = pack
        return pack
    }

    func availableYears() async -> [Int] {
        availableYearsSync()
    }

    func hasPack(for taxYear: Int) async -> Bool {
        hasPackSync(for: taxYear)
    }

    /// 同期呼び出し用: 利用可能年分一覧
    func availableYearsSync() -> [Int] {
        guard let packsRoot = taxYearPacksRootURL() else { return [] }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: packsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let years = contents.compactMap { directoryURL -> Int? in
            guard let year = Int(directoryURL.lastPathComponent) else { return nil }
            let profileURL = directoryURL.appendingPathComponent("profile.json")
            return fileManager.fileExists(atPath: profileURL.path) ? year : nil
        }
        return years.sorted()
    }

    /// 同期呼び出し用: 指定年分のパック存在確認
    func hasPackSync(for taxYear: Int) -> Bool {
        availableYearsSync().contains(taxYear)
    }

    func packSync(for taxYear: Int) throws -> TaxYearPack {
        if let cached = cache[taxYear] {
            return cached
        }

        guard let url = profileURL(for: taxYear) else {
            throw TaxYearPackError.packNotFound(taxYear: taxYear)
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pack: TaxYearPack
        do {
            pack = try decoder.decode(TaxYearPack.self, from: data)
        } catch {
            throw TaxYearPackError.invalidPackData(
                taxYear: taxYear,
                reason: error.localizedDescription
            )
        }
        cache[taxYear] = pack
        return pack
    }

    // MARK: - Helpers

    private func profileURL(for taxYear: Int) -> URL? {
        if let bundled = bundle.url(
            forResource: "profile",
            withExtension: "json",
            subdirectory: "TaxYearPacks/\(taxYear)"
        ) {
            return bundled
        }
        guard let packsRoot = taxYearPacksRootURL() else { return nil }
        let fallback = packsRoot
            .appendingPathComponent(String(taxYear), isDirectory: true)
            .appendingPathComponent("profile.json")
        return fileManager.fileExists(atPath: fallback.path) ? fallback : nil
    }

    private func taxYearPacksRootURL() -> URL? {
        if let resourceURL = bundle.resourceURL {
            let bundledRoot = resourceURL.appendingPathComponent("TaxYearPacks", isDirectory: true)
            if fileManager.fileExists(atPath: bundledRoot.path) {
                return bundledRoot
            }
        }

        // テスト時は bundle に TaxYearPacks が展開されない場合があるため、
        // ソースツリー上の Resources/TaxYearPacks も探索対象に含める。
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TaxYearPack
            .deletingLastPathComponent() // Infrastructure
            .deletingLastPathComponent() // ProjectProfit
        let sourcePacks = sourceRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("TaxYearPacks", isDirectory: true)

        return fileManager.fileExists(atPath: sourcePacks.path) ? sourcePacks : nil
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
