import CryptoKit
import Foundation
import SwiftData

struct WithholdingStatementPaymentRow: Identifiable, Sendable, Equatable {
    let id: UUID
    let journalId: UUID
    let date: Date
    let description: String
    let grossAmount: Decimal
    let withholdingTaxAmount: Decimal
    let netAmount: Decimal
}

struct WithholdingStatementDocument: Identifiable, Sendable, Equatable {
    let id: UUID
    let fiscalYear: Int
    let counterpartyId: UUID
    let counterpartyName: String
    let payeeAddress: String?
    let payeeRegistrationNumber: String?
    let withholdingTaxCode: WithholdingTaxCode
    let businessName: String
    let businessAddress: String
    let ownerName: String
    let paymentCount: Int
    let totalGrossAmount: Decimal
    let totalWithholdingTaxAmount: Decimal
    let totalNetAmount: Decimal
    let rows: [WithholdingStatementPaymentRow]
}

struct WithholdingStatementAnnualSummary: Sendable, Equatable {
    let fiscalYear: Int
    let generatedAt: Date
    let businessName: String
    let businessAddress: String
    let ownerName: String
    let documentCount: Int
    let paymentCount: Int
    let totalGrossAmount: Decimal
    let totalWithholdingTaxAmount: Decimal
    let totalNetAmount: Decimal
    let documents: [WithholdingStatementDocument]
}

@MainActor
struct WithholdingStatementQueryUseCase {
    private let support: AccountingReadSupport

    init(modelContext: ModelContext) {
        self.support = AccountingReadSupport(modelContext: modelContext)
    }

    func summary(fiscalYear: Int) throws -> WithholdingStatementAnnualSummary {
        guard let businessProfile = support.fetchBusinessProfile() else {
            throw AppError.invalidInput(message: "事業者プロフィールが未設定です")
        }

        let journals = support.fetchCanonicalJournalEntries(
            businessId: businessProfile.id,
            taxYear: fiscalYear
        )
        .filter { $0.approvedAt != nil }

        struct GroupKey: Hashable {
            let counterpartyId: UUID
            let code: WithholdingTaxCode
        }

        var documentsByKey: [GroupKey: [WithholdingStatementPaymentRow]] = [:]

        for journal in journals {
            for line in journal.lines {
                guard let counterpartyId = line.counterpartyId,
                      let codeId = line.withholdingTaxCodeId,
                      let code = WithholdingTaxCode.resolve(id: codeId),
                      let withholdingTaxAmount = line.withholdingTaxAmount,
                      withholdingTaxAmount > 0 else {
                    continue
                }

                let grossAmount = line.withholdingTaxBaseAmount ?? line.amount
                let row = WithholdingStatementPaymentRow(
                    id: line.id,
                    journalId: journal.id,
                    date: journal.journalDate,
                    description: journal.description,
                    grossAmount: grossAmount,
                    withholdingTaxAmount: withholdingTaxAmount,
                    netAmount: grossAmount - withholdingTaxAmount
                )
                documentsByKey[GroupKey(counterpartyId: counterpartyId, code: code), default: []].append(row)
            }
        }

        let documents = documentsByKey.compactMap { key, rows -> WithholdingStatementDocument? in
            guard let counterparty = support.fetchCanonicalCounterparty(id: key.counterpartyId) else {
                return nil
            }
            let sortedRows = rows.sorted {
                if $0.date == $1.date {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.date < $1.date
            }

            let totalGrossAmount = sortedRows.reduce(Decimal.zero) { $0 + $1.grossAmount }
            let totalWithholdingTaxAmount = sortedRows.reduce(Decimal.zero) { $0 + $1.withholdingTaxAmount }
            let totalNetAmount = sortedRows.reduce(Decimal.zero) { $0 + $1.netAmount }

            return WithholdingStatementDocument(
                id: stableDocumentId(counterpartyId: key.counterpartyId, code: key.code),
                fiscalYear: fiscalYear,
                counterpartyId: key.counterpartyId,
                counterpartyName: counterparty.legalName ?? counterparty.displayName,
                payeeAddress: counterparty.address,
                payeeRegistrationNumber: counterparty.normalizedInvoiceRegistrationNumber,
                withholdingTaxCode: key.code,
                businessName: businessProfile.businessName,
                businessAddress: businessProfile.businessAddress,
                ownerName: businessProfile.ownerName,
                paymentCount: sortedRows.count,
                totalGrossAmount: totalGrossAmount,
                totalWithholdingTaxAmount: totalWithholdingTaxAmount,
                totalNetAmount: totalNetAmount,
                rows: sortedRows
            )
        }
        .sorted {
            if $0.counterpartyName == $1.counterpartyName {
                return $0.withholdingTaxCode.displayName < $1.withholdingTaxCode.displayName
            }
            return $0.counterpartyName.localizedStandardCompare($1.counterpartyName) == .orderedAscending
        }

        return WithholdingStatementAnnualSummary(
            fiscalYear: fiscalYear,
            generatedAt: Date(),
            businessName: businessProfile.businessName,
            businessAddress: businessProfile.businessAddress,
            ownerName: businessProfile.ownerName,
            documentCount: documents.count,
            paymentCount: documents.reduce(0) { $0 + $1.paymentCount },
            totalGrossAmount: documents.reduce(Decimal.zero) { $0 + $1.totalGrossAmount },
            totalWithholdingTaxAmount: documents.reduce(Decimal.zero) { $0 + $1.totalWithholdingTaxAmount },
            totalNetAmount: documents.reduce(Decimal.zero) { $0 + $1.totalNetAmount },
            documents: documents
        )
    }

    private func stableDocumentId(counterpartyId: UUID, code: WithholdingTaxCode) -> UUID {
        let seed = "\(counterpartyId.uuidString.lowercased())|\(code.rawValue)"
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }
}
