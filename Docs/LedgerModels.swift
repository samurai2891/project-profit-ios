// ============================================================
// LedgerModels.swift
// 個人事業主向け会計アプリ - 全台帳データモデル
// Excel原本16ファイルから完全準拠のSwift Codable定義
// ============================================================

import Foundation

// MARK: - 共通プロトコル

protocol LedgerEntry: Codable, Identifiable {
    var id: UUID { get }
    var month: Int { get set }
    var day: Int { get set }
}

protocol HasBalance {
    var computedBalance: Int { get }
}

// MARK: - インボイス対応

enum InvoiceType: String, Codable, CaseIterable {
    case applicable = "〇"
    case eightyPercent = "8割控除"
    case smallAmount = "少額特例"
    
    var displayName: String { rawValue }
}

// MARK: - 勘定科目マスター

enum AccountCategory: String, Codable, CaseIterable {
    case asset = "資産"
    case liability = "負債"
    case capital = "資本"
    case sales = "売上"
    case costOfSales = "売上原価"
    case expense = "経費"
}

struct AccountItem: Codable, Identifiable, Hashable {
    let id: UUID
    let category: AccountCategory
    let name: String
    
    init(category: AccountCategory, name: String) {
        self.id = UUID()
        self.category = category
        self.name = name
    }
}

struct AccountMaster {
    static let all: [AccountItem] = {
        var items: [AccountItem] = []
        let data: [(AccountCategory, [String])] = [
            (.asset, ["現金", "普通預金", "定期預金", "受取手形", "売掛金", "商品", "貯蔵品",
                       "仮払金", "建物", "建物附属設備", "機械装置", "車両運搬具", "工具器具備品",
                       "土地", "電話加入権", "敷金", "差入保証金", "預託金", "開業費", "事業主貸"]),
            (.liability, ["支払手形", "買掛金", "未払金", "前受金", "預り金", "事業主借"]),
            (.capital, ["元入金"]),
            (.sales, ["売上高", "雑収入"]),
            (.costOfSales, ["期首商品棚卸高", "仕入高", "期末商品棚卸高"]),
            (.expense, ["租税公課", "荷造運賃", "水道光熱費", "旅費交通費", "通信費", "広告宣伝費",
                         "接待交際費", "損害保険料", "修繕費", "消耗品費", "外注工賃", "地代家賃",
                         "減価償却費", "福利厚生費", "手形売却損", "支払手数料", "車両費", "雑費", "専従者給与"])
        ]
        for (cat, names) in data {
            for name in names {
                items.append(AccountItem(category: cat, name: name))
            }
        }
        return items
    }()
    
    static func accounts(for category: AccountCategory) -> [AccountItem] {
        all.filter { $0.category == category }
    }
}

// MARK: - 1. 現金出納帳 (Cash Book)

struct CashBookMetadata: Codable {
    var carryForward: Int = 0  // 前期より繰越
}

struct CashBookEntry: LedgerEntry {
    let id: UUID
    var month: Int
    var day: Int
    var description: String      // 摘要
    var account: String          // 勘定科目
    var income: Int?             // 入金
    var expense: Int?            // 出金
    // balance は computed（前行残高 + 入金 - 出金）
    
    // インボイス版追加フィールド
    var reducedTax: Bool?        // 軽減税率
    var invoiceType: InvoiceType? // インボイス
    
    init(month: Int, day: Int, description: String, account: String,
         income: Int? = nil, expense: Int? = nil,
         reducedTax: Bool? = nil, invoiceType: InvoiceType? = nil) {
        self.id = UUID()
        self.month = month
        self.day = day
        self.description = description
        self.account = account
        self.income = income
        self.expense = expense
        self.reducedTax = reducedTax
        self.invoiceType = invoiceType
    }
}

// MARK: - 2. 預金出納帳 (Bank Account Book)

struct BankAccountBookMetadata: Codable {
    var bankName: String = ""      // 銀行名
    var branchName: String = ""    // 本支店名
    var accountType: String = "普通預金" // 口座種類
    var carryForward: Int = 0      // 前期より繰越
}

struct BankAccountBookEntry: LedgerEntry {
    let id: UUID
    var month: Int
    var day: Int
    var description: String      // 摘要
    var account: String          // 勘定科目
    var deposit: Int?            // 入金
    var withdrawal: Int?         // 出金
    // balance は computed
    
    var reducedTax: Bool?
    var invoiceType: InvoiceType?
    
    init(month: Int, day: Int, description: String, account: String,
         deposit: Int? = nil, withdrawal: Int? = nil,
         reducedTax: Bool? = nil, invoiceType: InvoiceType? = nil) {
        self.id = UUID()
        self.month = month
        self.day = day
        self.description = description
        self.account = account
        self.deposit = deposit
        self.withdrawal = withdrawal
        self.reducedTax = reducedTax
        self.invoiceType = invoiceType
    }
}

