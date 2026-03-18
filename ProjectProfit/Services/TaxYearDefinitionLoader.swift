import Foundation

/// 年度別TaxLine→フィールドラベル定義をバンドルJSONからロードするサービス
@MainActor
enum TaxYearDefinitionLoader {

    struct PackCoverageReport {
        let missingForms: [String]
        let missingPackKeysByForm: [String: [String]]
        let unresolvedBuilderKeysByForm: [String: [String]]
        let missingRequiredRulesByForm: [String: [String]]
        let whitePage2MissingKeys: [String]
        let whiteLeafOnlyMappingViolations: [String]

        var isClean: Bool {
            missingForms.isEmpty &&
            missingPackKeysByForm.values.allSatisfy(\.isEmpty) &&
            unresolvedBuilderKeysByForm.values.allSatisfy(\.isEmpty) &&
            missingRequiredRulesByForm.values.allSatisfy(\.isEmpty) &&
            whitePage2MissingKeys.isEmpty &&
            whiteLeafOnlyMappingViolations.isEmpty
        }
    }

    // MARK: - Cache

    private static var cache: [Int: TaxYearDefinition] = [:]
    private static var packYearsCache: [Int]?
    private static let commonFormKey = "common"
    private static let taxYearPackProvider = BundledTaxYearPackProvider(bundle: .main)

    /// 指定年度のTaxLine用フィールドラベルを返す
    /// JSON未定義またはロード失敗時は `taxLine.label` にフォールバック
    static func fieldLabel(for taxLine: TaxLine, fiscalYear: Int) -> String {
        fieldLabel(for: taxLine, formType: .blueReturn, fiscalYear: fiscalYear)
    }

    /// 指定年度・様式のTaxLine用フィールドラベルを返す
    static func fieldLabel(for taxLine: TaxLine, formType: EtaxFormType, fiscalYear: Int) -> String {
        let definition = loadDefinition(for: fiscalYear)
        let candidates = definition?.fields.filter { $0.taxLineRawValue == taxLine.rawValue } ?? []
        let formKey = formType.definitionFormKey

        // 先に対象フォームの定義を優先し、なければ共通定義を参照する
        if let matched = candidates.first(where: { resolvedFormKey(of: $0) == formKey }) {
            return matched.fieldLabel
        }
        if let common = candidates.first(where: { resolvedFormKey(of: $0) == commonFormKey }) {
            return common.fieldLabel
        }
        if let fallback = candidates.first {
            return fallback.fieldLabel
        }
        return taxLine.label
    }

    /// 指定年度の internalKey に対応するフィールド定義を返す
    static func fieldDefinition(for internalKey: String, fiscalYear: Int) -> TaxFieldDefinition? {
        loadDefinition(for: fiscalYear)?.fields.first(where: { $0.internalKey == internalKey })
    }

    /// 指定年度・様式の internalKey に対応するフィールド定義を返す
    static func fieldDefinition(for internalKey: String, formType: EtaxFormType, fiscalYear: Int) -> TaxFieldDefinition? {
        guard let definition = loadDefinition(for: fiscalYear) else {
            return nil
        }
        let formKey = formType.definitionFormKey

        // 対象フォームを優先し、存在しない場合はcommonを許容
        if let matched = definition.fields.first(where: {
            $0.internalKey == internalKey && resolvedFormKey(of: $0) == formKey
        }) {
            return matched
        }
        return definition.fields.first(where: {
            $0.internalKey == internalKey && resolvedFormKey(of: $0) == commonFormKey
        })
    }

    /// 指定年度・様式に対応する全フィールド定義を返す
    static func fieldDefinitions(for formType: EtaxFormType, fiscalYear: Int) -> [TaxFieldDefinition] {
        guard let definition = loadDefinition(for: fiscalYear) else {
            return []
        }
        let formKey = formType.definitionFormKey
        return definition.fields.filter {
            let resolved = resolvedFormKey(of: $0)
            return resolved == formKey || resolved == commonFormKey
        }
    }

    /// 指定年度の internalKey に対応する XML タグを返す
    static func xmlTag(for internalKey: String, fiscalYear: Int) -> String? {
        guard let definition = fieldDefinition(for: internalKey, fiscalYear: fiscalYear),
              let xmlTag = definition.xmlTag,
              !xmlTag.isEmpty
        else {
            return nil
        }
        return xmlTag
    }

