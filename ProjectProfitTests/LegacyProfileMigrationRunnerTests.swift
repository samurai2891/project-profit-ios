import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class LegacyProfileMigrationRunnerTests: XCTestCase {
    private func makeCanonicalContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: PPAccountingProfile.self,
                 BusinessProfileEntity.self,
                 TaxYearProfileEntity.self,
            configurations: config
        )
    }

    private func makeLegacyOnlyContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: PPAccountingProfile.self,
            configurations: config
        )
    }

    func testDryRunWithoutLegacyProfileReturnsNoLegacyProfile() throws {
        let container = try makeCanonicalContainer()
        let runner = LegacyProfileMigrationRunner(modelContext: container.mainContext)

        let report = runner.dryRun()

        XCTAssertEqual(report.outcome, .noLegacyProfile)
        XCTAssertFalse(report.needsMigration)
    }

    func testDryRunWithLegacyProfileReturnsReadyAndDoesNotWrite() throws {
        let container = try makeCanonicalContainer()
        let context = container.mainContext
        context.insert(PPAccountingProfile(fiscalYear: 2025, businessName: "テスト商店", ownerName: "田中太郎"))
        try context.save()

        let runner = LegacyProfileMigrationRunner(modelContext: context)
        let report = runner.dryRun()

        XCTAssertEqual(report.outcome, .dryRunReady)
        XCTAssertTrue(report.createdBusinessProfile)
        XCTAssertTrue(report.createdTaxYearProfile)

        let businesses = try context.fetch(FetchDescriptor<BusinessProfileEntity>())
        let taxYears = try context.fetch(FetchDescriptor<TaxYearProfileEntity>())
        XCTAssertEqual(businesses.count, 0)
        XCTAssertEqual(taxYears.count, 0)
    }

    func testExecuteCreatesCanonicalProfilesAndBecomesIdempotent() throws {
        let container = try makeCanonicalContainer()
        let context = container.mainContext
        let legacy = PPAccountingProfile(
            fiscalYear: 2026,
            bookkeepingMode: .singleEntry,
            businessName: "テスト商店",
            ownerName: "田中太郎",
            taxOfficeCode: "12345",
            isBlueReturn: false,
            defaultPaymentAccountId: "acct-bank",
            openingDate: Date(timeIntervalSince1970: 1_700_000_000),
            lockedYears: [2026]
        )
        legacy.ownerNameKana = "タナカタロウ"
        legacy.postalCode = "1000001"
        legacy.address = "東京都千代田区1-1-1"
        legacy.phoneNumber = "0312345678"
        context.insert(legacy)
        try context.save()

        let runner = LegacyProfileMigrationRunner(modelContext: context)
        let first = runner.execute()
        XCTAssertEqual(first.outcome, .executed)
        XCTAssertTrue(first.createdBusinessProfile)
        XCTAssertTrue(first.createdTaxYearProfile)

        let businesses = try context.fetch(FetchDescriptor<BusinessProfileEntity>())
        let taxYears = try context.fetch(FetchDescriptor<TaxYearProfileEntity>())
        XCTAssertEqual(businesses.count, 1)
        XCTAssertEqual(taxYears.count, 1)

        let business = try XCTUnwrap(businesses.first)
        XCTAssertEqual(business.ownerName, "田中太郎")
        XCTAssertEqual(business.ownerNameKana, "タナカタロウ")
        XCTAssertEqual(business.businessName, "テスト商店")
        XCTAssertEqual(business.defaultPaymentAccountId, "acct-bank")
        XCTAssertEqual(business.postalCode, "1000001")

        let taxYear = try XCTUnwrap(taxYears.first)
        XCTAssertEqual(taxYear.taxYear, 2026)
        XCTAssertEqual(taxYear.filingStyleRaw, FilingStyle.white.rawValue)
        XCTAssertEqual(taxYear.bookkeepingBasisRaw, BookkeepingBasis.singleEntry.rawValue)
        XCTAssertEqual(taxYear.blueDeductionLevelRaw, BlueDeductionLevel.none.rawValue)
        XCTAssertEqual(taxYear.yearLockStateRaw, YearLockState.finalLock.rawValue)

        let second = runner.executeIfNeeded()
        XCTAssertEqual(second.outcome, .alreadyMigrated)
    }

    func testExecuteIfNeededDoesNotOverwriteExistingCanonicalProfiles() throws {
        let container = try makeCanonicalContainer()
        let context = container.mainContext

        let legacy = PPAccountingProfile(
            fiscalYear: 2026,
            bookkeepingMode: .singleEntry,
            businessName: "Legacy商店",
            ownerName: "Legacy Owner",
            isBlueReturn: false
        )
        context.insert(legacy)

        let businessId = UUID()
        let canonicalBusiness = BusinessProfileEntity(
            businessId: businessId,
            ownerName: "Canonical Owner",
            ownerNameKana: "カノニカル",
            businessName: "Canonical商店",
            businessAddress: "東京都港区1-1-1",
            postalCode: "1070001",
            phoneNumber: "0311111111",
            taxOfficeCode: "9999"
        )
        let canonicalTaxYear = TaxYearProfileEntity(
            businessId: businessId,
            taxYear: 2026,
            filingStyleRaw: FilingStyle.blueGeneral.rawValue,
            blueDeductionLevelRaw: BlueDeductionLevel.sixtyFive.rawValue,
            bookkeepingBasisRaw: BookkeepingBasis.doubleEntry.rawValue,
            yearLockStateRaw: YearLockState.softClose.rawValue,
            taxPackVersion: "2026-v1"
        )
        context.insert(canonicalBusiness)
        context.insert(canonicalTaxYear)
        try context.save()

        let runner = LegacyProfileMigrationRunner(modelContext: context)
        let report = runner.executeIfNeeded()

        XCTAssertEqual(report.outcome, .alreadyMigrated)

        let businesses = try context.fetch(FetchDescriptor<BusinessProfileEntity>())
        let taxYears = try context.fetch(FetchDescriptor<TaxYearProfileEntity>())
        XCTAssertEqual(businesses.first?.ownerName, "Canonical Owner")
        XCTAssertEqual(businesses.first?.businessName, "Canonical商店")
        XCTAssertEqual(taxYears.first?.filingStyleRaw, FilingStyle.blueGeneral.rawValue)
        XCTAssertEqual(taxYears.first?.yearLockStateRaw, YearLockState.softClose.rawValue)
    }

    func testExecuteMapsLockedYearsToCanonicalStateAndKeepsLegacyProfile() throws {
        let container = try makeCanonicalContainer()
        let context = container.mainContext
        let legacyId = "legacy-compat-profile"
        let legacy = PPAccountingProfile(
            id: legacyId,
            fiscalYear: 2027,
            bookkeepingMode: .doubleEntry,
            businessName: "Legacy商店",
            ownerName: "Legacy Owner",
            isBlueReturn: true,
            lockedYears: [2027]
        )
        context.insert(legacy)
        try context.save()

        let runner = LegacyProfileMigrationRunner(modelContext: context)
        let report = runner.execute()

        XCTAssertEqual(report.outcome, .executed)

        let taxYears = try context.fetch(FetchDescriptor<TaxYearProfileEntity>())
        let migratedTaxYear = try XCTUnwrap(taxYears.first(where: { $0.taxYear == 2027 }))
        XCTAssertEqual(migratedTaxYear.yearLockStateRaw, YearLockState.finalLock.rawValue)

        let legacyProfiles = try context.fetch(FetchDescriptor<PPAccountingProfile>())
        let preservedLegacy = try XCTUnwrap(legacyProfiles.first(where: { $0.id == legacyId }))
        XCTAssertEqual(preservedLegacy.lockedYears ?? [], [2027])
        XCTAssertEqual(preservedLegacy.fiscalYear, 2027)
    }

    func testLegacyOnlyContainerDoesNotReturnDryRunReadyOrCrash() throws {
        let container = try makeLegacyOnlyContainer()
        let context = container.mainContext
        context.insert(PPAccountingProfile(fiscalYear: 2025, businessName: "Legacy", ownerName: "User"))
        try context.save()

        let runner = LegacyProfileMigrationRunner(modelContext: context)
        let report = runner.executeIfNeeded()

        XCTAssertTrue(
            [.executed, .alreadyMigrated, .schemaUnavailable, .failed].contains(report.outcome)
        )
    }

    func testDataStoreLoadDataRemainsSafeWithLegacyOnlyContainer() throws {
        let container = try TestModelContainer.create()
        let store = DataStore(modelContext: container.mainContext)

        store.loadData()

        XCTAssertFalse(store.isLoading)
        // After loadData, canonical businessProfile should be populated
        // (bootstrap creates legacy profile which auto-migrates)
        XCTAssertNotNil(store.businessProfile)
    }

    func testReloadProfileSettingsMigratesLegacyProfileWithoutPriorLoadData() async throws {
        let container = try TestModelContainer.create()
        let context = container.mainContext
        let legacy = PPAccountingProfile(
            fiscalYear: 2026,
            bookkeepingMode: .singleEntry,
            businessName: "Legacy商店",
            ownerName: "Legacy User",
            taxOfficeCode: "4321",
            isBlueReturn: false,
            defaultPaymentAccountId: "acct-bank"
        )
        context.insert(legacy)
        try context.save()

        let store = DataStore(modelContext: context)
        let didReload = await store.reloadProfileSettings()

        XCTAssertTrue(didReload)
        XCTAssertEqual(store.businessProfile?.businessName, "Legacy商店")
        XCTAssertEqual(store.businessProfile?.ownerName, "Legacy User")
        XCTAssertEqual(store.currentTaxYearProfile?.taxYear, 2026)
        XCTAssertEqual(store.currentTaxYearProfile?.filingStyle, .white)
    }
}
