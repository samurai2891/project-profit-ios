import Foundation
import SwiftData

@MainActor
struct PostingIntakeStore {
    private let modelContext: ModelContext
    private let projectRepository: any ProjectRepository
    private let transactionFormQueryUseCase: TransactionFormQueryUseCase
    private let postingSupport: CanonicalPostingSupport
    private let evidenceRepository: any EvidenceRepository

    init(
        modelContext: ModelContext,
        projectRepository: (any ProjectRepository)? = nil,
        transactionFormQueryUseCase: TransactionFormQueryUseCase? = nil,
        postingSupport: CanonicalPostingSupport? = nil,
        evidenceRepository: (any EvidenceRepository)? = nil
    ) {
        self.modelContext = modelContext
        self.projectRepository = projectRepository ?? SwiftDataProjectRepository(modelContext: modelContext)
        let queryUseCase = transactionFormQueryUseCase ?? TransactionFormQueryUseCase(modelContext: modelContext)
        self.transactionFormQueryUseCase = queryUseCase
        self.postingSupport = postingSupport ?? CanonicalPostingSupport(
            modelContext: modelContext,
            transactionFormQueryUseCase: queryUseCase
        )
        self.evidenceRepository = evidenceRepository ?? SwiftDataEvidenceRepository(modelContext: modelContext)
    }

    func makeManualCandidate(
        input: ManualPostingCandidateInput,
        postingWorkflowUseCase: PostingWorkflowUseCase
    ) async throws -> PostingCandidate {
        let snapshot = try transactionFormQueryUseCase.snapshot()
        _ = postingWorkflowUseCase
        let posting = try postingSupport.buildApprovedPosting(
            seed: CanonicalPostingSeed(
                id: UUID(),
                type: input.type,
                amount: input.amount,
                date: input.date,
                categoryId: input.categoryId,
                memo: input.memo,
                recurringId: nil,
                paymentAccountId: input.paymentAccountId,
                transferToAccountId: input.transferToAccountId,
                taxDeductibleRate: input.taxDeductibleRate,
                taxAmount: input.taxAmount,
                taxCodeId: input.taxCodeId,
                isTaxIncluded: input.isTaxIncluded,
                receiptImagePath: nil,
                lineItems: [],
                counterpartyId: input.counterpartyId,
                counterpartyName: input.counterparty,
                source: input.candidateSource,
                isWithholdingEnabled: input.isWithholdingEnabled,
                withholdingTaxCodeId: input.withholdingTaxCodeId,
                withholdingTaxAmount: input.withholdingTaxAmount,
                createdAt: Date(),
                updatedAt: Date(),
                journalEntryId: nil
            ),
            snapshot: snapshot
        )

        do {
            return try await postingSupport.saveDraftCandidate(
                posting: posting,
                allocations: input.type == .transfer ? [] : input.allocations
            )
        } catch {
            throw AppError.saveFailed(underlying: error)
        }
    }

    func importTransactions(
        request: CSVImportRequest,
        postingWorkflowUseCase: PostingWorkflowUseCase
    ) async -> CSVImportResult {
        switch request.channel {
        case .settingsTransactionCSV:
            return await importTransactionCSV(
                request: request,
                postingWorkflowUseCase: postingWorkflowUseCase
            )
        case .ledgerBook(let ledgerType, let metadataJSON):
            return await importLedgerCSV(
                request: request,
                ledgerType: ledgerType,
                metadataJSON: metadataJSON,
                postingWorkflowUseCase: postingWorkflowUseCase
            )
        }
    }

