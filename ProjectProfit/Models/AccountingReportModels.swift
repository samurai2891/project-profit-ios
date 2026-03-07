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

// MARK: - Canonical Report Models (Decimal ベース)

struct CanonicalTrialBalanceReport {
    let fiscalYear: Int
    let generatedAt: Date
    let rows: [CanonicalTrialBalanceRow]

    var debitTotal: Decimal { rows.reduce(Decimal(0)) { $0 + $1.debit } }
    var creditTotal: Decimal { rows.reduce(Decimal(0)) { $0 + $1.credit } }
    var isBalanced: Bool { debitTotal == creditTotal }
}

struct CanonicalTrialBalanceRow: Identifiable {
    let id: UUID
    let code: String
    let name: String
    let accountType: CanonicalAccountType
    let normalBalance: NormalBalance
    let debit: Decimal
    let credit: Decimal
    let balance: Decimal
}

struct CanonicalProfitLossReport {
    let fiscalYear: Int
    let generatedAt: Date
    let revenueItems: [CanonicalProfitLossItem]
    let expenseItems: [CanonicalProfitLossItem]

    var totalRevenue: Decimal { revenueItems.reduce(Decimal(0)) { $0 + $1.amount } }
    var totalExpenses: Decimal { expenseItems.reduce(Decimal(0)) { $0 + $1.amount } }
    var netIncome: Decimal { totalRevenue - totalExpenses }
}

struct CanonicalProfitLossItem: Identifiable {
    let id: UUID
    let code: String
    let name: String
    let amount: Decimal
}

struct CanonicalBalanceSheetReport {
    let fiscalYear: Int
    let generatedAt: Date
    let assetItems: [CanonicalBalanceSheetItem]
    let liabilityItems: [CanonicalBalanceSheetItem]
    let equityItems: [CanonicalBalanceSheetItem]

    var totalAssets: Decimal { assetItems.reduce(Decimal(0)) { $0 + $1.balance } }
    var totalLiabilities: Decimal { liabilityItems.reduce(Decimal(0)) { $0 + $1.balance } }
    var totalEquity: Decimal { equityItems.reduce(Decimal(0)) { $0 + $1.balance } }
    var liabilitiesAndEquity: Decimal { totalLiabilities + totalEquity }
    var isBalanced: Bool { totalAssets == liabilitiesAndEquity }
}

struct CanonicalBalanceSheetItem: Identifiable {
    let id: UUID
    let code: String
    let name: String
    let balance: Decimal
}
