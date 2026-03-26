import Foundation

public struct DistributionApplicationPreview: Sendable, Equatable {
    public struct Allocation: Sendable, Equatable {
        public let projectId: UUID
        public let ratio: Int
        public let amount: Int

        public init(projectId: UUID, ratio: Int, amount: Int) {
            self.projectId = projectId
            self.ratio = ratio
            self.amount = amount
        }
    }

    public let allocations: [Allocation]
    public let totalAllocatedAmount: Int
    public let warnings: [String]

    public init(
        allocations: [Allocation],
        totalAllocatedAmount: Int,
        warnings: [String]
    ) {
        self.allocations = allocations
        self.totalAllocatedAmount = totalAllocatedAmount
        self.warnings = warnings
    }
}

struct DistributionTemplateApplicationUseCase {
    enum AllocationPeriod: Sendable {
        case month
        case year
    }

    func currentApprovalState(
        allocationMode: AllocationMode,
        allocations: [(projectId: UUID, ratio: Int)],
        totalAmount: Int
    ) -> ApprovalState {
        switch allocationMode {
        case .equalAll:
            return .equalAll
        case .manual:
            let amountAllocations = calculateRatioAllocations(amount: max(totalAmount, 0), allocations: allocations)
            return .manual(
                amountAllocations.map {
                    ApprovalState.Allocation(projectId: $0.projectId, ratio: $0.ratio, amount: $0.amount)
                }
            )
        }
    }

    func isSupported(
        _ rule: DistributionRule,
        allocationPeriod: AllocationPeriod = .month
    ) -> Bool {
        switch unsupportedReason(for: rule, allocationPeriod: allocationPeriod) {
        case .none:
            return true
        case .some:
            return false
        }
    }

    func shouldUseDynamicEqualAll(for rule: DistributionRule) -> Bool {
        rule.scope == .allActiveProjectsInMonth && rule.basis == .equal
    }

    func buildRatioAllocations(
        rule: DistributionRule,
        projects: [PPProject],
        referenceDate: Date,
        allocationPeriod: AllocationPeriod = .month
    ) throws -> [(projectId: UUID, ratio: Int)] {
        if let reason = unsupportedReason(for: rule, allocationPeriod: allocationPeriod) {
            throw reason
        }

        let eligibleProjects = resolvedProjects(for: rule, projects: projects, referenceDate: referenceDate)
        guard !eligibleProjects.isEmpty else {
            throw ApplicationError.noEligibleProjects
        }

        switch rule.basis {
        case .equal:
            return calculateEqualSplitAllocations(amount: 100, projectIds: eligibleProjects.map(\.id))
                .map { ($0.projectId, $0.ratio) }
        case .fixedWeight:
            let eligibleProjectIds = Set(eligibleProjects.map(\.id))
            let weights = rule.weights.filter { eligibleProjectIds.contains($0.projectId) }
            guard !weights.isEmpty else {
                throw ApplicationError.missingWeights
            }
            return AllocationCalculator.weightedSplit(
                totalAmount: 100,
                weights: weights,
                roundingPolicy: rule.roundingPolicy
            )
            .map {
                ($0.projectId, NSDecimalNumber(decimal: $0.amount).intValue)
            }
        case .activeDays:
            let activeDayWeights = eligibleProjects.compactMap { project -> DistributionWeight? in
                let activeDays = resolvedActiveDays(
                    for: project,
                    referenceDate: referenceDate,
                    allocationPeriod: allocationPeriod
                )
                guard activeDays > 0 else {
                    return nil
                }
                return DistributionWeight(projectId: project.id, weight: Decimal(activeDays))
            }
            guard !activeDayWeights.isEmpty else {
                throw ApplicationError.noEligibleProjects
            }
            return AllocationCalculator.weightedSplit(
                totalAmount: 100,
                weights: activeDayWeights,
                roundingPolicy: rule.roundingPolicy
            )
            .map {
                ($0.projectId, NSDecimalNumber(decimal: $0.amount).intValue)
            }
        case .revenueRatio, .expenseRatio, .customFormula:
            throw ApplicationError.unsupportedBasis(rule.basis)
        }
    }

