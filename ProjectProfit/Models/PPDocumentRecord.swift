import Foundation
import SwiftData

enum RetentionCategory: String, Codable, CaseIterable, Sendable {
    case books
    case financialStatements
    case cashBankDocuments
    case otherBusinessDocuments

    var label: String {
        switch self {
        case .books: "帳簿"
        case .financialStatements: "決算関係書類"
        case .cashBankDocuments: "現金預金取引等関係書類"
        case .otherBusinessDocuments: "その他の書類"
        }
    }

    var retentionYears: Int {
        switch self {
        case .otherBusinessDocuments:
            5
        case .books, .financialStatements, .cashBankDocuments:
            7
        }
    }
}

enum LegalDocumentType: String, Codable, CaseIterable, Sendable {
    case receipt
    case checkStub
    case passbook
    case promissoryNote
    case invoice
    case quotation
    case contract
    case deliveryNote
    case shippingSlip
    case financialStatement
    case other

    var label: String {
        switch self {
        case .receipt: "領収証"
        case .checkStub: "小切手控"
        case .passbook: "預金通帳"
        case .promissoryNote: "借用証"
        case .invoice: "請求書"
        case .quotation: "見積書"
        case .contract: "契約書"
        case .deliveryNote: "納品書"
        case .shippingSlip: "送り状"
        case .financialStatement: "決算関係書類"
        case .other: "その他"
        }
    }

    var retentionCategory: RetentionCategory {
        switch self {
        case .financialStatement:
            .financialStatements
        case .receipt, .checkStub, .passbook, .promissoryNote:
            .cashBankDocuments
        case .invoice, .quotation, .contract, .deliveryNote, .shippingSlip, .other:
            .otherBusinessDocuments
        }
    }
}

enum ComplianceEventType: String, Codable, CaseIterable, Sendable {
    case documentAdded
    case retentionWarningShown
    case retentionWarningConfirmedDeletion
    case documentDeleted
}

@Model
final class PPDocumentRecord {
    @Attribute(.unique) var id: UUID
    var transactionId: UUID?
    var documentType: LegalDocumentType
    var retentionCategory: RetentionCategory
    var retentionYears: Int
    var storedFileName: String
    var originalFileName: String
    var mimeType: String?
    var fileSize: Int
    var contentHash: String?
    var issueDate: Date
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        transactionId: UUID? = nil,
        documentType: LegalDocumentType,
        retentionCategory: RetentionCategory? = nil,
        retentionYears: Int? = nil,
        storedFileName: String,
        originalFileName: String,
        mimeType: String? = nil,
        fileSize: Int,
        contentHash: String? = nil,
        issueDate: Date = Date(),
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.transactionId = transactionId
        self.documentType = documentType
        let category = retentionCategory ?? documentType.retentionCategory
        self.retentionCategory = category
        self.retentionYears = retentionYears ?? category.retentionYears
        self.storedFileName = storedFileName
        self.originalFileName = originalFileName
        self.mimeType = mimeType
        self.fileSize = max(0, fileSize)
        self.contentHash = contentHash
        self.issueDate = issueDate
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension PPDocumentRecord {
    var retentionDeadline: Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: issueDate)
        let years = max(0, retentionYears)
        return calendar.date(byAdding: .year, value: years, to: start) ?? start
    }

    func retentionWarningMessage(referenceDate: Date = Date()) -> String? {
        let now = Calendar.current.startOfDay(for: referenceDate)
        if now < retentionDeadline {
            return "\(documentType.label) は保存期間（\(retentionYears)年）内です。削除前に要否を確認してください。"
        }
        return nil
    }
}

@Model
final class PPComplianceLog {
    @Attribute(.unique) var id: UUID
    var eventType: ComplianceEventType
    var message: String
    var documentId: UUID?
    var transactionId: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        eventType: ComplianceEventType,
        message: String,
        documentId: UUID? = nil,
        transactionId: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.eventType = eventType
        self.message = message
        self.documentId = documentId
        self.transactionId = transactionId
        self.createdAt = createdAt
    }
}
