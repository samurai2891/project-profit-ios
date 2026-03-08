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
            let profilePack = try decoder.decode(TaxYearPack.self, from: data)
            pack = try loadConsumptionTaxRules(for: taxYear, fallback: profilePack)
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
            let profilePack = try decoder.decode(TaxYearPack.self, from: data)
            pack = try loadConsumptionTaxRules(for: taxYear, fallback: profilePack)
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

    private func loadConsumptionTaxRules(for taxYear: Int, fallback profilePack: TaxYearPack) throws -> TaxYearPack {
        guard let rulesURL = bundle.url(
            forResource: "rules",
            withExtension: "json",
            subdirectory: "TaxYearPacks/\(taxYear)/consumption_tax"
        ) ?? taxYearPacksRootURL()?
            .appendingPathComponent(String(taxYear), isDirectory: true)
            .appendingPathComponent("consumption_tax", isDirectory: true)
            .appendingPathComponent("rules.json"),
            fileManager.fileExists(atPath: rulesURL.path)
        else {
            return profilePack
        }

        let rulesData = try Data(contentsOf: rulesURL)
        let decoder = JSONDecoder()
        let rules = try decoder.decode(ConsumptionTaxRules.self, from: rulesData)
        return TaxYearPack(
            id: profilePack.id,
            taxYear: profilePack.taxYear,
            version: profilePack.version,
            incomeTaxRateBrackets: profilePack.incomeTaxRateBrackets,
            consumptionTaxStandardRate: rules.standardRate ?? profilePack.consumptionTaxStandardRate,
            consumptionTaxReducedRate: rules.reducedRate ?? profilePack.consumptionTaxReducedRate,
            nationalRateStandard: rules.nationalRateStandard ?? profilePack.nationalRateStandard,
            localRateStandard: rules.localRateStandard ?? profilePack.localRateStandard,
            nationalRateReduced: rules.nationalRateReduced ?? profilePack.nationalRateReduced,
            localRateReduced: rules.localRateReduced ?? profilePack.localRateReduced,
            smallAmountThreshold: rules.smallAmountThreshold ?? profilePack.smallAmountThreshold,
            transitionalCreditRate: rules.transitionalMeasures.first?.creditRate ?? profilePack.transitionalCreditRate,
            transitionalMeasures: rules.transitionalMeasures.isEmpty ? profilePack.transitionalMeasures : rules.transitionalMeasures,
            twoTenthsSpecialAvailable: rules.twoTenthsSpecialAvailable ?? profilePack.twoTenthsSpecialAvailable,
            blueDeductionOptions: profilePack.blueDeductionOptions,
            filingDeadlineMonth: profilePack.filingDeadlineMonth,
            filingDeadlineDay: profilePack.filingDeadlineDay,
            releaseDate: profilePack.releaseDate,
            effectiveFrom: profilePack.effectiveFrom,
            deprecatedAt: profilePack.deprecatedAt
        )
    }
}

private struct ConsumptionTaxRules: Decodable {
    let standardRate: Decimal?
    let reducedRate: Decimal?
    let nationalRateStandard: Decimal?
    let localRateStandard: Decimal?
    let nationalRateReduced: Decimal?
    let localRateReduced: Decimal?
    let transitionalMeasures: [TransitionalTaxCreditMeasure]
    let smallAmountThreshold: Decimal?
    let twoTenthsSpecialAvailable: Bool?

    private enum CodingKeys: String, CodingKey {
        case standardRate
        case reducedRate
        case nationalRateStandard
        case localRateStandard
        case nationalRateReduced
        case localRateReduced
        case transitionalMeasures
        case specialProvisions
    }

    private struct SpecialProvision: Decodable {
        let id: String
        let available: Bool?
        let threshold: Decimal?

        private enum CodingKeys: String, CodingKey {
            case id
            case available
            case threshold
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            available = try container.decodeIfPresent(Bool.self, forKey: .available)
            threshold = try container.decodeDecimalIfPresent(forKey: .threshold)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        standardRate = try container.decodeDecimalIfPresent(forKey: .standardRate)
        reducedRate = try container.decodeDecimalIfPresent(forKey: .reducedRate)
        nationalRateStandard = try container.decodeDecimalIfPresent(forKey: .nationalRateStandard)
        localRateStandard = try container.decodeDecimalIfPresent(forKey: .localRateStandard)
        nationalRateReduced = try container.decodeDecimalIfPresent(forKey: .nationalRateReduced)
        localRateReduced = try container.decodeDecimalIfPresent(forKey: .localRateReduced)
        transitionalMeasures = try container.decodeIfPresent([TransitionalTaxCreditMeasure].self, forKey: .transitionalMeasures) ?? []

        let provisions = try container.decodeIfPresent([SpecialProvision].self, forKey: .specialProvisions) ?? []
        smallAmountThreshold = provisions.first(where: { $0.id == "small_amount_special" })?.threshold
        twoTenthsSpecialAvailable = provisions.first(where: { $0.id == "two_tenths_special" })?.available
    }
}

private extension KeyedDecodingContainer {
    func decodeDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        if let stringValue = try decodeIfPresent(String.self, forKey: key),
           let decimal = Decimal(string: stringValue) {
            return decimal
        }
        if let decimal = try decodeIfPresent(Decimal.self, forKey: key) {
            return decimal
        }
        if let doubleValue = try decodeIfPresent(Double.self, forKey: key) {
            return Decimal(doubleValue)
        }
        if let intValue = try decodeIfPresent(Int.self, forKey: key) {
            return Decimal(intValue)
        }
        return nil
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
