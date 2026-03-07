import Foundation

/// 証憑の構造化フィールド（OCR抽出結果やユーザー入力）
struct EvidenceStructuredFields: Codable, Sendable, Equatable {
    let counterpartyName: String?
    let registrationNumber: String?
    let invoiceNumber: String?
    let transactionDate: Date?
    let subtotalStandardRate: Decimal?
    let taxStandardRate: Decimal?
    let subtotalReducedRate: Decimal?
    let taxReducedRate: Decimal?
    let totalAmount: Decimal?
    let paymentMethod: String?
    let lineItems: [EvidenceLineItem]
    let confidence: Double?

    init(
        counterpartyName: String? = nil,
        registrationNumber: String? = nil,
        invoiceNumber: String? = nil,
        transactionDate: Date? = nil,
        subtotalStandardRate: Decimal? = nil,
        taxStandardRate: Decimal? = nil,
        subtotalReducedRate: Decimal? = nil,
        taxReducedRate: Decimal? = nil,
        totalAmount: Decimal? = nil,
        paymentMethod: String? = nil,
        lineItems: [EvidenceLineItem] = [],
        confidence: Double? = nil
    ) {
        self.counterpartyName = counterpartyName
        self.registrationNumber = registrationNumber
        self.invoiceNumber = invoiceNumber
        self.transactionDate = transactionDate
        self.subtotalStandardRate = subtotalStandardRate
        self.taxStandardRate = taxStandardRate
        self.subtotalReducedRate = subtotalReducedRate
        self.taxReducedRate = taxReducedRate
        self.totalAmount = totalAmount
        self.paymentMethod = paymentMethod
        self.lineItems = lineItems
        self.confidence = confidence
    }
}