    private func importTransactionCSV(
        request: CSVImportRequest,
        postingWorkflowUseCase: PostingWorkflowUseCase
    ) async -> CSVImportResult {
        let parsedEntries = parseCSV(csvString: request.csvString)
        guard !parsedEntries.isEmpty else {
            return CSVImportResult(errors: ["ヘッダー行またはデータが見つかりません"])
        }

        let formSnapshot = (try? transactionFormQueryUseCase.snapshot()) ?? .empty
        guard let businessId = formSnapshot.businessId else {
            return CSVImportResult(errors: ["事業者プロフィールが未設定のため CSV を取り込めません"])
        }

        let suggestedTaxYear = fiscalYear(
            for: parsedEntries.first?.date ?? Date(),
            startMonth: FiscalYearSettings.startMonth
        )

        let evidence: EvidenceDocument
        do {
            evidence = try await createEvidence(
                request: request,
                businessId: businessId,
                suggestedTaxYear: suggestedTaxYear,
                searchTokens: ["csv", "transaction-import"]
            )
        } catch {
            return CSVImportResult(errors: [error.localizedDescription])
        }

        var projects = formSnapshot.projects
        let categories = formSnapshot.activeCategories
        var candidateCount = 0
        var lineErrors: [CSVImportLineError] = []

        for entry in parsedEntries {
            let allocations: [(projectId: UUID, ratio: Int)]
            do {
                allocations = try resolvedImportAllocations(
                    for: entry,
                    projects: &projects
                )
            } catch {
                lineErrors.append(CSVImportLineError(line: entry.sourceLine, reason: error.localizedDescription))
                continue
            }

            if entry.type != .transfer {
                let totalRatio = allocations.reduce(0) { $0 + $1.ratio }
                guard totalRatio == 100 else {
                    lineErrors.append(
                        CSVImportLineError(
                            line: entry.sourceLine,
                            reason: "配分比率が不正です（合計: \(totalRatio)%）"
                        )
                    )
                    continue
                }
            }

            let categoryId: String
            switch entry.type {
            case .transfer:
                categoryId = ""
            case .income, .expense:
                let categoryType: CategoryType = entry.type == .income ? .income : .expense
                if let existing = categories.first(where: {
                    $0.name == entry.categoryName && $0.type == categoryType
                }) {
                    categoryId = existing.id
                } else if let fallback = categories.first(where: { $0.name == entry.categoryName }) {
                    categoryId = fallback.id
                } else {
                    lineErrors.append(
                        CSVImportLineError(
                            line: entry.sourceLine,
                            reason: "カテゴリが見つかりません: \(entry.categoryName)"
                        )
                    )
                    continue
                }
            }

            do {
                let resolvedTaxCodeId = TaxCode.resolve(
                    legacyCategory: entry.taxCategory,
                    taxRate: entry.taxRate
                )?.rawValue
                let posting = try postingSupport.buildApprovedPosting(
                    seed: CanonicalPostingSeed(
                        id: UUID(),
                        type: entry.type,
                        amount: entry.amount,
                        date: entry.date,
                        categoryId: categoryId,
                        memo: entry.memo,
                        recurringId: nil,
                        paymentAccountId: entry.paymentAccountId,
                        transferToAccountId: entry.type == .transfer ? entry.transferToAccountId : nil,
                        taxDeductibleRate: entry.type == .expense ? entry.taxDeductibleRate : nil,
                        taxAmount: entry.taxAmount,
                        taxCodeId: resolvedTaxCodeId,
                        isTaxIncluded: entry.isTaxIncluded,
                        receiptImagePath: nil,
                        lineItems: [],
                        counterpartyId: nil,
                        counterpartyName: entry.counterparty,
                        source: .importFile,
                        isWithholdingEnabled: false,
                        withholdingTaxCodeId: nil,
                        withholdingTaxAmount: nil,
                        createdAt: Date(),
                        updatedAt: Date(),
                        journalEntryId: nil
                    ),
                    snapshot: formSnapshot.replacing(projects: projects)
                )
                let queuedCandidate = queuedImportCandidate(
                    from: postingSupport.candidateWithProjectAllocations(
                        posting.candidate,
                        allocations: entry.type == .transfer ? [] : allocations
                    ),
                    evidenceId: evidence.id
                )
                try await postingWorkflowUseCase.saveCandidate(queuedCandidate)
                candidateCount += 1
            } catch {
                lineErrors.append(CSVImportLineError(line: entry.sourceLine, reason: error.localizedDescription))
            }
        }

        return CSVImportResult(
            evidenceCount: 1,
            candidateCount: candidateCount,
            assetCount: 0,
            lineErrors: lineErrors
        )
    }

