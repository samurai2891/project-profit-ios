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

/// 勘定科目の詳細区分（資産・負債・資本・収益の各区分 + e-Tax TaxLine経費区分）
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
    case accumulatedDepreciation // 減価償却累計額

    // 収益 (Revenue)
    case salesRevenue            // 売上（収入）金額
    case otherIncome             // 雑収入

    // 消費税 (Consumption Tax)
    case inputTax                // 仮払消費税
    case outputTax               // 仮受消費税
    case taxPayable              // 未払消費税

    // 在庫・売上原価 (Inventory / COGS)
    case openingInventory        // 期首商品棚卸高
    case purchases               // 仕入高
    case closingInventory        // 期末商品棚卸高
    case costOfGoodsSold         // 売上原価

    // 費用 — e-Tax 経費区分 (Expenses)
    case rentExpense             // 地代家賃
    case utilitiesExpense        // 水道光熱費
    case travelExpense           // 旅費交通費
    case communicationExpense    // 通信費
    case advertisingExpense      // 広告宣伝費
    case entertainmentExpense    // 接待交際費
    case depreciationExpense     // 減価償却費
    case insuranceExpense        // 損害保険料
    case interestExpense         // 利子割引料
    case taxesExpense            // 租税公課
    case suppliesExpense         // 消耗品費
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
        case .accumulatedDepreciation: "減価償却累計額"
        case .salesRevenue: "売上（収入）金額"
        case .otherIncome: "雑収入"
        case .inputTax: "仮払消費税"
        case .outputTax: "仮受消費税"
        case .taxPayable: "未払消費税"
        case .openingInventory: "期首商品棚卸高"
        case .purchases: "仕入高"
        case .closingInventory: "期末商品棚卸高"
        case .costOfGoodsSold: "売上原価"
        case .rentExpense: "地代家賃"
        case .utilitiesExpense: "水道光熱費"
        case .travelExpense: "旅費交通費"
        case .communicationExpense: "通信費"
        case .advertisingExpense: "広告宣伝費"
        case .entertainmentExpense: "接待交際費"
        case .depreciationExpense: "減価償却費"
        case .insuranceExpense: "損害保険料"
        case .interestExpense: "利子割引料"
        case .taxesExpense: "租税公課"
        case .suppliesExpense: "消耗品費"
        case .outsourcingExpense: "外注工賃"
        case .miscExpense: "雑費"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "repairExpense":
            self = .interestExpense
        case "welfareExpense":
            self = .taxesExpense
        default:
            guard let value = AccountSubtype(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown AccountSubtype raw value: \(rawValue)"
                )
            }
            self = value
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
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

// MARK: - DepreciationMethod

/// 減価償却方法
enum DepreciationMethod: String, Codable, CaseIterable {
    case straightLine      // 定額法（個人事業主デフォルト）
    case decliningBalance  // 定率法（届出が必要）
    case immediateExpense  // 少額一括（10万円未満）
    case threeYearEqual    // 一括償却資産（3年均等、10万～20万円未満）
    case smallBusiness     // 少額減価償却資産特例（30万円未満、青色申告者）

    var label: String {
        switch self {
        case .straightLine: "定額法"
        case .decliningBalance: "定率法"
        case .immediateExpense: "少額一括"
        case .threeYearEqual: "一括償却（3年均等）"
        case .smallBusiness: "少額減価償却資産特例"
        }
    }
}

// MARK: - AssetStatus

/// 固定資産のステータス
enum AssetStatus: String, Codable, CaseIterable {
    case active            // 使用中（償却中）
    case fullyDepreciated  // 償却完了
    case disposed          // 除却済み
    case sold              // 売却済み

    var label: String {
        switch self {
        case .active: "使用中"
        case .fullyDepreciated: "償却完了"
        case .disposed: "除却済み"
        case .sold: "売却済み"
        }
    }
}

// MARK: - TaxCategory

/// 消費税区分
enum TaxCategory: String, Codable, CaseIterable {
    case standardRate   // 標準税率（10%）
    case reducedRate    // 軽減税率（8%）
    case exempt         // 非課税
    case nonTaxable     // 不課税

    var label: String {
        switch self {
        case .standardRate: "課税（10%）"
        case .reducedRate: "軽減税率（8%）"
        case .exempt: "非課税"
        case .nonTaxable: "不課税"
        }
    }

    /// 税率（%）
    var rate: Int {
        switch self {
        case .standardRate: 10
        case .reducedRate: 8
        case .exempt, .nonTaxable: 0
        }
    }

    /// 課税取引かどうか
    var isTaxable: Bool {
        switch self {
        case .standardRate, .reducedRate: true
        case .exempt, .nonTaxable: false
        }
    }
}

// MARK: - BookkeepingMode

/// 記帳モード
enum BookkeepingMode: String, Codable, CaseIterable {
    case singleEntry  // 簡易簿記（プロフィール設定向け）
    case doubleEntry  // 複式簿記（プロフィール設定向け）
    case auto         // 仕訳を自動再生成
    case locked       // 仕訳をロック（自動再生成しない）

    var label: String {
        switch self {
        case .singleEntry: "簡易簿記"
        case .doubleEntry: "複式簿記"
        case .auto: "自動"
        case .locked: "ロック"
        }
    }
}
