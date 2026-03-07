import Foundation

/// 税務状態マシン
/// 個人事業主の全税制度状態遷移を定義し、不正な遷移を防止する
struct TaxStatusMachine: Sendable {

    /// 申告方式の遷移バリデーション（年分間）
    /// - Parameters:
    ///   - from: 前年分の申告方式
    ///   - to: 今年分の申告方式
    /// - Returns: 遷移が有効かどうか
    static func isValidFilingStyleTransition(
        from: FilingStyle,
        to: FilingStyle
    ) -> Bool {
        // 全ての遷移が許可される（年分ごとに独立）
        // ただし現金主義→一般は複式簿記への移行を伴う
        true
    }

    /// 消費税ステータスの遷移バリデーション
    static func isValidVatTransition(
        from: VatStatus,
        to: VatStatus,
        invoiceStatus: InvoiceIssuerStatus
    ) -> Bool {
        switch (from, to) {
        case (.exempt, .taxable):
            // 免税→課税: 常に可能
            return true
        case (.taxable, .exempt):
            // 課税→免税: インボイス登録中は不可
            return invoiceStatus != .registered
        case (.exempt, .exempt), (.taxable, .taxable):
            return true
        }
    }

    /// 消費税計算方式の有効な組み合わせを検証
    static func isValidVatMethodForStatus(
        vatStatus: VatStatus,
        vatMethod: VatMethod
    ) -> Bool {
        switch vatStatus {
        case .exempt:
            // 免税事業者は計算方式を持たない
            return false
        case .taxable:
            // 課税事業者は全方式が選択可能
            return true
        }
    }

    /// 青色控除レベルと記帳方式の整合性を検証
    static func isValidDeductionForBookkeeping(
        deductionLevel: BlueDeductionLevel,
        bookkeepingBasis: BookkeepingBasis,
        electronicBookLevel: ElectronicBookLevel
    ) -> Bool {
        switch deductionLevel {
        case .sixtyFive:
            // 65万: 複式簿記 + 優良電子帳簿 or e-Tax
            return bookkeepingBasis == .doubleEntry
        case .fiftyFive:
            // 55万: 複式簿記
            return bookkeepingBasis == .doubleEntry
        case .ten:
            // 10万: 簡易簿記でもOK
            return true
        case .none:
            return true
        }
    }

    /// 年度ロックの遷移バリデーション
    static func isValidLockTransition(
        from: YearLockState,
        to: YearLockState
    ) -> Bool {
        switch (from, to) {
        case (.open, .softClose): return true
        case (.softClose, .taxClose): return true
        case (.softClose, .open): return true  // 仮締め解除
        case (.taxClose, .filed): return true
        case (.taxClose, .softClose): return true  // 税務締め解除（調整前）
        case (.filed, .finalLock): return true
        // 逆方向の遷移は原則禁止
        case (.finalLock, _): return false
        case (.filed, .open), (.filed, .softClose), (.filed, .taxClose): return false
        default: return false
        }
    }

    /// TaxYearProfile の全体整合性バリデーション
    static func validate(_ profile: TaxYearProfile) -> [TaxValidationIssue] {
        var issues: [TaxValidationIssue] = []

        // 白色申告に青色控除は不可
        if !profile.filingStyle.isBlue && profile.blueDeductionLevel != .none {
            issues.append(.init(
                field: "blueDeductionLevel",
                message: "白色申告では青色申告特別控除は適用できません",
                severity: .error
            ))
        }

        // 現金主義で65万控除は不可
        if profile.filingStyle == .blueCashBasis && profile.blueDeductionLevel == .sixtyFive {
            issues.append(.init(
                field: "blueDeductionLevel",
                message: "現金主義では65万円控除は適用できません",
                severity: .error
            ))
        }

        // 現金主義は簡易簿記であるべき
        if profile.filingStyle == .blueCashBasis && profile.bookkeepingBasis != .cashBasis {
            issues.append(.init(
                field: "bookkeepingBasis",
                message: "現金主義の申告では記帳方式も現金主義にしてください",
                severity: .warning
            ))
        }

        // 控除と記帳方式の整合性
        if !isValidDeductionForBookkeeping(
            deductionLevel: profile.blueDeductionLevel,
            bookkeepingBasis: profile.bookkeepingBasis,
            electronicBookLevel: profile.electronicBookLevel
        ) {
            issues.append(.init(
                field: "bookkeepingBasis",
                message: "\(profile.blueDeductionLevel.displayName)には複式簿記が必要です",
                severity: .error
            ))
        }

        // 免税なのに消費税計算方式が設定されている
        if profile.vatStatus == .exempt && profile.vatMethod != .general {
            issues.append(.init(
                field: "vatMethod",
                message: "免税事業者に消費税計算方式は不要です",
                severity: .warning
            ))
        }

        // 簡易課税で業種区分が未設定
        if profile.vatMethod == .simplified && profile.simplifiedBusinessCategory == nil {
            issues.append(.init(
                field: "simplifiedBusinessCategory",
                message: "簡易課税では業種区分の設定が必要です",
                severity: .error
            ))
        }

        return issues
    }
}

/// 税務バリデーション問題
struct TaxValidationIssue: Sendable, Equatable {
    let field: String
    let message: String
    let severity: Severity

    enum Severity: String, Sendable {
        case error
        case warning
        case info
    }
}
