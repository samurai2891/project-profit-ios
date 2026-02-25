import Foundation

// MARK: - Default Account Definitions

/// デフォルト勘定科目定義（25勘定科目）
/// Todo.md 4B-1 準拠: 資産6, 負債2, 資本3(事業主貸含む), 収益2, 費用12(e-Tax準拠), 特殊1
/// コード体系: 1xx資産, 2xx負債, 3xx資本, 4xx収益, 5xx費用, 9xx特殊
struct DefaultAccountDefinition {
    let id: String
    let code: String
    let name: String
    let accountType: AccountType
    let normalBalance: NormalBalance
    let subtype: AccountSubtype
    let displayOrder: Int
}

enum AccountingConstants {

    // MARK: - Default Accounts

    static let defaultAccounts: [DefaultAccountDefinition] = [
        // 資産 (Assets) — 1xx
        DefaultAccountDefinition(id: "acct-cash", code: "101", name: "現金", accountType: .asset, normalBalance: .debit, subtype: .cash, displayOrder: 1),
        DefaultAccountDefinition(id: "acct-bank", code: "102", name: "普通預金", accountType: .asset, normalBalance: .debit, subtype: .ordinaryDeposit, displayOrder: 2),
        DefaultAccountDefinition(id: "acct-ar", code: "103", name: "売掛金", accountType: .asset, normalBalance: .debit, subtype: .accountsReceivable, displayOrder: 3),
        DefaultAccountDefinition(id: "acct-prepaid", code: "104", name: "前払費用", accountType: .asset, normalBalance: .debit, subtype: .prepaidExpenses, displayOrder: 4),
        DefaultAccountDefinition(id: "acct-cc", code: "105", name: "クレジットカード", accountType: .asset, normalBalance: .debit, subtype: .creditCard, displayOrder: 5),
        // 事業主貸: 資本区分だが B/S 上は資産の部に表示、正常残高は借方
        DefaultAccountDefinition(id: "acct-owner-drawings", code: "152", name: "事業主貸", accountType: .equity, normalBalance: .debit, subtype: .ownerDrawings, displayOrder: 6),

        // 負債 (Liabilities) — 2xx
        DefaultAccountDefinition(id: "acct-ap", code: "201", name: "買掛金", accountType: .liability, normalBalance: .credit, subtype: .accountsPayable, displayOrder: 10),
        DefaultAccountDefinition(id: "acct-accrued", code: "202", name: "未払費用", accountType: .liability, normalBalance: .credit, subtype: .accruedExpenses, displayOrder: 11),

        // 資本 (Equity) — 3xx
        DefaultAccountDefinition(id: "acct-owner-capital", code: "301", name: "元入金", accountType: .equity, normalBalance: .credit, subtype: .ownerCapital, displayOrder: 20),
        DefaultAccountDefinition(id: "acct-owner-contributions", code: "302", name: "事業主借", accountType: .equity, normalBalance: .credit, subtype: .ownerContributions, displayOrder: 21),

        // 収益 (Revenue) — 4xx
        DefaultAccountDefinition(id: "acct-sales", code: "401", name: "売上高", accountType: .revenue, normalBalance: .credit, subtype: .salesRevenue, displayOrder: 30),
        DefaultAccountDefinition(id: "acct-other-income", code: "402", name: "雑収入", accountType: .revenue, normalBalance: .credit, subtype: .otherIncome, displayOrder: 31),

        // 費用 — e-Tax 12経費区分 (Expenses) — 5xx
        DefaultAccountDefinition(id: "acct-rent", code: "501", name: "地代家賃", accountType: .expense, normalBalance: .debit, subtype: .rentExpense, displayOrder: 40),
        DefaultAccountDefinition(id: "acct-utilities", code: "502", name: "水道光熱費", accountType: .expense, normalBalance: .debit, subtype: .utilitiesExpense, displayOrder: 41),
        DefaultAccountDefinition(id: "acct-travel", code: "503", name: "旅費交通費", accountType: .expense, normalBalance: .debit, subtype: .travelExpense, displayOrder: 42),
        DefaultAccountDefinition(id: "acct-communication", code: "504", name: "通信費", accountType: .expense, normalBalance: .debit, subtype: .communicationExpense, displayOrder: 43),
        DefaultAccountDefinition(id: "acct-advertising", code: "505", name: "広告宣伝費", accountType: .expense, normalBalance: .debit, subtype: .advertisingExpense, displayOrder: 44),
        DefaultAccountDefinition(id: "acct-entertainment", code: "506", name: "接待交際費", accountType: .expense, normalBalance: .debit, subtype: .entertainmentExpense, displayOrder: 45),
        DefaultAccountDefinition(id: "acct-depreciation", code: "507", name: "減価償却費", accountType: .expense, normalBalance: .debit, subtype: .depreciationExpense, displayOrder: 46),
        DefaultAccountDefinition(id: "acct-repair", code: "508", name: "修繕費", accountType: .expense, normalBalance: .debit, subtype: .repairExpense, displayOrder: 47),
        DefaultAccountDefinition(id: "acct-supplies", code: "509", name: "消耗品費", accountType: .expense, normalBalance: .debit, subtype: .suppliesExpense, displayOrder: 48),
        DefaultAccountDefinition(id: "acct-welfare", code: "510", name: "福利厚生費", accountType: .expense, normalBalance: .debit, subtype: .welfareExpense, displayOrder: 49),
        DefaultAccountDefinition(id: "acct-outsourcing", code: "511", name: "外注工賃", accountType: .expense, normalBalance: .debit, subtype: .outsourcingExpense, displayOrder: 50),
        DefaultAccountDefinition(id: "acct-misc", code: "512", name: "雑費", accountType: .expense, normalBalance: .debit, subtype: .miscExpense, displayOrder: 51),

        // 特殊 (Special) — 9xx（仮勘定は B/S に表示されるため asset 区分）
        DefaultAccountDefinition(id: "acct-suspense", code: "900", name: "仮勘定", accountType: .asset, normalBalance: .debit, subtype: .suspense, displayOrder: 99),
    ]

