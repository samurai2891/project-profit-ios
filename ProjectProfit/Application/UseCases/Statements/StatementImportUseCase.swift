import Foundation
import SwiftData

@MainActor
struct StatementImportUseCase {
    private let modelContext: ModelContext
    private let statementRepository: any StatementRepository
    private let evidenceRepository: any EvidenceRepository
    private let transactionFormQueryUseCase: TransactionFormQueryUseCase
    private let matchService: StatementMatchService
    private let pdfParser: StatementPDFParser

    init(
        modelContext: ModelContext,
        statementRepository: (any StatementRepository)? = nil,
        evidenceRepository: (any EvidenceRepository)? = nil,
        transactionFormQueryUseCase: TransactionFormQueryUseCase? = nil,
        matchService: StatementMatchService? = nil,
        pdfParser: StatementPDFParser? = nil
    ) {
        self.modelContext = modelContext
        self.statementRepository = statementRepository ?? SwiftDataStatementRepository(modelContext: modelContext)
        self.evidenceRepository = evidenceRepository ?? SwiftDataEvidenceRepository(modelContext: modelContext)
        let queryUseCase = transactionFormQueryUseCase ?? TransactionFormQueryUseCase(modelContext: modelContext)
        self.transactionFormQueryUseCase = queryUseCase
        self.matchService = matchService ?? StatementMatchService(modelContext: modelContext)
        self.pdfParser = pdfParser ?? StatementPDFParser()
    }

    func preview(request: StatementImportRequest) async throws -> StatementImportPreview {
        let parseResult = try await parse(request: request)
        return StatementImportPreview(
            fileSource: parseResult.fileSource,
            parsedLineCount: parseResult.drafts.count,
            sampleLines: parseResult.drafts.prefix(5).map(sampleLine),
            lineErrors: parseResult.lineErrors
        )
    }

    func importStatement(request: StatementImportRequest) async throws -> StatementImportResult {
        let snapshot = try transactionFormQueryUseCase.snapshot()
        guard let businessId = snapshot.businessId else {
            throw AppError.invalidInput(message: "事業者プロフィールが未設定です")
        }

        let parseResult = try await parse(request: request)
        guard !parseResult.drafts.isEmpty else {
            throw AppError.invalidInput(message: "取り込める明細がありません")
        }

        let fileHash = ReceiptImageStore.sha256Hex(data: request.fileData)
        if try existingEvidenceId(businessId: businessId, fileHash: fileHash) != nil {
            throw AppError.invalidInput(message: "同一の statement ファイルは既に取り込み済みです")
        }

        let dates = parseResult.drafts.map(\.date)
        let storedFileName = try ReceiptImageStore.saveDocumentData(
            request.fileData,
            originalFileName: request.originalFileName
        )
        let suggestedTaxYear = fiscalYear(
            for: dates.min() ?? Date(),
            startMonth: FiscalYearSettings.startMonth
        )
        let evidence = EvidenceDocument(
            businessId: businessId,
            taxYear: suggestedTaxYear,
            sourceType: parseResult.fileSource == .csv ? .importedCSV : .importedPDF,
            legalDocumentType: .statement,
            storageCategory: .electronicTransaction,
            receivedAt: Date(),
            issueDate: dates.min(),
            paymentDate: dates.max(),
            originalFilename: request.originalFileName,
            mimeType: request.mimeType,
            fileHash: fileHash,
            originalFilePath: storedFileName,
            ocrText: parseResult.previewText,
            extractionVersion: "statement-v1",
            searchTokens: [
                "statement",
                request.statementKind.rawValue,
                request.originalFileName,
                request.paymentAccountId,
            ],
            structuredFields: nil,
            linkedCounterpartyId: nil,
            linkedProjectIds: [],
            complianceStatus: .pendingReview,
            retentionPolicyId: nil,
            deletedAt: nil,
            lockedAt: nil
        )

        do {
            try await evidenceRepository.save(evidence)
        } catch {
            ReceiptImageStore.deleteDocumentFile(fileName: storedFileName)
            throw error
        }

        let importRecord = StatementImportRecord(
            businessId: businessId,
            evidenceId: evidence.id,
            statementKind: request.statementKind,
            paymentAccountId: request.paymentAccountId,
            fileSource: parseResult.fileSource,
            importedAt: Date(),
            originalFileName: request.originalFileName
        )
        try await statementRepository.saveImport(importRecord)

        let lineRecords = parseResult.drafts.map { draft in
            StatementLineRecord(
                importId: importRecord.id,
                businessId: businessId,
                statementKind: request.statementKind,
                paymentAccountId: request.paymentAccountId,
                date: draft.date,
                description: draft.description,
                amount: draft.amount,
                direction: draft.direction,
                counterparty: draft.counterparty,
                reference: draft.reference,
                memo: draft.memo
            )
        }
        try await statementRepository.saveLines(lineRecords)
        let suggestedLines = try await matchService.refreshSuggestions(for: lineRecords)

        return StatementImportResult(
            importRecord: importRecord,
            evidenceId: evidence.id,
            lineCount: suggestedLines.count,
            lineErrors: parseResult.lineErrors
        )
    }

    private func parse(request: StatementImportRequest) async throws -> StatementParseResult {
        let fileSource = resolvedFileSource(
            fileName: request.originalFileName,
            mimeType: request.mimeType
        )
        switch fileSource {
        case .csv:
            let content = try decodeUTF8(request.fileData)
            return parseCSV(content: content)
        case .pdf:
            let drafts = try await pdfParser.parse(
                fileData: request.fileData,
                fallbackYear: Calendar.current.component(.year, from: Date())
            )
            return StatementParseResult(
                fileSource: .pdf,
                drafts: drafts,
                lineErrors: [],
                previewText: nil
            )
        }
    }

