import Foundation

enum SubLedgerType: String, CaseIterable, Identifiable {
    case cashBook
    case accountsReceivableBook
    case accountsPayableBook
    case expenseBook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cashBook: "現金出納帳"
        case .accountsReceivableBook: "売掛帳"
        case .accountsPayableBook: "買掛帳"
        case .expenseBook: "経費帳"
        }
    }

    var subtitle: String {
        switch self {
        case .cashBook: "現金勘定の増減明細"
        case .accountsReceivableBook: "売掛金の増減明細"
        case .accountsPayableBook: "買掛金の増減明細"
        case .expenseBook: "費用科目の明細"
        }
    }
}

struct SubLedgerEntry: Identifiable {
    let id: UUID
    let date: Date
    let accountId: String
    let accountCode: String
    let accountName: String
    let memo: String
    let debit: Int
    let credit: Int
    let runningBalance: Int
}

struct SubLedgerSummary {
    let count: Int
    let debitTotal: Int
    let creditTotal: Int
    let periodStart: Date?
    let periodEnd: Date?
}

extension DataStore {
    func subLedgerAccountIds(for type: SubLedgerType) -> [String] {
        switch type {
        case .cashBook:
            return [AccountingConstants.cashAccountId]
        case .accountsReceivableBook:
            return [AccountingConstants.accountsReceivableAccountId]
        case .accountsPayableBook:
            return [AccountingConstants.accountsPayableAccountId]
        case .expenseBook:
            return accounts.filter { $0.isActive && $0.accountType == .expense }.map(\.id)
        }
    }

    func getSubLedgerEntries(
        type: SubLedgerType,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> [SubLedgerEntry] {
        let accountIds = subLedgerAccountIds(for: type)
        guard !accountIds.isEmpty else { return [] }

        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        var merged: [SubLedgerEntry] = []
        merged.reserveCapacity(accountIds.count * 50)

        for accountId in accountIds {
            let account = accountMap[accountId]
            let code = account?.code ?? accountId
            let name = account?.name ?? accountId
            let rows = getLedgerEntries(accountId: accountId, startDate: startDate, endDate: endDate)
            merged.append(contentsOf: rows.map { row in
                SubLedgerEntry(
                    id: row.id,
                    date: row.date,
                    accountId: accountId,
                    accountCode: code,
                    accountName: name,
                    memo: row.memo,
                    debit: row.debit,
                    credit: row.credit,
                    runningBalance: row.runningBalance
                )
            })
        }

        return merged.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.accountCode != $1.accountCode { return $0.accountCode < $1.accountCode }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func getSubLedgerSummary(
        type: SubLedgerType,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> SubLedgerSummary {
        let entries = getSubLedgerEntries(type: type, startDate: startDate, endDate: endDate)
        return SubLedgerSummary(
            count: entries.count,
            debitTotal: entries.reduce(0) { $0 + $1.debit },
            creditTotal: entries.reduce(0) { $0 + $1.credit },
            periodStart: startDate,
            periodEnd: endDate
        )
    }

    func exportSubLedgerCSV(
        type: SubLedgerType,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> String {
        let rows = getSubLedgerEntries(type: type, startDate: startDate, endDate: endDate)
        var lines: [String] = ["date,accountCode,accountName,memo,debit,credit,runningBalance"]
        let formatter = ISO8601DateFormatter()
        for row in rows {
            let dateText = formatter.string(from: row.date)
            let memo = row.memo.replacingOccurrences(of: "\"", with: "\"\"")
            let accountName = row.accountName.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append("\(dateText),\(row.accountCode),\"\(accountName)\",\"\(memo)\",\(row.debit),\(row.credit),\(row.runningBalance)")
        }
        return lines.joined(separator: "\n")
    }
}