// MARK: - 3. 売掛帳 (Accounts Receivable Book)

struct AccountsReceivableMetadata: Codable {
    var clientName: String = ""  // 得意先名
    var carryForward: Int = 0    // 前期より繰越
}

struct AccountsReceivableEntry: LedgerEntry {
    let id: UUID
    var month: Int
    var day: Int
    var counterAccount: String    // 相手科目
    var description: String       // 摘要
    var quantity: Int?            // 数量
    var unitPrice: Int?           // 単価
    var salesAmount: Int?         // 売上金額
    var receivedAmount: Int?      // 入金金額
    // arBalance は computed（前行残高 + 売上金額 - 入金金額）
    
    init(month: Int, day: Int, counterAccount: String, description: String,
         quantity: Int? = nil, unitPrice: Int? = nil,
         salesAmount: Int? = nil, receivedAmount: Int? = nil) {
        self.id = UUID()
        self.month = month
        self.day = day
        self.counterAccount = counterAccount
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.salesAmount = salesAmount
        self.receivedAmount = receivedAmount
    }
}

// MARK: - 4. 買掛帳 (Accounts Payable Book)

struct AccountsPayableMetadata: Codable {
    var supplierName: String = ""  // 仕入先名
    var carryForward: Int = 0      // 前期より繰越
}

struct AccountsPayableEntry: LedgerEntry {
    let id: UUID
    var month: Int
    var day: Int
    var counterAccount: String    // 相手科目
    var description: String       // 摘要
    var quantity: Int?            // 数量
    var unitPrice: Int?           // 単価
    var purchaseAmount: Int?      // 仕入金額
    var paymentAmount: Int?       // 支払金額
    // apBalance は computed（前行残高 + 仕入金額 - 支払金額）
    
    init(month: Int, day: Int, counterAccount: String, description: String,
         quantity: Int? = nil, unitPrice: Int? = nil,
         purchaseAmount: Int? = nil, paymentAmount: Int? = nil) {
        self.id = UUID()
        self.month = month
        self.day = day
        self.counterAccount = counterAccount
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.purchaseAmount = purchaseAmount
        self.paymentAmount = paymentAmount
    }
}

// MARK: - 5. 経費帳 (Expense Book)

struct ExpenseBookMetadata: Codable {
    var accountName: String = ""  // 勘定科目名（例：消耗品費）
}

struct ExpenseBookEntry: LedgerEntry {
    let id: UUID
    var month: Int
    var day: Int
    var counterAccount: String    // 相手科目
    var description: String       // 摘要
    var amount: Int               // 金額
    // runningTotal は computed
    
    var reducedTax: Bool?
    var invoiceType: InvoiceType?
    
    init(month: Int, day: Int, counterAccount: String, description: String, amount: Int,
         reducedTax: Bool? = nil, invoiceType: InvoiceType? = nil) {
        self.id = UUID()
        self.month = month
        self.day = day
        self.counterAccount = counterAccount
        self.description = description
        self.amount = amount
        self.reducedTax = reducedTax
        self.invoiceType = invoiceType
    }
}

// MARK: - 6. 総勘定元帳 (General Ledger)

struct GeneralLedgerMetadata: Codable {
    var accountName: String = ""           // 勘定科目
    var accountAttribute: AccountCategory? // 科目の属性
    var carryForward: Int = 0              // 前期より繰越
}

struct GeneralLedgerEntry: LedgerEntry {
    let id: UUID
    var month: Int
    var day: Int
    var counterAccount: String    // 相手科目
    var description: String       // 摘要
    var debit: Int?               // 借方
    var credit: Int?              // 貸方
    // balance は computed（属性に応じて借方/貸方加減算）
    
    var reducedTax: Bool?
    var invoiceType: InvoiceType?
    
    init(month: Int, day: Int, counterAccount: String, description: String,
         debit: Int? = nil, credit: Int? = nil,
         reducedTax: Bool? = nil, invoiceType: InvoiceType? = nil) {
        self.id = UUID()
        self.month = month
        self.day = day
        self.counterAccount = counterAccount
        self.description = description
        self.debit = debit
        self.credit = credit
        self.reducedTax = reducedTax
        self.invoiceType = invoiceType
    }
}

// MARK: - 7. 仕訳帳 (Journal)

struct JournalEntry: LedgerEntry {
    let id: UUID
    var month: Int
    var day: Int
    var debitAccount: String?     // 借方科目
    var debitAmount: Int?         // 借方金額
    var creditAccount: String?    // 貸方科目
    var creditAmount: Int?        // 貸方金額
    var description: String       // 摘要
    var isCompoundContinuation: Bool = false // 複合仕訳の続行行
    
