import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class UITestBootstrapTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        FeatureFlags.clearOverrides()
        FeatureFlags.switchToCanonical()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
    }

    override func tearDown() {
        FeatureFlags.clearOverrides()
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testSeedWithholdingFlowCreatesPendingCandidateAndApprovedSummary() async throws {
        try XCTSkipUnless(dataStore.businessProfile != nil, "business profile is required")

        await UITestBootstrap.seedWithholdingFlow(modelContext: context, store: dataStore)

        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let workflow = PostingWorkflowUseCase(modelContext: context)
        let pending = try await workflow.pendingCandidates(businessId: businessId)
        let counterparty = try await CounterpartyMasterUseCase(modelContext: context)
            .loadCounterparties(businessId: businessId)
            .first(where: { $0.displayName == "UIテスト税理士" })
        let counterpartyId = try XCTUnwrap(counterparty?.id)
        let fiscalYear = fiscalYear(for: todayDate(), startMonth: FiscalYearSettings.startMonth)
        let summary = try WithholdingStatementQueryUseCase(modelContext: context).summary(fiscalYear: fiscalYear)

        XCTAssertTrue(pending.contains(where: { candidate in
            candidate.counterpartyId == counterpartyId &&
            candidate.proposedLines.contains {
                $0.withholdingTaxCodeId == WithholdingTaxCode.professionalFee.rawValue &&
                $0.withholdingTaxAmount != nil
            }
        }))
        XCTAssertTrue(summary.documents.contains(where: { $0.counterpartyId == counterpartyId }))
    }
}
