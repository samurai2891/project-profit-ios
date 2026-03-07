import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ProfileSettingsUseCaseTests: XCTestCase {
    func testLoadMigratesLegacyProfileIntoCanonicalRepositories() async throws {
        let container = try TestModelContainer.create()
        let context = container.mainContext
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

        let useCase = ProfileSettingsUseCase(modelContext: context)
        let payload = ProfileSensitivePayload.fromLegacyProfile(
            ownerNameKana: "タナカタロウ",
            postalCode: "1000001",
            address: "東京都千代田区1-1-1",
            phoneNumber: "0312345678",
            dateOfBirth: nil,
            businessCategory: nil,
            myNumberFlag: nil
        )

        let state = try await useCase.load(
            defaultTaxYear: 2025,
            legacyProfile: legacy,
            sensitivePayload: payload
        )

        XCTAssertEqual(state.businessProfile.businessName, "テスト商店")
        XCTAssertEqual(state.businessProfile.ownerNameKana, "タナカタロウ")
        XCTAssertEqual(state.businessProfile.postalCode, "1000001")
        XCTAssertEqual(state.businessProfile.defaultPaymentAccountId, "acct-bank")
        XCTAssertEqual(state.taxYearProfile.taxYear, 2025)
        XCTAssertEqual(state.taxYearProfile.filingStyle, .white)
        XCTAssertEqual(state.taxYearProfile.bookkeepingBasis, .singleEntry)

        let businesses = try context.fetch(FetchDescriptor<BusinessProfileEntity>())
        let taxYears = try context.fetch(FetchDescriptor<TaxYearProfileEntity>())
        XCTAssertEqual(businesses.count, 1)
        XCTAssertEqual(businesses.first?.defaultPaymentAccountId, "acct-bank")
        XCTAssertEqual(taxYears.count, 1)
    }

    func testSavePersistsUpdatedBusinessAndTaxYearProfiles() async throws {
        let container = try TestModelContainer.create()
        let context = container.mainContext
        let useCase = ProfileSettingsUseCase(modelContext: context)

        let initial = try await useCase.load(
            defaultTaxYear: 2026,
            legacyProfile: nil,
            sensitivePayload: nil
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

        let saved = try await useCase.save(
            command: command,
            currentState: initial
        )

        XCTAssertEqual(saved.businessProfile.ownerName, "山田太郎")
        XCTAssertEqual(saved.businessProfile.businessAddress, "東京都渋谷区1-2-3")
        XCTAssertEqual(saved.taxYearProfile.vatStatus, .taxable)
        XCTAssertEqual(saved.taxYearProfile.vatMethod, .simplified)
        XCTAssertEqual(saved.taxYearProfile.yearLockState, .softClose)
        XCTAssertEqual(saved.taxYearProfile.taxPackVersion, "2026-v1")

        let businesses = try context.fetch(FetchDescriptor<BusinessProfileEntity>())
        let taxYears = try context.fetch(FetchDescriptor<TaxYearProfileEntity>())
        XCTAssertEqual(businesses.first?.taxOfficeCode, "5678")
        XCTAssertEqual(taxYears.first?.simplifiedBusinessCategory, 3)
        XCTAssertEqual(taxYears.first?.invoiceIssuerStatusAtYearRaw, InvoiceIssuerStatus.registered.rawValue)
    }

    func testSaveRejectsInvalidVatTransitionWhenInvoiceStatusIsRegistered() async throws {
        let container = try TestModelContainer.create()
        let context = container.mainContext
        let useCase = ProfileSettingsUseCase(modelContext: context)

        let initial = try await useCase.load(
            defaultTaxYear: 2026,
            legacyProfile: nil,
            sensitivePayload: nil
        )
        let existingTaxProfile = initial.taxYearProfile.updated(
            vatStatus: .taxable,
            invoiceIssuerStatusAtYear: .registered
        )
        try context.fetch(FetchDescriptor<TaxYearProfileEntity>()).forEach(context.delete)
        context.insert(TaxYearProfileEntityMapper.toEntity(existingTaxProfile))
        try context.save()

        let state = ProfileSettingsState(
            businessProfile: initial.businessProfile,
            taxYearProfile: existingTaxProfile
        )
        let command = SaveProfileSettingsCommand(
            ownerName: "山田太郎",
            ownerNameKana: "ヤマダタロウ",
            businessName: "山田デザイン",
            businessAddress: "東京都渋谷区1-2-3",
            postalCode: "1500001",
            phoneNumber: "09012345678",
            openingDate: nil,
            taxOfficeCode: "5678",
            filingStyle: .blueGeneral,
            blueDeductionLevel: .sixtyFive,
            bookkeepingBasis: .doubleEntry,
            vatStatus: .exempt,
            vatMethod: .general,
            simplifiedBusinessCategory: nil,
            invoiceIssuerStatusAtYear: .registered,
            electronicBookLevel: .none,
            yearLockState: .open,
            taxYear: 2026
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await useCase.save(command: command, currentState: state)
        } errorHandler: { error in
            XCTAssertEqual(
                error as? ProfileSettingsUseCaseError,
                .validationFailed("インボイス登録状態では消費税区分を課税事業者から免税事業者へ変更できません")
            )
        }
    }

    func testSaveRejectsInvalidYearLockJump() async throws {
        let container = try TestModelContainer.create()
        let context = container.mainContext
        let useCase = ProfileSettingsUseCase(modelContext: context)

        let initial = try await useCase.load(
            defaultTaxYear: 2026,
            legacyProfile: nil,
            sensitivePayload: nil
        )
        let command = SaveProfileSettingsCommand(
            ownerName: initial.businessProfile.ownerName,
            ownerNameKana: initial.businessProfile.ownerNameKana,
            businessName: initial.businessProfile.businessName,
            businessAddress: initial.businessProfile.businessAddress,
            postalCode: initial.businessProfile.postalCode,
            phoneNumber: initial.businessProfile.phoneNumber,
            openingDate: initial.businessProfile.openingDate,
            taxOfficeCode: initial.businessProfile.taxOfficeCode,
            filingStyle: initial.taxYearProfile.filingStyle,
            blueDeductionLevel: initial.taxYearProfile.blueDeductionLevel,
            bookkeepingBasis: initial.taxYearProfile.bookkeepingBasis,
            vatStatus: initial.taxYearProfile.vatStatus,
            vatMethod: initial.taxYearProfile.vatMethod,
            simplifiedBusinessCategory: initial.taxYearProfile.simplifiedBusinessCategory,
            invoiceIssuerStatusAtYear: initial.taxYearProfile.invoiceIssuerStatusAtYear,
            electronicBookLevel: initial.taxYearProfile.electronicBookLevel,
            yearLockState: .finalLock,
            taxYear: 2026
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await useCase.save(command: command, currentState: initial)
        } errorHandler: { error in
            XCTAssertEqual(
                error as? ProfileSettingsUseCaseError,
                .validationFailed("年度状態を未締めから最終確定へ変更できません")
            )
        }
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line,
    errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
