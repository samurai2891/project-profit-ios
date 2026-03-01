// ============================================================
// LedgerExcelExportService.swift
// Excel(.xlsx)出力サービス - Excel原本と同一書式で出力
// 依存: libxlsxwriter (SwiftPM)
// ============================================================
//
// Package.swift に追加:
//   .package(url: "https://github.com/jmcnamara/libxlsxwriter", from: "1.1.5")
//
// ============================================================

import Foundation
import xlsxwriter  // libxlsxwriter

// MARK: - 共通スタイル定義

class ExcelStyles {
    let workbook: UnsafeMutablePointer<lxw_workbook>
    
    // フォーマット
    lazy var titleFormat: UnsafeMutablePointer<lxw_format> = {
        let fmt = workbook_add_format(workbook)!
        format_set_bold(fmt)
        format_set_font_size(fmt, 14)
        format_set_font_name(fmt, "MS PGothic")
        return fmt
    }()
    
    lazy var headerFormat: UnsafeMutablePointer<lxw_format> = {
        let fmt = workbook_add_format(workbook)!
        format_set_bold(fmt)
        format_set_font_size(fmt, 10)
        format_set_font_name(fmt, "MS PGothic")
        format_set_border(fmt, UInt8(LXW_BORDER_THIN.rawValue))
        format_set_bg_color(fmt, 0xD9E1F2) // 薄い青
        format_set_align(fmt, UInt8(LXW_ALIGN_CENTER.rawValue))
        format_set_align(fmt, UInt8(LXW_ALIGN_VERTICAL_CENTER.rawValue))
        format_set_text_wrap(fmt)
        return fmt
    }()
    
    lazy var subHeaderFormat: UnsafeMutablePointer<lxw_format> = {
        let fmt = workbook_add_format(workbook)!
        format_set_bold(fmt)
        format_set_font_size(fmt, 9)
        format_set_font_name(fmt, "MS PGothic")
        format_set_border(fmt, UInt8(LXW_BORDER_THIN.rawValue))
        format_set_bg_color(fmt, 0xD9E1F2)
        format_set_align(fmt, UInt8(LXW_ALIGN_CENTER.rawValue))
        return fmt
    }()
    
    lazy var dataFormat: UnsafeMutablePointer<lxw_format> = {
        let fmt = workbook_add_format(workbook)!
        format_set_font_size(fmt, 10)
        format_set_font_name(fmt, "MS PGothic")
        format_set_border(fmt, UInt8(LXW_BORDER_THIN.rawValue))
        return fmt
    }()
    
    lazy var numberFormat: UnsafeMutablePointer<lxw_format> = {
        let fmt = workbook_add_format(workbook)!
        format_set_font_size(fmt, 10)
        format_set_font_name(fmt, "MS PGothic")
        format_set_border(fmt, UInt8(LXW_BORDER_THIN.rawValue))
        format_set_num_format(fmt, "#,##0")
        return fmt
    }()
    
    lazy var metaLabelFormat: UnsafeMutablePointer<lxw_format> = {
        let fmt = workbook_add_format(workbook)!
        format_set_font_size(fmt, 10)
        format_set_font_name(fmt, "MS PGothic")
        format_set_bold(fmt)
        return fmt
    }()
    
    lazy var metaValueFormat: UnsafeMutablePointer<lxw_format> = {
        let fmt = workbook_add_format(workbook)!
        format_set_font_size(fmt, 10)
        format_set_font_name(fmt, "MS PGothic")
        format_set_underline(fmt, UInt8(LXW_UNDERLINE_SINGLE.rawValue))
        return fmt
    }()
    
    lazy var carryForwardFormat: UnsafeMutablePointer<lxw_format> = {
        let fmt = workbook_add_format(workbook)!
        format_set_font_size(fmt, 10)
        format_set_font_name(fmt, "MS PGothic")
        format_set_border(fmt, UInt8(LXW_BORDER_THIN.rawValue))
        format_set_italic(fmt)
        return fmt
    }()
    
    init(workbook: UnsafeMutablePointer<lxw_workbook>) {
        self.workbook = workbook
    }
}

// MARK: - Excel Export Service

class LedgerExcelExportService {
    
    static let shared = LedgerExcelExportService()
    
    // MARK: - 現金出納帳
    
