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
        results.filter { $0.result.needsReview }
    }

    var classifiedCount: Int {
        results.count - unclassifiedResults.count
    }

    // MARK: - 学習フィードバック (9B)

    /// ユーザーの手動分類修正を学習し、PPUserRuleを自動生成・更新する
    func correctClassification(candidateId: UUID, newTaxLine: TaxLine) {
        guard let item = results.first(where: { $0.candidate.id == candidateId }) else {
            return
        }

        ClassificationLearningService.learnFromCorrection(
            candidate: item.candidate,
            evidence: item.evidence,
            correctedTaxLine: newTaxLine,
            existingRules: userRules,
            modelContext: modelContext
        )
        try? userRuleRepository.saveChanges()
        refresh()
    }
}
