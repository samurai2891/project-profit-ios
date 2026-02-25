import XCTest
import SwiftData
@testable import ProjectProfit

/// 統合テスト: 消費税仕訳・e-Tax申告者情報・XTX XML 生成の検証
@MainActor
final class AccountingIntegrationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var engine: AccountingEngine!
    var accounts: [PPAccount]!
    var categories: [PPCategory]!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self,
            PPAccount.self, PPJournalEntry.self, PPJournalLine.self, PPAccountingProfile.self,
            PPUserRule.self,
            PPFixedAsset.self,
            configurations: config
        )
        context = ModelContext(container)
        engine = AccountingEngine(modelContext: context)

        // デフォルト勘定科目をシード
        for def in AccountingConstants.defaultAccounts {
            let account = PPAccount(
                id: def.id, code: def.code, name: def.name,
                accountType: def.accountType, normalBalance: def.normalBalance,
                subtype: def.subtype, isSystem: true, displayOrder: def.displayOrder
            )
            context.insert(account)
        }
        try! context.save()

        let descriptor = FetchDescriptor<PPAccount>(sortBy: [SortDescriptor(\.displayOrder)])
        accounts = try! context.fetch(descriptor)

        // カテゴリをシード
        for cat in DEFAULT_CATEGORIES {
            let category = PPCategory(
                id: cat.id, name: cat.name, type: cat.type, icon: cat.icon, isDefault: true
            )
            if let accountId = AccountingConstants.categoryToAccountMapping[cat.id] {
                category.linkedAccountId = accountId
            }
            context.insert(category)
        }
        try! context.save()

        let catDescriptor = FetchDescriptor<PPCategory>()
        categories = try! context.fetch(catDescriptor)
    }

    override func tearDown() {
        accounts = nil
        categories = nil
        engine = nil
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Test 1: 課税収入の仕訳行検証

    /// 標準税率10%の収入トランザクション (税込11,000円、税額1,000円) から
    /// Dr 現金 11,000 / Cr 売上 10,000 + Cr 仮受消費税 1,000 の3行仕訳が生成されることを検証
    func testTaxIncomeTransaction_GeneratesCorrectJournalLines() {
        let tx = createTransaction(
            type: .income,
            amount: 11_000,
            categoryId: "cat-sales",
            taxAmount: 1_000,
            taxCategory: .standardRate
        )

        let entry = engine.upsertJournalEntry(for: tx, categories: categories, accounts: accounts)

        XCTAssertNotNil(entry)
        XCTAssertTrue(entry!.isPosted, "課税収入仕訳は自動投稿されるべき")
        XCTAssertEqual(entry!.entryType, .auto)

        let lines = fetchLines(for: entry!.id)
        XCTAssertEqual(lines.count, 3, "課税収入は3行仕訳: Dr現金 / Cr売上 + Cr仮受消費税")

        // Dr 現金 11,000
        let cashLine = lines.first { $0.accountId == AccountingConstants.cashAccountId }
        XCTAssertNotNil(cashLine, "現金の借方行が存在すること")
        XCTAssertEqual(cashLine?.debit, 11_000)
        XCTAssertEqual(cashLine?.credit, 0)

        // Cr 売上 10,000 (税抜)
        let salesLine = lines.first { $0.accountId == AccountingConstants.salesAccountId }
        XCTAssertNotNil(salesLine, "売上の貸方行が存在すること")
        XCTAssertEqual(salesLine?.debit, 0)
        XCTAssertEqual(salesLine?.credit, 10_000)

        // Cr 仮受消費税 1,000
        let outputTaxLine = lines.first { $0.accountId == AccountingConstants.outputTaxAccountId }
        XCTAssertNotNil(outputTaxLine, "仮受消費税の貸方行が存在すること")
        XCTAssertEqual(outputTaxLine?.debit, 0)
        XCTAssertEqual(outputTaxLine?.credit, 1_000)

        // 貸借一致
        let totalDebit = lines.reduce(0) { $0 + $1.debit }
        let totalCredit = lines.reduce(0) { $0 + $1.credit }
        XCTAssertEqual(totalDebit, totalCredit, "借方合計 == 貸方合計")
        XCTAssertEqual(totalDebit, 11_000)
    }

    // MARK: - Test 2: 課税経費の仕訳行検証

    /// 軽減税率8%の経費トランザクション (税込10,800円、税額800円) から
    /// Dr 経費 10,000 + Dr 仮払消費税 800 / Cr 現金 10,800 の3行仕訳が生成されることを検証
    func testTaxExpenseTransaction_GeneratesCorrectJournalLines() {
        let tx = createTransaction(
            type: .expense,
            amount: 10_800,
            categoryId: "cat-food",
            taxAmount: 800,
            taxCategory: .reducedRate
        )

        let entry = engine.upsertJournalEntry(for: tx, categories: categories, accounts: accounts)

        XCTAssertNotNil(entry)
        XCTAssertTrue(entry!.isPosted, "課税経費仕訳は自動投稿されるべき")

        let lines = fetchLines(for: entry!.id)
        XCTAssertEqual(lines.count, 3, "課税経費は3行仕訳: Dr経費 + Dr仮払消費税 / Cr現金")

        // Dr 経費 10,000 (税抜) — cat-food は acct-entertainment にマッピング
        let expenseLine = lines.first { $0.accountId == "acct-entertainment" }
        XCTAssertNotNil(expenseLine, "経費（接待交際費）の借方行が存在すること")
        XCTAssertEqual(expenseLine?.debit, 10_000)
        XCTAssertEqual(expenseLine?.credit, 0)

        // Dr 仮払消費税 800
        let inputTaxLine = lines.first { $0.accountId == AccountingConstants.inputTaxAccountId }
        XCTAssertNotNil(inputTaxLine, "仮払消費税の借方行が存在すること")
        XCTAssertEqual(inputTaxLine?.debit, 800)
        XCTAssertEqual(inputTaxLine?.credit, 0)

        // Cr 現金 10,800
        let cashLine = lines.first { $0.accountId == AccountingConstants.cashAccountId }
        XCTAssertNotNil(cashLine, "現金の貸方行が存在すること")
        XCTAssertEqual(cashLine?.debit, 0)
        XCTAssertEqual(cashLine?.credit, 10_800)

        // 貸借一致
        let totalDebit = lines.reduce(0) { $0 + $1.debit }
        let totalCredit = lines.reduce(0) { $0 + $1.credit }
        XCTAssertEqual(totalDebit, totalCredit, "借方合計 == 貸方合計")
        XCTAssertEqual(totalDebit, 10_800)
    }

    // MARK: - Test 3: 消費税なし (後方互換性)

    /// taxAmount=nil のトランザクションは従来どおり消費税行なしの2行仕訳になることを検証
    func testTransactionWithoutTax_BackwardCompatibility() {
        // 収入: taxAmount=nil → 2行仕訳 (Dr 現金 / Cr 売上)
        let incomeTx = createTransaction(
            type: .income,
            amount: 50_000,
            categoryId: "cat-sales",
            taxAmount: nil,
            taxCategory: nil
        )

        let incomeEntry = engine.upsertJournalEntry(for: incomeTx, categories: categories, accounts: accounts)
        XCTAssertNotNil(incomeEntry)

        let incomeLines = fetchLines(for: incomeEntry!.id)
        XCTAssertEqual(incomeLines.count, 2, "taxAmount=nil の収入は2行仕訳")

        // 仮受消費税行がないことを確認
        let outputTaxLine = incomeLines.first { $0.accountId == AccountingConstants.outputTaxAccountId }
        XCTAssertNil(outputTaxLine, "消費税なしの場合は仮受消費税行が生成されない")

        // 経費: taxAmount=nil → 2行仕訳 (Dr 経費 / Cr 現金)
        let expenseTx = createTransaction(
            type: .expense,
            amount: 20_000,
            categoryId: "cat-tools",
            taxAmount: nil,
            taxCategory: nil
        )

        let expenseEntry = engine.upsertJournalEntry(for: expenseTx, categories: categories, accounts: accounts)
        XCTAssertNotNil(expenseEntry)

        let expenseLines = fetchLines(for: expenseEntry!.id)
        XCTAssertEqual(expenseLines.count, 2, "taxAmount=nil の経費は2行仕訳")

        // 仮払消費税行がないことを確認
        let inputTaxLine = expenseLines.first { $0.accountId == AccountingConstants.inputTaxAccountId }
        XCTAssertNil(inputTaxLine, "消費税なしの場合は仮払消費税行が生成されない")

        // 両方とも貸借一致
        for entry in [incomeEntry!, expenseEntry!] {
            let lines = fetchLines(for: entry.id)
            let totalDebit = lines.reduce(0) { $0 + $1.debit }
            let totalCredit = lines.reduce(0) { $0 + $1.credit }
            XCTAssertEqual(totalDebit, totalCredit, "仕訳 \(entry.memo) の貸借一致")
        }
    }

    // MARK: - Test 4: EtaxFieldPopulator 申告者情報フィールド生成

    /// PPAccountingProfile に e-Tax フィールドを設定し、EtaxFieldPopulator が
    /// .declarantInfo セクションのフィールドを正しく生成することを検証
    func testEtaxFieldPopulator_GeneratesDeclarantInfoFields() {
        let profile = PPAccountingProfile(
            fiscalYear: 2025,
            bookkeepingMode: .doubleEntry,
            businessName: "テスト屋号",
            ownerName: "田中太郎",
            ownerNameKana: "タナカタロウ",
            postalCode: "1000001",
            address: "東京都千代田区千代田1-1",
            phoneNumber: "03-1234-5678",
            businessCategory: "ソフトウェア開発"
        )

        let fields = EtaxFieldPopulator.populateDeclarantInfo(profile: profile)

        // 7フィールドすべてが生成されることを確認
        XCTAssertEqual(fields.count, 7, "全てのe-Tax申告者情報フィールドが生成されること")

        // 全フィールドが .declarantInfo セクションであること
        XCTAssertTrue(fields.allSatisfy { $0.section == .declarantInfo },
                       "全フィールドが declarantInfo セクション")

        // 各フィールドの存在を個別に確認
        let fieldIds = Set(fields.map(\.id))
        XCTAssertTrue(fieldIds.contains("declarant_name"), "氏名フィールド")
        XCTAssertTrue(fieldIds.contains("declarant_name_kana"), "氏名カナフィールド")
        XCTAssertTrue(fieldIds.contains("declarant_postal_code"), "郵便番号フィールド")
        XCTAssertTrue(fieldIds.contains("declarant_address"), "住所フィールド")
        XCTAssertTrue(fieldIds.contains("declarant_phone"), "電話番号フィールド")
        XCTAssertTrue(fieldIds.contains("declarant_business_name"), "屋号フィールド")
        XCTAssertTrue(fieldIds.contains("declarant_business_category"), "事業種類フィールド")

        let valueById = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0.value.exportText) })
        XCTAssertEqual(valueById["declarant_name"], "田中太郎")
        XCTAssertEqual(valueById["declarant_address"], "東京都千代田区千代田1-1")
        XCTAssertEqual(valueById["declarant_phone"], "03-1234-5678")
    }

    /// 空文字のフィールドは .declarantInfo に含まれないことを検証
    func testEtaxFieldPopulator_SkipsEmptyDeclarantFields() {
        let profile = PPAccountingProfile(
            fiscalYear: 2025,
            bookkeepingMode: .doubleEntry,
            businessName: "",
            ownerName: "山田花子"
            // ownerNameKana, postalCode, address, phoneNumber, businessCategory は全て nil
        )

        let fields = EtaxFieldPopulator.populateDeclarantInfo(profile: profile)

        // ownerName のみ設定 → declarant_name のみ
        XCTAssertEqual(fields.count, 1, "ownerName のみの場合は1フィールドのみ")
        XCTAssertEqual(fields.first?.id, "declarant_name")
    }

    // MARK: - Test 5: EtaxXtxExporter の全セクション XML 生成

    /// revenue, expenses, income, declarantInfo, inventory, balanceSheet の各セクションに
    /// フィールドを含む EtaxForm から generateXtx した XML が全セクションタグを含むことを検証
    func testEtaxXtxExporter_GeneratesValidXmlWithAllSections() {
        let fields: [EtaxField] = [
            // 収入
            EtaxField(
                id: "revenue_sales_revenue", fieldLabel: "売上金額",
                taxLine: .salesRevenue, value: 1_000_000, section: .revenue
            ),
            // 経費
            EtaxField(
                id: "expense_communication", fieldLabel: "通信費",
                taxLine: .communicationExpense, value: 50_000, section: .expenses
            ),
            // 所得
            EtaxField(
                id: "income_net", fieldLabel: "所得金額",
                taxLine: nil, value: 950_000, section: .income
            ),
            // 申告者情報
            EtaxField(
                id: "declarant_name", fieldLabel: "氏名",
                taxLine: nil, value: "山田太郎", section: .declarantInfo
            ),
            // 棚卸
            EtaxField(
                id: "inventory_opening", fieldLabel: "期首商品棚卸高",
                taxLine: nil, value: 100_000, section: .inventory
            ),
            // 貸借対照表
            EtaxField(
                id: "bs_total_assets", fieldLabel: "資産合計",
                taxLine: nil, value: 500_000, section: .balanceSheet
            ),
        ]

        let form = EtaxForm(
            fiscalYear: 2025,
            formType: .blueReturn,
            fields: fields,
            generatedAt: Date()
        )

        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success(let data):
            let xml = String(data: data, encoding: .utf8)!

            // ルート要素
            XCTAssertTrue(xml.contains("<eTaxData year=\"2025\""), "ルート開始タグ")
            XCTAssertTrue(xml.contains("</eTaxData>"), "ルート終了タグ")
            XCTAssertTrue(xml.contains("formType=\"青色申告決算書\""), "申告書種類")

            // xmlTag マッピングで出力されること
            XCTAssertTrue(xml.contains("<BlueRevenueSales>1000000</BlueRevenueSales>"), "売上金額")
            XCTAssertTrue(xml.contains("<BlueExpenseCommunication>50000</BlueExpenseCommunication>"), "通信費")
            XCTAssertTrue(xml.contains("<BlueIncomeNet>950000</BlueIncomeNet>"), "所得金額")
            XCTAssertTrue(xml.contains("<CommonName>山田太郎</CommonName>"), "氏名")
            XCTAssertTrue(xml.contains("<BlueInventoryOpening>100000</BlueInventoryOpening>"), "棚卸")
            XCTAssertTrue(xml.contains("<BlueBSTotalAssets>500000</BlueBSTotalAssets>"), "資産合計")

        case .failure(let error):
            XCTFail("XTX生成に失敗: \(error)")
        }
    }

    /// フィールドが空の EtaxForm は .noData エラーを返すことを検証
    func testEtaxXtxExporter_EmptyFormReturnsNoDataError() {
        let form = EtaxForm(
            fiscalYear: 2025,
            formType: .blueReturn,
            fields: [],
            generatedAt: Date()
        )

        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success:
            XCTFail("空フォームは成功すべきでない")
        case .failure(let error):
            if case .noData = error {
                // 期待どおり
            } else {
                XCTFail("noData エラーが期待されたが \(error) が返された")
            }
        }
    }

    // MARK: - Helpers

    private func createTransaction(
        type: TransactionType,
        amount: Int,
        categoryId: String,
        taxAmount: Int? = nil,
        taxCategory: TaxCategory? = nil
    ) -> PPTransaction {
        let tx = PPTransaction(
            type: type,
            amount: amount,
            date: Date(),
            categoryId: categoryId,
            memo: "テスト",
            allocations: [],
            taxAmount: taxAmount,
            taxCategory: taxCategory
        )
        context.insert(tx)
        try! context.save()
        return tx
    }

    private func fetchLines(for entryId: UUID) -> [PPJournalLine] {
        let descriptor = FetchDescriptor<PPJournalLine>(
            predicate: #Predicate<PPJournalLine> { $0.entryId == entryId },
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
