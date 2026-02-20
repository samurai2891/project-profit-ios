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
            state = .completed(receiptData)
        } catch {
            AppLogger.receipt.error("Scan failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Vision OCR

    private func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
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
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                continuation.resume(returning: text)
            }

            request.recognitionLanguages = ["ja", "en"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: ReceiptScanError.ocrFailed(underlying: error))
            }
        }
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
        以下はレシートまたは請求書のOCRテキストです。情報を抽出してください。
        金額は税込の合計金額を整数で返してください。
        日付はyyyy-MM-dd形式で返してください。
        カテゴリはhosting, tools, ads, contractor, communication, supplies, transport, \
        other-expenseから最適なものを選んでください。

        OCRテキスト:
        \(truncatedText)
        """

        let response = try await session.respond(to: prompt, generating: ReceiptExtraction.self)
        let extraction = response.content

        // Extract line items in a separate request to avoid nesting issues
        let lineItems = await extractLineItemsWithFoundationModels(from: truncatedText, session: session)

        return ReceiptData(
            totalAmount: extraction.totalAmount,
            date: extraction.date,
            storeName: extraction.storeName,
            estimatedCategory: extraction.estimatedCategory,
            itemSummary: extraction.itemSummary,
            lineItems: lineItems
        )
    }

    @available(iOS 26, *)
    private func extractLineItemsWithFoundationModels(
        from text: String,
        session: LanguageModelSession
    ) async -> [LineItem] {
        do {
            let prompt = """
            以下のレシートOCRテキストから明細行（品目）を抽出してください。
            合計、小計、税、お釣り、支払い方法の行は除外してください。
            品目ごとに名前、数量、単価、小計を返してください。

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
        ReceiptData(
            totalAmount: RegexReceiptParser.extractAmount(from: text),
            date: RegexReceiptParser.extractDate(from: text),
            storeName: RegexReceiptParser.extractStoreName(from: text),
            estimatedCategory: RegexReceiptParser.estimateCategory(from: text),
            itemSummary: RegexReceiptParser.extractSummary(from: text),
            lineItems: RegexReceiptParser.extractLineItems(from: text)
        )
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
    private static let storeSkipPatterns: [NSRegularExpression] = [
        "^\\d+$", "^[¥￥]", "^20\\d{2}", "^\\d{1,2}[:/]",
        "^TEL", "^T\\d{4}", "^レシート", "^領収",
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private static let totalKeywords = [
        "合計", "お会計", "お買上", "お買い上げ",
        "合計金額", "請求金額", "請求額", "ご請求",
        "TOTAL", "Total",
    ]

    static func extractAmount(from text: String) -> Int {
        let lines = text.components(separatedBy: .newlines)

        // Priority 1: lines containing total keywords
        for keyword in totalKeywords {
            for line in lines where line.contains(keyword) {
                if let amount = extractFirstNumber(from: line), amount > 0 {
                    return amount
                }
            }
        }

        // Priority 2: largest yen-prefixed number
        var maxAmount = findMaxAmount(in: lines, using: yenPrefixPattern)
        if maxAmount > 0 { return maxAmount }

        // Priority 3: number followed by 円
        maxAmount = findMaxAmount(in: lines, using: yenSuffixPattern)
        return maxAmount
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

    static func estimateCategory(from text: String) -> String {
        let lowerText = text.lowercased()

        let categoryKeywords: [(category: String, keywords: [String])] = [
            ("hosting", ["サーバー", "server", "aws", "gcp", "azure", "ドメイン", "domain", "heroku", "vercel"]),
            ("tools", ["ソフトウェア", "figma", "notion", "slack", "github", "サブスク", "ライセンス", "adobe"]),
            ("ads", ["広告", "google ads", "facebook", "meta", "プロモーション"]),
            ("contractor", ["外注", "請負", "委託", "業務委託"]),
            ("communication", ["電話", "通信", "インターネット", "wi-fi", "携帯", "ntt", "回線"]),
            ("supplies", ["文具", "コピー", "用紙", "消耗品", "事務用品", "トナー", "インク"]),
            ("transport", ["タクシー", "電車", "バス", "suica", "pasmo", "交通", "新幹線", "jr ", "駐車"]),
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
        pattern: "[xX×]\\s*(\\d+)"
    )
    private static let skipLineKeywords = [
        "合計", "小計", "税", "お会計", "TOTAL", "Total", "total",
        "お釣り", "お預り", "お預かり", "現金", "カード", "クレジット",
        "CHANGE", "CASH", "VISA", "MASTER", "JCB",
        "内税", "外税", "消費税", "値引", "割引",
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

            // Check for quantity pattern
            var quantity = 1
            let nsRange = NSRange(line.startIndex..., in: line)
            if let qtyMatch = quantityPattern?.firstMatch(in: line, range: nsRange),
               let qtyRange = Range(qtyMatch.range(at: 1), in: line),
               let qty = Int(String(line[qtyRange])), qty > 0, qty < 100
            {
                quantity = qty
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
        let plainNumberPattern = try? NSRegularExpression(pattern: "([\\d,]{2,})\\s*$")
        if let match = plainNumberPattern?.firstMatch(in: line, range: nsRange),
           let numRange = Range(match.range(at: 1), in: line)
        {
            let numStr = String(line[numRange]).replacingOccurrences(of: ",", with: "")
            return Int(numStr)
        }

        return nil
    }

    // MARK: - Helpers

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
