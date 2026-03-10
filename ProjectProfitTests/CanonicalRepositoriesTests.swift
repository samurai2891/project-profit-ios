import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class CanonicalRepositoriesTests: XCTestCase {
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

    func testEvidenceRepositoryRoundTripsStructuredFieldsAndVersions() async throws {
        let repository = SwiftDataEvidenceRepository(modelContext: context)
        let businessId = UUID()
        let evidence = EvidenceDocument(
            businessId: businessId,
            taxYear: 2025,
            sourceType: .camera,
            legalDocumentType: .receipt,
            storageCategory: .electronicTransaction,
            receivedAt: Date(timeIntervalSince1970: 1_735_689_600),
            issueDate: Date(timeIntervalSince1970: 1_735_603_200),
            originalFilename: "receipt.pdf",
            mimeType: "application/pdf",
            fileHash: "abc123",
            originalFilePath: "/tmp/receipt.pdf",
            ocrText: "新宿商店 1,100円",
            extractionVersion: "ocr-v2",
            searchTokens: ["新宿商店", "1100"],
            structuredFields: EvidenceStructuredFields(
                counterpartyName: "新宿商店",
                transactionDate: Date(timeIntervalSince1970: 1_735_603_200),
                totalAmount: Decimal(string: "1100")!,
                confidence: 0.91
            ),
            linkedProjectIds: [UUID()],
            complianceStatus: .compliant
        )
        let version = EvidenceVersion(
            evidenceId: evidence.id,
            changedBy: "tester",
            nextStructuredFields: EvidenceStructuredFields(
                counterpartyName: "新宿商店",
                totalAmount: Decimal(string: "1100")!,
                confidence: 0.95
            ),
            reason: "manual-review",
            modelSource: .user
        )

        try await repository.save(evidence)
        try await repository.saveVersion(version)

        let fetched = try await repository.findById(evidence.id)
        let searchResults = try await repository.search(
            criteria: EvidenceSearchCriteria(
                businessId: businessId,
                taxYear: 2025,
                textQuery: "新宿商店"
            )
        )
        let versions = try await repository.findVersions(evidenceId: evidence.id)

        XCTAssertEqual(fetched?.structuredFields?.counterpartyName, "新宿商店")
        XCTAssertEqual(fetched?.structuredFields?.totalAmount, Decimal(string: "1100"))
        XCTAssertEqual(searchResults.map(\.id), [evidence.id])
        XCTAssertEqual(versions.map(\.id), [version.id])
    }

    func testCounterpartyRepositorySearchesNameAndRegistrationNumber() async throws {
        let repository = SwiftDataCounterpartyRepository(modelContext: context)
        let businessId = UUID()
        let counterparty = Counterparty(
            businessId: businessId,
            displayName: "株式会社青色",
            kana: "カブシキガイシャアオイロ",
            invoiceRegistrationNumber: "T1234567890123",
            invoiceIssuerStatus: .registered,
            notes: "主要取引先"
        )

        try await repository.save(counterparty)

        let byName = try await repository.findByName(businessId: businessId, query: "青色")
        let byRegistration = try await repository.findByRegistrationNumber("T1234567890123")

        XCTAssertEqual(byName.map(\.id), [counterparty.id])
        XCTAssertEqual(byRegistration?.id, counterparty.id)
    }

    func testChartOfAccountsRepositoryRoundTripsLookupAndUpdate() async throws {
        let repository = SwiftDataChartOfAccountsRepository(modelContext: context)
        let businessId = UUID()
        let accountId = UUID()
        let account = CanonicalAccount(
            id: accountId,
            businessId: businessId,
            legacyAccountId: "acct-travel",
            code: "501",
            name: "旅費交通費",
            accountType: .expense,
            normalBalance: .debit,
            defaultLegalReportLineId: "blue-return-expense-travel",
            defaultTaxCodeId: "TAX-10",
            projectAllocatable: true,
            householdProrationAllowed: true,
            displayOrder: 42,
            createdAt: Date(timeIntervalSince1970: 1_735_689_600),
            updatedAt: Date(timeIntervalSince1970: 1_735_689_600)
        )

        try await repository.save(account)

        let fetchedById = try await repository.findById(accountId)
        let fetchedByLegacyId = try await repository.findByLegacyId(
            businessId: businessId,
            legacyAccountId: "acct-travel"
        )
        let fetchedByCode = try await repository.findByCode(businessId: businessId, code: "501")
        let expenseAccounts = try await repository.findByType(businessId: businessId, accountType: .expense)

        XCTAssertEqual(fetchedById?.name, "旅費交通費")
        XCTAssertEqual(fetchedById?.legacyAccountId, "acct-travel")
        XCTAssertEqual(fetchedByLegacyId?.id, accountId)
        XCTAssertEqual(fetchedByCode?.id, accountId)
        XCTAssertEqual(expenseAccounts.map(\.id), [accountId])

        let updated = account.updated(
            name: "旅費",
            defaultTaxCodeId: .some("TAX-8"),
            projectAllocatable: false,
            householdProrationAllowed: false,
            displayOrder: 7
        )
        try await repository.save(updated)

        let fetchedUpdated = try await repository.findById(accountId)
        XCTAssertEqual(fetchedUpdated?.name, "旅費")
        XCTAssertEqual(fetchedUpdated?.defaultTaxCodeId, "TAX-8")
        XCTAssertEqual(fetchedUpdated?.displayOrder, 7)
        XCTAssertEqual(fetchedUpdated?.projectAllocatable, false)
    }

    func testDistributionTemplateRepositoryFiltersActiveRulesByDate() async throws {
        let repository = SwiftDataDistributionTemplateRepository(modelContext: context)
        let businessId = UUID()
        let activeRule = DistributionRule(
            businessId: businessId,
            name: "共通費均等配賦",
            scope: .allActiveProjectsInMonth,
            basis: .equal,
            weights: [],
            roundingPolicy: .lastProjectAdjust,
            effectiveFrom: Date(timeIntervalSince1970: 1_735_689_600),
            effectiveTo: nil,
            createdAt: Date(timeIntervalSince1970: 1_735_689_600)
        )
        let expiredRule = DistributionRule(
            businessId: businessId,
            name: "旧固定比率",
            scope: .selectedProjects,
            basis: .fixedWeight,
            weights: [
                DistributionWeight(projectId: UUID(), weight: Decimal(string: "0.6")!),
                DistributionWeight(projectId: UUID(), weight: Decimal(string: "0.4")!)
            ],
            roundingPolicy: .largestWeightAdjust,
            effectiveFrom: Date(timeIntervalSince1970: 1_704_153_600),
            effectiveTo: Date(timeIntervalSince1970: 1_720_051_200),
            createdAt: Date(timeIntervalSince1970: 1_704_153_600)
        )

        try await repository.save(activeRule)
        try await repository.save(expiredRule)

        let allRules = try await repository.findByBusiness(businessId: businessId)
        let activeRules = try await repository.findActive(
            businessId: businessId,
            at: Date(timeIntervalSince1970: 1_736_553_600)
        )

        XCTAssertEqual(Set(allRules.map(\.id)), Set([activeRule.id, expiredRule.id]))
        XCTAssertEqual(activeRules.map(\.id), [activeRule.id])
        XCTAssertEqual(activeRules.first?.weights, [])
    }

    func testPostingCandidateRepositoryRoundTripsJSONFields() async throws {
        let repository = SwiftDataPostingCandidateRepository(modelContext: context)
        let candidate = PostingCandidate(
            businessId: UUID(),
            taxYear: 2025,
            candidateDate: Date(timeIntervalSince1970: 1_736_294_400),
            proposedLines: [
                PostingCandidateLine(
                    debitAccountId: UUID(),
                    creditAccountId: UUID(),
                    amount: Decimal(string: "5000")!,
                    taxCodeId: "TAX-10",
                    memo: "旅費交通費"
                )
            ],
            taxAnalysis: TaxAnalysis(
                creditMethod: .qualifiedInvoice,
                taxRateBreakdown: TaxRateBreakdown(
                    totalRate: Decimal(string: "0.10")!,
                    nationalRate: Decimal(string: "0.078")!,
                    localRate: Decimal(string: "0.022")!
                ),
                taxableAmount: Decimal(string: "5000")!,
                taxAmount: Decimal(string: "500")!,
                deductibleTaxAmount: Decimal(string: "500")!
            ),
            confidenceScore: 0.88,
            status: .needsReview,
            source: .ocr,
            memo: "OCR候補",
            legacySnapshot: PostingCandidateLegacySnapshot(
                type: .expense,
                categoryId: "cat-tools",
                recurringId: nil,
                paymentAccountId: "acct-cash",
                transferToAccountId: nil,
                taxDeductibleRate: 100,
                taxAmount: 500,
                taxCodeId: TaxCode.standard10.rawValue,
                taxRate: 10,
                isTaxIncluded: false,
                taxCategory: .standardRate,
                receiptImagePath: nil,
                lineItems: [ReceiptLineItem(name: "旅費", unitPrice: 5000)],
                counterpartyName: "OCR商事"
            )
        )

        try await repository.save(candidate)
        let fetched = try await repository.findByStatus(businessId: candidate.businessId, status: .needsReview)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.proposedLines.first?.amount, Decimal(string: "5000"))
        XCTAssertEqual(fetched.first?.taxAnalysis?.taxAmount, Decimal(string: "500"))
        XCTAssertEqual(fetched.first?.legacySnapshot?.categoryId, "cat-tools")
        XCTAssertEqual(fetched.first?.legacySnapshot?.paymentAccountId, "acct-cash")
        XCTAssertEqual(fetched.first?.legacySnapshot?.lineItems.first?.name, "旅費")
    }

    func testCanonicalJournalEntryRepositoryUpdatesLinesAndSkipsInvalidVoucherNumbers() async throws {
        let repository = SwiftDataCanonicalJournalEntryRepository(modelContext: context)
        let businessId = UUID()
        let januaryDate = Date(timeIntervalSince1970: 1_736_294_400)
        let marchDate = Date(timeIntervalSince1970: 1_741_478_400)

        let invalidVoucherEntry = CanonicalJournalEntry(
            businessId: businessId,
            taxYear: 2025,
            journalDate: januaryDate,
            voucherNo: "invalid",
            description: "invalid",
            lines: [
                JournalLine(journalId: UUID(), accountId: UUID(), debitAmount: 1000, creditAmount: 0, sortOrder: 0),
                JournalLine(journalId: UUID(), accountId: UUID(), debitAmount: 0, creditAmount: 1000, sortOrder: 1)
            ]
        )
        let validJournalId = UUID()
        let validEntry = CanonicalJournalEntry(
            id: validJournalId,
            businessId: businessId,
            taxYear: 2025,
            journalDate: marchDate,
            voucherNo: "2025-003-00001",
            description: "valid",
            lines: [
                JournalLine(journalId: validJournalId, accountId: UUID(), debitAmount: 3000, creditAmount: 0, sortOrder: 0),
                JournalLine(journalId: validJournalId, accountId: UUID(), debitAmount: 0, creditAmount: 3000, sortOrder: 1)
            ]
        )

        try await repository.save(invalidVoucherEntry)
        try await repository.save(validEntry)

        let updated = CanonicalJournalEntry(
            id: validJournalId,
            businessId: businessId,
            taxYear: 2025,
            journalDate: marchDate,
            voucherNo: "2025-003-00001",
            description: "updated",
            lines: [
                JournalLine(journalId: validJournalId, accountId: UUID(), debitAmount: 1000, creditAmount: 0, sortOrder: 2),
                JournalLine(journalId: validJournalId, accountId: UUID(), debitAmount: 2000, creditAmount: 0, sortOrder: 0),
                JournalLine(journalId: validJournalId, accountId: UUID(), debitAmount: 0, creditAmount: 3000, sortOrder: 1)
            ]
        )
        try await repository.save(updated)

        let fetched = try await repository.findById(validJournalId)
        let nextVoucher = try await repository.nextVoucherNumber(businessId: businessId, taxYear: 2025, month: 3)

        XCTAssertEqual(fetched?.description, "updated")
        XCTAssertEqual(fetched?.lines.count, 3)
        XCTAssertEqual(fetched?.lines.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(nextVoucher.value, "2025-003-00002")
    }
}