    func exportCashBook(
        metadata: CashBookMetadata,
        entries: [CashBookEntry],
        includeInvoice: Bool = false,
        to path: String
    ) {
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let sheetName = includeInvoice ? "現金出納帳（インボイス）" : "現金出納帳"
        let ws = workbook_add_worksheet(wb, sheetName)!
        
        // タイトル
        worksheet_merge_range(ws, 0, 0, 0, includeInvoice ? 8 : 6, "現　金　出　納　帳", styles.titleFormat)
        
        // ヘッダー行
        let headerRow: lxw_row_t = 2
        let subRow: lxw_row_t = 3
        
        if includeInvoice {
            let headers = ["日付", "", "摘　　　　要", "勘 定 科 目", "軽減税率", "インボイス", "入　　金", "出　　金", "残   高"]
            for (i, h) in headers.enumerated() {
                worksheet_write_string(ws, headerRow, lxw_col_t(i), h, styles.headerFormat)
            }
            worksheet_write_string(ws, subRow, 0, "月", styles.subHeaderFormat)
            worksheet_write_string(ws, subRow, 1, "日", styles.subHeaderFormat)
        } else {
            let headers = ["日付", "", "摘　　　　要", "勘 定 科 目", "入　　金", "出　　金", "残   高"]
            for (i, h) in headers.enumerated() {
                worksheet_write_string(ws, headerRow, lxw_col_t(i), h, styles.headerFormat)
            }
            worksheet_write_string(ws, subRow, 0, "月", styles.subHeaderFormat)
            worksheet_write_string(ws, subRow, 1, "日", styles.subHeaderFormat)
        }
        
        // 繰越行
        let dataStart: lxw_row_t = 4
        let balCol: lxw_col_t = includeInvoice ? 8 : 6
        worksheet_write_string(ws, dataStart, 2, "前期より繰越", styles.carryForwardFormat)
        worksheet_write_number(ws, dataStart, balCol, Double(metadata.carryForward), styles.numberFormat)
        
        // データ行（数式で残高計算）
        for (i, entry) in entries.enumerated() {
            let row = dataStart + lxw_row_t(i) + 1
            let incCol: lxw_col_t = includeInvoice ? 6 : 4
            let expCol: lxw_col_t = includeInvoice ? 7 : 5
            
            worksheet_write_number(ws, row, 0, Double(entry.month), styles.dataFormat)
            worksheet_write_number(ws, row, 1, Double(entry.day), styles.dataFormat)
            worksheet_write_string(ws, row, 2, entry.description, styles.dataFormat)
            worksheet_write_string(ws, row, 3, entry.account, styles.dataFormat)
            
            if includeInvoice {
                if entry.reducedTax == true {
                    worksheet_write_string(ws, row, 4, "〇", styles.dataFormat)
                }
                if let inv = entry.invoiceType {
                    worksheet_write_string(ws, row, 5, inv.rawValue, styles.dataFormat)
                }
            }
            
            if let income = entry.income, income > 0 {
                worksheet_write_number(ws, row, incCol, Double(income), styles.numberFormat)
            }
            if let expense = entry.expense, expense > 0 {
                worksheet_write_number(ws, row, expCol, Double(expense), styles.numberFormat)
            }
            
            // 残高数式: =+入金列+前行残高-出金列
            let incLetter = columnLetter(incCol)
            let expLetter = columnLetter(expCol)
            let balLetter = columnLetter(balCol)
            let formula = "=+\(incLetter)\(row+1)+\(balLetter)\(row)-\(expLetter)\(row+1)"
            worksheet_write_formula(ws, row, balCol, formula, styles.numberFormat)
        }
        
        // 列幅設定
        worksheet_set_column(ws, 0, 0, 4, nil)   // 月
        worksheet_set_column(ws, 1, 1, 4, nil)   // 日
        worksheet_set_column(ws, 2, 2, 28, nil)  // 摘要
        worksheet_set_column(ws, 3, 3, 14, nil)  // 勘定科目
        if includeInvoice {
            worksheet_set_column(ws, 4, 4, 8, nil)
            worksheet_set_column(ws, 5, 5, 10, nil)
            worksheet_set_column(ws, 6, 7, 12, nil)
            worksheet_set_column(ws, 8, 8, 12, nil)
        } else {
            worksheet_set_column(ws, 4, 5, 12, nil)
            worksheet_set_column(ws, 6, 6, 12, nil)
        }
        
        // 印刷設定
        worksheet_set_landscape(ws)
        worksheet_set_paper(ws, 9)  // A4
        worksheet_print_area(ws, 0, 0, dataStart + lxw_row_t(entries.count), balCol)
        
        // 勘定科目シート追加
        addAccountMasterSheet(workbook: wb, styles: styles)
        
        workbook_close(wb)
    }
    
