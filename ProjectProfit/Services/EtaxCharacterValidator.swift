import Foundation

/// e-Tax XML で使用可能な文字のバリデーション
/// JIS X 0208 準拠 + ASCII英数字
enum EtaxCharacterValidator {

    /// JIS X 0208 で許可されない文字を検出
    static func findInvalidCharacters(in text: String) -> [Character] {
        text.filter { !isValidCharacter($0) }
            .map { $0 }
    }

    /// 文字列が全てe-Tax使用可能な文字か
    static func isValid(_ text: String) -> Bool {
        text.allSatisfy { isValidCharacter($0) }
    }

    /// 禁止文字をサニタイズ（全角スペースに置換）
    static func sanitize(_ text: String) -> String {
        String(text.map { isValidCharacter($0) ? $0 : "\u{3000}" })
    }

    /// 個別文字の判定
    /// - ASCII英数字・記号（0x20-0x7E）
    /// - JIS X 0208 の範囲（一般的な日本語文字）
    static func isValidCharacter(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let value = scalar.value

        // ASCII printable range (space to ~)
        if value >= 0x20 && value <= 0x7E {
            return true
        }

        // 全角スペース
        if value == 0x3000 {
            return true
        }

        // CJK統合漢字 (common)
        if value >= 0x4E00 && value <= 0x9FFF {
            return true
        }

        // ひらがな
        if value >= 0x3040 && value <= 0x309F {
            return true
        }

        // カタカナ
        if value >= 0x30A0 && value <= 0x30FF {
            return true
        }

        // 全角英数字・記号
        if value >= 0xFF01 && value <= 0xFF5E {
            return true
        }

        // 全角カタカナ拡張
        if value >= 0x31F0 && value <= 0x31FF {
            return true
        }

        // CJK記号と句読点
        if value >= 0x3001 && value <= 0x303F {
            return true
        }

        // 丸数字・括弧付き文字等 (一部許可)
        if value >= 0x2460 && value <= 0x24FF {
            return true
        }

        return false
    }

    /// フォーム全体のバリデーション
    static func validateForm(_ form: EtaxForm) -> [EtaxExportError] {
        var errors: [EtaxExportError] = []

        if form.fields.isEmpty {
            errors.append(.noData)
            return errors
        }

        for field in form.fields {
            let invalid = findInvalidCharacters(in: field.value.exportText)
            if let first = invalid.first {
                errors.append(.invalidCharacter(field: field.id, character: first))
            }
        }

        return errors
    }
}
