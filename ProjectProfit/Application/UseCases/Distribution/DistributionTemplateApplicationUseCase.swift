import Foundation

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
