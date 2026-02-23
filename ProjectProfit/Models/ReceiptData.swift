import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Line Item

struct LineItem: Sendable, Hashable, Codable {
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

// MARK: - Foundation Models Extraction (iOS 26+)

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
struct LineItemExtraction {
    @Guide(description: "品目名")
    var name: String

    @Guide(description: "数量（整数、デフォルト1）")
    var quantity: Int

    @Guide(description: "単価（整数、円単位）")
    var unitPrice: Int

    @Guide(description: "小計（整数、円単位）")
    var subtotal: Int
}

@available(iOS 26, *)
@Generable
struct ReceiptExtraction {
    @Guide(description: "レシートの合計金額（税込、整数、円単位）。お預り・お釣り・支払い方法の金額は除外すること")
    var totalAmount: Int

    @Guide(description: "消費税額（整数、円単位、不明なら0）")
    var taxAmount: Int

    @Guide(description: "日付 yyyy-MM-dd形式")
    var date: String

    @Guide(description: "店舗名・発行者名")
    var storeName: String

    @Guide(description: "推定カテゴリ: hosting, tools, ads, contractor, communication, supplies, transport, food, entertainment, other-expense のいずれか")
    var estimatedCategory: String

    @Guide(description: "明細の要約（品目名など）")
    var itemSummary: String
}

@available(iOS 26, *)
@Generable
struct LineItemsExtraction {
    @Guide(description: "レシートの明細行リスト")
    var items: [LineItemExtraction]
}
#endif

// MARK: - Receipt Data

struct ReceiptData: Sendable, Hashable {
    let totalAmount: Int
    let taxAmount: Int
    let subtotalAmount: Int
    let date: String
    let storeName: String
    let estimatedCategory: String
    let itemSummary: String
    let lineItems: [LineItem]

    init(
        totalAmount: Int,
        taxAmount: Int = 0,
        subtotalAmount: Int = 0,
        date: String,
        storeName: String,
        estimatedCategory: String,
        itemSummary: String,
        lineItems: [LineItem] = []
    ) {
        self.totalAmount = totalAmount
        self.taxAmount = taxAmount
        self.subtotalAmount = subtotalAmount
        self.date = date
        self.storeName = storeName
        self.estimatedCategory = estimatedCategory
        self.itemSummary = itemSummary
        self.lineItems = lineItems
    }

    var categoryId: String {
        let mapping: [String: String] = [
            "hosting": "cat-hosting",
            "tools": "cat-tools",
            "ads": "cat-ads",
            "contractor": "cat-contractor",
            "communication": "cat-communication",
            "supplies": "cat-supplies",
            "transport": "cat-transport",
            "food": "cat-food",
            "entertainment": "cat-entertainment",
            "other-expense": "cat-other-expense",
        ]
        return mapping[estimatedCategory] ?? "cat-other-expense"
    }

    var parsedDate: Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.date(from: date) ?? Date()
    }

    var formattedMemo: String {
        var parts: [String] = []
        if !storeName.isEmpty {
            parts.append("[レシート] \(storeName)")
        } else {
            parts.append("[レシート]")
        }
        if !lineItems.isEmpty {
            let itemNames = lineItems.prefix(3).map(\.name).joined(separator: "、")
            parts.append(itemNames)
        } else if !itemSummary.isEmpty {
            parts.append(itemSummary)
        }
        return parts.joined(separator: " - ")
    }
}
