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
}

/// 所得税率ブラケット
struct IncomeTaxBracket: Codable, Sendable, Equatable {
    let lowerBound: Decimal
    let upperBound: Decimal?
    let rate: Decimal
    let deduction: Decimal
}