    init(month: Int, day: Int, description: String,
         debitAccount: String? = nil, debitAmount: Int? = nil,
         creditAccount: String? = nil, creditAmount: Int? = nil,
         isCompoundContinuation: Bool = false) {
        self.id = UUID()
        self.month = month
        self.day = day
        self.description = description
        self.debitAccount = debitAccount
        self.debitAmount = debitAmount
        self.creditAccount = creditAccount
        self.creditAmount = creditAmount
        self.isCompoundContinuation = isCompoundContinuation
    }
}

// MARK: - 8. 固定資産台帳 兼 減価償却計算表

enum DepreciationMethod: String, Codable, CaseIterable {
    case straightLine = "定額法"
    case decliningBalance = "定率法"
}

enum AssetStatus: String, Codable, CaseIterable {
    case inUse = "使用中"
    case disposed = "除却"
    case sold = "売却"
    case fullyDepreciated = "償却済"
}

struct FixedAssetDepreciationMetadata: Codable {
    var fiscalYear: String = ""  // 例: "令和7年分"
}

struct FixedAssetDepreciationEntry: Codable, Identifiable {
    let id: UUID
    var account: String               // 勘定科目
    var assetCode: String             // 資産コード
    var assetName: String             // 資産名
    var assetType: String             // 資産の種類
    var status: String                // 状態
    var quantity: Int?                // 数量
    var acquisitionDate: String       // 取得日
    var acquisitionCost: Int          // 取得価額
    var depreciationMethod: DepreciationMethod // 償却方法
    var usefulLife: Int               // 耐用年数
    var depreciationRate: Double      // 償却率
    var depreciationMonths: Int       // 償却月数
    var openingBookValue: Int         // 期首帳簿価額
    var midYearChange: Int?           // 期中増減
    // computed: depreciationExpense, specialDepreciation, totalDepreciation
    // computed: deductibleAmount, yearEndBalance
    var businessUseRatio: Double      // 事業専用割合（0.0〜1.0）
    var remarks: String?              // 摘要
    
    init(account: String, assetCode: String, assetName: String, assetType: String,
         status: String, acquisitionDate: String, acquisitionCost: Int,
         depreciationMethod: DepreciationMethod, usefulLife: Int,
         depreciationRate: Double, depreciationMonths: Int,
         openingBookValue: Int, businessUseRatio: Double,
         quantity: Int? = nil, midYearChange: Int? = nil, remarks: String? = nil) {
        self.id = UUID()
        self.account = account
        self.assetCode = assetCode
        self.assetName = assetName
        self.assetType = assetType
        self.status = status
        self.quantity = quantity
        self.acquisitionDate = acquisitionDate
        self.acquisitionCost = acquisitionCost
        self.depreciationMethod = depreciationMethod
        self.usefulLife = usefulLife
        self.depreciationRate = depreciationRate
        self.depreciationMonths = depreciationMonths
        self.openingBookValue = openingBookValue
        self.midYearChange = midYearChange
        self.businessUseRatio = businessUseRatio
        self.remarks = remarks
    }
}

// MARK: - 9. 固定資産台帳 (Simple)

struct FixedAssetRegisterMetadata: Codable {
    var assetName: String = ""            // 名称
    var assetNumber: String = ""          // 番号
    var assetType: String = ""            // 種類
    var acquisitionDate: String = ""      // 取得年月日
    var location: String = ""             // 所在
    var usefulLife: Int = 0               // 耐用年数
    var depreciationMethod: String = ""   // 償却方法
    var depreciationRate: Double = 0.0    // 償却率
}

struct FixedAssetRegisterEntry: Codable, Identifiable {
    let id: UUID
    var date: String                      // 年月日
    var description: String               // 摘要
    var acquiredQuantity: Int?            // 取得数量
    var acquiredUnitPrice: Int?           // 取得単価
    var acquiredAmount: Int?              // 取得金額
    var depreciationAmount: Int?          // 償却額
    var disposalQuantity: Int?            // 異動数量
    var disposalAmount: Int?              // 異動金額
    // computed: currentQuantity, currentAmount
    var businessUseRatio: Double?         // 事業専用割合
    // computed: deductibleAmount
    var remarks: String?                  // 備考
}

// MARK: - 10. 交通費精算書

enum TripType: String, Codable, CaseIterable {
    case oneWay = "片道"
    case roundTrip = "往復"
}

struct TransportationExpenseMetadata: Codable {
    var year: Int = 2025
    var monthPeriod: Int = 1           // 月度
    var department: String = ""        // 所属
    var employeeName: String = ""      // 氏名
    var requestDate: String = ""       // 申請日
    var settlementDate: String = ""    // 精算日
}

