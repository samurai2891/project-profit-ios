// ============================================================
// LedgerExportService.swift
// CSV書き出し・読み込み & PDF生成サービス
// Excel原本と完全同一フォーマットで出力
// ============================================================

import Foundation
#if canImport(UIKit)
import UIKit
import PDFKit
#endif

// MARK: - CSV Export Service

class CSVExportService {
    
    static let shared = CSVExportService()
    
    private let bom = "\u{FEFF}" // UTF-8 BOM for Excel compatibility
    
    // MARK: - 現金出納帳 CSV
    
    func exportCashBook(
        metadata: CashBookMetadata,
        entries: [CashBookEntry],
        includeInvoice: Bool = false
    ) -> String {
        var lines: [String] = []
        
        // Header
        if includeInvoice {
            lines.append(csvRow(["月", "日", "摘要", "勘定科目", "軽減税率", "インボイス", "入金", "出金", "残高"]))
        } else {
            lines.append(csvRow(["月", "日", "摘要", "勘定科目", "入金", "出金", "残高"]))
        }
        
        // Carry forward row
        var balance = metadata.carryForward
        if includeInvoice {
            lines.append(csvRow(["", "", "前期より繰越", "", "", "", "", "", "\(balance)"]))
        } else {
            lines.append(csvRow(["", "", "前期より繰越", "", "", "", "\(balance)"]))
        }
        
        // Data rows
        for entry in entries {
            let income = entry.income ?? 0
            let expense = entry.expense ?? 0
            balance = balance + income - expense
            
            if includeInvoice {
                lines.append(csvRow([
                    "\(entry.month)", "\(entry.day)",
                    entry.description, entry.account,
                    entry.reducedTax == true ? "〇" : "",
                    entry.invoiceType?.rawValue ?? "",
                    income > 0 ? "\(income)" : "",
                    expense > 0 ? "\(expense)" : "",
                    "\(balance)"
                ]))
            } else {
                lines.append(csvRow([
                    "\(entry.month)", "\(entry.day)",
                    entry.description, entry.account,
                    income > 0 ? "\(income)" : "",
                    expense > 0 ? "\(expense)" : "",
                    "\(balance)"
                ]))
            }
        }
        
        return bom + lines.joined(separator: "\n")
    }
    
    // MARK: - 預金出納帳 CSV
    
    func exportBankAccountBook(
        metadata: BankAccountBookMetadata,
        entries: [BankAccountBookEntry],
        includeInvoice: Bool = false
    ) -> String {
        var lines: [String] = []
        
        // Metadata rows
        lines.append(csvRow(["銀行名", metadata.bankName]))
        lines.append(csvRow(["本支店名", metadata.branchName]))
        lines.append(csvRow(["口座種類", metadata.accountType]))
        lines.append("") // blank line
        
        // Header
        if includeInvoice {
            lines.append(csvRow(["月", "日", "摘要", "勘定科目", "軽減税率", "インボイス", "入金", "出金", "残高"]))
        } else {
            lines.append(csvRow(["月", "日", "摘要", "勘定科目", "入金", "出金", "残高"]))
        }
        
        var balance = metadata.carryForward
        lines.append(csvRow(includeInvoice
            ? ["", "", "前期より繰越", "", "", "", "", "", "\(balance)"]
            : ["", "", "前期より繰越", "", "", "", "\(balance)"]))
        
        for entry in entries {
            let dep = entry.deposit ?? 0
            let wd = entry.withdrawal ?? 0
            balance = balance + dep - wd
            
            if includeInvoice {
                lines.append(csvRow([
                    "\(entry.month)", "\(entry.day)",
                    entry.description, entry.account,
                    entry.reducedTax == true ? "〇" : "",
                    entry.invoiceType?.rawValue ?? "",
                    dep > 0 ? "\(dep)" : "", wd > 0 ? "\(wd)" : "",
                    "\(balance)"
                ]))
            } else {
                lines.append(csvRow([
                    "\(entry.month)", "\(entry.day)",
                    entry.description, entry.account,
                    dep > 0 ? "\(dep)" : "", wd > 0 ? "\(wd)" : "",
                    "\(balance)"
                ]))
            }
        }
        
        return bom + lines.joined(separator: "\n")
    }
    
    // MARK: - 売掛帳 CSV
    
    func exportAccountsReceivable(
        metadata: AccountsReceivableMetadata,
        entries: [AccountsReceivableEntry]
    ) -> String {
        var lines: [String] = []
        
        lines.append(csvRow(["得意先名", metadata.clientName]))
        lines.append("")
        lines.append(csvRow(["月", "日", "相手科目", "摘要", "数量", "単価", "売上金額", "入金金額", "売掛金残高"]))
        
        var balance = metadata.carryForward
        lines.append(csvRow(["", "", "", "前期より繰越", "", "", "", "", "\(balance)"]))
        
        for entry in entries {
            let sales = entry.salesAmount ?? 0
            let received = entry.receivedAmount ?? 0
            balance = balance + sales - received
            
            lines.append(csvRow([
                "\(entry.month)", "\(entry.day)",
                entry.counterAccount, entry.description,
                entry.quantity.map { "\($0)" } ?? "",
                entry.unitPrice.map { "\($0)" } ?? "",
                sales > 0 ? "\(sales)" : "",
                received > 0 ? "\(received)" : "",
                "\(balance)"
            ]))
        }
        
        return bom + lines.joined(separator: "\n")
    }
    
