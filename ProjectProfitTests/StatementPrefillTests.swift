import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class StatementPrefillTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: PostingIntakeUseCase!

    override func setUp() {
        super.setUp()
        FeatureFlags.clearOverrides()
        FeatureFlags.useCanonicalPosting = true
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = PostingIntakeUseCase(modelContext: context)
    }

    override func tearDown() {
        FeatureFlags.clearOverrides()
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testStatementLinePrefillKeepsDateAmountMemoCounterpartyAndAccount() async throws {
        let project = mutations(dataStore).addProject(name: "PJ", description: "")
        let line = StatementLineRecord(
            importId: UUID(),
            businessId: try XCTUnwrap(dataStore.businessProfile?.id),
            statementKind: .card,
            paymentAccountId: "acct-cc",
            date: makeDate(2026, 1, 20),
            description: "会食",
            amount: Decimal(4800),
            direction: .outflow,
            counterparty: "カフェテスト",
            reference: "REF-01",
            memo: "明細から起票"
        )
        let prefill = try XCTUnwrap(StatementLinePrefill(line: line))

        XCTAssertEqual(prefill.type, .expense)
        XCTAssertEqual(prefill.amount, 4800)
        XCTAssertEqual(prefill.date, makeDate(2026, 1, 20))
        XCTAssertEqual(prefill.memo, "明細から起票")
        XCTAssertEqual(prefill.counterparty, "カフェテスト")
        XCTAssertEqual(prefill.paymentAccountId, "acct-cc")

        let candidate = try await useCase.saveManualCandidate(
            input: ManualPostingCandidateInput(
                type: prefill.type,
                amount: prefill.amount,
                date: prefill.date,
                categoryId: "cat-food",
                memo: prefill.memo,
                allocations: [(projectId: project.id, ratio: 100)],
                paymentAccountId: prefill.paymentAccountId,
                transferToAccountId: nil,
                taxDeductibleRate: 100,
                taxAmount: nil,
                taxCodeId: nil,
                isTaxIncluded: nil,
                counterpartyId: nil,
                counterparty: prefill.counterparty,
                isWithholdingEnabled: false,
                withholdingTaxCodeId: nil,
                withholdingTaxAmount: nil,
                candidateSource: .manual
            )
        )

        XCTAssertEqual(candidate.status, .draft)
        XCTAssertEqual(candidate.memo, "明細から起票")
        XCTAssertEqual(candidate.legacySnapshot?.paymentAccountId, "acct-cc")
        XCTAssertEqual(candidate.legacySnapshot?.counterpartyName, "カフェテスト")
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