    // MARK: - 預金出納帳
    
    func exportBankAccountBook(
        metadata: BankAccountBookMetadata,
        entries: [BankAccountBookEntry],
        includeInvoice: Bool = false,
        to path: String
    ) {
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let sheetName = includeInvoice ? "預金出納帳（インボイス）" : "預金出納帳"
        let ws = workbook_add_worksheet(wb, sheetName)!
        
        // タイトル
        worksheet_merge_range(ws, 0, 0, 0, includeInvoice ? 8 : 6, "預　金　出　納　帳", styles.titleFormat)
        
        // メタデータ
        worksheet_write_string(ws, 1, 0, "銀行名", styles.metaLabelFormat)
        worksheet_write_string(ws, 1, 2, metadata.bankName, styles.metaValueFormat)
        worksheet_write_string(ws, 2, 0, "本支店名", styles.metaLabelFormat)
        worksheet_write_string(ws, 2, 2, metadata.branchName, styles.metaValueFormat)
        worksheet_write_string(ws, 3, 0, "口座種類", styles.metaLabelFormat)
        worksheet_write_string(ws, 3, 2, metadata.accountType, styles.metaValueFormat)
        
        let noteCol: lxw_col_t = includeInvoice ? 9 : 7
        worksheet_write_string(ws, 3, noteCol, "※当座預金・普通預金・定期預金等", styles.dataFormat)
        
        // ヘッダー (Row 6-7)
        let headerRow: lxw_row_t = 6
        if includeInvoice {
            let headers = ["日付", "", "摘　　　　要", "勘 定 科 目", "軽減税率", "インボイス", "入　　金", "出　　金", "残   高"]
            for (i, h) in headers.enumerated() {
                worksheet_write_string(ws, headerRow, lxw_col_t(i), h, styles.headerFormat)
            }
        } else {
            let headers = ["日付", "", "摘　　　　要", "勘 定 科 目", "入　　金", "出　　金", "残   高"]
            for (i, h) in headers.enumerated() {
                worksheet_write_string(ws, headerRow, lxw_col_t(i), h, styles.headerFormat)
            }
        }
        worksheet_write_string(ws, headerRow + 1, 0, "月", styles.subHeaderFormat)
        worksheet_write_string(ws, headerRow + 1, 1, "日", styles.subHeaderFormat)
        
        // 繰越 + データ行（現金出納帳と同一ロジック）
        let dataStart: lxw_row_t = 8
        let balCol: lxw_col_t = includeInvoice ? 8 : 6
        worksheet_write_string(ws, dataStart, 2, "前期より繰越", styles.carryForwardFormat)
        worksheet_write_number(ws, dataStart, balCol, Double(metadata.carryForward), styles.numberFormat)
        
        for (i, entry) in entries.enumerated() {
            let row = dataStart + lxw_row_t(i) + 1
            let depCol: lxw_col_t = includeInvoice ? 6 : 4
            let wdCol: lxw_col_t = includeInvoice ? 7 : 5
            
            worksheet_write_number(ws, row, 0, Double(entry.month), styles.dataFormat)
            worksheet_write_number(ws, row, 1, Double(entry.day), styles.dataFormat)
            worksheet_write_string(ws, row, 2, entry.description, styles.dataFormat)
            worksheet_write_string(ws, row, 3, entry.account, styles.dataFormat)
            
            if includeInvoice {
                if entry.reducedTax == true {
                    worksheet_write_string(ws, row, 4, "〇", styles.dataFormat)
                }
                if let inv = entry.invoiceType {
                    worksheet_write_string(ws, row, 5, inv.rawValue, styles.dataFormat)
                }
            }
            
            if let dep = entry.deposit, dep > 0 {
                worksheet_write_number(ws, row, depCol, Double(dep), styles.numberFormat)
            }
            if let wd = entry.withdrawal, wd > 0 {
                worksheet_write_number(ws, row, wdCol, Double(wd), styles.numberFormat)
            }
            
            let depLetter = columnLetter(depCol)
            let wdLetter = columnLetter(wdCol)
            let balLetter = columnLetter(balCol)
            let formula = "=+\(depLetter)\(row+1)+\(balLetter)\(row)-\(wdLetter)\(row+1)"
            worksheet_write_formula(ws, row, balCol, formula, styles.numberFormat)
        }
        
        // 列幅・印刷設定
        worksheet_set_column(ws, 0, 0, 4, nil)
        worksheet_set_column(ws, 1, 1, 4, nil)
        worksheet_set_column(ws, 2, 2, 28, nil)
        worksheet_set_column(ws, 3, 3, 14, nil)
        worksheet_set_landscape(ws)
        worksheet_set_paper(ws, 9)
        
        addAccountMasterSheet(workbook: wb, styles: styles)
        workbook_close(wb)
    }
    
