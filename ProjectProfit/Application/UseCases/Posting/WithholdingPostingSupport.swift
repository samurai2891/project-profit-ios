import Foundation
import SwiftData

enum WithholdingPostingSupportError: LocalizedError {
    case missingWithholdingCode
    case invalidWithholdingCode(String)
    case paymentLineNotFound
    case invalidWithholdingAmount
    case liabilityAccountNotFound

    var errorDescription: String? {
        switch self {
        case .missingWithholdingCode:
            return "源泉区分を選択してください"
        case .invalidWithholdingCode:
            return "源泉区分の値が不正です"
        case .paymentLineNotFound:
            return "支払元口座の仕訳行を解決できませんでした"
        case .invalidWithholdingAmount:
            return "源泉徴収税額が不正です"
        case .liabilityAccountNotFound:
            return "源泉所得税預り金の勘定科目を解決できませんでした"
        }
    }
}

struct WithholdingPostingInput: Sendable, Equatable {
    let isEnabled: Bool
    let codeId: String?
    let explicitAmount: Decimal?
    let totalAmount: Int
    let taxAmount: Int?
    let isTaxIncluded: Bool?

    init(
        isEnabled: Bool,
        codeId: String?,
        explicitAmount: Decimal?,
        totalAmount: Int,
        taxAmount: Int?,
        isTaxIncluded: Bool?
    ) {
        self.isEnabled = isEnabled
        self.codeId = codeId
        self.explicitAmount = explicitAmount
        self.totalAmount = totalAmount
        self.taxAmount = taxAmount
        self.isTaxIncluded = isTaxIncluded
    }
}

struct ResolvedWithholdingPosting: Sendable, Equatable {
    let code: WithholdingTaxCode
    let withholdingAmount: Decimal
    let calculationBaseAmount: Decimal
}

enum WithholdingPostingSupport {
    static func resolve(input: WithholdingPostingInput) throws -> ResolvedWithholdingPosting? {
        guard input.isEnabled else {
            return nil
        }

        guard let rawCode = input.codeId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawCode.isEmpty else {
            throw WithholdingPostingSupportError.missingWithholdingCode
        }
        guard let code = WithholdingTaxCode.resolve(id: rawCode) else {
            throw WithholdingPostingSupportError.invalidWithholdingCode(rawCode)
        }

        let baseAmount = calculationBaseAmount(
            totalAmount: input.totalAmount,
            taxAmount: input.taxAmount,
            isTaxIncluded: input.isTaxIncluded
        )
        let resolvedAmount = input.explicitAmount ?? WithholdingTaxCalculator.calculate(
            grossAmount: baseAmount,
            code: code
        ).withholdingAmount

        guard resolvedAmount > 0, resolvedAmount <= Decimal(input.totalAmount) else {
            throw WithholdingPostingSupportError.invalidWithholdingAmount
        }

        return ResolvedWithholdingPosting(
            code: code,
            withholdingAmount: resolvedAmount,
            calculationBaseAmount: baseAmount
        )
    }

    static func calculationBaseAmount(
        totalAmount: Int,
        taxAmount: Int?,
        isTaxIncluded: Bool?
    ) -> Decimal {
        let total = max(0, totalAmount)
        guard let taxAmount,
              taxAmount > 0,
              isTaxIncluded == false else {
            return Decimal(total)
        }
        return Decimal(max(0, total - taxAmount))
    }

    static func liabilityAccount(
        businessId: UUID,
        chartOfAccountsUseCase: ChartOfAccountsUseCase
    ) async throws -> CanonicalAccount {
        guard let account = try await chartOfAccountsUseCase.account(
            businessId: businessId,
            legacyAccountId: AccountingConstants.withholdingTaxPayableAccountId
        ) else {
            throw WithholdingPostingSupportError.liabilityAccountNotFound
        }
        return account
    }

    static func applyToExpenseLines(
        _ lines: [PostingCandidateLine],
        paymentAccountId: UUID,
        liabilityAccount: CanonicalAccount,
        withholding: ResolvedWithholdingPosting,
        memo: String?
    ) throws -> [PostingCandidateLine] {
        guard !lines.isEmpty else {
            return lines
        }

        var adjustedLines = lines
        guard let paymentLineIndex = adjustedLines.firstIndex(where: { line in
            line.creditAccountId == paymentAccountId && line.amount >= withholding.withholdingAmount
        }) else {
            throw WithholdingPostingSupportError.paymentLineNotFound
        }

        let paymentLine = adjustedLines[paymentLineIndex]
        let netPaymentAmount = paymentLine.amount - withholding.withholdingAmount
        guard netPaymentAmount >= 0 else {
            throw WithholdingPostingSupportError.invalidWithholdingAmount
        }

        if netPaymentAmount > 0 {
            adjustedLines[paymentLineIndex] = paymentLine.updated(amount: netPaymentAmount)
        } else {
            adjustedLines.remove(at: paymentLineIndex)
        }

        let annotationLineIndex = adjustedLines.firstIndex(where: { line in
            line.debitAccountId != nil && line.amount > 0
        })
        if let annotationLineIndex {
            adjustedLines[annotationLineIndex] = adjustedLines[annotationLineIndex].updated(
                withholdingTaxCodeId: .some(withholding.code.rawValue),
                withholdingTaxAmount: .some(withholding.withholdingAmount),
                withholdingTaxBaseAmount: .some(withholding.calculationBaseAmount)
            )
        }

        adjustedLines.append(
            PostingCandidateLine(
                creditAccountId: liabilityAccount.id,
                amount: withholding.withholdingAmount,
                legalReportLineId: liabilityAccount.defaultLegalReportLineId,
                memo: memo ?? "源泉所得税預り金"
            )
        )

        return adjustedLines
    }
}
