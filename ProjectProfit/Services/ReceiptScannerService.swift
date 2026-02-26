import Foundation
import os
import UIKit
import Vision

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Scan Error

enum ReceiptScanError: LocalizedError {
    case invalidImage
    case ocrFailed(underlying: Error)
    case noTextFound
    case cameraUnavailable
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "画像を読み込めませんでした"
        case .ocrFailed:
            "テキストの読み取りに失敗しました"
        case .noTextFound:
            "テキストが検出されませんでした"
        case .cameraUnavailable:
            "カメラが利用できません"
        case .permissionDenied:
            "カメラまたはフォトライブラリへのアクセスが許可されていません"
        }
    }
}

// MARK: - Scan State

enum ReceiptScanState {
    case idle
    case processing
    case completed(ReceiptData)
    case failed(String)
}

// MARK: - Scanner Service

@MainActor
@Observable
final class ReceiptScannerService {
    private static let ciContext = CIContext()
    private static let digitPattern = try? NSRegularExpression(pattern: "\\d")

    // OCR confidence thresholds
    private static let minimumConfidence: Float = 0.3
    private static let mediumConfidenceThreshold: Float = 0.7
    private static let alternativeConfidenceMultiplier: Float = 0.8

    private(set) var state: ReceiptScanState = .idle

    func reset() {
        state = .idle
    }

