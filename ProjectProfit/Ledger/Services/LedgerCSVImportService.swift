// ============================================================
// LedgerCSVImportService.swift
// CSVインポートサービス - 台帳タイプ別エントリ生成
// ============================================================

import Foundation

struct LedgerCSVImportResult {
    let successCount: Int
    let errorCount: Int
    let errors: [(line: Int, reason: String)]
}

@MainActor
class LedgerCSVImportService {

    static let shared = LedgerCSVImportService()

    // MARK: - Public API

    func importCSV(
        content: String,
        ledgerType: LedgerType,
        ledgerStore: LedgerDataStore,
        bookId: UUID
    ) -> LedgerCSVImportResult {
        let rows = CSVImportService.shared.parseCSV(content)
        guard rows.count > 1 else {
            return LedgerCSVImportResult(successCount: 0, errorCount: 1, errors: [(1, "ヘッダー行またはデータが見つかりません")])
        }

        let headerRow = rows[0]
        let dataRows = Array(rows.dropFirst())
        let headerMap = detectHeaderMapping(headerRow, ledgerType: ledgerType)

        var successCount = 0
        var errors: [(Int, String)] = []

        for (index, row) in dataRows.enumerated() {
            let lineNumber = index + 2
            do {
                try importRow(row, headerMap: headerMap, ledgerType: ledgerType, ledgerStore: ledgerStore, bookId: bookId)
                successCount += 1
            } catch {
                errors.append((lineNumber, error.localizedDescription))
            }
        }

        return LedgerCSVImportResult(successCount: successCount, errorCount: errors.count, errors: errors)
    }

    // MARK: - Header Detection

    private func detectHeaderMapping(_ headers: [String], ledgerType: LedgerType) -> [String: Int] {
        var map: [String: Int] = [:]
        let normalized = headers.map { $0.trimmingCharacters(in: .whitespaces) }

        // Japanese header mappings
        let jaToKey: [String: String] = [
            "月": "month", "日": "day", "摘要": "description",
            "勘定科目": "account", "相手科目": "counterAccount",
            "入金": "income", "出金": "expense", "金額": "amount",
            "借方": "debit", "貸方": "credit",
            "借方科目": "debitAccount", "借方金額": "debitAmount",
            "貸方科目": "creditAccount", "貸方金額": "creditAmount",
            "数量": "quantity", "単価": "unitPrice",
            "売上金額": "salesAmount", "入金金額": "receivedAmount",
            "仕入金額": "purchaseAmount", "支払金額": "paymentAmount",
            "軽減税率": "reducedTax", "インボイス": "invoiceType",
            "行先": "destination", "目的": "purpose",
            "交通機関": "transportMethod", "出発地": "routeFrom",
            "到着地": "routeTo", "片/往": "tripType", "日付": "date",
            "預入金額": "deposit", "引出金額": "withdrawal",
            "売上": "salesAmount", "雑収入": "miscIncome",
            "雑収入等": "miscIncome", "仕入": "purchases",
        ]

        // English header mappings
        let enToKey: [String: String] = [
            "month": "month", "day": "day", "description": "description",
            "account": "account", "counter_account": "counterAccount",
            "income": "income", "expense": "expense", "amount": "amount",
            "debit": "debit", "credit": "credit",
            "debit_account": "debitAccount", "debit_amount": "debitAmount",
            "credit_account": "creditAccount", "credit_amount": "creditAmount",
            "quantity": "quantity", "unit_price": "unitPrice",
            "sales_amount": "salesAmount", "received_amount": "receivedAmount",
            "purchase_amount": "purchaseAmount", "payment_amount": "paymentAmount",
            "date": "date", "destination": "destination", "purpose": "purpose",
        ]

        for (i, header) in normalized.enumerated() {
            if let key = jaToKey[header] {
                map[key] = i
            } else if let key = enToKey[header.lowercased()] {
                map[key] = i
            }
        }

        return map
    }

    // MARK: - Row Import

