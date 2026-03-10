import CryptoKit
import Foundation
import SwiftData

enum ReceiptEvidenceIntakeUseCaseError: LocalizedError {
    case businessProfileUnavailable
    case invalidFileData
    case duplicateEvidence(existingEvidenceId: UUID, fileHash: String)

    var errorDescription: String? {
        switch self {
        case .businessProfileUnavailable:
            return "事業者プロフィールが見つかりません"
        case .invalidFileData:
            return "書類ファイルの保存に失敗しました"
        case let .duplicateEvidence(existingEvidenceId, _):
            return "同一ファイルの証憑が既に登録されています（evidenceId: \(existingEvidenceId.uuidString)）"
        }
    }
}

struct ReceiptEvidenceIntakeRequest {
    let receiptData: ReceiptData
    let ocrText: String
    let sourceType: EvidenceSourceType
    let fileData: Data
    let originalFileName: String
    let mimeType: String
    let reviewedAmount: Int
    let reviewedDate: Date
    let transactionType: TransactionType
    let categoryId: String
    let memo: String
    let lineItems: [LineItem]
    let linkedProjectIds: [UUID]
    let paymentAccountId: String?
    let transferToAccountId: String?
    let taxDeductibleRate: Int
    let taxCodeId: String?
    let isTaxIncluded: Bool
    let taxAmount: Int?
    let registrationNumber: String?
    let counterpartyId: UUID?
    let counterpartyName: String?
}

struct ReceiptEvidenceIntakeResult {
    let evidence: EvidenceDocument
    let candidate: PostingCandidate
    let documentRecordId: UUID
    let duplicateDetected: Bool
}

@MainActor
struct ReceiptEvidenceIntakeUseCase {
    private let modelContext: ModelContext
    private let businessProfileRepository: any BusinessProfileRepository
    private let evidenceCatalogUseCase: EvidenceCatalogUseCase
    private let counterpartyMasterUseCase: CounterpartyMasterUseCase
    private let chartOfAccountsUseCase: ChartOfAccountsUseCase
    private let postingWorkflowUseCase: PostingWorkflowUseCase
    private let auditRepository: any AuditRepository

    init(
        modelContext: ModelContext,
        businessProfileRepository: any BusinessProfileRepository,
        evidenceCatalogUseCase: EvidenceCatalogUseCase,
        counterpartyMasterUseCase: CounterpartyMasterUseCase,
        chartOfAccountsUseCase: ChartOfAccountsUseCase,
        postingWorkflowUseCase: PostingWorkflowUseCase,
        auditRepository: any AuditRepository
    ) {
        self.modelContext = modelContext
        self.businessProfileRepository = businessProfileRepository
        self.evidenceCatalogUseCase = evidenceCatalogUseCase
        self.counterpartyMasterUseCase = counterpartyMasterUseCase
        self.chartOfAccountsUseCase = chartOfAccountsUseCase
        self.postingWorkflowUseCase = postingWorkflowUseCase
        self.auditRepository = auditRepository
    }

    init(modelContext: ModelContext) {
        self.init(
            modelContext: modelContext,
            businessProfileRepository: SwiftDataBusinessProfileRepository(modelContext: modelContext),
            evidenceCatalogUseCase: EvidenceCatalogUseCase(modelContext: modelContext),
            counterpartyMasterUseCase: CounterpartyMasterUseCase(modelContext: modelContext),
            chartOfAccountsUseCase: ChartOfAccountsUseCase(modelContext: modelContext),
            postingWorkflowUseCase: PostingWorkflowUseCase(modelContext: modelContext),
            auditRepository: SwiftDataAuditRepository(modelContext: modelContext)
        )
    }

