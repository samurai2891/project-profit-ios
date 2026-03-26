import Foundation
import PDFKit
import UIKit
import Vision

@MainActor
struct StatementPDFParser {
    func parse(
        fileData: Data,
        fallbackYear: Int? = nil
    ) async throws -> [StatementLineDraft] {
        guard let document = PDFDocument(data: fileData) else {
            throw AppError.invalidInput(message: "PDF を読み込めません")
        }

        let extractedText = extractText(from: document)
        let text: String
        if extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = try await recognizeTextWithOCR(from: document)
        } else {
            text = extractedText
        }

        let drafts = StatementTextLineParser(fallbackYear: fallbackYear).parse(text: text)
        guard !drafts.isEmpty else {
            throw AppError.invalidInput(message: "明細行を抽出できませんでした")
        }
        return drafts
    }

    private func extractText(from document: PDFDocument) -> String {
        (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }

    private func recognizeTextWithOCR(from document: PDFDocument) async throws -> String {
        var collected: [String] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                continue
            }
            let image = render(page: page)
            let pageText = try await recognizeText(from: image)
            if !pageText.isEmpty {
                collected.append(pageText)
            }
        }
        return collected.joined(separator: "\n")
    }

    private func render(page: PDFPage) -> UIImage {
        let bounds = page.bounds(for: .mediaBox)
        let renderScale: CGFloat = 2.0
        let size = CGSize(width: bounds.width * renderScale, height: bounds.height * renderScale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: renderScale, y: -renderScale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }

    private func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw AppError.invalidInput(message: "PDF ページ画像を生成できません")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
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

            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

struct StatementTextLineParser {
    private let fallbackYear: Int?

    init(fallbackYear: Int?) {
        self.fallbackYear = fallbackYear
    }

    func parse(text: String) -> [StatementLineDraft] {
        text
            .components(separatedBy: .newlines)
            .compactMap(parseLine)
    }

    func parseLine(_ line: String) -> StatementLineDraft? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let amountMatches = StatementPatterns.amount.matches(in: trimmed, range: nsRange(for: trimmed))
        guard let amountMatch = amountMatches.last,
              let amountRange = Range(amountMatch.range(at: 1), in: trimmed),
              let amount = parseAmount(String(trimmed[amountRange])) else {
            return nil
        }
        guard let dateRange = firstDateRange(in: trimmed),
              let date = parseDate(String(trimmed[dateRange])) else {
            return nil
        }

        var description = trimmed
        description.removeSubrange(dateRange)
        if let amountRangeInUpdated = Range(amountMatch.range(at: 1), in: description) {
            description.removeSubrange(amountRangeInUpdated)
        } else {
            description = description.replacingOccurrences(of: String(trimmed[amountRange]), with: "")
        }
        description = description
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return nil }

        let direction = resolveDirection(line: trimmed, amount: amount)
        return StatementLineDraft(
            date: date,
            description: description,
            amount: amount.magnitude,
            direction: direction,
            counterparty: nil,
            reference: nil,
            memo: nil
        )
    }

    private func parseAmount(_ value: String) -> Decimal? {
        let normalized = value
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "円", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: normalized)
    }

    private func parseDate(_ value: String) -> Date? {
        let formatters = [
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "yyyy.M.d",
            "yyyy/M/d",
            "MM/dd",
            "M/d",
        ].map(makeFormatter)

        for formatter in formatters {
            if let date = formatter.date(from: value) {
                if value.split(separator: "/").count == 2 || value.split(separator: "-").count == 2 {
                    guard let fallbackYear else { return date }
                    let comps = Calendar.current.dateComponents([.month, .day], from: date)
                    return Calendar.current.date(from: DateComponents(year: fallbackYear, month: comps.month, day: comps.day))
                }
                return date
            }
        }
        return nil
    }

    private func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    private func resolveDirection(line: String, amount: Decimal) -> StatementDirection {
        let normalized = SearchIndexNormalizer.normalizeText(line)
        if ["出金", "引落", "支払", "withdrawal", "payment", "debit"].contains(where: normalized.contains) {
            return .outflow
        }
        if ["入金", "預入", "deposit", "credit", "refund"].contains(where: normalized.contains) {
            return .inflow
        }
        return amount.sign == .minus ? .outflow : .inflow
    }

    private func firstDateRange(in text: String) -> Range<String.Index>? {
        let nsRange = nsRange(for: text)
        if let match = StatementPatterns.fullDate.firstMatch(in: text, range: nsRange),
           let range = Range(match.range(at: 1), in: text) {
            return range
        }
        if let match = StatementPatterns.monthDay.firstMatch(in: text, range: nsRange),
           let range = Range(match.range(at: 1), in: text) {
            return range
        }
        return nil
    }

    private func nsRange(for text: String) -> NSRange {
        NSRange(text.startIndex..., in: text)
    }
}

private enum StatementPatterns {
    static let fullDate = try! NSRegularExpression(pattern: "(\\d{4}[/-]\\d{1,2}[/-]\\d{1,2})")
    static let monthDay = try! NSRegularExpression(pattern: "(\\d{1,2}[/-]\\d{1,2})")
    static let amount = try! NSRegularExpression(pattern: "([-+]?¥?\\d[\\d,]*(?:\\.\\d+)?)")
}
