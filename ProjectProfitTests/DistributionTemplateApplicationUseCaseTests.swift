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

    func testPreviewAllocationsReturnsRatiosAndAmountsWithTotalAmount() {
        let useCase = DistributionTemplateApplicationUseCase()
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let projectA = PPProject(name: "Alpha")
        let projectB = PPProject(name: "Beta")
        let rule = DistributionRule(
            businessId: UUID(),
            name: "固定重みプレビュー",
            scope: .selectedProjects,
            basis: .fixedWeight,
            weights: [
                DistributionWeight(projectId: projectA.id, weight: 70),
                DistributionWeight(projectId: projectB.id, weight: 30)
            ],
            roundingPolicy: .largestWeightAdjust,
            effectiveFrom: referenceDate
        )

        let preview = useCase.previewAllocations(
            rule: rule,
            projects: [projectA, projectB],
            referenceDate: referenceDate,
            totalAmount: 10_000
        )

        XCTAssertTrue(preview.warnings.isEmpty)
        XCTAssertEqual(preview.allocations.count, 2)
        XCTAssertEqual(preview.totalAllocatedAmount, 10_000)

        let ratioByProjectId = Dictionary(uniqueKeysWithValues: preview.allocations.map {
            ($0.projectId, $0.ratio)
        })
        let amountByProjectId = Dictionary(uniqueKeysWithValues: preview.allocations.map {
            ($0.projectId, $0.amount)
        })
        XCTAssertEqual(ratioByProjectId[projectA.id], 70)
        XCTAssertEqual(ratioByProjectId[projectB.id], 30)
        XCTAssertEqual(amountByProjectId[projectA.id], 7_000)
        XCTAssertEqual(amountByProjectId[projectB.id], 3_000)
        XCTAssertEqual(preview.allocations.map(\.amount).reduce(0, +), 10_000)
    }

    func testPreviewAllocationsReturnsWarningWhenRuleIsUnsupported() {
        let useCase = DistributionTemplateApplicationUseCase()
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let rule = DistributionRule(
            businessId: UUID(),
            name: "未対応基準",
            scope: .allProjects,
            basis: .revenueRatio,
            roundingPolicy: .lastProjectAdjust,
            effectiveFrom: referenceDate
        )

        let preview = useCase.previewAllocations(
            rule: rule,
            projects: [PPProject(name: "Alpha")],
            referenceDate: referenceDate,
            totalAmount: 10_000
        )

        XCTAssertTrue(preview.allocations.isEmpty)
        XCTAssertEqual(preview.totalAllocatedAmount, 0)
        XCTAssertFalse(preview.warnings.isEmpty)
        XCTAssertTrue(preview.warnings[0].contains("配賦基準"))
    }

    func testPreviewAllocationsReturnsWarningWhenTotalAmountIsInvalid() {
        let useCase = DistributionTemplateApplicationUseCase()
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let project = PPProject(name: "Alpha")
        let rule = DistributionRule(
            businessId: UUID(),
            name: "均等配賦",
            scope: .selectedProjects,
            basis: .equal,
            weights: [DistributionWeight(projectId: project.id, weight: 1)],
            roundingPolicy: .lastProjectAdjust,
            effectiveFrom: referenceDate
        )

        let preview = useCase.previewAllocations(
            rule: rule,
            projects: [project],
            referenceDate: referenceDate,
            totalAmount: 0
        )

        XCTAssertTrue(preview.allocations.isEmpty)
        XCTAssertEqual(preview.totalAllocatedAmount, 0)
        XCTAssertEqual(preview.warnings, ["プレビュー対象金額は1以上を指定してください。"])
    }

    func testMakeApprovalPreviewBuildsCurrentAndProposedManualStates() {
        let useCase = DistributionTemplateApplicationUseCase()
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let projectA = PPProject(name: "Alpha")
        let projectB = PPProject(name: "Beta")
        let rule = DistributionRule(
            businessId: UUID(),
            name: "固定重みプレビュー",
            scope: .selectedProjects,
            basis: .fixedWeight,
            weights: [
                DistributionWeight(projectId: projectA.id, weight: 70),
                DistributionWeight(projectId: projectB.id, weight: 30)
            ],
            roundingPolicy: .largestWeightAdjust,
            effectiveFrom: referenceDate
        )

        let currentState = useCase.currentApprovalState(
            allocationMode: .manual,
            allocations: [(projectId: projectA.id, ratio: 100)],
            totalAmount: 10_000
        )
        let preview = useCase.makeApprovalPreview(
            rule: rule,
            currentState: currentState,
            projects: [projectA, projectB],
            referenceDate: referenceDate,
            totalAmount: 10_000
        )

        XCTAssertTrue(preview.isApprovable)
        XCTAssertEqual(preview.ruleName, "固定重みプレビュー")
        XCTAssertEqual(
            preview.currentState,
            .manual([
                .init(projectId: projectA.id, ratio: 100, amount: 10_000)
            ])
        )
        XCTAssertEqual(
            preview.proposedState,
            .manual([
                .init(projectId: projectA.id, ratio: 70, amount: 7_000),
                .init(projectId: projectB.id, ratio: 30, amount: 3_000)
            ])
        )
        XCTAssertTrue(preview.warnings.isEmpty)
    }

    func testMakeApprovalRequestDraftBuildsDistributionPayloadForManualState() throws {
        let useCase = DistributionTemplateApplicationUseCase()
        let businessId = UUID()
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let projectA = PPProject(name: "Alpha")
        let projectB = PPProject(name: "Beta")
        let rule = DistributionRule(
            businessId: businessId,
            name: "固定重みプレビュー",
            scope: .selectedProjects,
            basis: .fixedWeight,
            weights: [
                DistributionWeight(projectId: projectA.id, weight: 70),
                DistributionWeight(projectId: projectB.id, weight: 30)
            ],
            roundingPolicy: .largestWeightAdjust,
            effectiveFrom: referenceDate
        )

        let result = useCase.makeApprovalRequestDraft(
            businessId: businessId,
            draftKey: "transaction:draft",
            draftKind: .transaction,
            rule: rule,
            currentState: .manual([
                .init(projectId: projectA.id, ratio: 100, amount: 10_000)
            ]),
            projects: [projectA, projectB],
            referenceDate: referenceDate,
            totalAmount: 10_000,
            supportsEqualAllMode: false
        )

        XCTAssertTrue(result.isApprovable)
        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(result.requestDraft?.kind, .distribution)
        XCTAssertEqual(result.requestDraft?.targetKind, .transactionDraft)
        XCTAssertEqual(result.requestDraft?.targetKey, "transaction:draft")
        let payload = try XCTUnwrap(result.payload)
        XCTAssertEqual(payload.ruleId, rule.id)
        XCTAssertEqual(payload.ruleName, rule.name)
        XCTAssertEqual(
            payload.proposedState,
            .manual([
                .init(projectId: projectA.id, ratio: 70, amount: 7_000),
                .init(projectId: projectB.id, ratio: 30, amount: 3_000)
            ])
        )
        let requestDraft = try XCTUnwrap(result.requestDraft)
        let decodedPayload = try XCTUnwrap(
            CanonicalJSONCoder.decodeIfPresent(
                DistributionTemplateApplicationUseCase.DistributionApprovalPayload.self,
                from: requestDraft.payloadJSON
            )
        )
        XCTAssertEqual(decodedPayload, payload)
    }

    func testMakeApprovalPreviewReturnsDynamicEqualAllForRecurringRule() {
        let useCase = DistributionTemplateApplicationUseCase()
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let rule = DistributionRule(
            businessId: UUID(),
            name: "動的均等",
            scope: .allActiveProjectsInMonth,
            basis: .equal,
            roundingPolicy: .lastProjectAdjust,
            effectiveFrom: referenceDate
        )

        let preview = useCase.makeApprovalPreview(
            rule: rule,
            currentState: .manual([]),
            projects: [PPProject(name: "Alpha")],
            referenceDate: referenceDate,
            totalAmount: 10_000,
            allocationPeriod: .month,
            supportsEqualAllMode: true
        )

        XCTAssertTrue(preview.isApprovable)
        XCTAssertEqual(preview.proposedState, .equalAll)
        XCTAssertTrue(preview.warnings.isEmpty)
    }

    func testMakeApprovalRequestDraftBuildsEqualAllPayloadForDynamicRule() throws {
        let useCase = DistributionTemplateApplicationUseCase()
        let businessId = UUID()
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let rule = DistributionRule(
            businessId: businessId,
            name: "動的均等",
            scope: .allActiveProjectsInMonth,
            basis: .equal,
            roundingPolicy: .lastProjectAdjust,
            effectiveFrom: referenceDate
        )

        let result = useCase.makeApprovalRequestDraft(
            businessId: businessId,
            draftKey: "recurring:draft",
            draftKind: .recurring,
            rule: rule,
            currentState: .manual([]),
            projects: [PPProject(name: "Alpha")],
            referenceDate: referenceDate,
            totalAmount: 10_000,
            allocationPeriod: .month,
            supportsEqualAllMode: true
        )

        XCTAssertTrue(result.isApprovable)
        XCTAssertEqual(result.requestDraft?.targetKind, .recurringDraft)
        XCTAssertEqual(result.payload?.proposedState, .equalAll)
    }

    func testMakeApprovalPreviewBuildsManualStateWhenEqualAllModeIsNotSupported() {
        let useCase = DistributionTemplateApplicationUseCase()
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let projectA = PPProject(name: "Alpha")
        let projectB = PPProject(name: "Beta")
        let rule = DistributionRule(
            businessId: UUID(),
            name: "動的均等",
            scope: .allActiveProjectsInMonth,
            basis: .equal,
            roundingPolicy: .lastProjectAdjust,
            effectiveFrom: referenceDate
        )

        let preview = useCase.makeApprovalPreview(
            rule: rule,
            currentState: .manual([]),
            projects: [projectA, projectB],
            referenceDate: referenceDate,
            totalAmount: 10_000,
            allocationPeriod: .month,
            supportsEqualAllMode: false
        )

        XCTAssertTrue(preview.isApprovable)
        XCTAssertEqual(
            preview.proposedState,
            .manual([
                .init(projectId: projectA.id, ratio: 50, amount: 5_000),
                .init(projectId: projectB.id, ratio: 50, amount: 5_000)
            ])
        )
    }

    func testMakeApprovalPreviewKeepsWarningsWhenPreviewIsApprovable() {
        let useCase = DistributionTemplateApplicationUseCase()
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let projectA = PPProject(name: "Alpha")
        let projectB = PPProject(name: "Beta")
        let rule = DistributionRule(
            businessId: UUID(),
            name: "同一配分",
            scope: .selectedProjects,
            basis: .fixedWeight,
            weights: [
                DistributionWeight(projectId: projectA.id, weight: 70),
                DistributionWeight(projectId: projectB.id, weight: 30)
            ],
            roundingPolicy: .largestWeightAdjust,
            effectiveFrom: referenceDate
        )
        let currentState: DistributionTemplateApplicationUseCase.ApprovalState = .manual([
            .init(projectId: projectA.id, ratio: 70, amount: 7_000),
            .init(projectId: projectB.id, ratio: 30, amount: 3_000)
        ])

        let preview = useCase.makeApprovalPreview(
            rule: rule,
            currentState: currentState,
            projects: [projectA, projectB],
            referenceDate: referenceDate,
            totalAmount: 10_000
        )

        XCTAssertTrue(preview.isApprovable)
        XCTAssertEqual(preview.proposedState, currentState)
        XCTAssertEqual(preview.warnings, ["現在の配分と同じ内容です。"])
    }

    func testMakeApprovalPreviewReturnsNonApprovablePreviewForInvalidAmount() {
        let useCase = DistributionTemplateApplicationUseCase()
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let project = PPProject(name: "Alpha")
        let rule = DistributionRule(
            businessId: UUID(),
            name: "均等配賦",
            scope: .selectedProjects,
            basis: .equal,
            weights: [DistributionWeight(projectId: project.id, weight: 1)],
            roundingPolicy: .lastProjectAdjust,
            effectiveFrom: referenceDate
        )

        let preview = useCase.makeApprovalPreview(
            rule: rule,
            currentState: .manual([]),
            projects: [project],
            referenceDate: referenceDate,
            totalAmount: 0
        )

        XCTAssertFalse(preview.isApprovable)
        XCTAssertNil(preview.proposedState)
        XCTAssertEqual(preview.warnings, ["プレビュー対象金額は1以上を指定してください。"])
        XCTAssertThrowsError(try useCase.approve(preview)) { error in
            XCTAssertEqual(
                error as? DistributionTemplateApplicationUseCase.ApplicationError,
                .approvalPreviewNotApplicable
            )
        }
    }

    func testMakeApprovalRequestDraftReturnsNonApprovableResultForInvalidAmount() {
        let useCase = DistributionTemplateApplicationUseCase()
        let businessId = UUID()
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let project = PPProject(name: "Alpha")
        let rule = DistributionRule(
            businessId: businessId,
            name: "均等配賦",
            scope: .selectedProjects,
            basis: .equal,
            weights: [DistributionWeight(projectId: project.id, weight: 1)],
            roundingPolicy: .lastProjectAdjust,
            effectiveFrom: referenceDate
        )

        let result = useCase.makeApprovalRequestDraft(
            businessId: businessId,
            draftKey: "transaction:draft",
            draftKind: .transaction,
            rule: rule,
            currentState: .manual([]),
            projects: [project],
            referenceDate: referenceDate,
            totalAmount: 0
        )

        XCTAssertFalse(result.isApprovable)
        XCTAssertNil(result.requestDraft)
        XCTAssertNil(result.payload)
        XCTAssertEqual(result.warnings, ["プレビュー対象金額は1以上を指定してください。"])
    }

    func testApproveReturnsApplicationForManualAndEqualAllStates() throws {
        let useCase = DistributionTemplateApplicationUseCase()
        let projectA = UUID()
        let projectB = UUID()

        let manualPreview = DistributionTemplateApplicationUseCase.ApprovalPreview(
            ruleName: "手動",
            currentState: .manual([]),
            proposedState: .manual([
                .init(projectId: projectA, ratio: 60, amount: 6_000),
                .init(projectId: projectB, ratio: 40, amount: 4_000)
            ]),
            warnings: [],
            isApprovable: true
        )
        let equalAllPreview = DistributionTemplateApplicationUseCase.ApprovalPreview(
            ruleName: "均等",
            currentState: .manual([]),
            proposedState: .equalAll,
            warnings: [],
            isApprovable: true
        )

        let manual = try useCase.approve(manualPreview)
        let equalAll = try useCase.approve(equalAllPreview)

        XCTAssertEqual(manual.allocationMode, .manual)
        XCTAssertEqual(
            manual.allocations,
            [
                .init(projectId: projectA, ratio: 60, amount: 6_000),
                .init(projectId: projectB, ratio: 40, amount: 4_000)
            ]
        )
        XCTAssertEqual(equalAll.allocationMode, .equalAll)
        XCTAssertTrue(equalAll.allocations.isEmpty)
    }
}
