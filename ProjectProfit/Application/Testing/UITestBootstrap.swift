import Foundation
import SwiftData

enum UITestBootstrap {
    static let modeArgument = "--ui-testing"
    static let seedArgument = "--seed-withholding-flow"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(modeArgument)
    }

    static var shouldSeedWithholdingFlow: Bool {
        ProcessInfo.processInfo.arguments.contains(seedArgument)
    }

    @MainActor
    static func seedIfNeeded(modelContext: ModelContext, store: DataStore) async {
        guard shouldSeedWithholdingFlow else {
            return
        }

        let workflow = PostingWorkflowUseCase(modelContext: modelContext)
        if let businessId = store.businessProfile?.id,
           let pending = try? await workflow.pendingCandidates(businessId: businessId),
           !pending.isEmpty {
            return
        }

        guard let businessId = store.businessProfile?.id else {
            return
        }

        let project = PPProject(name: "UI Test Project", projectDescription: "withholding")
        modelContext.insert(project)

        let counterparty = Counterparty(
            businessId: businessId,
            displayName: "UIテスト税理士",
            address: "東京都千代田区1-1-1",
            payeeInfo: PayeeInfo(isWithholdingSubject: true, withholdingCategory: .professionalFee)
        )
        try? await CounterpartyMasterUseCase(modelContext: modelContext).save(counterparty)
        try? modelContext.save()

        let intake = PostingIntakeUseCase(modelContext: modelContext)
        let pendingCandidate = try? await intake.saveManualCandidate(
            input: ManualPostingCandidateInput(
                type: .expense,
                amount: 100_000,
                date: todayDate(),
                categoryId: "cat-tools",
                memo: "UI Test Pending Withholding",
                allocations: [(projectId: project.id, ratio: 100)],
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
                withholdingTaxAmount: 10_210,
                candidateSource: .manual
            )
        )

        let approvedCandidate = try? await intake.saveManualCandidate(
            input: ManualPostingCandidateInput(
                type: .expense,
                amount: 120_000,
                date: todayDate(),
                categoryId: "cat-tools",
                memo: "UI Test Approved Withholding",
                allocations: [(projectId: project.id, ratio: 100)],
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
                withholdingTaxAmount: 12_252,
                candidateSource: .manual
            )
        )

        if let approvedCandidate {
            _ = try? await workflow.approveCandidate(candidateId: approvedCandidate.id)
        }

        if pendingCandidate != nil {
            store.loadData()
        }
    }
}
