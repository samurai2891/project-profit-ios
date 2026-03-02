import XCTest
@testable import ProjectProfit

/// ゴールデンテスト: リファクタリング前後で帳簿・帳票の出力が一致することを検証
final class GoldenBaselineTests: XCTestCase {

    private func loadFixture() throws -> GoldenFixture {
        let url = Bundle(for: type(of: self)).url(
            forResource: "baseline_fiscal_year_2025",
            withExtension: "json",
            subdirectory: "Golden/fixtures"
        )!
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(GoldenFixture.self, from: data)
    }

    func testFixtureLoads() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.businessProfile.fiscalYear, 2025)
        XCTAssertEqual(fixture.projects.count, 3)
        XCTAssertGreaterThanOrEqual(fixture.transactions.count, 12)
        XCTAssertGreaterThanOrEqual(fixture.categories.count, 5)
    }

    // MARK: - リファクタリング完了後に有効化するテスト

    func testJournalBookMatchesExpected() throws {
        // let fixture = try loadFixture()
        // TODO: BookEngine 完成後に実装
    }

    func testTrialBalanceMatchesExpected() throws {
        // let fixture = try loadFixture()
        // TODO: BookEngine 完成後に実装
    }

    func testBlueReturnMatchesExpected() throws {
        // let fixture = try loadFixture()
        // TODO: FormEngine 完成後に実装
    }

    func testConsumptionTaxWorksheetMatchesExpected() throws {
        // let fixture = try loadFixture()
        // TODO: ConsumptionTaxEngine 完成後に実装
    }
}

// MARK: - Golden Fixture Data Structures

struct GoldenFixture: Codable {
    let businessProfile: GoldenBusinessProfile
    let projects: [GoldenProject]
    let transactions: [GoldenTransaction]
    let categories: [GoldenCategory]
    let accounts: [GoldenAccount]
}

struct GoldenBusinessProfile: Codable {
    let businessName: String
    let ownerName: String
    let ownerNameKana: String
    let fiscalYear: Int
    let isBlueReturn: Bool
    let bookkeepingMode: String
    let address: String
    let postalCode: String
    let phoneNumber: String
    let taxOfficeCode: String
}

struct GoldenProject: Codable {
    let id: String
    let name: String
    let status: String
    let startDate: String?
    let completedAt: String?
}

struct GoldenTransaction: Codable {
    let id: String
    let type: String
    let amount: Int
    let date: String
    let categoryId: String
    let memo: String
    let taxRate: Int?
    let isTaxIncluded: Bool?
    let counterparty: String?
    let allocations: [GoldenAllocation]?
}

struct GoldenAllocation: Codable {
    let projectId: String
    let ratio: Int
    let amount: Int
}

struct GoldenCategory: Codable {
    let id: String
    let name: String
    let type: String
}

struct GoldenAccount: Codable {
    let id: String
    let code: String
    let name: String
    let accountType: String
}