    // MARK: - 買掛帳 CSV
    
    func exportAccountsPayable(
        metadata: AccountsPayableMetadata,
        entries: [AccountsPayableEntry]
    ) -> String {
        var lines: [String] = []
        
        lines.append(csvRow(["仕入先名", metadata.supplierName]))
        lines.append("")
        lines.append(csvRow(["月", "日", "相手科目", "摘要", "数量", "単価", "仕入金額", "支払金額", "買掛金残高"]))
        
        var balance = metadata.carryForward
        lines.append(csvRow(["", "", "", "前期より繰越", "", "", "", "", "\(balance)"]))
        
        for entry in entries {
            let purchase = entry.purchaseAmount ?? 0
            let payment = entry.paymentAmount ?? 0
            balance = balance + purchase - payment
            
            lines.append(csvRow([
                "\(entry.month)", "\(entry.day)",
                entry.counterAccount, entry.description,
                entry.quantity.map { "\($0)" } ?? "",
                entry.unitPrice.map { "\($0)" } ?? "",
                purchase > 0 ? "\(purchase)" : "",
                payment > 0 ? "\(payment)" : "",
                "\(balance)"
            ]))
        }
        
        return bom + lines.joined(separator: "\n")
    }
    
    // MARK: - 経費帳 CSV
    
    func exportExpenseBook(
        metadata: ExpenseBookMetadata,
        entries: [ExpenseBookEntry],
        includeInvoice: Bool = false
    ) -> String {
        var lines: [String] = []
        
        lines.append(csvRow(["勘定科目名", metadata.accountName]))
        lines.append("")
        
        if includeInvoice {
            lines.append(csvRow(["月", "日", "相手科目", "摘要", "軽減税率", "インボイス", "金額", "金額合計"]))
        } else {
            lines.append(csvRow(["月", "日", "相手科目", "摘要", "金額", "金額合計"]))
        }
        
        var runningTotal = 0
        for entry in entries {
            runningTotal += entry.amount
            if includeInvoice {
                lines.append(csvRow([
                    "\(entry.month)", "\(entry.day)",
                    entry.counterAccount, entry.description,
                    entry.reducedTax == true ? "〇" : "",
                    entry.invoiceType?.rawValue ?? "",
                    "\(entry.amount)", "\(runningTotal)"
                ]))
            } else {
                lines.append(csvRow([
                    "\(entry.month)", "\(entry.day)",
                    entry.counterAccount, entry.description,
                    "\(entry.amount)", "\(runningTotal)"
                ]))
            }
        }
        
        return bom + lines.joined(separator: "\n")
    }
    
    // MARK: - 総勘定元帳 CSV
    
    func exportGeneralLedger(
        metadata: GeneralLedgerMetadata,
        entries: [GeneralLedgerEntry],
        includeInvoice: Bool = false
    ) -> String {
        var lines: [String] = []
        
        lines.append(csvRow(["勘定科目", metadata.accountName,
                              "科目の属性", metadata.accountAttribute?.rawValue ?? ""]))
        lines.append("")
        
        if includeInvoice {
            lines.append(csvRow(["月", "日", "相手科目", "摘要", "軽減税率", "インボイス", "借方", "貸方", "差引残高"]))
        } else {
            lines.append(csvRow(["月", "日", "相手科目", "摘要", "借方", "貸方", "差引残高"]))
        }
        
        var balance = metadata.carryForward
        let isDebitNormal = [AccountCategory.asset, .expense, .costOfSales]
            .contains(metadata.accountAttribute ?? .asset)
        
        lines.append(csvRow(includeInvoice
            ? ["", "", "", "前期より繰越", "", "", "", "", "\(balance)"]
            : ["", "", "", "前期より繰越", "", "", "\(balance)"]))
        
        for entry in entries {
            let debit = entry.debit ?? 0
            let credit = entry.credit ?? 0
            balance = isDebitNormal ? balance + debit - credit : balance - debit + credit
            
            if includeInvoice {
                lines.append(csvRow([
                    "\(entry.month)", "\(entry.day)",
                    entry.counterAccount, entry.description,
                    entry.reducedTax == true ? "〇" : "",
                    entry.invoiceType?.rawValue ?? "",
                    debit > 0 ? "\(debit)" : "",
                    credit > 0 ? "\(credit)" : "",
                    "\(balance)"
                ]))
            } else {
                lines.append(csvRow([
                    "\(entry.month)", "\(entry.day)",
                    entry.counterAccount, entry.description,
                    debit > 0 ? "\(debit)" : "",
                    credit > 0 ? "\(credit)" : "",
                    "\(balance)"
                ]))
            }
        }
        
        return bom + lines.joined(separator: "\n")
    }
    
