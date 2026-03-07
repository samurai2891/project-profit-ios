import Foundation

/// 伝票番号の生成と管理
struct VoucherNumber: Codable, Sendable, Equatable, Comparable {
    let value: String

    /// フォーマット: YYYY-NNN-NNNNN (例: 2025-001-00001)
    init(taxYear: Int, month: Int, sequence: Int) {
        self.value = String(format: "%04d-%03d-%05d", taxYear, month, sequence)
    }

    init(rawValue: String) {
        self.value = rawValue
    }

    var taxYear: Int? {
        let parts = value.split(separator: "-")
        guard parts.count >= 1 else { return nil }
        return Int(parts[0])
    }

    var month: Int? {
        let parts = value.split(separator: "-")
        guard parts.count >= 2 else { return nil }
        return Int(parts[1])
    }

    var sequence: Int? {
        let parts = value.split(separator: "-")
        guard parts.count >= 3 else { return nil }
        return Int(parts[2])
    }

    static func < (lhs: VoucherNumber, rhs: VoucherNumber) -> Bool {
        lhs.value < rhs.value
    }
}
