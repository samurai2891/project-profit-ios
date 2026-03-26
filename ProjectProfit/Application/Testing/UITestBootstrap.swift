import Foundation
import SwiftData

enum UITestBootstrap {
    static let modeArgument = "--ui-testing"
    static let seedArgument = "--seed-withholding-flow"
    static let lockedYearSeedArgument = "--seed-withholding-flow-locked-year"
    private static let projectName = "UI Test Project"
    private static let counterpartyName = "UIテスト税理士"
    private static let pendingMemo = "UI Test Pending Withholding"
    private static let approvedMemo = "UI Test Approved Withholding"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(modeArgument)
    }

    static var shouldSeedWithholdingFlow: Bool {
        ProcessInfo.processInfo.arguments.contains(seedArgument)
    }

    static var shouldSeedWithholdingFlowLockedYear: Bool {
        ProcessInfo.processInfo.arguments.contains(lockedYearSeedArgument)
    }

    @MainActor
    static func seedIfNeeded(modelContext: ModelContext, store: DataStore) async {
        if shouldSeedWithholdingFlowLockedYear {
            await seedWithholdingFlowLockedYear(modelContext: modelContext, store: store)
            return
        }

        guard shouldSeedWithholdingFlow else {
            return
        }

        await seedWithholdingFlow(modelContext: modelContext, store: store)
    }

    @MainActor
    static func seedWithholdingFlowLockedYear(modelContext: ModelContext, store: DataStore) async {
        await seedWithholdingFlow(modelContext: modelContext, store: store)
        store.loadData()

        let workflow = PostingWorkflowUseCase(modelContext: modelContext)
        guard let businessId = store.businessProfile?.id,
              let counterparty = await existingCounterparty(
                  businessId: businessId,
                  modelContext: modelContext
              ),
              let pendingCandidate = await pendingWithholdingCandidate(
                  businessId: businessId,
                  workflow: workflow,
                  counterpartyId: counterparty.id
              ) else {
            return
        }

#if DEBUG
        store.lockFiscalYear(pendingCandidate.taxYear)
#endif
        store.loadData()
    }

    @MainActor
    static func seedWithholdingFlow(modelContext: ModelContext, store: DataStore) async {
        store.loadData()

        let workflow = PostingWorkflowUseCase(modelContext: modelContext)
        guard let businessId = store.businessProfile?.id else {
            return
        }

        let project = existingProject(in: store) ?? createProject(modelContext: modelContext)
        let counterparty = await existingCounterparty(businessId: businessId, modelContext: modelContext)
            ?? createCounterparty(businessId: businessId)

        try? await CounterpartyMasterUseCase(modelContext: modelContext).save(counterparty)
        try? modelContext.save()

        let intake = PostingIntakeUseCase(modelContext: modelContext)
        if (await pendingWithholdingCandidate(
            businessId: businessId,
            workflow: workflow,
            counterpartyId: counterparty.id
        )) == nil {
            _ = try? await intake.saveManualCandidate(
                input: withholdingInput(
                    amount: 100_000,
                    memo: pendingMemo,
                    projectId: project.id,
                    counterparty: counterparty
                )
            )
        }

        if !hasApprovedWithholdingDocument(
            fiscalYear: fiscalYear(for: todayDate(), startMonth: FiscalYearSettings.startMonth),
            modelContext: modelContext,
            counterpartyId: counterparty.id
        ) {
            if let approvedCandidate = try? await intake.saveManualCandidate(
                input: withholdingInput(
                    amount: 120_000,
                    memo: approvedMemo,
                    projectId: project.id,
                    counterparty: counterparty
                )
            ) {
                _ = try? await workflow.approveCandidate(candidateId: approvedCandidate.id)
            }
        }

        store.loadData()
    }

    @MainActor
    private static func existingProject(in store: DataStore) -> PPProject? {
        store.projects.first { $0.name == projectName }
    }

    @MainActor
    private static func createProject(modelContext: ModelContext) -> PPProject {
        let project = PPProject(name: projectName, projectDescription: "withholding")
        modelContext.insert(project)
        return project
    }

    @MainActor
    private static func existingCounterparty(
        businessId: UUID,
        modelContext: ModelContext
    ) async -> Counterparty? {
        try? await CounterpartyMasterUseCase(modelContext: modelContext)
            .loadCounterparties(businessId: businessId)
            .first(where: { $0.displayName == counterpartyName })
    }

    private static func createCounterparty(businessId: UUID) -> Counterparty {
        Counterparty(
            businessId: businessId,
            displayName: counterpartyName,
            address: "東京都千代田区1-1-1",
            payeeInfo: PayeeInfo(isWithholdingSubject: true, withholdingCategory: .professionalFee)
        )
    }

    @MainActor
    private static func pendingWithholdingCandidate(
        businessId: UUID,
        workflow: PostingWorkflowUseCase,
        counterpartyId: UUID?
    ) async -> PostingCandidate? {
        guard let candidates = try? await workflow.pendingCandidates(businessId: businessId) else {
            return nil
        }

        return candidates.first { candidate in
            (counterpartyId == nil || candidate.counterpartyId == counterpartyId) &&
            candidate.proposedLines.contains {
                $0.withholdingTaxCodeId == WithholdingTaxCode.professionalFee.rawValue &&
                $0.withholdingTaxAmount != nil
            }
        }
    }

    @MainActor
    private static func hasApprovedWithholdingDocument(
        fiscalYear: Int,
        modelContext: ModelContext,
        counterpartyId: UUID
    ) -> Bool {
        guard let summary = try? WithholdingStatementQueryUseCase(modelContext: modelContext)
            .summary(fiscalYear: fiscalYear) else {
            return false
        }

        return summary.documents.contains { $0.counterpartyId == counterpartyId }
    }

    private static func withholdingInput(
        amount: Int,
        memo: String,
        projectId: UUID,
        counterparty: Counterparty
    ) -> ManualPostingCandidateInput {
        ManualPostingCandidateInput(
            type: .expense,
            amount: amount,
            date: todayDate(),
            categoryId: "cat-tools",
            memo: memo,
            allocations: [(projectId: projectId, ratio: 100)],
            paymentAccountId: AccountingConstants.cashAccountId,
            transferToAccountId: nil,
            taxDeductibleRate: nil,
            taxAmount: nil,
            taxCodeId: nil,
            isTaxIncluded: nil,
            counterpartyId: counterparty.id,
            counterparty: counterparty.displayName,
            isWithholdingEnabled: true,
            withholdingTaxCodeId: WithholdingTaxCode.professionalFee.rawValue,
            withholdingTaxAmount: nil,
            candidateSource: .manual
        )
    }
}
