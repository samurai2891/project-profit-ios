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
    enum ApplicationError: LocalizedError, Equatable {
        case unsupportedScope(DistributionScope)
        case unsupportedBasis(DistributionBasis)
        case unsupportedFixedWeightScope(DistributionScope)
        case noEligibleProjects
        case missingWeights

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
            }
        }
    }
}
