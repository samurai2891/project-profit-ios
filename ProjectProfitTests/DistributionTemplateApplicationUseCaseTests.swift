import XCTest
@testable import ProjectProfit

final class DistributionTemplateApplicationUseCaseTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testDistributionRuleBuilderSelectedProjectsEqualStoresUnitWeights() throws {
        let projectA = UUID()
        let projectB = UUID()
        let effectiveFrom = calendar.date(from: DateComponents(year: 2026, month: 1, day: 6))!

        let rule = try DistributionRuleBuilder().build(
            businessId: UUID(),
            name: "共通費テンプレート",
            scope: .selectedProjects,
            basis: .equal,
            roundingPolicy: .lastProjectAdjust,
            effectiveFrom: effectiveFrom,
            effectiveTo: nil,
            selectedProjectIds: [projectA, projectB],
            weightTexts: [:]
        )

        XCTAssertEqual(Set(rule.weights.map(\.projectId)), [projectA, projectB])
        XCTAssertTrue(rule.weights.allSatisfy { $0.weight == 1 })
    }

    func testDistributionRuleBuilderRejectsFixedWeightWithoutSelectedProjectScope() {
        let effectiveFrom = calendar.date(from: DateComponents(year: 2026, month: 1, day: 6))!

        XCTAssertThrowsError(
            try DistributionRuleBuilder().build(
                businessId: UUID(),
                name: "固定重み",
                scope: .allProjects,
                basis: .fixedWeight,
                roundingPolicy: .lastProjectAdjust,
                effectiveFrom: effectiveFrom,
                effectiveTo: nil,
                selectedProjectIds: [],
                weightTexts: [:]
            )
        ) { error in
            XCTAssertEqual(
                error as? DistributionRuleBuilder.ValidationError,
                .fixedWeightRequiresSelectedProjects
            )
        }
    }

    func testApplicationUseCaseEqualSelectedProjectsRatiosSumTo100() throws {
        let projectA = PPProject(name: "Alpha")
        let projectB = PPProject(name: "Beta")
        let projectC = PPProject(name: "Gamma")
        let effectiveFrom = calendar.date(from: DateComponents(year: 2026, month: 1, day: 6))!
        let rule = try DistributionRuleBuilder().build(
            businessId: UUID(),
            name: "均等割",
            scope: .selectedProjects,
            basis: .equal,
            roundingPolicy: .lastProjectAdjust,
            effectiveFrom: effectiveFrom,
            effectiveTo: nil,
            selectedProjectIds: [projectA.id, projectB.id, projectC.id],
            weightTexts: [:]
        )

        let ratios = try DistributionTemplateApplicationUseCase().buildRatioAllocations(
            rule: rule,
            projects: [projectA, projectB, projectC],
            referenceDate: effectiveFrom
        )

        XCTAssertEqual(ratios.count, 3)
        XCTAssertEqual(ratios.map(\.ratio).reduce(0, +), 100)
        XCTAssertEqual(Set(ratios.map(\.projectId)), [projectA.id, projectB.id, projectC.id])
    }

    func testApplicationUseCaseAllActiveProjectsInMonthFiltersInactiveProjects() throws {
        let januaryReference = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let active = PPProject(name: "Active")
        let startedLater = PPProject(
            name: "Later",
            startDate: calendar.date(from: DateComponents(year: 2026, month: 2, day: 14))
        )
        let completedBefore = PPProject(
            name: "Done",
            status: .completed,
            completedAt: calendar.date(from: DateComponents(year: 2025, month: 12, day: 31))
        )
        let archived = PPProject(name: "Archived", isArchived: true)
        let rule = DistributionRule(
            businessId: UUID(),
            name: "当月アクティブ",
            scope: .allActiveProjectsInMonth,
            basis: .equal,
            roundingPolicy: .lastProjectAdjust,
            effectiveFrom: januaryReference
        )

        let ratios = try DistributionTemplateApplicationUseCase().buildRatioAllocations(
            rule: rule,
            projects: [active, startedLater, completedBefore, archived],
            referenceDate: januaryReference
        )

        XCTAssertEqual(ratios.count, 1)
        XCTAssertEqual(ratios.first?.projectId, active.id)
        XCTAssertEqual(ratios.first?.ratio, 100)
    }

    func testApplicationUseCaseFixedWeightUsesConfiguredWeights() throws {
        let projectA = PPProject(name: "Alpha")
        let projectB = PPProject(name: "Beta")
        let effectiveFrom = calendar.date(from: DateComponents(year: 2026, month: 1, day: 6))!
        let rule = DistributionRule(
            businessId: UUID(),
            name: "固定重み",
            scope: .selectedProjects,
            basis: .fixedWeight,
            weights: [
                DistributionWeight(projectId: projectA.id, weight: 70),
                DistributionWeight(projectId: projectB.id, weight: 30)
            ],
            roundingPolicy: .largestWeightAdjust,
            effectiveFrom: effectiveFrom
        )

        let ratios = try DistributionTemplateApplicationUseCase().buildRatioAllocations(
            rule: rule,
            projects: [projectA, projectB],
            referenceDate: effectiveFrom
        )

        XCTAssertEqual(ratios.map(\.ratio).reduce(0, +), 100)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: ratios.map { ($0.projectId, $0.ratio) })[projectA.id], 70)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: ratios.map { ($0.projectId, $0.ratio) })[projectB.id], 30)
    }

    func testApplicationUseCaseActiveDaysUsesMonthlyActiveDayWeights() throws {
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let projectA = PPProject(name: "Alpha")
        let projectB = PPProject(
            name: "Beta",
            startDate: calendar.date(from: DateComponents(year: 2026, month: 4, day: 21))
        )
        let rule = try DistributionRuleBuilder().build(
            businessId: UUID(),
            name: "稼働日数",
            scope: .selectedProjects,
            basis: .activeDays,
            roundingPolicy: .lastProjectAdjust,
            effectiveFrom: referenceDate,
            effectiveTo: nil,
            selectedProjectIds: [projectA.id, projectB.id],
            weightTexts: [:]
        )

        let ratios = try DistributionTemplateApplicationUseCase().buildRatioAllocations(
            rule: rule,
            projects: [projectA, projectB],
            referenceDate: referenceDate,
            allocationPeriod: .month
        )

        XCTAssertEqual(Dictionary(uniqueKeysWithValues: ratios.map { ($0.projectId, $0.ratio) })[projectA.id], 75)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: ratios.map { ($0.projectId, $0.ratio) })[projectB.id], 25)
        XCTAssertEqual(ratios.map(\.ratio).reduce(0, +), 100)
    }

    func testApplicationUseCaseActiveDaysDropsProjectsWithZeroActiveDays() throws {
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let active = PPProject(name: "Alpha")
        let completedBeforeMonth = PPProject(
            name: "Beta",
            status: .completed,
            completedAt: calendar.date(from: DateComponents(year: 2026, month: 3, day: 31))
        )
        let rule = DistributionRule(
            businessId: UUID(),
            name: "全体稼働日数",
            scope: .allProjects,
            basis: .activeDays,
            roundingPolicy: .lastProjectAdjust,
            effectiveFrom: referenceDate
        )

        let ratios = try DistributionTemplateApplicationUseCase().buildRatioAllocations(
            rule: rule,
            projects: [active, completedBeforeMonth],
            referenceDate: referenceDate,
            allocationPeriod: .month
        )

        XCTAssertEqual(ratios.count, 1)
        XCTAssertEqual(ratios.first?.projectId, active.id)
        XCTAssertEqual(ratios.first?.ratio, 100)
    }

    func testShouldUseDynamicEqualAllOnlyForMonthlyActiveEqualRule() {
        let useCase = DistributionTemplateApplicationUseCase()
        let effectiveFrom = calendar.date(from: DateComponents(year: 2026, month: 1, day: 6))!
        let dynamicRule = DistributionRule(
            businessId: UUID(),
            name: "動的均等",
            scope: .allActiveProjectsInMonth,
            basis: .equal,
            effectiveFrom: effectiveFrom
        )
        let manualRule = DistributionRule(
            businessId: UUID(),
            name: "手動テンプレート",
            scope: .selectedProjects,
            basis: .equal,
            weights: [DistributionWeight(projectId: UUID(), weight: 1)],
            effectiveFrom: effectiveFrom
        )

        XCTAssertTrue(useCase.shouldUseDynamicEqualAll(for: dynamicRule))
        XCTAssertFalse(useCase.shouldUseDynamicEqualAll(for: manualRule))
    }

    func testIsSupportedRejectsActiveDaysForYearlyContext() {
        let useCase = DistributionTemplateApplicationUseCase()
        let effectiveFrom = calendar.date(from: DateComponents(year: 2026, month: 1, day: 6))!
        let rule = DistributionRule(
            businessId: UUID(),
            name: "年次稼働日数",
            scope: .selectedProjects,
            basis: .activeDays,
            weights: [DistributionWeight(projectId: UUID(), weight: 1)],
            effectiveFrom: effectiveFrom
        )

        XCTAssertFalse(useCase.isSupported(rule, allocationPeriod: .year))
    }
}