    func intake(_ request: ReceiptEvidenceIntakeRequest) async throws -> ReceiptEvidenceIntakeResult {
        guard !request.fileData.isEmpty else {
            throw ReceiptEvidenceIntakeUseCaseError.invalidFileData
        }
        guard let businessProfile = try await businessProfileRepository.findDefault() else {
            throw ReceiptEvidenceIntakeUseCaseError.businessProfileUnavailable
        }

        let businessId = businessProfile.id
        let taxYear = fiscalYear(for: request.reviewedDate, startMonth: FiscalYearSettings.startMonth)
        let contentHash = ReceiptImageStore.sha256Hex(data: request.fileData)
        if let existingEvidenceId = try existingEvidenceId(businessId: businessId, fileHash: contentHash) {
            throw ReceiptEvidenceIntakeUseCaseError.duplicateEvidence(
                existingEvidenceId: existingEvidenceId,
                fileHash: contentHash
            )
        }
        let storedFileName = try ReceiptImageStore.saveDocumentData(
            request.fileData,
            originalFileName: request.originalFileName
        )
        let counterpartyId = try await matchedCounterpartyId(
            businessId: businessId,
            explicitId: request.counterpartyId,
            registrationNumber: request.registrationNumber,
            name: request.counterpartyName,
            defaultTaxCodeId: request.taxCodeId
        )
        let evidence = EvidenceDocument(
            businessId: businessId,
            taxYear: taxYear,
            sourceType: request.sourceType,
            legalDocumentType: canonicalLegalDocumentType(for: request.receiptData.documentType),
            storageCategory: storageCategory(for: request.sourceType),
            receivedAt: Date(),
            issueDate: request.reviewedDate,
            paymentDate: nil,
            originalFilename: request.originalFileName,
            mimeType: request.mimeType,
            fileHash: contentHash,
            originalFilePath: storedFileName,
            ocrText: normalizedOptionalString(request.ocrText),
            extractionVersion: "receipt-review-v1",
            searchTokens: makeSearchTokens(from: request),
            structuredFields: makeStructuredFields(from: request),
            linkedCounterpartyId: counterpartyId,
            linkedProjectIds: Array(Set(request.linkedProjectIds)),
            complianceStatus: .pendingReview
        )

        let candidate = try await makePostingCandidate(
            request: request,
            businessId: businessId,
            taxYear: taxYear,
            evidenceId: evidence.id,
            counterpartyId: counterpartyId
        )

        do {
            try await evidenceCatalogUseCase.save(evidence)
        } catch {
            ReceiptImageStore.deleteDocumentFile(fileName: storedFileName)
            throw error
        }

        do {
            try await postingWorkflowUseCase.saveCandidate(candidate)
        } catch {
            try? await evidenceCatalogUseCase.delete(evidence.id)
            ReceiptImageStore.deleteDocumentFile(fileName: storedFileName)
            throw error
        }

        do {
            try await auditRepository.save(
                AuditEvent(
                    businessId: businessId,
                    eventType: .evidenceCreated,
                    aggregateType: "EvidenceDocument",
                    aggregateId: evidence.id,
                    beforeStateHash: nil,
                    afterStateHash: stateHash(evidence),
                    actor: "system",
                    reason: "receipt-intake",
                    relatedEvidenceId: evidence.id,
                    relatedJournalId: nil
                )
            )
            try await auditRepository.save(
                AuditEvent(
                    businessId: businessId,
                    eventType: .candidateCreated,
                    aggregateType: "PostingCandidate",
                    aggregateId: candidate.id,
                    beforeStateHash: nil,
                    afterStateHash: stateHash(candidate),
                    actor: "system",
                    reason: "receipt-intake",
                    relatedEvidenceId: evidence.id,
                    relatedJournalId: nil
                )
            )
        } catch {
            try? await postingWorkflowUseCase.deleteCandidate(candidate.id)
            try? await evidenceCatalogUseCase.delete(evidence.id)
            ReceiptImageStore.deleteDocumentFile(fileName: storedFileName)
            throw error
        }

        let documentRecord = PPDocumentRecord(
            transactionId: nil,
            documentType: legacyDocumentType(for: request.receiptData.documentType),
            storedFileName: storedFileName,
            originalFileName: request.originalFileName,
            mimeType: request.mimeType,
            fileSize: request.fileData.count,
            contentHash: contentHash,
            issueDate: request.reviewedDate,
            note: "evidence-intake"
        )
        let complianceLog = PPComplianceLog(
            eventType: .documentAdded,
            message: "書類登録: \(documentRecord.documentType.label) (\(documentRecord.originalFileName))",
            documentId: documentRecord.id,
            transactionId: nil
        )

        do {
            modelContext.insert(documentRecord)
            modelContext.insert(complianceLog)
            try modelContext.save()
            return ReceiptEvidenceIntakeResult(
                evidence: evidence,
                candidate: candidate,
                documentRecordId: documentRecord.id,
                duplicateDetected: false
            )
        } catch {
            modelContext.delete(documentRecord)
            modelContext.delete(complianceLog)
            try? await postingWorkflowUseCase.deleteCandidate(candidate.id)
            try? await evidenceCatalogUseCase.delete(evidence.id)
            ReceiptImageStore.deleteDocumentFile(fileName: storedFileName)
            throw error
        }
    }

