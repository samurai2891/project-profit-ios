import Foundation

struct InputTaxDeductionCalculator: Sendable {
    enum Mode: Sendable, Equatable {
        case lineBased
        case simplified(deemedPurchaseRate: Decimal)
        case twoTenths
    }

    let profile: TaxYearProfile

    init(profile: TaxYearProfile) {
        self.profile = profile
    }

    func mode() -> Mode {
        if profile.isTwoTenthsSpecial {
            return .twoTenths
        }
        if profile.isSimplifiedTaxation {
            return .simplified(
                deemedPurchaseRate: Self.deemedPurchaseRate(
                    category: profile.simplifiedBusinessCategory
                )
            )
        }
        return .lineBased
    }

    func deductibleTaxAmount(
        taxAmount: Decimal,
        creditMethod: InputTaxCreditMethod
    ) -> Decimal {
        switch mode() {
        case .lineBased:
            return taxAmount * creditMethod.creditRate
        case .simplified(let deemedPurchaseRate):
            return taxAmount * deemedPurchaseRate
        case .twoTenths:
            return taxAmount * Decimal(string: "0.8")!
        }
    }

    func worksheetDeductibleInputTaxTotal(
        outputTaxTotal: Int,
        provisionalInputDeductibleTotal: Int
    ) -> Int {
        switch mode() {
        case .lineBased:
            return provisionalInputDeductibleTotal
        case .simplified(let deemedPurchaseRate):
            return decimalToInt(Decimal(outputTaxTotal) * deemedPurchaseRate)
        case .twoTenths:
            return decimalToInt(Decimal(outputTaxTotal) * Decimal(string: "0.8")!)
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

    static func deemedPurchaseRate(category: Int?) -> Decimal {
        switch category {
        case 1:
            return Decimal(string: "0.90")!
        case 2:
            return Decimal(string: "0.80")!
        case 3:
            return Decimal(string: "0.70")!
        case 4:
            return Decimal(string: "0.60")!
        case 5:
            return Decimal(string: "0.50")!
        case 6:
            return Decimal(string: "0.40")!
        default:
            return 0
        }
    }

    private func decimalToInt(_ value: Decimal) -> Int {
        NSDecimalNumber(decimal: value).intValue
    }
}
