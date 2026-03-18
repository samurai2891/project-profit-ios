import Foundation

/// 青色申告決算書/収支内訳書の .xtx (XML) ファイルを生成するエクスポーター
@MainActor
enum EtaxXtxExporter {

    private struct MappedEtaxField {
        let field: EtaxField
        let definition: TaxFieldDefinition
        let xmlTag: String
    }

    private struct BalanceSheetAdditionalEntry {
        let slot: Int
        let name: MappedEtaxField?
        let closing: MappedEtaxField?
    }

    // MARK: - Public API

    /// e-Tax .xtx 形式のXMLデータを生成
    static func generateXtx(form: EtaxForm) -> Result<Data, EtaxExportError> {
        guard let definition = TaxYearDefinitionLoader.loadDefinition(for: form.fiscalYear) else {
            return .failure(.unsupportedTaxYear(year: form.fiscalYear))
        }

        let mappedResult = resolveMappedFields(form: form, definition: definition)
        let mappedFields: [MappedEtaxField]
        switch mappedResult {
        case .success(let fields):
            mappedFields = fields
        case .failure(let error):
            return .failure(error)
        }

        let errors = EtaxCharacterValidator.validateForm(
            EtaxForm(
                fiscalYear: form.fiscalYear,
                formType: form.formType,
                fields: validationFields(for: form.formType, mappedFields: mappedFields),
                generatedAt: form.generatedAt
            )
        )
        guard errors.isEmpty else {
            return .failure(errors[0])
        }

        do {
            let xml = try buildXml(form: form, definition: definition, fields: mappedFields)
            guard let data = xml.data(using: .utf8) else {
                return .failure(.xmlGenerationFailed(underlying: NSError(
                    domain: "EtaxXtxExporter",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "UTF-8エンコードに失敗"]
                )))
            }
            return .success(data)
        } catch {
            return .failure(.xmlGenerationFailed(underlying: error))
        }
    }

    /// CSVエクスポート（内部キー・タグ・値の検証用）
    static func generateCsv(form: EtaxForm) -> Result<Data, EtaxExportError> {
        guard let definition = TaxYearDefinitionLoader.loadDefinition(for: form.fiscalYear) else {
            return .failure(.unsupportedTaxYear(year: form.fiscalYear))
        }

        let mappedResult = resolveMappedFields(form: form, definition: definition)
        let mappedFields: [MappedEtaxField]
        switch mappedResult {
        case .success(let fields):
            mappedFields = fields
        case .failure(let error):
            return .failure(error)
        }

        let errors = EtaxCharacterValidator.validateForm(
            EtaxForm(
                fiscalYear: form.fiscalYear,
                formType: form.formType,
                fields: validationFields(for: form.formType, mappedFields: mappedFields),
                generatedAt: form.generatedAt
            )
        )
        guard errors.isEmpty else {
            return .failure(errors[0])
        }

        var lines: [String] = []
        lines.append("internalKey,xmlTag,form,セクション,フィールド名,値")

        for mapped in mappedFields {
            let section = csvQuote(mapped.field.section.rawValue)
            let key = csvQuote(mapped.field.id)
            let xmlTag = csvQuote(mapped.xmlTag)
            let formName = csvQuote(mapped.definition.form ?? form.formType.definitionFormKey)
            let label = csvQuote(EtaxCharacterValidator.sanitize(mapped.field.fieldLabel))
            let value = csvQuote(EtaxCharacterValidator.sanitize(mapped.field.value.exportText))
            lines.append("\(key),\(xmlTag),\(formName),\(section),\(label),\(value)")
        }

        let csv = lines.joined(separator: "\n")
        guard let data = csv.data(using: .utf8) else {
            return .failure(.xmlGenerationFailed(underlying: NSError(
                domain: "EtaxXtxExporter",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "CSVエンコードに失敗"]
            )))
        }
        return .success(data)
    }

    // MARK: - XML Builder

    private static func buildXml(
        form: EtaxForm,
        definition: TaxYearDefinition,
        fields: [MappedEtaxField]
    ) throws -> String {
        switch form.formType {
        case .blueReturn:
            return buildBlueReturnXml(form: form, definition: definition, fields: fields)
        case .blueCashBasis:
            return buildBlueCashBasisXml(form: form, definition: definition, fields: fields)
        case .whiteReturn:
            return buildWhiteReturnXml(form: form, definition: definition, fields: fields)
        }
    }

    private static func buildBlueReturnXml(
        form: EtaxForm,
        definition: TaxYearDefinition,
        fields: [MappedEtaxField]
    ) -> String {
        let formDef = definition.forms?["blue_general"]
        let rootTag = formDef?.rootTag ?? "KOA210"
        let vr = formDef?.formVer ?? "11.0"

        let formDate = ymd(form.generatedAt)
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<\(rootTag) xmlns=\"http://xml.e-tax.nta.go.jp/XSD/shotoku\" xmlns:gen=\"http://xml.e-tax.nta.go.jp/XSD/general\" VR=\"\(xmlEscape(vr))\" softNM=\"ProjectProfit\" sakuseiNM=\"Project Profit iOS\" sakuseiDay=\"\(formDate)\">")

        let mappedByPrefix = Dictionary(grouping: fields, by: { prefix(of: $0.xmlTag) })
        let amfFields = mappedByPrefix["AMF"] ?? []
        let amgFields = mappedByPrefix["AMG"] ?? []

        lines.append("  <KOA210-1>")
        lines.append("    <AMA00000 IDREF=\"NENBUN\"/>")
        appendDeclarantBlock(
            to: &lines,
            fields: fields,
            containerTag: "AMB00000",
            addressTag: "AMB00010",
            kanaContainerTag: "AMB00020",
            kanaTag: "AMB00030",
            nameTag: "AMB00040",
            businessLocationTag: "AMB00050",
            phoneContainerTag: "AMB00060",
            phoneTag: "AMB00070",
            businessCategoryTag: "AMB00090",
            businessNameTag: "AMB00100",
            indent: "    ",
            useReferenceElements: true,
            useStructuredPhone: true
        )
        if !amfFields.isEmpty {
            lines.append("    <AMF00000>")
            lines.append("      <AMF00010>")
            lines.append(contentsOf: blueProfitAndLossLines(for: amfFields, indent: "        "))
            lines.append("      </AMF00010>")
            lines.append("    </AMF00000>")
        }
        let handledTags = Set([
            "AMA00000",
            "AMB00010", "AMB00030", "AMB00040", "AMB00050", "AMB00070", "AMB00090", "AMB00100"
        ])
        let unknown = fields.filter { prefix(of: $0.xmlTag) != "AMG" && !handledTags.contains($0.xmlTag) && prefix(of: $0.xmlTag) != "AMF" }
        lines.append(contentsOf: xmlElementLines(for: unknown, indent: "    "))
        lines.append("  </KOA210-1>")
        lines.append("  <KOA210-2>")
        lines.append("  </KOA210-2>")
        lines.append("  <KOA210-3>")
        lines.append("  </KOA210-3>")

        if !amgFields.isEmpty {
            lines.append("  <KOA210-4>")
            lines.append(contentsOf: blueBalanceSheetLines(for: amgFields, indent: "    "))
            lines.append("  </KOA210-4>")
        }

        lines.append("</\(rootTag)>")
        return lines.joined(separator: "\n")
    }

    private static func buildBlueCashBasisXml(
        form: EtaxForm,
        definition: TaxYearDefinition,
        fields: [MappedEtaxField]
    ) -> String {
        let formDef = definition.forms?["blue_cash_basis"]
        let rootTag = formDef?.rootTag ?? "KOA230"
        let vr = formDef?.formVer ?? "10.0"

        let formDate = ymd(form.generatedAt)
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<\(rootTag) xmlns=\"http://xml.e-tax.nta.go.jp/XSD/shotoku\" xmlns:gen=\"http://xml.e-tax.nta.go.jp/XSD/general\" VR=\"\(xmlEscape(vr))\" softNM=\"ProjectProfit\" sakuseiNM=\"Project Profit iOS\" sakuseiDay=\"\(formDate)\">")
        lines.append("  <KOA230-1>")

        lines.append("    <AOA00000>\(xmlEscape(String(form.fiscalYear)))</AOA00000>")

        appendDeclarantBlock(
            to: &lines,
            fields: fields,
            containerTag: "AOB00000",
            addressTag: "AOB00010",
            kanaContainerTag: "AOB00020",
            kanaTag: "AOB00030",
            nameTag: "AOB00040",
            businessLocationTag: "AOB00050",
            phoneContainerTag: "AOB00060",
            phoneTag: "AOB00070",
            businessCategoryTag: "AOB00090",
            businessNameTag: "AOB00100",
            indent: "    "
        )

        lines.append("    <AOF00000>")

        let representativeExpense = fields.first(where: { isCashBasisDynamicExpense($0.field.id) })
        let otherExpenseTotal = fields
            .filter { isCashBasisDynamicExpense($0.field.id) && $0.field.id != representativeExpense?.field.id }
            .reduce(0) { $0 + ($1.field.value.numberValue ?? 0) }

        if let representativeExpense {
            lines.append("      <AOF00040>")
            lines.append("        <AOF00050>\(xmlEscape(cashBasisCategoryName(from: representativeExpense.field.fieldLabel)))</AOF00050>")
            lines.append("      </AOF00040>")
        }

        let revenueField = fields.first(where: { $0.field.id == "cash_basis_revenue" })
        if let revenueValue = revenueField?.field.value.numberValue {
            lines.append("      <AOF00070>")
            lines.append("        <AOF00110>\(xmlEscape(String(revenueValue)))</AOF00110>")
            lines.append("      </AOF00070>")
        }

        let expenseTotalField = fields.first(where: { $0.field.id == "cash_basis_expense_total" })
        if representativeExpense != nil || otherExpenseTotal > 0 || expenseTotalField != nil {
            lines.append("      <AOF00120>")
            if let representativeExpenseValue = representativeExpense?.field.value.numberValue {
                lines.append("        <AOF00180>\(xmlEscape(String(representativeExpenseValue)))</AOF00180>")
            }
            if otherExpenseTotal > 0 {
                lines.append("        <AOF00190>\(xmlEscape(String(otherExpenseTotal)))</AOF00190>")
            }
            if let expenseTotalValue = expenseTotalField?.field.value.numberValue {
                lines.append("        <AOF00200>\(xmlEscape(String(expenseTotalValue)))</AOF00200>")
            }
            lines.append("      </AOF00120>")
        }

        if let incomeValue = fields.first(where: { $0.field.id == "cash_basis_income" })?.field.value.numberValue {
            lines.append("      <AOF00290>\(xmlEscape(String(incomeValue)))</AOF00290>")
        }

        lines.append("    </AOF00000>")
        lines.append("  </KOA230-1>")
        lines.append("</\(rootTag)>")
        return lines.joined(separator: "\n")
    }

    private static func buildWhiteReturnXml(
        form: EtaxForm,
        definition: TaxYearDefinition,
        fields: [MappedEtaxField]
    ) -> String {
        let formDef = definition.forms?["white_shushi"]
        let rootTag = formDef?.rootTag ?? "KOA110"
        let vr = formDef?.formVer ?? "12.0"

        let formDate = ymd(form.generatedAt)
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<\(rootTag) xmlns=\"http://xml.e-tax.nta.go.jp/XSD/shotoku\" xmlns:gen=\"http://xml.e-tax.nta.go.jp/XSD/general\" VR=\"\(xmlEscape(vr))\" softNM=\"ProjectProfit\" sakuseiNM=\"Project Profit iOS\" sakuseiDay=\"\(formDate)\">")
        lines.append("  <KOA110-1>")

        let mappedByPrefix = Dictionary(grouping: fields, by: { prefix(of: $0.xmlTag) })

        lines.append("    <AIA00000>\(xmlEscape(String(form.fiscalYear)))</AIA00000>")

        appendDeclarantBlock(
            to: &lines,
            fields: fields,
            containerTag: "AIB00000",
            addressTag: "AIB00010",
            kanaContainerTag: "AIB00020",
            kanaTag: "AIB00030",
            nameTag: "AIB00040",
            businessLocationTag: "AIB00050",
            phoneContainerTag: "AIB00060",
            phoneTag: "AIB00070",
            businessCategoryTag: "AIB00090",
            businessNameTag: "AIB00100",
            indent: "    "
        )

        if let aigFields = mappedByPrefix["AIG"], !aigFields.isEmpty {
            lines.append("    <AIG00000>")
            lines.append(contentsOf: xmlElementLines(for: aigFields, indent: "      "))
            lines.append("    </AIG00000>")
        }

        if let ainFields = mappedByPrefix["AIN"], !ainFields.isEmpty {
            lines.append("    <AIN00000>")
            lines.append(contentsOf: xmlElementLines(for: ainFields, indent: "      "))
            lines.append("    </AIN00000>")
        }

        // 未知プレフィックスはKOA110-1直下に出力
        let handled = Set(["AIG", "AIN"])
        let handledTags = Set([
            "AIA00000",
            "AIB00010", "AIB00030", "AIB00040", "AIB00050", "AIB00070", "AIB00090", "AIB00100"
        ])
        let unknown = fields.filter { !handled.contains(prefix(of: $0.xmlTag)) && !handledTags.contains($0.xmlTag) }
        lines.append(contentsOf: xmlElementLines(for: unknown, indent: "    "))

        lines.append("  </KOA110-1>")
        lines.append("</\(rootTag)>")
        return lines.joined(separator: "\n")
    }

    private static func xmlElementLines(for fields: [MappedEtaxField], indent: String) -> [String] {
        fields
            .sorted { $0.xmlTag < $1.xmlTag }
            .map { mapped in
                let value = xmlEscape(EtaxCharacterValidator.sanitize(mapped.field.value.exportText))
                return "\(indent)<\(mapped.xmlTag)>\(value)</\(mapped.xmlTag)>"
            }
    }

    private static func appendDeclarantBlock(
        to lines: inout [String],
        fields: [MappedEtaxField],
        containerTag: String,
        addressTag: String,
        kanaContainerTag: String,
        kanaTag: String,
        nameTag: String,
        businessLocationTag: String,
        phoneContainerTag: String,
        phoneTag: String,
        businessCategoryTag: String,
        businessNameTag: String,
        indent: String,
        useReferenceElements: Bool = false,
        useStructuredPhone: Bool = false
    ) {
        let addressField = fields.first(where: { $0.xmlTag == addressTag })
        let kanaField = fields.first(where: { $0.xmlTag == kanaTag })
        let nameField = fields.first(where: { $0.xmlTag == nameTag })
        let businessLocationField = fields.first(where: { $0.xmlTag == businessLocationTag })
        let phoneField = fields.first(where: { $0.xmlTag == phoneTag })
        let businessCategoryField = fields.first(where: { $0.xmlTag == businessCategoryTag })
        let businessNameField = fields.first(where: { $0.xmlTag == businessNameTag })

        guard addressField != nil || kanaField != nil || nameField != nil || businessLocationField != nil
                || phoneField != nil || businessCategoryField != nil || businessNameField != nil
        else {
            return
        }

        lines.append("\(indent)<\(containerTag)>")

        if let addressField {
            lines.append(xmlElementLine(for: addressField, indent: "\(indent)  "))
        }

        if kanaField != nil || nameField != nil {
            lines.append("\(indent)  <\(kanaContainerTag)>")
            if let kanaField {
                let line = useReferenceElements
                    ? xmlReferenceElementLine(for: kanaField, indent: "\(indent)    ")
                    : xmlElementLine(for: kanaField, indent: "\(indent)    ")
                lines.append(line)
            }
            if let nameField {
                let line = useReferenceElements
                    ? xmlReferenceElementLine(for: nameField, indent: "\(indent)    ")
                    : xmlElementLine(for: nameField, indent: "\(indent)    ")
                lines.append(line)
            }
            lines.append("\(indent)  </\(kanaContainerTag)>")
        }

        if let businessLocationField {
            lines.append(xmlElementLine(for: businessLocationField, indent: "\(indent)  "))
        }

        if let phoneField {
            lines.append("\(indent)  <\(phoneContainerTag)>")
            if useStructuredPhone {
                lines.append("\(indent)    <\(phoneTag)>")
                lines.append(contentsOf: xmlPhoneElementLines(for: phoneField, indent: "\(indent)      "))
                lines.append("\(indent)    </\(phoneTag)>")
            } else {
                lines.append(xmlElementLine(for: phoneField, indent: "\(indent)    "))
            }
            lines.append("\(indent)  </\(phoneContainerTag)>")
        }

        if let businessCategoryField {
            let line = useReferenceElements
                ? xmlReferenceElementLine(for: businessCategoryField, indent: "\(indent)  ")
                : xmlElementLine(for: businessCategoryField, indent: "\(indent)  ")
            lines.append(line)
        }

        if let businessNameField {
            let line = useReferenceElements
                ? xmlReferenceElementLine(for: businessNameField, indent: "\(indent)  ")
                : xmlElementLine(for: businessNameField, indent: "\(indent)  ")
            lines.append(line)
        }

        lines.append("\(indent)</\(containerTag)>")
    }

    private static func xmlElementLine(for mapped: MappedEtaxField, indent: String) -> String {
        let value = xmlEscape(EtaxCharacterValidator.sanitize(mapped.field.value.exportText))
        return "\(indent)<\(mapped.xmlTag)>\(value)</\(mapped.xmlTag)>"
    }

    private static func blueProfitAndLossLines(for fields: [MappedEtaxField], indent: String) -> [String] {
        let inventoryTags = Set(["AMF00120", "AMF00130", "AMF00140", "AMF00150", "AMF00160"])
        let inventoryFields = fields.filter { inventoryTags.contains($0.xmlTag) }
        let amountFields = fields.filter { !inventoryTags.contains($0.xmlTag) }

        var lines: [String] = []
        if !amountFields.isEmpty || !inventoryFields.isEmpty {
            lines.append("\(indent)<AMF00090>")
            lines.append(contentsOf: xmlElementLines(for: amountFields, indent: "\(indent)  "))
            if !inventoryFields.isEmpty {
                lines.append("\(indent)  <AMF00110>")
                lines.append(contentsOf: xmlElementLines(for: inventoryFields, indent: "\(indent)    "))
                lines.append("\(indent)  </AMF00110>")
            }
            lines.append("\(indent)</AMF00090>")
        }
        return lines
    }

    private static func blueBalanceSheetLines(for fields: [MappedEtaxField], indent: String) -> [String] {
        let assetClosingTags = Set([
            "AMG00260", "AMG00270", "AMG00280", "AMG00290", "AMG00300", "AMG00310",
            "AMG00320", "AMG00330", "AMG00340", "AMG00350", "AMG00360", "AMG00370",
            "AMG00380", "AMG00390", "AMG00400", "AMG00410", "AMG00430", "AMG00440"
        ])
        let liabilityEquityClosingTags = Set([
            "AMG00640", "AMG00650", "AMG00660", "AMG00670", "AMG00680", "AMG00690",
            "AMG00710", "AMG00720", "AMG00730", "AMG00740", "AMG00750", "AMG00760"
        ])
        let assetClosingFields = fields.filter { assetClosingTags.contains($0.xmlTag) }
        let liabilityEquityClosingFields = fields.filter { liabilityEquityClosingTags.contains($0.xmlTag) }
        let assetAdditionalEntries = balanceSheetAdditionalEntries(
            from: fields,
            prefix: "bs_asset_additional_",
            nameTag: "AMG00030",
            closingTag: "AMG00420"
        )
        let liabilityAdditionalEntries = balanceSheetAdditionalEntries(
            from: fields,
            prefix: "bs_liability_additional_",
            nameTag: "AMG00470",
            closingTag: "AMG00700"
        )
        let equityAdditionalEntries = balanceSheetAdditionalEntries(
            from: fields,
            prefix: "bs_equity_additional_",
            nameTag: "AMG00480",
            closingTag: "AMG00720"
        )

        var lines: [String] = []
        lines.append("\(indent)<AMG00000>")
        if !assetClosingFields.isEmpty || !assetAdditionalEntries.isEmpty {
            lines.append("\(indent)  <AMG00020>")
            for entry in assetAdditionalEntries {
                lines.append("\(indent)    <AMG00025>")
                if let nameField = entry.name {
                    lines.append(xmlElementLine(for: nameField, indent: "\(indent)      "))
                }
                if let closingField = entry.closing {
                    lines.append(xmlElementLine(for: closingField, indent: "\(indent)      "))
                }
                lines.append("\(indent)    </AMG00025>")
            }
            if !assetClosingFields.isEmpty {
                lines.append("\(indent)    <AMG00240>")
                lines.append(contentsOf: xmlElementLines(for: assetClosingFields, indent: "\(indent)      "))
                lines.append("\(indent)    </AMG00240>")
            }
            lines.append("\(indent)  </AMG00020>")
        }
        if !liabilityEquityClosingFields.isEmpty || !liabilityAdditionalEntries.isEmpty || !equityAdditionalEntries.isEmpty {
            lines.append("\(indent)  <AMG00450>")
            if !liabilityAdditionalEntries.isEmpty || !equityAdditionalEntries.isEmpty {
                lines.append("\(indent)    <AMG00460>")
                for entry in liabilityAdditionalEntries {
                    lines.append("\(indent)      <AMG00465>")
                    if let nameField = entry.name {
                        lines.append(xmlElementLine(for: nameField, indent: "\(indent)        "))
                    }
                    if let closingField = entry.closing {
                        lines.append(xmlElementLine(for: closingField, indent: "\(indent)        "))
                    }
                    lines.append("\(indent)      </AMG00465>")
                }
                for entry in equityAdditionalEntries {
                    lines.append("\(indent)      <AMG00475>")
                    if let nameField = entry.name {
                        lines.append(xmlElementLine(for: nameField, indent: "\(indent)        "))
                    }
                    if let closingField = entry.closing {
                        lines.append(xmlElementLine(for: closingField, indent: "\(indent)        "))
                    }
                    lines.append("\(indent)      </AMG00475>")
                }
                lines.append("\(indent)    </AMG00460>")
            }
            if !liabilityEquityClosingFields.isEmpty {
                lines.append("\(indent)    <AMG00620>")
                lines.append(contentsOf: xmlElementLines(for: liabilityEquityClosingFields, indent: "\(indent)      "))
                lines.append("\(indent)    </AMG00620>")
            }
            lines.append("\(indent)  </AMG00450>")
        }
        lines.append("\(indent)</AMG00000>")
        return lines
    }

    private static func balanceSheetAdditionalEntries(
        from fields: [MappedEtaxField],
        prefix: String,
        nameTag: String,
        closingTag: String
    ) -> [BalanceSheetAdditionalEntry] {
        let relevant = fields.filter { $0.field.id.hasPrefix(prefix) }
        let grouped = Dictionary(grouping: relevant) { field in
            let suffix = field.field.id.replacingOccurrences(of: prefix, with: "")
            let slotString = suffix.split(separator: "_").first.flatMap { Int(String($0)) } ?? 0
            return slotString
        }

        return grouped.keys.sorted().compactMap { slot in
            let slotFields = grouped[slot] ?? []
            let nameField = slotFields.first { $0.xmlTag == nameTag }
            let closingField = slotFields.first { $0.xmlTag == closingTag }
            guard nameField != nil || closingField != nil else {
                return nil
            }
            return BalanceSheetAdditionalEntry(slot: slot, name: nameField, closing: closingField)
        }
    }

    private static func xmlReferenceElementLine(for mapped: MappedEtaxField, indent: String) -> String {
        let idref = xmlReferenceID(for: mapped.xmlTag) ?? mapped.field.value.exportText
        return "\(indent)<\(mapped.xmlTag) IDREF=\"\(xmlEscape(idref))\"/>"
    }

    private static func xmlPhoneElementLines(for mapped: MappedEtaxField, indent: String) -> [String] {
        let digits = mapped.field.value.exportText.filter(\.isNumber)
        guard !digits.isEmpty else {
            return []
        }

        let parts = splitPhoneNumber(digits)
        var lines: [String] = []
        if let tel1 = parts.tel1 {
            lines.append("\(indent)<gen:tel1>\(xmlEscape(tel1))</gen:tel1>")
        }
        if let tel2 = parts.tel2 {
            lines.append("\(indent)<gen:tel2>\(xmlEscape(tel2))</gen:tel2>")
        }
        lines.append("\(indent)<gen:tel3>\(xmlEscape(parts.tel3))</gen:tel3>")
        return lines
    }

    private static func resolveMappedFields(
        form: EtaxForm,
        definition: TaxYearDefinition
    ) -> Result<[MappedEtaxField], EtaxExportError> {
        guard !form.fields.isEmpty else {
            return .failure(.noData)
        }

        let definitions = TaxYearDefinitionLoader.fieldDefinitions(for: form.formType, fiscalYear: form.fiscalYear)
        guard !definitions.isEmpty else {
            return .failure(.unsupportedTaxYear(year: form.fiscalYear))
        }

        var mapped: [MappedEtaxField] = []
        for field in form.fields {
            if shouldSkipDirectCompositeField(field.id, formType: form.formType) {
                continue
            }
            if form.formType == .blueCashBasis, isCashBasisDynamicExpense(field.id) {
                let syntheticTag = cashBasisDynamicExpenseXmlTag(for: field.id)
                let definitionField = TaxFieldDefinition(
                    internalKey: field.id,
                    fieldLabel: field.fieldLabel,
                    xmlTag: syntheticTag,
                    taxLineRawValue: nil,
                    section: field.section.rawValue,
                    dataType: .number,
                    form: form.formType.definitionFormKey,
                    idref: nil,
                    format: nil,
                    requiredRule: nil
                )
                mapped.append(MappedEtaxField(field: field, definition: definitionField, xmlTag: syntheticTag))
                continue
            }

            let definitionField = matchingDefinition(
                for: field.id,
                formKey: form.formType.definitionFormKey,
                definitions: definitions
            ) ?? syntheticDeclarantDefinition(
                for: field.id,
                formType: form.formType
            )
            guard let definitionField else {
                return .failure(.validationFailed(reasons: ["未定義internalKey: \(field.id)"]))
            }
            guard let xmlTag = definitionField.xmlTag?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !xmlTag.isEmpty
            else {
                return .failure(.missingXmlTag(internalKey: field.id))
            }
            mapped.append(MappedEtaxField(field: field, definition: definitionField, xmlTag: xmlTag))
        }

        guard !mapped.isEmpty else {
            return .failure(.noData)
        }

        return .success(mapped)
    }

    private static func matchingDefinition(
        for internalKey: String,
        formKey: String,
        definitions: [TaxFieldDefinition]
    ) -> TaxFieldDefinition? {
        if internalKey.hasPrefix("declarant_") {
            return nil
        }
        return definitions.first {
            $0.internalKey == internalKey && ($0.form == nil || $0.form == formKey)
        }
    }

    private static func syntheticDeclarantDefinition(
        for internalKey: String,
        formType: EtaxFormType
    ) -> TaxFieldDefinition? {
        let xmlTagByInternalKey: [String: String]
        switch formType {
        case .blueReturn:
            xmlTagByInternalKey = [
                "declarant_address": "AMB00010",
                "declarant_name_kana": "AMB00030",
                "declarant_name": "AMB00040",
                "declarant_postal_code": "AMB00050",
                "declarant_phone": "AMB00070",
                "declarant_business_category": "AMB00090",
                "declarant_business_name": "AMB00100"
            ]
        case .whiteReturn:
            xmlTagByInternalKey = [
                "declarant_address": "AIB00010",
                "declarant_name_kana": "AIB00030",
                "declarant_name": "AIB00040",
                "declarant_postal_code": "AIB00050",
                "declarant_phone": "AIB00070",
                "declarant_business_category": "AIB00090",
                "declarant_business_name": "AIB00100"
            ]
        case .blueCashBasis:
            xmlTagByInternalKey = [
                "declarant_address": "AOB00010",
                "declarant_name_kana": "AOB00030",
                "declarant_name": "AOB00040",
                "declarant_postal_code": "AOB00050",
                "declarant_phone": "AOB00070",
                "declarant_business_category": "AOB00090",
                "declarant_business_name": "AOB00100"
            ]
        }

        guard let xmlTag = xmlTagByInternalKey[internalKey] else {
            return nil
        }

        return TaxFieldDefinition(
            internalKey: internalKey,
            fieldLabel: internalKey,
            xmlTag: xmlTag,
            taxLineRawValue: nil,
            section: EtaxSection.declarantInfo.rawValue,
            dataType: .text,
            form: formType.definitionFormKey,
            idref: nil,
            format: nil,
            requiredRule: nil
        )
    }

    // MARK: - Utilities

    private static func prefix(of xmlTag: String) -> String {
        String(xmlTag.prefix(3)).uppercased()
    }

    private static func validationFields(
        for formType: EtaxFormType,
        mappedFields: [MappedEtaxField]
    ) -> [EtaxField] {
        mappedFields.map(\.field).filter { field in
            if field.section == .declarantInfo {
                return false
            }
            if formType == .blueCashBasis, isCashBasisDynamicExpense(field.id) {
                return false
            }
            return true
        }
    }

    private static func shouldSkipDirectCompositeField(_ internalKey: String, formType: EtaxFormType) -> Bool {
        guard formType == .blueReturn else {
            return false
        }
        return internalKey == "income_total_revenue" || internalKey == "inventory_cogs"
    }

    private static func isCashBasisDynamicExpense(_ internalKey: String) -> Bool {
        internalKey.hasPrefix("cash_basis_expense_") && internalKey != "cash_basis_expense_total"
    }

    private static func cashBasisDynamicExpenseXmlTag(for internalKey: String) -> String {
        internalKey == "cash_basis_expense_1" ? "AOF00180" : "AOF00190"
    }

    private static func cashBasisCategoryName(from fieldLabel: String) -> String {
        let parts = fieldLabel.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        if parts.count == 2 {
            return String(parts[1])
        }
        return fieldLabel
    }

    private static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func csvQuote(_ field: String) -> String {
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func ymd(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func xmlReferenceID(for xmlTag: String) -> String? {
        let ids: [String: String] = [
            "AMA00000": "NENBUN",
            "AMB00030": "NOZEISHA_NM_KN",
            "AMB00040": "NOZEISHA_NM",
            "AMB00090": "SHOKUGYO",
            "AMB00100": "NOZEISHA_YAGO"
        ]
        return ids[xmlTag]
    }

    private static func splitPhoneNumber(_ digits: String) -> (tel1: String?, tel2: String?, tel3: String) {
        let suffixLength = min(4, digits.count)
        let tel3 = String(digits.suffix(suffixLength))
        let prefix = String(digits.dropLast(suffixLength))

        guard !prefix.isEmpty else {
            return (nil, nil, tel3)
        }

        let tel1Length: Int
        if digits.count == 10, digits.hasPrefix("03") || digits.hasPrefix("06") {
            tel1Length = 2
        } else if digits.count >= 11 && (digits.hasPrefix("050") || digits.hasPrefix("070") || digits.hasPrefix("080") || digits.hasPrefix("090")) {
            tel1Length = 3
        } else {
            switch digits.count {
            case ...9:
                tel1Length = min(2, prefix.count)
            case 10:
                tel1Length = min(3, prefix.count)
            default:
                tel1Length = min(4, prefix.count)
            }
        }

        let tel1 = String(prefix.prefix(tel1Length))
        let tel2Digits = String(prefix.dropFirst(tel1Length))
        let tel2 = tel2Digits.isEmpty ? nil : tel2Digits
        return (tel1.isEmpty ? nil : tel1, tel2, tel3)
    }
}