    private func makePostingCandidate(
        request: ReceiptEvidenceIntakeRequest,
        businessId: UUID,
        taxYear: Int,
        evidenceId: UUID,
        counterpartyId: UUID?
    ) async throws -> PostingCandidate {
        let candidateDate = request.reviewedDate
        let lines = try await makePostingCandidateLines(
            request: request,
            businessId: businessId
        )

        return PostingCandidate(
            evidenceId: evidenceId,
            businessId: businessId,
            taxYear: taxYear,
            candidateDate: candidateDate,
            counterpartyId: counterpartyId,
            proposedLines: lines,
            taxAnalysis: nil,
            confidenceScore: request.receiptData.confidence,
            status: .needsReview,
            source: .ocr,
            memo: normalizedOptionalString(request.memo),
            legacySnapshot: PostingCandidateLegacySnapshot(
                type: request.transactionType,
                categoryId: request.categoryId,
                recurringId: nil,
                paymentAccountId: request.paymentAccountId,
                transferToAccountId: request.transferToAccountId,
                taxDeductibleRate: request.transactionType == .expense ? request.taxDeductibleRate : nil,
                taxAmount: resolvedTaxAmount(for: request),
                taxCodeId: resolvedTaxCode(for: request)?.rawValue,
                taxRate: resolvedTaxCode(for: request)?.taxRatePercent,
                isTaxIncluded: request.isTaxIncluded,
                taxCategory: resolvedTaxCode(for: request)?.legacyCategory,
                receiptImagePath: nil,
                lineItems: request.lineItems.map {
                    ReceiptLineItem(
                        name: $0.name,
                        quantity: $0.quantity,
                        unitPrice: $0.unitPrice,
                        subtotal: $0.subtotal
                    )
                },
                counterpartyName: normalizedOptionalString(request.counterpartyName)
            )
        )
    }

