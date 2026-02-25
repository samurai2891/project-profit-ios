import Foundation

// MARK: - e-Tax Field

/// e-Tax申告書の1フィールド
struct EtaxField: Identifiable {
    let id: String           // internalKey: e.g. "ketsusan_uriage"
    let fieldLabel: String   // e-Tax上の表示ラベル: e.g. "ア 売上（収入）金額"
    let taxLine: TaxLine?    // 対応するTaxLine（計算フィールドはnil）
    var value: Int            // 金額（円）
    let section: EtaxSection
}

enum EtaxSection: String, CaseIterable {
    case revenue = "収入金額"
    case expenses = "必要経費"
    case income = "所得金額"
    case deductions = "各種控除"
    case declarantInfo = "申告者情報"
    case inventory = "棚卸"
    case fixedAssetSchedule = "固定資産明細"
    case balanceSheet = "貸借対照表"
}

// MARK: - e-Tax Form

/// e-Tax申告書1セットの全フィールド
struct EtaxForm {
    let fiscalYear: Int
    let formType: EtaxFormType
    var fields: [EtaxField]
    let generatedAt: Date

    var totalRevenue: Int {
        fields.filter { $0.section == .revenue }.reduce(0) { $0 + $1.value }
    }

    var totalExpenses: Int {
        fields.filter { $0.section == .expenses }.reduce(0) { $0 + $1.value }
    }

    var netIncome: Int { totalRevenue - totalExpenses }
}

enum EtaxFormType: String {
    case blueReturn = "青色申告決算書"
    case whiteReturn = "白色収支内訳書"
}

// MARK: - Tax Year Definition

/// 年度別のTaxLine→フィールドラベル定義
struct TaxYearDefinition: Codable {
    let fiscalYear: Int
    let fields: [TaxFieldDefinition]
}

struct TaxFieldDefinition: Codable {
    let internalKey: String
    let fieldLabel: String
    let taxLineRawValue: String?  // TaxLine.rawValue or nil for calculated fields
    let section: String
}

// MARK: - Export Error

enum EtaxExportError: Error, CustomStringConvertible {
    case noData
    case invalidCharacter(field: String, character: Character)
    case missingRequiredField(field: String)
    case validationFailed(reasons: [String])
    case xmlGenerationFailed(underlying: Error)

    var description: String {
        switch self {
        case .noData:
            return "出力するデータがありません"
        case .invalidCharacter(let field, let char):
            return "フィールド「\(field)」に使用できない文字「\(char)」が含まれています"
        case .missingRequiredField(let field):
            return "必須フィールド「\(field)」が未入力です"
        case .validationFailed(let reasons):
            return "バリデーションエラー: \(reasons.joined(separator: ", "))"
        case .xmlGenerationFailed(let error):
            return "XML生成エラー: \(error.localizedDescription)"
        }
    }
}
