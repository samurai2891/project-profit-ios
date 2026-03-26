import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class EvidenceInboxQueryUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    func testSearchEvidenceReturnsEmptyWithoutBusinessProfile() async throws {
        let useCase = EvidenceInboxQueryUseCase(
            modelContext: context,
            currentDateProvider: { self.date(2026, 3, 11) }
        )

        let results = try await useCase.searchEvidence(
            form: EvidenceSearchFormState(),
            selectedStatus: nil
        )

        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(
            useCase.reloadKey(selectedStatus: nil, searchReloadToken: "token"),
            "none:all:token"
        )
        XCTAssertFalse(useCase.isCurrentYearLocked())
    }

    func testIsCurrentYearLockedMatchesStoredTaxYearState() async throws {
        let businessId = UUID()
        try seedBusinessProfile(id: businessId)
        try seedTaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            state: .finalLock
        )

        let useCase = EvidenceInboxQueryUseCase(
            modelContext: context,
            currentDateProvider: { self.date(2026, 3, 11) },
            startMonth: 4
        )

        XCTAssertTrue(useCase.isCurrentYearLocked())
    }

    func testAvailableProjectsAndProjectNamesPreserveCurrentData() throws {
        let businessId = UUID()
        try seedBusinessProfile(id: businessId)
        let older = PPProject(
            name: "旧案件",
            createdAt: date(2025, 1, 10),
            updatedAt: date(2025, 1, 10)
        )
        let newer = PPProject(
            name: "新案件",
            createdAt: date(2025, 2, 10),
            updatedAt: date(2025, 2, 10)
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        let useCase = EvidenceInboxQueryUseCase(modelContext: context)

        XCTAssertEqual(useCase.availableProjects().map(\.name), ["新案件", "旧案件"])
        XCTAssertEqual(useCase.projectNames(ids: [older.id, newer.id]), ["旧案件", "新案件"])
    }

    func testJournalsUsesPostingWorkflowResults() async throws {
        let businessId = UUID()
        let evidenceId = UUID()
        let journal = CanonicalJournalEntry(
            businessId: businessId,
            taxYear: 2026,
            journalDate: date(2026, 3, 10),
            voucherNo: "2026-03-001",
            sourceEvidenceId: evidenceId,
            lines: [
                JournalLine(
                    journalId: UUID(),
                    accountId: UUID(),
                    debitAmount: Decimal(1200),
                    creditAmount: .zero,
                    sortOrder: 0
                ),
                JournalLine(
                    journalId: UUID(),
                    accountId: UUID(),
                    debitAmount: .zero,
                    creditAmount: Decimal(1200),
                    sortOrder: 1
                ),
            ],
            approvedAt: date(2026, 3, 10),
            createdAt: date(2026, 3, 10),
            updatedAt: date(2026, 3, 10)
        )
        try await SwiftDataCanonicalJournalEntryRepository(modelContext: context).save(journal)

        let useCase = EvidenceInboxQueryUseCase(modelContext: context)
        let results = try await useCase.journals(evidenceId: evidenceId)

        XCTAssertEqual(results.map(\.id), [journal.id])
    }

    func testRebuildEvidenceIndexAllowsSubsequentSearch() async throws {
        let businessId = UUID()
        try seedBusinessProfile(id: businessId)
        let evidence = EvidenceDocument(
            businessId: businessId,
            taxYear: 2026,
            sourceType: .camera,
            legalDocumentType: .receipt,
            storageCategory: .paperScan,
            receivedAt: date(2026, 3, 10),
            issueDate: date(2026, 3, 10),
            originalFilename: "receipt.jpg",
            mimeType: "image/jpeg",
            fileHash: "hash-1",
            originalFilePath: "evidence-test-receipt.jpg",
            ocrText: "テスト商店 1200円",
            searchTokens: ["テスト商店", "1200"],
            linkedProjectIds: [],
            complianceStatus: .pendingReview,
            createdAt: date(2026, 3, 10),
            updatedAt: date(2026, 3, 10)
        )
        try await EvidenceCatalogUseCase(modelContext: context).save(evidence)

        let useCase = EvidenceInboxQueryUseCase(
            modelContext: context,
            currentDateProvider: { self.date(2026, 3, 11) }
        )
        var form = EvidenceSearchFormState()
        form.textQuery = "テスト商店"

        try await useCase.rebuildEvidenceIndex()
        let results = try await useCase.searchEvidence(form: form, selectedStatus: nil)

        XCTAssertEqual(results.map(\.id), [evidence.id])
    }

    private func seedBusinessProfile(id: UUID) throws {
        context.insert(
            BusinessProfileEntity(
                businessId: id,
                ownerName: "テスト事業者",
                createdAt: date(2025, 1, 1),
                updatedAt: date(2025, 1, 1)
            )
        )
        try context.save()
    }

    private func seedTaxYearProfile(
        businessId: UUID,
        taxYear: Int,
        state: YearLockState
    ) throws {
        context.insert(
            TaxYearProfileEntity(
                businessId: businessId,
                taxYear: taxYear,
                yearLockStateRaw: state.rawValue,
                taxPackVersion: "\(taxYear)-v1",
                createdAt: date(2025, 1, 1),
                updatedAt: date(2025, 1, 1)
            )
        )
        try context.save()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
