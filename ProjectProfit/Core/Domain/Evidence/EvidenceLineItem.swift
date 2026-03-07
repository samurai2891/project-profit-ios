import Foundation

/// 証憑の明細行
struct EvidenceLineItem: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let description: String
    let quantity: Decimal?
    let unitPrice: Decimal?
    let lineAmount: Decimal
    let taxRate: Decimal?
    let isTaxIncluded: Bool

    init(
        id: UUID = UUID(),
        description: String,
        quantity: Decimal? = nil,
        unitPrice: Decimal? = nil,
        lineAmount: Decimal,
        taxRate: Decimal? = nil,
        isTaxIncluded: Bool = true
    ) {
        self.id = id
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.lineAmount = lineAmount
        self.taxRate = taxRate
        self.isTaxIncluded = isTaxIncluded
    }
}