    /// 指定年度・様式の internalKey に対応する XML タグを返す
    static func xmlTag(for internalKey: String, formType: EtaxFormType, fiscalYear: Int) -> String? {
        guard let definition = fieldDefinition(for: internalKey, formType: formType, fiscalYear: fiscalYear),
              let xmlTag = definition.xmlTag,
              !xmlTag.isEmpty
        else {
            return nil
        }
        return xmlTag
    }

    /// 指定年度の全フィールド定義をロードする
    /// filing pack のみを正本として組み立てる
    static func loadDefinition(for fiscalYear: Int) -> TaxYearDefinition? {
        if let cached = cache[fiscalYear] { return cached }

        if let packDefinition = loadDefinitionFromPack(for: fiscalYear) {
            cache[fiscalYear] = packDefinition
            return packDefinition
        }
        return nil
    }

    /// パック内の filing/*.json からフィールド定義を組み立てる
    private static func loadDefinitionFromPack(for fiscalYear: Int) -> TaxYearDefinition? {
        guard let filingDir = packFilingDirectoryURL(for: fiscalYear) else {
            return nil
        }

        let filingFiles: [(formKey: String, fileName: String)] = [
            (commonFormKey, "common.json"),
            ("blue_general", "blue_general.json"),
            ("blue_cash_basis", "blue_cash_basis.json"),
            ("white_shushi", "white_shushi.json")
        ]

        var allFields: [TaxFieldDefinition] = []
        var forms: [String: TaxFormDefinition] = [:]
        var foundAny = false

        for filing in filingFiles {
            let fileURL = filingDir.appendingPathComponent(filing.fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL),
                  let parsed = try? JSONDecoder().decode(PackFilingDefinition.self, from: data)
            else {
                continue
            }
            foundAny = true

            forms[filing.formKey] = TaxFormDefinition(
                formId: parsed.formId,
                formVer: parsed.formVer,
                rootTag: parsed.rootTag,
                mappingFile: nil
            )

            for section in parsed.sections {
                for field in section.fields {
                    let taxFieldDef = TaxFieldDefinition(
                        internalKey: field.internalKey,
                        fieldLabel: field.fieldLabel,
                        xmlTag: field.xmlTag,
                        taxLineRawValue: field.taxLineRawValue ?? resolveTaxLineRawValue(for: field.internalKey),
                        section: section.id,
                        dataType: EtaxFieldDataType(rawValue: field.dataType),
                        form: filing.formKey,
                        idref: field.idref,
                        format: field.format,
                        requiredRule: field.requiredRule
                    )
                    allFields.append(taxFieldDef)
                }
            }
        }

        guard foundAny else { return nil }

        return TaxYearDefinition(
            fiscalYear: fiscalYear,
            forms: forms,
            fields: allFields
        )
    }

    /// パック内の filing ディレクトリ URL を返す
    private static func packFilingDirectoryURL(for fiscalYear: Int) -> URL? {
        // バンドルリソース内のフォルダ型パス
        if let bundledRoot = Bundle.main.resourceURL {
            let filingDir = bundledRoot
                .appendingPathComponent("TaxYearPacks", isDirectory: true)
                .appendingPathComponent(String(fiscalYear), isDirectory: true)
                .appendingPathComponent("filing", isDirectory: true)
            if FileManager.default.fileExists(atPath: filingDir.path) {
                return filingDir
            }
        }

        // ソースツリーからのフォールバック（テスト時）
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // ProjectProfit
        let sourceFiling = sourceRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("TaxYearPacks", isDirectory: true)
            .appendingPathComponent(String(fiscalYear), isDirectory: true)
            .appendingPathComponent("filing", isDirectory: true)
        return FileManager.default.fileExists(atPath: sourceFiling.path) ? sourceFiling : nil
    }

