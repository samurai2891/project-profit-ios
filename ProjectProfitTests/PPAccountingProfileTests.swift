import SwiftData
import XCTest
@testable import ProjectProfit

final class PPAccountingProfileTests: XCTestCase {

    // MARK: - Init Tests

    func testInitWithDefaults() {
        let profile = PPAccountingProfile(fiscalYear: 2026)

        XCTAssertEqual(profile.id, "profile-default")
        XCTAssertEqual(profile.fiscalYear, 2026)
        XCTAssertEqual(profile.bookkeepingMode, .doubleEntry)
        XCTAssertEqual(profile.businessName, "")
        XCTAssertEqual(profile.ownerName, "")
        XCTAssertNil(profile.taxOfficeCode)
        XCTAssertTrue(profile.isBlueReturn)
        XCTAssertEqual(profile.defaultPaymentAccountId, "acct-cash")
        XCTAssertNil(profile.openingDate)
        XCTAssertNil(profile.lockedAt)
    }

    func testInitWithAllParameters() {
        let now = Date()
        let openingDate = Date(timeIntervalSince1970: 1_600_000_000)

        let profile = PPAccountingProfile(
            id: "profile-default",
            fiscalYear: 2025,
            bookkeepingMode: .singleEntry,
            businessName: "テスト屋号",
            ownerName: "山田太郎",
            taxOfficeCode: "01234",
            isBlueReturn: false,
            defaultPaymentAccountId: "acct-bank",
            openingDate: openingDate,
            lockedAt: now,
            createdAt: now,
            updatedAt: now
        )

        XCTAssertEqual(profile.fiscalYear, 2025)
        XCTAssertEqual(profile.bookkeepingMode, .singleEntry)
        XCTAssertEqual(profile.businessName, "テスト屋号")
        XCTAssertEqual(profile.ownerName, "山田太郎")
        XCTAssertEqual(profile.taxOfficeCode, "01234")
        XCTAssertFalse(profile.isBlueReturn)
        XCTAssertEqual(profile.defaultPaymentAccountId, "acct-bank")
        XCTAssertEqual(profile.openingDate, openingDate)
        XCTAssertEqual(profile.lockedAt, now)
    }

    // MARK: - Computed Properties

    func testIsLockedWhenLockedAtIsNil() {
        let profile = PPAccountingProfile(fiscalYear: 2026)
        XCTAssertFalse(profile.isLocked)
    }

    func testIsLockedWhenLockedAtIsSet() {
        let profile = PPAccountingProfile(fiscalYear: 2026, lockedAt: Date())
        XCTAssertTrue(profile.isLocked)
    }

    // MARK: - BookkeepingMode

    func testBookkeepingModeDoubleEntry() {
        let profile = PPAccountingProfile(fiscalYear: 2026, bookkeepingMode: .doubleEntry)
        XCTAssertEqual(profile.bookkeepingMode, .doubleEntry)
    }

    func testBookkeepingModeSingleEntry() {
        let profile = PPAccountingProfile(fiscalYear: 2026, bookkeepingMode: .singleEntry)
        XCTAssertEqual(profile.bookkeepingMode, .singleEntry)
    }

    // MARK: - SwiftData Persistence Tests

    @MainActor
    func testPersistenceRoundTrip() throws {
        let container = try TestModelContainer.create()
        let context = container.mainContext

        let profile = PPAccountingProfile(
            fiscalYear: 2026,
            businessName: "テスト事業",
            ownerName: "鈴木一郎",
            isBlueReturn: true,
            defaultPaymentAccountId: "acct-cash"
        )
        context.insert(profile)
        try context.save()

        let descriptor = FetchDescriptor<PPAccountingProfile>()
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        let result = fetched[0]
        XCTAssertEqual(result.id, "profile-default")
        XCTAssertEqual(result.fiscalYear, 2026)
        XCTAssertEqual(result.businessName, "テスト事業")
        XCTAssertEqual(result.ownerName, "鈴木一郎")
        XCTAssertTrue(result.isBlueReturn)
        XCTAssertEqual(result.bookkeepingMode, .doubleEntry)
    }

    @MainActor
    func testUniqueIdConstraint() throws {
        let container = try TestModelContainer.create()
        let context = container.mainContext

        let profile1 = PPAccountingProfile(fiscalYear: 2025, businessName: "最初")
        let profile2 = PPAccountingProfile(fiscalYear: 2026, businessName: "重複")

        context.insert(profile1)
        context.insert(profile2)
        try context.save()

        let descriptor = FetchDescriptor<PPAccountingProfile>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1, "同一idのプロファイルは1件のみ保存される")
    }
}
