import Foundation

enum SearchIndexNormalizer {
    static func normalizeText(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
            .lowercased() ?? ""
    }

    static func normalizeOptionalText(_ value: String?) -> String? {
        let normalized = normalizeText(value)
        return normalized.isEmpty ? nil : normalized
    }

    static func normalizeIdentifier(_ value: String?) -> String? {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
            .lowercased() ?? ""
        return normalized.isEmpty ? nil : normalized
    }
}