    /// internalKey から TaxLine.rawValue を逆引きする
    private static func resolveTaxLineRawValue(for internalKey: String) -> String? {
        // pack filing フィールドの internalKey と TaxLine.rawValue のマッピング
        let mappings: [String: String] = [
            "revenue_sales_revenue": "sales_revenue",
            "revenue_other_income": "other_income",
            "expense_rent": "rent",
            "expense_utilities": "utilities",
            "expense_travel": "travel",
            "expense_communication": "communication",
            "expense_advertising": "advertising",
            "expense_entertainment": "entertainment",
            "expense_depreciation": "depreciation",
            "expense_insurance": "insurance",
            "expense_interest": "interest",
            "expense_supplies": "supplies",
            "expense_taxes": "taxes",
            "expense_outsourcing": "outsourcing",
            "expense_misc": "misc",
            "shushi_revenue_sales": "sales_revenue",
            "shushi_revenue_total": "sales_revenue",
            "shushi_expense_rent": "rent",
            "shushi_expense_utilities": "utilities",
            "shushi_expense_travel": "travel",
            "shushi_expense_communication": "communication",
            "shushi_expense_advertising": "advertising",
            "shushi_expense_entertainment": "entertainment",
            "shushi_expense_depreciation": "depreciation",
            "shushi_expense_insurance": "insurance",
            "shushi_expense_interest": "interest",
            "shushi_expense_supplies": "supplies",
            "shushi_expense_taxes": "taxes",
            "shushi_expense_outsourcing": "outsourcing",
            "shushi_expense_misc": "misc",
            "shushi_rent_breakdown": "rent"
        ]
        return mappings[internalKey]
    }

    /// 対応済み年分かどうかを返す
    static func isSupported(year fiscalYear: Int) -> Bool {
        loadDefinition(for: fiscalYear) != nil || supportedPackYears().contains(fiscalYear)
    }

    /// 指定様式が対応済みかどうかを返す
    static func isSupported(year fiscalYear: Int, formType: EtaxFormType) -> Bool {
        guard let definition = loadDefinition(for: fiscalYear) else {
            return false
        }
        let formKey = formType.definitionFormKey

        // formsメタがあればそれを優先
        if let forms = definition.forms, forms[formKey] != nil {
            return true
        }
        // 旧定義との互換のため fields から判定
        return definition.fields.contains { resolvedFormKey(of: $0) == formKey }
    }

    /// バンドルに存在する対応年分一覧を返す
    static func supportedYears() -> [Int] {
        supportedYears(formType: nil)
    }

    /// 指定様式で利用可能な対応年分一覧を返す
    static func supportedYears(formType: EtaxFormType?) -> [Int] {
        let sorted = supportedPackYears().sorted()
        guard let formType else {
            return sorted
        }
        return sorted.filter { isSupported(year: $0, formType: formType) }
    }

    /// キャッシュをクリアする（テスト用）
    static func clearCache() {
        cache = [:]
        packYearsCache = nil
    }

    /// 全TaxLineのラベルが定義されているか検証する
    static func validateCoverage(for fiscalYear: Int) -> [TaxLine] {
        guard let definition = loadDefinition(for: fiscalYear) else {
            return TaxLine.allCases.map { $0 }
        }
        let definedRawValues = Set(definition.fields.compactMap(\.taxLineRawValue))
        return TaxLine.allCases.filter { !definedRawValues.contains($0.rawValue) }
    }

