// ============================================================
// LedgerPDFExportService.swift
// PDF(.pdf)出力サービス - 全11台帳対応
// UIGraphicsPDFRenderer ベースの描画
// ============================================================

import UIKit

final class LedgerPDFExportService {

    static let shared = LedgerPDFExportService()

    // MARK: - Constants

    private let pageSize = PDFLedgerConfig.a4Landscape
    private let margin: CGFloat = 40
    private let rowHeight: CGFloat = 18
    private let bodyFont = UIFont(name: "HiraginoSans-W3", size: 9) ?? UIFont.systemFont(ofSize: 9)
    private let headerFont = UIFont(name: "HiraginoSans-W6", size: 9) ?? UIFont.boldSystemFont(ofSize: 9)
    private let titleFont = UIFont(name: "HiraginoSans-W6", size: 14) ?? UIFont.boldSystemFont(ofSize: 14)
    private let headerBgColor = UIColor(red: 0.85, green: 0.88, blue: 0.95, alpha: 1.0)

    // MARK: - Cash Book

    func exportCashBook(metadata: CashBookMetadata, entries: [CashBookEntry], includeInvoice: Bool) -> Data {
        let headers: [String]
        let widths: [CGFloat]
        if includeInvoice {
            headers = ["月", "日", "摘要", "勘定科目", "軽減税率", "インボイス", "入金", "出金", "残高"]
            widths = [30, 30, 180, 100, 50, 60, 80, 80, 80]
        } else {
            headers = ["月", "日", "摘要", "勘定科目", "入金", "出金", "残高"]
            widths = [30, 30, 200, 120, 90, 90, 90]
        }
        let title = "現金出納帳"

        return renderPDF(title: title, headers: headers, columnWidths: widths) { context in
            var balance = metadata.carryForward
            let carryRow = self.makeRow(widths: widths, values: includeInvoice
                ? ["", "", "前期より繰越", "", "", "", "", "", formatNumber(balance)]
                : ["", "", "前期より繰越", "", "", "", formatNumber(balance)])
            context.drawDataRow(carryRow, italic: true)

            for entry in entries {
                let inc = entry.income ?? 0
                let exp = entry.expense ?? 0
                balance = balance + inc - exp
                let values: [String]
                if includeInvoice {
                    values = [
                        "\(entry.month)", "\(entry.day)", entry.description, entry.account,
                        entry.reducedTax == true ? "〇" : "", entry.invoiceType?.rawValue ?? "",
                        optNum(inc), optNum(exp), formatNumber(balance)
                    ]
                } else {
                    values = [
                        "\(entry.month)", "\(entry.day)", entry.description, entry.account,
                        optNum(inc), optNum(exp), formatNumber(balance)
                    ]
                }
                context.drawDataRow(self.makeRow(widths: widths, values: values))
            }
        }
    }

    // MARK: - Bank Account Book

    func exportBankAccountBook(metadata: BankAccountBookMetadata, entries: [BankAccountBookEntry], includeInvoice: Bool) -> Data {
        let headers: [String]
        let widths: [CGFloat]
        if includeInvoice {
            headers = ["月", "日", "摘要", "勘定科目", "軽減税率", "インボイス", "入金", "出金", "残高"]
            widths = [30, 30, 180, 100, 50, 60, 80, 80, 80]
        } else {
            headers = ["月", "日", "摘要", "勘定科目", "入金", "出金", "残高"]
            widths = [30, 30, 200, 120, 90, 90, 90]
        }
        let title = "預金出納帳"
        let subtitle = "銀行名: \(metadata.bankName)　支店名: \(metadata.branchName)"

        return renderPDF(title: title, subtitle: subtitle, headers: headers, columnWidths: widths) { context in
            var balance = metadata.carryForward
            let carryValues: [String] = includeInvoice
                ? ["", "", "前期より繰越", "", "", "", "", "", formatNumber(balance)]
                : ["", "", "前期より繰越", "", "", "", formatNumber(balance)]
            context.drawDataRow(self.makeRow(widths: widths, values: carryValues), italic: true)

            for entry in entries {
                let dep = entry.deposit ?? 0
                let wd = entry.withdrawal ?? 0
                balance = balance + dep - wd
                let values: [String]
                if includeInvoice {
                    values = [
                        "\(entry.month)", "\(entry.day)", entry.description, entry.account,
                        entry.reducedTax == true ? "〇" : "", entry.invoiceType?.rawValue ?? "",
                        optNum(dep), optNum(wd), formatNumber(balance)
                    ]
                } else {
                    values = [
                        "\(entry.month)", "\(entry.day)", entry.description, entry.account,
                        optNum(dep), optNum(wd), formatNumber(balance)
                    ]
                }
                context.drawDataRow(self.makeRow(widths: widths, values: values))
            }
        }
    }