    // MARK: - 売掛帳
    
    func exportAccountsReceivable(
        metadata: AccountsReceivableMetadata,
        entries: [AccountsReceivableEntry],
        to path: String
    ) {
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = workbook_add_worksheet(wb, "売掛帳")!
        
        worksheet_merge_range(ws, 0, 0, 0, 8, "売　掛　帳", styles.titleFormat)
        worksheet_write_string(ws, 1, 0, "得意先名", styles.metaLabelFormat)
        worksheet_write_string(ws, 1, 3, metadata.clientName, styles.metaValueFormat)
        
        let headers = ["日付", "", "相手科目", "摘　　　　要", "数量", "単価", "売上金額", "入金金額", "売掛金残高"]
        for (i, h) in headers.enumerated() {
            worksheet_write_string(ws, 3, lxw_col_t(i), h, styles.headerFormat)
        }
        worksheet_write_string(ws, 4, 0, "月", styles.subHeaderFormat)
        worksheet_write_string(ws, 4, 1, "日", styles.subHeaderFormat)
        
        worksheet_write_string(ws, 5, 3, "前期より繰越", styles.carryForwardFormat)
        worksheet_write_number(ws, 5, 8, Double(metadata.carryForward), styles.numberFormat)
        
        for (i, entry) in entries.enumerated() {
            let row: lxw_row_t = 6 + lxw_row_t(i)
            worksheet_write_number(ws, row, 0, Double(entry.month), styles.dataFormat)
            worksheet_write_number(ws, row, 1, Double(entry.day), styles.dataFormat)
            worksheet_write_string(ws, row, 2, entry.counterAccount, styles.dataFormat)
            worksheet_write_string(ws, row, 3, entry.description, styles.dataFormat)
            if let q = entry.quantity { worksheet_write_number(ws, row, 4, Double(q), styles.numberFormat) }
            if let u = entry.unitPrice { worksheet_write_number(ws, row, 5, Double(u), styles.numberFormat) }
            if let s = entry.salesAmount, s > 0 { worksheet_write_number(ws, row, 6, Double(s), styles.numberFormat) }
            if let r = entry.receivedAmount, r > 0 { worksheet_write_number(ws, row, 7, Double(r), styles.numberFormat) }
            
            let formula = "=+G\(row+1)+I\(row)-H\(row+1)"
            worksheet_write_formula(ws, row, 8, formula, styles.numberFormat)
        }
        
        worksheet_set_column(ws, 0, 0, 4, nil)
        worksheet_set_column(ws, 1, 1, 4, nil)
        worksheet_set_column(ws, 2, 2, 12, nil)
        worksheet_set_column(ws, 3, 3, 24, nil)
        worksheet_set_column(ws, 4, 8, 12, nil)
        worksheet_set_landscape(ws)
        worksheet_set_paper(ws, 9)
        
        addAccountMasterSheet(workbook: wb, styles: styles)
        workbook_close(wb)
    }
    
    // MARK: - 買掛帳
    
