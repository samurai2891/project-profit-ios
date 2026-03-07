import Foundation

/// 年分別税制パック
/// 年度ごとの税率、帳票フィールド、e-Tax 仕様、特例ルールを pack 化
/// if文連鎖で年度差分を処理する代わりに、データ駆動で切り替える
struct TaxYearPack: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let taxYear: Int
    let version: String
    let incomeTaxRateBrackets: [IncomeTaxBracket]
    let consumptionTaxStandardRate: Decimal
    let consumptionTaxReducedRate: Decimal
    let nationalRateStandard: Decimal
    let localRateStandard: Decimal
    let nationalRateReduced: Decimal
    let localRateReduced: Decimal
    let smallAmountThreshold: Decimal
    let transitionalCreditRate: Decimal?
    let twoTenthsSpecialAvailable: Bool
    let blueDeductionOptions: [BlueDeductionLevel]
    let filingDeadlineMonth: Int
    let filingDeadlineDay: Int
    let releaseDate: Date
    let effectiveFrom: Date
    let deprecatedAt: Date?

    fileprivate enum CodingKeys: String, CodingKey {
        case id
        case taxYear
        case version
        case incomeTaxRateBrackets
        case consumptionTaxStandardRate
        case consumptionTaxReducedRate
        case nationalRateStandard
        case localRateStandard
        case nationalRateReduced
        case localRateReduced
        case smallAmountThreshold
        case transitionalCreditRate
        case twoTenthsSpecialAvailable
        case blueDeductionOptions
        case filingDeadlineMonth
        case filingDeadlineDay
        case releaseDate
        case effectiveFrom
        case deprecatedAt
    }

    init(
        id: UUID = UUID(),
        taxYear: Int,
        version: String,
        incomeTaxRateBrackets: [IncomeTaxBracket] = [],
        consumptionTaxStandardRate: Decimal = Decimal(string: "0.10")!,
        consumptionTaxReducedRate: Decimal = Decimal(string: "0.08")!,
        nationalRateStandard: Decimal = Decimal(string: "0.078")!,
        localRateStandard: Decimal = Decimal(string: "0.022")!,
        nationalRateReduced: Decimal = Decimal(string: "0.0624")!,
        localRateReduced: Decimal = Decimal(string: "0.0176")!,
        smallAmountThreshold: Decimal = 10000,
        transitionalCreditRate: Decimal? = nil,
        twoTenthsSpecialAvailable: Bool = true,
        blueDeductionOptions: [BlueDeductionLevel] = BlueDeductionLevel.allCases,
        filingDeadlineMonth: Int = 3,
        filingDeadlineDay: Int = 15,
        releaseDate: Date = Date(),
        effectiveFrom: Date = Date(),
        deprecatedAt: Date? = nil
    ) {
        self.id = id
        self.taxYear = taxYear
        self.version = version
        self.incomeTaxRateBrackets = incomeTaxRateBrackets
        self.consumptionTaxStandardRate = consumptionTaxStandardRate
        self.consumptionTaxReducedRate = consumptionTaxReducedRate
        self.nationalRateStandard = nationalRateStandard
        self.localRateStandard = localRateStandard
        self.nationalRateReduced = nationalRateReduced
        self.localRateReduced = localRateReduced
        self.smallAmountThreshold = smallAmountThreshold
        self.transitionalCreditRate = transitionalCreditRate
        self.twoTenthsSpecialAvailable = twoTenthsSpecialAvailable
        self.blueDeductionOptions = blueDeductionOptions
        self.filingDeadlineMonth = filingDeadlineMonth
        self.filingDeadlineDay = filingDeadlineDay
        self.releaseDate = releaseDate
        self.effectiveFrom = effectiveFrom
        self.deprecatedAt = deprecatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let taxYear = try container.decode(Int.self, forKey: .taxYear)
        let defaultEffectiveDate = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: taxYear, month: 1, day: 1)
        ) ?? Date(timeIntervalSince1970: 0)

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.taxYear = taxYear
        self.version = try container.decode(String.self, forKey: .version)
        self.incomeTaxRateBrackets = try container.decodeIfPresent([IncomeTaxBracket].self, forKey: .incomeTaxRateBrackets) ?? []
        self.consumptionTaxStandardRate = try container.decodeDecimalIfPresent(forKey: .consumptionTaxStandardRate) ?? Decimal(string: "0.10")!
        self.consumptionTaxReducedRate = try container.decodeDecimalIfPresent(forKey: .consumptionTaxReducedRate) ?? Decimal(string: "0.08")!
        self.nationalRateStandard = try container.decodeDecimalIfPresent(forKey: .nationalRateStandard) ?? Decimal(string: "0.078")!
        self.localRateStandard = try container.decodeDecimalIfPresent(forKey: .localRateStandard) ?? Decimal(string: "0.022")!
        self.nationalRateReduced = try container.decodeDecimalIfPresent(forKey: .nationalRateReduced) ?? Decimal(string: "0.0624")!
        self.localRateReduced = try container.decodeDecimalIfPresent(forKey: .localRateReduced) ?? Decimal(string: "0.0176")!
        self.smallAmountThreshold = try container.decodeDecimalIfPresent(forKey: .smallAmountThreshold) ?? 10000
        self.transitionalCreditRate = try container.decodeDecimalIfPresent(forKey: .transitionalCreditRate)
        self.twoTenthsSpecialAvailable = try container.decodeIfPresent(Bool.self, forKey: .twoTenthsSpecialAvailable) ?? true
        self.blueDeductionOptions = try container.decodeBlueDeductionOptionsIfPresent(forKey: .blueDeductionOptions) ?? BlueDeductionLevel.allCases
        self.filingDeadlineMonth = try container.decodeIfPresent(Int.self, forKey: .filingDeadlineMonth) ?? 3
        self.filingDeadlineDay = try container.decodeIfPresent(Int.self, forKey: .filingDeadlineDay) ?? 15
        self.releaseDate = try container.decodeIfPresent(Date.self, forKey: .releaseDate) ?? defaultEffectiveDate
        self.effectiveFrom = try container.decodeIfPresent(Date.self, forKey: .effectiveFrom) ?? defaultEffectiveDate
        self.deprecatedAt = try container.decodeIfPresent(Date.self, forKey: .deprecatedAt)
    }
}

