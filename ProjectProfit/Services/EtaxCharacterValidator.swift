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
    @MainActor
    static func validateForm(_ form: EtaxForm) -> [EtaxExportError] {
        var errors: [EtaxExportError] = []

        if form.fields.isEmpty {
            errors.append(.noData)
            return errors
        }

        guard TaxYearDefinitionLoader.loadDefinition(for: form.fiscalYear) != nil else {
            errors.append(.unsupportedTaxYear(year: form.fiscalYear))
            return errors
        }

        let definitions = TaxYearDefinitionLoader.fieldDefinitions(for: form.formType, fiscalYear: form.fiscalYear)
        let definitionsByKey = Dictionary(uniqueKeysWithValues: definitions.map { ($0.internalKey, $0) })
        let fieldsById = Dictionary(uniqueKeysWithValues: form.fields.map { ($0.id, $0) })

        // 未定義キーの混入を検出
        for field in form.fields where definitionsByKey[field.id] == nil {
            errors.append(.validationFailed(reasons: ["未定義のinternalKeyです: \(field.id)"]))
        }

        // 定義ベース検証
        for definition in definitions {
            let required = isRequired(definition.requiredRule)
            guard let field = fieldsById[definition.internalKey] else {
                if required {
                    errors.append(.missingRequiredField(field: definition.internalKey))
                }
                continue
            }

            let valueText = field.value.exportText

            // 文字種検証は定義有無にかかわらず全フィールドに適用
            let invalid = findInvalidCharacters(in: valueText)
            if let first = invalid.first {
                errors.append(.invalidCharacter(field: field.id, character: first))
            }

            // dataType 検証
            if let dataType = definition.dataType, !matchesDataType(field.value, expected: dataType) {
                errors.append(.validationFailed(reasons: [
                    "型不一致: \(definition.internalKey) expected=\(dataType.rawValue) value=\(valueText)"
                ]))
            }

            // format 検証（定義されている場合のみ）
            if let format = definition.format?.trimmingCharacters(in: .whitespacesAndNewlines),
               !format.isEmpty,
               !matchesFormat(valueText, format: format)
            {
                errors.append(.validationFailed(reasons: [
                    "書式不一致: \(definition.internalKey) format=\(format) value=\(valueText)"
                ]))
            }

            // IDREF 相関（参照先キーが存在し、値が空でないこと）
            if let idref = definition.idref?.trimmingCharacters(in: .whitespacesAndNewlines), !idref.isEmpty {
                let ref = fieldsById[idref]
                if ref == nil || ref?.value.exportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                    errors.append(.validationFailed(reasons: [
                        "相関不一致: \(definition.internalKey) が参照する \(idref) が未設定"
                    ]))
                }
            }
        }

        return errors
    }

    // MARK: - Helpers

    private static func isRequired(_ rule: String?) -> Bool {
        guard let normalized = rule?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !normalized.isEmpty
        else {
            return false
        }

        // 明示的な任意指定は必須扱いにしない
        if normalized == "optional" || normalized == "false" || normalized == "任意" {
            return false
        }
        return true
    }

    private static func matchesDataType(_ value: EtaxFieldValue, expected: EtaxFieldDataType) -> Bool {
        switch (value, expected) {
        case (.number, .number), (.text, .text), (.flag, .flag):
            return true
        default:
            return false
        }
    }

    private static func matchesFormat(_ value: String, format: String) -> Bool {
        let normalized = format.lowercased()

        switch normalized {
        case "yyyy-mm-dd", "date":
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "ja_JP_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: value) != nil
        case "digits7":
            return value.range(of: "^[0-9]{7}$", options: .regularExpression) != nil
        case "digits10", "digits11":
            let min = normalized == "digits10" ? 10 : 11
            return value.range(of: "^[0-9]{\(min)}$", options: .regularExpression) != nil
        default:
            // regex: プレフィックスがある場合は正規表現として評価
            if normalized.hasPrefix("regex:") {
                let pattern = String(format.dropFirst("regex:".count))
                return value.range(of: pattern, options: .regularExpression) != nil
            }
            // 未知書式は失敗扱いせず、将来の拡張余地を残す
            return true
        }
    }
}