    private func makePostingCandidateLines(
        request: ReceiptEvidenceIntakeRequest,
        businessId: UUID
    ) async throws -> [PostingCandidateLine] {
        let amount = request.reviewedAmount
        let taxAmount = resolvedTaxAmount(for: request)
        let taxCodeId = resolvedTaxCode(for: request)?.rawValue
        let primaryMemo = normalizedOptionalString(request.memo)

        switch request.transactionType {
        case .income:
            let paymentAccountId = try await canonicalAccountId(
                businessId: businessId,
                legacyAccountId: request.paymentAccountId ?? AccountingConstants.defaultPaymentAccountId
            )
            let paymentAccountLegalReportLineId = try await defaultLegalReportLineId(accountId: paymentAccountId)
            let revenueAccountId = try await canonicalAccountId(
                businessId: businessId,
                legacyAccountId: resolveLinkedLegacyAccountId(
                    categoryId: request.categoryId,
                    fallback: AccountingConstants.salesAccountId
                )
            )
            let revenueAccountLegalReportLineId = try await defaultLegalReportLineId(accountId: revenueAccountId)
            if taxAmount > 0, let taxCodeId {
                let outputTaxAccountId = try await canonicalAccountId(
                    businessId: businessId,
                    legacyAccountId: AccountingConstants.outputTaxAccountId
                )
                let outputTaxLegalReportLineId = try await defaultLegalReportLineId(accountId: outputTaxAccountId)
                let netAmount = amount - taxAmount
                return [
                    PostingCandidateLine(
                        debitAccountId: paymentAccountId,
                        amount: Decimal(amount),
                        legalReportLineId: paymentAccountLegalReportLineId,
                        memo: primaryMemo
                    ),
                    PostingCandidateLine(
                        creditAccountId: revenueAccountId,
                        amount: Decimal(netAmount),
                        taxCodeId: taxCodeId,
                        legalReportLineId: revenueAccountLegalReportLineId,
                        memo: primaryMemo
                    ),
                    PostingCandidateLine(
                        creditAccountId: outputTaxAccountId,
                        amount: Decimal(taxAmount),
                        legalReportLineId: outputTaxLegalReportLineId,
                        memo: "仮受消費税"
                    ),
                ]
            }
            return [
                PostingCandidateLine(
                    debitAccountId: paymentAccountId,
                    creditAccountId: revenueAccountId,
                    amount: Decimal(amount),
                    taxCodeId: taxCodeId,
                    memo: primaryMemo
                ),
            ]

        case .expense:
            let paymentAccountId = try await canonicalAccountId(
                businessId: businessId,
                legacyAccountId: request.paymentAccountId ?? AccountingConstants.defaultPaymentAccountId
            )
            let paymentAccountLegalReportLineId = try await defaultLegalReportLineId(accountId: paymentAccountId)
            let expenseAccountId = try await canonicalAccountId(
                businessId: businessId,
                legacyAccountId: resolveLinkedLegacyAccountId(
                    categoryId: request.categoryId,
                    fallback: AccountingConstants.miscExpenseAccountId
                )
            )
            let expenseAccountLegalReportLineId = try await defaultLegalReportLineId(accountId: expenseAccountId)
            let rate = min(100, max(0, request.taxDeductibleRate))
            let expenseBase = taxAmount > 0 ? (amount - taxAmount) : amount

            if rate >= 100 {
                var lines = [
                    PostingCandidateLine(
                        debitAccountId: expenseAccountId,
                        amount: Decimal(expenseBase),
                        taxCodeId: taxCodeId,
                        legalReportLineId: expenseAccountLegalReportLineId,
                        memo: primaryMemo
                    ),
                ]
                if taxAmount > 0 {
                    let inputTaxAccountId = try await canonicalAccountId(
                        businessId: businessId,
                        legacyAccountId: AccountingConstants.inputTaxAccountId
                    )
                    let inputTaxLegalReportLineId = try await defaultLegalReportLineId(accountId: inputTaxAccountId)
                    lines.append(
                        PostingCandidateLine(
                            debitAccountId: inputTaxAccountId,
                            amount: Decimal(taxAmount),
                            legalReportLineId: inputTaxLegalReportLineId,
                            memo: "仮払消費税"
                        )
                    )
                }
                lines.append(
                    PostingCandidateLine(
                        creditAccountId: paymentAccountId,
                        amount: Decimal(amount),
                        legalReportLineId: paymentAccountLegalReportLineId,
                        memo: primaryMemo
                    )
                )
                return lines
            }

            var lines: [PostingCandidateLine] = []
            let deductibleAmount = expenseBase * rate / 100
            let personalAmount = expenseBase - deductibleAmount
            if deductibleAmount > 0 {
                lines.append(
                    PostingCandidateLine(
                        debitAccountId: expenseAccountId,
                        amount: Decimal(deductibleAmount),
                        taxCodeId: taxCodeId,
                        memo: primaryMemo
                    )
                )
            }

            let ownerDrawingsAccountId = try await canonicalAccountId(
                businessId: businessId,
                legacyAccountId: AccountingConstants.ownerDrawingsAccountId
            )
            let ownerDrawingsLegalReportLineId = try await defaultLegalReportLineId(accountId: ownerDrawingsAccountId)

            if taxAmount > 0 {
                let inputTaxAccountId = try await canonicalAccountId(
                    businessId: businessId,
                    legacyAccountId: AccountingConstants.inputTaxAccountId
                )
                let inputTaxLegalReportLineId = try await defaultLegalReportLineId(accountId: inputTaxAccountId)
                let deductibleTax = taxAmount * rate / 100
                let personalTax = taxAmount - deductibleTax
                if deductibleTax > 0 {
                    lines.append(
                        PostingCandidateLine(
                            debitAccountId: inputTaxAccountId,
                            amount: Decimal(deductibleTax),
                            legalReportLineId: inputTaxLegalReportLineId,
                            memo: "仮払消費税"
                        )
                    )
                }
                let ownerDrawingsAmount = personalAmount + personalTax
                if ownerDrawingsAmount > 0 {
                    lines.append(
                        PostingCandidateLine(
                            debitAccountId: ownerDrawingsAccountId,
                            amount: Decimal(ownerDrawingsAmount),
                            legalReportLineId: ownerDrawingsLegalReportLineId,
                            memo: primaryMemo
                        )
                    )
                }
            } else if personalAmount > 0 {
                lines.append(
                    PostingCandidateLine(
                        debitAccountId: ownerDrawingsAccountId,
                        amount: Decimal(personalAmount),
                        legalReportLineId: ownerDrawingsLegalReportLineId,
                        memo: primaryMemo
                    )
                )
            }

            lines.append(
                PostingCandidateLine(
                    creditAccountId: paymentAccountId,
                    amount: Decimal(amount),
                    legalReportLineId: paymentAccountLegalReportLineId,
                    memo: primaryMemo
                )
            )
            return lines

        case .transfer:
            let fromAccountId = try await canonicalAccountId(
                businessId: businessId,
                legacyAccountId: request.paymentAccountId ?? AccountingConstants.defaultPaymentAccountId
            )
            let toAccountId = try await canonicalAccountId(
                businessId: businessId,
                legacyAccountId: request.transferToAccountId ?? AccountingConstants.suspenseAccountId
            )
            return [
                PostingCandidateLine(
                    debitAccountId: toAccountId,
                    creditAccountId: fromAccountId,
                    amount: Decimal(amount),
                    memo: primaryMemo
                ),
            ]
        }
    }

