import SwiftData
import SwiftUI

@MainActor
@Observable
final class ClassificationViewModel {
    private let dataStore: DataStore

    var results: [(transaction: PPTransaction, result: ClassificationEngine.ClassificationResult)] = []
    var userRules: [PPUserRule] = []

    init(dataStore: DataStore) {
        self.dataStore = dataStore
        refresh()
    }

    func refresh() {
        loadUserRules()
        classifyAll()
    }

    private func loadUserRules() {
        do {
            let descriptor = FetchDescriptor<PPUserRule>(sortBy: [SortDescriptor(\.priority, order: .reverse)])
            userRules = try dataStore.modelContext.fetch(descriptor)
        } catch {
            userRules = []
        }
    }

    private func classifyAll() {
        results = ClassificationEngine.classifyBatch(
            transactions: dataStore.transactions,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: userRules
        )
    }

    var unclassifiedResults: [(transaction: PPTransaction, result: ClassificationEngine.ClassificationResult)] {
        results.filter { $0.result.source == .fallback }
    }

    var classifiedCount: Int {
        results.count - unclassifiedResults.count
    }

    // MARK: - 学習フィードバック (9B)

    /// ユーザーの手動分類修正を学習し、PPUserRuleを自動生成・更新する
    func correctClassification(transactionId: UUID, newTaxLine: TaxLine) {
        guard let transaction = dataStore.transactions.first(where: { $0.id == transactionId }) else {
            return
        }

        ClassificationLearningService.learnFromCorrection(
            transaction: transaction,
            correctedTaxLine: newTaxLine,
            existingRules: userRules,
            modelContext: dataStore.modelContext
        )
        dataStore.save()
        refresh()
    }
}
