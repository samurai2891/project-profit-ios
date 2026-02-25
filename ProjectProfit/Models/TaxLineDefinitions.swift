import Foundation

/// e-Tax 確定申告書の経費区分（TaxLine）
enum TaxLine: String, Codable, CaseIterable, Identifiable {
    // 収入
    case salesRevenue       = "sales_revenue"       // ア 売上（収入）金額
    case otherIncome        = "other_income"         // カ 雑収入

    // 経費 — e-Tax 12区分
    case rentExpense        = "rent"                 // 地代家賃
    case utilitiesExpense   = "utilities"            // 水道光熱費
    case travelExpense      = "travel"               // 旅費交通費
    case communicationExpense = "communication"      // 通信費
    case advertisingExpense = "advertising"          // 広告宣伝費
    case entertainmentExpense = "entertainment"      // 接待交際費
    case depreciationExpense = "depreciation"        // 減価償却費
    case repairExpense      = "repair"               // 修繕費
    case suppliesExpense    = "supplies"             // 消耗品費
    case welfareExpense     = "welfare"              // 福利厚生費
    case outsourcingExpense = "outsourcing"          // 外注工賃
    case miscExpense        = "misc"                 // 雑費

    var id: String { rawValue }

    var label: String {
        switch self {
        case .salesRevenue: "売上（収入）金額"
        case .otherIncome: "雑収入"
        case .rentExpense: "地代家賃"
        case .utilitiesExpense: "水道光熱費"
        case .travelExpense: "旅費交通費"
        case .communicationExpense: "通信費"
        case .advertisingExpense: "広告宣伝費"
        case .entertainmentExpense: "接待交際費"
        case .depreciationExpense: "減価償却費"
        case .repairExpense: "修繕費"
        case .suppliesExpense: "消耗品費"
        case .welfareExpense: "福利厚生費"
        case .outsourcingExpense: "外注工賃"
        case .miscExpense: "雑費"
        }
    }

    var isRevenue: Bool {
        switch self {
        case .salesRevenue, .otherIncome: true
        default: false
        }
    }

    /// AccountSubtype への対応マッピング
    var accountSubtype: AccountSubtype {
        switch self {
        case .salesRevenue: .salesRevenue
        case .otherIncome: .otherIncome
        case .rentExpense: .rentExpense
        case .utilitiesExpense: .utilitiesExpense
        case .travelExpense: .travelExpense
        case .communicationExpense: .communicationExpense
        case .advertisingExpense: .advertisingExpense
        case .entertainmentExpense: .entertainmentExpense
        case .depreciationExpense: .depreciationExpense
        case .repairExpense: .repairExpense
        case .suppliesExpense: .suppliesExpense
        case .welfareExpense: .welfareExpense
        case .outsourcingExpense: .outsourcingExpense
        case .miscExpense: .miscExpense
        }
    }
}
