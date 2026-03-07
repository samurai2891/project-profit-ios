import Foundation

/// canonical な消費税区分マスタ
/// legacy `TaxCategory` と既存の `defaultTaxCodeId` をこの識別子へ寄せる。
enum TaxCode: String, Codable, CaseIterable, Sendable {
    case standard10 = "TAX-10"
    case reduced8 = "TAX-8"
    case exempt = "TAX-EXEMPT"
    case nonTaxable = "TAX-NON-TAXABLE"

    var displayName: String {
        switch self {
        case .standard10:
            return "課税（10%）"
        case .reduced8:
            return "軽減税率（8%）"
        case .exempt:
            return "非課税"
        case .nonTaxable:
            return "不課税"
        }
    }

    var shortLabel: String {
        switch self {
        case .standard10: "10%"
        case .reduced8: "8%"
        case .exempt: "非課税"
        case .nonTaxable: "不課税"
        }
    }

    var legacyCategory: TaxCategory {
        switch self {
        case .standard10:
            return .standardRate
        case .reduced8:
            return .reducedRate
        case .exempt:
            return .exempt
        case .nonTaxable:
            return .nonTaxable
        }
    }

    var isTaxable: Bool {
        switch self {
        case .standard10, .reduced8:
            return true
        case .exempt, .nonTaxable:
            return false
        }
    }

    var taxRatePercent: Int {
        switch self {
        case .standard10:
            return 10
        case .reduced8:
            return 8
        case .exempt, .nonTaxable:
            return 0
        }
    }

    func rateBreakdown(using pack: TaxYearPack? = nil) -> TaxRateBreakdown {
        switch self {
        case .standard10:
            return TaxRateBreakdown(
                totalRate: pack?.consumptionTaxStandardRate ?? Decimal(string: "0.10")!,
                nationalRate: pack?.nationalRateStandard ?? Decimal(string: "0.078")!,
                localRate: pack?.localRateStandard ?? Decimal(string: "0.022")!
            )
        case .reduced8:
            return TaxRateBreakdown(
                totalRate: pack?.consumptionTaxReducedRate ?? Decimal(string: "0.08")!,
                nationalRate: pack?.nationalRateReduced ?? Decimal(string: "0.0624")!,
                localRate: pack?.localRateReduced ?? Decimal(string: "0.0176")!
            )
        case .exempt, .nonTaxable:
            return TaxRateBreakdown(totalRate: 0, nationalRate: 0, localRate: 0)
        }
    }

    static func resolve(id: String?) -> TaxCode? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            return nil
        }
        return TaxCode(rawValue: id)
    }

    static func resolve(legacyCategory: TaxCategory?, taxRate: Int?) -> TaxCode? {
        if let legacyCategory {
            switch legacyCategory {
            case .standardRate:
                return .standard10
            case .reducedRate:
                return .reduced8
            case .exempt:
                return .exempt
            case .nonTaxable:
                return .nonTaxable
            }
        }

        switch taxRate {
        case 8:
            return .reduced8
        case 10:
            return .standard10
        default:
            return nil
        }
    }
}
