import Foundation
import SwiftData

enum UITestBootstrap {
    static let modeArgument = "--ui-testing"
    static let seedArgument = "--seed-withholding-flow"
    static let lockedYearSeedArgument = "--seed-withholding-flow-locked-year"
    static let annualFourProjectsSeedArgument = "--seed-annual-four-projects"
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

    static var shouldSeedAnnualFourProjects: Bool {
        ProcessInfo.processInfo.arguments.contains(annualFourProjectsSeedArgument)
    }

    @MainActor
    static func seedIfNeeded(modelContext: ModelContext, store: DataStore) async {
        if shouldSeedAnnualFourProjects {
            await seedAnnualFourProjectScenario(modelContext: modelContext, store: store)
            return
        }

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
    static func seedAnnualFourProjectScenario(modelContext: ModelContext, store: DataStore) async {
        store.loadData()
        guard !store.projects.contains(where: { $0.name == "UI年次 Web制作 A" }) else {
            return
        }

        let projects = [
            store.addProject(
                name: "UI年次 Web制作 A",
                description: "国内向けWeb制作案件",
                startDate: date(year: 2025, month: 1, day: 1),
                plannedEndDate: date(year: 2025, month: 12, day: 31)
            ),
            store.addProject(
                name: "UI年次 iOS開発 B",
                description: "国内向けiOSアプリ開発案件",
                startDate: date(year: 2025, month: 1, day: 1),
                plannedEndDate: date(year: 2025, month: 12, day: 31)
            ),
            store.addProject(
                name: "UI年次 顧問 C",
                description: "国内事業者向け顧問案件",
                startDate: date(year: 2025, month: 1, day: 1),
                plannedEndDate: date(year: 2025, month: 12, day: 31)
            ),
            store.addProject(
                name: "UI年次 保守運用 D",
                description: "国内向け保守運用案件",
                startDate: date(year: 2025, month: 1, day: 1),
                plannedEndDate: date(year: 2025, month: 12, day: 31)
            ),
        ]

        let monthlyIncome = [
            240_000, 320_000, 180_000, 150_000,
            260_000, 340_000, 190_000, 160_000,
            280_000, 360_000, 200_000, 170_000,
        ]
        for month in 1...12 {
            let project = projects[(month - 1) % projects.count]
            await approveManualCandidate(
                modelContext: modelContext,
                type: .income,
                amount: monthlyIncome[month - 1],
                date: date(year: 2025, month: month, day: 15),
                categoryId: "cat-sales",
                memo: "UI年次 \(month)月 売上",
                allocations: [(projectId: project.id, ratio: 100)],
                paymentAccountId: AccountingConstants.bankAccountId,
                counterparty: "国内取引先\(month)"
            )
        }

        let equalAllocations = projects.map { (projectId: $0.id, ratio: 25) }
        for month in 1...12 {
            await approveManualCandidate(
                modelContext: modelContext,
                type: .expense,
                amount: 80_000,
                date: date(year: 2025, month: month, day: 25),
                categoryId: "cat-other-expense",
                memo: "UI年次 \(month)月 事務所費",
                allocations: equalAllocations,
                paymentAccountId: AccountingConstants.bankAccountId,
                counterparty: "国内オフィス"
            )
            await approveManualCandidate(
                modelContext: modelContext,
                type: .expense,
                amount: 22_000,
                date: date(year: 2025, month: month, day: 28),
                categoryId: "cat-tools",
                memo: "UI年次 \(month)月 業務ツール",
                allocations: equalAllocations,
                paymentAccountId: AccountingConstants.bankAccountId,
                counterparty: "国内SaaS"
            )
        }

        for (index, month) in [1, 4, 7, 10].enumerated() {
            await approveManualCandidate(
                modelContext: modelContext,
                type: .expense,
                amount: 12_000,
                date: date(year: 2025, month: month, day: 20),
                categoryId: "cat-transport",
                memo: "UI年次 \(month)月 交通費",
                allocations: [(projectId: projects[index].id, ratio: 100)],
                paymentAccountId: AccountingConstants.bankAccountId,
                counterparty: "国内交通機関"
            )
        }

        let fixedAssetWorkflow = FixedAssetWorkflowUseCase(modelContext: modelContext)
        if let asset = try? fixedAssetWorkflow.createAsset(
            input: FixedAssetUpsertInput(
                name: "UI年次 MacBook Pro",
                acquisitionDate: date(year: 2025, month: 1, day: 5),
                acquisitionCost: 180_000,
                usefulLifeYears: 4,
                depreciationMethod: .straightLine,
                salvageValue: 1,
                businessUsePercent: 90,
                memo: "UI年次E2E用固定資産"
            )
        ) {
            _ = try? fixedAssetWorkflow.postDepreciation(assetId: asset.id, fiscalYear: 2025)
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

    @MainActor
    private static func approveManualCandidate(
        modelContext: ModelContext,
        type: TransactionType,
        amount: Int,
        date: Date,
        categoryId: String,
        memo: String,
        allocations: [(projectId: UUID, ratio: Int)],
        paymentAccountId: String?,
        counterparty: String
    ) async {
        let intake = PostingIntakeUseCase(modelContext: modelContext)
        guard let candidate = try? await intake.saveManualCandidate(
            input: ManualPostingCandidateInput(
                type: type,
                amount: amount,
                date: date,
                categoryId: categoryId,
                memo: memo,
                allocations: allocations,
                paymentAccountId: paymentAccountId,
                transferToAccountId: nil,
                taxDeductibleRate: nil,
                taxAmount: nil,
                taxCodeId: nil,
                isTaxIncluded: nil,
                counterpartyId: nil,
                counterparty: counterparty,
                isWithholdingEnabled: false,
                withholdingTaxCodeId: nil,
                withholdingTaxAmount: nil,
                candidateSource: .manual
            )
        ) else {
            return
        }

        _ = try? await PostingWorkflowUseCase(modelContext: modelContext)
            .approveCandidate(candidateId: candidate.id, actor: "ui-test")
    }

    private static func date(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