    /// filing pack と builder/populator 由来キーの coverage を検証する
    static func validatePackCoverage(for fiscalYear: Int) -> PackCoverageReport {
        let requiredFormKeys = [commonFormKey, "blue_general", "white_shushi", "blue_cash_basis"]
        let filingDefinitions = loadPackFilingDefinitions(for: fiscalYear)
        let missingForms = requiredFormKeys.filter { filingDefinitions[$0] == nil }

        let packKeysByForm = Dictionary(uniqueKeysWithValues: filingDefinitions.map { formKey, definition in
            let keys = Set(definition.sections.flatMap { $0.fields.map(\.internalKey) })
            return (formKey, keys)
        })
        let requiredRulesByForm = Dictionary(uniqueKeysWithValues: filingDefinitions.map { formKey, definition in
            let mapping = Dictionary(uniqueKeysWithValues: definition.sections.flatMap { section in
                section.fields.map { ($0.internalKey, $0.requiredRule) }
            })
            return (formKey, mapping)
        })
        let fieldMetaByForm = Dictionary(uniqueKeysWithValues: filingDefinitions.map { formKey, definition in
            let mapping = Dictionary(uniqueKeysWithValues: definition.sections.flatMap { section in
                section.fields.map { ($0.internalKey, $0) }
            })
            return (formKey, mapping)
        })

        let expectedPackKeys = expectedPackKeysByForm()
        let allowedBuilderOnlyKeys = allowedBuilderOnlyKeysByForm()

        var missingPackKeysByForm: [String: [String]] = [:]
        var unresolvedBuilderKeysByForm: [String: [String]] = [:]

        for formKey in requiredFormKeys {
            let actualKeys = packKeysByForm[formKey] ?? []
            let expectedKeys = expectedPackKeys[formKey] ?? []
            let missingKeys = expectedKeys.subtracting(actualKeys).sorted()
            missingPackKeysByForm[formKey] = missingKeys

            let unresolved = builderGeneratedKeys(for: formKey)
                .filter { !actualKeys.contains($0) && !(allowedBuilderOnlyKeys[formKey] ?? []).contains($0) }
                .sorted()
            unresolvedBuilderKeysByForm[formKey] = unresolved
        }

        let whiteRequiredKeys = whiteRequiredRuleKeys()
        let whiteRequiredRules = requiredRulesByForm["white_shushi"] ?? [:]
        let missingWhiteRequiredRules = whiteRequiredKeys.filter { whiteRequiredRules[$0] != "required" }.sorted()

        let whitePage2Keys = whitePage2CoverageKeys()
        let whitePackKeys = packKeysByForm["white_shushi"] ?? []
        let whitePage2MissingKeys = whitePage2Keys.filter { !whitePackKeys.contains($0) }.sorted()

        let whiteLeafOnlyMappingViolations = validateWhiteLeafOnlyMappings(fieldMetaByForm["white_shushi"] ?? [:])

        return PackCoverageReport(
            missingForms: missingForms,
            missingPackKeysByForm: missingPackKeysByForm,
            unresolvedBuilderKeysByForm: unresolvedBuilderKeysByForm,
            missingRequiredRulesByForm: ["white_shushi": missingWhiteRequiredRules],
            whitePage2MissingKeys: whitePage2MissingKeys,
            whiteLeafOnlyMappingViolations: whiteLeafOnlyMappingViolations
        )
    }

    // MARK: - Helpers

    private static func resolvedFormKey(of definition: TaxFieldDefinition) -> String {
        if let explicit = definition.form?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty
        {
            return explicit
        }

        // 後方互換: 旧TaxYear定義（formなし）を推定
        let key = definition.internalKey
        if key.hasPrefix("shushi_") {
            return "white_shushi"
        }
        if key.hasPrefix("declarant_") {
            return commonFormKey
        }
        return "blue_general"
    }

    private static func supportedPackYears() -> [Int] {
        if let cached = packYearsCache {
            return cached
        }
        let years = taxYearPackProvider.availableYearsSync()
        packYearsCache = years
        return years
    }

    private static func loadPackFilingDefinitions(for fiscalYear: Int) -> [String: PackFilingDefinition] {
        guard let filingDir = packFilingDirectoryURL(for: fiscalYear) else {
            return [:]
        }

        let filingFiles: [(formKey: String, fileName: String)] = [
            (commonFormKey, "common.json"),
            ("blue_general", "blue_general.json"),
            ("blue_cash_basis", "blue_cash_basis.json"),
            ("white_shushi", "white_shushi.json")
        ]

        var definitions: [String: PackFilingDefinition] = [:]
        for filing in filingFiles {
            let fileURL = filingDir.appendingPathComponent(filing.fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL),
                  let parsed = try? JSONDecoder().decode(PackFilingDefinition.self, from: data)
            else {
                continue
            }
            definitions[filing.formKey] = parsed
        }
        return definitions
    }

