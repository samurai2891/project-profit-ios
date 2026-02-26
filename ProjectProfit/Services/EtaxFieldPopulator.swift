import Foundation
import Security

/// P&L / B/S レポートデータを e-Tax フィールドにマッピングする
@MainActor
enum EtaxFieldPopulator {

    /// P&Lレポートからe-Taxフォームを生成
    static func populate(
        fiscalYear: Int,
        profitLoss: ProfitLossReport,
        balanceSheet: BalanceSheetReport?,
        formType: EtaxFormType = .blueReturn,
        accounts: [PPAccount],
        profile: PPAccountingProfile? = nil,
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
        if let profile {
            fields.append(contentsOf: populateDeclarantInfo(profile: profile))
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

    // MARK: - Declarant Info

    /// 申告者情報セクションのフィールドを生成
    static func populateDeclarantInfo(profile: PPAccountingProfile) -> [EtaxField] {
        var fields: [EtaxField] = []
        let secure = ProfileSecureStore.load(profileId: profile.id)
        let includeSensitive = secure?.includeSensitiveInExport ?? false

        let ownerNameKana = secure?.ownerNameKana
        let postalCode = secure?.postalCode
        let address = secure?.address
        let phoneNumber = secure?.phoneNumber
        let dateOfBirth = secure?.dateOfBirth
        let businessCategory = secure?.businessCategory
        let myNumberFlag = secure?.myNumberFlag

        if !profile.ownerName.isEmpty {
            fields.append(EtaxField(
                id: "declarant_name", fieldLabel: "氏名",
                taxLine: nil, value: profile.ownerName, section: .declarantInfo
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
        if !profile.businessName.isEmpty {
            fields.append(EtaxField(
                id: "declarant_business_name", fieldLabel: "屋号",
                taxLine: nil, value: profile.businessName, section: .declarantInfo
            ))
        }
        if includeSensitive, let category = businessCategory, !category.isEmpty {
            fields.append(EtaxField(
                id: "declarant_business_category", fieldLabel: "事業種類",
                taxLine: nil, value: category, section: .declarantInfo
            ))
        }
        if includeSensitive, let birthDate = dateOfBirth {
            fields.append(EtaxField(
                id: "declarant_birth_date", fieldLabel: "生年月日",
                taxLine: nil, value: birthDateEtaxString(from: birthDate), section: .declarantInfo
            ))
        }
        if includeSensitive, let myNumberFlag {
            fields.append(EtaxField(
                id: "declarant_my_number_flag", fieldLabel: "マイナンバー提出有無",
                taxLine: nil, value: myNumberFlag, section: .declarantInfo
            ))
        }

        return fields
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

        for item in balanceSheet.assetItems {
            fields.append(EtaxField(
                id: "bs_asset_\(item.id)", fieldLabel: item.name,
                taxLine: nil, value: item.balance, section: .balanceSheet
            ))
        }
        fields.append(EtaxField(
            id: "bs_total_assets", fieldLabel: "資産合計",
            taxLine: nil, value: balanceSheet.totalAssets, section: .balanceSheet
        ))

        for item in balanceSheet.liabilityItems {
            fields.append(EtaxField(
                id: "bs_liability_\(item.id)", fieldLabel: item.name,
                taxLine: nil, value: item.balance, section: .balanceSheet
            ))
        }
        fields.append(EtaxField(
            id: "bs_total_liabilities", fieldLabel: "負債合計",
            taxLine: nil, value: balanceSheet.totalLiabilities, section: .balanceSheet
        ))

        for item in balanceSheet.equityItems {
            fields.append(EtaxField(
                id: "bs_equity_\(item.id)", fieldLabel: item.name,
                taxLine: nil, value: item.balance, section: .balanceSheet
            ))
        }
        fields.append(EtaxField(
            id: "bs_total_equity", fieldLabel: "資本合計",
            taxLine: nil, value: balanceSheet.totalEquity, section: .balanceSheet
        ))

        return fields
    }

    // MARK: - Helpers

    private static func taxLineForAccountId(_ accountId: String, accounts: [PPAccount]) -> TaxLine? {
        guard let account = accounts.first(where: { $0.id == accountId }),
              let subtype = account.subtype
        else { return nil }

        return TaxLine.allCases.first { $0.accountSubtype == subtype }
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