    // MARK: - 仕訳帳 CSV
    
    func exportJournal(entries: [JournalEntry]) -> String {
        var lines: [String] = []
        lines.append(csvRow(["月", "日", "借方科目", "借方金額", "貸方科目", "貸方金額", "摘要"]))
        
        for entry in entries {
            lines.append(csvRow([
                entry.isCompoundContinuation ? "" : "\(entry.month)",
                entry.isCompoundContinuation ? "" : "\(entry.day)",
                entry.debitAccount ?? "",
                entry.debitAmount.map { "\($0)" } ?? "",
                entry.creditAccount ?? "",
                entry.creditAmount.map { "\($0)" } ?? "",
                entry.description
            ]))
        }
        
        return bom + lines.joined(separator: "\n")
    }
    
    // MARK: - 白色申告用 簡易帳簿 CSV
    
    func exportWhiteTaxBookkeeping(
        metadata: WhiteTaxBookkeepingMetadata,
        entries: [WhiteTaxBookkeepingEntry],
        includeInvoice: Bool = false
    ) -> String {
        var lines: [String] = []
        
        // Header row
        var headers = ["月", "日", "摘要"]
        if includeInvoice {
            headers += ["軽減税率", "インボイス"]
        }
        headers += [
            "売上金額", "雑収入等", "仕入",
            "給料賃金", "外注工賃", "減価償却費", "貸倒金", "地代家賃", "利子割引料",
            "租税公課", "荷造運賃", "水道光熱費", "旅費交通費", "通信費",
            "広告宣伝費", "接待交際費", "損害保険料", "修繕費", "消耗品費", "福利厚生費", "雑費"
        ]
        lines.append(csvRow(headers))
        
        for entry in entries {
            var row = ["\(entry.month)", "\(entry.day)", entry.description]
            if includeInvoice {
                row += [
                    entry.reducedTax == true ? "〇" : "",
                    entry.invoiceType?.rawValue ?? ""
                ]
            }
            row += [
                entry.salesAmount.map { "\($0)" } ?? "",
                entry.miscIncome.map { "\($0)" } ?? "",
                entry.purchases.map { "\($0)" } ?? "",
                entry.salaries.map { "\($0)" } ?? "",
                entry.outsourcing.map { "\($0)" } ?? "",
                entry.depreciation.map { "\($0)" } ?? "",
                entry.badDebts.map { "\($0)" } ?? "",
                entry.rent.map { "\($0)" } ?? "",
                entry.interestDiscount.map { "\($0)" } ?? "",
                entry.taxesDuties.map { "\($0)" } ?? "",
                entry.packingShipping.map { "\($0)" } ?? "",
                entry.utilities.map { "\($0)" } ?? "",
                entry.travelTransport.map { "\($0)" } ?? "",
                entry.communication.map { "\($0)" } ?? "",
                entry.advertising.map { "\($0)" } ?? "",
                entry.entertainment.map { "\($0)" } ?? "",
                entry.insurance.map { "\($0)" } ?? "",
                entry.repairs.map { "\($0)" } ?? "",
                entry.supplies.map { "\($0)" } ?? "",
                entry.welfare.map { "\($0)" } ?? "",
                entry.miscellaneous.map { "\($0)" } ?? ""
            ]
            lines.append(csvRow(row))
        }
        
        return bom + lines.joined(separator: "\n")
    }
    
    // MARK: - Helper
    
    private func csvRow(_ values: [String]) -> String {
        values.map { val in
            if val.contains(",") || val.contains("\"") || val.contains("\n") {
                return "\"\(val.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return val
        }.joined(separator: ",")
    }
}

// MARK: - CSV Import Service

class CSVImportService {
    
    static let shared = CSVImportService()
    
    func parseCSV(_ content: String) -> [[String]] {
        var rows: [[String]] = []
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            rows.append(parseCSVLine(line))
        }
        return rows
    }
    
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }
}

// MARK: - PDF Generation Config

struct PDFLedgerConfig {
    let title: String
    let headers: [String]
    let columnWidths: [CGFloat]  // 各列の幅（ポイント）
    let isLandscape: Bool
    let fontSize: CGFloat
    let headerFontSize: CGFloat
    
    // A4 サイズ
    static let a4Portrait = CGSize(width: 595.28, height: 841.89)
    static let a4Landscape = CGSize(width: 841.89, height: 595.28)
}

// PDFの各台帳設定は LedgerType ごとに PDFLedgerConfig を生成
// 実際のPDF描画は UIGraphicsPDFRenderer を使用