    // MARK: - Accounts Receivable

    func exportAccountsReceivable(metadata: AccountsReceivableMetadata, entries: [AccountsReceivableEntry]) -> Data {
        let headers = ["月", "日", "相手科目", "摘要", "数量", "単価", "売上金額", "入金金額", "残高"]
        let widths: [CGFloat] = [30, 30, 90, 160, 60, 70, 80, 80, 80]
        let subtitle = "得意先名: \(metadata.clientName)"

        return renderPDF(title: "売掛帳", subtitle: subtitle, headers: headers, columnWidths: widths) { context in
            var balance = metadata.carryForward
            context.drawDataRow(self.makeRow(widths: widths, values: ["", "", "", "前期より繰越", "", "", "", "", formatNumber(balance)]), italic: true)

            for entry in entries {
                let sales = entry.salesAmount ?? 0
                let received = entry.receivedAmount ?? 0
                balance = balance + sales - received
                let qty: String = entry.quantity.map { "\($0)" } ?? ""
                let uPrice: String = entry.unitPrice.map { self.formatNumber($0) } ?? ""
                let values: [String] = [
                    "\(entry.month)", "\(entry.day)", entry.counterAccount, entry.description,
                    qty, uPrice, self.optNum(sales), self.optNum(received), self.formatNumber(balance)
                ]
                context.drawDataRow(self.makeRow(widths: widths, values: values))
            }
        }
    }

    // MARK: - Accounts Payable

    func exportAccountsPayable(metadata: AccountsPayableMetadata, entries: [AccountsPayableEntry]) -> Data {
        let headers = ["月", "日", "相手科目", "摘要", "数量", "単価", "仕入金額", "支払金額", "残高"]
        let widths: [CGFloat] = [30, 30, 90, 160, 60, 70, 80, 80, 80]
        let subtitle = "仕入先名: \(metadata.supplierName)"

        return renderPDF(title: "買掛帳", subtitle: subtitle, headers: headers, columnWidths: widths) { context in
            var balance = metadata.carryForward
            context.drawDataRow(self.makeRow(widths: widths, values: ["", "", "", "前期より繰越", "", "", "", "", self.formatNumber(balance)]), italic: true)

            for entry in entries {
                let purchase = entry.purchaseAmount ?? 0
                let payment = entry.paymentAmount ?? 0
                balance = balance + purchase - payment
                let qty: String = entry.quantity.map { "\($0)" } ?? ""
                let uPrice: String = entry.unitPrice.map { self.formatNumber($0) } ?? ""
                let values: [String] = [
                    "\(entry.month)", "\(entry.day)", entry.counterAccount, entry.description,
                    qty, uPrice, self.optNum(purchase), self.optNum(payment), self.formatNumber(balance)
                ]
                context.drawDataRow(self.makeRow(widths: widths, values: values))
            }
        }
    }

    // MARK: - Expense Book

