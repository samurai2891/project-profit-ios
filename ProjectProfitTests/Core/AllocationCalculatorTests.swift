import XCTest
@testable import ProjectProfit

final class AllocationCalculatorTests: XCTestCase {

    // MARK: - 均等配賦

    func testEqualSplitTwoProjects() {
        let projectIds = [UUID(), UUID()]
        let allocations = AllocationCalculator.equalSplit(
            totalAmount: 100000,
            projectIds: projectIds
        )

        XCTAssertEqual(allocations.count, 2)
        let total = allocations.reduce(Decimal(0)) { $0 + $1.amount }
        XCTAssertEqual(total, 100000, "配賦合計が元金額と一致")
    }

    func testEqualSplitThreeProjects() {
        let projectIds = [UUID(), UUID(), UUID()]
        let allocations = AllocationCalculator.equalSplit(
            totalAmount: 100000,
            projectIds: projectIds
        )

        XCTAssertEqual(allocations.count, 3)
        let total = allocations.reduce(Decimal(0)) { $0 + $1.amount }
        XCTAssertEqual(total, 100000, "端数調整後も合計が元金額と一致")
    }

    func testEqualSplitOneProject() {
        let projectIds = [UUID()]
        let allocations = AllocationCalculator.equalSplit(
            totalAmount: 550000,
            projectIds: projectIds
        )

        XCTAssertEqual(allocations.count, 1)
        XCTAssertEqual(allocations.first?.amount, 550000)
    }

    func testEqualSplitEmptyProjects() {
        let allocations = AllocationCalculator.equalSplit(
            totalAmount: 100000,
            projectIds: []
        )
        XCTAssertTrue(allocations.isEmpty)
    }

    // MARK: - 重み付き配賦

    func testWeightedSplit() {
        let proj1 = UUID()
        let proj2 = UUID()
        let weights = [
            DistributionWeight(projectId: proj1, weight: 70),
            DistributionWeight(projectId: proj2, weight: 30)
        ]

        let allocations = AllocationCalculator.weightedSplit(
            totalAmount: 100000,
            weights: weights
        )

        XCTAssertEqual(allocations.count, 2)
        let total = allocations.reduce(Decimal(0)) { $0 + $1.amount }
        XCTAssertEqual(total, 100000, "重み付き配賦の合計が元金額と一致")
    }

    func testWeightedSplitRoundingAdjustment() {
        let proj1 = UUID()
        let proj2 = UUID()
        let proj3 = UUID()
        let weights = [
            DistributionWeight(projectId: proj1, weight: 34),
            DistributionWeight(projectId: proj2, weight: 33),
            DistributionWeight(projectId: proj3, weight: 33)
        ]

        let allocations = AllocationCalculator.weightedSplit(
            totalAmount: 110000,
            weights: weights
        )

        XCTAssertEqual(allocations.count, 3)
        let total = allocations.reduce(Decimal(0)) { $0 + $1.amount }
        XCTAssertEqual(total, 110000, "端数調整後も合計が元金額と一致")
    }

    func testWeightedSplitLargestWeightAdjustAppliesResidualToLargestWeightProject() {
        let proj1 = UUID()
        let proj2 = UUID()
        let weights = [
            DistributionWeight(projectId: proj1, weight: 70),
            DistributionWeight(projectId: proj2, weight: 30)
        ]

        let allocations = AllocationCalculator.weightedSplit(
            totalAmount: 100,
            weights: weights,
            roundingPolicy: .largestWeightAdjust
        )

        XCTAssertEqual(allocations.map(\.amount), [70, 30])
    }

    func testWeightedSplitEmptyWeights() {
        let allocations = AllocationCalculator.weightedSplit(
            totalAmount: 100000,
            weights: []
        )
        XCTAssertTrue(allocations.isEmpty)
    }

    // MARK: - 配賦ソース

    func testAllocationSourceIsFromRule() {
        let projectIds = [UUID(), UUID()]
        let allocations = AllocationCalculator.equalSplit(
            totalAmount: 100000,
            projectIds: projectIds
        )
        XCTAssertTrue(allocations.allSatisfy { $0.source == .fromRule })
    }
}
