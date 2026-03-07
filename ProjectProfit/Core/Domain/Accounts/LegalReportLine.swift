import Foundation

/// 青色申告決算書の表示行ID
/// 勘定科目がどの決算書行に表示されるかを定義する
enum LegalReportLine: String, CaseIterable, Codable, Sendable, Identifiable {
    // 損益計算書 — 収入
    case salesRevenue = "sales_revenue"          // ア 売上（収入）金額
    case miscIncome = "misc_income"              // 雑収入

    // 損益計算書 — 売上原価
    case openingInventory = "opening_inventory"  // 期首商品棚卸高
    case purchases = "purchases"                 // 仕入金額
    case closingInventory = "closing_inventory"  // 期末商品棚卸高

    // 損益計算書 — 経費
    case salaries = "salaries"                   // 給料賃金
    case outsourcing = "outsourcing"             // 外注工賃
    case depreciation = "depreciation"           // 減価償却費
    case taxes = "taxes"                         // 租税公課
    case travelTransport = "travel_transport"    // 旅費交通費
    case communication = "communication"         // 通信費
    case advertising = "advertising"             // 広告宣伝費
    case entertainment = "entertainment"         // 接待交際費
    case insurance = "insurance"                 // 損害保険料
    case repair = "repair"                       // 修繕費
    case consumables = "consumables"             // 消耗品費
    case welfare = "welfare"                     // 福利厚生費
    case rent = "rent"                           // 地代家賃
    case utilities = "utilities"                 // 水道光熱費
    case packagingShipping = "packaging_shipping" // 荷造運賃
    case interest = "interest"                   // 利子割引料
    case miscExpense = "misc_expense"            // 雑費

    // 貸借対照表
    case cash = "cash"                           // 現金
    case deposits = "deposits"                   // 預金
    case accountsReceivable = "accounts_receivable" // 売掛金
    case inventory = "inventory"                 // 棚卸資産
    case fixedAssets = "fixed_assets"            // 固定資産
    case accountsPayable = "accounts_payable"    // 買掛金
    case borrowings = "borrowings"               // 借入金
    case capital = "capital"                     // 元入金

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .salesRevenue: "ア 売上（収入）金額"
        case .miscIncome: "雑収入"
        case .openingInventory: "期首商品棚卸高"
        case .purchases: "仕入金額"
        case .closingInventory: "期末商品棚卸高"
        case .salaries: "給料賃金"
        case .outsourcing: "外注工賃"
        case .depreciation: "減価償却費"
        case .taxes: "租税公課"
        case .travelTransport: "旅費交通費"
        case .communication: "通信費"
        case .advertising: "広告宣伝費"
        case .entertainment: "接待交際費"
        case .insurance: "損害保険料"
        case .repair: "修繕費"
        case .consumables: "消耗品費"
        case .welfare: "福利厚生費"
        case .rent: "地代家賃"
        case .utilities: "水道光熱費"
        case .packagingShipping: "荷造運賃"
        case .interest: "利子割引料"
        case .miscExpense: "雑費"
        case .cash: "現金"
        case .deposits: "預金"
        case .accountsReceivable: "売掛金"
        case .inventory: "棚卸資産"
        case .fixedAssets: "固定資産"
        case .accountsPayable: "買掛金"
        case .borrowings: "借入金"
        case .capital: "元入金"
        }
    }

    /// 決算書のセクション
    var section: LegalReportSection {
        switch self {
        case .salesRevenue, .miscIncome:
            return .revenue
        case .openingInventory, .purchases, .closingInventory:
            return .costOfSales
        case .salaries, .outsourcing, .depreciation, .taxes, .travelTransport,
             .communication, .advertising, .entertainment, .insurance,
             .repair, .consumables, .welfare, .rent, .utilities,
             .packagingShipping, .interest, .miscExpense:
            return .expenses
        case .cash, .deposits, .accountsReceivable, .inventory, .fixedAssets,
             .accountsPayable, .borrowings, .capital:
            return .balanceSheet
        }
    }
}

/// 決算書セクション
enum LegalReportSection: String, CaseIterable, Sendable {
    case revenue = "収入金額"
    case costOfSales = "売上原価"
    case expenses = "経費"
    case balanceSheet = "貸借対照表"
}
