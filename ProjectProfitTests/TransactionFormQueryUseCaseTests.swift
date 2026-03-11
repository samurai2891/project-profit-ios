import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class TransactionFormQueryUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        FeatureFlags.clearOverrides()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
    }

    override func tearDown() {
        FeatureFlags.clearOverrides()
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testSnapshotMatchesCurrentFormDataOrderingAndDefaults() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let laterProject = PPProject(
            name: "後発案件",
            createdAt: date(2025, 2, 1),
            updatedAt: date(2025, 2, 1)
        )
        let earlierProject = PPProject(
            name: "先発案件",
            createdAt: date(2025, 1, 1),
            updatedAt: date(2025, 1, 1)
        )
        context.insert(earlierProject)
        context.insert(laterProject)
        try context.save()

        let counterparty = Counterparty(
            businessId: businessId,
            displayName: "テスト商店"
        )
        try await CounterpartyMasterUseCase(modelContext: context).save(counterparty)

        let snapshot = try TransactionFormQueryUseCase(modelContext: context).snapshot()

        XCTAssertEqual(snapshot.businessId, businessId)
        XCTAssertEqual(snapshot.defaultPaymentAccountId, dataStore.defaultPaymentAccountPreference)
        XCTAssertEqual(snapshot.projects.map(\.name).prefix(2), ["後発案件", "先発案件"])
        XCTAssertTrue(snapshot.accounts.contains(where: { $0.id == "acct-cash" }))
        XCTAssertTrue(snapshot.activeCategories.contains(where: { $0.id == "cat-tools" }))
        XCTAssertEqual(snapshot.counterparties.map(\.displayName), ["テスト商店"])
    }

    func testCategoriesAndPaymentAccountsFollowCurrentFormRules() throws {
        let useCase = TransactionFormQueryUseCase(modelContext: context)
        let snapshot = try useCase.snapshot()

        let expenseCategories = useCase.categories(for: .expense, snapshot: snapshot)
        let incomeCategories = useCase.categories(for: .income, snapshot: snapshot)
        let paymentAccounts = useCase.paymentAccounts(snapshot: snapshot)

        XCTAssertTrue(expenseCategories.allSatisfy { $0.type == .expense })
        XCTAssertTrue(incomeCategories.allSatisfy { $0.type == .income })
        XCTAssertTrue(paymentAccounts.allSatisfy { $0.isPaymentAccount && $0.isActive })
    }

    func testCounterpartyDefaultsResolveLegacyAccountTaxCodeAndActiveProject() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let project = PPProject(name: "割当先案件")
        context.insert(project)
        try context.save()

        let canonicalAccountId = UUID()
        try await SwiftDataChartOfAccountsRepository(modelContext: context).save(
            CanonicalAccount(
                id: canonicalAccountId,
                businessId: businessId,
                legacyAccountId: "acct-bank",
                code: "102",
                name: "普通預金",
                accountType: .asset,
                normalBalance: .debit,
                defaultLegalReportLineId: LegalReportLine.deposits.rawValue
            )
        )

        let counterparty = Counterparty(
            businessId: businessId,
            displayName: "得意先A",
            defaultAccountId: canonicalAccountId,
            defaultTaxCodeId: TaxCode.standard10.rawValue,
            defaultProjectId: project.id
        )
        try await CounterpartyMasterUseCase(modelContext: context).save(counterparty)

        let useCase = TransactionFormQueryUseCase(modelContext: context)
        let snapshot = try useCase.snapshot()
        let defaults = try XCTUnwrap(
            useCase.counterpartyDefaults(
                for: counterparty.id,
                type: .expense,
                snapshot: snapshot
            )
        )
        let transferDefaults = try XCTUnwrap(
            useCase.counterpartyDefaults(
                for: counterparty.id,
                type: .transfer,
                snapshot: snapshot
            )
        )

        XCTAssertEqual(defaults.displayName, "得意先A")
        XCTAssertEqual(defaults.taxCode, .standard10)
        XCTAssertEqual(defaults.paymentAccountId, "acct-bank")
        XCTAssertEqual(defaults.projectId, project.id)
        XCTAssertNil(transferDefaults.projectId)
    }

    func testActiveDistributionTemplatesFilterUnsupportedRulesAndPreviewProjects() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let projectA = PPProject(name: "A案件")
        let projectB = PPProject(name: "B案件")
        context.insert(projectA)
        context.insert(projectB)
        try context.save()

        let distributionUseCase = DistributionTemplateUseCase(modelContext: context)
        try await distributionUseCase.save(
            DistributionRule(
                businessId: businessId,
                name: "均等配賦",
                scope: .allProjects,
                basis: .equal,
                effectiveFrom: date(2025, 1, 1)
            )
        )
        try await distributionUseCase.save(
            DistributionRule(
                businessId: businessId,
                name: "未対応",
                scope: .projectsByTag,
                basis: .equal,
                effectiveFrom: date(2025, 1, 1)
            )
        )

        let useCase = TransactionFormQueryUseCase(modelContext: context)
        let templates = try await useCase.activeDistributionTemplates(
            businessId: businessId,
            at: date(2025, 3, 11)
        )
        let snapshot = try useCase.snapshot()
        let preview = useCase.previewDistribution(
            rule: try XCTUnwrap(templates.supportedRules.first),
            snapshot: snapshot,
            referenceDate: date(2025, 3, 11),
            totalAmount: 1_000
        )

        XCTAssertEqual(templates.supportedRules.map(\.name), ["均等配賦"])
        XCTAssertEqual(templates.unsupportedCount, 1)
        XCTAssertEqual(Set(preview.allocations.map(\.projectId)), Set([projectA.id, projectB.id]))
        XCTAssertEqual(preview.totalAllocatedAmount, 1_000)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }
}