    func scan(image: UIImage) async {
        state = .processing
        do {
            let text = try await recognizeText(from: image)
            guard !text.isEmpty else {
                state = .failed(ReceiptScanError.noTextFound.localizedDescription)
                return
            }

            AppLogger.receipt.info("OCR extracted \(text.count) characters")
            let receiptData = try await extractReceiptData(from: text)
            AppLogger.receipt.info("OCR inferred document=\(receiptData.documentType.rawValue) type=\(receiptData.suggestedTransactionType.rawValue) confidence=\(receiptData.confidence)")
            state = .completed(receiptData)
        } catch {
            AppLogger.receipt.error("Scan failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Vision OCR

    private func recognizeText(from image: UIImage) async throws -> String {
        let preprocessed = preprocessImage(image)
        guard let cgImage = preprocessed.cgImage else {
            throw ReceiptScanError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: ReceiptScanError.ocrFailed(underlying: error))
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { observation -> String? in
                        let candidates = observation.topCandidates(3)
                        guard let best = candidates.first else { return nil }

                        // Skip very low confidence results
                        guard best.confidence >= Self.minimumConfidence else { return nil }

                        // For lines containing digits (likely amounts), try to find
                        // the candidate with highest confidence that parses numbers
                        if best.confidence < Self.mediumConfidenceThreshold,
                           let digitRegex = Self.digitPattern
                        {
                            for candidate in candidates {
                                let str = candidate.string
                                let range = NSRange(str.startIndex..., in: str)
                                let hasDigits = digitRegex.firstMatch(in: str, range: range) != nil
                                if hasDigits && candidate.confidence > best.confidence * Self.alternativeConfidenceMultiplier {
                                    return candidate.string
                                }
                            }
                        }

                        return best.string
                    }
                    .joined(separator: "\n")

                continuation.resume(returning: text)
            }

            request.recognitionLanguages = ["ja", "en"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if #available(iOS 16, *) {
                request.automaticallyDetectsLanguage = true
            }
            request.revision = VNRecognizeTextRequestRevision3

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: ReceiptScanError.ocrFailed(underlying: error))
            }
        }
    }

    /// Preprocess image for better OCR accuracy: normalize orientation and enhance contrast
    private func preprocessImage(_ image: UIImage) -> UIImage {
        // Step 1: Normalize orientation
        let oriented: UIImage
        if image.imageOrientation != .up {
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
            oriented = renderer.image { _ in
                image.draw(at: .zero)
            }
        } else {
            oriented = image
        }

        // Step 2: Apply CIFilter-based enhancement for better OCR
        guard let ciImage = CIImage(image: oriented) else { return oriented }
        let context = Self.ciContext

        // Enhance contrast and brightness (helps with faded thermal receipts)
        let enhanced = ciImage
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.4,
                kCIInputBrightnessKey: 0.05,
            ])
            // Sharpen to improve text edge clarity
            .applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: 0.4,
            ])

        guard let cgImage = context.createCGImage(enhanced, from: enhanced.extent) else {
            return oriented
        }
        return UIImage(cgImage: cgImage, scale: oriented.scale, orientation: .up)
    }

    // MARK: - Data Extraction

    private func extractReceiptData(from text: String) async throws -> ReceiptData {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            do {
                return try await extractWithFoundationModels(from: text)
            } catch {
                AppLogger.receipt.warning("Foundation Models failed, using regex: \(error.localizedDescription)")
                return extractWithRegex(from: text)
            }
        }
        #endif
        return extractWithRegex(from: text)
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private func extractWithFoundationModels(from text: String) async throws -> ReceiptData {
        let session = LanguageModelSession()
        // Truncate input to prevent excessive processing
        let truncatedText = String(text.prefix(5000))
        let prompt = """
        以下はレシート・請求書・領収書のOCRテキストです。正確に情報を抽出してください。

        【抽出ルール】
        - totalAmount: 税込の合計金額を整数で。以下の優先順で探す:
          1. 「税込合計」「お支払い合計」「お支払い金額」行の金額（最優先）
          2. 「合計」「お会計」「お買上」行の金額
          3. 見つからない場合は最大金額
          ※「お預り」「お預かり」「お釣り」「現金」「クレジット」行の金額は合計ではないので除外すること
        - taxAmount: 消費税額を整数で（「消費税」「内税」「外税」行の金額。不明なら0）
        - date: yyyy-MM-dd形式（「2026/01/15」→「2026-01-15」）
        - storeName: 店舗名・発行者名
        - documentType: receipt / invoice / expense-receipt / unknown から選択
        - transactionType: income / expense のどちらかを選択（請求書は原則 income、領収書・レシートは原則 expense）
        - estimatedCategory: 以下から最適なものを1つ選択:
          hosting（サーバー・ドメイン・クラウド）, tools（ソフトウェア・SaaS）, ads（広告）,
          contractor（外注・委託）, communication（通信・電話）, supplies（事務用品・消耗品）,
          transport（交通費・タクシー・駐車場）, food（飲食・食料品・コンビニ・レストラン・カフェ）,
          entertainment（接待・会議費）, insurance（保険料）, other-expense（上記以外の経費）,
          sales（売上）, service（サービス収入）, other-income（上記以外の収益）
        - itemSummary: 購入品目の要約（品名を3つまでカンマ区切り）
        - confidence: 推定の信頼度を0.0〜1.0で返す

        【注意】
        - OCRの誤読を考慮し、文脈から正しい値を推測してください
        - 金額のカンマ区切り（1,000）は除去して整数にしてください
        - 日付が見つからない場合は空文字を返してください
        - 「お預り」「お預かり」金額は、お客様から受け取った金額であり合計金額ではありません
        - 「お釣り」は返金額であり合計金額ではありません
        - 合計が税抜と税込の両方ある場合は、必ず税込（大きい方）の金額を選んでください

        OCRテキスト:
        \(truncatedText)
        """

        let response = try await session.respond(to: prompt, generating: ReceiptExtraction.self)
        let extraction = response.content

        // Extract line items in a separate request to avoid nesting issues
        let lineItems = await extractLineItemsWithFoundationModels(from: truncatedText, session: session)

        let documentType = Self.parseDocumentType(extraction.documentType)
        let inferredType = Self.parseTransactionType(extraction.transactionType)
            ?? RegexReceiptParser.inferTransactionType(from: text, documentType: documentType)
        let inferredCategory = RegexReceiptParser.normalizeEstimatedCategory(
            extraction.estimatedCategory,
            type: inferredType,
            fallbackText: text
        )

        // Use regex as supplementary for tax/subtotal if FM didn't provide
        let taxAmount = extraction.taxAmount > 0
            ? extraction.taxAmount
            : RegexReceiptParser.extractTax(from: text)
        let subtotalAmount = RegexReceiptParser.extractSubtotal(from: text)
        let normalizedDate = extraction.date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? RegexReceiptParser.extractDate(from: text)
            : extraction.date
        let normalizedStoreName = extraction.storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? RegexReceiptParser.extractStoreName(from: text)
            : extraction.storeName
        let normalizedLineItems = lineItems.isEmpty
            ? RegexReceiptParser.extractLineItems(from: text)
            : lineItems
        let confidence = max(0, min(1, extraction.confidence))

        return ReceiptData(
            totalAmount: extraction.totalAmount,
            taxAmount: taxAmount,
            subtotalAmount: subtotalAmount,
            date: normalizedDate,
            storeName: normalizedStoreName,
            estimatedCategory: inferredCategory,
            itemSummary: extraction.itemSummary,
            lineItems: normalizedLineItems,
            documentType: documentType,
            suggestedTransactionType: inferredType,
            confidence: confidence
        )
    }

    @available(iOS 26, *)
    private func extractLineItemsWithFoundationModels(
        from text: String,
        session: LanguageModelSession
    ) async -> [LineItem] {
        do {
            let prompt = """
            以下の書類OCRテキストから購入した品目（明細行）を抽出してください。

            【抽出ルール】
            - name: 品目名（商品名・サービス名）
            - quantity: 数量（明記がなければ1）
            - unitPrice: 1個あたりの単価（整数、円単位）
            - subtotal: 小計 = quantity × unitPrice（整数、円単位）

            【除外する行】
            合計、小計、税、消費税、内税、外税、お釣り、お預り、現金、カード、
            クレジット、TOTAL、CHANGE、CASH、VISA、MASTER、JCB、値引、割引、ポイント

            【注意】
            - 「x2」「×3」「2個」「3点」などは数量として解釈
            - OCRの誤読を考慮し、品名と金額を文脈から推測
            - 金額のカンマは除去して整数に

            OCRテキスト:
            \(text)
            """

            let response = try await session.respond(to: prompt, generating: LineItemsExtraction.self)
            return response.content.items.map { item in
                LineItem(
                    name: item.name,
                    quantity: max(1, item.quantity),
                    unitPrice: item.unitPrice,
                    subtotal: item.subtotal
                )
            }
        } catch {
            AppLogger.receipt.warning("Line items extraction failed: \(error.localizedDescription)")
            return []
        }
    }
    #endif

    // MARK: - Regex Fallback

    private func extractWithRegex(from text: String) -> ReceiptData {
        let totalAmount = RegexReceiptParser.extractAmount(from: text)
        let taxAmount = RegexReceiptParser.extractTax(from: text)
        let subtotalAmount = RegexReceiptParser.extractSubtotal(from: text)
        let documentType = RegexReceiptParser.detectDocumentType(from: text)
        let transactionType = RegexReceiptParser.inferTransactionType(from: text, documentType: documentType)
        let confidence = RegexReceiptParser.inferenceConfidence(
            from: text,
            documentType: documentType,
            transactionType: transactionType
        )

        return ReceiptData(
            totalAmount: totalAmount,
            taxAmount: taxAmount,
            subtotalAmount: subtotalAmount,
            date: RegexReceiptParser.extractDate(from: text),
            storeName: RegexReceiptParser.extractStoreName(from: text),
            estimatedCategory: RegexReceiptParser.estimateCategory(from: text, type: transactionType),
            itemSummary: RegexReceiptParser.extractSummary(from: text),
            lineItems: RegexReceiptParser.extractLineItems(from: text),
            documentType: documentType,
            suggestedTransactionType: transactionType,
            confidence: confidence
        )
    }

    private static func parseDocumentType(_ rawValue: String) -> ScannedDocumentType {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        switch normalized {
        case "receipt":
            return .receipt
        case "invoice":
            return .invoice
        case "expense-receipt", "expense-receipts", "expense receipt":
            return .expenseReceipt
        default:
            return .unknown
        }
    }

    private static func parseTransactionType(_ rawValue: String) -> TransactionType? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "income":
            return .income
        case "expense":
            return .expense
        case "transfer":
            return .transfer
        default:
            return nil
        }
    }
}

