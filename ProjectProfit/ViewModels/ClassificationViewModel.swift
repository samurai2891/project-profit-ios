import SwiftData
import SwiftUI

@MainActor
@Observable
final class ClassificationViewModel {
    private let modelContext: ModelContext
    private let queryUseCase: ClassificationQueryUseCase
    private let userRuleRepository: any UserRuleRepository

    var results: [ClassificationResultItem] = []
    var userRules: [PPUserRule] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.queryUseCase = ClassificationQueryUseCase(modelContext: modelContext)
        self.userRuleRepository = SwiftDataUserRuleRepository(modelContext: modelContext)
        refresh()
    }

    func refresh() {
        let snapshot = queryUseCase.snapshot()
        results = snapshot.results
        userRules = snapshot.userRules
    }

    var unclassifiedResults: [ClassificationResultItem] {
        results.filter { $0.result.source == .fallback }
    }

    var classifiedCount: Int {
        results.count - unclassifiedResults.count
    }

    // MARK: - 学習フィードバック (9B)

    /// ユーザーの手動分類修正を学習し、PPUserRuleを自動生成・更新する
    func correctClassification(transactionId: UUID, newTaxLine: TaxLine) {
        guard let transaction = results.first(where: { $0.transaction.id == transactionId })?.transaction else {
            return
        }

        ClassificationLearningService.learnFromCorrection(
            transaction: transaction,
            correctedTaxLine: newTaxLine,
            existingRules: userRules,
            modelContext: modelContext
        )
        try? userRuleRepository.saveChanges()
        refresh()
    }
}
