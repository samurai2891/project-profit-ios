import Foundation

enum BackupScope: Equatable, Sendable, Codable {
    case full
    case taxYear(Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case taxYear
    }

    private enum Kind: String, Codable {
        case full
        case taxYear
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .full:
            self = .full
        case .taxYear:
            self = .taxYear(try container.decode(Int.self, forKey: .taxYear))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .full:
            try container.encode(Kind.full, forKey: .kind)
        case let .taxYear(taxYear):
            try container.encode(Kind.taxYear, forKey: .kind)
            try container.encode(taxYear, forKey: .taxYear)
        }
    }

    var label: String {
        switch self {
        case .full:
            return "full"
        case let .taxYear(year):
            return "taxYear-\(year)"
        }
    }
}

struct SnapshotFileRecord: Codable, Equatable, Sendable {
    enum Category: String, Codable, Sendable {
        case receiptImage
        case documentFile
        case settings
    }

    let category: Category
    let fileName: String
    let relativePath: String
    let byteCount: Int
    let sha256: String
}

struct SnapshotSecureProfile: Codable, Equatable, Sendable {
    let profileId: String
    let payload: ProfileSensitivePayload
}

struct SnapshotManifest: Codable, Equatable, Sendable {
    let snapshotId: UUID
    let createdAt: Date
    let scope: BackupScope
    let fiscalStartMonth: Int
    let payloadChecksum: String
    let securePayloadChecksum: String
    let fileRecords: [SnapshotFileRecord]
    let counts: [String: Int]
    let warnings: [String]
}

struct AppSnapshotPayload: Codable, Equatable, Sendable {
    let fiscalStartMonth: Int
    let legacy: LegacySnapshotSection
    let canonical: CanonicalSnapshotSection
}

struct LegacySnapshotSection: Codable, Equatable, Sendable {
    var projects: [LegacyProjectSnapshot]
    var categories: [LegacyCategorySnapshot]
    var recurringTransactions: [LegacyRecurringTransactionSnapshot]
    var transactions: [LegacyTransactionSnapshot]
    var accounts: [LegacyAccountSnapshot]
    var journalEntries: [LegacyJournalEntrySnapshot]
    var journalLines: [LegacyJournalLineSnapshot]
    /// Decode/restore compatibility only. New backups must keep this empty and use canonical profiles instead.
    var accountingProfiles: [LegacyAccountingProfileSnapshot]
    var userRules: [LegacyUserRuleSnapshot]
    var fixedAssets: [LegacyFixedAssetSnapshot]
    var inventoryRecords: [LegacyInventoryRecordSnapshot]
    var documentRecords: [LegacyDocumentRecordSnapshot]
    var complianceLogs: [LegacyComplianceLogSnapshot]
    var transactionLogs: [LegacyTransactionLogSnapshot]
    var ledgerBooks: [LegacyLedgerBookSnapshot]
    var ledgerEntries: [LegacyLedgerEntrySnapshot]
}

struct CanonicalSnapshotSection: Codable, Equatable, Sendable {
    var businessProfiles: [BusinessProfile]
    var taxYearProfiles: [TaxYearProfile]
    var evidenceDocuments: [EvidenceDocument]
    var postingCandidates: [PostingCandidate]
    var journalEntries: [CanonicalJournalEntry]
    var counterparties: [Counterparty]
    var accounts: [CanonicalAccount]
    var distributionRules: [DistributionRule]
    var auditEvents: [AuditEvent]
}

