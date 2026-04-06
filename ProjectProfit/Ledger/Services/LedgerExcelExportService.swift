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

enum LedgerTemplateAsset: String, CaseIterable {
    case bsPlAnalysisSample = "project-profit-ios_bs_pl_analysis_template"
    case consolidatedSpreadsheetSample = "project-profit-ios_templates_consolidated_spreadsheet"
    case balanceSheet = "project-profit-ios_balance_sheet_template"
    case profitLoss = "project-profit-ios_profit_loss_template"
    case cashBook = "project-profit-ios_cash_book_template"
    case cashBookInvoice = "project-profit-ios_cash_book_invoice_template"
    case bankAccountBook = "project-profit-ios_bank_account_book_template"
    case bankAccountBookInvoice = "project-profit-ios_bank_account_book_invoice_template"
    case expenseBook = "project-profit-ios_expense_book_template"
    case expenseBookInvoice = "project-profit-ios_expense_book_invoice_template"
    case generalLedger = "project-profit-ios_general_ledger_template"
    case generalLedgerInvoice = "project-profit-ios_general_ledger_invoice_template"
    case whiteTaxBookkeeping = "project-profit-ios_white_tax_bookkeeping_template"
    case whiteTaxBookkeepingInvoice = "project-profit-ios_white_tax_bookkeeping_invoice_template"
    case accountsReceivable = "project-profit-ios_accounts_receivable_template"
    case accountsPayable = "project-profit-ios_accounts_payable_template"
    case journal = "project-profit-ios_journal_template"
    case trialBalance = "project-profit-ios_trial_balance_template"
    case fixedAssetRegister = "project-profit-ios_fixed_asset_register_template"
    case fixedAssetDepreciation = "project-profit-ios_fixed_asset_depreciation_template"
    case transportationExpense = "project-profit-ios_transportation_expense_template"

    var fileName: String { "\(rawValue).xlsx" }

    var bundleSubdirectory: String {
        switch self {
        case .bsPlAnalysisSample, .consolidatedSpreadsheetSample:
            return "excel_templates"
        case .balanceSheet, .profitLoss:
            return "excel_templates/reports"
        default:
            return "excel_templates/ledgers"
        }
    }

    var repoRelativeDirectory: String {
        switch self {
        case .bsPlAnalysisSample, .consolidatedSpreadsheetSample:
            return "excel_templates"
        case .balanceSheet, .profitLoss:
            return "excel_templates/reports"
        default:
            return "excel_templates/ledgers"
        }
    }
}

enum LedgerTemplateAssetLocator {
    static func url(
        for asset: LedgerTemplateAsset,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> URL? {
        if let bundledURL = bundle.url(
            forResource: asset.rawValue,
            withExtension: "xlsx",
            subdirectory: asset.bundleSubdirectory
        ) {
            return bundledURL
        }

        let repoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Services
            .deletingLastPathComponent()   // Ledger
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(asset.repoRelativeDirectory, isDirectory: true)
            .appendingPathComponent(asset.fileName, isDirectory: false)

        return fileManager.fileExists(atPath: repoURL.path) ? repoURL : nil
    }
}

struct LedgerWorkbookTemplateDescriptor: Equatable {
    let ledgerType: LedgerType
    let asset: LedgerTemplateAsset
    let formSheetName: String
    let workbookTitle: String
    let worksheetName: String
    let titleRow: Int
    let titleEndColumn: Int
    let headerRows: ClosedRange<Int>
    let dataStartRow: Int
    let columnHeaders: [String]
    let subheaders: [Int: String]
    let columnWidths: [Double]
    let auxiliarySheets: [LedgerAuxiliarySheet]
    let printSettings: LedgerPrintSettings
}

enum LedgerAuxiliarySheet: Equatable {
    case accountMaster
    case entryGuide
}

struct LedgerPrintSettings: Equatable {
    let isLandscape: Bool
    let paperSize: UInt8
}

enum ReportWorkbookTemplateID: String, CaseIterable {
    case profitLoss
    case balanceSheet
    case trialBalance
    case journal
    case ledger
    case fixedAssets
}

struct ReportWorkbookTemplateDescriptor: Equatable {
    let id: ReportWorkbookTemplateID
    let asset: LedgerTemplateAsset?
    let worksheetName: String
    let workbookTitle: String
    let subtitle: String?
    let titleRow: Int
    let titleEndColumn: Int
    let headerRows: ClosedRange<Int>
    let dataStartRow: Int
    let columnHeaders: [String]
    let columnWidths: [Double]
    let auxiliarySheets: [LedgerAuxiliarySheet]
    let printSettings: LedgerPrintSettings
}

// MARK: - 共通スタイル定義

final class ExcelStyles {
    let workbook: UnsafeMutablePointer<lxw_workbook>
    
    // フォーマット
    lazy var titleBandFormat: UnsafeMutablePointer<lxw_format> = {
        let fmt = workbook_add_format(workbook)!
        format_set_bold(fmt)
        format_set_font_size(fmt, 14)
        format_set_font_name(fmt, "MS PGothic")
        return fmt
    }()
    
