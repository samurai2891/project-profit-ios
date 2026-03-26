import Foundation

/// Canonical persistence 向けの JSON encode / decode 共通化
enum CanonicalJSONCoder {
    enum StrictDecodeError: LocalizedError {
        case missingValue
        case emptyValue
        case invalidUTF8
        case decodingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .missingValue:
                return "JSON 値が存在しません"
            case .emptyValue:
                return "JSON 値が空です"
            case .invalidUTF8:
                return "JSON を UTF-8 として解釈できません"
            case .decodingFailed(let error):
                return error.localizedDescription
            }
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func encode<T: Encodable>(_ value: T, fallback: String) -> String {
        guard let data = try? encoder.encode(value), let json = String(data: data, encoding: .utf8) else {
            return fallback
        }
        return json
    }

    static func encodeIfPresent<T: Encodable>(_ value: T?) -> String? {
        guard let value,
              let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String?, fallback: T) -> T {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8) else {
            return fallback
        }
        return (try? decoder.decode(T.self, from: data)) ?? fallback
    }

    static func decodeStrict<T: Decodable>(_ type: T.Type, from json: String?) throws -> T {
        guard let json else {
            throw StrictDecodeError.missingValue
        }
        guard !json.isEmpty else {
            throw StrictDecodeError.emptyValue
        }
        guard let data = json.data(using: .utf8) else {
            throw StrictDecodeError.invalidUTF8
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw StrictDecodeError.decodingFailed(error)
        }
    }

    static func decodeIfPresent<T: Decodable>(_ type: T.Type, from json: String?) -> T? {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8) else {
            return nil
        }
        return try? decoder.decode(T.self, from: data)
    }
}