struct LegacyProjectSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let projectDescription: String
    let status: ProjectStatus
    let startDate: Date?
    let completedAt: Date?
    let plannedEndDate: Date?
    let isArchived: Bool?
    let createdAt: Date
    let updatedAt: Date

    init(_ project: PPProject) {
        self.id = project.id
        self.name = project.name
        self.projectDescription = project.projectDescription
        self.status = project.status
        self.startDate = project.startDate
        self.completedAt = project.completedAt
        self.plannedEndDate = project.plannedEndDate
        self.isArchived = project.isArchived
        self.createdAt = project.createdAt
        self.updatedAt = project.updatedAt
    }

    func toModel() -> PPProject {
        PPProject(
            id: id,
            name: name,
            projectDescription: projectDescription,
            status: status,
            startDate: startDate,
            completedAt: completedAt,
            plannedEndDate: plannedEndDate,
            isArchived: isArchived,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct LegacyCategorySnapshot: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let type: CategoryType
    let icon: String
    let isDefault: Bool
    let linkedAccountId: String?
    let archivedAt: Date?

    init(_ category: PPCategory) {
        self.id = category.id
        self.name = category.name
        self.type = category.type
        self.icon = category.icon
        self.isDefault = category.isDefault
        self.linkedAccountId = category.linkedAccountId
        self.archivedAt = category.archivedAt
    }

    func toModel() -> PPCategory {
        PPCategory(
            id: id,
            name: name,
            type: type,
            icon: icon,
            isDefault: isDefault,
            linkedAccountId: linkedAccountId,
            archivedAt: archivedAt
        )
    }
}

struct LegacyRecurringTransactionSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let type: TransactionType
    let amount: Int
    let categoryId: String
    let memo: String
    let allocationMode: AllocationMode
    let allocations: [Allocation]
    let frequency: RecurringFrequency
    let dayOfMonth: Int
    let monthOfYear: Int?
    let isActive: Bool
    let endDate: Date?
    let lastGeneratedDate: Date?
    let skipDates: [Date]
    let yearlyAmortizationMode: YearlyAmortizationMode
    let lastGeneratedMonths: [String]
    let notificationTiming: NotificationTiming
    let receiptImagePath: String?
    let paymentAccountId: String?
    let transferToAccountId: String?
    let taxDeductibleRate: Int?
    let counterpartyId: UUID?
    let counterparty: String?
    let createdAt: Date
    let updatedAt: Date

    init(_ recurring: PPRecurringTransaction) {
        self.id = recurring.id
        self.name = recurring.name
        self.type = recurring.type
        self.amount = recurring.amount
        self.categoryId = recurring.categoryId
        self.memo = recurring.memo
        self.allocationMode = recurring.allocationMode
        self.allocations = recurring.allocations
        self.frequency = recurring.frequency
        self.dayOfMonth = recurring.dayOfMonth
        self.monthOfYear = recurring.monthOfYear
        self.isActive = recurring.isActive
        self.endDate = recurring.endDate
        self.lastGeneratedDate = recurring.lastGeneratedDate
        self.skipDates = recurring.skipDates
        self.yearlyAmortizationMode = recurring.yearlyAmortizationMode
        self.lastGeneratedMonths = recurring.lastGeneratedMonths
        self.notificationTiming = recurring.notificationTiming
        self.receiptImagePath = recurring.receiptImagePath
        self.paymentAccountId = recurring.paymentAccountId
        self.transferToAccountId = recurring.transferToAccountId
        self.taxDeductibleRate = recurring.taxDeductibleRate
        self.counterpartyId = recurring.counterpartyId
        self.counterparty = recurring.counterparty
        self.createdAt = recurring.createdAt
        self.updatedAt = recurring.updatedAt
    }

    func toModel() -> PPRecurringTransaction {
        PPRecurringTransaction(
            id: id,
            name: name,
            type: type,
            amount: amount,
            categoryId: categoryId,
            memo: memo,
            allocationMode: allocationMode,
            allocations: allocations,
            frequency: frequency,
            dayOfMonth: dayOfMonth,
            monthOfYear: monthOfYear,
            isActive: isActive,
            endDate: endDate,
            lastGeneratedDate: lastGeneratedDate,
            skipDates: skipDates,
            yearlyAmortizationMode: yearlyAmortizationMode,
            lastGeneratedMonths: lastGeneratedMonths,
            notificationTiming: notificationTiming,
            receiptImagePath: receiptImagePath,
            paymentAccountId: paymentAccountId,
            transferToAccountId: transferToAccountId,
            taxDeductibleRate: taxDeductibleRate,
            counterpartyId: counterpartyId,
            counterparty: counterparty,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct LegacyTransactionSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let type: TransactionType
    let amount: Int
    let date: Date
    let categoryId: String
    let memo: String
    let allocations: [Allocation]
    let recurringId: UUID?
    let receiptImagePath: String?
    let lineItems: [ReceiptLineItem]
    let isManuallyEdited: Bool?
    let paymentAccountId: String?
    let transferToAccountId: String?
    let taxDeductibleRate: Int?
    let bookkeepingMode: BookkeepingMode?
    let journalEntryId: UUID?
    let taxAmount: Int?
    let taxCodeId: String?
    /// Restore compatibility only. Canonical tax input is `taxCodeId`.
    let taxRate: Int?
    /// Restore compatibility only. Canonical tax identity is still `taxCodeId`.
    let isTaxIncluded: Bool?
    /// Restore compatibility only. Canonical tax input is `taxCodeId`.
    let taxCategory: TaxCategory?
    let counterpartyId: UUID?
    let counterparty: String?
    let deletedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    init(_ transaction: PPTransaction) {
        self.id = transaction.id
        self.type = transaction.type
        self.amount = transaction.amount
        self.date = transaction.date
        self.categoryId = transaction.categoryId
        self.memo = transaction.memo
        self.allocations = transaction.allocations
        self.recurringId = transaction.recurringId
        self.receiptImagePath = transaction.receiptImagePath
        self.lineItems = transaction.lineItems
        self.isManuallyEdited = transaction.isManuallyEdited
        self.paymentAccountId = transaction.paymentAccountId
        self.transferToAccountId = transaction.transferToAccountId
        self.taxDeductibleRate = transaction.taxDeductibleRate
        self.bookkeepingMode = transaction.bookkeepingMode
        self.journalEntryId = transaction.journalEntryId
        self.taxAmount = transaction.taxAmount
        self.taxCodeId = transaction.taxCodeId
        self.taxRate = transaction.taxRate
        self.isTaxIncluded = transaction.isTaxIncluded
        self.taxCategory = transaction.taxCategory
        self.counterpartyId = transaction.counterpartyId
        self.counterparty = transaction.counterparty
        self.deletedAt = transaction.deletedAt
        self.createdAt = transaction.createdAt
        self.updatedAt = transaction.updatedAt
    }

    func toModel() -> PPTransaction {
        PPTransaction.makeCompatibilityTransaction(
            id: id,
            type: type,
            amount: amount,
            date: date,
            categoryId: categoryId,
            memo: memo,
            allocations: allocations,
            recurringId: recurringId,
            receiptImagePath: receiptImagePath,
            lineItems: lineItems,
            isManuallyEdited: isManuallyEdited,
            paymentAccountId: paymentAccountId,
            transferToAccountId: transferToAccountId,
            taxDeductibleRate: taxDeductibleRate,
            bookkeepingMode: bookkeepingMode,
            journalEntryId: journalEntryId,
            taxAmount: taxAmount,
            taxCodeId: taxCodeId,
            taxRate: taxRate,
            isTaxIncluded: isTaxIncluded,
            taxCategory: taxCategory,
            counterpartyId: counterpartyId,
            counterparty: counterparty,
            deletedAt: deletedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct LegacyAccountSnapshot: Codable, Equatable, Sendable {
    let id: String
    let code: String
    let name: String
    let accountType: AccountType
    let normalBalance: NormalBalance
    let subtype: AccountSubtype?
    let parentAccountId: String?
    let isSystem: Bool
    let isActive: Bool
    let displayOrder: Int
    let createdAt: Date
    let updatedAt: Date

    init(_ account: PPAccount) {
        self.id = account.id
        self.code = account.code
        self.name = account.name
        self.accountType = account.accountType
        self.normalBalance = account.normalBalance
        self.subtype = account.subtype
        self.parentAccountId = account.parentAccountId
        self.isSystem = account.isSystem
        self.isActive = account.isActive
        self.displayOrder = account.displayOrder
        self.createdAt = account.createdAt
        self.updatedAt = account.updatedAt
    }

    func toModel() -> PPAccount {
        PPAccount(
            id: id,
            code: code,
            name: name,
            accountType: accountType,
            normalBalance: normalBalance,
            subtype: subtype,
            parentAccountId: parentAccountId,
            isSystem: isSystem,
            isActive: isActive,
            displayOrder: displayOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct LegacyJournalEntrySnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let sourceKey: String
    let date: Date
    let entryType: JournalEntryType
    let memo: String
    let isPosted: Bool
    let createdAt: Date
    let updatedAt: Date

    init(_ entry: PPJournalEntry) {
        self.id = entry.id
        self.sourceKey = entry.sourceKey
        self.date = entry.date
        self.entryType = entry.entryType
        self.memo = entry.memo
        self.isPosted = entry.isPosted
        self.createdAt = entry.createdAt
        self.updatedAt = entry.updatedAt
    }

    func toModel() -> PPJournalEntry {
        PPJournalEntry(
            id: id,
            sourceKey: sourceKey,
            date: date,
            entryType: entryType,
            memo: memo,
            isPosted: isPosted,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct LegacyJournalLineSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let entryId: UUID
    let accountId: String
    let debit: Int
    let credit: Int
    let memo: String
    let displayOrder: Int
    let createdAt: Date
    let updatedAt: Date

    init(_ line: PPJournalLine) {
        self.id = line.id
        self.entryId = line.entryId
        self.accountId = line.accountId
        self.debit = line.debit
        self.credit = line.credit
        self.memo = line.memo
        self.displayOrder = line.displayOrder
        self.createdAt = line.createdAt
        self.updatedAt = line.updatedAt
    }

    func toModel() -> PPJournalLine {
        PPJournalLine(
            id: id,
            entryId: entryId,
            accountId: accountId,
            debit: debit,
            credit: credit,
            memo: memo,
            displayOrder: displayOrder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@available(*, deprecated, message: "Legacy profile snapshots are restore-compat only. New backups must use canonical profiles.")
struct LegacyAccountingProfileSnapshot: Codable, Equatable, Sendable {
    let id: String
    let fiscalYear: Int
    let bookkeepingMode: BookkeepingMode
    let businessName: String
    let ownerName: String
    let taxOfficeCode: String?
    let isBlueReturn: Bool
    let defaultPaymentAccountId: String
    let openingDate: Date?
    /// Old archive compatibility only. Current-format snapshots must use canonical taxYearProfiles.
    let lockedAt: Date?
    let ownerNameKana: String?
    let postalCode: String?
    let address: String?
    let phoneNumber: String?
    let dateOfBirth: Date?
    let businessCategory: String?
    let myNumberFlag: Bool?
    let createdAt: Date
    let updatedAt: Date

    init(_ profile: PPAccountingProfile) {
        self.id = profile.id
        self.fiscalYear = profile.fiscalYear
        self.bookkeepingMode = profile.bookkeepingMode
        self.businessName = profile.businessName
        self.ownerName = profile.ownerName
        self.taxOfficeCode = profile.taxOfficeCode
        self.isBlueReturn = profile.isBlueReturn
        self.defaultPaymentAccountId = profile.defaultPaymentAccountId
        self.openingDate = profile.openingDate
        self.lockedAt = profile.lockedAt
        self.ownerNameKana = profile.ownerNameKana
        self.postalCode = profile.postalCode
        self.address = profile.address
        self.phoneNumber = profile.phoneNumber
        self.dateOfBirth = profile.dateOfBirth
        self.businessCategory = profile.businessCategory
        self.myNumberFlag = profile.myNumberFlag
        self.createdAt = profile.createdAt
        self.updatedAt = profile.updatedAt
    }

    /// Restore compatibility only. New snapshots should persist BusinessProfile instead.
    func toBusinessProfile(
        existingId: UUID? = nil,
        sensitivePayload: ProfileSensitivePayload? = nil
    ) -> BusinessProfile {
        BusinessProfile(
            id: existingId ?? UUID(),
            ownerName: ownerName,
            ownerNameKana: normalized(sensitivePayload?.ownerNameKana ?? ownerNameKana),
            businessName: businessName,
            defaultPaymentAccountId: defaultPaymentAccountId,
            businessAddress: normalized(sensitivePayload?.address ?? address),
            postalCode: normalized(sensitivePayload?.postalCode ?? postalCode),
            phoneNumber: normalized(sensitivePayload?.phoneNumber ?? phoneNumber),
            openingDate: openingDate,
            taxOfficeCode: normalized(taxOfficeCode),
            invoiceRegistrationNumber: nil,
            invoiceIssuerStatus: .unknown,
            defaultCurrency: "JPY",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Restore compatibility only. New snapshots should persist TaxYearProfile instead.
    func toTaxYearProfile(
        businessId: UUID,
        taxPackVersion: String = "legacy-restored",
        existingId: UUID? = nil
    ) -> TaxYearProfile {
        let bookkeepingBasis: BookkeepingBasis = switch bookkeepingMode {
        case .singleEntry:
            .singleEntry
        case .doubleEntry, .auto, .locked:
            .doubleEntry
        }
        let blueDeductionLevel: BlueDeductionLevel = {
            guard isBlueReturn else {
                return .none
            }
            switch bookkeepingMode {
            case .singleEntry:
                return .ten
            case .doubleEntry, .auto, .locked:
                return .sixtyFive
            }
        }()

        return TaxYearProfile(
            id: existingId ?? UUID(),
            businessId: businessId,
            taxYear: fiscalYear,
            filingStyle: isBlueReturn ? .blueGeneral : .white,
            blueDeductionLevel: blueDeductionLevel,
            bookkeepingBasis: bookkeepingBasis,
            vatStatus: .exempt,
            vatMethod: .general,
            simplifiedBusinessCategory: nil,
            invoiceIssuerStatusAtYear: .unknown,
            electronicBookLevel: .none,
            etaxSubmissionPlanned: false,
            yearLockState: lockedAt == nil ? .open : .finalLock,
            taxPackVersion: taxPackVersion,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    @available(*, deprecated, message: "Legacy profile snapshots are restore-compat only. Convert to canonical profiles instead.")
    func toModel() -> PPAccountingProfile {
        PPAccountingProfile(
            id: id,
            fiscalYear: fiscalYear,
            bookkeepingMode: bookkeepingMode,
            businessName: businessName,
            ownerName: ownerName,
            taxOfficeCode: taxOfficeCode,
            isBlueReturn: isBlueReturn,
            defaultPaymentAccountId: defaultPaymentAccountId,
            openingDate: openingDate,
            lockedAt: lockedAt,
            ownerNameKana: ownerNameKana,
            postalCode: postalCode,
            address: address,
            phoneNumber: phoneNumber,
            dateOfBirth: dateOfBirth,
            businessCategory: businessCategory,
            myNumberFlag: myNumberFlag,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct LegacyUserRuleSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let keyword: String
    let taxLine: TaxLine
    let priority: Int
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date

    init(_ rule: PPUserRule) {
        self.id = rule.id
        self.keyword = rule.keyword
        self.taxLine = rule.taxLine
        self.priority = rule.priority
        self.isActive = rule.isActive
        self.createdAt = rule.createdAt
        self.updatedAt = rule.updatedAt
    }

    func toModel() -> PPUserRule {
        PPUserRule(
            id: id,
            keyword: keyword,
            taxLine: taxLine,
            priority: priority,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct LegacyFixedAssetSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let acquisitionDate: Date
    let acquisitionCost: Int
    let usefulLifeYears: Int
    let depreciationMethod: PPDepreciationMethod
    let salvageValue: Int
    let assetStatus: PPAssetStatus
    let disposalDate: Date?
    let disposalAmount: Int?
    let memo: String?
    let businessUsePercent: Int
    let createdAt: Date
    let updatedAt: Date

    init(_ asset: PPFixedAsset) {
        self.id = asset.id
        self.name = asset.name
        self.acquisitionDate = asset.acquisitionDate
        self.acquisitionCost = asset.acquisitionCost
        self.usefulLifeYears = asset.usefulLifeYears
        self.depreciationMethod = asset.depreciationMethod
        self.salvageValue = asset.salvageValue
        self.assetStatus = asset.assetStatus
        self.disposalDate = asset.disposalDate
        self.disposalAmount = asset.disposalAmount
        self.memo = asset.memo
        self.businessUsePercent = asset.businessUsePercent
        self.createdAt = asset.createdAt
        self.updatedAt = asset.updatedAt
    }

    func toModel() -> PPFixedAsset {
        PPFixedAsset(
            id: id,
            name: name,
            acquisitionDate: acquisitionDate,
            acquisitionCost: acquisitionCost,
            usefulLifeYears: usefulLifeYears,
            depreciationMethod: depreciationMethod,
            salvageValue: salvageValue,
            assetStatus: assetStatus,
            disposalDate: disposalDate,
            disposalAmount: disposalAmount,
            memo: memo,
            businessUsePercent: businessUsePercent,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct LegacyInventoryRecordSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let fiscalYear: Int
    let openingInventory: Int
    let purchases: Int
    let closingInventory: Int
    let memo: String?
    let createdAt: Date
    let updatedAt: Date

    init(_ record: PPInventoryRecord) {
        self.id = record.id
        self.fiscalYear = record.fiscalYear
        self.openingInventory = record.openingInventory
        self.purchases = record.purchases
        self.closingInventory = record.closingInventory
        self.memo = record.memo
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
    }

    func toModel() -> PPInventoryRecord {
        PPInventoryRecord(
            id: id,
            fiscalYear: fiscalYear,
            openingInventory: openingInventory,
            purchases: purchases,
            closingInventory: closingInventory,
            memo: memo,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct LegacyDocumentRecordSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let transactionId: UUID?
    let documentType: LegalDocumentType
    let retentionCategory: RetentionCategory
    let retentionYears: Int
    let storedFileName: String
    let originalFileName: String
    let mimeType: String?
    let fileSize: Int
    let contentHash: String?
    let issueDate: Date
    let note: String
    let createdAt: Date
    let updatedAt: Date

    init(_ record: PPDocumentRecord) {
        self.id = record.id
        self.transactionId = record.transactionId
        self.documentType = record.documentType
        self.retentionCategory = record.retentionCategory
        self.retentionYears = record.retentionYears
        self.storedFileName = record.storedFileName
        self.originalFileName = record.originalFileName
        self.mimeType = record.mimeType
        self.fileSize = record.fileSize
        self.contentHash = record.contentHash
        self.issueDate = record.issueDate
        self.note = record.note
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
    }

    func toModel() -> PPDocumentRecord {
        PPDocumentRecord(
            id: id,
            transactionId: transactionId,
            documentType: documentType,
            retentionCategory: retentionCategory,
            retentionYears: retentionYears,
            storedFileName: storedFileName,
            originalFileName: originalFileName,
            mimeType: mimeType,
            fileSize: fileSize,
            contentHash: contentHash,
            issueDate: issueDate,
            note: note,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct LegacyComplianceLogSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let eventType: ComplianceEventType
    let message: String
    let documentId: UUID?
    let transactionId: UUID?
    let createdAt: Date

    init(_ log: PPComplianceLog) {
        self.id = log.id
        self.eventType = log.eventType
        self.message = log.message
        self.documentId = log.documentId
        self.transactionId = log.transactionId
        self.createdAt = log.createdAt
    }

    func toModel() -> PPComplianceLog {
        PPComplianceLog(
            id: id,
            eventType: eventType,
            message: message,
            documentId: documentId,
            transactionId: transactionId,
            createdAt: createdAt
        )
    }
}

struct LegacyTransactionLogSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let transactionId: UUID
    let fieldName: String
    let oldValue: String?
    let newValue: String?
    let changedAt: Date

    init(_ log: PPTransactionLog) {
        self.id = log.id
        self.transactionId = log.transactionId
        self.fieldName = log.fieldName
        self.oldValue = log.oldValue
        self.newValue = log.newValue
        self.changedAt = log.changedAt
    }

    func toModel() -> PPTransactionLog {
        PPTransactionLog(
            id: id,
            transactionId: transactionId,
            fieldName: fieldName,
            oldValue: oldValue,
            newValue: newValue,
            changedAt: changedAt
        )
    }
}

struct LegacyLedgerBookSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let ledgerTypeRaw: String
    let title: String
    let metadataJSON: String
    let includeInvoice: Bool
    let createdAt: Date
    let updatedAt: Date

    init(_ book: SDLedgerBook) {
        self.id = book.id
        self.ledgerTypeRaw = book.ledgerTypeRaw
        self.title = book.title
        self.metadataJSON = book.metadataJSON
        self.includeInvoice = book.includeInvoice
        self.createdAt = book.createdAt
        self.updatedAt = book.updatedAt
    }

    func toModel() -> SDLedgerBook {
        let book = SDLedgerBook(
            id: id,
            ledgerType: LedgerType(rawValue: ledgerTypeRaw) ?? .cashBook,
            title: title,
            metadataJSON: metadataJSON,
            includeInvoice: includeInvoice
        )
        book.createdAt = createdAt
        book.updatedAt = updatedAt
        return book
    }
}

struct LegacyLedgerEntrySnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let bookId: UUID
    let entryJSON: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date

    init(_ entry: SDLedgerEntry) {
        self.id = entry.id
        self.bookId = entry.bookId
        self.entryJSON = entry.entryJSON
        self.sortOrder = entry.sortOrder
        self.createdAt = entry.createdAt
        self.updatedAt = entry.updatedAt
    }

    func toModel() -> SDLedgerEntry {
        let entry = SDLedgerEntry(
            id: id,
            bookId: bookId,
            entryJSON: entryJSON,
            sortOrder: sortOrder
        )
        entry.createdAt = createdAt
        entry.updatedAt = updatedAt
        return entry
    }
}
