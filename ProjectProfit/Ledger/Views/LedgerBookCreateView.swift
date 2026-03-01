// ============================================================
// LedgerBookCreateView.swift
// 帳簿の新規作成 - 種類選択 → メタデータ入力
// ============================================================

import SwiftUI

struct LedgerBookCreateView: View {
    @Environment(LedgerDataStore.self) private var ledgerStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var selectedType: LedgerType = .cashBook
    @State private var includeInvoice = false

    // メタデータ（台帳種類に応じて使用）
    @State private var carryForwardText = "0"
    @State private var bankName = ""
    @State private var branchName = ""
    @State private var bankAccountType = "普通"
    @State private var clientName = ""
    @State private var supplierName = ""
    @State private var accountName = ""
    @State private var selectedAccountAttribute: AccountCategory = .asset

    private var isValid: Bool {
        !title.isEmpty
    }

    // 台帳種類のグループ定義
    private static let baseTypes: [LedgerType] = [
        .cashBook, .bankAccountBook, .accountsReceivable, .accountsPayable,
        .expenseBook, .generalLedger, .journal,
        .fixedAssetDepreciation, .fixedAssetRegister,
        .transportationExpense, .whiteTaxBookkeeping
    ]

    var body: some View {
        Form {
            Section("台帳の種類") {
                Picker("種類", selection: $selectedType) {
                    ForEach(Self.baseTypes, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .onChange(of: selectedType) {
                    updateDefaultTitle()
                }

                if selectedType.hasInvoiceVariant {
                    Toggle("インボイス対応", isOn: $includeInvoice)
                }
            }

            Section("基本情報") {
                TextField("帳簿名", text: $title)
            }

            metadataSection
        }
        .navigationTitle("帳簿を作成")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("作成") {
                    createBook()
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
        .onAppear { updateDefaultTitle() }
    }

    // MARK: - Metadata Sections

    @ViewBuilder
    private var metadataSection: some View {
        switch selectedType {
        case .cashBook, .cashBookInvoice:
            Section("繰越") {
                currencyField(label: "前期より繰越", text: $carryForwardText)
            }

        case .bankAccountBook, .bankAccountBookInvoice:
            Section("口座情報") {
                TextField("銀行名", text: $bankName)
                TextField("支店名", text: $branchName)
                Picker("口座種類", selection: $bankAccountType) {
                    Text("普通").tag("普通")
                    Text("当座").tag("当座")
                    Text("貯蓄").tag("貯蓄")
                }
            }
            Section("繰越") {
                currencyField(label: "前期より繰越", text: $carryForwardText)
            }

        case .accountsReceivable:
            Section("得意先") {
                TextField("得意先名", text: $clientName)
            }
            Section("繰越") {
                currencyField(label: "前期より繰越", text: $carryForwardText)
            }

        case .accountsPayable:
            Section("仕入先") {
                TextField("仕入先名", text: $supplierName)
            }
            Section("繰越") {
                currencyField(label: "前期より繰越", text: $carryForwardText)
            }

        case .expenseBook, .expenseBookInvoice:
            Section("勘定科目") {
                TextField("勘定科目名", text: $accountName)
            }

        case .generalLedger, .generalLedgerInvoice:
            Section("勘定科目") {
                TextField("勘定科目名", text: $accountName)
                Picker("科目の属性", selection: $selectedAccountAttribute) {
                    ForEach(AccountCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
            }
            Section("繰越") {
                currencyField(label: "前期より繰越", text: $carryForwardText)
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private func currencyField(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
            Text("円")
        }
    }

    private func updateDefaultTitle() {
        let baseName = selectedType.displayName
        if includeInvoice && selectedType.hasInvoiceVariant {
            title = "\(baseName)（インボイス）"
        } else {
            title = baseName
        }
    }

    private func resolvedLedgerType() -> LedgerType {
        if includeInvoice {
            switch selectedType {
            case .cashBook: return .cashBookInvoice
            case .bankAccountBook: return .bankAccountBookInvoice
            case .expenseBook: return .expenseBookInvoice
            case .generalLedger: return .generalLedgerInvoice
            case .whiteTaxBookkeeping: return .whiteTaxBookkeepingInvoice
            default: return selectedType
            }
        }
        return selectedType
    }

    private func createBook() {
        let ledgerType = resolvedLedgerType()
        let metadataJSON = buildMetadataJSON()

        ledgerStore.createBook(
            ledgerType: ledgerType,
            title: title,
            metadataJSON: metadataJSON,
            includeInvoice: includeInvoice
        )
    }

    private func buildMetadataJSON() -> String {
        let carryForward = Int(carryForwardText) ?? 0

        switch selectedType {
        case .cashBook, .cashBookInvoice:
            let meta = CashBookMetadata(carryForward: carryForward)
            return LedgerBridge.encodeCashBookMetadata(meta)

        case .bankAccountBook, .bankAccountBookInvoice:
            let meta = BankAccountBookMetadata(
                bankName: bankName,
                branchName: branchName,
                accountType: bankAccountType,
                carryForward: carryForward
            )
            return LedgerBridge.encodeBankAccountBookMetadata(meta)

        case .accountsReceivable:
            let meta = AccountsReceivableMetadata(
                clientName: clientName,
                carryForward: carryForward
            )
            return LedgerBridge.encodeAccountsReceivableMetadata(meta)

        case .accountsPayable:
            let meta = AccountsPayableMetadata(
                supplierName: supplierName,
                carryForward: carryForward
            )
            return LedgerBridge.encodeAccountsPayableMetadata(meta)

        case .expenseBook, .expenseBookInvoice:
            let meta = ExpenseBookMetadata(accountName: accountName)
            return LedgerBridge.encodeExpenseBookMetadata(meta)

        case .generalLedger, .generalLedgerInvoice:
            let meta = GeneralLedgerMetadata(
                accountName: accountName,
                accountAttribute: selectedAccountAttribute,
                carryForward: carryForward
            )
            return LedgerBridge.encodeGeneralLedgerMetadata(meta)

        case .fixedAssetDepreciation:
            var meta = FixedAssetDepreciationMetadata()
            meta.fiscalYear = "令和\(Calendar.current.component(.year, from: Date()) - 2018)年分"
            return LedgerBridge.encodeFixedAssetDepreciationMetadata(meta)

        case .fixedAssetRegister:
            var meta = FixedAssetRegisterMetadata()
            meta.assetName = title
            return LedgerBridge.encodeFixedAssetRegisterMetadata(meta)

        case .transportationExpense:
            var meta = TransportationExpenseMetadata()
            meta.year = Calendar.current.component(.year, from: Date())
            return LedgerBridge.encodeTransportationExpenseMetadata(meta)

        case .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice:
            var meta = WhiteTaxBookkeepingMetadata()
            meta.fiscalYear = Calendar.current.component(.year, from: Date())
            return LedgerBridge.encodeWhiteTaxBookkeepingMetadata(meta)

        default:
            return "{}"
        }
    }
}