    lazy var primaryHeaderFormat: UnsafeMutablePointer<lxw_format> = {
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
    
    lazy var secondaryHeaderFormat: UnsafeMutablePointer<lxw_format> = {
        let fmt = workbook_add_format(workbook)!
        format_set_bold(fmt)
        format_set_font_size(fmt, 9)
        format_set_font_name(fmt, "MS PGothic")
        format_set_border(fmt, UInt8(LXW_BORDER_THIN.rawValue))
        format_set_bg_color(fmt, 0xD9E1F2)
        format_set_align(fmt, UInt8(LXW_ALIGN_CENTER.rawValue))
        return fmt
    }()
    
    lazy var bodyTextFormat: UnsafeMutablePointer<lxw_format> = {
        let fmt = workbook_add_format(workbook)!
        format_set_font_size(fmt, 10)
        format_set_font_name(fmt, "MS PGothic")
        format_set_border(fmt, UInt8(LXW_BORDER_THIN.rawValue))
        return fmt
    }()
    
    lazy var amountFormat: UnsafeMutablePointer<lxw_format> = {
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

    lazy var sectionHeaderFormat: UnsafeMutablePointer<lxw_format> = {
        let fmt = workbook_add_format(workbook)!
        format_set_font_size(fmt, 10)
        format_set_font_name(fmt, "MS PGothic")
        format_set_bold(fmt)
        format_set_border(fmt, UInt8(LXW_BORDER_THIN.rawValue))
        format_set_bg_color(fmt, 0xE2F0D9)
        return fmt
    }()

    lazy var subtotalFormat: UnsafeMutablePointer<lxw_format> = {
        let fmt = workbook_add_format(workbook)!
        format_set_font_size(fmt, 10)
        format_set_font_name(fmt, "MS PGothic")
        format_set_bold(fmt)
        format_set_border(fmt, UInt8(LXW_BORDER_THIN.rawValue))
        format_set_bg_color(fmt, 0xFCE4D6)
        format_set_num_format(fmt, "#,##0")
        return fmt
    }()
    
    init(workbook: UnsafeMutablePointer<lxw_workbook>) {
        self.workbook = workbook
    }

    var titleFormat: UnsafeMutablePointer<lxw_format> { titleBandFormat }
    var headerFormat: UnsafeMutablePointer<lxw_format> { primaryHeaderFormat }
    var subHeaderFormat: UnsafeMutablePointer<lxw_format> { secondaryHeaderFormat }
    var dataFormat: UnsafeMutablePointer<lxw_format> { bodyTextFormat }
    var numberFormat: UnsafeMutablePointer<lxw_format> { amountFormat }
}

// MARK: - Excel Export Service

final class LedgerExcelExportService {
    
    static let shared = LedgerExcelExportService()

    static func reportTemplateDescriptor(for target: ReportWorkbookTemplateID) -> ReportWorkbookTemplateDescriptor? {
        switch target {
        case .profitLoss:
            return .init(
                id: .profitLoss,
                asset: .profitLoss,
                worksheetName: "損益計算書",
                workbookTitle: "損益計算書",
                subtitle: "※ 単年度出力用。収入と費用を分けて表示。",
                titleRow: 0,
                titleEndColumn: 2,
                headerRows: 3...3,
                dataStartRow: 4,
                columnHeaders: ["科目", "収入", "費用"],
                columnWidths: [34, 16, 16],
                auxiliarySheets: [.entryGuide],
                printSettings: .init(isLandscape: false, paperSize: 9)
            )
        case .balanceSheet:
            return .init(
                id: .balanceSheet,
                asset: .balanceSheet,
                worksheetName: "貸借対照表",
                workbookTitle: "貸借対照表",
                subtitle: "※ 単年度出力用。資産の部と負債・純資産の部を左右に分けて表示。",
                titleRow: 0,
                titleEndColumn: 4,
                headerRows: 3...3,
                dataStartRow: 4,
                columnHeaders: ["資産の部", "金額", "", "負債・純資産の部", "金額"],
                columnWidths: [28, 16, 4, 28, 16],
                auxiliarySheets: [.entryGuide],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .trialBalance:
            return .init(
                id: .trialBalance,
                asset: .trialBalance,
                worksheetName: "残高試算表",
                workbookTitle: "残高試算表",
                subtitle: nil,
                titleRow: 0,
                titleEndColumn: 5,
                headerRows: 8...8,
                dataStartRow: 9,
                columnHeaders: ["コード", "勘定科目", "区分", "借方", "貸方", "残高"],
                columnWidths: [10, 20, 10, 12, 12, 12],
                auxiliarySheets: [.accountMaster, .entryGuide],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .journal:
            return .init(
                id: .journal,
                asset: .journal,
                worksheetName: "仕訳帳",
                workbookTitle: "仕訳帳",
                subtitle: nil,
                titleRow: 0,
                titleEndColumn: 6,
                headerRows: 8...8,
                dataStartRow: 9,
                columnHeaders: ["月", "日", "借方科目", "借方金額", "貸方科目", "貸方金額", "摘要"],
                columnWidths: [7, 7, 18, 14, 18, 14, 28],
                auxiliarySheets: [.accountMaster, .entryGuide],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .ledger:
            return .init(
                id: .ledger,
                asset: .generalLedger,
                worksheetName: "総勘定元帳",
                workbookTitle: "総勘定元帳（通常版）",
                subtitle: nil,
                titleRow: 0,
                titleEndColumn: 6,
                headerRows: 9...9,
                dataStartRow: 10,
                columnHeaders: ["月", "日", "相手科目", "摘要", "借方", "貸方", "差引残高"],
                columnWidths: [8, 8, 18, 26, 14, 14, 16],
                auxiliarySheets: [.accountMaster, .entryGuide],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .fixedAssets:
            return .init(
                id: .fixedAssets,
                asset: .fixedAssetDepreciation,
                worksheetName: "固定資産台帳",
                workbookTitle: "固定資産台帳 兼 減価償却計算表",
                subtitle: nil,
                titleRow: 0,
                titleEndColumn: 20,
                headerRows: 8...8,
                dataStartRow: 9,
                columnHeaders: ["勘定科目", "資産コード", "資産名", "資産の種類", "状態", "数量", "取得日", "取得価額", "償却方法", "耐用年数", "償却率", "償却月数", "期首帳簿価額", "期中増減", "減価償却費", "特別償却費", "償却費合計", "事業専用割合", "必要経費算入額", "本年末残高", "摘要"],
                columnWidths: [14, 12, 18, 14, 10, 8, 12, 14, 12, 10, 10, 10, 14, 12, 14, 14, 14, 12, 14, 14, 18],
                auxiliarySheets: [.entryGuide],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        }
    }

    static func templateDescriptor(for ledgerType: LedgerType) -> LedgerWorkbookTemplateDescriptor? {
        switch ledgerType {
        case .cashBook:
            return .init(
                ledgerType: ledgerType,
                asset: .cashBook,
                formSheetName: "L01_CashStd_Form",
                workbookTitle: "現　金　出　納　帳",
                worksheetName: "現金出納帳",
                titleRow: 0,
                titleEndColumn: 6,
                headerRows: 2...3,
                dataStartRow: 4,
                columnHeaders: ["日付", "", "摘　　　　要", "勘 定 科 目", "入　　金", "出　　金", "残   高"],
                subheaders: [0: "月", 1: "日"],
                columnWidths: [4, 4, 28, 14, 12, 12, 12],
                auxiliarySheets: [.accountMaster],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .cashBookInvoice:
            return .init(
                ledgerType: ledgerType,
                asset: .cashBookInvoice,
                formSheetName: "L02_CashInv_Form",
                workbookTitle: "現　金　出　納　帳",
                worksheetName: "現金出納帳（インボイス）",
                titleRow: 0,
                titleEndColumn: 8,
                headerRows: 2...3,
                dataStartRow: 4,
                columnHeaders: ["日付", "", "摘　　　　要", "勘 定 科 目", "軽減税率", "インボイス", "入　　金", "出　　金", "残   高"],
                subheaders: [0: "月", 1: "日"],
                columnWidths: [4, 4, 28, 14, 8, 10, 12, 12, 12],
                auxiliarySheets: [.accountMaster],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .bankAccountBook:
            return .init(
                ledgerType: ledgerType,
                asset: .bankAccountBook,
                formSheetName: "L03_BankStd_Form",
                workbookTitle: "預　金　出　納　帳",
                worksheetName: "預金出納帳",
                titleRow: 0,
                titleEndColumn: 6,
                headerRows: 6...7,
                dataStartRow: 8,
                columnHeaders: ["日付", "", "摘　　　　要", "勘 定 科 目", "入　　金", "出　　金", "残   高"],
                subheaders: [0: "月", 1: "日"],
                columnWidths: [4, 4, 28, 14, 12, 12, 12],
                auxiliarySheets: [.accountMaster],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .bankAccountBookInvoice:
            return .init(
                ledgerType: ledgerType,
                asset: .bankAccountBookInvoice,
                formSheetName: "L04_BankInv_Form",
                workbookTitle: "預　金　出　納　帳",
                worksheetName: "預金出納帳（インボイス）",
                titleRow: 0,
                titleEndColumn: 8,
                headerRows: 6...7,
                dataStartRow: 8,
                columnHeaders: ["日付", "", "摘　　　　要", "勘 定 科 目", "軽減税率", "インボイス", "入　　金", "出　　金", "残   高"],
                subheaders: [0: "月", 1: "日"],
                columnWidths: [4, 4, 28, 14, 8, 10, 12, 12, 12],
                auxiliarySheets: [.accountMaster],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .expenseBook:
            return .init(
                ledgerType: ledgerType,
                asset: .expenseBook,
                formSheetName: "L05_ExpStd_Form",
                workbookTitle: "経　費　帳",
                worksheetName: "経費帳",
                titleRow: 0,
                titleEndColumn: 5,
                headerRows: 2...3,
                dataStartRow: 4,
                columnHeaders: ["日付", "", "相手科目", "摘　　　　要", "金額", "累計"],
                subheaders: [0: "月", 1: "日"],
                columnWidths: [4, 4, 14, 28, 12, 12],
                auxiliarySheets: [.accountMaster, .entryGuide],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .expenseBookInvoice:
            return .init(
                ledgerType: ledgerType,
                asset: .expenseBookInvoice,
                formSheetName: "L06_ExpInv_Form",
                workbookTitle: "経　費　帳",
                worksheetName: "経費帳（インボイス）",
                titleRow: 0,
                titleEndColumn: 7,
                headerRows: 2...3,
                dataStartRow: 4,
                columnHeaders: ["日付", "", "相手科目", "摘　　　　要", "軽減\n税率", "イン\nボイス", "金額", "累計"],
                subheaders: [0: "月", 1: "日"],
                columnWidths: [4, 4, 14, 24, 8, 10, 12, 12],
                auxiliarySheets: [.accountMaster, .entryGuide],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .generalLedger:
            return .init(
                ledgerType: ledgerType,
                asset: .generalLedger,
                formSheetName: "L07_GLedStd_Form",
                workbookTitle: "総勘定元帳",
                worksheetName: "総勘定元帳",
                titleRow: 1,
                titleEndColumn: 6,
                headerRows: 4...5,
                dataStartRow: 6,
                columnHeaders: ["日付", "", "相手科目", "摘　　　　要", "借方", "貸方", "差引残高"],
                subheaders: [0: "月", 1: "日"],
                columnWidths: [4, 4, 14, 28, 12, 12, 12],
                auxiliarySheets: [.accountMaster],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .generalLedgerInvoice:
            return .init(
                ledgerType: ledgerType,
                asset: .generalLedgerInvoice,
                formSheetName: "L08_GLedInv_Form",
                workbookTitle: "総勘定元帳",
                worksheetName: "総勘定元帳（インボイス）",
                titleRow: 1,
                titleEndColumn: 8,
                headerRows: 4...5,
                dataStartRow: 6,
                columnHeaders: ["日付", "", "相手科目", "摘　　　　要", "軽減\n税率", "イン\nボイス", "借方", "貸方", "差引残高"],
                subheaders: [0: "月", 1: "日"],
                columnWidths: [4, 4, 14, 28, 8, 10, 12, 12, 12],
                auxiliarySheets: [.accountMaster],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .whiteTaxBookkeeping:
            return .init(
                ledgerType: ledgerType,
                asset: .whiteTaxBookkeeping,
                formSheetName: "L09_WhiteStd_Form",
                workbookTitle: "白色申告用簡易帳簿",
                worksheetName: "白色申告用 簡易帳簿",
                titleRow: 0,
                titleEndColumn: 23,
                headerRows: 2...2,
                dataStartRow: 4,
                columnHeaders: [
                    "月", "日", "摘要", "売上金額", "雑収入等", "仕入",
                    "給料賃金", "外注工賃", "減価償却費", "貸倒金", "地代家賃", "利子割引料",
                    "租税公課", "荷造運賃", "水道光熱費", "旅費交通費", "通信費",
                    "広告宣伝費", "接待交際費", "損害保険料", "修繕費", "消耗品費", "福利厚生費", "雑費"
                ],
                subheaders: [:],
                columnWidths: [4, 4, 18, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10],
                auxiliarySheets: [.accountMaster, .entryGuide],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .whiteTaxBookkeepingInvoice:
            return .init(
                ledgerType: ledgerType,
                asset: .whiteTaxBookkeepingInvoice,
                formSheetName: "L10_WhiteInv_Form",
                workbookTitle: "白色申告用簡易帳簿",
                worksheetName: "白色申告用 簡易帳簿（インボイス）",
                titleRow: 0,
                titleEndColumn: 25,
                headerRows: 2...2,
                dataStartRow: 4,
                columnHeaders: [
                    "月", "日", "摘要", "軽減\n税率", "イン\nボイス",
                    "売上金額", "雑収入等", "仕入",
                    "給料賃金", "外注工賃", "減価償却費", "貸倒金", "地代家賃", "利子割引料",
                    "租税公課", "荷造運賃", "水道光熱費", "旅費交通費", "通信費",
                    "広告宣伝費", "接待交際費", "損害保険料", "修繕費", "消耗品費", "福利厚生費", "雑費"
                ],
                subheaders: [:],
                columnWidths: [4, 4, 18, 8, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10],
                auxiliarySheets: [.accountMaster, .entryGuide],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .accountsReceivable:
            return .init(
                ledgerType: ledgerType,
                asset: .accountsReceivable,
                formSheetName: "L11_AR_Form",
                workbookTitle: "売　掛　帳",
                worksheetName: "売掛帳",
                titleRow: 0,
                titleEndColumn: 8,
                headerRows: 3...4,
                dataStartRow: 5,
                columnHeaders: ["日付", "", "相手科目", "摘　　　　要", "数量", "単価", "売上金額", "入金金額", "売掛金残高"],
                subheaders: [0: "月", 1: "日"],
                columnWidths: [4, 4, 12, 24, 12, 12, 12, 12, 12],
                auxiliarySheets: [.accountMaster],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .accountsPayable:
            return .init(
                ledgerType: ledgerType,
                asset: .accountsPayable,
                formSheetName: "L12_AP_Form",
                workbookTitle: "買　掛　帳",
                worksheetName: "買掛帳",
                titleRow: 0,
                titleEndColumn: 8,
                headerRows: 3...4,
                dataStartRow: 5,
                columnHeaders: ["日付", "", "相手科目", "摘　　　　要", "数量", "単価", "仕入金額", "支払金額", "買掛金残高"],
                subheaders: [0: "月", 1: "日"],
                columnWidths: [4, 4, 12, 24, 12, 12, 12, 12, 12],
                auxiliarySheets: [.accountMaster],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .journal:
            return .init(
                ledgerType: ledgerType,
                asset: .journal,
                formSheetName: "L13_Journal_Form",
                workbookTitle: "仕　訳　帳",
                worksheetName: "仕訳帳",
                titleRow: 0,
                titleEndColumn: 6,
                headerRows: 2...3,
                dataStartRow: 4,
                columnHeaders: ["日付", "", "借方科目", "借方金額", "貸方科目", "貸方金額", "摘　　　　要"],
                subheaders: [0: "月", 1: "日"],
                columnWidths: [4, 4, 14, 12, 14, 12, 28],
                auxiliarySheets: [.accountMaster],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .fixedAssetRegister:
            return .init(
                ledgerType: ledgerType,
                asset: .fixedAssetRegister,
                formSheetName: "L14_FixReg_Form",
                workbookTitle: "固定資産台帳",
                worksheetName: "固定資産台帳",
                titleRow: 0,
                titleEndColumn: 12,
                headerRows: 5...5,
                dataStartRow: 6,
                columnHeaders: ["日付", "摘要", "取得数量", "取得単価", "取得金額", "償却額", "異動数量", "異動金額", "現在数量", "現在金額", "事業専用割合", "必要経費算入額", "備考"],
                subheaders: [:],
                columnWidths: [12, 22, 10, 12, 12, 12, 10, 12, 10, 12, 12, 12, 16],
                auxiliarySheets: [.entryGuide],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .fixedAssetDepreciation:
            return .init(
                ledgerType: ledgerType,
                asset: .fixedAssetDepreciation,
                formSheetName: "L15_FixDep_Form",
                workbookTitle: "固定資産台帳 兼 減価償却計算表",
                worksheetName: "固定資産台帳 兼 減価償却計算表",
                titleRow: 0,
                titleEndColumn: 12,
                headerRows: 3...3,
                dataStartRow: 4,
                columnHeaders: ["勘定科目", "資産コード", "資産名", "取得日", "取得価額", "償却方法", "耐用年数", "償却率", "償却月数", "期首帳簿価額", "減価償却費", "本年末残高", "摘要"],
                subheaders: [:],
                columnWidths: [12, 10, 16, 12, 12, 10, 10, 10, 10, 12, 12, 12, 16],
                auxiliarySheets: [.entryGuide],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        case .transportationExpense:
            return .init(
                ledgerType: ledgerType,
                asset: .transportationExpense,
                formSheetName: "L16_Travel_Form",
                workbookTitle: "交通費精算書",
                worksheetName: "交通費精算書",
                titleRow: 0,
                titleEndColumn: 7,
                headerRows: 4...4,
                dataStartRow: 5,
                columnHeaders: ["日付", "行先", "目的", "交通機関", "出発地", "到着地", "片/往", "金額"],
                subheaders: [:],
                columnWidths: [12, 16, 18, 14, 12, 12, 8, 12],
                auxiliarySheets: [.entryGuide],
                printSettings: .init(isLandscape: true, paperSize: 9)
            )
        }
    }

    private func addPrimaryWorksheet(
        workbook: UnsafeMutablePointer<lxw_workbook>,
        template: LedgerWorkbookTemplateDescriptor
    ) -> UnsafeMutablePointer<lxw_worksheet> {
        workbook_add_worksheet(workbook, template.worksheetName)!
    }

    private func addPrimaryWorksheet(
        workbook: UnsafeMutablePointer<lxw_workbook>,
        template: ReportWorkbookTemplateDescriptor
    ) -> UnsafeMutablePointer<lxw_worksheet> {
        workbook_add_worksheet(workbook, template.worksheetName)!
    }

    private func writeTemplateTitle(
        worksheet: UnsafeMutablePointer<lxw_worksheet>,
        template: LedgerWorkbookTemplateDescriptor,
        styles: ExcelStyles
    ) {
        worksheet_merge_range(
            worksheet,
            lxw_row_t(template.titleRow),
            0,
            lxw_row_t(template.titleRow),
            lxw_col_t(template.titleEndColumn),
            template.workbookTitle,
            styles.titleBandFormat
        )
    }

    private func writeTemplateTitle(
        worksheet: UnsafeMutablePointer<lxw_worksheet>,
        template: ReportWorkbookTemplateDescriptor,
        styles: ExcelStyles
    ) {
        worksheet_merge_range(
            worksheet,
            lxw_row_t(template.titleRow),
            0,
            lxw_row_t(template.titleRow),
            lxw_col_t(template.titleEndColumn),
            template.workbookTitle,
            styles.titleBandFormat
        )

        if let subtitle = template.subtitle {
            worksheet_merge_range(
                worksheet,
                lxw_row_t(template.titleRow + 1),
                0,
                lxw_row_t(template.titleRow + 1),
                lxw_col_t(template.titleEndColumn),
                subtitle,
                styles.dataFormat
            )
        }
    }

    private func writeTemplateHeaders(
        worksheet: UnsafeMutablePointer<lxw_worksheet>,
        template: LedgerWorkbookTemplateDescriptor,
        styles: ExcelStyles
    ) {
        let headerRow = lxw_row_t(template.headerRows.lowerBound)
        for (index, header) in template.columnHeaders.enumerated() {
            worksheet_write_string(worksheet, headerRow, lxw_col_t(index), header, styles.primaryHeaderFormat)
        }

        if template.headerRows.lowerBound != template.headerRows.upperBound {
            let subheaderRow = lxw_row_t(template.headerRows.upperBound)
            for (column, label) in template.subheaders {
                worksheet_write_string(worksheet, subheaderRow, lxw_col_t(column), label, styles.secondaryHeaderFormat)
            }
        }
    }

    private func writeTemplateHeaders(
        worksheet: UnsafeMutablePointer<lxw_worksheet>,
        template: ReportWorkbookTemplateDescriptor,
        styles: ExcelStyles
    ) {
        let headerRow = lxw_row_t(template.headerRows.lowerBound)
        for (index, header) in template.columnHeaders.enumerated() {
            worksheet_write_string(worksheet, headerRow, lxw_col_t(index), header, styles.primaryHeaderFormat)
        }
    }

    private func applyTemplateColumnWidths(
        worksheet: UnsafeMutablePointer<lxw_worksheet>,
        template: LedgerWorkbookTemplateDescriptor
    ) {
        for (index, width) in template.columnWidths.enumerated() {
            worksheet_set_column(worksheet, lxw_col_t(index), lxw_col_t(index), width, nil)
        }
    }

    private func applyTemplateColumnWidths(
        worksheet: UnsafeMutablePointer<lxw_worksheet>,
        template: ReportWorkbookTemplateDescriptor
    ) {
        for (index, width) in template.columnWidths.enumerated() {
            worksheet_set_column(worksheet, lxw_col_t(index), lxw_col_t(index), width, nil)
        }
    }

    private func applyTemplatePrintSettings(
        worksheet: UnsafeMutablePointer<lxw_worksheet>,
        template: LedgerWorkbookTemplateDescriptor,
        lastDataRow: Int
    ) {
        if template.printSettings.isLandscape {
            worksheet_set_landscape(worksheet)
        }
        worksheet_set_paper(worksheet, template.printSettings.paperSize)
        worksheet_print_area(
            worksheet,
            0,
            0,
            lxw_row_t(lastDataRow),
            lxw_col_t(template.titleEndColumn)
        )
    }

    private func applyTemplatePrintSettings(
        worksheet: UnsafeMutablePointer<lxw_worksheet>,
        template: ReportWorkbookTemplateDescriptor,
        lastDataRow: Int
    ) {
        if template.printSettings.isLandscape {
            worksheet_set_landscape(worksheet)
        }
        worksheet_set_paper(worksheet, template.printSettings.paperSize)
        worksheet_print_area(
            worksheet,
            0,
            0,
            lxw_row_t(lastDataRow),
            lxw_col_t(template.titleEndColumn)
        )
    }

    private func addAuxiliarySheets(
        workbook: UnsafeMutablePointer<lxw_workbook>,
        styles: ExcelStyles,
        template: LedgerWorkbookTemplateDescriptor
    ) {
        for sheet in template.auxiliarySheets {
            switch sheet {
            case .accountMaster:
                addAccountMasterSheet(workbook: workbook, styles: styles)
            case .entryGuide:
                addEntryGuideSheet(workbook: workbook, styles: styles, template: template)
            }
        }
    }

    private func addAuxiliarySheets(
        workbook: UnsafeMutablePointer<lxw_workbook>,
        styles: ExcelStyles,
        template: ReportWorkbookTemplateDescriptor
    ) {
        for sheet in template.auxiliarySheets {
            switch sheet {
            case .accountMaster:
                addAccountMasterSheet(workbook: workbook, styles: styles)
            case .entryGuide:
                addEntryGuideSheet(workbook: workbook, styles: styles, title: template.worksheetName)
            }
        }
    }
    
    // MARK: - 現金出納帳
    
    func exportCashBook(
        metadata: CashBookMetadata,
        entries: [CashBookEntry],
        includeInvoice: Bool = false,
        to path: String
    ) {
        let template = Self.templateDescriptor(for: includeInvoice ? .cashBookInvoice : .cashBook)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)
        
        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)
        
        // 繰越行
        let dataStart = lxw_row_t(template.dataStartRow)
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
        
        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: template.dataStartRow + entries.count)
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
        
        workbook_close(wb)
    }
    
    // MARK: - 預金出納帳
    
    func exportBankAccountBook(
        metadata: BankAccountBookMetadata,
        entries: [BankAccountBookEntry],
        includeInvoice: Bool = false,
        to path: String
    ) {
        let template = Self.templateDescriptor(for: includeInvoice ? .bankAccountBookInvoice : .bankAccountBook)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)
        
        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        
        // メタデータ
        worksheet_write_string(ws, 1, 0, "銀行名", styles.metaLabelFormat)
        worksheet_write_string(ws, 1, 2, metadata.bankName, styles.metaValueFormat)
        worksheet_write_string(ws, 2, 0, "本支店名", styles.metaLabelFormat)
        worksheet_write_string(ws, 2, 2, metadata.branchName, styles.metaValueFormat)
        worksheet_write_string(ws, 3, 0, "口座種類", styles.metaLabelFormat)
        worksheet_write_string(ws, 3, 2, metadata.accountType, styles.metaValueFormat)
        
        let noteCol: lxw_col_t = includeInvoice ? 9 : 7
        worksheet_write_string(ws, 3, noteCol, "※当座預金・普通預金・定期預金等", styles.dataFormat)
        
        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)
        
        // 繰越 + データ行（現金出納帳と同一ロジック）
        let dataStart = lxw_row_t(template.dataStartRow)
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
        
        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: template.dataStartRow + entries.count)
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
        workbook_close(wb)
    }
    
    // MARK: - 売掛帳
    
    func exportAccountsReceivable(
        metadata: AccountsReceivableMetadata,
        entries: [AccountsReceivableEntry],
        to path: String
    ) {
        let template = Self.templateDescriptor(for: .accountsReceivable)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)
        
        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        worksheet_write_string(ws, 1, 0, "得意先名", styles.metaLabelFormat)
        worksheet_write_string(ws, 1, 3, metadata.clientName, styles.metaValueFormat)
        
        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)
        
        worksheet_write_string(ws, lxw_row_t(template.dataStartRow), 3, "前期より繰越", styles.carryForwardFormat)
        worksheet_write_number(ws, lxw_row_t(template.dataStartRow), 8, Double(metadata.carryForward), styles.numberFormat)
        
        for (i, entry) in entries.enumerated() {
            let row: lxw_row_t = lxw_row_t(template.dataStartRow + 1) + lxw_row_t(i)
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
        
        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: template.dataStartRow + entries.count + 1)
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
        workbook_close(wb)
    }
    
    // MARK: - 買掛帳
    
    func exportAccountsPayable(
        metadata: AccountsPayableMetadata,
        entries: [AccountsPayableEntry],
        to path: String
    ) {
        let template = Self.templateDescriptor(for: .accountsPayable)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)
        
        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        worksheet_write_string(ws, 1, 0, "仕入先名", styles.metaLabelFormat)
        worksheet_write_string(ws, 1, 3, metadata.supplierName, styles.metaValueFormat)
        
        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)
        
        worksheet_write_string(ws, lxw_row_t(template.dataStartRow), 3, "前期より繰越", styles.carryForwardFormat)
        worksheet_write_number(ws, lxw_row_t(template.dataStartRow), 8, Double(metadata.carryForward), styles.numberFormat)
        
        for (i, entry) in entries.enumerated() {
            let row: lxw_row_t = lxw_row_t(template.dataStartRow + 1) + lxw_row_t(i)
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
        
        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: template.dataStartRow + entries.count + 1)
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
        workbook_close(wb)
    }

    // MARK: - 経費帳

    func exportExpenseBook(
        metadata: ExpenseBookMetadata,
        entries: [ExpenseBookEntry],
        includeInvoice: Bool = false,
        to path: String
    ) {
        let template = Self.templateDescriptor(for: includeInvoice ? .expenseBookInvoice : .expenseBook)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)

        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        worksheet_write_string(ws, 1, 0, "勘定科目名", styles.metaLabelFormat)
        worksheet_write_string(ws, 1, 2, metadata.accountName, styles.metaValueFormat)
        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)

        var runningTotal = 0
        for (index, entry) in entries.enumerated() {
            let row = lxw_row_t(template.dataStartRow + index)
            runningTotal += entry.amount

            worksheet_write_number(ws, row, 0, Double(entry.month), styles.dataFormat)
            worksheet_write_number(ws, row, 1, Double(entry.day), styles.dataFormat)
            worksheet_write_string(ws, row, 2, entry.counterAccount, styles.dataFormat)
            worksheet_write_string(ws, row, 3, entry.description, styles.dataFormat)

            let amountCol: lxw_col_t = includeInvoice ? 6 : 4
            let totalCol: lxw_col_t = includeInvoice ? 7 : 5
            if includeInvoice {
                if entry.reducedTax == true {
                    worksheet_write_string(ws, row, 4, "〇", styles.dataFormat)
                }
                if let invoiceType = entry.invoiceType {
                    worksheet_write_string(ws, row, 5, invoiceType.rawValue, styles.dataFormat)
                }
            }

            worksheet_write_number(ws, row, amountCol, Double(entry.amount), styles.numberFormat)
            worksheet_write_number(ws, row, totalCol, Double(runningTotal), styles.numberFormat)
        }

        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: template.dataStartRow + max(entries.count - 1, 0))
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
        workbook_close(wb)
    }
    
    // MARK: - 総勘定元帳
    
    func exportGeneralLedger(
        metadata: GeneralLedgerMetadata,
        entries: [GeneralLedgerEntry],
        includeInvoice: Bool = false,
        to path: String
    ) {
        let template = Self.templateDescriptor(for: includeInvoice ? .generalLedgerInvoice : .generalLedger)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)
        
        let balCol: lxw_col_t = includeInvoice ? 8 : 6
        
        // 属性ラベル
        worksheet_write_string(ws, 0, balCol - 1, "科目の属性：", styles.metaLabelFormat)
        worksheet_write_string(ws, 0, balCol, metadata.accountAttribute?.rawValue ?? "資産", styles.metaValueFormat)
        
        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        worksheet_write_string(ws, 2, 0, "勘定科目", styles.metaLabelFormat)
        worksheet_write_string(ws, 2, 3, metadata.accountName, styles.metaValueFormat)
        
        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)
        
        // 繰越
        worksheet_write_string(ws, lxw_row_t(template.dataStartRow), 3, "前期より繰越", styles.carryForwardFormat)
        worksheet_write_number(ws, lxw_row_t(template.dataStartRow), balCol, Double(metadata.carryForward), styles.numberFormat)
        
        // データ行 + 属性別残高数式
        let debitCol: lxw_col_t = includeInvoice ? 6 : 4
        let creditCol: lxw_col_t = includeInvoice ? 7 : 5
        for (i, entry) in entries.enumerated() {
            let row: lxw_row_t = lxw_row_t(template.dataStartRow + 1) + lxw_row_t(i)
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
        
        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: template.dataStartRow + entries.count + 1)
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
        workbook_close(wb)
    }
    
    // MARK: - 仕訳帳
    
    func exportJournal(
        entries: [JournalEntry],
        to path: String
    ) {
        let template = Self.templateDescriptor(for: .journal)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)
        
        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)
        
        for (i, entry) in entries.enumerated() {
            let row: lxw_row_t = lxw_row_t(template.dataStartRow) + lxw_row_t(i)
            
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
        
        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: template.dataStartRow + entries.count - 1)
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
        workbook_close(wb)
    }

    // MARK: - 交通費精算書

    func exportTransportationExpense(
        metadata: TransportationExpenseMetadata,
        entries: [TransportationExpenseEntry],
        to path: String
    ) {
        let template = Self.templateDescriptor(for: .transportationExpense)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)

        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        worksheet_write_string(ws, 1, 0, "所属", styles.metaLabelFormat)
        worksheet_write_string(ws, 1, 1, metadata.department, styles.metaValueFormat)
        worksheet_write_string(ws, 1, 3, "氏名", styles.metaLabelFormat)
        worksheet_write_string(ws, 1, 4, metadata.employeeName, styles.metaValueFormat)
        worksheet_write_string(ws, 1, 6, "対象", styles.metaLabelFormat)
        worksheet_write_string(ws, 1, 7, "\(metadata.year)年 \(metadata.monthPeriod)月度", styles.metaValueFormat)
        worksheet_write_string(ws, 2, 0, "申請日", styles.metaLabelFormat)
        worksheet_write_string(ws, 2, 1, metadata.requestDate, styles.metaValueFormat)
        worksheet_write_string(ws, 2, 3, "精算日", styles.metaLabelFormat)
        worksheet_write_string(ws, 2, 4, metadata.settlementDate, styles.metaValueFormat)

        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)

        for (index, entry) in entries.enumerated() {
            let row = lxw_row_t(template.dataStartRow + index)
            worksheet_write_string(ws, row, 0, entry.date, styles.dataFormat)
            worksheet_write_string(ws, row, 1, entry.destination, styles.dataFormat)
            worksheet_write_string(ws, row, 2, entry.purpose, styles.dataFormat)
            worksheet_write_string(ws, row, 3, entry.transportMethod, styles.dataFormat)
            worksheet_write_string(ws, row, 4, entry.routeFrom, styles.dataFormat)
            worksheet_write_string(ws, row, 5, entry.routeTo, styles.dataFormat)
            worksheet_write_string(ws, row, 6, entry.tripType.rawValue, styles.dataFormat)
            worksheet_write_number(ws, row, 7, Double(entry.amount), styles.numberFormat)
        }

        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: template.dataStartRow + max(entries.count - 1, 0))
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
        workbook_close(wb)
    }

    // MARK: - 白色申告用 簡易帳簿

    func exportWhiteTaxBookkeeping(
        metadata: WhiteTaxBookkeepingMetadata,
        entries: [WhiteTaxBookkeepingEntry],
        includeInvoice: Bool = false,
        to path: String
    ) {
        let template = Self.templateDescriptor(for: includeInvoice ? .whiteTaxBookkeepingInvoice : .whiteTaxBookkeeping)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)

        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        worksheet_write_string(ws, 1, 0, "年分", styles.metaLabelFormat)
        worksheet_write_string(ws, 1, 1, "\(metadata.fiscalYear)年", styles.metaValueFormat)
        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)

        for (index, entry) in entries.enumerated() {
            let row = lxw_row_t(template.dataStartRow + index)
            var column: lxw_col_t = 0

            worksheet_write_number(ws, row, column, Double(entry.month), styles.dataFormat)
            column += 1
            worksheet_write_number(ws, row, column, Double(entry.day), styles.dataFormat)
            column += 1
            worksheet_write_string(ws, row, column, entry.description, styles.dataFormat)
            column += 1

            if includeInvoice {
                if entry.reducedTax == true {
                    worksheet_write_string(ws, row, column, "〇", styles.dataFormat)
                }
                column += 1
                if let invoiceType = entry.invoiceType {
                    worksheet_write_string(ws, row, column, invoiceType.rawValue, styles.dataFormat)
                }
                column += 1
            }

            let values: [Int?] = [
                entry.salesAmount, entry.miscIncome, entry.purchases,
                entry.salaries, entry.outsourcing, entry.depreciation, entry.badDebts,
                entry.rent, entry.interestDiscount, entry.taxesDuties, entry.packingShipping,
                entry.utilities, entry.travelTransport, entry.communication, entry.advertising,
                entry.entertainment, entry.insurance, entry.repairs, entry.supplies,
                entry.welfare, entry.miscellaneous
            ]
            for value in values {
                if let value, value > 0 {
                    worksheet_write_number(ws, row, column, Double(value), styles.numberFormat)
                }
                column += 1
            }
        }

        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: template.dataStartRow + max(entries.count - 1, 0))
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
        workbook_close(wb)
    }