    func exportExpenseBook(metadata: ExpenseBookMetadata, entries: [ExpenseBookEntry], includeInvoice: Bool) -> Data {
        let headers: [String]
        let widths: [CGFloat]
        if includeInvoice {
            headers = ["月", "日", "相手科目", "摘要", "軽減税率", "インボイス", "金額", "累計"]
            widths = [30, 30, 100, 180, 50, 60, 80, 80]
        } else {
            headers = ["月", "日", "相手科目", "摘要", "金額", "累計"]
            widths = [30, 30, 120, 220, 100, 100]
        }

        return renderPDF(title: "経費帳（\(metadata.accountName)）", headers: headers, columnWidths: widths) { context in
            var total = 0
            for entry in entries {
                total += entry.amount
                let values: [String]
                if includeInvoice {
                    values = [
                        "\(entry.month)", "\(entry.day)", entry.counterAccount, entry.description,
                        entry.reducedTax == true ? "〇" : "", entry.invoiceType?.rawValue ?? "",
                        formatNumber(entry.amount), formatNumber(total)
                    ]
                } else {
                    values = [
                        "\(entry.month)", "\(entry.day)", entry.counterAccount, entry.description,
                        formatNumber(entry.amount), formatNumber(total)
                    ]
                }
                context.drawDataRow(self.makeRow(widths: widths, values: values))
            }
        }
    }

    // MARK: - General Ledger

    func exportGeneralLedger(metadata: GeneralLedgerMetadata, entries: [GeneralLedgerEntry], includeInvoice: Bool) -> Data {
        let headers: [String]
        let widths: [CGFloat]
        if includeInvoice {
            headers = ["月", "日", "相手科目", "摘要", "軽減税率", "インボイス", "借方", "貸方", "差引残高"]
            widths = [30, 30, 90, 150, 50, 60, 80, 80, 80]
        } else {
            headers = ["月", "日", "相手科目", "摘要", "借方", "貸方", "差引残高"]
            widths = [30, 30, 100, 200, 90, 90, 90]
        }
        let isDebitNature = metadata.accountAttribute == .asset || metadata.accountAttribute == .expense
        let subtitle = "勘定科目: \(metadata.accountName)　属性: \(metadata.accountAttribute?.rawValue ?? "資産")"

        return renderPDF(title: "総勘定元帳", subtitle: subtitle, headers: headers, columnWidths: widths) { context in
            var balance = metadata.carryForward
            let carryValues: [String] = includeInvoice
                ? ["", "", "", "前期より繰越", "", "", "", "", formatNumber(balance)]
                : ["", "", "", "前期より繰越", "", "", formatNumber(balance)]
            context.drawDataRow(self.makeRow(widths: widths, values: carryValues), italic: true)

            for entry in entries {
                let d = entry.debit ?? 0
                let c = entry.credit ?? 0
                balance = isDebitNature ? balance + d - c : balance + c - d
                let values: [String]
                if includeInvoice {
                    values = [
                        "\(entry.month)", "\(entry.day)", entry.counterAccount, entry.description,
                        entry.reducedTax == true ? "〇" : "", entry.invoiceType?.rawValue ?? "",
                        optNum(d), optNum(c), formatNumber(balance)
                    ]
                } else {
                    values = [
                        "\(entry.month)", "\(entry.day)", entry.counterAccount, entry.description,
                        optNum(d), optNum(c), formatNumber(balance)
                    ]
                }
                context.drawDataRow(self.makeRow(widths: widths, values: values))
            }
        }
    }

    // MARK: - Journal

    func exportJournal(entries: [JournalEntry]) -> Data {
        let headers = ["月", "日", "借方科目", "借方金額", "貸方科目", "貸方金額", "摘要"]
        let widths: [CGFloat] = [30, 30, 110, 90, 110, 90, 200]

        return renderPDF(title: "仕訳帳", headers: headers, columnWidths: widths) { context in
            for entry in entries {
                let monthStr: String = entry.isCompoundContinuation ? "" : "\(entry.month)"
                let dayStr: String = entry.isCompoundContinuation ? "" : "\(entry.day)"
                let da: String = entry.debitAccount ?? ""
                let dam: String = entry.debitAmount.map { self.formatNumber($0) } ?? ""
                let ca: String = entry.creditAccount ?? ""
                let cam: String = entry.creditAmount.map { self.formatNumber($0) } ?? ""
                let values: [String] = [monthStr, dayStr, da, dam, ca, cam, entry.description]
                context.drawDataRow(self.makeRow(widths: widths, values: values))
            }
        }
    }

