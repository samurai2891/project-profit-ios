import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ReceiptEvidenceIntakeUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = container.mainContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    func testIntakeCreatesEvidenceCandidateAndDocumentRecordWithoutTransaction() async throws {
        let businessId = try await seedBusinessProfile()
        try await seedCanonicalAccount(
            businessId: businessId,
            legacyAccountId: "acct-supplies",
            code: "611",
            name: "消耗品費",
            accountType: .expense,
            normalBalance: .debit,
            displayOrder: 1
        )
        try await seedCanonicalAccount(
            businessId: businessId,
            legacyAccountId: "acct-cash",
            code: "101",
            name: "現金",
            accountType: .asset,
            normalBalance: .debit,
            displayOrder: 2
        )

        let useCase = ReceiptEvidenceIntakeUseCase(modelContext: context)
        let request = ReceiptEvidenceIntakeRequest(
            receiptData: ReceiptData(
                totalAmount: 1200,
                date: "2026-03-07",
                storeName: "文具センター",
                registrationNumber: nil,
                estimatedCategory: "tools",
                itemSummary: "ノート"
            ),
            ocrText: "文具センター\n合計 1,200円",
            sourceType: .camera,
            fileData: Data("jpeg".utf8),
            originalFileName: "camera-receipt.jpg",
            mimeType: "image/jpeg",
            reviewedAmount: 1200,
            reviewedDate: date(2026, 3, 7),
            transactionType: .expense,
            categoryId: "cat-tools",
            memo: "[レシート] 文具センター - ノート",
            lineItems: [LineItem(name: "ノート", quantity: 1, unitPrice: 1200)],
            linkedProjectIds: [],
            paymentAccountId: "acct-cash",
            transferToAccountId: nil,
            taxDeductibleRate: 100,
            taxCodeId: nil,
            isTaxIncluded: false,
            taxAmount: nil,
            registrationNumber: nil,
            counterpartyId: nil,
            counterpartyName: "文具センター"
        )

        let result = try await useCase.intake(request)
        defer { ReceiptImageStore.deleteDocumentFile(fileName: result.evidence.originalFilePath) }

        let evidence = try await EvidenceCatalogUseCase(modelContext: context).search(
            EvidenceSearchCriteria(businessId: businessId)
        )
        let candidates = try await PostingWorkflowUseCase(modelContext: context).candidates(
            evidenceId: result.evidence.id
        )
        let auditEvents = try context.fetch(FetchDescriptor<AuditEventEntity>())
        let documents = try context.fetch(FetchDescriptor<PPDocumentRecord>())
        let transactions = try context.fetch(FetchDescriptor<PPTransaction>())

        XCTAssertEqual(evidence.map(\.id), [result.evidence.id])
        XCTAssertEqual(candidates.map(\.id), [result.candidate.id])
        XCTAssertEqual(candidates.first?.evidenceId, result.evidence.id)
        XCTAssertEqual(candidates.first?.status, .needsReview)
        XCTAssertEqual(candidates.first?.source, .ocr)
        XCTAssertEqual(documents.map(\.id), [result.documentRecordId])
        XCTAssertTrue(transactions.isEmpty)
        XCTAssertEqual(result.evidence.structuredFields?.counterpartyName, "文具センター")
        XCTAssertEqual(result.candidate.proposedLines.count, 2)
        XCTAssertEqual(
            Set(auditEvents.map(\.eventTypeRaw)),
            Set([AuditEventType.evidenceCreated.rawValue, AuditEventType.candidateCreated.rawValue])
        )
    }

    func testIntakeMatchesExistingCounterpartyAndBuildsTaxLines() async throws {
        let businessId = try await seedBusinessProfile()
        try await seedCanonicalAccount(
            businessId: businessId,
            legacyAccountId: "acct-supplies",
            code: "611",
            name: "消耗品費",
            accountType: .expense,
            normalBalance: .debit,
            displayOrder: 1
        )
        try await seedCanonicalAccount(
            businessId: businessId,
            legacyAccountId: "acct-cash",
            code: "101",
            name: "現金",
            accountType: .asset,
            normalBalance: .debit,
            displayOrder: 2
        )
        try await seedCanonicalAccount(
            businessId: businessId,
            legacyAccountId: AccountingConstants.inputTaxAccountId,
            code: "142",
            name: "仮払消費税",
            accountType: .asset,
            normalBalance: .debit,
            displayOrder: 3
        )

        let counterparty = Counterparty(
            businessId: businessId,
            displayName: "登録済み商事",
            invoiceRegistrationNumber: "T1234567890123",
            invoiceIssuerStatus: .registered
        )
        try await CounterpartyMasterUseCase(modelContext: context).save(counterparty)

        let useCase = ReceiptEvidenceIntakeUseCase(modelContext: context)
        let request = ReceiptEvidenceIntakeRequest(
            receiptData: ReceiptData(
                totalAmount: 1100,
                taxAmount: 100,
                subtotalAmount: 1000,
                date: "2026-03-07",
                storeName: "登録済み商事",
                registrationNumber: "T1234567890123",
                estimatedCategory: "tools",
                itemSummary: "消耗品"
            ),
            ocrText: "登録済み商事\n小計 1,000円\n消費税 100円\n合計 1,100円",
            sourceType: .photoLibrary,
            fileData: Data("jpeg-tax".utf8),
            originalFileName: "photo-receipt.jpg",
            mimeType: "image/jpeg",
            reviewedAmount: 1100,
            reviewedDate: date(2026, 3, 7),
            transactionType: .expense,
            categoryId: "cat-tools",
            memo: "[レシート] 登録済み商事 - 消耗品",
            lineItems: [LineItem(name: "消耗品", quantity: 1, unitPrice: 1100)],
            linkedProjectIds: [],
            paymentAccountId: "acct-cash",
            transferToAccountId: nil,
            taxDeductibleRate: 100,
            taxCodeId: TaxCode.standard10.rawValue,
            isTaxIncluded: false,
            taxAmount: 100,
            registrationNumber: "T1234567890123",
            counterpartyId: nil,
            counterpartyName: "登録済み商事"
        )

        let result = try await useCase.intake(request)
        defer { ReceiptImageStore.deleteDocumentFile(fileName: result.evidence.originalFilePath) }

        XCTAssertEqual(result.evidence.linkedCounterpartyId, counterparty.id)
        XCTAssertEqual(result.candidate.counterpartyId, counterparty.id)
        XCTAssertEqual(result.evidence.structuredFields?.registrationNumber, "T1234567890123")
        XCTAssertTrue(result.evidence.searchTokens.contains("T1234567890123"))
        XCTAssertEqual(result.candidate.proposedLines.count, 3)
        XCTAssertEqual(result.candidate.proposedLines.compactMap(\.legalReportLineId).count, 3)
        XCTAssertEqual(
            result.candidate.proposedLines.compactMap(\.taxCodeId),
            [TaxCode.standard10.rawValue]
        )
        XCTAssertEqual(result.evidence.structuredFields?.taxStandardRate, Decimal(100))
        XCTAssertNil(result.evidence.structuredFields?.taxReducedRate)
    }

    func testIntakeBuildsReducedRateStructuredFieldsFromCanonicalTaxCode() async throws {
        let businessId = try await seedBusinessProfile()
        try await seedCanonicalAccount(
            businessId: businessId,
            legacyAccountId: "acct-supplies",
            code: "611",
            name: "消耗品費",
            accountType: .expense,
            normalBalance: .debit,
            displayOrder: 1
        )
        try await seedCanonicalAccount(
            businessId: businessId,
            legacyAccountId: "acct-cash",
            code: "101",
            name: "現金",
            accountType: .asset,
            normalBalance: .debit,
            displayOrder: 2
        )
        try await seedCanonicalAccount(
            businessId: businessId,
            legacyAccountId: AccountingConstants.inputTaxAccountId,
            code: "142",
            name: "仮払消費税",
            accountType: .asset,
            normalBalance: .debit,
            displayOrder: 3
        )

        let useCase = ReceiptEvidenceIntakeUseCase(modelContext: context)
        let request = ReceiptEvidenceIntakeRequest(
            receiptData: ReceiptData(
                totalAmount: 1080,
                taxAmount: 80,
                subtotalAmount: 1000,
                date: "2026-03-07",
                storeName: "食品ストア",
                registrationNumber: nil,
                estimatedCategory: "supplies",
                itemSummary: "軽減税率商品"
            ),
            ocrText: "食品ストア\n小計 1,000円\n消費税 80円\n合計 1,080円",
            sourceType: .camera,
            fileData: Data("jpeg-reduced".utf8),
            originalFileName: "reduced-rate.jpg",
            mimeType: "image/jpeg",
            reviewedAmount: 1080,
            reviewedDate: date(2026, 3, 7),
            transactionType: .expense,
            categoryId: "cat-tools",
            memo: "[レシート] 食品ストア - 軽減税率商品",
            lineItems: [LineItem(name: "軽減税率商品", quantity: 1, unitPrice: 1080)],
            linkedProjectIds: [],
            paymentAccountId: "acct-cash",
            transferToAccountId: nil,
            taxDeductibleRate: 100,
            taxCodeId: TaxCode.reduced8.rawValue,
            isTaxIncluded: false,
            taxAmount: 80,
            registrationNumber: nil,
            counterpartyId: nil,
            counterpartyName: "食品ストア"
        )

        let result = try await useCase.intake(request)
        defer { ReceiptImageStore.deleteDocumentFile(fileName: result.evidence.originalFilePath) }

        XCTAssertEqual(result.candidate.proposedLines.compactMap(\.taxCodeId), [TaxCode.reduced8.rawValue])
        XCTAssertEqual(result.evidence.structuredFields?.taxReducedRate, Decimal(80))
        XCTAssertNil(result.evidence.structuredFields?.taxStandardRate)
    }

    private func seedBusinessProfile() async throws -> UUID {
        let businessId = UUID()
        let profile = BusinessProfile(
            id: businessId,
            ownerName: "テスト事業者",
            businessName: "テスト商店",
            defaultPaymentAccountId: "acct-cash"
        )
        try await SwiftDataBusinessProfileRepository(modelContext: context).save(profile)
        return businessId
    }

    private func seedCanonicalAccount(
        businessId: UUID,
        legacyAccountId: String,
        code: String,
        name: String,
        accountType: CanonicalAccountType,
        normalBalance: NormalBalance,
        displayOrder: Int
    ) async throws {
        let account = CanonicalAccount(
            businessId: businessId,
            legacyAccountId: legacyAccountId,
            code: code,
            name: name,
            accountType: accountType,
            normalBalance: normalBalance,
            defaultLegalReportLineId: AccountingConstants.defaultLegalReportLineId(forLegacyAccountId: legacyAccountId),
            displayOrder: displayOrder
        )
        try await ChartOfAccountsUseCase(modelContext: context).save(account)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return components.date!
    }
}