struct TransportationExpenseEntry: Codable, Identifiable {
    let id: UUID
    var date: String                   // 日付
    var destination: String            // 行先
    var purpose: String                // 目的（用件）
    var transportMethod: String        // 交通機関（手段）
    var routeFrom: String              // 区間（起点）
    var routeTo: String                // 区間（終点）
    var tripType: TripType             // 片/往
    var amount: Int                    // 金額
}

// MARK: - 11. 白色申告用 簡易帳簿

struct WhiteTaxBookkeepingMetadata: Codable {
    var fiscalYear: Int = 2024
}

struct WhiteTaxBookkeepingEntry: LedgerEntry {
    let id: UUID
    var month: Int
    var day: Int
    var description: String            // 摘要
    
    // 収入金額
    var salesAmount: Int?              // 売上金額
    var miscIncome: Int?               // 雑収入等
    
    // 売上原価
    var purchases: Int?                // 仕入
    
    // 経費
    var salaries: Int?                 // 給料賃金
    var outsourcing: Int?              // 外注工賃
    var depreciation: Int?             // 減価償却費
    var badDebts: Int?                 // 貸倒金
    var rent: Int?                     // 地代家賃
    var interestDiscount: Int?         // 利子割引料
    
    // その他の経費
    var taxesDuties: Int?              // 租税公課
    var packingShipping: Int?          // 荷造運賃
    var utilities: Int?                // 水道光熱費
    var travelTransport: Int?          // 旅費交通費
    var communication: Int?            // 通信費
    var advertising: Int?              // 広告宣伝費
    var entertainment: Int?            // 接待交際費
    var insurance: Int?                // 損害保険料
    var repairs: Int?                  // 修繕費
    var supplies: Int?                 // 消耗品費
    var welfare: Int?                  // 福利厚生費
    var miscellaneous: Int?            // 雑費
    
    // インボイス版追加
    var reducedTax: Bool?
    var invoiceType: InvoiceType?
}

// MARK: - CSV書き出し / 読み込みプロトコル

protocol CSVExportable {
    static var csvHeaders: [String] { get }
    static var csvHeadersJa: [String] { get }
    func toCSVRow() -> [String]
}

protocol CSVImportable {
    static func fromCSVRow(_ values: [String]) throws -> Self
}

// MARK: - 台帳タイプ列挙

enum LedgerType: String, Codable, CaseIterable {
    case cashBook = "cash_book"
    case cashBookInvoice = "cash_book_invoice"
    case bankAccountBook = "bank_account_book"
    case bankAccountBookInvoice = "bank_account_book_invoice"
    case accountsReceivable = "accounts_receivable_book"
    case accountsPayable = "accounts_payable_book"
    case expenseBook = "expense_book"
    case expenseBookInvoice = "expense_book_invoice"
    case generalLedger = "general_ledger"
    case generalLedgerInvoice = "general_ledger_invoice"
    case journal = "journal"
    case fixedAssetDepreciation = "fixed_asset_depreciation"
    case fixedAssetRegister = "fixed_asset_register"
    case transportationExpense = "transportation_expense"
    case whiteTaxBookkeeping = "white_tax_bookkeeping"
    case whiteTaxBookkeepingInvoice = "white_tax_bookkeeping_invoice"
    
    var displayName: String {
        switch self {
        case .cashBook: return "現金出納帳"
        case .cashBookInvoice: return "現金出納帳（インボイス）"
        case .bankAccountBook: return "預金出納帳"
        case .bankAccountBookInvoice: return "預金出納帳（インボイス）"
        case .accountsReceivable: return "売掛帳"
        case .accountsPayable: return "買掛帳"
        case .expenseBook: return "経費帳"
        case .expenseBookInvoice: return "経費帳（インボイス）"
        case .generalLedger: return "総勘定元帳"
        case .generalLedgerInvoice: return "総勘定元帳（インボイス）"
        case .journal: return "仕訳帳"
        case .fixedAssetDepreciation: return "固定資産台帳 兼 減価償却計算表"
        case .fixedAssetRegister: return "固定資産台帳"
        case .transportationExpense: return "交通費精算書"
        case .whiteTaxBookkeeping: return "白色申告用 簡易帳簿"
        case .whiteTaxBookkeepingInvoice: return "白色申告用 簡易帳簿（インボイス）"
        }
    }
    
    var hasInvoiceVariant: Bool {
        switch self {
        case .cashBook, .bankAccountBook, .expenseBook, .generalLedger, .whiteTaxBookkeeping:
            return true
        default:
            return false
        }
    }
}