    // MARK: - Transportation Expense

    func exportTransportationExpense(metadata: TransportationExpenseMetadata, entries: [TransportationExpenseEntry]) -> Data {
        let headers = ["日付", "行先", "目的", "交通機関", "出発地", "到着地", "片/往", "金額"]
        let widths: [CGFloat] = [70, 100, 100, 80, 80, 80, 40, 80]
        let subtitle = "所属: \(metadata.department)　氏名: \(metadata.employeeName)"

        return renderPDF(title: "交通費精算書", subtitle: subtitle, headers: headers, columnWidths: widths) { context in
            for entry in entries {
                let values = [
                    entry.date, entry.destination, entry.purpose, entry.transportMethod,
                    entry.routeFrom, entry.routeTo, entry.tripType.rawValue,
                    formatNumber(entry.amount)
                ]
                context.drawDataRow(self.makeRow(widths: widths, values: values))
            }
        }
    }

    // MARK: - White Tax Bookkeeping

    func exportWhiteTaxBookkeeping(metadata: WhiteTaxBookkeepingMetadata, entries: [WhiteTaxBookkeepingEntry], includeInvoice: Bool) -> Data {
        let headers = ["月", "日", "摘要", "売上", "雑収入", "仕入", "経費計"]
        let widths: [CGFloat] = [30, 30, 180, 80, 80, 80, 80]

        return renderPDF(title: "白色申告用 簡易帳簿（\(metadata.fiscalYear)年）", headers: headers, columnWidths: widths) { context in
            for entry in entries {
                let expenseTotal = [
                    entry.salaries, entry.outsourcing, entry.depreciation, entry.badDebts,
                    entry.rent, entry.interestDiscount, entry.taxesDuties, entry.packingShipping,
                    entry.utilities, entry.travelTransport, entry.communication, entry.advertising,
                    entry.entertainment, entry.insurance, entry.repairs, entry.supplies,
                    entry.welfare, entry.miscellaneous
                ].compactMap { $0 }.reduce(0, +)

                let salesStr: String = entry.salesAmount.map { self.formatNumber($0) } ?? ""
                let miscStr: String = entry.miscIncome.map { self.formatNumber($0) } ?? ""
                let purchStr: String = entry.purchases.map { self.formatNumber($0) } ?? ""
                let expStr: String = expenseTotal > 0 ? self.formatNumber(expenseTotal) : ""
                let values: [String] = [
                    "\(entry.month)", "\(entry.day)", entry.description,
                    salesStr, miscStr, purchStr, expStr
                ]
                context.drawDataRow(self.makeRow(widths: widths, values: values))
            }
        }
    }

    // MARK: - Fixed Asset Depreciation

    func exportFixedAssetDepreciation(entries: [FixedAssetDepreciationEntry]) -> Data {
        let headers = ["勘定科目", "資産名", "種類", "取得日", "取得価額", "償却方法", "耐用年数", "償却率", "期首帳簿価額", "減価償却費"]
        let widths: [CGFloat] = [70, 80, 60, 65, 70, 50, 45, 45, 70, 70]

        return renderPDF(title: "固定資産台帳 兼 減価償却計算表", headers: headers, columnWidths: widths) { context in
            for entry in entries {
                let depExp = Int(Double(entry.openingBookValue) * entry.depreciationRate)
                let values = [
                    entry.account, entry.assetName, entry.assetType,
                    entry.acquisitionDate, formatNumber(entry.acquisitionCost),
                    entry.depreciationMethod.rawValue, "\(entry.usefulLife)",
                    String(format: "%.3f", entry.depreciationRate),
                    formatNumber(entry.openingBookValue), formatNumber(depExp)
                ]
                context.drawDataRow(self.makeRow(widths: widths, values: values))
            }
        }
    }

