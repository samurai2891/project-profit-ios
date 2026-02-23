import SwiftData
import SwiftUI

// MARK: - Enums

enum ProjectStatus: String, Codable, CaseIterable {
    case active
    case completed
    case paused

    var label: String {
        switch self {
        case .active: "進行中"
        case .completed: "完了"
        case .paused: "保留"
        }
    }

    var color: Color {
        switch self {
        case .active: Color(hex: "16A34A")
        case .completed: Color(hex: "2563EB")
        case .paused: Color(hex: "F59E0B")
        }
    }
}

enum TransactionType: String, Codable {
    case income
    case expense

    var label: String {
        switch self {
        case .income: "収益"
        case .expense: "経費"
        }
    }
}

enum CategoryType: String, Codable {
    case income
    case expense
}

enum RecurringFrequency: String, Codable {
    case monthly
    case yearly

    var label: String {
        switch self {
        case .monthly: "毎月"
        case .yearly: "毎年"
        }
    }
}

enum AllocationMode: String, Codable {
    case equalAll
    case manual

    var label: String {
        switch self {
        case .equalAll: "全体（均等割）"
        case .manual: "プロジェクト指定"
        }
    }
}

enum YearlyAmortizationMode: String, Codable {
    case lumpSum       // 一括登録（既存動作）
    case monthlySpread // 月次分割

    var label: String {
        switch self {
        case .lumpSum: "一括登録"
        case .monthlySpread: "月次分割"
        }
    }
}

enum NotificationTiming: String, Codable {
    case none
    case sameDay
    case dayBefore
    case both

    var label: String {
        switch self {
        case .none: "通知なし"
        case .sameDay: "当日に通知"
        case .dayBefore: "前日に通知"
        case .both: "前日と当日に通知"
        }
    }
}

// MARK: - Supporting Structs

struct Allocation: Codable, Hashable {
    let projectId: UUID
    let ratio: Int
    let amount: Int

    init(projectId: UUID, ratio: Int, amount: Int) {
        self.projectId = projectId
        self.ratio = ratio
        self.amount = amount
    }
}

struct ReceiptLineItem: Codable, Hashable {
    let name: String
    let quantity: Int
    let unitPrice: Int
    let subtotal: Int

    init(name: String, quantity: Int = 1, unitPrice: Int, subtotal: Int? = nil) {
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.subtotal = subtotal ?? (quantity * unitPrice)
    }
}

// MARK: - SwiftData Models

