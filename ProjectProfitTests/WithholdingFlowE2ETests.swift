import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class WithholdingFlowE2ETests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
    }

    override func tearDown() {
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testWithholdingCandidateApprovalSummaryAndExportFlow() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let fiscalYear = fiscalYear(for: todayDate(), startMonth: FiscalYearSettings.startMonth)
        let project = mutations(dataStore).addProject(name: "Withholding E2E Project", description: "")
        let counterparty = Counterparty(
            businessId: businessId,
            displayName: "支払調書E2E先",
            address: "東京都港区1-2-3",
            payeeInfo: PayeeInfo(isWithholdingSubject: true, withholdingCategory: .professionalFee)
        )
        try await CounterpartyMasterUseCase(modelContext: context).save(counterparty)

        let candidate = try await PostingIntakeUseCase(modelContext: context).saveManualCandidate(
            input: ManualPostingCandidateInput(
                type: .expense,
                amount: 100_000,
                date: todayDate(),
                categoryId: "cat-tools",
                memo: "支払調書E2E",
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
                withholdingTaxAmount: nil,
                candidateSource: .manual
            )
        )

        let journal = try await PostingWorkflowUseCase(modelContext: context).approveCandidate(candidateId: candidate.id)
        let summary = try WithholdingStatementQueryUseCase(modelContext: context).summary(fiscalYear: fiscalYear)
        let document = try XCTUnwrap(summary.documents.first { $0.counterpartyId == counterparty.id })

        let annualCSV = try ExportCoordinator.export(
            target: .withholdingStatement,
            format: .csv,
            fiscalYear: fiscalYear,
            modelContext: context,
            skipPreflightValidation: true,
            withholdingStatementOptions: .init(
                scope: .annualSummary,
                annualSummary: summary,
                document: nil
            )
        )
        let payeePDF = try ExportCoordinator.export(
            target: .withholdingStatement,
            format: .pdf,
            fiscalYear: fiscalYear,
            modelContext: context,
            skipPreflightValidation: true,
            withholdingStatementOptions: .init(
                scope: .payee(document.counterpartyId),
                annualSummary: summary,
                document: document
            )
        )

        XCTAssertEqual(journal.lines.filter { $0.withholdingTaxAmount != nil }.count, 1)
        XCTAssertEqual(summary.documentCount, 1)
        XCTAssertEqual(document.paymentCount, 1)
        XCTAssertEqual(document.rows.first?.description, "支払調書E2E")
        XCTAssertTrue(FileManager.default.fileExists(atPath: annualCSV.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: payeePDF.path))
        XCTAssertEqual(FilingDashboardView.workflowItems.map(\.destinationID), [.booksWorkspace, .withholding, .closingEntry, .etaxExport])
    }
}