    // MARK: - Fixed Asset Register

    func exportFixedAssetRegister(metadata: FixedAssetRegisterMetadata, entries: [FixedAssetRegisterEntry]) -> Data {
        let headers = ["日付", "摘要", "取得数量", "取得単価", "取得金額", "償却額", "異動数量", "異動金額", "事業専用割合"]
        let widths: [CGFloat] = [65, 140, 60, 70, 70, 70, 60, 70, 60]
        let subtitle = "名称: \(metadata.assetName)　種類: \(metadata.assetType)"

        return renderPDF(title: "固定資産台帳", subtitle: subtitle, headers: headers, columnWidths: widths) { context in
            for entry in entries {
                let aqQty: String = entry.acquiredQuantity.map { "\($0)" } ?? ""
                let aqPrice: String = entry.acquiredUnitPrice.map { self.formatNumber($0) } ?? ""
                let aqAmt: String = entry.acquiredAmount.map { self.formatNumber($0) } ?? ""
                let depAmt: String = entry.depreciationAmount.map { self.formatNumber($0) } ?? ""
                let disQty: String = entry.disposalQuantity.map { "\($0)" } ?? ""
                let disAmt: String = entry.disposalAmount.map { self.formatNumber($0) } ?? ""
                let bizRatio: String = entry.businessUseRatio.map { String(format: "%.0f%%", $0 * 100) } ?? ""
                let values: [String] = [entry.date, entry.description, aqQty, aqPrice, aqAmt, depAmt, disQty, disAmt, bizRatio]
                context.drawDataRow(self.makeRow(widths: widths, values: values))
            }
        }
    }

    // MARK: - PDF Rendering Engine

    struct RowData {
        let values: [String]
        let widths: [CGFloat]
        let alignments: [NSTextAlignment]
    }

    private func makeRow(widths: [CGFloat], values: [String]) -> RowData {
        let alignments: [NSTextAlignment] = values.enumerated().map { idx, val in
            if idx < 2 { return .center }
            if let _ = Int(val.replacingOccurrences(of: ",", with: "")) { return .right }
            return .left
        }
        return RowData(values: values, widths: widths, alignments: alignments)
    }

    private func renderPDF(
        title: String,
        subtitle: String? = nil,
        headers: [String],
        columnWidths: [CGFloat],
        drawRows: (PDFDrawingContext) -> Void
    ) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: pageSize),
            format: format
        )

        return renderer.pdfData { pdfContext in
            let drawCtx = PDFDrawingContext(
                pdfContext: pdfContext,
                pageSize: pageSize,
                margin: margin,
                rowHeight: rowHeight,
                bodyFont: bodyFont,
                headerFont: headerFont,
                titleFont: titleFont,
                headerBgColor: headerBgColor,
                title: title,
                subtitle: subtitle,
                headers: headers,
                columnWidths: columnWidths
            )
            drawCtx.beginNewPage()
            drawRows(drawCtx)
        }
    }

    // MARK: - Number Formatting

    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func optNum(_ value: Int) -> String {
        value == 0 ? "" : formatNumber(value)
    }
}

// MARK: - PDF Drawing Context

private class PDFDrawingContext {
    let pdfContext: UIGraphicsPDFRendererContext
    let pageSize: CGSize
    let margin: CGFloat
    let rowHeight: CGFloat
    let bodyFont: UIFont
    let headerFont: UIFont
    let titleFont: UIFont
    let headerBgColor: UIColor
    let title: String
    let subtitle: String?
    let headers: [String]
    let columnWidths: [CGFloat]

    var currentY: CGFloat = 0
    private let lineColor = UIColor.gray

