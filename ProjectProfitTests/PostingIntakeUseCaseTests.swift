import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class PostingIntakeUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: PostingIntakeUseCase!

    override func setUp() {
        super.setUp()
        FeatureFlags.clearOverrides()
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

    func testSaveManualCandidateCreatesDraftWithoutLegacyTransaction() async throws {
        FeatureFlags.useCanonicalPosting = true
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let beforeTransactions = dataStore.transactions.count
        let workflow = PostingWorkflowUseCase(modelContext: context)
        let fiscalYear = fiscalYear(for: Date(), startMonth: FiscalYearSettings.startMonth)
        let beforeJournals = try await workflow.journals(businessId: businessId, taxYear: fiscalYear)

        let candidate = try await useCase.saveManualCandidate(
            input: ManualPostingCandidateInput(
                type: .expense,
                amount: 12_000,
                date: Date(),
                categoryId: "cat-tools",
                memo: "manual candidate",
                allocations: [(projectId: project.id, ratio: 100)],
                paymentAccountId: "acct-cash",
                transferToAccountId: nil,
                taxDeductibleRate: 100,
                taxAmount: 1_200,
                taxCodeId: TaxCode.standard10.rawValue,
                taxRate: 10,
                isTaxIncluded: false,
                taxCategory: .standardRate,
                counterpartyId: nil,
                counterparty: nil,
                candidateSource: .manual
            )
        )

        let pendingCandidates = try await workflow.pendingCandidates(businessId: businessId)
        let journals = try await workflow.journals(businessId: businessId, taxYear: fiscalYear)

        XCTAssertEqual(candidate.status, .draft)
        XCTAssertEqual(candidate.source, .manual)
        XCTAssertEqual(candidate.legacySnapshot?.categoryId, "cat-tools")
        XCTAssertEqual(dataStore.transactions.count, beforeTransactions)
        XCTAssertEqual(journals.count, beforeJournals.count)
        XCTAssertTrue(pendingCandidates.contains(where: { $0.id == candidate.id }))
    }

    func testSaveManualCandidateFailsForYearLockedDate() async {
        FeatureFlags.useCanonicalPosting = true
        let lockedYear = Calendar.current.component(.year, from: Date())
        mutations(dataStore).lockFiscalYear(lockedYear)
        let project = mutations(dataStore).addProject(name: "Locked PJ", description: "")

        do {
            _ = try await useCase.saveManualCandidate(
                input: ManualPostingCandidateInput(
                    type: .expense,
                    amount: 5_000,
                    date: Date(),
                    categoryId: "cat-tools",
                    memo: "locked candidate",
                    allocations: [(projectId: project.id, ratio: 100)],
                    paymentAccountId: "acct-cash",
                    transferToAccountId: nil,
                    taxDeductibleRate: nil,
                    taxAmount: nil,
                    taxCodeId: nil,
                    taxRate: nil,
                    isTaxIncluded: nil,
                    taxCategory: nil,
                    counterpartyId: nil,
                    counterparty: nil,
                    candidateSource: .manual
                )
            )
            XCTFail("year locked save should fail")
        } catch let error as AppError {
            guard case let .yearLocked(year) = error else {
                return XCTFail("expected yearLocked error, got \(error)")
            }
            XCTAssertEqual(year, lockedYear)
        } catch {
            XCTFail("unexpected error: \(error.localizedDescription)")
        }
    }

    func testImportTransactionsCreatesCanonicalJournalWithoutLegacyMirrorTransaction() async throws {
        FeatureFlags.useCanonicalPosting = true
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let beforeTransactions = dataStore.transactions.count
        let workflow = PostingWorkflowUseCase(modelContext: context)
        let beforeJournals = try await workflow.journals(businessId: businessId, taxYear: 2026)
        let csv = """
        日付,種類,金額,カテゴリ,プロジェクト,メモ,支払口座,税率,税込区分,税区分
        2026-01-10,経費,5500,ツール,ImportProject(100%),CSV取り込み,acct-cash,10,税込,課税（10%）
        """

        let result = await useCase.importTransactions(csvString: csv)
        dataStore.refreshProjects()
        dataStore.refreshTransactions()
        dataStore.refreshJournalEntries()
        dataStore.refreshJournalLines()
        let journals = try await workflow.journals(businessId: businessId, taxYear: 2026)
        let project = try XCTUnwrap(dataStore.projects.first { $0.name == "ImportProject" })

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(dataStore.transactions.count, beforeTransactions)
        XCTAssertEqual(journals.count, beforeJournals.count + 1)
        XCTAssertEqual(Set(journals.last?.lines.compactMap(\.taxCodeId) ?? []), [TaxCode.standard10.rawValue])
        XCTAssertEqual(dataStore.getProjectSummary(projectId: project.id)?.totalExpense, 5_500)
    }

    func testImportTransactionsReportsInvalidAllocationRatio() async {
        let csv = """
        日付,種類,金額,カテゴリ,プロジェクト,メモ
        2026-01-10,経費,5500,ツール,ImportProjectA(60%);ImportProjectB(30%),CSV取り込み
        """

        let result = await useCase.importTransactions(csvString: csv)

        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.errorCount, 1)
        XCTAssertEqual(result.errors.first, "配分比率が不正です（合計: 90%）")
    }

    func testImportTransactionsReportsUnknownCategory() async {
        let csv = """
        日付,種類,金額,カテゴリ,プロジェクト,メモ
        2026-01-10,経費,5500,存在しないカテゴリ,ImportProject(100%),CSV取り込み
        """

        let result = await useCase.importTransactions(csvString: csv)

        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.errorCount, 1)
        XCTAssertEqual(result.errors.first, "カテゴリが見つかりません: 存在しないカテゴリ")
    }
}