    func exportAccountsPayable(
        metadata: AccountsPayableMetadata,
        entries: [AccountsPayableEntry],
        to path: String
    ) {
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = workbook_add_worksheet(wb, "買掛帳")!
        
        worksheet_merge_range(ws, 0, 0, 0, 8, "買　掛　帳", styles.titleFormat)
        worksheet_write_string(ws, 1, 0, "仕入先名", styles.metaLabelFormat)
        worksheet_write_string(ws, 1, 3, metadata.supplierName, styles.metaValueFormat)
        
        let headers = ["日付", "", "相手科目", "摘　　　　要", "数量", "単価", "仕入金額", "支払金額", "買掛金残高"]
        for (i, h) in headers.enumerated() {
            worksheet_write_string(ws, 3, lxw_col_t(i), h, styles.headerFormat)
        }
        worksheet_write_string(ws, 4, 0, "月", styles.subHeaderFormat)
        worksheet_write_string(ws, 4, 1, "日", styles.subHeaderFormat)
        
        worksheet_write_string(ws, 5, 3, "前期より繰越", styles.carryForwardFormat)
        worksheet_write_number(ws, 5, 8, Double(metadata.carryForward), styles.numberFormat)
        
        for (i, entry) in entries.enumerated() {
            let row: lxw_row_t = 6 + lxw_row_t(i)
            worksheet_write_number(ws, row, 0, Double(entry.month), styles.dataFormat)
            worksheet_write_number(ws, row, 1, Double(entry.day), styles.dataFormat)
            worksheet_write_string(ws, row, 2, entry.counterAccount, styles.dataFormat)
            worksheet_write_string(ws, row, 3, entry.description, styles.dataFormat)
            if let q = entry.quantity { worksheet_write_number(ws, row, 4, Double(q), styles.numberFormat) }
            if let u = entry.unitPrice { worksheet_write_number(ws, row, 5, Double(u), styles.numberFormat) }
            if let p = entry.purchaseAmount, p > 0 { worksheet_write_number(ws, row, 6, Double(p), styles.numberFormat) }
            if let pay = entry.paymentAmount, pay > 0 { worksheet_write_number(ws, row, 7, Double(pay), styles.numberFormat) }
            
            // 残高 = 前行残高 + 仕入金額 - 支払金額
            let formula = "=+G\(row+1)+I\(row)-H\(row+1)"
            worksheet_write_formula(ws, row, 8, formula, styles.numberFormat)
        }
        
        worksheet_set_landscape(ws)
        worksheet_set_paper(ws, 9)
        addAccountMasterSheet(workbook: wb, styles: styles)
        workbook_close(wb)
    }
    
    // MARK: - 総勘定元帳
    
    func exportGeneralLedger(
        metadata: GeneralLedgerMetadata,
        entries: [GeneralLedgerEntry],
        includeInvoice: Bool = false,
        to path: String
    ) {
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let sheetName = includeInvoice ? "総勘定元帳（インボイス）" : "総勘定元帳"
        let ws = workbook_add_worksheet(wb, sheetName)!
        
        let balCol: lxw_col_t = includeInvoice ? 8 : 6
        
        // 属性ラベル
        worksheet_write_string(ws, 0, balCol - 1, "科目の属性：", styles.metaLabelFormat)
        worksheet_write_string(ws, 0, balCol, metadata.accountAttribute?.rawValue ?? "資産", styles.metaValueFormat)
        
        worksheet_merge_range(ws, 1, 0, 1, balCol, "総勘定元帳", styles.titleFormat)
        worksheet_write_string(ws, 2, 0, "勘定科目", styles.metaLabelFormat)
        worksheet_write_string(ws, 2, 3, metadata.accountName, styles.metaValueFormat)
        
        // ヘッダー
        if includeInvoice {
            let headers = ["日付", "", "相手科目", "摘　　　　要", "軽減\n税率", "イン\nボイス", "借方", "貸方", "差引残高"]
            for (i, h) in headers.enumerated() {
                worksheet_write_string(ws, 4, lxw_col_t(i), h, styles.headerFormat)
            }
        } else {
            let headers = ["日付", "", "相手科目", "摘　　　　要", "借方", "貸方", "差引残高"]
            for (i, h) in headers.enumerated() {
                worksheet_write_string(ws, 4, lxw_col_t(i), h, styles.headerFormat)
            }
        }
        worksheet_write_string(ws, 5, 0, "月", styles.subHeaderFormat)
        worksheet_write_string(ws, 5, 1, "日", styles.subHeaderFormat)
        
        // 繰越
        worksheet_write_string(ws, 6, 3, "前期より繰越", styles.carryForwardFormat)
        worksheet_write_number(ws, 6, balCol, Double(metadata.carryForward), styles.numberFormat)
        
        // データ行 + 属性別残高数式
        let debitCol: lxw_col_t = includeInvoice ? 6 : 4
        let creditCol: lxw_col_t = includeInvoice ? 7 : 5
        let attrCell = "\(columnLetter(balCol))1"  // 属性セル参照
        
        for (i, entry) in entries.enumerated() {
            let row: lxw_row_t = 7 + lxw_row_t(i)
            worksheet_write_number(ws, row, 0, Double(entry.month), styles.dataFormat)
            worksheet_write_number(ws, row, 1, Double(entry.day), styles.dataFormat)
            worksheet_write_string(ws, row, 2, entry.counterAccount, styles.dataFormat)
            worksheet_write_string(ws, row, 3, entry.description, styles.dataFormat)
            
            if includeInvoice {
                if entry.reducedTax == true {
                    worksheet_write_string(ws, row, 4, "〇", styles.dataFormat)
                }
                if let inv = entry.invoiceType {
                    worksheet_write_string(ws, row, 5, inv.rawValue, styles.dataFormat)
                }
            }
            
            if let d = entry.debit, d > 0 {
                worksheet_write_number(ws, row, debitCol, Double(d), styles.numberFormat)
            }
            if let c = entry.credit, c > 0 {
                worksheet_write_number(ws, row, creditCol, Double(c), styles.numberFormat)
            }
            
            // 属性に応じた残高計算: IF(OR(属性="資産",属性="費用"), 借方-貸方+前行, 前行+貸方-借方)
            let dL = columnLetter(debitCol)
            let cL = columnLetter(creditCol)
            let bL = columnLetter(balCol)
            let formula = "=+IF(OR($\(columnLetter(balCol))$1=\"資産\",$\(columnLetter(balCol))$1=\"費用\"),\(dL)\(row+1)-\(cL)\(row+1)+\(bL)\(row),\(bL)\(row)+\(cL)\(row+1)-\(dL)\(row+1))"
            worksheet_write_formula(ws, row, balCol, formula, styles.numberFormat)
        }
        
        worksheet_set_landscape(ws)
        worksheet_set_paper(ws, 9)
        addAccountMasterSheet(workbook: wb, styles: styles)
        workbook_close(wb)
    }
    