    private static func builderGeneratedKeys(for formKey: String) -> Set<String> {
        switch formKey {
        case commonFormKey:
            return [
                "declarant_name",
                "declarant_name_kana",
                "declarant_postal_code",
                "declarant_address",
                "declarant_phone",
                "declarant_business_name",
                "declarant_business_category",
            ]
        case "blue_general":
            var keys: Set<String> = [
                "revenue_sales_revenue",
                "revenue_other_income",
                "expense_rent",
                "expense_utilities",
                "expense_travel",
                "expense_communication",
                "expense_advertising",
                "expense_entertainment",
                "expense_depreciation",
                "expense_insurance",
                "expense_interest",
                "expense_supplies",
                "expense_taxes",
                "expense_outsourcing",
                "expense_misc",
                "income_total_revenue",
                "income_total_expenses",
                "income_net",
                "inventory_opening",
                "inventory_purchases",
                "inventory_closing",
                "inventory_cogs",
                "bs_asset_cash",
                "bs_asset_checking_deposit",
                "bs_asset_time_deposit",
                "bs_asset_other_deposit",
                "bs_asset_notes_receivable",
                "bs_asset_accounts_receivable",
                "bs_asset_securities",
                "bs_asset_inventory",
                "bs_asset_prepayments",
                "bs_asset_loans_receivable",
                "bs_asset_buildings",
                "bs_asset_building_attachments",
                "bs_asset_machinery",
                "bs_asset_vehicles",
                "bs_asset_tools_fixtures_equipment",
                "bs_asset_land",
                "bs_asset_owner_draw",
                "bs_total_assets",
                "bs_liability_notes_payable",
                "bs_liability_accounts_payable",
                "bs_liability_loans_payable",
                "bs_liability_unpaid_amount",
                "bs_liability_advance_receipts",
                "bs_liability_deposits_received",
                "bs_liability_allowance_bad_debts",
                "bs_equity_owner_borrowings",
                "bs_equity_owner_capital",
                "bs_equity_income_before_blue_deduction",
                "bs_total_liabilities_and_equity",
            ]
            for index in 1...7 {
                keys.insert("bs_asset_additional_\(index)_name")
                keys.insert("bs_asset_additional_\(index)_closing")
                keys.insert("bs_liability_additional_\(index)_name")
                keys.insert("bs_liability_additional_\(index)_closing")
                keys.insert("bs_equity_additional_\(index)_name")
                keys.insert("bs_equity_additional_\(index)_closing")
            }
            return keys
        case "white_shushi":
            var keys: Set<String> = [
                "shushi_revenue_sales",
                "shushi_revenue_total",
                "shushi_revenue_home_consumption",
                "shushi_revenue_other",
                "shushi_inventory_opening",
                "shushi_inventory_purchases",
                "shushi_inventory_subtotal",
                "shushi_inventory_closing",
                "shushi_inventory_cogs",
                "shushi_income_gross",
                "shushi_expense_salary",
                "shushi_expense_outsourcing",
                "shushi_expense_depreciation",
                "shushi_expense_bad_debt",
                "shushi_expense_rent",
                "shushi_expense_interest",
                "shushi_expense_taxes",
                "shushi_expense_shipping",
                "shushi_expense_utilities",
                "shushi_expense_travel",
                "shushi_expense_communication",
                "shushi_expense_advertising",
                "shushi_expense_entertainment",
                "shushi_expense_insurance",
                "shushi_expense_repairs",
                "shushi_expense_supplies",
                "shushi_expense_welfare",
                "shushi_expense_additional_name",
                "shushi_expense_additional_amount",
                "shushi_expense_misc",
                "shushi_expense_other_subtotal",
                "shushi_expense_total",
                "shushi_income_before_employee_deduction",
                "shushi_employee_deduction",
                "shushi_income_net",
                "shushi_depreciation_next_total_label",
                "shushi_depreciation_total_ordinary",
                "shushi_depreciation_total_special",
                "shushi_depreciation_total_amount",
                "shushi_depreciation_total_necessary_expense",
                "shushi_depreciation_total_remaining_balance",
                "shushi_sales_detail_other_total",
                "shushi_sales_detail_reduced_tax_total",
                "shushi_sales_detail_total",
                "shushi_purchase_detail_other_total",
                "shushi_purchase_detail_reduced_tax_total",
                "shushi_purchase_detail_total",
            ]
            for index in 1...4 {
                keys.insert("shushi_sales_detail_\(index)_name")
                keys.insert("shushi_sales_detail_\(index)_address")
                keys.insert("shushi_sales_detail_\(index)_invoice_registration")
                keys.insert("shushi_sales_detail_\(index)_corporate_number")
                keys.insert("shushi_sales_detail_\(index)_amount")
                keys.insert("shushi_purchase_detail_\(index)_name")
                keys.insert("shushi_purchase_detail_\(index)_address")
                keys.insert("shushi_purchase_detail_\(index)_invoice_registration")
                keys.insert("shushi_purchase_detail_\(index)_corporate_number")
                keys.insert("shushi_purchase_detail_\(index)_amount")
            }
            for index in 1...6 {
                keys.insert("shushi_depreciation_detail_\(index)_name")
                keys.insert("shushi_depreciation_detail_\(index)_acquired_year_month")
                keys.insert("shushi_depreciation_detail_\(index)_acquisition_cost")
                keys.insert("shushi_depreciation_detail_\(index)_method")
                keys.insert("shushi_depreciation_detail_\(index)_useful_life")
                keys.insert("shushi_depreciation_detail_\(index)_period_months")
                keys.insert("shushi_depreciation_detail_\(index)_ordinary_amount")
                keys.insert("shushi_depreciation_detail_\(index)_necessary_expense_amount")
                keys.insert("shushi_depreciation_detail_\(index)_remaining_balance")
            }
            for index in 1...2 {
                keys.insert("shushi_rent_detail_\(index)_address")
                keys.insert("shushi_rent_detail_\(index)_name")
                keys.insert("shushi_rent_detail_\(index)_property")
                keys.insert("shushi_rent_detail_\(index)_key_money")
                keys.insert("shushi_rent_detail_\(index)_renewal_fee")
                keys.insert("shushi_rent_detail_\(index)_rent")
                keys.insert("shushi_rent_detail_\(index)_necessary_expense")
            }
            return keys
        case "blue_cash_basis":
            return [
                "cash_basis_revenue",
                "cash_basis_expense_total",
                "cash_basis_income",
                "cash_basis_expense_1",
                "cash_basis_expense_2",
            ]
        default:
            return []
        }
    }