    private func defaultLegalReportLineId(accountId: UUID) async throws -> String? {
        let account = try await chartOfAccountsUseCase.account(accountId)
        return account?.defaultLegalReportLineId
    }

    private func resolvedTaxAmount(for request: ReceiptEvidenceIntakeRequest) -> Int {
        guard let taxCode = resolvedTaxCode(for: request), taxCode.isTaxable else {
            return 0
        }
        if request.isTaxIncluded {
            let taxRate = taxCode.taxRatePercent
            return request.reviewedAmount * taxRate / (100 + taxRate)
        }
        return max(0, request.taxAmount ?? 0)
    }

    private func resolvedTaxCode(for request: ReceiptEvidenceIntakeRequest) -> TaxCode? {
        TaxCode.resolve(id: request.taxCodeId)
    }

    private func resolveLinkedLegacyAccountId(categoryId: String, fallback: String) -> String {
        guard !categoryId.isEmpty else {
            return fallback
        }
        let descriptor = FetchDescriptor<PPCategory>(
            predicate: #Predicate { $0.id == categoryId }
        )
        if let category = try? modelContext.fetch(descriptor).first,
           let linkedAccountId = category.linkedAccountId,
           !linkedAccountId.isEmpty {
            return linkedAccountId
        }
        return AccountingConstants.categoryToAccountMapping[categoryId] ?? fallback
    }

    private func canonicalAccountId(businessId: UUID, legacyAccountId: String) async throws -> UUID {
        if let account = try await chartOfAccountsUseCase.account(
            businessId: businessId,
            legacyAccountId: legacyAccountId
        ) {
            return account.id
        }
        return LegacyAccountCanonicalMapper.canonicalAccountId(
            businessId: businessId,
            legacyAccountId: legacyAccountId
        )
    }