// MARK: - Regex Parser

enum RegexReceiptParser {
    // Pre-compiled regex patterns for performance
    private static let yenPrefixPattern = try? NSRegularExpression(pattern: "[¥￥]\\s*([\\d,]+)")
    private static let yenSuffixPattern = try? NSRegularExpression(pattern: "([\\d,]+)\\s*円")
    private static let dateSlashPattern = try? NSRegularExpression(pattern: "(20\\d{2})[/\\-](\\d{1,2})[/\\-](\\d{1,2})")
    private static let dateJPPattern = try? NSRegularExpression(pattern: "(20\\d{2})年\\s*(\\d{1,2})月\\s*(\\d{1,2})日")
    private static let numberFirstPatterns: [NSRegularExpression] = [
        "[¥￥]\\s*([\\d,]+)",
        "([\\d,]+)\\s*円",
        "([\\d,]{3,})",
    ].compactMap { try? NSRegularExpression(pattern: $0) }
    private static let plainNumberEndPattern = try? NSRegularExpression(pattern: "([\\d,]{2,})\\s*$")
    private static let storeSkipPatterns: [NSRegularExpression] = [
        "^\\d+$", "^[¥￥]", "^20\\d{2}", "^\\d{1,2}[:/]",
        "^TEL", "^T\\d{4}", "^レシート", "^領収",
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    // Tax-inclusive total keywords (highest priority)
    private static let taxInclusiveTotalKeywords = [
        "税込合計", "税込計", "税込金額",
        "お支払い合計", "お支払合計", "お支払い金額", "お支払金額",
        "お買い上げ合計", "お買上合計",
    ]

    private static let totalKeywords = [
        "合計", "お会計", "お買上", "お買い上げ",
        "合計金額", "請求金額", "請求額", "ご請求",
        "TOTAL", "Total",
    ]

    // Lines containing these keywords should be excluded from amount extraction
    private static let amountExcludeKeywords = [
        "お預り", "お預かり", "お釣り", "釣銭",
        "現金", "クレジット", "VISA", "MASTER", "JCB", "AMEX",
        "カード", "電子マネー", "PayPay", "paypay",
        "交通系", "Suica", "PASMO", "ICOCA",
        "CHANGE", "CASH", "nanaco", "WAON", "iD",
        "小計",
    ]

    private static let taxKeywords = [
        "消費税", "内税", "外税", "内消費税", "うち消費税",
    ]

    private static let invoiceKeywords = [
        "請求書", "請求日", "請求番号", "ご請求", "請求先", "請求金額", "請求額",
        "お支払期限", "支払期限", "振込先", "御中", "invoice", "bill to",
    ]

    private static let expenseReceiptKeywords = [
        "領収書", "領収証", "領収", "受領", "receipt",
    ]

    private static let receiptKeywords = [
        "レシート", "お会計", "お買上", "小計", "お預り", "お釣り", "change", "cash",
    ]

    private static let incomeHintKeywords = [
        "請求書", "請求金額", "売上", "入金", "振込", "御中", "納品", "invoice", "billing",
    ]

    private static let expenseHintKeywords = [
        "領収書", "領収証", "レシート", "お預り", "お釣り", "現金", "クレジット", "小計", "receipt",
    ]

    static func extractAmount(from text: String) -> Int {
        let lines = text.components(separatedBy: .newlines)
        let nonExcludedLines = lines.filter { line in
            !amountExcludeKeywords.contains { line.contains($0) }
        }

        // Priority 0: Tax-inclusive total keywords (most reliable)
        for keyword in taxInclusiveTotalKeywords {
            for line in nonExcludedLines where line.contains(keyword) {
                if let amount = extractFirstNumber(from: line), amount > 0 {
                    return amount
                }
            }
        }

        // Priority 1: Total keywords — prefer the LAST matching line
        // (receipts typically list subtotal first, then tax, then total)
        for keyword in totalKeywords {
            var lastAmount = 0
            for line in nonExcludedLines where line.contains(keyword) {
                // Skip lines that also contain tax keywords (e.g., "消費税")
                let isTaxLine = taxKeywords.contains { line.contains($0) }
                guard !isTaxLine else { continue }
                if let amount = extractFirstNumber(from: line), amount > 0 {
                    lastAmount = amount
                }
            }
            if lastAmount > 0 {
                return lastAmount
            }
        }

        // Priority 2: largest yen-prefixed number (excluding payment/deposit lines)
        var maxAmount = findMaxAmount(in: nonExcludedLines, using: yenPrefixPattern)
        if maxAmount > 0 { return maxAmount }

        // Priority 3: number followed by 円 (excluding payment/deposit lines)
        maxAmount = findMaxAmount(in: nonExcludedLines, using: yenSuffixPattern)
        return maxAmount
    }

    // MARK: - Tax Extraction

    static func extractTax(from text: String) -> Int {
        let lines = text.components(separatedBy: .newlines)
        var totalTax = 0

        // Pattern: lines containing tax keywords with amounts
        for line in lines {
            let isTaxLine = taxKeywords.contains { line.contains($0) }
            guard isTaxLine else { continue }
            // Skip lines that are tax rate descriptions (e.g., "税率10% 対象 ¥1,000")
            if line.contains("税率") && line.contains("対象") { continue }
            if let amount = extractFirstNumber(from: line), amount > 0 {
                totalTax += amount
            }
        }

        return totalTax
    }

    // MARK: - Subtotal Extraction

    static func extractSubtotal(from text: String) -> Int {
        let lines = text.components(separatedBy: .newlines)
        let subtotalKeywords = ["小計"]

        for keyword in subtotalKeywords {
            for line in lines where line.contains(keyword) {
                // Avoid lines that also match total keywords
                let isTotalLine = totalKeywords.contains { line.contains($0) }
                guard !isTotalLine else { continue }
                if let amount = extractFirstNumber(from: line), amount > 0 {
                    return amount
                }
            }
        }

        return 0
    }

    static func extractDate(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)

        // Pattern 1: yyyy/MM/dd or yyyy-MM-dd
        if let result = findDate(in: lines, using: dateSlashPattern) {
            return result
        }

        // Pattern 2: yyyy年MM月dd日
        if let result = findDate(in: lines, using: dateJPPattern) {
            return result
        }

        // Default: today
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static func extractStoreName(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines.prefix(5) {
            let nsRange = NSRange(line.startIndex..., in: line)
            let shouldSkip = storeSkipPatterns.contains { regex in
                regex.firstMatch(in: line, range: nsRange) != nil
            }
            if !shouldSkip, line.count >= 2, line.count <= 30 {
                return line
            }
        }

        return ""
    }

    static func detectDocumentType(from text: String) -> ScannedDocumentType {
        let normalized = text.lowercased()
        let invoiceScore = keywordScore(in: normalized, keywords: invoiceKeywords)
        let expenseReceiptScore = keywordScore(in: normalized, keywords: expenseReceiptKeywords)
        let receiptScore = keywordScore(in: normalized, keywords: receiptKeywords)

        if expenseReceiptScore > 0, expenseReceiptScore >= invoiceScore, expenseReceiptScore >= receiptScore {
            return .expenseReceipt
        }
        if invoiceScore > 0, invoiceScore >= receiptScore {
            return .invoice
        }
        if receiptScore > 0 {
            return .receipt
        }
        return .unknown
    }

    static func inferTransactionType(from text: String, documentType: ScannedDocumentType? = nil) -> TransactionType {
        let resolvedDocumentType = documentType ?? detectDocumentType(from: text)
        let normalized = text.lowercased()

        var incomeScore = keywordScore(in: normalized, keywords: incomeHintKeywords)
        var expenseScore = keywordScore(in: normalized, keywords: expenseHintKeywords)

        switch resolvedDocumentType {
        case .invoice:
            incomeScore += 2
        case .expenseReceipt, .receipt:
            expenseScore += 2
        case .unknown:
            break
        }

        if incomeScore == expenseScore {
            return resolvedDocumentType == .invoice ? .income : .expense
        }
        return incomeScore > expenseScore ? .income : .expense
    }

    static func inferenceConfidence(
        from text: String,
        documentType: ScannedDocumentType,
        transactionType: TransactionType
    ) -> Double {
        let normalized = text.lowercased()
        let documentScore: Int
        switch documentType {
        case .invoice:
            documentScore = keywordScore(in: normalized, keywords: invoiceKeywords)
        case .expenseReceipt:
            documentScore = keywordScore(in: normalized, keywords: expenseReceiptKeywords)
        case .receipt:
            documentScore = keywordScore(in: normalized, keywords: receiptKeywords)
        case .unknown:
            documentScore = 0
        }

        let transactionScore: Int
        switch transactionType {
        case .income:
            transactionScore = keywordScore(in: normalized, keywords: incomeHintKeywords)
        case .expense:
            transactionScore = keywordScore(in: normalized, keywords: expenseHintKeywords)
        case .transfer:
            transactionScore = 0
        }
        let base = documentType == .unknown ? 0.45 : 0.58
        let bonus = Double(documentScore + transactionScore) * 0.06
        return min(0.95, base + bonus)
    }

    static func normalizeEstimatedCategory(
        _ category: String,
        type: TransactionType,
        fallbackText: String
    ) -> String {
        let normalized = category
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let validIncome = Set(["sales", "service", "other-income"])
        let validExpense = Set([
            "hosting", "tools", "ads", "contractor", "communication",
            "supplies", "transport", "food", "entertainment", "insurance", "other-expense",
        ])

        if type == .income {
            if validIncome.contains(normalized) { return normalized }
            return estimateCategory(from: fallbackText, type: .income)
        }

        if validExpense.contains(normalized) { return normalized }
        return estimateCategory(from: fallbackText, type: .expense)
    }

    static func estimateCategory(from text: String) -> String {
        estimateCategory(from: text, type: .expense)
    }

    static func estimateCategory(from text: String, type: TransactionType) -> String {
        let lowerText = text.lowercased()

        if type == .income {
            let incomeCategoryKeywords: [(category: String, keywords: [String])] = [
                ("sales", [
                    "売上", "売掛", "請求書", "ご請求", "請求金額", "請求額",
                    "受注", "納品", "制作費", "開発費", "販売",
                ]),
                ("service", [
                    "サービス", "保守", "サポート", "運用", "顧問", "コンサル",
                    "利用料", "月額", "契約料", "手数料",
                ]),
            ]

            for (category, keywords) in incomeCategoryKeywords {
                for keyword in keywords {
                    if lowerText.contains(keyword.lowercased()) {
                        return category
                    }
                }
            }
            return "other-income"
        }

        // More specific categories first to avoid false matches
        let categoryKeywords: [(category: String, keywords: [String])] = [
            ("hosting", [
                "サーバー", "server", "aws", "gcp", "azure", "ドメイン", "domain",
                "heroku", "vercel", "netlify", "cloudflare", "レンタルサーバ",
                "さくらインターネット", "エックスサーバー", "conoha",
            ]),
            ("tools", [
                "ソフトウェア", "figma", "notion", "slack", "github", "サブスク",
                "ライセンス", "adobe", "microsoft", "google workspace", "zoom",
                "chatgpt", "openai", "saas", "アプリ", "jira", "confluence",
                "dropbox", "evernote", "canva", "jetbrains",
            ]),
            ("ads", [
                "広告", "google ads", "facebook ads", "meta ads", "プロモーション",
                "instagram", "twitter ads", "tiktok", "リスティング", "ディスプレイ広告",
            ]),
            ("contractor", ["外注", "請負", "委託", "業務委託", "フリーランス", "制作費"]),
            ("communication", [
                "電話", "通信", "インターネット", "wi-fi", "wifi", "携帯",
                "ntt", "回線", "ソフトバンク", "au ", "kddi", "docomo", "ドコモ",
                "楽天モバイル", "uq", "ymobile", "ワイモバイル",
            ]),
            ("transport", [
                "タクシー", "電車", "バス", "suica", "pasmo", "交通",
                "新幹線", "jr ", "駐車", "ガソリン", "高速道路", "eta",
                "uber", "go タクシー", "飛行機", "航空", "ana ", "jal ",
                "切符", "定期券", "icoca", "manaca", "きっぷ",
            ]),
            ("food", [
                "コンビニ", "セブン", "ファミリーマート", "ファミマ", "ローソン",
                "スーパー", "イオン", "西友", "マルエツ", "ライフ",
                "レストラン", "食堂", "カフェ", "coffee", "コーヒー",
                "スターバックス", "starbucks", "ドトール", "タリーズ",
                "マクドナルド", "mcdonald", "吉野家", "松屋", "すき家",
                "弁当", "ランチ", "ディナー", "居酒屋", "飲食",
                "食料品", "食品", "惣菜", "ベーカリー", "パン屋",
                "ケータリング", "出前", "デリバリー", "uber eats",
                "ミニストップ", "デイリーヤマザキ", "サンクス",
                "飲料", "おにぎり", "サンドイッチ", "お茶", "ジュース",
            ]),
            ("entertainment", [
                "接待", "会議費", "懇親会", "歓迎会", "送別会", "忘年会", "新年会",
                "打ち合わせ", "ミーティング", "セミナー", "研修",
            ]),
            ("insurance", [
                "保険", "保険料", "損害保険", "火災保険", "地震保険", "自動車保険",
                "賠償責任保険", "共済", "生命保険", "医療保険",
            ]),
            ("supplies", [
                "文具", "コピー", "用紙", "消耗品", "事務用品", "トナー", "インク",
                "ペン", "ノート", "封筒", "切手", "印刷", "プリント",
                "電池", "ケーブル", "usb", "マウス", "キーボード",
                "100均", "ダイソー", "セリア", "キャンドゥ",
                "ホームセンター", "文房具", "オフィス用品",
            ]),
        ]

        for (category, keywords) in categoryKeywords {
            for keyword in keywords {
                if lowerText.contains(keyword.lowercased()) {
                    return category
                }
            }
        }

        return "other-expense"
    }

    static func extractSummary(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let skipKeywords = ["合計", "小計", "税", "お会計", "TOTAL", "お釣り", "現金", "カード", "クレジット"]
        var items: [String] = []

        for line in lines {
            let isSkipLine = skipKeywords.contains { line.contains($0) }
            guard !isSkipLine, line.count > 3, line.count < 50 else { continue }
            guard line.range(of: "\\d{2,}", options: .regularExpression) != nil else { continue }

            let cleaned = line.replacingOccurrences(
                of: "\\s*[¥￥]?\\s*[\\d,]+\\s*$",
                with: "",
                options: .regularExpression
            )
            if cleaned.count > 1 {
                items.append(cleaned)
            }
        }

        return items.prefix(3).joined(separator: "、")
    }

    // MARK: - Line Items Extraction

    private static let lineItemPattern = try? NSRegularExpression(
        pattern: "(.+?)\\s+[¥￥]?\\s*([\\d,]+)\\s*$"
    )
    private static let quantityPattern = try? NSRegularExpression(
        pattern: "(?:[xX×]\\s*(\\d+)|(\\d+)\\s*[個点枚本杯袋箱缶瓶冊台])"
    )
    private static let skipLineKeywords = [
        "合計", "小計", "税", "お会計", "TOTAL", "Total", "total",
        "お釣り", "お預り", "お預かり", "現金", "カード", "クレジット",
        "CHANGE", "CASH", "VISA", "MASTER", "JCB", "AMEX",
        "内税", "外税", "消費税", "値引", "割引", "ポイント",
        "TEL", "電話", "レシート", "領収", "No.", "会員",
        "いらっしゃい", "ありがとう", "またお越し",
    ]

    static func extractLineItems(from text: String) -> [LineItem] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var items: [LineItem] = []

        for line in lines {
            // Skip non-item lines
            let isSkipLine = skipLineKeywords.contains { line.contains($0) }
            guard !isSkipLine else { continue }
            guard line.count > 2, line.count < 60 else { continue }

            // Must contain at least one digit (price)
            guard line.range(of: "\\d", options: .regularExpression) != nil else { continue }

            // Try to extract price from end of line
            guard let price = extractLastPrice(from: line), price > 0 else { continue }

            // Extract item name (everything before the price)
            let nameCandidate = line
                .replacingOccurrences(
                    of: "\\s*[¥￥]?\\s*[\\d,]+\\s*円?\\s*$",
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespaces)

            guard nameCandidate.count >= 1 else { continue }

            // Check for quantity pattern (supports x3, X3, ×3, 3個, 3点, etc.)
            var quantity = 1
            let nsRange = NSRange(line.startIndex..., in: line)
            if let qtyMatch = quantityPattern?.firstMatch(in: line, range: nsRange) {
                // Try group 1 (xX×) first, then group 2 (個/点/etc.)
                let group1Range = qtyMatch.range(at: 1)
                let group2Range = qtyMatch.range(at: 2)
                if group1Range.location != NSNotFound,
                   let range = Range(group1Range, in: line),
                   let qty = Int(String(line[range])), qty > 0, qty < 100
                {
                    quantity = qty
                } else if group2Range.location != NSNotFound,
                          let range = Range(group2Range, in: line),
                          let qty = Int(String(line[range])), qty > 0, qty < 100
                {
                    quantity = qty
                }
            }

            let unitPrice = quantity > 1 ? price / quantity : price
            items.append(LineItem(
                name: nameCandidate,
                quantity: quantity,
                unitPrice: unitPrice,
                subtotal: price
            ))
        }

        return items
    }

