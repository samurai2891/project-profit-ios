import Foundation

/// リファクタリング機能フラグ
/// 新旧コード(canonical vs legacy)の段階的切り替えを制御する
enum FeatureFlags {

    private enum Keys {
        static let useCanonicalPosting = "ff_useCanonicalPosting"
        static let useLegacyLedger = "ff_useLegacyLedger"
        static let useCanonicalEvidence = "ff_useCanonicalEvidence"
        static let useCanonicalTaxEngine = "ff_useCanonicalTaxEngine"
    }

    /// 新正本系統 (Evidence → Candidate → PostedJournal) を使用
    static var useCanonicalPosting: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.useCanonicalPosting) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.useCanonicalPosting) }
    }

    /// 旧 LedgerDataStore を正本として使用
    static var useLegacyLedger: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.useLegacyLedger) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.useLegacyLedger)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.useLegacyLedger) }
    }

    /// 新証憑管理 (EvidenceDocument) を使用
    static var useCanonicalEvidence: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.useCanonicalEvidence) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.useCanonicalEvidence) }
    }

    /// 新消費税エンジンを使用
    static var useCanonicalTaxEngine: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.useCanonicalTaxEngine) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.useCanonicalTaxEngine) }
    }

    /// 全フラグをデフォルト（legacy ON）に戻す
    static func resetToDefaults() {
        useCanonicalPosting = false
        useLegacyLedger = true
        useCanonicalEvidence = false
        useCanonicalTaxEngine = false
    }

    /// 全フラグを canonical に切り替え（カットオーバー用）
    static func switchToCanonical() {
        useCanonicalPosting = true
        useLegacyLedger = false
        useCanonicalEvidence = true
        useCanonicalTaxEngine = true
    }

    /// デバッグ用: 現在のフラグ状態
    static var debugDescription: String {
        """
        FeatureFlags:
          useCanonicalPosting: \(useCanonicalPosting)
          useLegacyLedger: \(useLegacyLedger)
          useCanonicalEvidence: \(useCanonicalEvidence)
          useCanonicalTaxEngine: \(useCanonicalTaxEngine)
        """
    }
}
