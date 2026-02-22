import Foundation

enum FiscalYearSettings {
    static let defaultStartMonth = 4
    static let userDefaultsKey = "fiscalYearStartMonth"

    static var startMonth: Int {
        let stored = UserDefaults.standard.integer(forKey: userDefaultsKey)
        return (1...12).contains(stored) ? stored : defaultStartMonth
    }
}
