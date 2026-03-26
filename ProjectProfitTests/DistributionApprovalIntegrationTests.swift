import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class DistributionApprovalIntegrationTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var workflowUseCase: ApprovalQueueWorkflowUseCase!
    private var queryUseCase: ApprovalQueueQueryUseCase!
    private var distributionUseCase: DistributionTemplateApplicationUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        workflowUseCase = ApprovalQueueWorkflowUseCase(modelContext: context)
        queryUseCase = ApprovalQueueQueryUseCase(modelContext: context)
        distributionUseCase = DistributionTemplateApplicationUseCase()
    }

    override func tearDown() {
        distributionUseCase = nil
        queryUseCase = nil
        workflowUseCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testTransactionDraftRoundTripsPendingAndApprovedDistributionState() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let projectA = mutations(dataStore).addProject(name: "Tx A", description: "")
        let projectB = mutations(dataStore).addProject(name: "Tx B", description: "")
        let rule = distributionRule(projectA: projectA, projectB: projectB, businessId: businessId)
        let request = try await queueDistributionRequest(
            businessId: businessId,
            draftKey: "integration:transaction",
            draftKind: .transaction,
            snapshotJSON: transactionSnapshotJSON(templateId: rule.id, projectId: projectA.id),
            currentState: distributionUseCase.currentApprovalState(
                allocationMode: .manual,
                allocations: [(projectId: projectA.id, ratio: 100)],
                totalAmount: 10_000
            ),
            rule: rule,
            projects: [projectA, projectB]
        )

        let reloadedQuery = ApprovalQueueQueryUseCase(modelContext: context)
        let pendingDraftValue = try await reloadedQuery.formDraft(draftKey: "integration:transaction")
        let pendingDraft = try XCTUnwrap(pendingDraftValue)
        let pendingSnapshot = try XCTUnwrap(pendingDraft.transactionSnapshot())
        let pendingRequestValue = try await reloadedQuery.activeRequest(for: "integration:transaction")
        let pendingRequest = try XCTUnwrap(pendingRequestValue)

        XCTAssertEqual(pendingSnapshot.allocations, [DraftAllocationInput(projectId: projectA.id, ratio: 100)])
        XCTAssertEqual(pendingRequest.id, request.id)
        XCTAssertEqual(pendingRequest.status, .pending)
        XCTAssertTrue(pendingRequest.status == .pending)

        _ = try await ApprovalQueueWorkflowUseCase(modelContext: context).approveRequest(request.id)

        let approvedDraftValue = try await ApprovalQueueQueryUseCase(modelContext: context).formDraft(draftKey: "integration:transaction")
        let approvedDraft = try XCTUnwrap(approvedDraftValue)
        let approvedSnapshot = try XCTUnwrap(approvedDraft.transactionSnapshot())
        let approvedRequestValue = try await ApprovalQueueQueryUseCase(modelContext: context).activeRequest(for: "integration:transaction")
        let approvedRequest = try XCTUnwrap(approvedRequestValue)

        XCTAssertEqual(
            approvedSnapshot.allocations,
            [
                DraftAllocationInput(projectId: projectA.id, ratio: 70),
                DraftAllocationInput(projectId: projectB.id, ratio: 30),
            ]
        )
        XCTAssertEqual(approvedRequest.status, .approved)
        XCTAssertFalse(approvedRequest.status == .pending)
    }

    func testRecurringDraftRoundTripsPendingAndRejectedState() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let projectA = mutations(dataStore).addProject(name: "Recurring A", description: "")
        let projectB = mutations(dataStore).addProject(name: "Recurring B", description: "")
        let rule = distributionRule(projectA: projectA, projectB: projectB, businessId: businessId)
        let request = try await queueDistributionRequest(
            businessId: businessId,
            draftKey: "integration:recurring:reject",
            draftKind: .recurring,
            snapshotJSON: recurringSnapshotJSON(templateId: rule.id, projectId: projectA.id),
            currentState: distributionUseCase.currentApprovalState(
                allocationMode: .manual,
                allocations: [(projectId: projectA.id, ratio: 100)],
                totalAmount: 10_000
            ),
            rule: rule,
            projects: [projectA, projectB]
        )

        let pendingRequestValue = try await ApprovalQueueQueryUseCase(modelContext: context).activeRequest(for: "integration:recurring:reject")
        let pendingRequest = try XCTUnwrap(pendingRequestValue)
        XCTAssertEqual(pendingRequest.status, .pending)
        XCTAssertTrue(pendingRequest.status == .pending)

        _ = try await ApprovalQueueWorkflowUseCase(modelContext: context).rejectRequest(request.id)

        let rejectedDraftValue = try await ApprovalQueueQueryUseCase(modelContext: context).formDraft(draftKey: "integration:recurring:reject")
        let rejectedDraft = try XCTUnwrap(rejectedDraftValue)
        let rejectedSnapshot = try XCTUnwrap(rejectedDraft.recurringSnapshot())
        let activeRequest = try await ApprovalQueueQueryUseCase(modelContext: context).activeRequest(for: "integration:recurring:reject")

        XCTAssertEqual(rejectedSnapshot.allocations, [DraftAllocationInput(projectId: projectA.id, ratio: 100)])
        XCTAssertNil(activeRequest)
    }

    func testTransactionDraftInvalidationRestoresOriginalAllocations() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let projectA = mutations(dataStore).addProject(name: "Invalidate A", description: "")
        let projectB = mutations(dataStore).addProject(name: "Invalidate B", description: "")
        let rule = distributionRule(projectA: projectA, projectB: projectB, businessId: businessId)
        let request = try await queueDistributionRequest(
            businessId: businessId,
            draftKey: "integration:transaction:invalidate",
            draftKind: .transaction,
            snapshotJSON: transactionSnapshotJSON(templateId: rule.id, projectId: projectA.id),
            currentState: distributionUseCase.currentApprovalState(
                allocationMode: .manual,
                allocations: [(projectId: projectA.id, ratio: 100)],
                totalAmount: 10_000
            ),
            rule: rule,
            projects: [projectA, projectB]
        )

        _ = try await ApprovalQueueWorkflowUseCase(modelContext: context).invalidateRequest(request.id)

        let invalidatedDraftValue = try await ApprovalQueueQueryUseCase(modelContext: context).formDraft(draftKey: "integration:transaction:invalidate")
        let invalidatedDraft = try XCTUnwrap(invalidatedDraftValue)
        let invalidatedSnapshot = try XCTUnwrap(invalidatedDraft.transactionSnapshot())
        let activeRequest = try await ApprovalQueueQueryUseCase(modelContext: context).activeRequest(for: "integration:transaction:invalidate")

        XCTAssertEqual(invalidatedSnapshot.allocations, [DraftAllocationInput(projectId: projectA.id, ratio: 100)])
        XCTAssertNil(activeRequest)
    }

    private var referenceDate: Date {
        date(2026, 4, 15)
    }

    private func distributionRule(
        projectA: PPProject,
        projectB: PPProject,
        businessId: UUID
    ) -> DistributionRule {
        DistributionRule(
            businessId: businessId,
            name: "承認統合テンプレート",
            scope: .selectedProjects,
            basis: .fixedWeight,
            weights: [
                DistributionWeight(projectId: projectA.id, weight: 70),
                DistributionWeight(projectId: projectB.id, weight: 30),
            ],
            roundingPolicy: .largestWeightAdjust,
            effectiveFrom: referenceDate
        )
    }

    private func queueDistributionRequest(
        businessId: UUID,
        draftKey: String,
        draftKind: FormDraftKind,
        snapshotJSON: String,
        currentState: DistributionTemplateApplicationUseCase.ApprovalState,
        rule: DistributionRule,
        projects: [PPProject]
    ) async throws -> ApprovalRequest {
        let result = distributionUseCase.makeApprovalRequestDraft(
            businessId: businessId,
            draftKey: draftKey,
            draftKind: draftKind,
            rule: rule,
            currentState: currentState,
            projects: projects,
            referenceDate: referenceDate,
            totalAmount: 10_000,
            supportsEqualAllMode: false
        )
        let requestDraft = try XCTUnwrap(result.requestDraft)
        return try await workflowUseCase.queueDistributionRequest(
            businessId: businessId,
            draftKey: draftKey,
            draftKind: draftKind,
            snapshotJSON: snapshotJSON,
            requestDraft: requestDraft
        )
    }

    private func transactionSnapshotJSON(templateId: UUID, projectId: UUID) -> String {
        CanonicalJSONCoder.encode(
            TransactionFormDraftSnapshot(
                type: .expense,
                amountText: "10000",
                date: referenceDate,
                categoryId: "cat-tools",
                memo: "transaction draft",
                allocations: [DraftAllocationInput(projectId: projectId, ratio: 100)],
                paymentAccountId: "acct-cash",
                transferToAccountId: nil,
                taxDeductibleRate: 100,
                selectedTaxCodeId: nil,
                isTaxIncluded: true,
                taxAmountText: "",
                selectedCounterpartyId: nil,
                counterparty: "",
                isWithholdingEnabled: false,
                selectedWithholdingTaxCodeId: nil,
                selectedDistributionTemplateId: templateId
            ),
            fallback: "{}"
        )
    }

    private func recurringSnapshotJSON(templateId: UUID, projectId: UUID) -> String {
        CanonicalJSONCoder.encode(
            RecurringFormDraftSnapshot(
                recurringId: nil,
                name: "Recurring Draft",
                type: .expense,
                amountText: "10000",
                frequency: .monthly,
                dayOfMonth: 1,
                monthOfYear: 1,
                selectedCategoryId: "cat-tools",
                allocationMode: .manual,
                allocations: [DraftAllocationInput(projectId: projectId, ratio: 100)],
                memo: "recurring draft",
                isActive: true,
                hasEndDate: false,
                endDate: referenceDate,
                yearlyAmortizationMode: .lumpSum,
                paymentAccountId: "acct-cash",
                transferToAccountId: nil,
                taxDeductibleRate: 100,
                selectedCounterpartyId: nil,
                counterparty: "",
                selectedDistributionTemplateId: templateId
            ),
            fallback: "{}"
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }
}