    // MARK: - 固定資産台帳 兼 減価償却計算表

    func exportFixedAssetDepreciation(
        entries: [FixedAssetDepreciationEntry],
        to path: String
    ) {
        let template = Self.templateDescriptor(for: .fixedAssetDepreciation)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)

        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)

        for (index, entry) in entries.enumerated() {
            let row = lxw_row_t(template.dataStartRow + index)
            let depreciationExpense = Int(Double(entry.openingBookValue + (entry.midYearChange ?? 0)) * entry.depreciationRate)
            let yearEndBalance = max(entry.openingBookValue + (entry.midYearChange ?? 0) - depreciationExpense, 0)

            worksheet_write_string(ws, row, 0, entry.account, styles.dataFormat)
            worksheet_write_string(ws, row, 1, entry.assetCode, styles.dataFormat)
            worksheet_write_string(ws, row, 2, entry.assetName, styles.dataFormat)
            worksheet_write_string(ws, row, 3, entry.acquisitionDate, styles.dataFormat)
            worksheet_write_number(ws, row, 4, Double(entry.acquisitionCost), styles.numberFormat)
            worksheet_write_string(ws, row, 5, entry.depreciationMethod.rawValue, styles.dataFormat)
            worksheet_write_number(ws, row, 6, Double(entry.usefulLife), styles.numberFormat)
            worksheet_write_number(ws, row, 7, entry.depreciationRate, styles.numberFormat)
            worksheet_write_number(ws, row, 8, Double(entry.depreciationMonths), styles.numberFormat)
            worksheet_write_number(ws, row, 9, Double(entry.openingBookValue), styles.numberFormat)
            worksheet_write_number(ws, row, 10, Double(depreciationExpense), styles.numberFormat)
            worksheet_write_number(ws, row, 11, Double(yearEndBalance), styles.numberFormat)
            worksheet_write_string(ws, row, 12, entry.remarks ?? "", styles.dataFormat)
        }

        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: template.dataStartRow + max(entries.count - 1, 0))
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
        workbook_close(wb)
    }

    // MARK: - 固定資産台帳

    func exportFixedAssetRegister(
        metadata: FixedAssetRegisterMetadata,
        entries: [FixedAssetRegisterEntry],
        to path: String
    ) {
        let template = Self.templateDescriptor(for: .fixedAssetRegister)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)

        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        worksheet_write_string(ws, 1, 0, "名称", styles.metaLabelFormat)
        worksheet_write_string(ws, 1, 1, metadata.assetName, styles.metaValueFormat)
        worksheet_write_string(ws, 1, 3, "番号", styles.metaLabelFormat)
        worksheet_write_string(ws, 1, 4, metadata.assetNumber, styles.metaValueFormat)
        worksheet_write_string(ws, 1, 6, "種類", styles.metaLabelFormat)
        worksheet_write_string(ws, 1, 7, metadata.assetType, styles.metaValueFormat)
        worksheet_write_string(ws, 2, 0, "取得年月日", styles.metaLabelFormat)
        worksheet_write_string(ws, 2, 1, metadata.acquisitionDate, styles.metaValueFormat)
        worksheet_write_string(ws, 2, 3, "所在", styles.metaLabelFormat)
        worksheet_write_string(ws, 2, 4, metadata.location, styles.metaValueFormat)
        worksheet_write_string(ws, 2, 6, "耐用年数", styles.metaLabelFormat)
        worksheet_write_number(ws, 2, 7, Double(metadata.usefulLife), styles.numberFormat)
        worksheet_write_string(ws, 3, 0, "償却方法", styles.metaLabelFormat)
        worksheet_write_string(ws, 3, 1, metadata.depreciationMethod, styles.metaValueFormat)
        worksheet_write_string(ws, 3, 3, "償却率", styles.metaLabelFormat)
        worksheet_write_number(ws, 3, 4, metadata.depreciationRate, styles.numberFormat)

        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)

        var currentQuantity = 0
        var currentAmount = 0
        for (index, entry) in entries.enumerated() {
            let row = lxw_row_t(template.dataStartRow + index)
            currentQuantity += (entry.acquiredQuantity ?? 0) - (entry.disposalQuantity ?? 0)
            currentAmount += (entry.acquiredAmount ?? 0) - (entry.depreciationAmount ?? 0) - (entry.disposalAmount ?? 0)
            let deductibleAmount = Int(Double(max(currentAmount, 0)) * (entry.businessUseRatio ?? 0))

            worksheet_write_string(ws, row, 0, entry.date, styles.dataFormat)
            worksheet_write_string(ws, row, 1, entry.description, styles.dataFormat)
            writeOptionalNumber(entry.acquiredQuantity, worksheet: ws, row: row, column: 2, styles: styles)
            writeOptionalNumber(entry.acquiredUnitPrice, worksheet: ws, row: row, column: 3, styles: styles)
            writeOptionalNumber(entry.acquiredAmount, worksheet: ws, row: row, column: 4, styles: styles)
            writeOptionalNumber(entry.depreciationAmount, worksheet: ws, row: row, column: 5, styles: styles)
            writeOptionalNumber(entry.disposalQuantity, worksheet: ws, row: row, column: 6, styles: styles)
            writeOptionalNumber(entry.disposalAmount, worksheet: ws, row: row, column: 7, styles: styles)
            worksheet_write_number(ws, row, 8, Double(currentQuantity), styles.numberFormat)
            worksheet_write_number(ws, row, 9, Double(max(currentAmount, 0)), styles.numberFormat)
            if let businessUseRatio = entry.businessUseRatio {
                worksheet_write_string(ws, row, 10, String(format: "%.0f%%", businessUseRatio * 100), styles.dataFormat)
            }
            worksheet_write_number(ws, row, 11, Double(deductibleAmount), styles.numberFormat)
            worksheet_write_string(ws, row, 12, entry.remarks ?? "", styles.dataFormat)
        }

        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: template.dataStartRow + max(entries.count - 1, 0))
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
        workbook_close(wb)
    }

    // MARK: - Report Export

    func exportProfitLossReport(
        report: ProfitLossReport,
        to path: String
    ) {
        let template = Self.reportTemplateDescriptor(for: .profitLoss)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)

        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        let metaRow = lxw_row_t(max(template.titleRow + 1, template.headerRows.lowerBound - 1))
        worksheet_write_string(ws, metaRow, 0, "年度", styles.metaLabelFormat)
        worksheet_write_string(ws, metaRow, 1, "\(report.fiscalYear)年度", styles.metaValueFormat)
        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)

        var row = template.dataStartRow
        worksheet_write_string(ws, lxw_row_t(row), 0, "【収益の部】", styles.sectionHeaderFormat)
        row += 1
        for item in report.revenueItems {
            worksheet_write_string(ws, lxw_row_t(row), 0, item.name, styles.dataFormat)
            worksheet_write_number(ws, lxw_row_t(row), 1, Double(item.amount), styles.numberFormat)
            row += 1
        }
        worksheet_write_string(ws, lxw_row_t(row), 0, "収益合計", styles.sectionHeaderFormat)
        worksheet_write_number(ws, lxw_row_t(row), 1, Double(report.totalRevenue), styles.subtotalFormat)
        row += 2

        worksheet_write_string(ws, lxw_row_t(row), 0, "【費用の部】", styles.sectionHeaderFormat)
        row += 1
        for item in report.expenseItems {
            worksheet_write_string(ws, lxw_row_t(row), 0, item.name, styles.dataFormat)
            worksheet_write_number(ws, lxw_row_t(row), 2, Double(item.amount), styles.numberFormat)
            row += 1
        }
        worksheet_write_string(ws, lxw_row_t(row), 0, "費用合計", styles.sectionHeaderFormat)
        worksheet_write_number(ws, lxw_row_t(row), 2, Double(report.totalExpenses), styles.subtotalFormat)
        row += 2

        worksheet_write_string(ws, lxw_row_t(row), 0, "当期純利益", styles.sectionHeaderFormat)
        if report.netIncome >= 0 {
            worksheet_write_number(ws, lxw_row_t(row), 1, Double(report.netIncome), styles.subtotalFormat)
        } else {
            worksheet_write_number(ws, lxw_row_t(row), 2, Double(-report.netIncome), styles.subtotalFormat)
        }

        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: row)
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
        workbook_close(wb)
    }

    func exportBalanceSheetReport(
        report: BalanceSheetReport,
        to path: String
    ) {
        let template = Self.reportTemplateDescriptor(for: .balanceSheet)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)

        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        let metaRow = lxw_row_t(max(template.titleRow + 1, template.headerRows.lowerBound - 1))
        worksheet_write_string(ws, metaRow, 0, "年度", styles.metaLabelFormat)
        worksheet_write_string(ws, metaRow, 1, "\(report.fiscalYear)年度", styles.metaValueFormat)
        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)

        var leftRow = template.dataStartRow
        worksheet_write_string(ws, lxw_row_t(leftRow), 0, "資産の部", styles.sectionHeaderFormat)
        leftRow += 1
        for item in report.assetItems {
            worksheet_write_string(ws, lxw_row_t(leftRow), 0, item.name, styles.dataFormat)
            worksheet_write_number(ws, lxw_row_t(leftRow), 1, Double(item.balance), styles.numberFormat)
            leftRow += 1
        }
        worksheet_write_string(ws, lxw_row_t(leftRow), 0, "資産合計", styles.sectionHeaderFormat)
        worksheet_write_number(ws, lxw_row_t(leftRow), 1, Double(report.totalAssets), styles.subtotalFormat)

        var rightRow = template.dataStartRow
        worksheet_write_string(ws, lxw_row_t(rightRow), 3, "負債の部", styles.sectionHeaderFormat)
        rightRow += 1
        for item in report.liabilityItems {
            worksheet_write_string(ws, lxw_row_t(rightRow), 3, item.name, styles.dataFormat)
            worksheet_write_number(ws, lxw_row_t(rightRow), 4, Double(item.balance), styles.numberFormat)
            rightRow += 1
        }
        worksheet_write_string(ws, lxw_row_t(rightRow), 3, "負債合計", styles.sectionHeaderFormat)
        worksheet_write_number(ws, lxw_row_t(rightRow), 4, Double(report.totalLiabilities), styles.subtotalFormat)
        rightRow += 2

        worksheet_write_string(ws, lxw_row_t(rightRow), 3, "純資産の部", styles.sectionHeaderFormat)
        rightRow += 1
        for item in report.equityItems {
            worksheet_write_string(ws, lxw_row_t(rightRow), 3, item.name, styles.dataFormat)
            worksheet_write_number(ws, lxw_row_t(rightRow), 4, Double(item.balance), styles.numberFormat)
            rightRow += 1
        }
        worksheet_write_string(ws, lxw_row_t(rightRow), 3, "純資産合計", styles.sectionHeaderFormat)
        worksheet_write_number(ws, lxw_row_t(rightRow), 4, Double(report.totalEquity), styles.subtotalFormat)
        rightRow += 1
        worksheet_write_string(ws, lxw_row_t(rightRow), 3, "負債・純資産合計", styles.sectionHeaderFormat)
        worksheet_write_number(ws, lxw_row_t(rightRow), 4, Double(report.liabilitiesAndEquity), styles.subtotalFormat)

        let lastRow = max(leftRow, rightRow)
        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: lastRow)
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
        workbook_close(wb)
    }

    func exportTrialBalanceReport(
        report: TrialBalanceReport,
        to path: String
    ) {
        let template = Self.reportTemplateDescriptor(for: .trialBalance)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)

        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        worksheet_write_string(ws, 3, 0, "帳簿名", styles.metaLabelFormat)
        worksheet_write_string(ws, 3, 1, "残高試算表", styles.metaValueFormat)
        worksheet_write_string(ws, 4, 0, "年度", styles.metaLabelFormat)
        worksheet_write_string(ws, 4, 1, "\(report.fiscalYear)年度", styles.metaValueFormat)
        worksheet_write_string(ws, 5, 0, "事業者名", styles.metaLabelFormat)
        worksheet_write_string(ws, 5, 1, "Project Profit", styles.metaValueFormat)
        worksheet_write_string(ws, 6, 0, "作成者", styles.metaLabelFormat)
        worksheet_write_string(ws, 6, 1, "Project Profit", styles.metaValueFormat)
        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)

        var row = template.dataStartRow
        for item in report.rows {
            worksheet_write_string(ws, lxw_row_t(row), 0, item.code, styles.dataFormat)
            worksheet_write_string(ws, lxw_row_t(row), 1, item.name, styles.dataFormat)
            worksheet_write_string(ws, lxw_row_t(row), 2, item.accountType.label, styles.dataFormat)
            worksheet_write_number(ws, lxw_row_t(row), 3, Double(item.debit), styles.numberFormat)
            worksheet_write_number(ws, lxw_row_t(row), 4, Double(item.credit), styles.numberFormat)
            worksheet_write_number(ws, lxw_row_t(row), 5, Double(item.balance), styles.numberFormat)
            row += 1
        }
        worksheet_write_string(ws, lxw_row_t(row), 1, "合計", styles.sectionHeaderFormat)
        worksheet_write_number(ws, lxw_row_t(row), 3, Double(report.debitTotal), styles.subtotalFormat)
        worksheet_write_number(ws, lxw_row_t(row), 4, Double(report.creditTotal), styles.subtotalFormat)

        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: row)
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
        workbook_close(wb)
    }

    func exportJournalReport(
        entries: [PPJournalEntry],
        lines: [PPJournalLine],
        accounts: [PPAccount],
        fiscalYear: Int,
        to path: String
    ) {
        let template = Self.reportTemplateDescriptor(for: .journal)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)
        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let linesByEntry = Dictionary(grouping: lines, by: \.entryId)
        let calendar = Calendar(identifier: .gregorian)

        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        worksheet_write_string(ws, 3, 0, "帳簿名", styles.metaLabelFormat)
        worksheet_write_string(ws, 3, 1, "仕訳帳", styles.metaValueFormat)
        worksheet_write_string(ws, 4, 0, "年度", styles.metaLabelFormat)
        worksheet_write_string(ws, 4, 1, "\(fiscalYear)年度", styles.metaValueFormat)
        worksheet_write_string(ws, 5, 0, "事業者名", styles.metaLabelFormat)
        worksheet_write_string(ws, 5, 1, "Project Profit", styles.metaValueFormat)
        worksheet_write_string(ws, 6, 0, "作成者", styles.metaLabelFormat)
        worksheet_write_string(ws, 6, 1, "Project Profit", styles.metaValueFormat)
        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)

        var row = template.dataStartRow
        for entry in entries.filter(\.isPosted).sorted(by: { $0.date < $1.date }) {
            let entryLines = (linesByEntry[entry.id] ?? []).sorted { $0.displayOrder < $1.displayOrder }
            for line in entryLines {
                let accountName = accountMap[line.accountId]?.name ?? line.accountId
                let comps = calendar.dateComponents([.month, .day], from: entry.date)
                worksheet_write_number(ws, lxw_row_t(row), 0, Double(comps.month ?? 0), styles.dataFormat)
                worksheet_write_number(ws, lxw_row_t(row), 1, Double(comps.day ?? 0), styles.dataFormat)
                if line.debit > 0 {
                    worksheet_write_string(ws, lxw_row_t(row), 2, accountName, styles.dataFormat)
                    worksheet_write_number(ws, lxw_row_t(row), 3, Double(line.debit), styles.numberFormat)
                }
                if line.credit > 0 {
                    worksheet_write_string(ws, lxw_row_t(row), 4, accountName, styles.dataFormat)
                    worksheet_write_number(ws, lxw_row_t(row), 5, Double(line.credit), styles.numberFormat)
                }
                worksheet_write_string(ws, lxw_row_t(row), 6, entry.memo, styles.dataFormat)
                row += 1
            }
        }

        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: max(row - 1, template.dataStartRow))
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
        workbook_close(wb)
    }

    func exportLedgerReport(
        accountName: String,
        accountCode: String,
        accountTypeLabel: String,
        openingBalance: Int,
        entries: [DataStore.LedgerEntry],
        counterpartyNames: [UUID: String],
        fiscalYear: Int,
        to path: String
    ) {
        let template = Self.reportTemplateDescriptor(for: .ledger)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)
        let calendar = Calendar(identifier: .gregorian)

        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        worksheet_write_string(ws, 3, 0, "帳簿名", styles.metaLabelFormat)
        worksheet_write_string(ws, 3, 1, "総勘定元帳", styles.metaValueFormat)
        worksheet_write_string(ws, 4, 0, "年度", styles.metaLabelFormat)
        worksheet_write_string(ws, 4, 1, "\(fiscalYear)年度", styles.metaValueFormat)
        worksheet_write_string(ws, 5, 0, "勘定科目名", styles.metaLabelFormat)
        worksheet_write_string(ws, 5, 1, "\(accountCode) \(accountName)", styles.metaValueFormat)
        worksheet_write_string(ws, 6, 0, "科目の属性", styles.metaLabelFormat)
        worksheet_write_string(ws, 6, 1, accountTypeLabel, styles.metaValueFormat)
        worksheet_write_string(ws, 7, 0, "前期より繰越", styles.metaLabelFormat)
        worksheet_write_number(ws, 7, 1, Double(openingBalance), styles.numberFormat)
        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)

        var row = template.dataStartRow
        for entry in entries {
            let comps = calendar.dateComponents([.month, .day], from: entry.date)
            worksheet_write_number(ws, lxw_row_t(row), 0, Double(comps.month ?? 0), styles.dataFormat)
            worksheet_write_number(ws, lxw_row_t(row), 1, Double(comps.day ?? 0), styles.dataFormat)
            worksheet_write_string(ws, lxw_row_t(row), 2, counterpartyNames[entry.id] ?? entry.counterparty ?? "", styles.dataFormat)
            worksheet_write_string(ws, lxw_row_t(row), 3, entry.memo, styles.dataFormat)
            if entry.debit > 0 {
                worksheet_write_number(ws, lxw_row_t(row), 4, Double(entry.debit), styles.numberFormat)
            }
            if entry.credit > 0 {
                worksheet_write_number(ws, lxw_row_t(row), 5, Double(entry.credit), styles.numberFormat)
            }
            worksheet_write_number(ws, lxw_row_t(row), 6, Double(entry.runningBalance), styles.numberFormat)
            row += 1
        }

        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: max(row - 1, template.dataStartRow))
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
        workbook_close(wb)
    }

    func exportFixedAssetsReport(
        assets: [PPFixedAsset],
        fiscalYear: Int,
        calculateAccumulated: (PPFixedAsset) -> Int,
        calculateCurrentYear: (PPFixedAsset) -> Int,
        to path: String
    ) {
        let template = Self.reportTemplateDescriptor(for: .fixedAssets)!
        let wb = workbook_new(path)!
        let styles = ExcelStyles(workbook: wb)
        let ws = addPrimaryWorksheet(workbook: wb, template: template)
        let calendar = Calendar(identifier: .gregorian)

        writeTemplateTitle(worksheet: ws, template: template, styles: styles)
        worksheet_write_string(ws, 3, 0, "帳簿名", styles.metaLabelFormat)
        worksheet_write_string(ws, 3, 1, "固定資産台帳 兼 減価償却計算表", styles.metaValueFormat)
        worksheet_write_string(ws, 4, 0, "年分", styles.metaLabelFormat)
        worksheet_write_string(ws, 4, 1, "\(fiscalYear)年", styles.metaValueFormat)
        worksheet_write_string(ws, 5, 0, "事業者名", styles.metaLabelFormat)
        worksheet_write_string(ws, 5, 1, "Project Profit", styles.metaValueFormat)
        worksheet_write_string(ws, 6, 0, "作成者", styles.metaLabelFormat)
        worksheet_write_string(ws, 6, 1, "Project Profit", styles.metaValueFormat)
        writeTemplateHeaders(worksheet: ws, template: template, styles: styles)

        var row = template.dataStartRow
        for (index, asset) in assets.enumerated() {
            let currentYear = calculateCurrentYear(asset)
            let accumulated = calculateAccumulated(asset)
            let beginningBookValue = max(asset.acquisitionCost - accumulated + currentYear, 0)
            let endingBookValue = max(asset.acquisitionCost - accumulated, 0)
            let months = max(1, calendar.dateComponents([.month], from: asset.acquisitionDate, to: asset.disposalDate ?? calendar.date(from: DateComponents(year: fiscalYear, month: 12, day: 31)) ?? asset.acquisitionDate).month ?? 12)

            worksheet_write_string(ws, lxw_row_t(row), 0, "固定資産", styles.dataFormat)
            worksheet_write_string(ws, lxw_row_t(row), 1, String(format: "FA-%03d", index + 1), styles.dataFormat)
            worksheet_write_string(ws, lxw_row_t(row), 2, asset.name, styles.dataFormat)
            worksheet_write_string(ws, lxw_row_t(row), 3, asset.memo ?? "固定資産", styles.dataFormat)
            worksheet_write_string(ws, lxw_row_t(row), 4, asset.assetStatus.label, styles.dataFormat)
            worksheet_write_number(ws, lxw_row_t(row), 5, 1, styles.numberFormat)
            worksheet_write_string(ws, lxw_row_t(row), 6, formatDate(asset.acquisitionDate), styles.dataFormat)
            worksheet_write_number(ws, lxw_row_t(row), 7, Double(asset.acquisitionCost), styles.numberFormat)
            worksheet_write_string(ws, lxw_row_t(row), 8, asset.depreciationMethod.label, styles.dataFormat)
            worksheet_write_number(ws, lxw_row_t(row), 9, Double(asset.usefulLifeYears), styles.numberFormat)
            let depreciationRate = asset.usefulLifeYears > 0 ? 1.0 / Double(asset.usefulLifeYears) : 0
            worksheet_write_string(ws, lxw_row_t(row), 10, String(format: "%.3f", depreciationRate), styles.dataFormat)
            worksheet_write_number(ws, lxw_row_t(row), 11, Double(months), styles.numberFormat)
            worksheet_write_number(ws, lxw_row_t(row), 12, Double(beginningBookValue), styles.numberFormat)
            worksheet_write_number(ws, lxw_row_t(row), 13, Double(asset.disposalAmount ?? 0), styles.numberFormat)
            worksheet_write_number(ws, lxw_row_t(row), 14, Double(currentYear), styles.numberFormat)
            worksheet_write_number(ws, lxw_row_t(row), 15, 0, styles.numberFormat)
            worksheet_write_number(ws, lxw_row_t(row), 16, Double(currentYear), styles.numberFormat)
            worksheet_write_string(ws, lxw_row_t(row), 17, "\(asset.businessUsePercent)%", styles.dataFormat)
            worksheet_write_number(ws, lxw_row_t(row), 18, Double(currentYear * asset.businessUsePercent / 100), styles.numberFormat)
            worksheet_write_number(ws, lxw_row_t(row), 19, Double(endingBookValue), styles.numberFormat)
            worksheet_write_string(ws, lxw_row_t(row), 20, asset.memo ?? "", styles.dataFormat)
            row += 1
        }

        applyTemplateColumnWidths(worksheet: ws, template: template)
        applyTemplatePrintSettings(worksheet: ws, template: template, lastDataRow: max(row - 1, template.dataStartRow))
        addAuxiliarySheets(workbook: wb, styles: styles, template: template)
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

    private func addEntryGuideSheet(
        workbook: UnsafeMutablePointer<lxw_workbook>,
        styles: ExcelStyles,
        template: LedgerWorkbookTemplateDescriptor
    ) {
        addEntryGuideSheet(workbook: workbook, styles: styles, title: template.worksheetName)
    }

    private func addEntryGuideSheet(
        workbook: UnsafeMutablePointer<lxw_workbook>,
        styles: ExcelStyles,
        title: String
    ) {
        let ws = workbook_add_worksheet(workbook, "入力ガイド")!
        let lines = [
            "帳票名: \(title)",
            "この workbook はテンプレート準拠の見た目でアプリから再生成されています。",
            "明細列の意味はアプリ内の CSV / PDF 出力仕様と一致します。",
            "必要に応じてアプリ側のメタデータ項目を先頭シート上部に追記しています。"
        ]

        worksheet_merge_range(ws, 0, 0, 0, 5, "入力ガイド", styles.titleBandFormat)
        for (index, line) in lines.enumerated() {
            worksheet_write_string(ws, lxw_row_t(index + 2), 0, line, styles.dataFormat)
        }
        worksheet_set_column(ws, 0, 0, 56, nil)
    }

    private func writeOptionalNumber(
        _ value: Int?,
        worksheet: UnsafeMutablePointer<lxw_worksheet>,
        row: lxw_row_t,
        column: lxw_col_t,
        styles: ExcelStyles
    ) {
        guard let value, value != 0 else { return }
        worksheet_write_number(worksheet, row, column, Double(value), styles.numberFormat)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
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
        case .expenseBook:
            exportExpenseBook(metadata: metadata as! ExpenseBookMetadata,
                              entries: entries as! [ExpenseBookEntry],
                              includeInvoice: false, to: path)
        case .expenseBookInvoice:
            exportExpenseBook(metadata: metadata as! ExpenseBookMetadata,
                              entries: entries as! [ExpenseBookEntry],
                              includeInvoice: true, to: path)
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
        case .whiteTaxBookkeeping:
            exportWhiteTaxBookkeeping(metadata: metadata as! WhiteTaxBookkeepingMetadata,
                                      entries: entries as! [WhiteTaxBookkeepingEntry],
                                      includeInvoice: false, to: path)
        case .whiteTaxBookkeepingInvoice:
            exportWhiteTaxBookkeeping(metadata: metadata as! WhiteTaxBookkeepingMetadata,
                                      entries: entries as! [WhiteTaxBookkeepingEntry],
                                      includeInvoice: true, to: path)
        case .transportationExpense:
            exportTransportationExpense(metadata: metadata as! TransportationExpenseMetadata,
                                        entries: entries as! [TransportationExpenseEntry],
                                        to: path)
        case .fixedAssetRegister:
            exportFixedAssetRegister(metadata: metadata as! FixedAssetRegisterMetadata,
                                     entries: entries as! [FixedAssetRegisterEntry],
                                     to: path)
        case .fixedAssetDepreciation:
            exportFixedAssetDepreciation(entries: entries as! [FixedAssetDepreciationEntry],
                                         to: path)
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
