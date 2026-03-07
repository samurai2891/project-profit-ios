import Foundation
import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class MigrationReportRunnerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try TestModelContainer.create()
        context = container.mainContext
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MigrationReportRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        ReceiptImageStore.setBaseDirectoryOverride(tempDirectory)
    }

    override func tearDownWithError() throws {
        ReceiptImageStore.setBaseDirectoryOverride(nil)
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    func testDryRunReportsProfileDeltaAndWarningWhenOnlyLegacyProfileExists() throws {
        context.insert(PPAccountingProfile(
            id: "legacy-profile",
            fiscalYear: 2025,
            businessName: "Legacy商店",
            ownerName: "田中太郎"
        ))
        try context.save()

        let report = try MigrationReportRunner(modelContext: context).dryRun()
        let profileDelta = try XCTUnwrap(report.deltas.first { $0.modelName == "Profile" })

        XCTAssertEqual(profileDelta.legacyCount, 1)
        XCTAssertEqual(profileDelta.canonicalCount, 0)
        XCTAssertTrue(profileDelta.executeSupported)
        XCTAssertTrue(report.warnings.contains("Profile canonical data is empty while legacy data exists"))
    }

    func testDryRunDetectsMissingReceiptImageAndMissingCandidateEvidence() throws {
        context.insert(PPCategory(id: "cat-expense", name: "経費", type: .expense, icon: "tag"))
        context.insert(PPTransaction(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            type: .expense,
            amount: 1200,
            date: Date(timeIntervalSince1970: 1_735_689_600),
            categoryId: "cat-expense",
            memo: "missing image",
            receiptImagePath: "missing-receipt.jpg"
        ))

        let orphanCandidate = PostingCandidate(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            evidenceId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            businessId: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            taxYear: 2025,
            candidateDate: Date(timeIntervalSince1970: 1_735_689_600),
            status: .needsReview
        )
        context.insert(PostingCandidateEntityMapper.toEntity(orphanCandidate))
        try context.save()

        let report = try MigrationReportRunner(modelContext: context).dryRun()

        XCTAssertTrue(
            report.orphanRecords.contains {
                $0.area == "legacy.transaction" && $0.message == "missing receipt image missing-receipt.jpg"
            }
        )
        XCTAssertTrue(
            report.orphanRecords.contains {
                $0.area == "canonical.candidate" && $0.identifier == orphanCandidate.id.uuidString && $0.message.contains("missing evidence")
            }
        )
    }
}