    // MARK: - 仕訳帳
    
    func exportJournal(
        entries: [JournalEntry],
        to path: String
    ) {
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = workbook_add_worksheet(wb, "仕訳帳")!
        
        worksheet_merge_range(ws, 0, 0, 0, 6, "仕　訳　帳", styles.titleFormat)
        
        let headers = ["日付", "", "借方科目", "借方金額", "貸方科目", "貸方金額", "摘　　　　要"]
        for (i, h) in headers.enumerated() {
            worksheet_write_string(ws, 2, lxw_col_t(i), h, styles.headerFormat)
        }
        worksheet_write_string(ws, 3, 0, "月", styles.subHeaderFormat)
        worksheet_write_string(ws, 3, 1, "日", styles.subHeaderFormat)
        
        for (i, entry) in entries.enumerated() {
            let row: lxw_row_t = 4 + lxw_row_t(i)
            
            if !entry.isCompoundContinuation {
                worksheet_write_number(ws, row, 0, Double(entry.month), styles.dataFormat)
                worksheet_write_number(ws, row, 1, Double(entry.day), styles.dataFormat)
            }
            if let da = entry.debitAccount {
                worksheet_write_string(ws, row, 2, da, styles.dataFormat)
            }
            if let dam = entry.debitAmount {
                worksheet_write_number(ws, row, 3, Double(dam), styles.numberFormat)
            }
            if let ca = entry.creditAccount {
                worksheet_write_string(ws, row, 4, ca, styles.dataFormat)
            }
            if let cam = entry.creditAmount {
                worksheet_write_number(ws, row, 5, Double(cam), styles.numberFormat)
            }
            worksheet_write_string(ws, row, 6, entry.description, styles.dataFormat)
        }
        
        worksheet_set_column(ws, 0, 0, 4, nil)
        worksheet_set_column(ws, 1, 1, 4, nil)
        worksheet_set_column(ws, 2, 2, 14, nil)
        worksheet_set_column(ws, 3, 3, 12, nil)
        worksheet_set_column(ws, 4, 4, 14, nil)
        worksheet_set_column(ws, 5, 5, 12, nil)
        worksheet_set_column(ws, 6, 6, 28, nil)
        worksheet_set_landscape(ws)
        worksheet_set_paper(ws, 9)
        
        addAccountMasterSheet(workbook: wb, styles: styles)
        workbook_close(wb)
    }
    
