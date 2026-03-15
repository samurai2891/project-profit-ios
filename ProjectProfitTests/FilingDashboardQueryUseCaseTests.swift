import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class FilingDashboardQueryUseCaseTests: XCTestCase {
    func testSnapshotWithoutBusinessProfileReturnsOpenStateAndNoIssues() async throws {
        let useCase = FilingDashboardQueryUseCase(
            businessProfileRepository: StubBusinessProfileRepository(defaultProfile: nil),
            taxYearProfileRepository: StubTaxYearProfileRepository(),
            preflightReportLoader: { _, _ in
                XCTFail("preflight should not run without business profile")
                throw StubError.unexpectedCall
            }
        )

        let snapshot = try await useCase.snapshot(fiscalYear: 2025)

        XCTAssertNil(snapshot.businessId)
        XCTAssertEqual(snapshot.yearLockState, YearLockState.open)
        XCTAssertEqual(snapshot.preflightIssues, [])
    }

    func testSnapshotUsesPersistedYearLockStateWhenTaxYearProfileExists() async throws {
        let businessId = UUID()
        let useCase = FilingDashboardQueryUseCase(
            businessProfileRepository: StubBusinessProfileRepository(
                defaultProfile: BusinessProfile(id: businessId, ownerName: "所有者", businessName: "事業")
            ),
            taxYearProfileRepository: StubTaxYearProfileRepository(
                profiles: [
                    TaxYearProfile(
                        businessId: businessId,
                        taxYear: 2025,
                        yearLockState: .taxClose
                    )
                ]
            ),
            preflightReportLoader: { _, _ in
                FilingPreflightReport(
                    businessId: businessId,
                    taxYear: 2025,
                    context: .export,
                    issues: [],
                    generatedAt: Date()
                )
            }
        )

        let snapshot = try await useCase.snapshot(fiscalYear: 2025)

        XCTAssertEqual(snapshot.businessId, businessId)
        XCTAssertEqual(snapshot.yearLockState, YearLockState.taxClose)
        XCTAssertEqual(snapshot.preflightIssues, [])
    }

    func testSnapshotDefaultsToOpenWhenTaxYearProfileDoesNotExist() async throws {
        let businessId = UUID()
        let useCase = FilingDashboardQueryUseCase(
            businessProfileRepository: StubBusinessProfileRepository(
                defaultProfile: BusinessProfile(id: businessId, ownerName: "所有者", businessName: "事業")
            ),
            taxYearProfileRepository: StubTaxYearProfileRepository(),
            preflightReportLoader: { _, _ in
                FilingPreflightReport(
                    businessId: businessId,
                    taxYear: 2026,
                    context: .export,
                    issues: [],
                    generatedAt: Date()
                )
            }
        )

        let snapshot = try await useCase.snapshot(fiscalYear: 2026)

        XCTAssertEqual(snapshot.yearLockState, YearLockState.open)
    }

    func testSnapshotReturnsBlockingPreflightMessages() async throws {
        let businessId = UUID()
        let useCase = FilingDashboardQueryUseCase(
            businessProfileRepository: StubBusinessProfileRepository(
                defaultProfile: BusinessProfile(id: businessId, ownerName: "所有者", businessName: "事業")
            ),
            taxYearProfileRepository: StubTaxYearProfileRepository(),
            preflightReportLoader: { _, fiscalYear in
                FilingPreflightReport(
                    businessId: businessId,
                    taxYear: fiscalYear,
                    context: .export,
                    issues: [
                        FilingPreflightIssue(
                            code: .yearStateTooOpen,
                            severity: .error,
                            message: "帳票出力は税務締め以降でのみ実行できます"
                        ),
                        FilingPreflightIssue(
                            code: .pendingCandidateExists,
                            severity: .warning,
                            message: "warning"
                        )
                    ],
                    generatedAt: Date()
                )
            }
        )

        let snapshot = try await useCase.snapshot(fiscalYear: 2025)

        XCTAssertEqual(snapshot.preflightIssues, ["帳票出力は税務締め以降でのみ実行できます"])
    }

    func testSnapshotReturnsLocalizedDescriptionWhenPreflightThrows() async throws {
        let businessId = UUID()
        let useCase = FilingDashboardQueryUseCase(
            businessProfileRepository: StubBusinessProfileRepository(
                defaultProfile: BusinessProfile(id: businessId, ownerName: "所有者", businessName: "事業")
            ),
            taxYearProfileRepository: StubTaxYearProfileRepository(),
            preflightReportLoader: { _, _ in
                throw StubError.preflightFailure
            }
        )

        let snapshot = try await useCase.snapshot(fiscalYear: 2025)

        XCTAssertEqual(snapshot.preflightIssues, [StubError.preflightFailure.localizedDescription ?? ""])
    }
}

private struct StubBusinessProfileRepository: BusinessProfileRepository {
    let defaultProfile: BusinessProfile?

    func findById(_ id: UUID) async throws -> BusinessProfile? {
        defaultProfile?.id == id ? defaultProfile : nil
    }

    func findDefault() async throws -> BusinessProfile? {
        defaultProfile
    }

    func save(_ profile: BusinessProfile) async throws {}

    func delete(_ id: UUID) async throws {}
}

private struct StubTaxYearProfileRepository: TaxYearProfileRepository {
    var profiles: [TaxYearProfile] = []

    func findById(_ id: UUID) async throws -> TaxYearProfile? {
        profiles.first(where: { $0.id == id })
    }

    func findByBusinessAndYear(businessId: UUID, taxYear: Int) async throws -> TaxYearProfile? {
        profiles.first(where: { $0.businessId == businessId && $0.taxYear == taxYear })
    }

    func findAllByBusiness(businessId: UUID) async throws -> [TaxYearProfile] {
        profiles.filter { $0.businessId == businessId }
    }

    func save(_ profile: TaxYearProfile) async throws {}

    func delete(_ id: UUID) async throws {}
}

private enum StubError: LocalizedError {
    case unexpectedCall
    case preflightFailure

    var errorDescription: String? {
        switch self {
        case .unexpectedCall:
            return "unexpected call"
        case .preflightFailure:
            return "preflight failure"
        }
    }
}