    private static func expectedPackKeysByForm() -> [String: Set<String>] {
        [
            commonFormKey: builderGeneratedKeys(for: commonFormKey),
            "blue_general": builderGeneratedKeys(for: "blue_general").subtracting(allowedBuilderOnlyKeysByForm()["blue_general"] ?? []),
            "white_shushi": builderGeneratedKeys(for: "white_shushi"),
            "blue_cash_basis": ["cash_basis_revenue", "cash_basis_expense_total", "cash_basis_income"],
        ]
    }

    private static func allowedBuilderOnlyKeysByForm() -> [String: Set<String>] {
        [
            "blue_general": ["income_total_revenue", "inventory_cogs"],
            "blue_cash_basis": ["cash_basis_expense_1", "cash_basis_expense_2"],
        ]
    }

    private static func whiteRequiredRuleKeys() -> [String] {
        [
            "shushi_revenue_total",
            "shushi_inventory_subtotal",
            "shushi_inventory_cogs",
            "shushi_income_gross",
            "shushi_expense_other_subtotal",
            "shushi_expense_total",
            "shushi_income_before_employee_deduction",
            "shushi_income_net",
            "shushi_sales_detail_total",
            "shushi_purchase_detail_total",
            "shushi_depreciation_total_ordinary",
            "shushi_depreciation_total_special",
            "shushi_depreciation_total_amount",
            "shushi_depreciation_total_necessary_expense",
            "shushi_depreciation_total_remaining_balance",
        ]
    }

    private static func whitePage2CoverageKeys() -> [String] {
        [
            "shushi_sales_detail_total",
            "shushi_purchase_detail_total",
            "shushi_depreciation_total_necessary_expense",
            "shushi_rent_detail_1_necessary_expense",
        ]
    }

    private static func validateWhiteLeafOnlyMappings(_ fieldsByKey: [String: PackFilingField]) -> [String] {
        var violations: [String] = []
        if let field = fieldsByKey.values.first(where: { $0.xmlTag == "AIG00020" }) {
            violations.append("container xmlTag AIG00020 must not be assigned to direct field: \(field.internalKey)")
        }

        for field in fieldsByKey.values where field.xmlTag == "AIN00090" {
            if field.fieldLabel.contains("合計") || field.fieldLabel == "計" {
                violations.append("AIN00090 must remain leaf-only rent detail amount: \(field.internalKey)")
            }
        }
        return violations.sorted()
    }
}

// MARK: - Pack Filing Definition (Decode-only)

/// パック内 filing/*.json のデコード用構造体
private struct PackFilingDefinition: Decodable {
    let formType: String
    let taxYear: Int
    let formId: String
    let formVer: String
    let rootTag: String
    let displayName: String
    let filingDeadline: String
    let sections: [PackFilingSection]
}

private struct PackFilingSection: Decodable {
    let id: String
    let label: String
    let fields: [PackFilingField]
}

private struct PackFilingField: Decodable {
    let internalKey: String
    let fieldLabel: String
    let xmlTag: String?
    let dataType: String
    let taxLineRawValue: String?
    let format: String?
    let requiredRule: String?
    let idref: String?
}
