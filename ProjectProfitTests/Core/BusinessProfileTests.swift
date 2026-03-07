import XCTest
@testable import ProjectProfit

final class BusinessProfileTests: XCTestCase {

    func testCreationWithDefaults() {
        let profile = BusinessProfile(ownerName: "田中太郎")
        XCTAssertEqual(profile.ownerName, "田中太郎")
        XCTAssertEqual(profile.defaultCurrency, "JPY")
        XCTAssertEqual(profile.invoiceIssuerStatus, .unknown)
        XCTAssertEqual(profile.ownerNameKana, "")
        XCTAssertEqual(profile.defaultPaymentAccountId, AccountingConstants.defaultPaymentAccountId)
    }

    func testCreationWithAllFields() {
        let profile = BusinessProfile(
            ownerName: "田中太郎",
            ownerNameKana: "タナカタロウ",
            businessName: "田中ソフトウェア開発",
            businessAddress: "東京都渋谷区1-2-3",
            postalCode: "1500001",
            phoneNumber: "03-1234-5678",
            taxOfficeCode: "01234",
            invoiceRegistrationNumber: "T1234567890123",
            invoiceIssuerStatus: .registered
        )
        XCTAssertEqual(profile.businessName, "田中ソフトウェア開発")
        XCTAssertEqual(profile.invoiceIssuerStatus, .registered)
        XCTAssertEqual(profile.invoiceRegistrationNumber, "T1234567890123")
    }

    func testImmutableUpdate() {
        let original = BusinessProfile(
            ownerName: "田中太郎",
            businessName: "旧社名"
        )

        let updated = original.updated(
            businessName: "新社名",
            invoiceIssuerStatus: .registered
        )

        // 元のオブジェクトは変更されない
        XCTAssertEqual(original.businessName, "旧社名")
        XCTAssertEqual(original.invoiceIssuerStatus, .unknown)

        // 新しいオブジェクトに変更が反映
        XCTAssertEqual(updated.businessName, "新社名")
        XCTAssertEqual(updated.invoiceIssuerStatus, .registered)

        // IDは同一
        XCTAssertEqual(original.id, updated.id)
        // ownerName は変更されていない
        XCTAssertEqual(updated.ownerName, "田中太郎")
        XCTAssertEqual(updated.defaultPaymentAccountId, AccountingConstants.defaultPaymentAccountId)
    }

    func testInvoiceIssuerStatusTransitions() {
        let profile = BusinessProfile(
            ownerName: "田中太郎",
            invoiceIssuerStatus: .unregistered
        )
        XCTAssertEqual(profile.invoiceIssuerStatus, .unregistered)

        let registered = profile.updated(invoiceIssuerStatus: .registered)
        XCTAssertEqual(registered.invoiceIssuerStatus, .registered)
    }
}