    private func parseCSV(content: String) -> StatementParseResult {
        let rows = CSVImportService.shared.parseCSV(content.replacingOccurrences(of: "\u{FEFF}", with: ""))
        guard let header = rows.first else {
            return StatementParseResult(fileSource: .csv, drafts: [], lineErrors: [CSVImportLineError(line: 1, reason: "ヘッダー行がありません")], previewText: nil)
        }
        let headerMap = StatementCSVHeaderMap(headers: header)
        var drafts: [StatementLineDraft] = []
        var lineErrors: [CSVImportLineError] = []

        for (index, row) in rows.dropFirst().enumerated() {
            let sourceLine = index + 2
            guard row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                continue
            }
            do {
                drafts.append(try StatementCSVRowParser(
                    row: row,
                    headerMap: headerMap
                ).parse())
            } catch {
                lineErrors.append(CSVImportLineError(line: sourceLine, reason: error.localizedDescription))
            }
        }
        return StatementParseResult(
            fileSource: .csv,
            drafts: drafts,
            lineErrors: lineErrors,
            previewText: nil
        )
    }

    private func sampleLine(_ draft: StatementLineDraft) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .currency
        currencyFormatter.currencyCode = "JPY"
        currencyFormatter.locale = Locale(identifier: "ja_JP")
        currencyFormatter.maximumFractionDigits = 0
        let amount = currencyFormatter.string(from: NSDecimalNumber(decimal: draft.amount)) ?? NSDecimalNumber(decimal: draft.amount).stringValue
        return [
            formatter.string(from: draft.date),
            draft.direction.displayName,
            draft.description,
            amount,
        ].joined(separator: " ")
    }

    private func decodeUTF8(_ data: Data) throws -> String {
        guard let content = String(data: data, encoding: .utf8) else {
            throw AppError.invalidInput(message: "UTF-8 で読み込めないファイルです")
        }
        return content
    }

    private func resolvedFileSource(fileName: String, mimeType: String) -> StatementFileSource {
        let lowered = fileName.lowercased()
        if lowered.hasSuffix(".pdf") || mimeType.lowercased().contains("pdf") {
            return .pdf
        }
        return .csv
    }

    private func existingEvidenceId(
        businessId: UUID,
        fileHash: String
    ) throws -> UUID? {
        let descriptor = FetchDescriptor<EvidenceRecordEntity>(
            predicate: #Predicate {
                $0.businessId == businessId &&
                    $0.fileHash == fileHash &&
                    $0.deletedAt == nil
            }
        )
        return try modelContext.fetch(descriptor).first?.evidenceId
    }
}

private struct StatementParseResult {
    let fileSource: StatementFileSource
    let drafts: [StatementLineDraft]
    let lineErrors: [CSVImportLineError]
    let previewText: String?
}

private struct StatementCSVHeaderMap {
    let indices: [String: Int]

    init(headers: [String]) {
        let map: [String: String] = [
            "日付": "date",
            "date": "date",
            "摘要": "description",
            "description": "description",
            "金額": "amount",
            "amount": "amount",
            "入出金区分": "direction",
            "direction": "direction",
            "取引先": "counterparty",
            "counterparty": "counterparty",
            "参照番号": "reference",
            "reference": "reference",
            "メモ": "memo",
            "memo": "memo",
        ]
        var indices: [String: Int] = [:]
        for (index, header) in headers.enumerated() {
            let normalized = SearchIndexNormalizer.normalizeText(header)
            if let key = map[normalized] {
                indices[key] = index
            }
        }
        self.indices = indices
    }

    func index(for key: String) -> Int? {
        indices[key]
    }
}

private struct StatementCSVRowParser {
    let row: [String]
    let headerMap: StatementCSVHeaderMap

    func parse() throws -> StatementLineDraft {
        guard let dateString = value(for: "date"),
              let description = value(for: "description"),
              let amountString = value(for: "amount") else {
            throw AppError.invalidInput(message: "日付 / 摘要 / 金額 は必須です")
        }

        guard let date = parseDate(dateString) else {
            throw AppError.invalidInput(message: "日付を解釈できません: \(dateString)")
        }
        guard let amount = parseAmount(amountString) else {
            throw AppError.invalidInput(message: "金額を解釈できません: \(amountString)")
        }
        let direction = parseDirection(value(for: "direction"), amount: amount)

        return StatementLineDraft(
            date: date,
            description: description,
            amount: amount.magnitude,
            direction: direction,
            counterparty: value(for: "counterparty"),
            reference: value(for: "reference"),
            memo: value(for: "memo")
        )
    }

    private func value(for key: String) -> String? {
        guard let index = headerMap.index(for: key),
              row.indices.contains(index) else {
            return nil
        }
        let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func parseDate(_ value: String) -> Date? {
        let candidates = [
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "yyyy.M.d",
            "yyyy/M/d",
        ]
        for format in candidates {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private func parseAmount(_ value: String) -> Decimal? {
        let normalized = value
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "円", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: normalized)
    }

    private func parseDirection(_ value: String?, amount: Decimal) -> StatementDirection {
        if let value {
            let normalized = SearchIndexNormalizer.normalizeText(value)
            if ["入金", "credit", "deposit", "inflow"].contains(where: normalized.contains) {
                return .inflow
            }
            if ["出金", "debit", "withdrawal", "outflow", "支払", "引落"].contains(where: normalized.contains) {
                return .outflow
            }
        }
        return amount.sign == .minus ? .outflow : .inflow
    }
}
