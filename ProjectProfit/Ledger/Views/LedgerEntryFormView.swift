// ============================================================
// LedgerEntryFormView.swift
// エントリの追加/編集フォーム（台帳タイプ別に適応）
// ============================================================

import SwiftUI

struct LedgerEntryFormView: View {
    @Environment(LedgerDataStore.self) private var ledgerStore
    @Environment(\.dismiss) private var dismiss

    let bookId: UUID

    // 共通フィールド
    @State private var month = Calendar.current.component(.month, from: Date())
    @State private var day = Calendar.current.component(.day, from: Date())
    @State private var descriptionText = ""
    @State private var accountText = ""
    @State private var counterAccountText = ""

    // 金額フィールド
    @State private var incomeText = ""
    @State private var expenseText = ""
    @State private var debitText = ""
    @State private var creditText = ""
    @State private var amountText = ""
    @State private var quantityText = ""
    @State private var unitPriceText = ""

    // インボイス
    @State private var reducedTax = false
    @State private var selectedInvoiceType: InvoiceType?

    // 仕訳帳
    @State private var debitAccountText = ""
    @State private var creditAccountText = ""
    @State private var isCompoundContinuation = false

    // 交通費
    @State private var destination = ""
    @State private var purpose = ""
    @State private var transportMethod = ""
    @State private var routeFrom = ""
    @State private var routeTo = ""
    @State private var tripType: TripType = .roundTrip
    @State private var entryDate = Date()

    // 白色申告 経費18列
    @State private var salariesText = ""
    @State private var outsourcingText = ""
    @State private var depreciationText = ""
    @State private var badDebtsText = ""
    @State private var rentText = ""
    @State private var interestDiscountText = ""
    @State private var taxesDutiesText = ""
    @State private var packingShippingText = ""
    @State private var utilitiesText = ""
    @State private var travelTransportText = ""
    @State private var communicationText = ""
    @State private var advertisingText = ""
    @State private var entertainmentText = ""
    @State private var insuranceText = ""
    @State private var repairsText = ""
    @State private var suppliesText = ""
    @State private var welfareText = ""
    @State private var miscellaneousText = ""

    // 固定資産台帳兼減価償却計算表
    @State private var assetCode = ""
    @State private var assetName = ""
    @State private var assetType = ""
    @State private var selectedAssetStatus: AssetStatus = .inUse
    @State private var acquisitionCostText = ""
    @State private var selectedDepreciationMethod: DepreciationMethod = .straightLine
    @State private var usefulLifeText = ""
    @State private var depreciationRateText = ""
    @State private var depreciationMonthsText = ""
    @State private var openingBookValueText = ""
    @State private var midYearChangeText = ""
    @State private var specialDepreciationText = ""
    @State private var businessUseRatioText = ""
    @State private var assetRemarks = ""
    @State private var acquisitionDateText = ""

    // 固定資産台帳
    @State private var regAcqQuantityText = ""
    @State private var regAcqUnitPriceText = ""
    @State private var regDepAmountText = ""
    @State private var regDispQuantityText = ""
    @State private var regDispAmountText = ""
    @State private var regBizRatioText = ""
    @State private var regRemarks = ""

    private var book: SDLedgerBook? {
        ledgerStore.book(for: bookId)
    }

    private var ledgerType: LedgerType? {
        book?.ledgerType
    }

    private var includeInvoice: Bool {
        book?.includeInvoice ?? false
    }