    func previewAllocations(
        rule: DistributionRule,
        projects: [PPProject],
        referenceDate: Date,
        totalAmount: Int = 100,
        allocationPeriod: AllocationPeriod = .month
    ) -> DistributionApplicationPreview {
        var warnings: [String] = []
        guard totalAmount > 0 else {
            warnings.append("プレビュー対象金額は1以上を指定してください。")
            return DistributionApplicationPreview(
                allocations: [],
                totalAllocatedAmount: 0,
                warnings: warnings
            )
        }

        let ratios: [(projectId: UUID, ratio: Int)]
        do {
            ratios = try buildRatioAllocations(
                rule: rule,
                projects: projects,
                referenceDate: referenceDate,
                allocationPeriod: allocationPeriod
            )
        } catch {
            warnings.append(error.localizedDescription)
            return DistributionApplicationPreview(
                allocations: [],
                totalAllocatedAmount: 0,
                warnings: warnings
            )
        }

        let ratioSum = ratios.map(\.ratio).reduce(0, +)
        if ratioSum != 100 {
            warnings.append("配賦比率の合計が100%ではありません（現在: \(ratioSum)%）。")
        }

        let previewAllocations = buildAmountPreviewAllocations(
            ratios: ratios,
            totalAmount: totalAmount,
            roundingPolicy: rule.roundingPolicy
        )
        let totalAllocatedAmount = previewAllocations.map(\.amount).reduce(0, +)

        if totalAllocatedAmount != totalAmount {
            warnings.append("配賦金額の合計が入力金額と一致しません。")
        }

        return DistributionApplicationPreview(
            allocations: previewAllocations,
            totalAllocatedAmount: totalAllocatedAmount,
            warnings: warnings
        )
    }

    func makeApprovalPreview(
        rule: DistributionRule,
        currentState: ApprovalState,
        projects: [PPProject],
        referenceDate: Date,
        totalAmount: Int,
        allocationPeriod: AllocationPeriod = .month,
        supportsEqualAllMode: Bool = true
    ) -> ApprovalPreview {
        let buildResult = makeApprovalRequestDraft(
            businessId: rule.businessId,
            draftKey: "preview:\(rule.id.uuidString)",
            draftKind: .transaction,
            rule: rule,
            currentState: currentState,
            projects: projects,
            referenceDate: referenceDate,
            totalAmount: totalAmount,
            allocationPeriod: allocationPeriod,
            supportsEqualAllMode: supportsEqualAllMode
        )
        let payload = buildResult.payload
        if supportsEqualAllMode && shouldUseDynamicEqualAll(for: rule) {
            let warnings = currentState == .equalAll ? ["現在の配分と同じ内容です。"] : []
            return ApprovalPreview(
                ruleName: rule.name,
                currentState: currentState,
                proposedState: .equalAll,
                warnings: warnings,
                isApprovable: true
            )
        }

        guard buildResult.isApprovable, let payload else {
            return ApprovalPreview(
                ruleName: rule.name,
                currentState: currentState,
                proposedState: nil,
                warnings: buildResult.warnings,
                isApprovable: false
            )
        }

        return ApprovalPreview(
            ruleName: rule.name,
            currentState: payload.currentState,
            proposedState: payload.proposedState,
            warnings: buildResult.warnings,
            isApprovable: buildResult.isApprovable
        )
    }

    func approve(_ preview: ApprovalPreview) throws -> ApprovedApplication {
        guard preview.isApprovable, let proposedState = preview.proposedState else {
            throw ApplicationError.approvalPreviewNotApplicable
        }

        switch proposedState {
        case .equalAll:
            return ApprovedApplication(allocationMode: .equalAll, allocations: [])
        case let .manual(allocations):
            return ApprovedApplication(
                allocationMode: .manual,
                allocations: allocations.map {
                    ApprovedApplication.Allocation(projectId: $0.projectId, ratio: $0.ratio, amount: $0.amount)
                }
            )
        }
    }

