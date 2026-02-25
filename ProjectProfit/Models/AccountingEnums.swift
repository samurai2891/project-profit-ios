import Foundation

// MARK: - AccountType

/// 勘定科目の5大分類
enum AccountType: String, Codable, CaseIterable {
    case asset      // 資産
    case liability  // 負債
    case equity     // 資本（元入金等）
    case revenue    // 収益
    case expense    // 費用

    var label: String {
        switch self {
        case .asset: "資産"
        case .liability: "負債"
        case .equity: "資本"
        case .revenue: "収益"
        case .expense: "費用"
        }
    }

    /// 勘定科目の正常残高方向（資産・費用は借方、負債・資本・収益は貸方）
    var normalBalance: NormalBalance {
        switch self {
        case .asset, .expense: .debit
        case .liability, .equity, .revenue: .credit
        }
    }
}

// MARK: - NormalBalance

/// 勘定科目の正常残高方向
enum NormalBalance: String, Codable {
    case debit   // 借方
    case credit  // 貸方

    var label: String {
        switch self {
        case .debit: "借方"
        case .credit: "貸方"
        }
    }
}

// MARK: - AccountSubtype

/// 勘定科目の詳細区分（資産・負債・資本・収益の各区分 + e-Tax TaxLine 12経費区分）
enum AccountSubtype: String, Codable, CaseIterable {
    // 資産 (Assets)
    case cash                    // 現金
    case ordinaryDeposit         // 普通預金
    case accountsReceivable      // 売掛金
    case prepaidExpenses         // 前払費用
    case creditCard              // クレジットカード

    // 負債 (Liabilities)
    case accountsPayable         // 買掛金
    case accruedExpenses         // 未払費用

    // 資本 (Equity)
    case ownerCapital            // 元入金
    case ownerContributions      // 事業主借
    case ownerDrawings           // 事業主貸

    // 特殊 (Special)
    case suspense                // 仮勘定
    case openingBalance          // 期首残高用

    // 収益 (Revenue)
    case salesRevenue            // 売上（収入）金額
    case otherIncome             // 雑収入

    // 費用 — e-Tax 12経費区分 (Expenses)
    case rentExpense             // 地代家賃
    case utilitiesExpense        // 水道光熱費
    case travelExpense           // 旅費交通費
    case communicationExpense    // 通信費
    case advertisingExpense      // 広告宣伝費
    case entertainmentExpense    // 接待交際費
    case depreciationExpense     // 減価償却費
    case repairExpense           // 修繕費
    case suppliesExpense         // 消耗品費
    case welfareExpense          // 福利厚生費
    case outsourcingExpense      // 外注工賃
    case miscExpense             // 雑費

    var label: String {
        switch self {
        case .cash: "現金"
        case .ordinaryDeposit: "普通預金"
        case .accountsReceivable: "売掛金"
        case .prepaidExpenses: "前払費用"
        case .creditCard: "クレジットカード"
        case .accountsPayable: "買掛金"
        case .accruedExpenses: "未払費用"
        case .ownerCapital: "元入金"
        case .ownerContributions: "事業主借"
        case .ownerDrawings: "事業主貸"
        case .suspense: "仮勘定"
        case .openingBalance: "期首残高"
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
}

// MARK: - JournalEntryType

/// 仕訳の種別
enum JournalEntryType: String, Codable, CaseIterable {
    case auto       // トランザクションから自動生成
    case manual     // 手動仕訳（決算整理仕訳等）
    case opening    // 期首残高仕訳
    case closing    // 決算仕訳

    var label: String {
        switch self {
        case .auto: "自動仕訳"
        case .manual: "手動仕訳"
        case .opening: "期首残高仕訳"
        case .closing: "決算仕訳"
        }
    }
}

// MARK: - BookkeepingMode

/// 記帳方式
enum BookkeepingMode: String, Codable, CaseIterable {
    case singleEntry  // 簡易簿記（10万円控除）
    case doubleEntry  // 複式簿記（65万円控除）

    var label: String {
        switch self {
        case .singleEntry: "簡易簿記"
        case .doubleEntry: "複式簿記"
        }
    }
}