    init(pdfContext: UIGraphicsPDFRendererContext, pageSize: CGSize, margin: CGFloat,
         rowHeight: CGFloat, bodyFont: UIFont, headerFont: UIFont, titleFont: UIFont,
         headerBgColor: UIColor, title: String, subtitle: String?,
         headers: [String], columnWidths: [CGFloat]) {
        self.pdfContext = pdfContext
        self.pageSize = pageSize
        self.margin = margin
        self.rowHeight = rowHeight
        self.bodyFont = bodyFont
        self.headerFont = headerFont
        self.titleFont = titleFont
        self.headerBgColor = headerBgColor
        self.title = title
        self.subtitle = subtitle
        self.headers = headers
        self.columnWidths = columnWidths
    }

    func beginNewPage() {
        pdfContext.beginPage()
        currentY = margin
        drawTitle()
        if let subtitle {
            drawSubtitle(subtitle)
        }
        drawHeaders()
    }

    private func drawTitle() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ]
        let titleSize = title.size(withAttributes: attrs)
        let x = (pageSize.width - titleSize.width) / 2
        title.draw(at: CGPoint(x: x, y: currentY), withAttributes: attrs)
        currentY += titleSize.height + 8
    }

    private func drawSubtitle(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.darkGray
        ]
        text.draw(at: CGPoint(x: margin, y: currentY), withAttributes: attrs)
        currentY += bodyFont.lineHeight + 6
    }

    func drawHeaders() {
        let totalWidth = columnWidths.reduce(0, +)
        let startX = (pageSize.width - totalWidth) / 2

        // Background
        let headerRect = CGRect(x: startX, y: currentY, width: totalWidth, height: rowHeight)
        headerBgColor.setFill()
        UIBezierPath(rect: headerRect).fill()

        // Text + borders
        var x = startX
        for (i, header) in headers.enumerated() {
            let cellRect = CGRect(x: x, y: currentY, width: columnWidths[i], height: rowHeight)
            drawCellBorder(cellRect)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: UIColor.black
            ]
            let textSize = header.size(withAttributes: attrs)
            let textX = x + (columnWidths[i] - textSize.width) / 2
            let textY = currentY + (rowHeight - textSize.height) / 2
            header.draw(at: CGPoint(x: textX, y: textY), withAttributes: attrs)

            x += columnWidths[i]
        }
        currentY += rowHeight
    }

    func drawDataRow(_ row: LedgerPDFExportService.RowData, italic: Bool = false) {
        checkPageBreak()

        let totalWidth = columnWidths.reduce(0, +)
        let startX = (pageSize.width - totalWidth) / 2

        var x = startX
        for (i, value) in row.values.enumerated() {
            guard i < columnWidths.count else { break }
            let cellRect = CGRect(x: x, y: currentY, width: columnWidths[i], height: rowHeight)
            drawCellBorder(cellRect)

            let font: UIFont = italic
                ? UIFont.italicSystemFont(ofSize: bodyFont.pointSize)
                : bodyFont
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black
            ]
            let textSize = value.size(withAttributes: attrs)
            let textY = currentY + (rowHeight - textSize.height) / 2
            let padding: CGFloat = 4

            let textX: CGFloat
            switch row.alignments[i] {
            case .right:
                textX = x + columnWidths[i] - textSize.width - padding
            case .center:
                textX = x + (columnWidths[i] - textSize.width) / 2
            default:
                textX = x + padding
            }

            value.draw(at: CGPoint(x: textX, y: textY), withAttributes: attrs)
            x += columnWidths[i]
        }
        currentY += rowHeight
    }

    private func drawCellBorder(_ rect: CGRect) {
        lineColor.setStroke()
        let path = UIBezierPath(rect: rect)
        path.lineWidth = 0.5
        path.stroke()
    }

    private func checkPageBreak() {
        let bottomMargin = margin + rowHeight
        if currentY + rowHeight > pageSize.height - bottomMargin {
            beginNewPage()
        }
    }
}
