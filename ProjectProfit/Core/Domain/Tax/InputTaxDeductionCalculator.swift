import Foundation

enum InputTaxDeductionCalculationMode: Sendable, Equatable {
    case lineBased
    case simplified(deemedPurchaseRate: Decimal)
    case twoTenths(creditRate: Decimal)
    case reviewRequired
}

struct InputTaxDeductionDecision: Sendable, Equatable {
    let creditMethod: InputTaxCreditMethod
    let calculationMode: InputTaxDeductionCalculationMode
    let creditRate: Decimal
    let deemedPurchaseRate: Decimal?
    let requiresReview: Bool
}

struct InputTaxDeductionCalculator: Sendable {
    func deductibleTaxAmount(
        taxAmount: Decimal,
        decision: InputTaxDeductionDecision
    ) -> Decimal {
        guard !decision.requiresReview else {
            return 0
        }
        return taxAmount * decision.creditRate
    }

    func worksheetDeductibleInputTaxTotal(
        outputTaxTotal: Int,
        provisionalInputDeductibleTotal: Int,
        calculationMode: InputTaxDeductionCalculationMode
    ) -> Int {
        switch calculationMode {
        case .lineBased:
            return provisionalInputDeductibleTotal
        case .simplified(let deemedPurchaseRate):
            return decimalToInt(Decimal(outputTaxTotal) * deemedPurchaseRate)
        case .twoTenths(let creditRate):
            return decimalToInt(Decimal(outputTaxTotal) * creditRate)
        case .reviewRequired:
            return 0
        }
    }

    func distributeWorksheetDeduction(
        targetDeductibleTaxAmount: Int,
        lines: [ConsumptionTaxWorksheetLine]
    ) -> [ConsumptionTaxWorksheetLine] {
        guard targetDeductibleTaxAmount > 0 else {
            return lines.map { line in
                guard line.direction == .input else { return line }
                return line.withDeductibleTaxAmount(0)
            }
        }

        let inputLineIndexes = lines.enumerated()
            .filter { _, line in line.direction == .input && line.taxCode.isTaxable }
            .map(\.offset)
        guard !inputLineIndexes.isEmpty else {
            return lines
        }

        let totalWeight = inputLineIndexes.reduce(0) { partial, index in
            partial + max(lines[index].taxAmount, 1)
        }

        var remaining = targetDeductibleTaxAmount
        var updated = lines
        for (offset, index) in inputLineIndexes.enumerated() {
            let weight = max(lines[index].taxAmount, 1)
            let allocated: Int
            if offset == inputLineIndexes.count - 1 {
                allocated = remaining
            } else {
                allocated = totalWeight > 0 ? targetDeductibleTaxAmount * weight / totalWeight : 0
                remaining -= allocated
            }
            updated[index] = updated[index].withDeductibleTaxAmount(max(allocated, 0))
        }
        return updated
    }

    private func decimalToInt(_ value: Decimal) -> Int {
        NSDecimalNumber(decimal: value).intValue
    }
}
