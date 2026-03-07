import Foundation
import SwiftData

@MainActor
struct CounterpartyMasterUseCase {
    private let counterpartyRepository: any CounterpartyRepository

    init(counterpartyRepository: any CounterpartyRepository) {
        self.counterpartyRepository = counterpartyRepository
    }

    init(modelContext: ModelContext) {
        self.init(counterpartyRepository: SwiftDataCounterpartyRepository(modelContext: modelContext))
    }

    func loadCounterparties(businessId: UUID) async throws -> [Counterparty] {
        try await counterpartyRepository.findByBusiness(businessId: businessId)
    }

    func searchCounterparties(businessId: UUID, query: String) async throws -> [Counterparty] {
        try await counterpartyRepository.findByName(businessId: businessId, query: query)
    }

    func findByRegistrationNumber(_ number: String) async throws -> Counterparty? {
        try await counterpartyRepository.findByRegistrationNumber(number)
    }

    /// OCRで抽出された店名から取引先を自動照合する。
    /// 完全一致 → 前方一致 → 部分一致の優先度で最も適合する取引先を返す。
    func suggestCounterparty(storeName: String, businessId: UUID) async throws -> Counterparty? {
        let trimmed = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1回のfetchで完全一致・前方一致・部分一致を判定（actor hop最小化）
        let candidates = try await counterpartyRepository.findByDisplayNamePrefix(businessId: businessId, query: trimmed)
        guard !candidates.isEmpty else { return nil }

        let folded = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)

        // findByDisplayNamePrefix が完全一致→前方一致→部分一致の優先度でソート済み
        // 先頭が完全一致ならそれを返す
        if let first = candidates.first {
            let firstFolded = first.displayName.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            if firstFolded == folded { return first }
        }

        // それ以外は最上位の部分一致を返す
        return candidates.first
    }

    func save(_ counterparty: Counterparty) async throws {
        try await counterpartyRepository.save(counterparty)
    }

    func delete(_ id: UUID) async throws {
        try await counterpartyRepository.delete(id)
    }
}