    func makeApprovalRequestDraft(
        businessId: UUID,
        draftKey: String,
        draftKind: FormDraftKind,
        rule: DistributionRule,
        currentState: ApprovalState,
        projects: [PPProject],
        referenceDate: Date,
        totalAmount: Int,
        allocationPeriod: AllocationPeriod = .month,
        supportsEqualAllMode: Bool = true
    ) -> ApprovalRequestBuildResult {
        if supportsEqualAllMode && shouldUseDynamicEqualAll(for: rule) {
            let warnings = currentState == .equalAll ? ["現在の配分と同じ内容です。"] : []
            let payload = DistributionApprovalPayload(
                draftKey: draftKey,
                draftKind: draftKind,
                ruleId: rule.id,
                ruleName: rule.name,
                currentState: currentState,
                proposedState: .equalAll,
                warnings: warnings
            )
            return ApprovalRequestBuildResult(
                requestDraft: ApprovalRequestDraft(
                    businessId: businessId,
                    kind: .distribution,
                    targetKind: draftKind == .transaction ? .transactionDraft : .recurringDraft,
                    targetKey: draftKey,
                    title: rule.name,
                    subtitle: "配賦テンプレート",
                    payloadJSON: CanonicalJSONCoder.encode(payload, fallback: "{}")
                ),
                payload: payload,
                warnings: warnings,
                isApprovable: true
            )
        }

        let preview = previewAllocations(
            rule: rule,
            projects: projects,
            referenceDate: referenceDate,
            totalAmount: totalAmount,
            allocationPeriod: allocationPeriod
        )

        guard !preview.allocations.isEmpty else {
            return ApprovalRequestBuildResult(
                requestDraft: nil,
                payload: nil,
                warnings: preview.warnings,
                isApprovable: false
            )
        }

        let proposedState: ApprovalState = .manual(
            preview.allocations.map {
                ApprovalState.Allocation(projectId: $0.projectId, ratio: $0.ratio, amount: $0.amount)
            }
        )
        var warnings = preview.warnings
        if proposedState == currentState {
            warnings.append("現在の配分と同じ内容です。")
        }

        let payload = DistributionApprovalPayload(
            draftKey: draftKey,
            draftKind: draftKind,
            ruleId: rule.id,
            ruleName: rule.name,
            currentState: currentState,
            proposedState: proposedState,
            warnings: warnings
        )
        return ApprovalRequestBuildResult(
            requestDraft: ApprovalRequestDraft(
                businessId: businessId,
                kind: .distribution,
                targetKind: draftKind == .transaction ? .transactionDraft : .recurringDraft,
                targetKey: draftKey,
                title: rule.name,
                subtitle: "配賦テンプレート",
                payloadJSON: CanonicalJSONCoder.encode(payload, fallback: "{}")
            ),
            payload: payload,
            warnings: warnings,
            isApprovable: true
        )
    }

    func approve(_ payload: DistributionApprovalPayload) throws -> ApprovedApplication {
        switch payload.proposedState {
        case .equalAll:
            return ApprovedApplication(allocationMode: .equalAll, allocations: [])
        case .manual(let allocations):
            return ApprovedApplication(
                allocationMode: .manual,
                allocations: allocations.map {
                    ApprovedApplication.Allocation(projectId: $0.projectId, ratio: $0.ratio, amount: $0.amount)
                }
            )
        }
    }

    private func unsupportedReason(
        for rule: DistributionRule,
        allocationPeriod: AllocationPeriod
    ) -> ApplicationError? {
        switch rule.scope {
        case .allProjects, .allActiveProjectsInMonth, .selectedProjects:
            break
        case .projectsByTag:
            return .unsupportedScope(rule.scope)
        }

        switch rule.basis {
        case .equal:
            return nil
        case .fixedWeight:
            return rule.scope == .selectedProjects ? nil : .unsupportedFixedWeightScope(rule.scope)
        case .activeDays:
            return allocationPeriod == .month ? nil : .unsupportedBasis(rule.basis)
        case .revenueRatio, .expenseRatio, .customFormula:
            return .unsupportedBasis(rule.basis)
        }
    }