    var body: some View {
        Form {
            if ledgerStore.isReadOnly {
                Section {
                    Text("旧台帳は読み取り専用です")
                        .foregroundStyle(.secondary)
                }
            }

            switch ledgerType {
            case .cashBook, .cashBookInvoice:
                cashBookForm
            case .bankAccountBook, .bankAccountBookInvoice:
                bankAccountBookForm
            case .accountsReceivable:
                accountsReceivableForm
            case .accountsPayable:
                accountsPayableForm
            case .expenseBook, .expenseBookInvoice:
                expenseBookForm
            case .generalLedger, .generalLedgerInvoice:
                generalLedgerForm
            case .journal:
                journalForm
            case .transportationExpense:
                transportationExpenseForm
            case .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice:
                whiteTaxBookkeepingForm
            case .fixedAssetDepreciation:
                fixedAssetDepreciationForm
            case .fixedAssetRegister:
                fixedAssetRegisterForm
            default:
                Text("この台帳タイプはまだ対応していません")
            }
        }
        .navigationTitle("エントリを追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    saveEntry()
                    dismiss()
                }
                .disabled((descriptionText.isEmpty && destination.isEmpty && assetName.isEmpty) || ledgerStore.isReadOnly)
            }
        }
    }

    // MARK: - Common Date Section

    private var dateSection: some View {
        Section("日付") {
            HStack {
                Text("月")
                Spacer()
                TextField("月", value: $month, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }
            HStack {
                Text("日")
                Spacer()
                TextField("日", value: $day, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }
        }
    }

    private var invoiceSection: some View {
        Group {
            if includeInvoice {
                Section("インボイス") {
                    Toggle("軽減税率", isOn: $reducedTax)
                    Picker("インボイス種類", selection: $selectedInvoiceType) {
                        Text("なし").tag(nil as InvoiceType?)
                        ForEach([InvoiceType.applicable, .eightyPercent, .smallAmount], id: \.self) { type in
                            Text(type.rawValue).tag(type as InvoiceType?)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cash Book Form

    private var cashBookForm: some View {
        Group {
            dateSection
            Section("取引") {
                TextField("摘要", text: $descriptionText)
                LedgerAccountPicker(label: "勘定科目", selection: $accountText, ledgerType: ledgerType ?? .cashBook)
            }
            invoiceSection
            Section("金額") {
                currencyInput(label: "入金", text: $incomeText)
                currencyInput(label: "出金", text: $expenseText)
            }
        }
    }

    // MARK: - Bank Account Book Form

    private var bankAccountBookForm: some View {
        Group {
            dateSection
            Section("取引") {
                TextField("摘要", text: $descriptionText)
                LedgerAccountPicker(label: "勘定科目", selection: $accountText, ledgerType: ledgerType ?? .bankAccountBook)
            }
            invoiceSection
            Section("金額") {
                currencyInput(label: "入金", text: $incomeText)
                currencyInput(label: "出金", text: $expenseText)
            }
        }
    }

    // MARK: - Accounts Receivable Form

    private var accountsReceivableForm: some View {
        Group {
            dateSection
            Section("取引") {
                LedgerAccountPicker(label: "相手科目", selection: $counterAccountText, ledgerType: .accountsReceivable)
                TextField("摘要", text: $descriptionText)
            }
            Section("数量・単価") {
                currencyInput(label: "数量", text: $quantityText)
                currencyInput(label: "単価", text: $unitPriceText)
            }
            Section("金額") {
                currencyInput(label: "売上金額", text: $incomeText)
                currencyInput(label: "入金金額", text: $expenseText)
            }
        }
    }

    // MARK: - Accounts Payable Form

    private var accountsPayableForm: some View {
        Group {
            dateSection
            Section("取引") {
                LedgerAccountPicker(label: "相手科目", selection: $counterAccountText, ledgerType: .accountsPayable)
                TextField("摘要", text: $descriptionText)
            }
            Section("数量・単価") {
                currencyInput(label: "数量", text: $quantityText)
                currencyInput(label: "単価", text: $unitPriceText)
            }
            Section("金額") {
                currencyInput(label: "仕入金額", text: $incomeText)
                currencyInput(label: "支払金額", text: $expenseText)
            }
        }
    }

    // MARK: - Expense Book Form

    private var expenseBookForm: some View {
        Group {
            dateSection
            Section("取引") {
                LedgerAccountPicker(label: "相手科目", selection: $counterAccountText, ledgerType: ledgerType ?? .expenseBook)
                TextField("摘要", text: $descriptionText)
            }
            invoiceSection
            Section("金額") {
                currencyInput(label: "金額", text: $amountText)
            }
        }
    }

    // MARK: - General Ledger Form

    private var generalLedgerForm: some View {
        Group {
            dateSection
            Section("取引") {
                LedgerAccountPicker(label: "相手科目", selection: $counterAccountText, ledgerType: ledgerType ?? .generalLedger)
                TextField("摘要", text: $descriptionText)
            }
            invoiceSection
            Section("金額") {
                currencyInput(label: "借方", text: $debitText)
                currencyInput(label: "貸方", text: $creditText)
            }
        }
    }

    // MARK: - Journal Form

    private var journalForm: some View {
        Group {
            dateSection
            Section("仕訳") {
                LedgerAccountPicker(label: "借方科目", selection: $debitAccountText, ledgerType: .journal)
                currencyInput(label: "借方金額", text: $debitText)
                LedgerAccountPicker(label: "貸方科目", selection: $creditAccountText, ledgerType: .journal)
                currencyInput(label: "貸方金額", text: $creditText)
            }
            Section("摘要") {
                TextField("摘要", text: $descriptionText)
            }
            Section {
                Toggle("複合仕訳の続行行", isOn: $isCompoundContinuation)
            }
        }
    }

    // MARK: - Transportation Expense Form

    private var transportationExpenseForm: some View {
        Group {
            Section("日付") {
                DatePicker("日付", selection: $entryDate, displayedComponents: .date)
            }
            Section("移動") {
                TextField("行先", text: $destination)
                TextField("目的", text: $purpose)
                TextField("交通手段", text: $transportMethod)
                TextField("出発地", text: $routeFrom)
                TextField("到着地", text: $routeTo)
                Picker("区分", selection: $tripType) {
                    Text("片道").tag(TripType.oneWay)
                    Text("往復").tag(TripType.roundTrip)
                }
            }
            Section("金額") {
                currencyInput(label: "金額", text: $amountText)
            }
        }
    }

    // MARK: - White Tax Bookkeeping Form

    private var whiteTaxBookkeepingForm: some View {
        Group {
            dateSection
            Section("摘要") {
                TextField("摘要", text: $descriptionText)
            }
            invoiceSection
            Section("収入") {
                currencyInput(label: "売上金額", text: $incomeText)
                currencyInput(label: "雑収入等", text: $expenseText)
            }
            Section("仕入") {
                currencyInput(label: "仕入", text: $amountText)
            }
            whiteTaxExpenseSection
            whiteTaxExpenseTotalSection
        }
    }

    private var whiteTaxExpenseSection: some View {
        Group {
            Section {
                DisclosureGroup("経費（人件費）") {
                    currencyInput(label: "給料賃金", text: $salariesText)
                    currencyInput(label: "外注工賃", text: $outsourcingText)
                    currencyInput(label: "福利厚生費", text: $welfareText)
                }
            }
            Section {
                DisclosureGroup("経費（固定費）") {
                    currencyInput(label: "地代家賃", text: $rentText)
                    currencyInput(label: "利子割引料", text: $interestDiscountText)
                    currencyInput(label: "損害保険料", text: $insuranceText)
                    currencyInput(label: "減価償却費", text: $depreciationText)
                }
            }
            Section {
                DisclosureGroup("経費（変動費）") {
                    currencyInput(label: "水道光熱費", text: $utilitiesText)
                    currencyInput(label: "旅費交通費", text: $travelTransportText)
                    currencyInput(label: "通信費", text: $communicationText)
                    currencyInput(label: "広告宣伝費", text: $advertisingText)
                    currencyInput(label: "接待交際費", text: $entertainmentText)
                }
            }
            Section {
                DisclosureGroup("経費（その他）") {
                    currencyInput(label: "租税公課", text: $taxesDutiesText)
                    currencyInput(label: "荷造運賃", text: $packingShippingText)
                    currencyInput(label: "貸倒金", text: $badDebtsText)
                    currencyInput(label: "修繕費", text: $repairsText)
                    currencyInput(label: "消耗品費", text: $suppliesText)
                    currencyInput(label: "雑費", text: $miscellaneousText)
                }
            }
        }
    }

    private var whiteTaxExpenseTotalSection: some View {
        Section("経費合計") {
            let total = whiteTaxExpenseTotal
            HStack {
                Text("経費合計")
                    .font(.headline)
                Spacer()
                Text(formatCurrency(total))
                    .font(.headline.monospacedDigit())
                Text("円")
            }
        }
    }

    private var whiteTaxExpenseTotal: Int {
        [salariesText, outsourcingText, depreciationText, badDebtsText,
         rentText, interestDiscountText, taxesDutiesText, packingShippingText,
         utilitiesText, travelTransportText, communicationText, advertisingText,
         entertainmentText, insuranceText, repairsText, suppliesText,
         welfareText, miscellaneousText].compactMap { Int($0) }.reduce(0, +)
    }

    // MARK: - Fixed Asset Depreciation Form

    private var fixedAssetDepreciationForm: some View {
        Group {
            Section("基本情報") {
                LedgerAccountPicker(label: "勘定科目", selection: $accountText, ledgerType: .fixedAssetDepreciation)
                TextField("資産コード", text: $assetCode)
                TextField("資産名", text: $assetName)
                TextField("資産の種類", text: $assetType)
                Picker("状態", selection: $selectedAssetStatus) {
                    ForEach(AssetStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                currencyInput(label: "数量", text: $quantityText)
                TextField("取得日", text: $acquisitionDateText)
                    .keyboardType(.numbersAndPunctuation)
                currencyInput(label: "取得価額", text: $acquisitionCostText)
            }
            Section("償却設定") {
                Picker("償却方法", selection: $selectedDepreciationMethod) {
                    ForEach(DepreciationMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                numberInput(label: "耐用年数", text: $usefulLifeText, suffix: "年")
                decimalInput(label: "償却率", text: $depreciationRateText)
                numberInput(label: "償却月数", text: $depreciationMonthsText, suffix: "月")
            }
            Section("本年の計算") {
                currencyInput(label: "期首帳簿価額", text: $openingBookValueText)
                currencyInput(label: "期中増減", text: $midYearChangeText)
                currencyInput(label: "特別償却費", text: $specialDepreciationText)
                decimalInput(label: "事業専用割合", text: $businessUseRatioText)
            }
            Section("自動計算結果") {
                let depExp = calculatedDepreciationExpense
                let totalDep = depExp + (Int(specialDepreciationText) ?? 0)
                let ratio = Double(businessUseRatioText) ?? 1.0
                let deductible = Int(Double(totalDep) * ratio)
                let opening = Int(openingBookValueText) ?? 0
                let change = Int(midYearChangeText) ?? 0
                let yearEnd = opening + change - totalDep

                HStack {
                    Text("減価償却費")
                    Spacer()
                    Text(formatCurrency(depExp))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("償却費合計")
                    Spacer()
                    Text(formatCurrency(totalDep))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("必要経費算入額")
                    Spacer()
                    Text(formatCurrency(deductible))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("本年末残高")
                    Spacer()
                    Text(formatCurrency(yearEnd))
                        .foregroundStyle(.secondary)
                }
            }
            Section("摘要") {
                TextField("摘要", text: $assetRemarks)
            }
        }
    }

    private var calculatedDepreciationExpense: Int {
        let opening = Int(openingBookValueText) ?? 0
        let rate = Double(depreciationRateText) ?? 0.0
        return Int(Double(opening) * rate)
    }

    // MARK: - Fixed Asset Register Form

    private var fixedAssetRegisterForm: some View {
        Group {
            Section("日付・摘要") {
                HStack {
                    Text("月")
                    Spacer()
                    TextField("月", value: $month, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                }
                HStack {
                    Text("日")
                    Spacer()
                    TextField("日", value: $day, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                }
                TextField("摘要", text: $descriptionText)
            }
            Section("取得") {
                currencyInput(label: "数量", text: $regAcqQuantityText)
                currencyInput(label: "単価", text: $regAcqUnitPriceText)
                HStack {
                    Text("金額")
                    Spacer()
                    let qty = Int(regAcqQuantityText) ?? 0
                    let price = Int(regAcqUnitPriceText) ?? 0
                    Text(formatCurrency(qty * price))
                        .foregroundStyle(.secondary)
                    Text("円")
                }
            }
            Section("償却・異動") {
                currencyInput(label: "償却額", text: $regDepAmountText)
                currencyInput(label: "異動数量", text: $regDispQuantityText)
                currencyInput(label: "異動金額", text: $regDispAmountText)
            }
            Section("事業専用割合") {
                decimalInput(label: "割合", text: $regBizRatioText)
            }
            Section("備考") {
                TextField("備考", text: $regRemarks)
            }
        }
    }

    // MARK: - Helpers

    private func numberInput(label: String, text: Binding<String>, suffix: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
            Text(suffix)
        }
    }

    private func decimalInput(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0.0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func currencyInput(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
            Text("円")
        }
    }

    // MARK: - Save

    private func saveEntry() {
        guard let ledgerType else { return }

        switch ledgerType {
        case .cashBook, .cashBookInvoice:
            let entry = CashBookEntry(
                month: month, day: day,
                description: descriptionText,
                account: accountText,
                income: Int(incomeText),
                expense: Int(expenseText),
                reducedTax: reducedTax ? true : nil,
                invoiceType: selectedInvoiceType
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .bankAccountBook, .bankAccountBookInvoice:
            let entry = BankAccountBookEntry(
                month: month, day: day,
                description: descriptionText,
                account: accountText,
                deposit: Int(incomeText),
                withdrawal: Int(expenseText),
                reducedTax: reducedTax ? true : nil,
                invoiceType: selectedInvoiceType
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .accountsReceivable:
            let entry = AccountsReceivableEntry(
                month: month, day: day,
                counterAccount: counterAccountText,
                description: descriptionText,
                quantity: Int(quantityText),
                unitPrice: Int(unitPriceText),
                salesAmount: Int(incomeText),
                receivedAmount: Int(expenseText)
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .accountsPayable:
            let entry = AccountsPayableEntry(
                month: month, day: day,
                counterAccount: counterAccountText,
                description: descriptionText,
                quantity: Int(quantityText),
                unitPrice: Int(unitPriceText),
                purchaseAmount: Int(incomeText),
                paymentAmount: Int(expenseText)
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .expenseBook, .expenseBookInvoice:
            let entry = ExpenseBookEntry(
                month: month, day: day,
                counterAccount: counterAccountText,
                description: descriptionText,
                amount: Int(amountText) ?? 0,
                reducedTax: reducedTax ? true : nil,
                invoiceType: selectedInvoiceType
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .generalLedger, .generalLedgerInvoice:
            let entry = GeneralLedgerEntry(
                month: month, day: day,
                counterAccount: counterAccountText,
                description: descriptionText,
                debit: Int(debitText),
                credit: Int(creditText),
                reducedTax: reducedTax ? true : nil,
                invoiceType: selectedInvoiceType
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .journal:
            let entry = JournalEntry(
                month: month, day: day,
                description: descriptionText,
                debitAccount: debitAccountText.isEmpty ? nil : debitAccountText,
                debitAmount: Int(debitText),
                creditAccount: creditAccountText.isEmpty ? nil : creditAccountText,
                creditAmount: Int(creditText),
                isCompoundContinuation: isCompoundContinuation
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .transportationExpense:
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy/MM/dd"
            let entry = TransportationExpenseEntry(
                id: UUID(),
                date: dateFormatter.string(from: entryDate),
                destination: destination,
                purpose: purpose,
                transportMethod: transportMethod,
                routeFrom: routeFrom,
                routeTo: routeTo,
                tripType: tripType,
                amount: Int(amountText) ?? 0
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice:
            let entry = WhiteTaxBookkeepingEntry(
                id: UUID(),
                month: month, day: day,
                description: descriptionText,
                salesAmount: Int(incomeText),
                miscIncome: Int(expenseText),
                purchases: Int(amountText),
                salaries: Int(salariesText),
                outsourcing: Int(outsourcingText),
                depreciation: Int(depreciationText),
                badDebts: Int(badDebtsText),
                rent: Int(rentText),
                interestDiscount: Int(interestDiscountText),
                taxesDuties: Int(taxesDutiesText),
                packingShipping: Int(packingShippingText),
                utilities: Int(utilitiesText),
                travelTransport: Int(travelTransportText),
                communication: Int(communicationText),
                advertising: Int(advertisingText),
                entertainment: Int(entertainmentText),
                insurance: Int(insuranceText),
                repairs: Int(repairsText),
                supplies: Int(suppliesText),
                welfare: Int(welfareText),
                miscellaneous: Int(miscellaneousText),
                reducedTax: reducedTax ? true : nil,
                invoiceType: selectedInvoiceType
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .fixedAssetDepreciation:
            let entry = FixedAssetDepreciationEntry(
                account: accountText,
                assetCode: assetCode,
                assetName: assetName,
                assetType: assetType,
                status: selectedAssetStatus.rawValue,
                acquisitionDate: acquisitionDateText,
                acquisitionCost: Int(acquisitionCostText) ?? 0,
                depreciationMethod: selectedDepreciationMethod,
                usefulLife: Int(usefulLifeText) ?? 0,
                depreciationRate: Double(depreciationRateText) ?? 0.0,
                depreciationMonths: Int(depreciationMonthsText) ?? 0,
                openingBookValue: Int(openingBookValueText) ?? 0,
                businessUseRatio: Double(businessUseRatioText) ?? 1.0,
                quantity: Int(quantityText),
                midYearChange: Int(midYearChangeText),
                remarks: assetRemarks.isEmpty ? nil : assetRemarks
            )
            ledgerStore.addEntry(to: bookId, entry: entry)

        case .fixedAssetRegister:
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy/MM/dd"
            let year = Calendar.current.component(.year, from: Date())
            let dateStr = String(format: "%04d/%02d/%02d", year, month, day)
            let qty = Int(regAcqQuantityText) ?? 0
            let price = Int(regAcqUnitPriceText) ?? 0
            let entry = FixedAssetRegisterEntry(
                id: UUID(),
                date: dateStr,
                description: descriptionText,
                acquiredQuantity: qty > 0 ? qty : nil,
                acquiredUnitPrice: price > 0 ? price : nil,
                acquiredAmount: (qty * price) > 0 ? qty * price : nil,
                depreciationAmount: Int(regDepAmountText),
                disposalQuantity: Int(regDispQuantityText),
                disposalAmount: Int(regDispAmountText),
                businessUseRatio: Double(regBizRatioText),
                remarks: regRemarks.isEmpty ? nil : regRemarks
            )
            ledgerStore.addEntry(to: bookId, entry: entry)
        }
    }
}
