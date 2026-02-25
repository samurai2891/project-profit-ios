import Foundation

// MARK: - e-Tax Field

enum EtaxFieldValue: Equatable {
    case number(Int)
    case text(String)
    case flag(Bool)

    var numberValue: Int? {
        if case .number(let value) = self {
            return value
        }
        return nil
    }

    var exportText: String {
        switch self {
        case .number(let value):
            return String(value)
        case .text(let value):
            return value
        case .flag(let value):
            return value ? "1" : "0"
        }
    }

    var previewText: String {
        switch self {
        case .number(let value):
            return formatCurrency(value)
        case .text(let value):
            return value
        case .flag(let value):
            return value ? "あり" : "なし"
        }
    }
}

/// e-Tax申告書の1フィールド
struct EtaxField: Identifiable {
    let id: String           // internalKey: e.g. "ketsusan_uriage"
    let fieldLabel: String   // e-Tax上の表示ラベル: e.g. "ア 売上（収入）金額"
    let taxLine: TaxLine?    // 対応するTaxLine（計算フィールドはnil）
    var value: EtaxFieldValue
    let section: EtaxSection

    init(
        id: String,
        fieldLabel: String,
        taxLine: TaxLine?,
        value: EtaxFieldValue,
        section: EtaxSection
    ) {
        self.id = id
        self.fieldLabel = fieldLabel
        self.taxLine = taxLine
        self.value = value
        self.section = section
    }

    init(
        id: String,
        fieldLabel: String,
        taxLine: TaxLine?,
        value: Int,
        section: EtaxSection
    ) {
        self.init(id: id, fieldLabel: fieldLabel, taxLine: taxLine, value: .number(value), section: section)
    }

    init(
        id: String,
        fieldLabel: String,
        taxLine: TaxLine?,
        value: String,
        section: EtaxSection
    ) {
        self.init(id: id, fieldLabel: fieldLabel, taxLine: taxLine, value: .text(value), section: section)
    }

    init(
        id: String,
        fieldLabel: String,
        taxLine: TaxLine?,
        value: Bool,
        section: EtaxSection
    ) {
        self.init(id: id, fieldLabel: fieldLabel, taxLine: taxLine, value: .flag(value), section: section)
    }
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
        fields
            .filter { $0.section == .revenue }
            .reduce(0) { $0 + ($1.value.numberValue ?? 0) }
    }

    var totalExpenses: Int {
        fields
            .filter { $0.section == .expenses }
            .reduce(0) { $0 + ($1.value.numberValue ?? 0) }
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

enum EtaxFieldDataType: String, Codable {
    case number
    case text
    case flag
}

struct TaxFieldDefinition: Codable {
    let internalKey: String
    let fieldLabel: String
    let xmlTag: String?
    let taxLineRawValue: String?  // TaxLine.rawValue or nil for calculated fields
    let section: String
    let dataType: EtaxFieldDataType?
}

// MARK: - Export Error

enum EtaxExportError: Error, CustomStringConvertible {
    case noData
    case invalidCharacter(field: String, character: Character)
    case missingRequiredField(field: String)
    case unsupportedTaxYear(year: Int)
    case missingXmlTag(internalKey: String)
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
        case .unsupportedTaxYear(let year):
            return "\(year)年分のe-Tax定義に未対応です"
        case .missingXmlTag(let internalKey):
            return "内部キー「\(internalKey)」のxmlTag定義がありません"
        case .validationFailed(let reasons):
            return "バリデーションエラー: \(reasons.joined(separator: ", "))"
        case .xmlGenerationFailed(let error):
            return "XML生成エラー: \(error.localizedDescription)"
        }
    }
}
