import Foundation

/// 税務ルール評価器
/// 年分プロフィールと取引情報から適用される税務ルールを決定する
struct TaxRuleEvaluator: Sendable {

    let profile: TaxYearProfile
    let pack: TaxYearPack?

    init(profile: TaxYearProfile, pack: TaxYearPack? = nil) {
        self.profile = profile
        self.pack = pack
    }

    /// 仕入税額控除の方式を判定
    func evaluateInputTaxCreditMethod(
        transactionDate: Date,
        counterpartyInvoiceStatus: InvoiceIssuerStatus,
        amount: Decimal
    ) -> InputTaxCreditMethod {
        // 免税事業者は控除なし
        guard profile.isTaxable else {
            return .notApplicable
        }

        // 2割特例の場合は概算控除
        if profile.isTwoTenthsSpecial && (pack?.twoTenthsSpecialAvailable ?? true) {
            return .twoTenthsEstimate
        }

        // 簡易課税の場合はみなし仕入率
        if profile.isSimplifiedTaxation {
            return .simplifiedEstimate
        }

        // 一般課税: インボイスの有無で判定
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
        // 少額特例: 税込1万円未満（基準期間の課税売上高1億円以下）
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

        // 経過措置終了後: 控除不可
        return .notDeductible
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

    /// 控除率（%）
    var creditRate: Decimal {
        switch self {
        case .qualifiedInvoice, .simplifiedQualifiedInvoice, .smallAmountSpecial:
            return Decimal(1)
        case .transitional80:
            return Decimal(string: "0.8")!
        case .transitional50:
            return Decimal(string: "0.5")!
        case .notDeductible, .notApplicable, .requiresReview:
            return Decimal(0)
        case .simplifiedEstimate, .twoTenthsEstimate:
            return Decimal(0)  // 別途計算
        }
    }

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
