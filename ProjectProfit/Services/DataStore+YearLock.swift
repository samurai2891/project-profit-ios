import SwiftData
import SwiftUI

// MARK: - DataStore Year Lock Extension

extension DataStore {

    // MARK: - Year Lock Guard

    /// 指定日付の年度がロック済みか確認し、ロック済みならエラーを設定してtrueを返す
    func isYearLocked(for date: Date) -> Bool {
        let year = Calendar.current.component(.year, from: date)
        return isYearLocked(year)
    }

    /// 指定年度がロック済みか確認し、ロック済みならエラーを設定してtrueを返す
    func isYearLocked(_ year: Int) -> Bool {
        guard let profile = accountingProfile else { return false }
        if profile.isYearLocked(year) {
            lastError = .yearLocked(year: year)
            return true
        }
        return false
    }

    // MARK: - Lock / Unlock

    /// 指定年度をロックする
    func lockFiscalYear(_ year: Int) {
        guard let profile = accountingProfile else { return }
        profile.lockYear(year)
        save()
    }

    /// 指定年度のロックを解除する
    func unlockFiscalYear(_ year: Int) {
        guard let profile = accountingProfile else { return }
        profile.unlockYear(year)
        save()
    }
}
