import Foundation

@MainActor
protocol DataRevisionRepository {
    func dashboardRevisionKey() throws -> String
    func reportRevisionKey() throws -> String
    func transactionsRevisionKey() throws -> String
}