    private static func extractLastPrice(from line: String) -> Int? {
        // Try ¥ prefix pattern first
        let nsRange = NSRange(line.startIndex..., in: line)
        if let match = yenPrefixPattern?.firstMatch(in: line, range: nsRange),
           let numRange = Range(match.range(at: 1), in: line)
        {
            let numStr = String(line[numRange]).replacingOccurrences(of: ",", with: "")
            return Int(numStr)
        }

        // Try 円 suffix pattern
        if let match = yenSuffixPattern?.firstMatch(in: line, range: nsRange),
           let numRange = Range(match.range(at: 1), in: line)
        {
            let numStr = String(line[numRange]).replacingOccurrences(of: ",", with: "")
            return Int(numStr)
        }

        // Try plain number at end of line
        if let match = plainNumberEndPattern?.firstMatch(in: line, range: nsRange),
           let numRange = Range(match.range(at: 1), in: line)
        {
            let numStr = String(line[numRange]).replacingOccurrences(of: ",", with: "")
            return Int(numStr)
        }

        return nil
    }

    // MARK: - Helpers

    private static func keywordScore(in text: String, keywords: [String]) -> Int {
        keywords.reduce(0) { partial, keyword in
            partial + (text.contains(keyword.lowercased()) ? 1 : 0)
        }
    }