    // MARK: - 勘定科目マスターシート（共通）
    
    private func addAccountMasterSheet(workbook: UnsafeMutablePointer<lxw_workbook>, styles: ExcelStyles) {
        let ws = workbook_add_worksheet(workbook, "勘定科目")!
        
        worksheet_write_string(ws, 0, 1, "現金出納帳/預金出納帳", styles.headerFormat)
        worksheet_write_string(ws, 2, 1, "区分", styles.headerFormat)
        worksheet_write_string(ws, 2, 2, "勘定科目", styles.headerFormat)
        
        let accounts = AccountMaster.all
        var row: lxw_row_t = 3
        var lastCategory = ""
        
        for item in accounts {
            let catName = item.category.rawValue
            if catName != lastCategory {
                worksheet_write_string(ws, row, 1, catName, styles.dataFormat)
                lastCategory = catName
            }
            worksheet_write_string(ws, row, 2, item.name, styles.dataFormat)
            row += 1
        }
        
        worksheet_set_column(ws, 1, 1, 10, nil)
        worksheet_set_column(ws, 2, 2, 16, nil)
    }
    
    // MARK: - ユーティリティ
    
    private func columnLetter(_ col: lxw_col_t) -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        if col < 26 {
            return String(letters[letters.index(letters.startIndex, offsetBy: Int(col))])
        }
        let first = col / 26 - 1
        let second = col % 26
        return String(letters[letters.index(letters.startIndex, offsetBy: Int(first))]) +
               String(letters[letters.index(letters.startIndex, offsetBy: Int(second))])
    }
    
    // MARK: - 汎用エクスポート（LedgerTypeで分岐）
    
    func exportToExcel(
        ledgerType: LedgerType,
        metadata: Any,
        entries: [Any],
        to path: String
    ) {
        switch ledgerType {
        case .cashBook:
            exportCashBook(metadata: metadata as! CashBookMetadata,
                          entries: entries as! [CashBookEntry],
                          includeInvoice: false, to: path)
        case .cashBookInvoice:
            exportCashBook(metadata: metadata as! CashBookMetadata,
                          entries: entries as! [CashBookEntry],
                          includeInvoice: true, to: path)
        case .bankAccountBook:
            exportBankAccountBook(metadata: metadata as! BankAccountBookMetadata,
                                 entries: entries as! [BankAccountBookEntry],
                                 includeInvoice: false, to: path)
        case .bankAccountBookInvoice:
            exportBankAccountBook(metadata: metadata as! BankAccountBookMetadata,
                                 entries: entries as! [BankAccountBookEntry],
                                 includeInvoice: true, to: path)
        case .accountsReceivable:
            exportAccountsReceivable(metadata: metadata as! AccountsReceivableMetadata,
                                    entries: entries as! [AccountsReceivableEntry],
                                    to: path)
        case .accountsPayable:
            exportAccountsPayable(metadata: metadata as! AccountsPayableMetadata,
                                 entries: entries as! [AccountsPayableEntry],
                                 to: path)
        case .generalLedger:
            exportGeneralLedger(metadata: metadata as! GeneralLedgerMetadata,
                               entries: entries as! [GeneralLedgerEntry],
                               includeInvoice: false, to: path)
        case .generalLedgerInvoice:
            exportGeneralLedger(metadata: metadata as! GeneralLedgerMetadata,
                               entries: entries as! [GeneralLedgerEntry],
                               includeInvoice: true, to: path)
        case .journal:
            exportJournal(entries: entries as! [JournalEntry], to: path)
        default:
            break // 他台帳は同パターンで実装
        }
    }
}

// MARK: - 使い方

/*
 // 1. SwiftPM に追加
 // Package.swift:
 //   dependencies: [
 //     .package(url: "https://github.com/jmcnamara/libxlsxwriter", from: "1.1.5")
 //   ]
 
 // 2. エクスポート
 let outputPath = FileManager.default.temporaryDirectory
     .appendingPathComponent("現金出納帳.xlsx").path
 
 LedgerExcelExportService.shared.exportCashBook(
     metadata: CashBookMetadata(carryForward: 100000),
     entries: myEntries,
     includeInvoice: false,
     to: outputPath
 )
 
 // 3. シェア
 let url = URL(fileURLWithPath: outputPath)
 let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
 present(activityVC, animated: true)
*/
