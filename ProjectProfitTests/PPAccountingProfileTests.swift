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

    // MARK: - Migration Compat Tests

    func testLegacySnapshotConvertsToCanonicalBusinessProfile() {
        let profile = PPAccountingProfile(
            fiscalYear: 2026,
            businessName: "テスト事業",
            ownerName: "鈴木一郎",
            isBlueReturn: true,
            defaultPaymentAccountId: "acct-cash"
        )
        profile.ownerNameKana = "スズキイチロウ"
        profile.postalCode = "1000001"
        profile.address = "東京都千代田区1-1-1"
        profile.phoneNumber = "0312345678"

        let snapshot = LegacyAccountingProfileSnapshot(profile)
        let businessProfile = snapshot.toBusinessProfile(
            existingId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            sensitivePayload: nil
        )

        XCTAssertEqual(businessProfile.id.uuidString, "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        XCTAssertEqual(businessProfile.ownerName, "鈴木一郎")
        XCTAssertEqual(businessProfile.ownerNameKana, "スズキイチロウ")
        XCTAssertEqual(businessProfile.businessName, "テスト事業")
        XCTAssertEqual(businessProfile.postalCode, "1000001")
    }

    func testLegacySnapshotConvertsToCanonicalTaxYearProfile() {
        let lockedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let profile = PPAccountingProfile(
            fiscalYear: 2025,
            bookkeepingMode: .singleEntry,
            businessName: "テスト事業",
            ownerName: "鈴木一郎",
            isBlueReturn: true,
            lockedAt: lockedAt
        )
        let snapshot = LegacyAccountingProfileSnapshot(profile)
        let taxYearProfile = snapshot.toTaxYearProfile(
            businessId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )

        XCTAssertEqual(taxYearProfile.taxYear, 2025)
        XCTAssertEqual(taxYearProfile.filingStyle, .blueGeneral)
        XCTAssertEqual(taxYearProfile.bookkeepingBasis, .singleEntry)
        XCTAssertEqual(taxYearProfile.blueDeductionLevel, .ten)
        XCTAssertEqual(taxYearProfile.yearLockState, .finalLock)
    }
}
