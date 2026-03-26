import Foundation
import Security

/// P&L / B/S レポートデータを e-Tax フィールドにマッピングする
@MainActor
enum EtaxFieldPopulator {

    private enum BalanceSheetCategory {
        case asset
        case liability
        case equity
    }

    private struct BalanceSheetAdditionalSlot {
        let nameKey: String
        let closingKey: String
    }

    /// P&Lレポートからe-Taxフォームを生成（canonical profile ベース）
    static func populate(
        fiscalYear: Int,
        profitLoss: ProfitLossReport,
        balanceSheet: BalanceSheetReport?,
        formType: EtaxFormType = .blueReturn,
        accounts: [PPAccount],
        businessProfile: BusinessProfile? = nil,
        taxYearProfile: TaxYearProfile? = nil,
        sensitivePayload: ProfileSensitivePayload? = nil,
        inventoryRecord: PPInventoryRecord? = nil
    ) -> EtaxForm {
        var fields: [EtaxField] = []

        // 収入セクション — 同じTaxLineの項目は合算
        var revenueByTaxLine: [TaxLine: Int] = [:]
        for item in profitLoss.revenueItems {
            if let taxLine = taxLineForAccountId(item.id, accounts: accounts) {
                revenueByTaxLine[taxLine, default: 0] += item.amount
            }
        }
        for (taxLine, amount) in revenueByTaxLine.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            fields.append(EtaxField(
                id: "revenue_\(taxLine.rawValue)",
                fieldLabel: TaxYearDefinitionLoader.fieldLabel(
                    for: taxLine,
                    formType: .blueReturn,
                    fiscalYear: fiscalYear
                ),
                taxLine: taxLine,
                value: amount,
                section: .revenue
            ))
        }

