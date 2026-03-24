import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ApprovalQueueWorkflowUseCaseTests: XCTestCase {
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

    func testPendingItemsMixCandidatesAndApprovalRequests() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let projectA = mutations(dataStore).addProject(name: "Queue A", description: "")
        let projectB = mutations(dataStore).addProject(name: "Queue B", description: "")

        let candidateRepository = SwiftDataPostingCandidateRepository(modelContext: context)
        let candidate = PostingCandidate(
            businessId: businessId,
            taxYear: fiscalYear(for: referenceDate, startMonth: FiscalYearSettings.startMonth),
            candidateDate: referenceDate,
            status: .draft,
            source: .manual,
            memo: "manual draft candidate"
        )
        try await candidateRepository.save(candidate)

        let distributionRequest = try await queueDistributionRequest(
            businessId: businessId,
            draftKey: "queue:transaction",
            draftKind: .transaction,
            snapshotJSON: transactionSnapshotJSON(
                templateId: distributionRule(projectA: projectA, projectB: projectB, businessId: businessId).id,
                projectId: projectA.id
            ),
            currentState: distributionUseCase.currentApprovalState(
                allocationMode: .manual,
                allocations: [(projectId: projectA.id, ratio: 100)],
                totalAmount: 10_000
            ),
            projectA: projectA,
            projectB: projectB
        )

        _ = mutations(dataStore).addRecurring(
            name: "Approval Queue Recurring",
            type: .expense,
            amount: 6_000,
            categoryId: "cat-tools",
            memo: "queue recurring",
            allocationMode: .manual,
            allocations: [(projectId: projectA.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1,
            paymentAccountId: "acct-cash"
        )

        let items = try await queryUseCase.pendingItems()

        let candidateIds = items.compactMap { item -> UUID? in
            guard case .candidate(let candidate) = item else { return nil }
            return candidate.id
        }
        let requests = items.compactMap { item -> ApprovalRequest? in
            guard case .request(let request) = item else { return nil }
            return request
        }

        XCTAssertTrue(candidateIds.contains(candidate.id))
        XCTAssertTrue(requests.contains(where: { $0.id == distributionRequest.id && $0.kind == .distribution }))
        XCTAssertTrue(requests.contains(where: { $0.kind == .recurring }))
    }

    func testApproveRejectAndInvalidateDistributionRequestsUpdateDraftState() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let projectA = mutations(dataStore).addProject(name: "Approve A", description: "")
        let projectB = mutations(dataStore).addProject(name: "Approve B", description: "")
        let rule = distributionRule(projectA: projectA, projectB: projectB, businessId: businessId)

        let approveRequest = try await queueDistributionRequest(
            businessId: businessId,
            draftKey: "distribution:approve",
            draftKind: .transaction,
            snapshotJSON: transactionSnapshotJSON(templateId: rule.id, projectId: projectA.id),
            currentState: distributionUseCase.currentApprovalState(
                allocationMode: .manual,
                allocations: [(projectId: projectA.id, ratio: 100)],
                totalAmount: 10_000
            ),
            projectA: projectA,
            projectB: projectB
        )
        let approved = try await workflowUseCase.approveRequest(approveRequest.id)
        let approvedDraftValue = try await workflowUseCase.formDraft(draftKey: "distribution:approve")
        let approvedDraft = try XCTUnwrap(approvedDraftValue)
        let approvedSnapshot = try XCTUnwrap(approvedDraft.transactionSnapshot())
        XCTAssertEqual(approved.status, .approved)
        XCTAssertEqual(approvedDraft.activeApprovalRequestId, approveRequest.id)
        XCTAssertEqual(
            approvedSnapshot.allocations,
            [
                DraftAllocationInput(projectId: projectA.id, ratio: 70),
                DraftAllocationInput(projectId: projectB.id, ratio: 30),
            ]
        )

        let rejectedRequest = try await queueDistributionRequest(
            businessId: businessId,
            draftKey: "distribution:reject",
            draftKind: .transaction,
            snapshotJSON: transactionSnapshotJSON(templateId: rule.id, projectId: projectA.id),
            currentState: distributionUseCase.currentApprovalState(
                allocationMode: .manual,
                allocations: [(projectId: projectA.id, ratio: 100)],
                totalAmount: 10_000
            ),
            projectA: projectA,
            projectB: projectB
        )
        let rejected = try await workflowUseCase.rejectRequest(rejectedRequest.id)
        let rejectedDraftValue = try await workflowUseCase.formDraft(draftKey: "distribution:reject")
        let rejectedDraft = try XCTUnwrap(rejectedDraftValue)
        let rejectedSnapshot = try XCTUnwrap(rejectedDraft.transactionSnapshot())
        XCTAssertEqual(rejected.status, .rejected)
        XCTAssertNil(rejectedDraft.activeApprovalRequestId)
        XCTAssertEqual(
            rejectedSnapshot.allocations,
            [DraftAllocationInput(projectId: projectA.id, ratio: 100)]
        )

        let invalidatedRequest = try await queueDistributionRequest(
            businessId: businessId,
            draftKey: "distribution:invalidate",
            draftKind: .transaction,
            snapshotJSON: transactionSnapshotJSON(templateId: rule.id, projectId: projectA.id),
            currentState: distributionUseCase.currentApprovalState(
                allocationMode: .manual,
                allocations: [(projectId: projectA.id, ratio: 100)],
                totalAmount: 10_000
            ),
            projectA: projectA,
            projectB: projectB
        )
        let invalidated = try await workflowUseCase.invalidateRequest(invalidatedRequest.id)
        let invalidatedDraftValue = try await workflowUseCase.formDraft(draftKey: "distribution:invalidate")
        let invalidatedDraft = try XCTUnwrap(invalidatedDraftValue)
        let invalidatedSnapshot = try XCTUnwrap(invalidatedDraft.transactionSnapshot())
        XCTAssertEqual(invalidated.status, .invalidated)
        XCTAssertNil(invalidatedDraft.activeApprovalRequestId)
        XCTAssertEqual(
            invalidatedSnapshot.allocations,
            [DraftAllocationInput(projectId: projectA.id, ratio: 100)]
        )
    }

    func testApproveRecurringRequestCompletesPostingAndMarksRequestApproved() async throws {
        FeatureFlags.useCanonicalPosting = true
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let project = mutations(dataStore).addProject(name: "Recurring Queue PJ", description: "")
        _ = mutations(dataStore).addRecurring(
            name: "Recurring Approval",
            type: .expense,
            amount: 8_000,
            categoryId: "cat-tools",
            memo: "queue approve recurring",
            allocationMode: .manual,
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1,
            paymentAccountId: "acct-cash"
        )

        let postingWorkflow = PostingWorkflowUseCase(modelContext: context)
        let taxYear = fiscalYear(for: Date(), startMonth: FiscalYearSettings.startMonth)
        let beforeJournals = try await postingWorkflow.journals(businessId: businessId, taxYear: taxYear)

        let previewItems = await RecurringWorkflowUseCase(modelContext: context).previewRecurringTransactions()
        let requestId = try XCTUnwrap(previewItems.first?.id)

        let approvedRequest = try await workflowUseCase.approveRequest(requestId)
        let afterJournals = try await postingWorkflow.journals(businessId: businessId, taxYear: taxYear)

        XCTAssertEqual(approvedRequest.kind, .recurring)
        XCTAssertEqual(approvedRequest.status, .approved)
        XCTAssertEqual(afterJournals.count, beforeJournals.count + 1)
        XCTAssertTrue(afterJournals.contains(where: { $0.entryType == .recurring }))
    }

    func testDistributionRequestRejectsNonPendingTransitions() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let projectA = mutations(dataStore).addProject(name: "Guard A", description: "")
        let projectB = mutations(dataStore).addProject(name: "Guard B", description: "")
        let rule = distributionRule(projectA: projectA, projectB: projectB, businessId: businessId)

        let approvedRequest = try await queueDistributionRequest(
            businessId: businessId,
            draftKey: "distribution:guard:approved",
            draftKind: .transaction,
            snapshotJSON: transactionSnapshotJSON(templateId: rule.id, projectId: projectA.id),
            currentState: distributionUseCase.currentApprovalState(
                allocationMode: .manual,
                allocations: [(projectId: projectA.id, ratio: 100)],
                totalAmount: 10_000
            ),
            projectA: projectA,
            projectB: projectB
        )
        _ = try await workflowUseCase.approveRequest(approvedRequest.id)
        let approvedDraftBeforeValue = try await workflowUseCase.formDraft(draftKey: "distribution:guard:approved")
        let approvedDraftBefore = try XCTUnwrap(approvedDraftBeforeValue)

        await assertInvalidStatusTransition(
            requestId: approvedRequest.id,
            kind: .distribution,
            action: .approve,
            status: .approved
        ) {
            _ = try await workflowUseCase.approveRequest(approvedRequest.id)
        }
        await assertInvalidStatusTransition(
            requestId: approvedRequest.id,
            kind: .distribution,
            action: .reject,
            status: .approved
        ) {
            _ = try await workflowUseCase.rejectRequest(approvedRequest.id)
        }

        let approvedDraftAfterValue = try await workflowUseCase.formDraft(draftKey: "distribution:guard:approved")
        let approvedDraftAfter = try XCTUnwrap(approvedDraftAfterValue)
        let approvedRequestAfterValue = try await workflowUseCase.request(approvedRequest.id)
        let approvedRequestAfter = try XCTUnwrap(approvedRequestAfterValue)
        XCTAssertEqual(approvedDraftAfter, approvedDraftBefore)
        XCTAssertEqual(approvedRequestAfter.status, .approved)

        let rejectedRequest = try await queueDistributionRequest(
            businessId: businessId,
            draftKey: "distribution:guard:rejected",
            draftKind: .transaction,
            snapshotJSON: transactionSnapshotJSON(templateId: rule.id, projectId: projectA.id),
            currentState: distributionUseCase.currentApprovalState(
                allocationMode: .manual,
                allocations: [(projectId: projectA.id, ratio: 100)],
                totalAmount: 10_000
            ),
            projectA: projectA,
            projectB: projectB
        )
        _ = try await workflowUseCase.rejectRequest(rejectedRequest.id)

        await assertInvalidStatusTransition(
            requestId: rejectedRequest.id,
            kind: .distribution,
            action: .invalidate,
            status: .rejected
        ) {
            _ = try await workflowUseCase.invalidateRequest(rejectedRequest.id)
        }

        let rejectedRequestAfterValue = try await workflowUseCase.request(rejectedRequest.id)
        let rejectedRequestAfter = try XCTUnwrap(rejectedRequestAfterValue)
        XCTAssertEqual(rejectedRequestAfter.status, .rejected)
    }

    func testRecurringRequestRejectsNonPendingTransitions() async throws {
        FeatureFlags.useCanonicalPosting = true
        let project = mutations(dataStore).addProject(name: "Recurring Guard PJ", description: "")
        _ = mutations(dataStore).addRecurring(
            name: "Recurring Guard",
            type: .expense,
            amount: 9_000,
            categoryId: "cat-tools",
            memo: "queue guard recurring",
            allocationMode: .manual,
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1,
            paymentAccountId: "acct-cash"
        )

        let previewItems = await RecurringWorkflowUseCase(modelContext: context).previewRecurringTransactions()
        let requestId = try XCTUnwrap(previewItems.first?.id)
        _ = try await workflowUseCase.approveRequest(requestId)

        await assertInvalidStatusTransition(
            requestId: requestId,
            kind: .recurring,
            action: .approve,
            status: .approved
        ) {
            _ = try await workflowUseCase.approveRequest(requestId)
        }
        await assertInvalidStatusTransition(
            requestId: requestId,
            kind: .recurring,
            action: .reject,
            status: .approved
        ) {
            _ = try await workflowUseCase.rejectRequest(requestId)
        }
        await assertInvalidStatusTransition(
            requestId: requestId,
            kind: .recurring,
            action: .invalidate,
            status: .approved
        ) {
            _ = try await workflowUseCase.invalidateRequest(requestId)
        }

        let requestAfterValue = try await workflowUseCase.request(requestId)
        let requestAfter = try XCTUnwrap(requestAfterValue)
        XCTAssertEqual(requestAfter.status, .approved)
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
            name: "共通費テンプレート",
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
        projectA: PPProject,
        projectB: PPProject
    ) async throws -> ApprovalRequest {
        let rule = distributionRule(projectA: projectA, projectB: projectB, businessId: businessId)
        let result = distributionUseCase.makeApprovalRequestDraft(
            businessId: businessId,
            draftKey: draftKey,
            draftKind: draftKind,
            rule: rule,
            currentState: currentState,
            projects: [projectA, projectB],
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
                memo: "draft memo",
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

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }

    private func assertInvalidStatusTransition(
        requestId: UUID,
        kind: ApprovalRequestKind,
        action: ApprovalRequestTransitionAction,
        status: ApprovalRequestStatus,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected invalidStatusTransition error", file: file, line: line)
        } catch let error as ApprovalQueueWorkflowError {
            guard case let .invalidStatusTransition(actualId, actualKind, actualAction, actualStatus) = error else {
                XCTFail("Unexpected ApprovalQueueWorkflowError: \(error)", file: file, line: line)
                return
            }
            XCTAssertEqual(actualId, requestId, file: file, line: line)
            XCTAssertEqual(actualKind.rawValue, kind.rawValue, file: file, line: line)
            XCTAssertEqual(actualAction.rawValue, action.rawValue, file: file, line: line)
            XCTAssertEqual(actualStatus.rawValue, status.rawValue, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