    private func importRow(
        _ row: [String],
        headerMap: [String: Int],
        ledgerType: LedgerType,
        ledgerStore: LedgerDataStore,
        bookId: UUID
    ) throws {
        func str(_ key: String) -> String {
            guard let idx = headerMap[key], idx < row.count else { return "" }
            return row[idx].trimmingCharacters(in: .whitespaces)
        }
        func intVal(_ key: String) -> Int? {
            let s = str(key).replacingOccurrences(of: ",", with: "")
            return Int(s)
        }
        func month() -> Int { intVal("month") ?? 1 }
        func day() -> Int { intVal("day") ?? 1 }

        switch ledgerType {
        case .cashBook, .cashBookInvoice:
            let desc = str("description")
            guard !desc.isEmpty else { throw ImportError.missingField("摘要") }
            let entry = CashBookEntry(
                month: month(), day: day(),
                description: desc,
                account: str("account"),
                income: intVal("income"),
                expense: intVal("expense"),
                reducedTax: str("reducedTax") == "〇" ? true : nil,
                invoiceType: InvoiceType(rawValue: str("invoiceType"))
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .bankAccountBook, .bankAccountBookInvoice:
            let desc = str("description")
            guard !desc.isEmpty else { throw ImportError.missingField("摘要") }
            let entry = BankAccountBookEntry(
                month: month(), day: day(),
                description: desc,
                account: str("account"),
                deposit: intVal("income") ?? intVal("deposit"),
                withdrawal: intVal("expense") ?? intVal("withdrawal"),
                reducedTax: str("reducedTax") == "〇" ? true : nil,
                invoiceType: InvoiceType(rawValue: str("invoiceType"))
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .accountsReceivable:
            let desc = str("description")
            guard !desc.isEmpty else { throw ImportError.missingField("摘要") }
            let entry = AccountsReceivableEntry(
                month: month(), day: day(),
                counterAccount: str("counterAccount"),
                description: desc,
                quantity: intVal("quantity"),
                unitPrice: intVal("unitPrice"),
                salesAmount: intVal("salesAmount"),
                receivedAmount: intVal("receivedAmount")
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .accountsPayable:
            let desc = str("description")
            guard !desc.isEmpty else { throw ImportError.missingField("摘要") }
            let entry = AccountsPayableEntry(
                month: month(), day: day(),
                counterAccount: str("counterAccount"),
                description: desc,
                quantity: intVal("quantity"),
                unitPrice: intVal("unitPrice"),
                purchaseAmount: intVal("purchaseAmount"),
                paymentAmount: intVal("paymentAmount")
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .expenseBook, .expenseBookInvoice:
            let desc = str("description")
            guard !desc.isEmpty else { throw ImportError.missingField("摘要") }
            let entry = ExpenseBookEntry(
                month: month(), day: day(),
                counterAccount: str("counterAccount"),
                description: desc,
                amount: intVal("amount") ?? 0,
                reducedTax: str("reducedTax") == "〇" ? true : nil,
                invoiceType: InvoiceType(rawValue: str("invoiceType"))
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .generalLedger, .generalLedgerInvoice:
            let desc = str("description")
            guard !desc.isEmpty else { throw ImportError.missingField("摘要") }
            let entry = GeneralLedgerEntry(
                month: month(), day: day(),
                counterAccount: str("counterAccount"),
                description: desc,
                debit: intVal("debit"),
                credit: intVal("credit"),
                reducedTax: str("reducedTax") == "〇" ? true : nil,
                invoiceType: InvoiceType(rawValue: str("invoiceType"))
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .journal:
            let desc = str("description")
            guard !desc.isEmpty else { throw ImportError.missingField("摘要") }
            let da = str("debitAccount")
            let ca = str("creditAccount")
            let entry = JournalEntry(
                month: month(), day: day(),
                description: desc,
                debitAccount: da.isEmpty ? nil : da,
                debitAmount: intVal("debitAmount"),
                creditAccount: ca.isEmpty ? nil : ca,
                creditAmount: intVal("creditAmount")
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice:
            let desc = str("description")
            guard !desc.isEmpty else { throw ImportError.missingField("摘要") }
            let entry = WhiteTaxBookkeepingEntry(
                id: UUID(),
                month: month(), day: day(),
                description: desc,
                salesAmount: intVal("salesAmount"),
                miscIncome: intVal("miscIncome"),
                purchases: intVal("purchases"),
                reducedTax: str("reducedTax") == "〇" ? true : nil,
                invoiceType: InvoiceType(rawValue: str("invoiceType"))
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .transportationExpense:
            let dest = str("destination")
            guard !dest.isEmpty else { throw ImportError.missingField("行先") }
            let entry = TransportationExpenseEntry(
                id: UUID(),
                date: str("date"),
                destination: dest,
                purpose: str("purpose"),
                transportMethod: str("transportMethod"),
                routeFrom: str("routeFrom"),
                routeTo: str("routeTo"),
                tripType: TripType(rawValue: str("tripType")) ?? .roundTrip,
                amount: intVal("amount") ?? 0
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .fixedAssetDepreciation, .fixedAssetRegister:
            throw ImportError.unsupportedType
        }
    }

    // MARK: - Errors

    enum ImportError: LocalizedError {
        case missingField(String)
        case unsupportedType

        var errorDescription: String? {
            switch self {
            case .missingField(let field):
                return "必須フィールド「\(field)」が空です"
            case .unsupportedType:
                return "この台帳タイプのインポートは未対応です"
            }
        }
    }
}
