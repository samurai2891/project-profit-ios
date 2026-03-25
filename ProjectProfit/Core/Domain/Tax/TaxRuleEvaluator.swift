import Foundation

/// 税務ルール評価器
/// 年分プロフィールと取引情報から適用される税務ルールを決定する
struct TaxRuleEvaluator: Sendable {

    private static let twoTenthsCreditRate = Decimal(string: "0.8")!

    let profile: TaxYearProfile
    let pack: TaxYearPack?

    init(profile: TaxYearProfile, pack: TaxYearPack? = nil) {
        self.profile = profile
        self.pack = pack
    }

    func inputTaxDeductionCalculationMode() -> InputTaxDeductionCalculationMode {
        guard profile.isTaxable else {
            return .lineBased
        }

        if profile.isTwoTenthsSpecial && (pack?.twoTenthsSpecialAvailable ?? true) {
            return .twoTenths(creditRate: Self.twoTenthsCreditRate)
        }

        if profile.isSimplifiedTaxation {
            guard let deemedPurchaseRate = simplifiedDeemedPurchaseRate else {
                return .reviewRequired
            }
            return .simplified(deemedPurchaseRate: deemedPurchaseRate)
        }

        return .lineBased
    }

    /// 仕入税額控除の判定と控除計算モードの解決
    func evaluateInputTaxDeductionDecision(
        transactionDate: Date,
        counterpartyInvoiceStatus: InvoiceIssuerStatus,
        amount: Decimal
    ) -> InputTaxDeductionDecision {
        guard profile.isTaxable else {
            return makeDecision(
                creditMethod: .notApplicable,
                calculationMode: .lineBased,
                creditRate: 0,
                deemedPurchaseRate: nil,
                requiresReview: false
            )
        }

        switch inputTaxDeductionCalculationMode() {
        case .twoTenths(let creditRate):
            return makeDecision(
                creditMethod: .twoTenthsEstimate,
                calculationMode: .twoTenths(creditRate: creditRate),
                creditRate: creditRate,
                deemedPurchaseRate: nil,
                requiresReview: false
            )
        case .simplified(let deemedPurchaseRate):
            return makeDecision(
                creditMethod: .simplifiedEstimate,
                calculationMode: .simplified(deemedPurchaseRate: deemedPurchaseRate),
                creditRate: deemedPurchaseRate,
                deemedPurchaseRate: deemedPurchaseRate,
                requiresReview: false
            )
        case .reviewRequired:
            return makeDecision(
                creditMethod: .requiresReview,
                calculationMode: .reviewRequired,
                creditRate: 0,
                deemedPurchaseRate: nil,
                requiresReview: true
            )
        case .lineBased:
            let method = evaluateLineBasedCreditMethod(
                transactionDate: transactionDate,
                counterpartyInvoiceStatus: counterpartyInvoiceStatus,
                amount: amount
            )
            return makeDecision(
                creditMethod: method,
                calculationMode: .lineBased,
                creditRate: Self.creditRate(for: method),
                deemedPurchaseRate: nil,
                requiresReview: method == .requiresReview
            )
        }
    }

    /// 消費税率の判定
    func evaluateTaxRate(
        isReducedRate: Bool
    ) -> TaxRateBreakdown {
        if isReducedRate {
            return TaxRateBreakdown(
                totalRate: pack?.consumptionTaxReducedRate ?? Decimal(string: "0.08")!,
                nationalRate: pack?.nationalRateReduced ?? Decimal(string: "0.0624")!,
                localRate: pack?.localRateReduced ?? Decimal(string: "0.0176")!
            )
        } else {
            return TaxRateBreakdown(
                totalRate: pack?.consumptionTaxStandardRate ?? Decimal(string: "0.10")!,
                nationalRate: pack?.nationalRateStandard ?? Decimal(string: "0.078")!,
                localRate: pack?.localRateStandard ?? Decimal(string: "0.022")!
            )
        }
    }

    private var simplifiedDeemedPurchaseRate: Decimal? {
        guard let category = profile.simplifiedBusinessCategory else {
            return nil
        }
        let rates = pack?.simplifiedDeemedPurchaseRates ?? TaxYearPack.defaultSimplifiedDeemedPurchaseRates
        return rates[category]
    }

