import Foundation
import SwiftData

@MainActor
protocol UserRuleRepository {
    func allRules() throws -> [PPUserRule]
    func saveChanges() throws
}