    private static func findMaxAmount(in lines: [String], using pattern: NSRegularExpression?) -> Int {
        var maxAmount = 0
        for line in lines {
            let nsRange = NSRange(line.startIndex..., in: line)
            let matches = pattern?.matches(in: line, range: nsRange) ?? []
            for match in matches {
                if let numRange = Range(match.range(at: 1), in: line) {
                    let numStr = String(line[numRange]).replacingOccurrences(of: ",", with: "")
                    if let num = Int(numStr), num > maxAmount {
                        maxAmount = num
                    }
                }
            }
        }
        return maxAmount
    }

    private static func findDate(in lines: [String], using pattern: NSRegularExpression?) -> String? {
        for line in lines {
            let nsRange = NSRange(line.startIndex..., in: line)
            if let match = pattern?.firstMatch(in: line, range: nsRange),
               let yRange = Range(match.range(at: 1), in: line),
               let mRange = Range(match.range(at: 2), in: line),
               let dRange = Range(match.range(at: 3), in: line)
            {
                let y = String(line[yRange])
                let m = String(format: "%02d", Int(String(line[mRange])) ?? 0)
                let d = String(format: "%02d", Int(String(line[dRange])) ?? 0)
                return "\(y)-\(m)-\(d)"
            }
        }
        return nil
    }

    private static func extractFirstNumber(from line: String) -> Int? {
        let nsRange = NSRange(line.startIndex..., in: line)
        for regex in numberFirstPatterns {
            if let match = regex.firstMatch(in: line, range: nsRange),
               let numRange = Range(match.range(at: 1), in: line)
            {
                let numStr = String(line[numRange]).replacingOccurrences(of: ",", with: "")
                if let num = Int(numStr), num > 0 {
                    return num
                }
            }
        }
        return nil
    }
}
