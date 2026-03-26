import Foundation
import SwiftData

@MainActor
struct LedgerImportCoordinator {
    private let postingIntakeUseCase: PostingIntakeUseCase
    private let ledgerType: LedgerType
    private let metadataJSON: String?

    init(
        modelContext: ModelContext,
        ledgerType: LedgerType,
        metadataJSON: String?
    ) {
        self.postingIntakeUseCase = PostingIntakeUseCase(modelContext: modelContext)
        self.ledgerType = ledgerType
        self.metadataJSON = metadataJSON
    }

    func preparePreview(content: String) -> [[String]] {
        let cleaned = content.replacingOccurrences(of: "\u{FEFF}", with: "")
        return CSVImportService.shared.parseCSV(cleaned)
    }

    func importFile(
        fileData: Data,
        originalFileName: String,
        mimeType: String = "text/csv"
    ) async throws -> CSVImportResult {
        guard let content = String(data: fileData, encoding: .utf8) else {
            throw AppError.invalidInput(message: "CSV の文字コードを UTF-8 として読み取れません")
        }

        return await postingIntakeUseCase.importTransactions(
            request: CSVImportRequest(
                csvString: content,
                originalFileName: originalFileName,
                fileData: fileData,
                mimeType: mimeType,
                channel: .ledgerBook(
                    ledgerType: ledgerType,
                    metadataJSON: metadataJSON
                )
            )
        )
    }
}
