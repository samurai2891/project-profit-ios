import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ProfileSettingsWorkflowUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: ProfileSettingsWorkflowUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        useCase = ProfileSettingsWorkflowUseCase(dataStore: dataStore)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FiscalYearSettings.userDefaultsKey)
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testLoadProfileMigratesLegacyProfileAndUpdatesDataStoreCache() async throws {
        let legacy = PPAccountingProfile(
            fiscalYear: 2025,
            bookkeepingMode: .singleEntry,
            businessName: "テスト商店",
            ownerName: "田中太郎",
            taxOfficeCode: "1234",
            isBlueReturn: false,
            defaultPaymentAccountId: "acct-bank"
        )
        context.insert(legacy)
        try context.save()

        let didLoad = await useCase.loadProfile(defaultTaxYear: 2025)

        XCTAssertTrue(didLoad)
        XCTAssertEqual(dataStore.businessProfile?.businessName, "テスト商店")
        XCTAssertEqual(dataStore.businessProfile?.defaultPaymentAccountId, "acct-bank")
        XCTAssertEqual(dataStore.currentTaxYearProfile?.taxYear, 2025)
        XCTAssertEqual(dataStore.currentTaxYearProfile?.bookkeepingBasis, .singleEntry)
        XCTAssertNil(dataStore.lastError)
    }

    func testSaveProfilePersistsSensitivePayloadAndUpdatesDataStoreState() async throws {
        let didLoad = await useCase.loadProfile(defaultTaxYear: 2026)
        XCTAssertTrue(didLoad)
        let payload = ProfileSensitivePayload.fromLegacyProfile(
            ownerNameKana: "ヤマダタロウ",
            postalCode: "1500001",
            address: "東京都渋谷区1-2-3",
            phoneNumber: "09012345678",
            dateOfBirth: nil,
            businessCategory: "デザイン",
            myNumberFlag: true,
            includeSensitiveInExport: true
        )
        let command = SaveProfileSettingsCommand(
            ownerName: "山田太郎",
            ownerNameKana: "ヤマダタロウ",
            businessName: "山田デザイン",
            businessAddress: "東京都渋谷区1-2-3",
            postalCode: "1500001",
            phoneNumber: "09012345678",
            openingDate: Date(timeIntervalSince1970: 1_700_000_000),
            taxOfficeCode: "5678",
            filingStyle: .blueGeneral,
            blueDeductionLevel: .sixtyFive,
            bookkeepingBasis: .doubleEntry,
            vatStatus: .taxable,
            vatMethod: .simplified,
            simplifiedBusinessCategory: 3,
            invoiceIssuerStatusAtYear: .registered,
            electronicBookLevel: .superior,
            yearLockState: .softClose,
            taxYear: 2026
        )

        let result = await useCase.saveProfile(command: command, sensitivePayload: payload)

        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("saveProfile should succeed: \(error.localizedDescription)")
        }

        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        defer { _ = ProfileSecureStore.delete(profileId: businessId.uuidString) }

        XCTAssertEqual(dataStore.businessProfile?.ownerName, "山田太郎")
        XCTAssertEqual(dataStore.businessProfile?.businessName, "山田デザイン")
        XCTAssertEqual(dataStore.currentTaxYearProfile?.vatMethod, .simplified)
        XCTAssertEqual(dataStore.currentTaxYearProfile?.yearLockState, .softClose)
        XCTAssertEqual(dataStore.profileSensitivePayload?.postalCode, "1500001")
        XCTAssertEqual(ProfileSecureStore.load(profileId: businessId.uuidString)?.businessCategory, "デザイン")
        XCTAssertNil(dataStore.lastError)
    }

    func testLoadProfileUsesCalendarYearWhenDefaultTaxYearAndCurrentTaxYearProfileAreMissing() async throws {
        UserDefaults.standard.set(4, forKey: FiscalYearSettings.userDefaultsKey)
        useCase = ProfileSettingsWorkflowUseCase(
            dataStore: dataStore,
            currentDateProvider: { Self.makeDate(year: 2026, month: 3, day: 11) }
        )

        let didLoad = await useCase.loadProfile()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(dataStore.currentTaxYearProfile?.taxYear, 2026)
        XCTAssertNil(dataStore.lastError)
    }

    func testLoadProfileUsesCurrentTaxYearProfileWhenDefaultTaxYearIsMissing() async throws {
        let initialLoad = await useCase.loadProfile(defaultTaxYear: 2031)
        XCTAssertTrue(initialLoad)

        let didLoad = await useCase.loadProfile()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(dataStore.currentTaxYearProfile?.taxYear, 2031)
        XCTAssertNil(dataStore.lastError)
    }

    func testLoadProfilePrefersExplicitDefaultTaxYearOverCurrentTaxYearProfile() async throws {
        let initialLoad = await useCase.loadProfile(defaultTaxYear: 2031)
        XCTAssertTrue(initialLoad)

        let didLoad = await useCase.loadProfile(defaultTaxYear: 2042)

        XCTAssertTrue(didLoad)
        XCTAssertEqual(dataStore.currentTaxYearProfile?.taxYear, 2042)
        XCTAssertNil(dataStore.lastError)
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date {
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: year,
            month: month,
            day: day
        )
        return components.date!
    }
}