/// 所得税率ブラケット
struct IncomeTaxBracket: Codable, Sendable, Equatable {
    let lowerBound: Decimal
    let upperBound: Decimal?
    let rate: Decimal
    let deduction: Decimal

    fileprivate enum CodingKeys: String, CodingKey {
        case lowerBound
        case upperBound
        case rate
        case deduction
    }

    init(
        lowerBound: Decimal,
        upperBound: Decimal?,
        rate: Decimal,
        deduction: Decimal
    ) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.rate = rate
        self.deduction = deduction
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.lowerBound = try container.decodeDecimal(forKey: .lowerBound)
        self.upperBound = try container.decodeDecimalIfPresent(forKey: .upperBound)
        self.rate = try container.decodeDecimal(forKey: .rate)
        self.deduction = try container.decodeDecimal(forKey: .deduction)
    }
}

private extension KeyedDecodingContainer where Key == TaxYearPack.CodingKeys {
    func decodeDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        do {
            if let string = try decodeIfPresent(String.self, forKey: key),
               let value = Decimal(string: string) {
                return value
            }
        } catch {}

        do {
            if let doubleValue = try decodeIfPresent(Double.self, forKey: key) {
                return Decimal(doubleValue)
            }
        } catch {}

        do {
            if let intValue = try decodeIfPresent(Int.self, forKey: key) {
                return Decimal(intValue)
            }
        } catch {}

        do {
            if let decimal = try decodeIfPresent(Decimal.self, forKey: key) {
                return decimal
            }
        } catch {}

        return nil
    }

    func decodeBlueDeductionOptionsIfPresent(forKey key: Key) throws -> [BlueDeductionLevel]? {
        do {
            if let rawNames = try decodeIfPresent([String].self, forKey: key) {
                return rawNames.compactMap(BlueDeductionLevel.init(packToken:))
            }
        } catch {}

        do {
            if let rawValues = try decodeIfPresent([Int].self, forKey: key) {
                return rawValues.compactMap(BlueDeductionLevel.init(rawValue:))
            }
        } catch {}

        do {
            if let decoded = try decodeIfPresent([BlueDeductionLevel].self, forKey: key) {
                return decoded
            }
        } catch {}

        return nil
    }
}

private extension KeyedDecodingContainer where Key == IncomeTaxBracket.CodingKeys {
    func decodeDecimal(forKey key: Key) throws -> Decimal {
        if let value = try decodeDecimalIfPresent(forKey: key) {
            return value
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Decimal value is missing or invalid."
        )
    }

    func decodeDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        do {
            if let string = try decodeIfPresent(String.self, forKey: key),
               let value = Decimal(string: string) {
                return value
            }
        } catch {}

        do {
            if let doubleValue = try decodeIfPresent(Double.self, forKey: key) {
                return Decimal(doubleValue)
            }
        } catch {}

        do {
            if let intValue = try decodeIfPresent(Int.self, forKey: key) {
                return Decimal(intValue)
            }
        } catch {}

        do {
            if let decimal = try decodeIfPresent(Decimal.self, forKey: key) {
                return decimal
            }
        } catch {}

        return nil
    }
}

private extension BlueDeductionLevel {
    init?(packToken: String) {
        switch packToken {
        case "none":
            self = .none
        case "ten":
            self = .ten
        case "fiftyFive":
            self = .fiftyFive
        case "sixtyFive":
            self = .sixtyFive
        default:
            return nil
        }
    }
}
