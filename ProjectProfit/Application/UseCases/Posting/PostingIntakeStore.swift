import Foundation
import SwiftData

@MainActor
struct PostingIntakeStore {
    private let modelContext: ModelContext
    private let projectRepository: any ProjectRepository
    private let transactionFormQueryUseCase: TransactionFormQueryUseCase
    private let postingSupport: CanonicalPostingSupport

    init(
        modelContext: ModelContext,
        projectRepository: (any ProjectRepository)? = nil,
        transactionFormQueryUseCase: TransactionFormQueryUseCase? = nil,
        postingSupport: CanonicalPostingSupport? = nil
    ) {
        self.modelContext = modelContext
        self.projectRepository = projectRepository ?? SwiftDataProjectRepository(modelContext: modelContext)
        let queryUseCase = transactionFormQueryUseCase ?? TransactionFormQueryUseCase(modelContext: modelContext)
        self.transactionFormQueryUseCase = queryUseCase
        self.postingSupport = postingSupport ?? CanonicalPostingSupport(
            modelContext: modelContext,
            transactionFormQueryUseCase: queryUseCase
        )
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
                taxRate: input.taxRate,
                isTaxIncluded: input.isTaxIncluded,
                taxCategory: input.taxCategory,
                receiptImagePath: nil,
                lineItems: [],
                counterpartyId: input.counterpartyId,
                counterpartyName: input.counterparty,
                source: input.candidateSource,
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
        csvString: String,
        postingWorkflowUseCase: PostingWorkflowUseCase
    ) async -> CSVImportResult {
        var successCount = 0
        var errorCount = 0
        var errors: [String] = []
        let formSnapshot = (try? transactionFormQueryUseCase.snapshot()) ?? .empty
        var projects = formSnapshot.projects
        let categories = formSnapshot.activeCategories

        for entry in parseCSV(csvString: csvString) {
            let allocations: [(projectId: UUID, ratio: Int)]
            do {
                allocations = try resolvedImportAllocations(
                    for: entry,
                    projects: &projects
                )
            } catch let error as AppError {
                errorCount += 1
                errors.append(error.errorDescription ?? error.localizedDescription)
                continue
            } catch {
                errorCount += 1
                errors.append(error.localizedDescription)
                continue
            }

            if entry.type != .transfer {
                let totalRatio = allocations.reduce(0) { $0 + $1.ratio }
                guard totalRatio == 100 else {
                    errorCount += 1
                    errors.append("配分比率が不正です（合計: \(totalRatio)%）")
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
                    errorCount += 1
                    errors.append("カテゴリが見つかりません: \(entry.categoryName)")
                    continue
                }
            }

            do {
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
                        taxCodeId: nil,
                        taxRate: entry.taxRate,
                        isTaxIncluded: entry.isTaxIncluded,
                        taxCategory: entry.taxCategory,
                        receiptImagePath: nil,
                        lineItems: [],
                        counterpartyId: nil,
                        counterpartyName: entry.counterparty,
                        source: .importFile,
                        createdAt: Date(),
                        updatedAt: Date(),
                        journalEntryId: nil
                    ),
                    snapshot: formSnapshot.replacing(projects: projects)
                )
                _ = postingWorkflowUseCase
                _ = try await postingSupport.syncApprovedCandidate(
                    posting: posting,
                    allocations: entry.type == .transfer ? [] : allocations
                )
                successCount += 1
            } catch {
                errorCount += 1
                errors.append(error.localizedDescription)
            }
        }

        return CSVImportResult(successCount: successCount, errorCount: errorCount, errors: errors)
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