    private func matchedCounterpartyId(
        businessId: UUID,
        explicitId: UUID?,
        registrationNumber: String?,
        name: String?,
        defaultTaxCodeId: String?
    ) async throws -> UUID? {
        if let explicitId {
            return explicitId
        }

        let normalizedRegistrationNumber = RegistrationNumberNormalizer.normalize(registrationNumber)
        if let normalizedRegistrationNumber,
           let matchedByRegistration = try await counterpartyMasterUseCase.findByRegistrationNumber(normalizedRegistrationNumber) {
            return matchedByRegistration.id
        }

        guard let normalizedName = normalizedOptionalString(name) else { return nil }

        let exactMatches = try await counterpartyMasterUseCase.searchCounterparties(
            businessId: businessId,
            query: normalizedName
        )
        if let exactMatch = exactMatches.first(where: {
            $0.displayName.compare(
                normalizedName,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
            ) == .orderedSame
        }) {
            return exactMatch.id
        }

        if let suggested = try await counterpartyMasterUseCase.suggestCounterparty(
            storeName: normalizedName,
            businessId: businessId
        ) {
            return suggested.id
        }

        let newCounterparty = Counterparty(
            id: stableCounterpartyId(businessId: businessId, displayName: normalizedName),
            businessId: businessId,
            displayName: normalizedName,
            invoiceRegistrationNumber: normalizedRegistrationNumber,
            defaultTaxCodeId: defaultTaxCodeId,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await counterpartyMasterUseCase.save(newCounterparty)
        return newCounterparty.id
    }

    private func makeStructuredFields(from request: ReceiptEvidenceIntakeRequest) -> EvidenceStructuredFields {
        let taxAmount = Decimal(resolvedTaxAmount(for: request))
        let totalAmount = Decimal(request.reviewedAmount)
        let subtotal = max(0, request.reviewedAmount - Int(truncating: taxAmount as NSNumber))
        let taxCode = resolvedTaxCode(for: request)
        let taxRateDecimal: Decimal? = taxCode?.isTaxable == true ? Decimal(taxCode?.taxRatePercent ?? 0) : nil
        let evidenceLineItems = request.lineItems.map { item in
            EvidenceLineItem(
                description: item.name,
                quantity: Decimal(item.quantity),
                unitPrice: Decimal(item.unitPrice),
                lineAmount: Decimal(item.subtotal),
                taxRate: taxRateDecimal,
                isTaxIncluded: request.isTaxIncluded
            )
        }
        let normalizedCounterpartyName = normalizedOptionalString(request.counterpartyName)
        let normalizedRegistrationNumber = RegistrationNumberNormalizer.normalize(request.registrationNumber)
        let subtotalDecimal = subtotal > 0 ? Decimal(subtotal) : nil

        switch taxCode {
        case .some(.reduced8) where taxAmount > 0:
            return EvidenceStructuredFields(
                counterpartyName: normalizedCounterpartyName,
                registrationNumber: normalizedRegistrationNumber,
                transactionDate: request.reviewedDate,
                subtotalReducedRate: subtotalDecimal,
                taxReducedRate: taxAmount > 0 ? taxAmount : nil,
                totalAmount: totalAmount,
                lineItems: evidenceLineItems,
                confidence: request.receiptData.confidence
            )
        case .some(.standard10) where taxAmount > 0:
            return EvidenceStructuredFields(
                counterpartyName: normalizedCounterpartyName,
                registrationNumber: normalizedRegistrationNumber,
                transactionDate: request.reviewedDate,
                subtotalStandardRate: subtotalDecimal,
                taxStandardRate: taxAmount > 0 ? taxAmount : nil,
                totalAmount: totalAmount,
                lineItems: evidenceLineItems,
                confidence: request.receiptData.confidence
            )
        default:
            return EvidenceStructuredFields(
                counterpartyName: normalizedCounterpartyName,
                registrationNumber: normalizedRegistrationNumber,
                transactionDate: request.reviewedDate,
                totalAmount: totalAmount,
                lineItems: evidenceLineItems,
                confidence: request.receiptData.confidence
            )
        }
    }

    private func makeSearchTokens(from request: ReceiptEvidenceIntakeRequest) -> [String] {
        let taxRateToken = resolvedTaxCode(for: request).map { String($0.taxRatePercent) } ?? "0"
        var tokens: [String] = [
            request.originalFileName,
            request.memo,
            request.receiptData.storeName,
            request.receiptData.itemSummary,
            request.receiptData.estimatedCategory,
            String(request.reviewedAmount),
            taxRateToken,
            request.registrationNumber ?? request.receiptData.registrationNumber ?? "",
        ]
        tokens.append(contentsOf: request.lineItems.map(\.name))
        tokens.append(contentsOf: request.linkedProjectIds.map(\.uuidString))
        if let counterpartyName = request.counterpartyName {
            tokens.append(counterpartyName)
        }
        return Array(
            Set(
                tokens
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
    }

    private func canonicalLegalDocumentType(for scannedDocumentType: ScannedDocumentType) -> CanonicalLegalDocumentType {
        switch scannedDocumentType {
        case .receipt:
            return .cashRegisterReceipt
        case .invoice:
            return .invoice
        case .expenseReceipt:
            return .receipt
        case .unknown:
            return .other
        }
    }

    private func legacyDocumentType(for scannedDocumentType: ScannedDocumentType) -> LegalDocumentType {
        switch scannedDocumentType {
        case .invoice:
            return .invoice
        case .receipt, .expenseReceipt:
            return .receipt
        case .unknown:
            return .other
        }
    }

    private func storageCategory(for sourceType: EvidenceSourceType) -> StorageCategory {
        switch sourceType {
        case .camera, .photoLibrary:
            return .paperScan
        case .scannedPDF, .emailAttachment, .importedPDF, .manualNoFile:
            return .electronicTransaction
        }
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func stableCounterpartyId(businessId: UUID, displayName: String) -> UUID {
        let normalizedName = displayName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let seed = "\(businessId.uuidString.lowercased())|\(normalizedName)"
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }

    private func existingEvidenceId(businessId: UUID, fileHash: String) throws -> UUID? {
        let descriptor = FetchDescriptor<EvidenceRecordEntity>(
            predicate: #Predicate {
                $0.businessId == businessId &&
                    $0.fileHash == fileHash &&
                    $0.deletedAt == nil
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).first?.evidenceId
    }

    private func stateHash<T: Encodable>(_ value: T) -> String? {
        do {
            let data = try JSONEncoder().encode(value)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }
}