    /// defaultAccounts の id を key とした辞書（O(1) ルックアップ用）
    static let defaultAccountsById: [String: DefaultAccountDefinition] = {
        Dictionary(uniqueKeysWithValues: defaultAccounts.map { ($0.id, $0) })
    }()

    // MARK: - Category → Account Mapping

    /// デフォルトカテゴリ ID → 勘定科目 ID のマッピング（Todo.md 4B-2 準拠: 13マッピング）
    static let categoryToAccountMapping: [String: String] = [
        // 経費カテゴリ
        "cat-hosting": "acct-communication",        // ホスティング → 通信費
        "cat-tools": "acct-supplies",               // ツール → 消耗品費
        "cat-ads": "acct-advertising",              // 広告 → 広告宣伝費
        "cat-contractor": "acct-outsourcing",       // 請負業者 → 外注工賃
        "cat-communication": "acct-communication",  // 通信費 → 通信費
        "cat-supplies": "acct-supplies",            // 消耗品 → 消耗品費
        "cat-transport": "acct-travel",             // 交通費 → 旅費交通費
        "cat-food": "acct-entertainment",           // 食費・飲食 → 接待交際費
        "cat-entertainment": "acct-entertainment",  // 接待・会議費 → 接待交際費
        "cat-other-expense": "acct-misc",           // その他経費 → 雑費
        // 収入カテゴリ
        "cat-sales": "acct-sales",                  // 売上 → 売上高
        "cat-service": "acct-sales",                // サービス収入 → 売上高
        "cat-other-income": "acct-other-income",    // その他収入 → 雑収入
    ]

    // MARK: - Well-Known Account IDs

    /// 現金
    static let cashAccountId = "acct-cash"
    /// 普通預金
    static let bankAccountId = "acct-bank"
    /// 事業主貸
    static let ownerDrawingsAccountId = "acct-owner-drawings"
    /// 事業主借
    static let ownerContributionsAccountId = "acct-owner-contributions"
    /// 元入金
    static let ownerCapitalAccountId = "acct-owner-capital"
    /// 売上高
    static let salesAccountId = "acct-sales"
    /// 雑収入
    static let otherIncomeAccountId = "acct-other-income"
    /// 雑費
    static let miscExpenseAccountId = "acct-misc"
    /// 仮勘定
    static let suspenseAccountId = "acct-suspense"

    // MARK: - Default Profile ID

    static let defaultProfileId = "profile-default"
    static let defaultPaymentAccountId = "acct-cash"
}
