import Foundation

/// 法定帳票/決算書の表示行ID
/// 勘定科目がどの表示行に対応するかを定義する
enum LegalReportLine: String, CaseIterable, Codable, Sendable, Identifiable {
    // 損益計算書 — 収入
    case salesRevenue = "sales_revenue"          // ア 売上（収入）金額
    case miscIncome = "misc_income"              // 雑収入

    // 損益計算書 — 売上原価
    case openingInventory = "opening_inventory"  // 期首商品棚卸高
    case purchases = "purchases"                 // 仕入金額
    case closingInventory = "closing_inventory"  // 期末商品棚卸高
    case costOfGoodsSold = "cost_of_goods_sold"  // 売上原価

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
    case prepaidExpenses = "prepaid_expenses"    // 前払費用
    case creditCard = "credit_card"              // クレジットカード
    case inventory = "inventory"                 // 棚卸資産
    case fixedAssets = "fixed_assets"            // 固定資産
    case accumulatedDepreciation = "accumulated_depreciation" // 減価償却累計額
    case inputTax = "input_tax"                  // 仮払消費税
    case suspense = "suspense"                   // 仮勘定
    case accountsPayable = "accounts_payable"    // 買掛金
    case accruedExpenses = "accrued_expenses"    // 未払費用
    case outputTax = "output_tax"                // 仮受消費税
    case taxPayable = "tax_payable"              // 未払消費税
    case borrowings = "borrowings"               // 借入金
    case ownerContributions = "owner_contributions" // 事業主借
    case capital = "capital"                     // 元入金
    case ownerDrawings = "owner_drawings"        // 事業主貸

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .salesRevenue: "ア 売上（収入）金額"
        case .miscIncome: "雑収入"
        case .openingInventory: "期首商品棚卸高"
        case .purchases: "仕入金額"
        case .closingInventory: "期末商品棚卸高"
        case .costOfGoodsSold: "売上原価"
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
        case .prepaidExpenses: "前払費用"
        case .creditCard: "クレジットカード"
        case .inventory: "棚卸資産"
        case .fixedAssets: "固定資産"
        case .accumulatedDepreciation: "減価償却累計額"
        case .inputTax: "仮払消費税"
        case .suspense: "仮勘定"
        case .accountsPayable: "買掛金"
        case .accruedExpenses: "未払費用"
        case .outputTax: "仮受消費税"
        case .taxPayable: "未払消費税"
        case .borrowings: "借入金"
        case .ownerContributions: "事業主借"
        case .capital: "元入金"
        case .ownerDrawings: "事業主貸"
        }
    }

    /// 決算書のセクション
    var section: LegalReportSection {
        switch self {
        case .salesRevenue, .miscIncome:
            return .revenue
        case .openingInventory, .purchases, .closingInventory, .costOfGoodsSold:
            return .costOfSales
        case .salaries, .outsourcing, .depreciation, .taxes, .travelTransport,
             .communication, .advertising, .entertainment, .insurance,
             .repair, .consumables, .welfare, .rent, .utilities,
             .packagingShipping, .interest, .miscExpense:
            return .expenses
        case .cash, .deposits, .accountsReceivable, .prepaidExpenses, .creditCard,
             .inventory, .fixedAssets, .accumulatedDepreciation, .inputTax, .suspense,
             .accountsPayable, .accruedExpenses, .outputTax, .taxPayable,
             .borrowings, .ownerContributions, .capital, .ownerDrawings:
            return .balanceSheet
        }
    }

    static func defaultLine(for subtype: AccountSubtype) -> LegalReportLine? {
        switch subtype {
        case .cash:
            return .cash
        case .ordinaryDeposit:
            return .deposits
        case .accountsReceivable:
            return .accountsReceivable
        case .prepaidExpenses:
            return .prepaidExpenses
        case .creditCard:
            return .creditCard
        case .accountsPayable:
            return .accountsPayable
        case .accruedExpenses:
            return .accruedExpenses
        case .ownerCapital:
            return .capital
        case .ownerContributions:
            return .ownerContributions
        case .ownerDrawings:
            return .ownerDrawings
        case .suspense:
            return .suspense
        case .openingBalance:
            return nil
        case .accumulatedDepreciation:
            return .accumulatedDepreciation
        case .salesRevenue:
            return .salesRevenue
        case .otherIncome:
            return .miscIncome
        case .inputTax:
            return .inputTax
        case .outputTax:
            return .outputTax
        case .taxPayable:
            return .taxPayable
        case .openingInventory:
            return .openingInventory
        case .purchases:
            return .purchases
        case .closingInventory:
            return .closingInventory
        case .costOfGoodsSold:
            return .costOfGoodsSold
        case .rentExpense:
            return .rent
        case .utilitiesExpense:
            return .utilities
        case .travelExpense:
            return .travelTransport
        case .communicationExpense:
            return .communication
        case .advertisingExpense:
            return .advertising
        case .entertainmentExpense:
            return .entertainment
        case .depreciationExpense:
            return .depreciation
        case .insuranceExpense:
            return .insurance
        case .interestExpense:
            return .interest
        case .taxesExpense:
            return .taxes
        case .suppliesExpense:
            return .consumables
        case .outsourcingExpense:
            return .outsourcing
        case .miscExpense:
            return .miscExpense
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
