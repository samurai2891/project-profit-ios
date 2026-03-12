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
            counterpartyName: "文具センター",
            isWithholdingEnabled: false,
            withholdingTaxCodeId: nil,
            withholdingTaxAmount: nil
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
        XCTAssertFalse(result.duplicateDetected)
        XCTAssertEqual(result.evidence.structuredFields?.counterpartyName, "文具センター")
        XCTAssertEqual(result.candidate.proposedLines.count, 2)
        XCTAssertEqual(result.candidate.legacySnapshot?.categoryId, "cat-tools")
        XCTAssertEqual(result.candidate.legacySnapshot?.paymentAccountId, "acct-cash")
        XCTAssertEqual(result.candidate.legacySnapshot?.lineItems.first?.name, "ノート")
        XCTAssertEqual(result.candidate.legacySnapshot?.counterpartyName, "文具センター")
        XCTAssertEqual(
            Set(auditEvents.map(\.eventTypeRaw)),
            Set([AuditEventType.evidenceCreated.rawValue, AuditEventType.candidateCreated.rawValue])
        )
    }

    func testIntakeThrowsDuplicateEvidenceWhenSameFileHashAlreadyExists() async throws {
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
        let firstRequest = ReceiptEvidenceIntakeRequest(
            receiptData: ReceiptData(
                totalAmount: 1200,
                date: "2026-03-07",
                storeName: "重複チェック商店",
                registrationNumber: nil,
                estimatedCategory: "tools",
                itemSummary: "ノート"
            ),
            ocrText: "重複チェック商店\n合計 1,200円",
            sourceType: .camera,
            fileData: Data("same-file-binary".utf8),
            originalFileName: "duplicate-base.jpg",
            mimeType: "image/jpeg",
            reviewedAmount: 1200,
            reviewedDate: date(2026, 3, 7),
            transactionType: .expense,
            categoryId: "cat-tools",
            memo: "[レシート] 重複チェック商店 - ノート",
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
            counterpartyName: "重複チェック商店",
            isWithholdingEnabled: false,
            withholdingTaxCodeId: nil,
            withholdingTaxAmount: nil
        )
        let firstResult = try await useCase.intake(firstRequest)
        defer { ReceiptImageStore.deleteDocumentFile(fileName: firstResult.evidence.originalFilePath) }

        let duplicateRequest = ReceiptEvidenceIntakeRequest(
            receiptData: ReceiptData(
                totalAmount: 1200,
                date: "2026-03-08",
                storeName: "重複チェック商店",
                registrationNumber: nil,
                estimatedCategory: "tools",
                itemSummary: "ノート再取込"
            ),
            ocrText: "重複チェック商店\n合計 1,200円",
            sourceType: .photoLibrary,
            fileData: Data("same-file-binary".utf8),
            originalFileName: "duplicate-second.jpg",
            mimeType: "image/jpeg",
            reviewedAmount: 1200,
            reviewedDate: date(2026, 3, 8),
            transactionType: .expense,
            categoryId: "cat-tools",
            memo: "[レシート] 重複チェック商店 - ノート再取込",
            lineItems: [LineItem(name: "ノート再取込", quantity: 1, unitPrice: 1200)],
            linkedProjectIds: [],
            paymentAccountId: "acct-cash",
            transferToAccountId: nil,
            taxDeductibleRate: 100,
            taxCodeId: nil,
            isTaxIncluded: false,
            taxAmount: nil,
            registrationNumber: nil,
            counterpartyId: nil,
            counterpartyName: "重複チェック商店",
            isWithholdingEnabled: false,
            withholdingTaxCodeId: nil,
            withholdingTaxAmount: nil
        )

        do {
            _ = try await useCase.intake(duplicateRequest)
            XCTFail("duplicate intake should throw an error")
        } catch let error as ReceiptEvidenceIntakeUseCaseError {
            switch error {
            case let .duplicateEvidence(existingEvidenceId, fileHash):
                XCTAssertEqual(existingEvidenceId, firstResult.evidence.id)
                XCTAssertEqual(fileHash, firstResult.evidence.fileHash)
            default:
                XCTFail("unexpected error: \(error)")
            }
        }

        let evidences = try await EvidenceCatalogUseCase(modelContext: context).search(
            EvidenceSearchCriteria(businessId: businessId)
        )
        let candidates = try await PostingWorkflowUseCase(modelContext: context).candidates(
            evidenceId: firstResult.evidence.id
        )
        let documents = try context.fetch(FetchDescriptor<PPDocumentRecord>())

        XCTAssertEqual(evidences.count, 1)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(documents.count, 1)
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
            counterpartyName: "登録済み商事",
            isWithholdingEnabled: false,
            withholdingTaxCodeId: nil,
            withholdingTaxAmount: nil
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
            counterpartyName: "食品ストア",
            isWithholdingEnabled: false,
            withholdingTaxCodeId: nil,
            withholdingTaxAmount: nil
        )

        let result = try await useCase.intake(request)
        defer { ReceiptImageStore.deleteDocumentFile(fileName: result.evidence.originalFilePath) }

        XCTAssertEqual(result.candidate.proposedLines.compactMap(\.taxCodeId), [TaxCode.reduced8.rawValue])
        XCTAssertEqual(result.evidence.structuredFields?.taxReducedRate, Decimal(80))
        XCTAssertNil(result.evidence.structuredFields?.taxStandardRate)
    }

    func testIntakeAppliesCounterpartyWithholdingDefaultsToCandidate() async throws {
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
            legacyAccountId: AccountingConstants.withholdingTaxPayableAccountId,
            code: "205",
            name: "源泉所得税預り金",
            accountType: .liability,
            normalBalance: .credit,
            displayOrder: 3
        )

        let counterparty = Counterparty(
            businessId: businessId,
            displayName: "顧問税理士",
            payeeInfo: PayeeInfo(
                isWithholdingSubject: true,
                withholdingCategory: .professionalFee
            )
        )
        try await CounterpartyMasterUseCase(modelContext: context).save(counterparty)

        let request = ReceiptEvidenceIntakeRequest(
            receiptData: ReceiptData(
                totalAmount: 100_000,
                date: "2026-03-07",
                storeName: "顧問税理士",
                registrationNumber: nil,
                estimatedCategory: "tools",
                itemSummary: "顧問料"
            ),
            ocrText: "顧問税理士\n合計 100,000円",
            sourceType: .camera,
            fileData: Data("jpeg-withholding".utf8),
            originalFileName: "withholding-default.jpg",
            mimeType: "image/jpeg",
            reviewedAmount: 100_000,
            reviewedDate: date(2026, 3, 7),
            transactionType: .expense,
            categoryId: "cat-tools",
            memo: "顧問料",
            lineItems: [LineItem(name: "顧問料", quantity: 1, unitPrice: 100_000)],
            linkedProjectIds: [],
            paymentAccountId: "acct-cash",
            transferToAccountId: nil,
            taxDeductibleRate: 100,
            taxCodeId: nil,
            isTaxIncluded: false,
            taxAmount: nil,
            registrationNumber: nil,
            counterpartyId: counterparty.id,
            counterpartyName: "顧問税理士",
            isWithholdingEnabled: false,
            withholdingTaxCodeId: nil,
            withholdingTaxAmount: nil
        )

        let result = try await ReceiptEvidenceIntakeUseCase(modelContext: context).intake(request)
        defer { ReceiptImageStore.deleteDocumentFile(fileName: result.evidence.originalFilePath) }

        let expectedWithholding = WithholdingTaxCalculator.calculate(
            grossAmount: Decimal(100_000),
            code: .professionalFee
        ).withholdingAmount
        let annotatedLine = try XCTUnwrap(result.candidate.proposedLines.first { $0.withholdingTaxAmount != nil })

        XCTAssertEqual(result.candidate.proposedLines.count, 3)
        XCTAssertEqual(annotatedLine.withholdingTaxCodeId, WithholdingTaxCode.professionalFee.rawValue)
        XCTAssertEqual(annotatedLine.withholdingTaxAmount, expectedWithholding)
        XCTAssertEqual(annotatedLine.withholdingTaxBaseAmount, Decimal(100_000))
        XCTAssertTrue(result.candidate.proposedLines.contains {
            $0.creditAccountId != nil && $0.amount == expectedWithholding
        })
    }

    func testIntakeAppliesUserRuleToResolvedCategoryAndCandidateLines() async throws {
        let businessId = try await seedBusinessProfile()
        let communicationLegacyAccountId = "acct-communication"
        try await seedCanonicalAccount(
            businessId: businessId,
            legacyAccountId: communicationLegacyAccountId,
            code: "612",
            name: "クラウド通信費",
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

        context.insert(
            PPAccount(
                id: communicationLegacyAccountId,
                code: "612",
                name: "クラウド通信費",
                accountType: .expense,
                subtype: .communicationExpense,
                displayOrder: 1
            )
        )
        context.insert(
            PPCategory(
                id: "cat-cloud-communication",
                name: "クラウド通信費",
                type: .expense,
                icon: "wifi",
                linkedAccountId: communicationLegacyAccountId
            )
        )
        context.insert(
            PPUserRule(
                keyword: "AWS",
                taxLine: .communicationExpense,
                priority: 300
            )
        )
        try context.save()

        let expectedExpenseAccount = try await ChartOfAccountsUseCase(modelContext: context).account(
            businessId: businessId,
            legacyAccountId: communicationLegacyAccountId
        )
        let expectedExpenseAccountId = try XCTUnwrap(expectedExpenseAccount?.id)

        let useCase = ReceiptEvidenceIntakeUseCase(modelContext: context)
        let request = ReceiptEvidenceIntakeRequest(
            receiptData: ReceiptData(
                totalAmount: 3_300,
                date: "2026-03-07",
                storeName: "AWS",
                registrationNumber: nil,
                estimatedCategory: "tools",
                itemSummary: "月額利用料"
            ),
            ocrText: "AWS\n合計 3,300円",
            sourceType: .camera,
            fileData: Data("jpeg-aws".utf8),
            originalFileName: "aws-receipt.jpg",
            mimeType: "image/jpeg",
            reviewedAmount: 3_300,
            reviewedDate: date(2026, 3, 7),
            transactionType: .expense,
            categoryId: "cat-tools",
            memo: "AWS 月額利用料",
            lineItems: [LineItem(name: "月額利用料", quantity: 1, unitPrice: 3_300)],
            linkedProjectIds: [],
            paymentAccountId: "acct-cash",
            transferToAccountId: nil,
            taxDeductibleRate: 100,
            taxCodeId: nil,
            isTaxIncluded: false,
            taxAmount: nil,
            registrationNumber: nil,
            counterpartyId: nil,
            counterpartyName: "AWS",
            isWithholdingEnabled: false,
            withholdingTaxCodeId: nil,
            withholdingTaxAmount: nil
        )

        let result = try await useCase.intake(request)
        defer { ReceiptImageStore.deleteDocumentFile(fileName: result.evidence.originalFilePath) }

        XCTAssertEqual(result.candidate.legacySnapshot?.categoryId, "cat-cloud-communication")
        XCTAssertEqual(result.candidate.proposedLines.first?.debitAccountId, expectedExpenseAccountId)
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