@Model
final class PPProject {
    @Attribute(.unique) var id: UUID
    var name: String
    var projectDescription: String
    var status: ProjectStatus
    var startDate: Date?
    var completedAt: Date?
    var plannedEndDate: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        projectDescription: String = "",
        status: ProjectStatus = .active,
        startDate: Date? = nil,
        completedAt: Date? = nil,
        plannedEndDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.projectDescription = projectDescription
        self.status = status
        self.startDate = startDate
        self.completedAt = completedAt
        self.plannedEndDate = plannedEndDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension PPProject {
    /// プロラタ計算用の有効終了日: completedAt > plannedEndDate > nil
    var effectiveEndDate: Date? { completedAt ?? plannedEndDate }
    /// 予定日ベースの推定配分かどうか
    var isUsingPlannedEndDate: Bool { completedAt == nil && plannedEndDate != nil }
}

@Model
final class PPTransaction {
    @Attribute(.unique) var id: UUID
    var type: TransactionType
    var amount: Int
    var date: Date
    var categoryId: String
    var memo: String
    var allocations: [Allocation]
    var recurringId: UUID?
    var receiptImagePath: String?
    var lineItems: [ReceiptLineItem]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        type: TransactionType,
        amount: Int,
        date: Date,
        categoryId: String,
        memo: String = "",
        allocations: [Allocation] = [],
        recurringId: UUID? = nil,
        receiptImagePath: String? = nil,
        lineItems: [ReceiptLineItem] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.date = date
        self.categoryId = categoryId
        self.memo = memo
        self.allocations = allocations
        self.recurringId = recurringId
        self.receiptImagePath = receiptImagePath
        self.lineItems = lineItems
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PPCategory {
    @Attribute(.unique) var id: String
    var name: String
    var type: CategoryType
    var icon: String
    var isDefault: Bool

    init(
        id: String,
        name: String,
        type: CategoryType,
        icon: String,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.icon = icon
        self.isDefault = isDefault
    }
}

@Model
final class PPRecurringTransaction {
    @Attribute(.unique) var id: UUID
    var name: String
    var type: TransactionType
    var amount: Int
    var categoryId: String
    var memo: String
    var allocationMode: AllocationMode?
    var allocations: [Allocation]
    var frequency: RecurringFrequency
    var dayOfMonth: Int
    var monthOfYear: Int?
    var isActive: Bool
    var endDate: Date?
    var lastGeneratedDate: Date?
    var skipDates: [Date]
    var yearlyAmortizationMode: YearlyAmortizationMode?  // nil = .lumpSum
    var lastGeneratedMonths: [String]  // ["2026-01", "2026-02", ...] 月次分割の生成追跡用
    var notificationTiming: NotificationTiming
    var receiptImagePath: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        type: TransactionType,
        amount: Int,
        categoryId: String,
        memo: String = "",
        allocationMode: AllocationMode = .manual,
        allocations: [Allocation] = [],
        frequency: RecurringFrequency = .monthly,
        dayOfMonth: Int = 1,
        monthOfYear: Int? = nil,
        isActive: Bool = true,
        endDate: Date? = nil,
        lastGeneratedDate: Date? = nil,
        skipDates: [Date] = [],
        yearlyAmortizationMode: YearlyAmortizationMode? = nil,
        lastGeneratedMonths: [String] = [],
        notificationTiming: NotificationTiming = .none,
        receiptImagePath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.amount = amount
        self.categoryId = categoryId
        self.memo = memo
        self.allocationMode = allocationMode
        self.allocations = allocations
        self.frequency = frequency
        self.dayOfMonth = min(28, max(1, dayOfMonth))
        self.monthOfYear = frequency == .yearly ? monthOfYear : nil
        self.isActive = isActive
        self.endDate = endDate
        self.lastGeneratedDate = lastGeneratedDate
        self.skipDates = skipDates
        self.yearlyAmortizationMode = yearlyAmortizationMode
        self.lastGeneratedMonths = lastGeneratedMonths
        self.notificationTiming = notificationTiming
        self.receiptImagePath = receiptImagePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Default Categories

let DEFAULT_CATEGORIES: [(id: String, name: String, type: CategoryType, icon: String)] = [
    ("cat-hosting", "ホスティング", .expense, "server.rack"),
    ("cat-tools", "ツール", .expense, "wrench.and.screwdriver"),
    ("cat-ads", "広告", .expense, "megaphone"),
    ("cat-contractor", "請負業者", .expense, "person.2"),
    ("cat-communication", "通信費", .expense, "wifi"),
    ("cat-supplies", "消耗品", .expense, "shippingbox"),
    ("cat-transport", "交通費", .expense, "car"),
    ("cat-food", "食費・飲食", .expense, "fork.knife"),
    ("cat-entertainment", "接待・会議費", .expense, "person.2.wave.2"),
    ("cat-other-expense", "その他経費", .expense, "ellipsis.circle"),
    ("cat-sales", "売上", .income, "yensign.circle"),
    ("cat-service", "サービス収入", .income, "briefcase"),
    ("cat-other-income", "その他収入", .income, "plus.circle"),
]

// MARK: - Summary Types

struct ProjectSummary: Identifiable {
    let id: UUID
    let projectName: String
    let status: ProjectStatus
    let totalIncome: Int
    let totalExpense: Int
    let profit: Int
    let profitMargin: Double

    var projectId: UUID { id }
}

struct OverallSummary {
    let totalIncome: Int
    let totalExpense: Int
    let netProfit: Int
    let profitMargin: Double
}

struct CategorySummary: Identifiable {
    let categoryId: String
    let categoryName: String
    let total: Int
    let percentage: Double

    var id: String { categoryId }
}

struct MonthlySummary: Identifiable {
    let month: String
    let income: Int
    let expense: Int
    let profit: Int

    var id: String { month }
}

struct FiscalYearProjectSummary: Identifiable {
    let fiscalYear: Int
    let label: String
    let income: Int
    let expense: Int
    let profit: Int

    var id: Int { fiscalYear }
}

// MARK: - Filter/Sort Types

struct TransactionFilter {
    var startDate: Date?
    var endDate: Date?
    var projectId: UUID?
    var categoryId: String?
    var type: TransactionType?
}

struct TransactionSort {
    var field: SortField = .date
    var order: SortOrder = .desc

    enum SortField: String {
        case date
        case amount
    }

    enum SortOrder: String {
        case asc
        case desc
    }
}
