import Foundation

// MARK: - CSVExportService

/// 各種帳票データを BOM 付き CSV 文字列に変換する純粋関数群。
/// DataStore への依存なし。呼び出し側がデータを渡す。
enum CSVExportService {

    // MARK: - Common Helpers

    /// BOM プレフィックス（Excel の日本語文字化け防止）
    private static let bom = "\u{FEFF}"

    /// フィールドをCSVセーフにエスケープする。
    /// カンマ・ダブルクォート・改行を含む場合はダブルクォートで囲み、
    /// 既存のダブルクォートは二重化する。
    static func escapeField(_ field: String) -> String {
        let needsQuoting = field.contains(",")
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")
        guard needsQuoting else { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// ヘッダ行 + データ行から BOM 付き CSV 文字列を構築する。
    static func buildCSV(headers: [String], rows: [[String]]) -> String {
        let headerLine = headers.map { escapeField($0) }.joined(separator: ",")
        let dataLines = rows.map { row in
            row.map { escapeField($0) }.joined(separator: ",")
        }
        let allLines = [headerLine] + dataLines
        return bom + allLines.joined(separator: "\r\n")
    }

    // MARK: - Date Formatter

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return formatter
    }()

    private static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    // MARK: - Journal CSV

    /// 仕訳帳 CSV を生成する。
    /// - Parameters:
    ///   - entries: 仕訳伝票の配列
    ///   - lines: 仕訳明細行の配列（全エントリ分）
    ///   - accounts: 勘定科目の配列（コード・名称の解決用）
    /// - Returns: BOM 付き CSV 文字列
    static func exportJournalCSV(
        entries: [PPJournalEntry],
        lines: [PPJournalLine],
        accounts: [PPAccount]
    ) -> String {
        let headers = ["日付", "仕訳番号", "勘定科目コード", "勘定科目名", "借方金額", "貸方金額", "摘要"]

        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let linesByEntry = Dictionary(grouping: lines, by: \.entryId)

        let sortedEntries = entries.sorted { $0.date < $1.date }

        let rows: [[String]] = sortedEntries.flatMap { entry -> [[String]] in
            let entryLines = (linesByEntry[entry.id] ?? [])
                .sorted { $0.displayOrder < $1.displayOrder }
            return entryLines.map { line in
                let account = accountMap[line.accountId]
                return [
                    formatDate(entry.date),
                    entry.sourceKey,
                    account?.code ?? "",
                    account?.name ?? line.accountId,
                    String(line.debit),
                    String(line.credit),
                    entry.memo,
                ]
            }
        }

        return buildCSV(headers: headers, rows: rows)
    }

    // MARK: - Profit & Loss CSV

    /// 損益計算書 CSV を生成する。
    /// セクション（売上 / 費用）ごとにグループ化し、小計・合計行を含む。
    static func exportProfitLossCSV(report: ProfitLossReport) -> String {
        let headers = ["勘定科目コード", "勘定科目名", "金額"]

        var rows: [[String]] = []

        // 売上（収益）
        rows.append(["", "【売上】", ""])
        for item in report.revenueItems {
            rows.append([item.code, item.name, String(item.amount)])
        }
        rows.append(["", "売上合計", String(report.totalRevenue)])

        // 費用
        rows.append(["", "【費用】", ""])
        for item in report.expenseItems {
            rows.append([item.code, item.name, String(item.amount)])
        }
        rows.append(["", "費用合計", String(report.totalExpenses)])

        // 純利益
        rows.append(["", "当期純利益", String(report.netIncome)])

        return buildCSV(headers: headers, rows: rows)
    }

    // MARK: - Balance Sheet CSV

    /// 貸借対照表 CSV を生成する。
    /// セクション（資産 / 負債 / 純資産）ごとにグループ化し、小計行を含む。
    static func exportBalanceSheetCSV(report: BalanceSheetReport) -> String {
        let headers = ["勘定科目コード", "勘定科目名", "金額"]

        var rows: [[String]] = []

        // 資産
        rows.append(["", "【資産】", ""])
        for item in report.assetItems {
            rows.append([item.code, item.name, String(item.balance)])
        }
        rows.append(["", "資産合計", String(report.totalAssets)])

        // 負債
        rows.append(["", "【負債】", ""])
        for item in report.liabilityItems {
            rows.append([item.code, item.name, String(item.balance)])
        }
        rows.append(["", "負債合計", String(report.totalLiabilities)])

        // 純資産（資本）
        rows.append(["", "【純資産】", ""])
        for item in report.equityItems {
            rows.append([item.code, item.name, String(item.balance)])
        }
        rows.append(["", "純資産合計", String(report.totalEquity)])

        return buildCSV(headers: headers, rows: rows)
    }

    // MARK: - Trial Balance CSV

    /// 試算表 CSV を生成する。
    static func exportTrialBalanceCSV(rows trialRows: [TrialBalanceRow]) -> String {
        let headers = ["勘定科目コード", "勘定科目名", "借方残高", "貸方残高"]

        let dataRows = trialRows.map { row in
            [row.code, row.name, String(row.debit), String(row.credit)]
        }

        return buildCSV(headers: headers, rows: dataRows)
    }

    // MARK: - Ledger CSV

    /// 勘定元帳 CSV を生成する。
    /// - Parameters:
    ///   - accountName: 勘定科目名（ヘッダ表示用）
    ///   - accountCode: 勘定科目コード（ヘッダ表示用）
    ///   - entries: 元帳エントリの配列
    /// - Returns: BOM 付き CSV 文字列
    static func exportLedgerCSV(
        accountName: String,
        accountCode: String,
        entries: [DataStore.LedgerEntry]
    ) -> String {
        let headers = ["日付", "摘要", "借方", "貸方", "残高"]

        let rows = entries.map { entry in
            [
                formatDate(entry.date),
                entry.memo,
                String(entry.debit),
                String(entry.credit),
                String(entry.runningBalance),
            ]
        }

        return buildCSV(headers: headers, rows: rows)
    }

    // MARK: - Fixed Assets CSV

    /// 固定資産台帳 CSV を生成する。
    /// 償却額の計算は呼び出し側が担当し、クロージャ経由で注入する。
    /// - Parameters:
    ///   - assets: 固定資産の配列
    ///   - calculateAccumulated: 累計償却額を計算するクロージャ
    ///   - calculateCurrentYear: 当期償却額を計算するクロージャ
    /// - Returns: BOM 付き CSV 文字列
    static func exportFixedAssetsCSV(
        assets: [PPFixedAsset],
        calculateAccumulated: (PPFixedAsset) -> Int,
        calculateCurrentYear: (PPFixedAsset) -> Int
    ) -> String {
        let headers = [
            "資産名", "取得日", "取得価額", "耐用年数",
            "償却方法", "当期償却額", "累計償却額", "帳簿価額",
        ]

        let rows = assets.map { asset in
            let accumulated = calculateAccumulated(asset)
            let currentYear = calculateCurrentYear(asset)
            let bookValue = asset.acquisitionCost - accumulated
            return [
                asset.name,
                formatDate(asset.acquisitionDate),
                String(asset.acquisitionCost),
                String(asset.usefulLifeYears),
                asset.depreciationMethod.label,
                String(currentYear),
                String(accumulated),
                String(bookValue),
            ]
        }

        return buildCSV(headers: headers, rows: rows)
    }
}
