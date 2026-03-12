import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class WithholdingStatementQueryUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var businessId: UUID!

    override func setUp() {
        super.setUp()
        FeatureFlags.clearOverrides()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        businessId = dataStore.businessProfile?.id
        XCTAssertNotNil(businessId)
    }

    override func tearDown() {
        FeatureFlags.clearOverrides()
        businessId = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testSummaryGroupsApprovedJournalsByPayeeYearAndCode() async throws {
        let counterpartyA = Counterparty(
            businessId: businessId,
            displayName: "税理士法人A",
            address: "東京都千代田区1-1-1",
            payeeInfo: PayeeInfo(isWithholdingSubject: true, withholdingCategory: .professionalFee)
        )
        let counterpartyB = Counterparty(
            businessId: businessId,
            displayName: "デザイン事務所B",
            address: "大阪府大阪市2-2-2",
            payeeInfo: PayeeInfo(isWithholdingSubject: true, withholdingCategory: .designFee)
        )
        let counterpartyUseCase = CounterpartyMasterUseCase(modelContext: context)
        try await counterpartyUseCase.save(counterpartyA)
        try await counterpartyUseCase.save(counterpartyB)

        _ = try await makeApprovedWithholdingJournal(
            counterparty: counterpartyA,
            code: .professionalFee,
            amount: 100_000,
            date: makeDate(year: 2025, month: 4, day: 10),
            memo: "4月顧問料"
        )
        _ = try await makeApprovedWithholdingJournal(
            counterparty: counterpartyA,
            code: .professionalFee,
            amount: 200_000,
            date: makeDate(year: 2025, month: 5, day: 10),
            memo: "5月顧問料"
        )
        _ = try await makeApprovedWithholdingJournal(
            counterparty: counterpartyB,
            code: .designFee,
            amount: 80_000,
            date: makeDate(year: 2025, month: 6, day: 10),
            memo: "ロゴ制作"
        )
        _ = try await makePendingWithholdingCandidate(
            counterparty: counterpartyA,
            code: .professionalFee,
            amount: 50_000,
            date: makeDate(year: 2025, month: 7, day: 10),
            memo: "未承認顧問料"
        )

        let summary = try WithholdingStatementQueryUseCase(modelContext: context).summary(fiscalYear: 2025)
        let documentA = try XCTUnwrap(summary.documents.first { $0.counterpartyId == counterpartyA.id })
        let documentB = try XCTUnwrap(summary.documents.first { $0.counterpartyId == counterpartyB.id })
        let expectedAWithholding = WithholdingTaxCalculator.calculate(
            grossAmount: Decimal(100_000),
            code: .professionalFee
        ).withholdingAmount + WithholdingTaxCalculator.calculate(
            grossAmount: Decimal(200_000),
            code: .professionalFee
        ).withholdingAmount
        let expectedBWithholding = WithholdingTaxCalculator.calculate(
            grossAmount: Decimal(80_000),
            code: .designFee
        ).withholdingAmount

        XCTAssertEqual(summary.documentCount, 2)
        XCTAssertEqual(summary.paymentCount, 3)
        XCTAssertEqual(documentA.paymentCount, 2)
        XCTAssertEqual(documentA.totalGrossAmount, Decimal(300_000))
        XCTAssertEqual(documentA.totalWithholdingTaxAmount, expectedAWithholding)
        XCTAssertEqual(documentA.rows.map(\.description), ["4月顧問料", "5月顧問料"])
        XCTAssertEqual(documentB.paymentCount, 1)
        XCTAssertEqual(documentB.totalGrossAmount, Decimal(80_000))
        XCTAssertEqual(documentB.totalWithholdingTaxAmount, expectedBWithholding)
    }

    func testExportCoordinatorExportsAnnualAndPayeeWithholdingStatements() async throws {
        let counterparty = Counterparty(
            businessId: businessId,
            displayName: "源泉対象支払先",
            invoiceRegistrationNumber: "T1234567890123",
            address: "東京都港区3-3-3",
            payeeInfo: PayeeInfo(isWithholdingSubject: true, withholdingCategory: .professionalFee)
        )
        try await CounterpartyMasterUseCase(modelContext: context).save(counterparty)
        _ = try await makeApprovedWithholdingJournal(
            counterparty: counterparty,
            code: .professionalFee,
            amount: 100_000,
            date: makeDate(year: 2025, month: 4, day: 10),
            memo: "支払調書テスト"
        )

        let summary = try WithholdingStatementQueryUseCase(modelContext: context).summary(fiscalYear: 2025)
        let document = try XCTUnwrap(summary.documents.first)

        let annualCSV = try ExportCoordinator.export(
            target: .withholdingStatement,
            format: .csv,
            fiscalYear: 2025,
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
            fiscalYear: 2025,
            modelContext: context,
            skipPreflightValidation: true,
            withholdingStatementOptions: .init(
                scope: .payee(document.counterpartyId),
                annualSummary: summary,
                document: document
            )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: annualCSV.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: payeePDF.path))
        XCTAssertTrue(try String(contentsOf: annualCSV, encoding: .utf8).contains("源泉対象支払先"))
        XCTAssertEqual(String(decoding: try Data(contentsOf: payeePDF).prefix(4), as: UTF8.self), "%PDF")

        XCTAssertThrowsError(
            try ExportCoordinator.export(
                target: .withholdingStatement,
                format: .xlsx,
                fiscalYear: 2025,
                modelContext: context,
                skipPreflightValidation: true,
                withholdingStatementOptions: .init(
                    scope: .annualSummary,
                    annualSummary: summary,
                    document: nil
                )
            )
        ) { error in
            guard let exportError = error as? ExportCoordinator.ExportError,
                  case .unsupportedFormat(let target, let format) = exportError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(target, .withholdingStatement)
            XCTAssertEqual(format, .xlsx)
        }
    }

    private func makeApprovedWithholdingJournal(
        counterparty: Counterparty,
        code: WithholdingTaxCode,
        amount: Int,
        date: Date,
        memo: String
    ) async throws -> CanonicalJournalEntry {
        let candidate = try await makePendingWithholdingCandidate(
            counterparty: counterparty,
            code: code,
            amount: amount,
            date: date,
            memo: memo
        )
        return try await PostingWorkflowUseCase(modelContext: context).approveCandidate(candidateId: candidate.id)
    }

    private func makePendingWithholdingCandidate(
        counterparty: Counterparty,
        code: WithholdingTaxCode,
        amount: Int,
        date: Date,
        memo: String
    ) async throws -> PostingCandidate {
        let project = mutations(dataStore).addProject(name: "Withholding Query Project \(UUID().uuidString.prefix(4))", description: "")
        return try await PostingIntakeUseCase(modelContext: context).saveManualCandidate(
            input: ManualPostingCandidateInput(
                type: .expense,
                amount: amount,
                date: date,
                categoryId: "cat-tools",
                memo: memo,
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
                withholdingTaxCodeId: code.rawValue,
                withholdingTaxAmount: nil,
                candidateSource: .manual
            )
        )
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
