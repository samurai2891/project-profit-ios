import Foundation

// MARK: - Trial Balance

struct TrialBalanceReport {
    let fiscalYear: Int
    let generatedAt: Date
    let rows: [TrialBalanceRow]

    var debitTotal: Int { rows.reduce(0) { $0 + $1.debit } }
    var creditTotal: Int { rows.reduce(0) { $0 + $1.credit } }
    var isBalanced: Bool { debitTotal == creditTotal }
}

struct TrialBalanceRow: Identifiable {
    let id: String  // accountId
    let code: String
    let name: String
    let accountType: AccountType
    let debit: Int
    let credit: Int
    let balance: Int
}

// MARK: - Profit & Loss

struct ProfitLossReport {
    let fiscalYear: Int
    let generatedAt: Date
    let revenueItems: [ProfitLossItem]
    let expenseItems: [ProfitLossItem]

    var totalRevenue: Int { revenueItems.reduce(0) { $0 + $1.amount } }
    var totalExpenses: Int { expenseItems.reduce(0) { $0 + $1.amount } }
    var netIncome: Int { totalRevenue - totalExpenses }
}

struct ProfitLossItem: Identifiable {
    let id: String  // accountId
    let code: String
    let name: String
    let amount: Int
    let deductibleAmount: Int  // 家事按分後の金額（費用のみ）
}

// MARK: - Balance Sheet

struct BalanceSheetReport {
    let fiscalYear: Int
    let generatedAt: Date
    let assetItems: [BalanceSheetItem]
    let liabilityItems: [BalanceSheetItem]
    let equityItems: [BalanceSheetItem]

    var totalAssets: Int { assetItems.reduce(0) { $0 + $1.balance } }
    var totalLiabilities: Int { liabilityItems.reduce(0) { $0 + $1.balance } }
    var totalEquity: Int { equityItems.reduce(0) { $0 + $1.balance } }
    var liabilitiesAndEquity: Int { totalLiabilities + totalEquity }
    var isBalanced: Bool { totalAssets == liabilitiesAndEquity }
}

struct BalanceSheetItem: Identifiable {
    let id: String  // accountId
    let code: String
    let name: String
    let balance: Int
}