    private func resolvedProjects(
        for rule: DistributionRule,
        projects: [PPProject],
        referenceDate: Date
    ) -> [PPProject] {
        let availableProjects = projects.filter { $0.isArchived != true }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        switch rule.scope {
        case .allProjects:
            return availableProjects
        case .allActiveProjectsInMonth:
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month], from: referenceDate)
            guard let year = components.year, let month = components.month else {
                return []
            }
            return availableProjects.filter { project in
                calculateActiveDaysInMonth(
                    startDate: project.startDate,
                    completedAt: project.effectiveEndDate,
                    year: year,
                    month: month
                ) > 0
            }
        case .selectedProjects:
            let selectedIds = Set(rule.weights.map(\.projectId))
            return availableProjects.filter { selectedIds.contains($0.id) }
        case .projectsByTag:
            return []
        }
    }

    private func resolvedActiveDays(
        for project: PPProject,
        referenceDate: Date,
        allocationPeriod: AllocationPeriod
    ) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: referenceDate)
        guard let year = components.year else {
            return 0
        }

        switch allocationPeriod {
        case .month:
            guard let month = components.month else {
                return 0
            }
            return calculateActiveDaysInMonth(
                startDate: project.startDate,
                completedAt: project.effectiveEndDate,
                year: year,
                month: month
            )
        case .year:
            return calculateActiveDaysInYear(
                startDate: project.startDate,
                completedAt: project.effectiveEndDate,
                year: year
            )
        }
    }

    private func buildAmountPreviewAllocations(
        ratios: [(projectId: UUID, ratio: Int)],
        totalAmount: Int,
        roundingPolicy: RoundingPolicy
    ) -> [DistributionApplicationPreview.Allocation] {
        guard !ratios.isEmpty else { return [] }

        let weights = ratios.map { ratio in
            DistributionWeight(projectId: ratio.projectId, weight: Decimal(ratio.ratio))
        }
        let weightedAllocations = AllocationCalculator.weightedSplit(
            totalAmount: Decimal(totalAmount),
            weights: weights,
            roundingPolicy: roundingPolicy
        )
        let amountByProjectId = Dictionary(uniqueKeysWithValues: weightedAllocations.map {
            ($0.projectId, NSDecimalNumber(decimal: $0.amount).intValue)
        })

        return ratios.map { ratio in
            DistributionApplicationPreview.Allocation(
                projectId: ratio.projectId,
                ratio: ratio.ratio,
                amount: amountByProjectId[ratio.projectId] ?? 0
            )
        }
    }
}

extension DistributionTemplateApplicationUseCase {
    struct ApprovalRequestBuildResult: Sendable, Equatable {
        let requestDraft: ApprovalRequestDraft?
        let payload: DistributionApprovalPayload?
        let warnings: [String]
        let isApprovable: Bool
    }

    struct ApprovalPreview: Sendable, Equatable {
        let ruleName: String
        let currentState: ApprovalState
        let proposedState: ApprovalState?
        let warnings: [String]
        let isApprovable: Bool
    }

    enum ApprovalState: Codable, Sendable, Equatable {
        struct Allocation: Codable, Sendable, Equatable {
            let projectId: UUID
            let ratio: Int
            let amount: Int
        }

        case equalAll
        case manual([Allocation])
    }

    struct DistributionApprovalPayload: Codable, Sendable, Equatable {
        let draftKey: String
        let draftKind: FormDraftKind
        let ruleId: UUID
        let ruleName: String
        let currentState: ApprovalState
        let proposedState: ApprovalState
        let warnings: [String]
    }

    struct ApprovedApplication: Sendable, Equatable {
        struct Allocation: Sendable, Equatable {
            let projectId: UUID
            let ratio: Int
            let amount: Int
        }

        let allocationMode: AllocationMode
        let allocations: [Allocation]
    }

    enum ApplicationError: LocalizedError, Equatable {
        case unsupportedScope(DistributionScope)
        case unsupportedBasis(DistributionBasis)
        case unsupportedFixedWeightScope(DistributionScope)
        case noEligibleProjects
        case missingWeights
        case approvalPreviewNotApplicable

        var errorDescription: String? {
            switch self {
            case .unsupportedScope:
                return "この配賦テンプレートの対象範囲はまだ適用できません。"
            case .unsupportedBasis:
                return "この配賦テンプレートの配賦基準はまだ適用できません。"
            case .unsupportedFixedWeightScope:
                return "固定重みテンプレートは選択プロジェクト指定で作成してください。"
            case .noEligibleProjects:
                return "適用対象のプロジェクトがありません。"
            case .missingWeights:
                return "固定重みテンプレートに重みが設定されていません。"
            case .approvalPreviewNotApplicable:
                return "この配賦プレビューは承認できません。"
            }
        }
    }
}
