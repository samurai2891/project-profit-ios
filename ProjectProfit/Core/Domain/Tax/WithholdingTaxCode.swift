import Foundation

/// 源泉徴収税の区分コード
/// 所得税法第204条に基づく報酬・料金等の源泉徴収区分
enum WithholdingTaxCode: String, Codable, Hashable, CaseIterable, Sendable {
    /// デザイン料（原稿料・デザイン料等）
    case designFee = "WH-DESIGN"
    /// 原稿料・執筆料
    case writingFee = "WH-WRITING"
    /// 講演料
    case lectureFee = "WH-LECTURE"
    /// 弁護士・税理士等の報酬
    case professionalFee = "WH-PROFESSIONAL"
    /// 芸能・スポーツ等の報酬
    case performanceFee = "WH-PERFORMANCE"
    /// その他の報酬・料金
    case other = "WH-OTHER"

    /// 日本語表示名
    var displayName: String {
        switch self {
        case .designFee:
            return "デザイン料"
        case .writingFee:
            return "原稿料・執筆料"
        case .lectureFee:
            return "講演料"
        case .professionalFee:
            return "弁護士・税理士等報酬"
        case .performanceFee:
            return "芸能・スポーツ等報酬"
        case .other:
            return "その他報酬・料金"
        }
    }

    /// 100万円以下に適用される標準税率（10.21%）
    var standardRate: Decimal {
        Decimal(string: "0.1021")!
    }

    /// 100万円超過分に適用される税率（20.42%）
    var excessRate: Decimal {
        Decimal(string: "0.2042")!
    }

    /// 超過税率が適用される基準額（100万円）
    var threshold: Decimal {
        Decimal(1_000_000)
    }

    /// 支払調書の区分コード（e-Tax用）
    var legalReportCategory: String {
        switch self {
        case .designFee:
            return "デザインの報酬"
        case .writingFee:
            return "原稿の報酬"
        case .lectureFee:
            return "講演の報酬"
        case .professionalFee:
            return "弁護士等の報酬"
        case .performanceFee:
            return "芸能人の報酬"
        case .other:
            return "その他の報酬"
        }
    }

    static func resolve(id: String?) -> WithholdingTaxCode? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            return nil
        }
        return WithholdingTaxCode(rawValue: id)
    }
}
