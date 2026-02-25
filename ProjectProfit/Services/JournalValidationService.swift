import Foundation

// MARK: - Journal Validation Issues

/// 仕訳バリデーションエラーの詳細
enum JournalValidationIssue: Equatable, CustomStringConvertible {
    /// 借方合計 ≠ 貸方合計
    case unbalanced(debitTotal: Int, creditTotal: Int)
    /// 勘定科目 ID が存在しない
    case missingAccount(accountId: String)
    /// 明細行の借方・貸方が不正（両方正 or 両方ゼロ）
    case invalidLine(lineId: UUID, debit: Int, credit: Int)
    /// 日付が会計年度範囲外
    case dateOutOfFiscalYear(date: Date, fiscalYear: Int)
    /// ロック済み年度への書き込み
    case lockedFiscalYear(year: Int)
    /// 明細行が空
    case emptyEntry

    var description: String {
        switch self {
        case let .unbalanced(debit, credit):
            "貸借不一致: 借方合計=\(debit), 貸方合計=\(credit)"
        case let .missingAccount(accountId):
            "勘定科目が見つかりません: \(accountId)"
        case let .invalidLine(lineId, debit, credit):
            "不正な明細行 (id=\(lineId)): 借方=\(debit), 貸方=\(credit)"
        case let .dateOutOfFiscalYear(date, year):
            "日付 \(date) が会計年度 \(year) の範囲外です"
        case let .lockedFiscalYear(year):
            "\(year)年度はロック済みのため書き込みできません"
        case .emptyEntry:
            "仕訳に明細行がありません"
        }
    }
}

// MARK: - JournalValidationService

/// 仕訳バリデーションサービス（Todo.md 4B-6 準拠）
/// ステートレスなバリデーションロジックを提供する
enum JournalValidationService {

    // MARK: - Entry-Level Validation

    /// PPJournalEntry とその明細行を包括的にバリデーションする
    static func validateEntry(
        _ entry: PPJournalEntry,
        lines: [PPJournalLine],
        accounts: [PPAccount] = [],
        profile: PPAccountingProfile? = nil
    ) -> [JournalValidationIssue] {
        var issues: [JournalValidationIssue] = []

        // 明細行が空
        if lines.isEmpty {
            issues.append(.emptyEntry)
            return issues
        }

        // 各明細行の個別チェック
        issues.append(contentsOf: validateLines(lines))

        // 借方/貸方合計の一致チェック
        let debitTotal = lines.reduce(0) { $0 + $1.debit }
        let creditTotal = lines.reduce(0) { $0 + $1.credit }
        if debitTotal != creditTotal {
            issues.append(.unbalanced(debitTotal: debitTotal, creditTotal: creditTotal))
        }

        // 勘定科目の存在チェック（accounts が渡された場合のみ）
        if !accounts.isEmpty {
            let accountIds = Set(accounts.map(\.id))
            for line in lines where !accountIds.contains(line.accountId) {
                issues.append(.missingAccount(accountId: line.accountId))
            }
        }

        // 年度ロックチェック（profile が渡された場合のみ）
        if let profile, profile.isLocked {
            let calendar = Calendar(identifier: .gregorian)
            let entryYear = calendar.component(.year, from: entry.date)
            if entryYear == profile.fiscalYear {
                issues.append(.lockedFiscalYear(year: profile.fiscalYear))
            }
        }

        return issues
    }

    // MARK: - Line-Level Validation

    /// 明細行のみのバリデーション（借方・貸方の整合性チェック）
    static func validateLines(_ lines: [PPJournalLine]) -> [JournalValidationIssue] {
        var issues: [JournalValidationIssue] = []
        for line in lines {
            // 借方と貸方の両方が正の値、または両方がゼロ
            if (line.debit > 0 && line.credit > 0) || (line.debit == 0 && line.credit == 0) {
                issues.append(.invalidLine(lineId: line.id, debit: line.debit, credit: line.credit))
            }
            // 負の値チェック
            if line.debit < 0 || line.credit < 0 {
                issues.append(.invalidLine(lineId: line.id, debit: line.debit, credit: line.credit))
            }
        }
        return issues
    }

    // MARK: - Fiscal Year Validation

    /// 日付が指定会計年度内かどうかをチェックする
    static func validateDateInFiscalYear(
        date: Date,
        fiscalYear: Int,
        startMonth: Int = 1
    ) -> JournalValidationIssue? {
        let calendar = Calendar(identifier: .gregorian)
        guard let fiscalStart = calendar.date(from: DateComponents(year: fiscalYear, month: startMonth, day: 1)),
              let fiscalEnd = calendar.date(from: DateComponents(year: fiscalYear + (startMonth > 1 ? 1 : 0), month: startMonth > 1 ? startMonth - 1 : 12, day: 1))
        else {
            return .dateOutOfFiscalYear(date: date, fiscalYear: fiscalYear)
        }

        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: fiscalEnd),
              let endOfFiscalYear = calendar.date(byAdding: .day, value: -1, to: nextMonth)
        else {
            return .dateOutOfFiscalYear(date: date, fiscalYear: fiscalYear)
        }

        if date < fiscalStart || date > endOfFiscalYear {
            return .dateOutOfFiscalYear(date: date, fiscalYear: fiscalYear)
        }
        return nil
    }
}