        // 経費セクション — 同じTaxLineの項目は合算
        var expenseByTaxLine: [TaxLine: Int] = [:]
        for item in profitLoss.expenseItems {
            if let taxLine = taxLineForAccountId(item.id, accounts: accounts) {
                expenseByTaxLine[taxLine, default: 0] += item.amount
            }
        }
        for (taxLine, amount) in expenseByTaxLine.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            fields.append(EtaxField(
                id: "expense_\(taxLine.rawValue)",
                fieldLabel: TaxYearDefinitionLoader.fieldLabel(
                    for: taxLine,
                    formType: .blueReturn,
                    fiscalYear: fiscalYear
                ),
                taxLine: taxLine,
                value: amount,
                section: .expenses
            ))
        }

        // 所得金額セクション
        fields.append(EtaxField(
            id: "income_total_revenue",
            fieldLabel: "収入金額合計",
            taxLine: nil,
            value: profitLoss.totalRevenue,
            section: .income
        ))
        fields.append(EtaxField(
            id: "income_total_expenses",
            fieldLabel: "必要経費合計",
            taxLine: nil,
            value: profitLoss.totalExpenses,
            section: .income
        ))
        fields.append(EtaxField(
            id: "income_net",
            fieldLabel: "所得金額",
            taxLine: nil,
            value: profitLoss.netIncome,
            section: .income
        ))

        // 申告者情報セクション
        if let businessProfile {
            fields.append(contentsOf: populateDeclarantInfo(
                businessProfile: businessProfile,
                sensitivePayload: sensitivePayload
            ))
        }

        // 棚卸セクション
        if let inventoryRecord {
            fields.append(contentsOf: populateInventory(record: inventoryRecord))
        }

        // 貸借対照表セクション
        if let balanceSheet {
            fields.append(contentsOf: populateBalanceSheet(balanceSheet: balanceSheet))
        }

        return EtaxForm(
            fiscalYear: fiscalYear,
            formType: formType,
            fields: fields,
            generatedAt: Date()
        )
    }

    static func populate(
        fiscalYear: Int,
        canonicalProfitLoss: CanonicalProfitLossReport,
        canonicalBalanceSheet: CanonicalBalanceSheetReport?,
        formType: EtaxFormType = .blueReturn,
        canonicalAccounts: [CanonicalAccount],
        businessProfile: BusinessProfile? = nil,
        taxYearProfile: TaxYearProfile? = nil,
        sensitivePayload: ProfileSensitivePayload? = nil,
        inventoryRecord: PPInventoryRecord? = nil
    ) -> EtaxForm {
        var fields: [EtaxField] = []
        let canonicalAccountsById = Dictionary(uniqueKeysWithValues: canonicalAccounts.map { ($0.id, $0) })

        var revenueByTaxLine: [TaxLine: Int] = [:]
        for item in canonicalProfitLoss.revenueItems {
            if let taxLine = taxLineForCanonicalAccountId(item.id, canonicalAccountsById: canonicalAccountsById) {
                revenueByTaxLine[taxLine, default: 0] += decimalInt(item.amount)
            }
        }
        for (taxLine, amount) in revenueByTaxLine.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            fields.append(EtaxField(
                id: "revenue_\(taxLine.rawValue)",
                fieldLabel: TaxYearDefinitionLoader.fieldLabel(
                    for: taxLine,
                    formType: .blueReturn,
                    fiscalYear: fiscalYear
                ),
                taxLine: taxLine,
                value: amount,
                section: .revenue
            ))
        }

        var expenseByTaxLine: [TaxLine: Int] = [:]
        for item in canonicalProfitLoss.expenseItems {
            if let taxLine = taxLineForCanonicalAccountId(item.id, canonicalAccountsById: canonicalAccountsById) {
                expenseByTaxLine[taxLine, default: 0] += decimalInt(item.amount)
            }
        }
        for (taxLine, amount) in expenseByTaxLine.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            fields.append(EtaxField(
                id: "expense_\(taxLine.rawValue)",
                fieldLabel: TaxYearDefinitionLoader.fieldLabel(
                    for: taxLine,
                    formType: .blueReturn,
                    fiscalYear: fiscalYear
                ),
                taxLine: taxLine,
                value: amount,
                section: .expenses
            ))
        }

        fields.append(EtaxField(
            id: "income_total_revenue",
            fieldLabel: "収入金額合計",
            taxLine: nil,
            value: decimalInt(canonicalProfitLoss.totalRevenue),
            section: .income
        ))
        fields.append(EtaxField(
            id: "income_total_expenses",
            fieldLabel: "必要経費合計",
            taxLine: nil,
            value: decimalInt(canonicalProfitLoss.totalExpenses),
            section: .income
        ))
        fields.append(EtaxField(
            id: "income_net",
            fieldLabel: "所得金額",
            taxLine: nil,
            value: decimalInt(canonicalProfitLoss.netIncome),
            section: .income
        ))

        if let businessProfile {
            fields.append(contentsOf: populateDeclarantInfo(
                businessProfile: businessProfile,
                sensitivePayload: sensitivePayload
            ))
        }

        if let inventoryRecord {
            fields.append(contentsOf: populateInventory(record: inventoryRecord))
        }

        if let canonicalBalanceSheet {
            fields.append(contentsOf: populateBalanceSheet(balanceSheet: canonicalBalanceSheet))
        }

        return EtaxForm(
            fiscalYear: fiscalYear,
            formType: formType,
            fields: fields,
            generatedAt: Date()
        )
    }

    // MARK: - Declarant Info (Canonical)

    /// 申告者情報セクションのフィールドを生成（canonical BusinessProfile ベース）
    static func populateDeclarantInfo(
        businessProfile: BusinessProfile,
        sensitivePayload: ProfileSensitivePayload? = nil
    ) -> [EtaxField] {
        let includeSensitive = sensitivePayload?.includeSensitiveInExport ?? false

        let ownerNameKana = sensitivePayload?.ownerNameKana ?? nonEmpty(businessProfile.ownerNameKana)
        let postalCode = sensitivePayload?.postalCode ?? nonEmpty(businessProfile.postalCode)
        let address = sensitivePayload?.address ?? nonEmpty(businessProfile.businessAddress)
        let phoneNumber = sensitivePayload?.phoneNumber ?? nonEmpty(businessProfile.phoneNumber)
        let businessCategory = sensitivePayload?.businessCategory

        var fields: [EtaxField] = []

        if !businessProfile.ownerName.isEmpty {
            fields.append(EtaxField(
                id: "declarant_name", fieldLabel: "氏名",
                taxLine: nil, value: businessProfile.ownerName, section: .declarantInfo
            ))
        }
        if includeSensitive, let kana = ownerNameKana, !kana.isEmpty {
            fields.append(EtaxField(
                id: "declarant_name_kana", fieldLabel: "氏名カナ",
                taxLine: nil, value: kana, section: .declarantInfo
            ))
        }
        if includeSensitive, let postalCode, !postalCode.isEmpty {
            fields.append(EtaxField(
                id: "declarant_postal_code", fieldLabel: "郵便番号",
                taxLine: nil, value: postalCode, section: .declarantInfo
            ))
        }
        if includeSensitive, let address, !address.isEmpty {
            fields.append(EtaxField(
                id: "declarant_address", fieldLabel: "住所",
                taxLine: nil, value: address, section: .declarantInfo
            ))
        }
        if includeSensitive, let phone = phoneNumber, !phone.isEmpty {
            fields.append(EtaxField(
                id: "declarant_phone", fieldLabel: "電話番号",
                taxLine: nil, value: phone, section: .declarantInfo
            ))
        }
        if !businessProfile.businessName.isEmpty {
            fields.append(EtaxField(
                id: "declarant_business_name", fieldLabel: "屋号",
                taxLine: nil, value: businessProfile.businessName, section: .declarantInfo
            ))
        }
        if includeSensitive, let category = businessCategory, !category.isEmpty {
            fields.append(EtaxField(
                id: "declarant_business_category", fieldLabel: "事業種類",
                taxLine: nil, value: category, section: .declarantInfo
            ))
        }

        return fields
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    // MARK: - Inventory

    /// 棚卸・COGS セクションのフィールドを生成
    static func populateInventory(record: PPInventoryRecord) -> [EtaxField] {
        [
            EtaxField(
                id: "inventory_opening", fieldLabel: "期首商品棚卸高",
                taxLine: nil, value: record.openingInventory, section: .inventory
            ),
            EtaxField(
                id: "inventory_purchases", fieldLabel: "仕入高",
                taxLine: nil, value: record.purchases, section: .inventory
            ),
            EtaxField(
                id: "inventory_closing", fieldLabel: "期末商品棚卸高",
                taxLine: nil, value: record.closingInventory, section: .inventory
            ),
            EtaxField(
                id: "inventory_cogs", fieldLabel: "売上原価",
                taxLine: nil, value: record.costOfGoodsSold, section: .inventory
            ),
        ]
    }

    // MARK: - Balance Sheet

    /// 貸借対照表セクションのフィールドを生成
    static func populateBalanceSheet(balanceSheet: BalanceSheetReport) -> [EtaxField] {
        var fields: [EtaxField] = []

        fields.append(contentsOf: mappedBalanceSheetFields(
            items: balanceSheet.assetItems.map { ($0.name, $0.balance) },
            category: .asset
        ))
        fields.append(EtaxField(
            id: "bs_total_assets", fieldLabel: "資産合計",
            taxLine: nil, value: balanceSheet.totalAssets, section: .balanceSheet
        ))

        fields.append(contentsOf: mappedBalanceSheetFields(
            items: balanceSheet.liabilityItems.map { ($0.name, $0.balance) },
            category: .liability
        ))

        fields.append(contentsOf: mappedBalanceSheetFields(
            items: balanceSheet.equityItems.map { ($0.name, $0.balance) },
            category: .equity
        ))
        fields.append(EtaxField(
            id: "bs_total_liabilities_and_equity", fieldLabel: "負債資本合計",
            taxLine: nil, value: balanceSheet.liabilitiesAndEquity, section: .balanceSheet
        ))

        return fields
    }

    static func populateBalanceSheet(balanceSheet: CanonicalBalanceSheetReport) -> [EtaxField] {
        var fields: [EtaxField] = []

        fields.append(contentsOf: mappedBalanceSheetFields(
            items: balanceSheet.assetItems.map { ($0.name, decimalInt($0.balance)) },
            category: .asset
        ))
        fields.append(EtaxField(
            id: "bs_total_assets",
            fieldLabel: "資産合計",
            taxLine: nil,
            value: decimalInt(balanceSheet.totalAssets),
            section: .balanceSheet
        ))

        fields.append(contentsOf: mappedBalanceSheetFields(
            items: balanceSheet.liabilityItems.map { ($0.name, decimalInt($0.balance)) },
            category: .liability
        ))

        fields.append(contentsOf: mappedBalanceSheetFields(
            items: balanceSheet.equityItems.map { ($0.name, decimalInt($0.balance)) },
            category: .equity
        ))
        fields.append(EtaxField(
            id: "bs_total_liabilities_and_equity",
            fieldLabel: "負債資本合計",
            taxLine: nil,
            value: decimalInt(balanceSheet.liabilitiesAndEquity),
            section: .balanceSheet
        ))

        return fields
    }

    private static func mappedBalanceSheetFields(
        items: [(name: String, balance: Int)],
        category: BalanceSheetCategory
    ) -> [EtaxField] {
        let fixedKeys = fixedBalanceSheetKeys(for: category)
        let additionalSlots = additionalBalanceSheetSlots(for: category)

        var fixedAmounts: [String: Int] = [:]
        var additionalEntries: [(name: String, balance: Int)] = []

        for item in items {
            let normalizedName = normalizedBalanceSheetName(item.name)
            if let key = fixedKeys[normalizedName] {
                fixedAmounts[key, default: 0] += item.balance
            } else if additionalEntries.count < additionalSlots.count {
                additionalEntries.append(item)
            }
        }

        var fields: [EtaxField] = fixedAmounts
            .sorted(by: { $0.key < $1.key })
            .map { key, amount in
                EtaxField(
                    id: key,
                    fieldLabel: key,
                    taxLine: nil,
                    value: amount,
                    section: .balanceSheet
                )
            }

        for (index, entry) in additionalEntries.enumerated() {
            let slot = additionalSlots[index]
            fields.append(EtaxField(
                id: slot.nameKey,
                fieldLabel: entry.name,
                taxLine: nil,
                value: entry.name,
                section: .balanceSheet
            ))
            fields.append(EtaxField(
                id: slot.closingKey,
                fieldLabel: entry.name,
                taxLine: nil,
                value: entry.balance,
                section: .balanceSheet
            ))
        }

        return fields
    }

    private static func fixedBalanceSheetKeys(for category: BalanceSheetCategory) -> [String: String] {
        switch category {
        case .asset:
            return [
                "現金": "bs_asset_cash",
                "当座預金": "bs_asset_checking_deposit",
                "定期預金": "bs_asset_time_deposit",
                "その他の預金": "bs_asset_other_deposit",
                "その他預金": "bs_asset_other_deposit",
                "受取手形": "bs_asset_notes_receivable",
                "売掛金": "bs_asset_accounts_receivable",
                "有価証券": "bs_asset_securities",
                "棚卸資産": "bs_asset_inventory",
                "前払金": "bs_asset_prepayments",
                "貸付金": "bs_asset_loans_receivable",
                "建物": "bs_asset_buildings",
                "建物附属設備": "bs_asset_building_attachments",
                "機械装置": "bs_asset_machinery",
                "車両運搬具": "bs_asset_vehicles",
                "工具器具備品": "bs_asset_tools_fixtures_equipment",
                "土地": "bs_asset_land",
                "事業主貸": "bs_asset_owner_draw"
            ]
        case .liability:
            return [
                "支払手形": "bs_liability_notes_payable",
                "買掛金": "bs_liability_accounts_payable",
                "借入金": "bs_liability_loans_payable",
                "未払金": "bs_liability_unpaid_amount",
                "前受金": "bs_liability_advance_receipts",
                "預り金": "bs_liability_deposits_received",
                "貸倒引当金": "bs_liability_allowance_bad_debts"
            ]
        case .equity:
            return [
                "事業主借": "bs_equity_owner_borrowings",
                "元入金": "bs_equity_owner_capital",
                "青色申告特別控除前の所得金額": "bs_equity_income_before_blue_deduction",
                "青色申告特別控除前所得金額": "bs_equity_income_before_blue_deduction"
            ]
        }
    }

    private static func additionalBalanceSheetSlots(for category: BalanceSheetCategory) -> [BalanceSheetAdditionalSlot] {
        switch category {
        case .asset:
            return (1...7).map {
                BalanceSheetAdditionalSlot(
                    nameKey: "bs_asset_additional_\($0)_name",
                    closingKey: "bs_asset_additional_\($0)_closing"
                )
            }
        case .liability:
            return (1...7).map {
                BalanceSheetAdditionalSlot(
                    nameKey: "bs_liability_additional_\($0)_name",
                    closingKey: "bs_liability_additional_\($0)_closing"
                )
            }
        case .equity:
            return (1...7).map {
                BalanceSheetAdditionalSlot(
                    nameKey: "bs_equity_additional_\($0)_name",
                    closingKey: "bs_equity_additional_\($0)_closing"
                )
            }
        }
    }

    private static func normalizedBalanceSheetName(_ name: String) -> String {
        name
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "・", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private static func taxLineForAccountId(_ accountId: String, accounts: [PPAccount]) -> TaxLine? {
        guard let account = accounts.first(where: { $0.id == accountId }),
              let subtype = account.subtype
        else { return nil }

        return TaxLine.allCases.first { $0.accountSubtype == subtype }
    }

    private static func taxLineForCanonicalAccountId(
        _ accountId: UUID,
        canonicalAccountsById: [UUID: CanonicalAccount]
    ) -> TaxLine? {
        guard let canonicalAccount = canonicalAccountsById[accountId] else {
            return nil
        }
        return TaxLine(legalReportLineId: canonicalAccount.defaultLegalReportLineId)
    }

    private static func decimalInt(_ value: Decimal) -> Int {
        NSDecimalNumber(decimal: value).intValue
    }

    private static func birthDateEtaxString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Profile Secure Storage

struct ProfileSensitivePayload: Codable, Equatable {
    var ownerNameKana: String?
    var postalCode: String?
    var address: String?
    var phoneNumber: String?
    var dateOfBirth: Date?
    var businessCategory: String?
    var myNumberFlag: Bool?
    var includeSensitiveInExport: Bool

    static func fromLegacyProfile(
        ownerNameKana: String?,
        postalCode: String?,
        address: String?,
        phoneNumber: String?,
        dateOfBirth: Date?,
        businessCategory: String?,
        myNumberFlag: Bool?,
        includeSensitiveInExport: Bool = true
    ) -> ProfileSensitivePayload {
        ProfileSensitivePayload(
            ownerNameKana: normalize(ownerNameKana),
            postalCode: normalize(postalCode),
            address: normalize(address),
            phoneNumber: normalize(phoneNumber),
            dateOfBirth: dateOfBirth,
            businessCategory: normalize(businessCategory),
            myNumberFlag: myNumberFlag,
            includeSensitiveInExport: includeSensitiveInExport
        )
    }

    private static func normalize(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

enum ProfileSecureStore {
    private static let service = "com.projectprofit.profile-sensitive"

    static func load(profileId: String) -> ProfileSensitivePayload? {
        var query = baseQuery(profileId: profileId)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = kCFBooleanTrue

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        let decoder = JSONDecoder()
        return try? decoder.decode(ProfileSensitivePayload.self, from: data)
    }

    @discardableResult
    static func save(_ payload: ProfileSensitivePayload, profileId: String) -> Bool {
        if profileId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else {
            return false
        }

        let base = baseQuery(profileId: profileId)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            return false
        }

        var addQuery = base
        attributes.forEach { key, value in
            addQuery[key] = value
        }
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete(profileId: String) -> Bool {
        let status = SecItemDelete(baseQuery(profileId: profileId) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(profileId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileId
        ]
    }
}