    private func makeDecision(
        creditMethod: InputTaxCreditMethod,
        calculationMode: InputTaxDeductionCalculationMode,
        creditRate: Decimal,
        deemedPurchaseRate: Decimal?,
        requiresReview: Bool
    ) -> InputTaxDeductionDecision {
        InputTaxDeductionDecision(
            creditMethod: creditMethod,
            calculationMode: calculationMode,
            creditRate: creditRate,
            deemedPurchaseRate: deemedPurchaseRate,
            requiresReview: requiresReview
        )
    }

    private func evaluateLineBasedCreditMethod(
        transactionDate: Date,
        counterpartyInvoiceStatus: InvoiceIssuerStatus,
        amount: Decimal
    ) -> InputTaxCreditMethod {
        switch counterpartyInvoiceStatus {
        case .registered:
            return .qualifiedInvoice
        case .unregistered:
            return evaluateTransitionalCredit(transactionDate: transactionDate, amount: amount)
        case .unknown:
            return .requiresReview
        }
    }

    /// 経過措置の判定
    private func evaluateTransitionalCredit(
        transactionDate: Date,
        amount: Decimal
    ) -> InputTaxCreditMethod {
        if amount < (pack?.smallAmountThreshold ?? 10000) {
            return .smallAmountSpecial
        }

        let measures = (pack?.transitionalMeasures ?? TransitionalTaxCreditMeasure.defaultMeasures)
            .sorted { $0.periodStart < $1.periodStart }
        for measure in measures where measure.periodStart <= transactionDate && transactionDate <= measure.periodEnd {
            switch measure.id {
            case "transitional_80":
                return .transitional80
            case "transitional_50":
                return .transitional50
            default:
                if measure.creditRate == Decimal(string: "0.8") {
                    return .transitional80
                }
                if measure.creditRate == Decimal(string: "0.5") {
                    return .transitional50
                }
            }
        }

        return .notDeductible
    }

    private static func creditRate(for method: InputTaxCreditMethod) -> Decimal {
        switch method {
        case .qualifiedInvoice, .simplifiedQualifiedInvoice, .smallAmountSpecial:
            return Decimal(1)
        case .transitional80:
            return Decimal(string: "0.8")!
        case .transitional50:
            return Decimal(string: "0.5")!
        case .notDeductible, .notApplicable, .requiresReview, .simplifiedEstimate, .twoTenthsEstimate:
            return 0
        }
    }
}

/// 仕入税額控除方式
enum InputTaxCreditMethod: String, Codable, Sendable {
    /// 適格請求書（100%控除）
    case qualifiedInvoice
    /// 簡易適格請求書（100%控除）
    case simplifiedQualifiedInvoice
    /// 少額特例（税込1万円未満、100%控除）
    case smallAmountSpecial
    /// 経過措置80%控除
    case transitional80
    /// 経過措置50%控除
    case transitional50
    /// 控除不可
    case notDeductible
    /// 簡易課税みなし仕入率
    case simplifiedEstimate
    /// 2割特例概算控除
    case twoTenthsEstimate
    /// 適用外（免税事業者）
    case notApplicable
    /// 確認が必要
    case requiresReview

    var displayName: String {
        switch self {
        case .qualifiedInvoice: "適格請求書（100%控除）"
        case .simplifiedQualifiedInvoice: "簡易適格請求書（100%控除）"
        case .smallAmountSpecial: "少額特例（100%控除）"
        case .transitional80: "経過措置（80%控除）"
        case .transitional50: "経過措置（50%控除）"
        case .notDeductible: "控除不可"
        case .simplifiedEstimate: "簡易課税（みなし仕入率）"
        case .twoTenthsEstimate: "2割特例"
        case .notApplicable: "適用外"
        case .requiresReview: "要確認"
        }
    }
}

/// 消費税率の内訳（国税・地方税分離保持）
struct TaxRateBreakdown: Codable, Sendable, Equatable {
    let totalRate: Decimal
    let nationalRate: Decimal
    let localRate: Decimal
}
