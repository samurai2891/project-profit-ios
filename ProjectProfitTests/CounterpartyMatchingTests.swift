import XCTest
@testable import ProjectProfit

// MARK: - Mock CounterpartyRepository

final class MockCounterpartyRepository: CounterpartyRepository {
    var counterparties: [Counterparty] = []

    func findById(_ id: UUID) async throws -> Counterparty? {
        counterparties.first { $0.id == id }
    }

    func findByBusiness(businessId: UUID) async throws -> [Counterparty] {
        counterparties.filter { $0.businessId == businessId }
    }

    func findByName(businessId: UUID, query: String) async throws -> [Counterparty] {
        let q = query.lowercased()
        return counterparties.filter {
            $0.businessId == businessId && $0.displayName.lowercased().contains(q)
        }
    }

    func findByDisplayNamePrefix(businessId: UUID, query: String) async throws -> [Counterparty] {
        let q = query.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        return counterparties.filter { cp in
            cp.businessId == businessId
                && cp.displayName
                    .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
                    .contains(q)
        }
        .sorted { lhs, rhs in
            let lf = lhs.displayName.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            let rf = rhs.displayName.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            if lf.hasPrefix(q) && !rf.hasPrefix(q) { return true }
            if !lf.hasPrefix(q) && rf.hasPrefix(q) { return false }
            return lf < rf
        }
    }

    func findByRegistrationNumber(_ number: String) async throws -> Counterparty? { nil }
    func save(_ counterparty: Counterparty) async throws {}
    func delete(_ id: UUID) async throws {}
}

// MARK: - CounterpartyMatchingTests

@MainActor
final class CounterpartyMatchingTests: XCTestCase {
    private var mockRepo: MockCounterpartyRepository!
    private var useCase: CounterpartyMasterUseCase!
    private let businessId = UUID()

    override func setUp() {
        super.setUp()
        mockRepo = MockCounterpartyRepository()
        useCase = CounterpartyMasterUseCase(counterpartyRepository: mockRepo)
    }

    override func tearDown() {
        mockRepo = nil
        useCase = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeCounterparty(displayName: String) -> Counterparty {
        Counterparty(businessId: businessId, displayName: displayName)
    }

    // MARK: - Tests

    /// 完全一致する取引先が存在する場合、その取引先を返す
    func testExactMatch() async throws {
        let cp = makeCounterparty(displayName: "Amazon")
        mockRepo.counterparties = [
            cp,
            makeCounterparty(displayName: "Amazon Web Services"),
            makeCounterparty(displayName: "Amazonas Corp"),
        ]

        let result = try await useCase.suggestCounterparty(
            storeName: "Amazon", businessId: businessId
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, cp.id)
        XCTAssertEqual(result?.displayName, "Amazon")
    }

    /// 完全一致がなく前方一致がある場合、前方一致の取引先を返す
    func testPrefixMatch() async throws {
        let prefixCp = makeCounterparty(displayName: "Amazonas Corp")
        mockRepo.counterparties = [
            prefixCp,
            makeCounterparty(displayName: "Not Amazon"),
        ]

        let result = try await useCase.suggestCounterparty(
            storeName: "Amazo", businessId: businessId
        )

        XCTAssertNotNil(result)
        // 前方一致: "Amazo" は "Amazonas Corp" の前方一致
        XCTAssertEqual(result?.id, prefixCp.id)
    }

    /// 前方一致がなく部分一致がある場合、部分一致の取引先を返す
    func testPartialMatch() async throws {
        let partialCp = makeCounterparty(displayName: "株式会社サクラ商店")
        mockRepo.counterparties = [partialCp]

        let result = try await useCase.suggestCounterparty(
            storeName: "サクラ商店", businessId: businessId
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, partialCp.id)
    }

    /// 空の店名を渡すとnilを返す
    func testEmptyStoreName() async throws {
        mockRepo.counterparties = [
            makeCounterparty(displayName: "SomeStore"),
        ]

        let result = try await useCase.suggestCounterparty(
            storeName: "", businessId: businessId
        )

        XCTAssertNil(result, "空の店名にはnilを返すべき")
    }

    /// 一致する取引先がない場合、nilを返す
    func testNoMatch() async throws {
        mockRepo.counterparties = [
            makeCounterparty(displayName: "Apple"),
            makeCounterparty(displayName: "Google"),
        ]

        let result = try await useCase.suggestCounterparty(
            storeName: "Microsoft", businessId: businessId
        )

        XCTAssertNil(result, "一致する取引先がなければnilを返すべき")
    }
}