    private func importLedgerCSV(
        request: CSVImportRequest,
        ledgerType: LedgerType,
        metadataJSON: String?,
        postingWorkflowUseCase: PostingWorkflowUseCase
    ) async -> CSVImportResult {
        let snapshot = (try? transactionFormQueryUseCase.snapshot()) ?? .empty
        guard let businessId = snapshot.businessId else {
            return CSVImportResult(errors: ["事業者プロフィールが未設定のため CSV を取り込めません"])
        }

        let draftBatch: LedgerCSVImportDraftBatch
        do {
            draftBatch = try await LedgerCSVImportService(modelContext: modelContext).prepareImport(
                content: request.csvString,
                ledgerType: ledgerType,
                metadataJSON: metadataJSON,
                snapshot: snapshot
            )
        } catch {
            return CSVImportResult(errors: [error.localizedDescription])
        }

        let evidence: EvidenceDocument
        do {
            evidence = try await createEvidence(
                request: request,
                businessId: businessId,
                suggestedTaxYear: draftBatch.suggestedTaxYear,
                searchTokens: ["csv", "ledger-import", ledgerType.rawValue]
            )
        } catch {
            return CSVImportResult(errors: [error.localizedDescription])
        }

        var candidateCount = 0
        var assetCount = 0
        var lineErrors = draftBatch.lineErrors
        let fixedAssetWorkflowUseCase = FixedAssetWorkflowUseCase(modelContext: modelContext)

        for draft in draftBatch.candidateDrafts {
            let candidate = PostingCandidate(
                evidenceId: evidence.id,
                businessId: businessId,
                taxYear: fiscalYear(for: draft.date, startMonth: FiscalYearSettings.startMonth),
                candidateDate: draft.date,
                counterpartyId: draft.counterpartyId,
                proposedLines: draft.proposedLines,
                taxAnalysis: nil,
                confidenceScore: 0,
                status: .needsReview,
                source: .importFile,
                memo: draft.memo,
                legacySnapshot: nil
            )

            do {
                try await postingWorkflowUseCase.saveCandidate(candidate)
                candidateCount += 1
            } catch {
                lineErrors.append(CSVImportLineError(line: draft.sourceLine, reason: error.localizedDescription))
            }
        }

        for draft in draftBatch.fixedAssetDrafts {
            do {
                try fixedAssetWorkflowUseCase.saveAsset(
                    existingAssetId: draft.existingAssetId,
                    input: draft.input
                )
                assetCount += 1
            } catch {
                lineErrors.append(CSVImportLineError(line: draft.sourceLine, reason: error.localizedDescription))
            }
        }

        return CSVImportResult(
            evidenceCount: 1,
            candidateCount: candidateCount,
            assetCount: assetCount,
            lineErrors: lineErrors
        )
    }

    private func queuedImportCandidate(
        from candidate: PostingCandidate,
        evidenceId: UUID
    ) -> PostingCandidate {
        PostingCandidate(
            id: candidate.id,
            evidenceId: evidenceId,
            businessId: candidate.businessId,
            taxYear: candidate.taxYear,
            candidateDate: candidate.candidateDate,
            counterpartyId: candidate.counterpartyId,
            proposedLines: candidate.proposedLines,
            taxAnalysis: candidate.taxAnalysis,
            confidenceScore: candidate.confidenceScore,
            status: .needsReview,
            source: .importFile,
            memo: candidate.memo,
            legacySnapshot: candidate.legacySnapshot,
            createdAt: candidate.createdAt,
            updatedAt: Date()
        )
    }

    private func createEvidence(
        request: CSVImportRequest,
        businessId: UUID,
        suggestedTaxYear: Int?,
        searchTokens: [String]
    ) async throws -> EvidenceDocument {
        let fileHash = ReceiptImageStore.sha256Hex(data: request.fileData)
        if try existingEvidenceId(businessId: businessId, fileHash: fileHash) != nil {
            throw AppError.invalidInput(message: "同一の CSV ファイルは既に取り込み済みです")
        }

        let storedFileName = try ReceiptImageStore.saveDocumentData(
            request.fileData,
            originalFileName: request.originalFileName
        )
        let evidence = EvidenceDocument(
            businessId: businessId,
            taxYear: suggestedTaxYear ?? fiscalYear(for: Date(), startMonth: FiscalYearSettings.startMonth),
            sourceType: .importedCSV,
            legalDocumentType: .other,
            storageCategory: .electronicTransaction,
            receivedAt: Date(),
            issueDate: nil,
            paymentDate: nil,
            originalFilename: request.originalFileName,
            mimeType: request.mimeType,
            fileHash: fileHash,
            originalFilePath: storedFileName,
            ocrText: nil,
            extractionVersion: nil,
            searchTokens: searchTokens + [request.originalFileName],
            structuredFields: nil,
            linkedCounterpartyId: nil,
            linkedProjectIds: [],
            complianceStatus: .pendingReview,
            retentionPolicyId: nil,
            deletedAt: nil,
            lockedAt: nil
        )
        do {
            try await evidenceRepository.save(evidence)
            return evidence
        } catch {
            ReceiptImageStore.deleteDocumentFile(fileName: storedFileName)
            throw error
        }
    }

    private func existingEvidenceId(
        businessId: UUID,
        fileHash: String
    ) throws -> UUID? {
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

    private func resolvedImportAllocations(
        for entry: CSVParsedTransaction,
        projects: inout [PPProject]
    ) throws -> [(projectId: UUID, ratio: Int)] {
        guard entry.type == .transfer || !entry.allocations.isEmpty else {
            throw AppError.invalidInput(message: "プロジェクトが見つかりません")
        }

        return try entry.allocations.map { allocation in
            if let existing = projects.first(where: { $0.name == allocation.projectName }) {
                return (projectId: existing.id, ratio: allocation.ratio)
            }

            let created = PPProject(name: allocation.projectName, projectDescription: "")
            projectRepository.insert(created)
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            projects.append(created)
            return (projectId: created.id, ratio: allocation.ratio)
        }
    }
}
