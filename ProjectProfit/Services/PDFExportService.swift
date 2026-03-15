import UIKit
import Foundation

// MARK: - PDFExportService

/// A4 サイズ（595x842pt）の PDF を生成するサービス。
/// 純粋関数型の enum として実装し、外部状態への依存を排除する。
enum PDFExportService {

    // MARK: - Constants

    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
    private static let margin: CGFloat = 40
    private static let contentWidth = pageWidth - margin * 2
    private static let rowHeight: CGFloat = 20
    private static let headerFontSize: CGFloat = 16
    private static let subtitleFontSize: CGFloat = 11
    private static let tableFontSize: CGFloat = 10
    private static let tableHeaderFontSize: CGFloat = 10

    // MARK: - Reiwa Conversion

    /// 西暦から令和年へ変換する（2019年 = 令和1年）
    static func reiwaYear(from date: Date) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        return year - 2018
    }

    // MARK: - Export: Journal (仕訳帳)

    static func exportJournalPDF(
        entries: [PPJournalEntry],
        lines: [PPJournalLine],
        accounts: [PPAccount],
        fiscalYear: Int
    ) -> Data {
        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let linesByEntry = Dictionary(grouping: lines, by: \.entryId)

        let sortedEntries = entries
            .filter(\.isPosted)
            .sorted { $0.date < $1.date }

        let columns: [Column] = [
            Column(title: "日付", width: 70, alignment: .left),
            Column(title: "摘要", width: 130, alignment: .left),
            Column(title: "種別", width: 55, alignment: .left),
            Column(title: "借方科目", width: 80, alignment: .left),
            Column(title: "借方金額", width: 75, alignment: .right),
            Column(title: "貸方科目", width: 80, alignment: .left),
            Column(title: "貸方金額", width: 75, alignment: .right),
        ]

        var rows: [[String]] = []
        let dateFormatter = makeDateFormatter()

        for entry in sortedEntries {
            let entryLines = (linesByEntry[entry.id] ?? []).sorted { $0.displayOrder < $1.displayOrder }
            for (i, line) in entryLines.enumerated() {
                let accountName = accountMap[line.accountId]?.name ?? line.accountId
                let dateStr = i == 0 ? dateFormatter.string(from: entry.date) : ""
                let memoStr = i == 0 ? entry.memo : ""
                let typeStr = i == 0 ? entry.entryType.label : ""

                let debitAccount = line.debit > 0 ? accountName : ""
                let debitAmount = line.debit > 0 ? formatCurrency(line.debit) : ""
                let creditAccount = line.credit > 0 ? accountName : ""
                let creditAmount = line.credit > 0 ? formatCurrency(line.credit) : ""

                rows.append([dateStr, memoStr, typeStr, debitAccount, debitAmount, creditAccount, creditAmount])
            }
        }

        let reiwa = fiscalYear - 2018
        return renderPDF(
            title: "仕訳帳",
            subtitle: "令和\(reiwa)年度（\(fiscalYear)年）",
            columns: columns,
            rows: rows
        )
    }

    // MARK: - Export: Profit & Loss (損益計算書)

    static func exportProfitLossPDF(report: ProfitLossReport) -> Data {
        let reiwa = report.fiscalYear - 2018

        let columns: [Column] = [
            Column(title: "コード", width: 60, alignment: .left),
            Column(title: "勘定科目", width: 200, alignment: .left),
            Column(title: "金額", width: 120, alignment: .right),
            Column(title: "必要経費算入額", width: 135, alignment: .right),
        ]

        var rows: [[String]] = []

        // Revenue section
        rows.append(["", "【収益の部】", "", ""])
        for item in report.revenueItems {
            rows.append([item.code, item.name, formatCurrency(item.amount), formatCurrency(item.deductibleAmount)])
        }
        rows.append(["", "収益合計", formatCurrency(report.totalRevenue), ""])

        // Expense section
        rows.append(["", "【費用の部】", "", ""])
        for item in report.expenseItems {
            rows.append([item.code, item.name, formatCurrency(item.amount), formatCurrency(item.deductibleAmount)])
        }
        rows.append(["", "費用合計", formatCurrency(report.totalExpenses), ""])

        // Net income
        rows.append(["", "当期純利益", formatCurrency(report.netIncome), ""])

        return renderPDF(
            title: "損益計算書",
            subtitle: "令和\(reiwa)年度（\(report.fiscalYear)年）",
            columns: columns,
            rows: rows
        )
    }

    // MARK: - Export: Balance Sheet (貸借対照表)

    static func exportBalanceSheetPDF(report: BalanceSheetReport) -> Data {
        let reiwa = report.fiscalYear - 2018

        let columns: [Column] = [
            Column(title: "コード", width: 60, alignment: .left),
            Column(title: "勘定科目", width: 260, alignment: .left),
            Column(title: "残高", width: 195, alignment: .right),
        ]

        var rows: [[String]] = []

        // Assets
        rows.append(["", "【資産の部】", ""])
        for item in report.assetItems {
            rows.append([item.code, item.name, formatCurrency(item.balance)])
        }
        rows.append(["", "資産合計", formatCurrency(report.totalAssets)])

        // Liabilities
        rows.append(["", "【負債の部】", ""])
        for item in report.liabilityItems {
            rows.append([item.code, item.name, formatCurrency(item.balance)])
        }
        rows.append(["", "負債合計", formatCurrency(report.totalLiabilities)])

        // Equity
        rows.append(["", "【資本の部】", ""])
        for item in report.equityItems {
            rows.append([item.code, item.name, formatCurrency(item.balance)])
        }
        rows.append(["", "資本合計", formatCurrency(report.totalEquity)])

        // Balance check
        rows.append(["", "負債・資本合計", formatCurrency(report.liabilitiesAndEquity)])

        return renderPDF(
            title: "貸借対照表",
            subtitle: "令和\(reiwa)年度（\(report.fiscalYear)年）",
            columns: columns,
            rows: rows
        )
    }

    // MARK: - Export: Trial Balance (残高試算表)

    static func exportTrialBalancePDF(report: TrialBalanceReport) -> Data {
        let reiwa = report.fiscalYear - 2018

        let columns: [Column] = [
            Column(title: "コード", width: 50, alignment: .left),
            Column(title: "勘定科目", width: 130, alignment: .left),
            Column(title: "区分", width: 50, alignment: .left),
            Column(title: "借方", width: 90, alignment: .right),
            Column(title: "貸方", width: 90, alignment: .right),
            Column(title: "残高", width: 105, alignment: .right),
        ]

        var rows: [[String]] = report.rows.map { row in
            [row.code, row.name, row.accountType.label,
             formatCurrency(row.debit), formatCurrency(row.credit), formatCurrency(row.balance)]
        }

        // Totals
        rows.append(["", "合計", "",
                     formatCurrency(report.debitTotal),
                     formatCurrency(report.creditTotal),
                     ""])

        return renderPDF(
            title: "残高試算表",
            subtitle: "令和\(reiwa)年度（\(report.fiscalYear)年）",
            columns: columns,
            rows: rows
        )
    }

    // MARK: - Export: Ledger (元帳)

    static func exportLedgerPDF(
        accountName: String,
        accountCode: String,
        entries: [DataStore.LedgerEntry],
        fiscalYear: Int
    ) -> Data {
        let reiwa = fiscalYear - 2018
        let dateFormatter = makeDateFormatter()

        let columns: [Column] = [
            Column(title: "日付", width: 70, alignment: .left),
            Column(title: "摘要", width: 140, alignment: .left),
            Column(title: "種別", width: 55, alignment: .left),
            Column(title: "借方", width: 75, alignment: .right),
            Column(title: "貸方", width: 75, alignment: .right),
            Column(title: "残高", width: 100, alignment: .right),
        ]

        let rows: [[String]] = entries.map { entry in
            [dateFormatter.string(from: entry.date),
             entry.memo,
             entry.entryType.label,
             entry.debit > 0 ? formatCurrency(entry.debit) : "",
             entry.credit > 0 ? formatCurrency(entry.credit) : "",
             formatCurrency(entry.runningBalance)]
        }

        return renderPDF(
            title: "総勘定元帳 — \(accountCode) \(accountName)",
            subtitle: "令和\(reiwa)年度（\(fiscalYear)年）",
            columns: columns,
            rows: rows
        )
    }

    // MARK: - Export: Fixed Assets (固定資産台帳)

    static func exportFixedAssetsPDF(
        assets: [PPFixedAsset],
        fiscalYear: Int,
        calculateAccumulated: (PPFixedAsset) -> Int,
        calculateCurrentYear: (PPFixedAsset) -> Int
    ) -> Data {
        let reiwa = fiscalYear - 2018
        let dateFormatter = makeDateFormatter()

        let columns: [Column] = [
            Column(title: "資産名", width: 100, alignment: .left),
            Column(title: "取得日", width: 65, alignment: .left),
            Column(title: "取得価額", width: 70, alignment: .right),
            Column(title: "償却方法", width: 55, alignment: .left),
            Column(title: "耐用年数", width: 40, alignment: .right),
            Column(title: "当期償却", width: 70, alignment: .right),
            Column(title: "償却累計", width: 70, alignment: .right),
            Column(title: "状態", width: 45, alignment: .left),
        ]

        let rows: [[String]] = assets.map { asset in
            let currentYear = calculateCurrentYear(asset)
            let accumulated = calculateAccumulated(asset)

            return [
                asset.name,
                dateFormatter.string(from: asset.acquisitionDate),
                formatCurrency(asset.acquisitionCost),
                asset.depreciationMethod.label,
                "\(asset.usefulLifeYears)年",
                formatCurrency(currentYear),
                formatCurrency(accumulated),
                asset.assetStatus.label,
            ]
        }

        return renderPDF(
            title: "固定資産台帳",
            subtitle: "令和\(reiwa)年度（\(fiscalYear)年）",
            columns: columns,
            rows: rows
        )
    }

    // MARK: - Export: Withholding Statements

    static func exportWithholdingStatementAnnualPDF(summary: WithholdingStatementAnnualSummary) -> Data {
        let columns: [Column] = [
            Column(title: "支払先", width: 150, alignment: .left),
            Column(title: "源泉区分", width: 90, alignment: .left),
            Column(title: "件数", width: 40, alignment: .right),
            Column(title: "支払総額", width: 90, alignment: .right),
            Column(title: "源泉税額", width: 90, alignment: .right),
            Column(title: "実支払額", width: 95, alignment: .right),
        ]

        let rows = summary.documents.map { document in
            [
                document.counterpartyName,
                document.withholdingTaxCode.displayName,
                String(document.paymentCount),
                formatDecimalCurrency(document.totalGrossAmount),
                formatDecimalCurrency(document.totalWithholdingTaxAmount),
                formatDecimalCurrency(document.totalNetAmount),
            ]
        }

        return renderPDF(
            title: "支払調書一覧",
            subtitle: "\(summary.fiscalYear)年分",
            columns: columns,
            rows: rows
        )
    }

    static func exportWithholdingStatementPayeePDF(document: WithholdingStatementDocument) -> Data {
        let columns: [Column] = [
            Column(title: "支払日", width: 70, alignment: .left),
            Column(title: "摘要", width: 185, alignment: .left),
            Column(title: "支払総額", width: 85, alignment: .right),
            Column(title: "源泉税額", width: 85, alignment: .right),
            Column(title: "実支払額", width: 90, alignment: .right),
        ]

        let rows = document.rows.map { row in
            [
                makeDateFormatter().string(from: row.date),
                row.description,
                formatDecimalCurrency(row.grossAmount),
                formatDecimalCurrency(row.withholdingTaxAmount),
                formatDecimalCurrency(row.netAmount),
            ]
        }

        return renderPDF(
            title: "支払調書 — \(document.counterpartyName)",
            subtitle: "\(document.fiscalYear)年分 / \(document.withholdingTaxCode.displayName)",
            columns: columns,
            rows: rows
        )
    }

    // MARK: - Internal: Column Definition

    private struct Column {
        let title: String
        let width: CGFloat
        let alignment: NSTextAlignment
    }

    // MARK: - Internal: Date Formatter

    private static func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }

    private static let decimalCurrencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static func formatDecimalCurrency(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        return decimalCurrencyFormatter.string(from: number) ?? number.stringValue
    }

    // MARK: - Internal: PDF Rendering

    private static func renderPDF(
        title: String,
        subtitle: String,
        columns: [Column],
        rows: [[String]]
    ) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { context in
            var currentY = beginNewPage(context: context, title: title, subtitle: subtitle)

            // Table header
            currentY = drawTableHeader(columns: columns, y: currentY)

            // Table rows
            for row in rows {
                if currentY + rowHeight > pageHeight - margin {
                    currentY = beginNewPage(context: context, title: title, subtitle: subtitle)
                    currentY = drawTableHeader(columns: columns, y: currentY)
                }
                currentY = drawTableRow(columns: columns, values: row, y: currentY)
            }
        }
    }

    /// 新しいページを開始し、ヘッダーを描画して、テーブル開始Y座標を返す
    private static func beginNewPage(
        context: UIGraphicsPDFRendererContext,
        title: String,
        subtitle: String
    ) -> CGFloat {
        context.beginPage()
        return drawHeader(title: title, subtitle: subtitle, rect: pageRect)
    }

    /// ヘッダー（タイトル + サブタイトル）を描画し、次の描画開始Y座標を返す
    private static func drawHeader(title: String, subtitle: String, rect: CGRect) -> CGFloat {
        let titleFont = UIFont.systemFont(ofSize: headerFontSize, weight: .bold)
        let subtitleFont = UIFont.systemFont(ofSize: subtitleFontSize, weight: .regular)

        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.alignment = .center

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black,
            .paragraphStyle: titleParagraph,
        ]

        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: UIColor.darkGray,
            .paragraphStyle: titleParagraph,
        ]

        let titleRect = CGRect(x: margin, y: margin, width: contentWidth, height: 24)
        (title as NSString).draw(in: titleRect, withAttributes: titleAttributes)

        let subtitleRect = CGRect(x: margin, y: margin + 26, width: contentWidth, height: 18)
        (subtitle as NSString).draw(in: subtitleRect, withAttributes: subtitleAttributes)

        return margin + 54
    }

    /// テーブルヘッダー行（灰色背景）を描画し、次のY座標を返す
    private static func drawTableHeader(columns: [Column], y: CGFloat) -> CGFloat {
        let headerFont = UIFont.systemFont(ofSize: tableHeaderFontSize, weight: .semibold)

        // Gray background
        let headerRect = CGRect(x: margin, y: y, width: contentWidth, height: rowHeight)
        UIColor(white: 0.9, alpha: 1.0).setFill()
        UIBezierPath(rect: headerRect).fill()

        // Border
        UIColor(white: 0.6, alpha: 1.0).setStroke()
        let borderPath = UIBezierPath(rect: headerRect)
        borderPath.lineWidth = 0.5
        borderPath.stroke()

        // Column titles
        var x = margin
        for column in columns {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = column.alignment
            paragraph.lineBreakMode = .byTruncatingTail

            let attributes: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph,
            ]

            let cellRect = CGRect(x: x + 3, y: y + 2, width: column.width - 6, height: rowHeight - 4)
            (column.title as NSString).draw(in: cellRect, withAttributes: attributes)

            x += column.width
        }

        return y + rowHeight
    }

    /// テーブルデータ行を描画し、次のY座標を返す
    private static func drawTableRow(columns: [Column], values: [String], y: CGFloat) -> CGFloat {
        let bodyFont = UIFont.systemFont(ofSize: tableFontSize, weight: .regular)

        // Row border
        let rowRect = CGRect(x: margin, y: y, width: contentWidth, height: rowHeight)
        UIColor(white: 0.6, alpha: 1.0).setStroke()
        let borderPath = UIBezierPath(rect: rowRect)
        borderPath.lineWidth = 0.25
        borderPath.stroke()

        // Cell values
        var x = margin
        for (i, column) in columns.enumerated() {
            let value = i < values.count ? values[i] : ""

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = column.alignment
            paragraph.lineBreakMode = .byTruncatingTail

            // Section headers (【...】) are bold
            let isSectionHeader = value.hasPrefix("【")
            let font = isSectionHeader
                ? UIFont.systemFont(ofSize: tableFontSize, weight: .semibold)
                : bodyFont

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph,
            ]

            let cellRect = CGRect(x: x + 3, y: y + 2, width: column.width - 6, height: rowHeight - 4)
            (value as NSString).draw(in: cellRect, withAttributes: attributes)

            // Vertical gridline
            let linePath = UIBezierPath()
            linePath.move(to: CGPoint(x: x, y: y))
            linePath.addLine(to: CGPoint(x: x, y: y + rowHeight))
            linePath.lineWidth = 0.25
            linePath.stroke()

            x += column.width
        }

        // Right edge vertical line
        let rightLinePath = UIBezierPath()
        rightLinePath.move(to: CGPoint(x: x, y: y))
        rightLinePath.addLine(to: CGPoint(x: x, y: y + rowHeight))
        rightLinePath.lineWidth = 0.25
        rightLinePath.stroke()

        return y + rowHeight
    }
}
