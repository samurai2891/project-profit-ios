import Foundation
import SwiftData

struct LedgerPostingCandidateDraft: Sendable, Equatable {
    let sourceLine: Int
    let date: Date
    let memo: String
    let proposedLines: [PostingCandidateLine]
    let counterpartyId: UUID?
}

struct FixedAssetImportDraft: Sendable, Equatable {
    let sourceLine: Int
    let existingAssetId: UUID?
    let input: FixedAssetUpsertInput
}

struct LedgerCSVImportDraftBatch: Sendable, Equatable {
    let candidateDrafts: [LedgerPostingCandidateDraft]
    let fixedAssetDrafts: [FixedAssetImportDraft]
    let lineErrors: [CSVImportLineError]
    let suggestedTaxYear: Int?
}

@MainActor
final class LedgerCSVImportService {
    private let modelContext: ModelContext
    private let chartOfAccountsRepository: any ChartOfAccountsRepository
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        chartOfAccountsRepository: (any ChartOfAccountsRepository)? = nil,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.modelContext = modelContext
        self.chartOfAccountsRepository = chartOfAccountsRepository ?? SwiftDataChartOfAccountsRepository(modelContext: modelContext)
        self.calendar = calendar
    }

    func prepareImport(
        content: String,
        ledgerType: LedgerType,
        metadataJSON: String?,
        snapshot: TransactionFormSnapshot
    ) async throws -> LedgerCSVImportDraftBatch {
        guard let businessId = snapshot.businessId else {
            throw ImportError.missingBusinessProfile
        }

        let rows = CSVImportService.shared.parseCSV(content.replacingOccurrences(of: "\u{FEFF}", with: ""))
        guard let header = detectHeader(in: rows, ledgerType: ledgerType) else {
            throw ImportError.headerNotFound
        }

        let canonicalAccounts = try await chartOfAccountsRepository.findAllByBusiness(businessId: businessId)
        let resolver = AccountResolver(
            canonicalAccounts: canonicalAccounts,
            legacyAccounts: snapshot.accounts
        )
        let yearHint = metadataYearHint(for: ledgerType, metadataJSON: metadataJSON)

        var candidateDrafts: [LedgerPostingCandidateDraft] = []
        var fixedAssetDrafts: [FixedAssetImportDraft] = []
        var lineErrors: [CSVImportLineError] = []
        var suggestedTaxYear = yearHint

        let dataRows = rows.dropFirst(header.rowIndex + 1)
        for (offset, row) in dataRows.enumerated() {
            let sourceLine = header.rowIndex + offset + 2
            guard !row.allSatisfy({ normalizedText($0) == nil }) else {
                continue
            }

            do {
                let mapped = try mapRow(
                    row,
                    sourceLine: sourceLine,
                    headerMap: header.headerMap,
                    ledgerType: ledgerType,
                    metadataJSON: metadataJSON,
                    resolver: resolver,
                    yearHint: yearHint
                )
                candidateDrafts.append(contentsOf: mapped.candidates)
                fixedAssetDrafts.append(contentsOf: mapped.fixedAssets)
                if suggestedTaxYear == nil {
                    suggestedTaxYear = mapped.taxYear
                }
            } catch {
                lineErrors.append(CSVImportLineError(line: sourceLine, reason: error.localizedDescription))
            }
        }

        return LedgerCSVImportDraftBatch(
            candidateDrafts: candidateDrafts,
            fixedAssetDrafts: fixedAssetDrafts,
            lineErrors: lineErrors,
            suggestedTaxYear: suggestedTaxYear
        )
    }

    private func detectHeader(
        in rows: [[String]],
        ledgerType: LedgerType
    ) -> (rowIndex: Int, headerMap: [String: Int])? {
        for (index, row) in rows.enumerated() {
            let headerMap = detectHeaderMapping(row)
            let requiredKeys = requiredHeaderKeys(for: ledgerType)
            guard requiredKeys.allSatisfy({ headerMap[$0] != nil }) else {
                continue
            }
            return (rowIndex: index, headerMap: headerMap)
        }
        return nil
    }

    private func requiredHeaderKeys(for ledgerType: LedgerType) -> [String] {
        switch ledgerType {
        case .cashBook, .cashBookInvoice,
             .bankAccountBook, .bankAccountBookInvoice,
             .accountsReceivable, .accountsPayable,
             .expenseBook, .expenseBookInvoice,
             .generalLedger, .generalLedgerInvoice,
             .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice:
            return ["description"]
        case .journal:
            return ["description", "debitAccount", "creditAccount"]
        case .transportationExpense:
            return ["date", "destination", "amount"]
        case .fixedAssetRegister:
            return ["date", "description"]
        case .fixedAssetDepreciation:
            return ["assetName", "acquisitionDate", "acquisitionCost"]
        }
    }

    private func detectHeaderMapping(_ headers: [String]) -> [String: Int] {
        let jaToKey: [String: String] = [
            "月": "month",
            "日": "day",
            "年月日": "date",
            "日付": "date",
            "摘要": "description",
            "勘定科目": "account",
            "相手科目": "counterAccount",
            "入金": "income",
            "出金": "expense",
            "預入金額": "deposit",
            "引出金額": "withdrawal",
            "金額": "amount",
            "借方": "debit",
            "貸方": "credit",
            "借方科目": "debitAccount",
            "借方金額": "debitAmount",
            "貸方科目": "creditAccount",
            "貸方金額": "creditAmount",
            "数量": "quantity",
            "単価": "unitPrice",
            "売上金額": "salesAmount",
            "入金金額": "receivedAmount",
            "仕入金額": "purchaseAmount",
            "支払金額": "paymentAmount",
            "軽減税率": "reducedTax",
            "インボイス": "invoiceType",
            "行先": "destination",
            "目的": "purpose",
            "目的（用件）": "purpose",
            "交通機関": "transportMethod",
            "交通機関（手段）": "transportMethod",
            "出発地": "routeFrom",
            "区間（起点）": "routeFrom",
            "到着地": "routeTo",
            "区間（終点）": "routeTo",
            "片/往": "tripType",
            "売上": "salesAmount",
            "雑収入": "miscIncome",
            "雑収入等": "miscIncome",
            "仕入": "purchases",
            "給料賃金": "salaries",
            "外注工賃": "outsourcing",
            "減価償却費": "depreciation",
            "貸倒金": "badDebts",
            "地代家賃": "rent",
            "利子割引料": "interestDiscount",
            "租税公課": "taxesDuties",
            "荷造運賃": "packingShipping",
            "水道光熱費": "utilities",
            "旅費交通費": "travelTransport",
            "通信費": "communication",
            "広告宣伝費": "advertising",
            "接待交際費": "entertainment",
            "損害保険料": "insurance",
            "修繕費": "repairs",
            "消耗品費": "supplies",
            "福利厚生費": "welfare",
            "雑費": "miscellaneous",
            "資産コード": "assetCode",
            "資産名": "assetName",
            "資産の種類": "assetType",
            "状態": "status",
            "取得日": "acquisitionDate",
            "取得価額": "acquisitionCost",
            "償却方法": "depreciationMethod",
            "耐用年数": "usefulLife",
            "償却率": "depreciationRate",
            "償却月数": "depreciationMonths",
            "期首帳簿価額": "openingBookValue",
            "期中増減": "midYearChange",
            "事業専用割合": "businessUseRatio",
            "備考": "remarks",
            "取得数量": "acquiredQuantity",
            "取得単価": "acquiredUnitPrice",
            "取得金額": "acquiredAmount",
            "償却額": "depreciationAmount",
            "異動数量": "disposalQuantity",
            "異動金額": "disposalAmount"
        ]

        let enToKey: [String: String] = [
            "month": "month",
            "day": "day",
            "date": "date",
            "description": "description",
            "account": "account",
            "counter_account": "counterAccount",
            "income": "income",
            "expense": "expense",
            "deposit": "deposit",
            "withdrawal": "withdrawal",
            "amount": "amount",
            "debit": "debit",
            "credit": "credit",
            "debit_account": "debitAccount",
            "debit_amount": "debitAmount",
            "credit_account": "creditAccount",
            "credit_amount": "creditAmount",
            "quantity": "quantity",
            "unit_price": "unitPrice",
            "sales_amount": "salesAmount",
            "received_amount": "receivedAmount",
            "purchase_amount": "purchaseAmount",
            "payment_amount": "paymentAmount",
            "destination": "destination",
            "purpose": "purpose",
            "transport_method": "transportMethod",
            "route_from": "routeFrom",
            "route_to": "routeTo",
            "trip_type": "tripType",
            "misc_income": "miscIncome",
            "purchases": "purchases",
            "salaries": "salaries",
            "outsourcing": "outsourcing",
            "depreciation": "depreciation",
            "bad_debts": "badDebts",
            "rent": "rent",
            "interest_discount": "interestDiscount",
            "taxes_duties": "taxesDuties",
            "packing_shipping": "packingShipping",
            "utilities": "utilities",
            "travel_transport": "travelTransport",
            "communication": "communication",
            "advertising": "advertising",
            "entertainment": "entertainment",
            "insurance": "insurance",
            "repairs": "repairs",
            "supplies": "supplies",
            "welfare": "welfare",
            "miscellaneous": "miscellaneous",
            "asset_code": "assetCode",
            "asset_name": "assetName",
            "asset_type": "assetType",
            "status": "status",
            "acquisition_date": "acquisitionDate",
            "acquisition_cost": "acquisitionCost",
            "depreciation_method": "depreciationMethod",
            "useful_life": "usefulLife",
            "depreciation_rate": "depreciationRate",
            "depreciation_months": "depreciationMonths",
            "opening_book_value": "openingBookValue",
            "mid_year_change": "midYearChange",
            "business_use_ratio": "businessUseRatio",
            "remarks": "remarks",
            "acquired_quantity": "acquiredQuantity",
            "acquired_unit_price": "acquiredUnitPrice",
            "acquired_amount": "acquiredAmount",
            "depreciation_amount": "depreciationAmount",
            "disposal_quantity": "disposalQuantity",
            "disposal_amount": "disposalAmount"
        ]

        var map: [String: Int] = [:]
        for (index, header) in headers.enumerated() {
            let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
            if let key = jaToKey[trimmed] {
                map[key] = index
            } else if let key = enToKey[trimmed.lowercased()] {
                map[key] = index
            }
        }
        return map
    }

    private func mapRow(
        _ row: [String],
        sourceLine: Int,
        headerMap: [String: Int],
        ledgerType: LedgerType,
        metadataJSON: String?,
        resolver: AccountResolver,
        yearHint: Int?
    ) throws -> (candidates: [LedgerPostingCandidateDraft], fixedAssets: [FixedAssetImportDraft], taxYear: Int?) {
        let reader = RowReader(row: row, headerMap: headerMap)

        switch ledgerType {
        case .cashBook, .cashBookInvoice:
            return try mapCashLikeRow(
                reader: reader,
                sourceLine: sourceLine,
                mainLegacyAccountId: AccountingConstants.cashAccountId,
                resolver: resolver,
                yearHint: yearHint
            )

        case .bankAccountBook, .bankAccountBookInvoice:
            return try mapCashLikeRow(
                reader: reader,
                sourceLine: sourceLine,
                mainLegacyAccountId: AccountingConstants.bankAccountId,
                resolver: resolver,
                yearHint: yearHint
            )

        case .accountsReceivable:
            return try mapAccountsReceivableRow(
                reader: reader,
                sourceLine: sourceLine,
                resolver: resolver,
                yearHint: yearHint
            )

        case .accountsPayable:
            return try mapAccountsPayableRow(
                reader: reader,
                sourceLine: sourceLine,
                resolver: resolver,
                yearHint: yearHint
            )

        case .expenseBook, .expenseBookInvoice:
            return try mapExpenseBookRow(
                reader: reader,
                sourceLine: sourceLine,
                metadata: LedgerBridge.decodeExpenseBookMetadata(from: metadataJSON ?? "{}"),
                resolver: resolver,
                yearHint: yearHint
            )

        case .generalLedger, .generalLedgerInvoice:
            return try mapGeneralLedgerRow(
                reader: reader,
                sourceLine: sourceLine,
                metadata: LedgerBridge.decodeGeneralLedgerMetadata(from: metadataJSON ?? "{}"),
                resolver: resolver,
                yearHint: yearHint
            )

        case .journal:
            return try mapJournalRow(
                reader: reader,
                sourceLine: sourceLine,
                resolver: resolver,
                yearHint: yearHint
            )

        case .transportationExpense:
            return try mapTransportationExpenseRow(
                reader: reader,
                sourceLine: sourceLine,
                metadata: LedgerBridge.decodeTransportationExpenseMetadata(from: metadataJSON ?? "{}"),
                resolver: resolver
            )

        case .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice:
            return try mapWhiteTaxRow(
                reader: reader,
                sourceLine: sourceLine,
                metadata: LedgerBridge.decodeWhiteTaxBookkeepingMetadata(from: metadataJSON ?? "{}"),
                resolver: resolver
            )

        case .fixedAssetRegister:
            return try mapFixedAssetRegisterRow(
                reader: reader,
                sourceLine: sourceLine,
                metadata: LedgerBridge.decodeFixedAssetRegisterMetadata(from: metadataJSON ?? "{}")
            )

        case .fixedAssetDepreciation:
            return try mapFixedAssetDepreciationRow(
                reader: reader,
                sourceLine: sourceLine
            )
        }
    }

    private func mapCashLikeRow(
        reader: RowReader,
        sourceLine: Int,
        mainLegacyAccountId: String,
        resolver: AccountResolver,
        yearHint: Int?
    ) throws -> (candidates: [LedgerPostingCandidateDraft], fixedAssets: [FixedAssetImportDraft], taxYear: Int?) {
        let description = try reader.required("description", label: "摘要")
        let date = try reader.monthDayDate(yearHint: yearHint, calendar: calendar)
        let mainAccount = try resolver.requiredAccount(
            fallbackLegacyAccountId: mainLegacyAccountId,
            label: "主勘定"
        )
        let counterAccount = resolver.account(
            named: reader.string("account"),
            fallbackLegacyAccountId: AccountingConstants.suspenseAccountId,
            allowSuspenseFallback: true
        )
        guard let counterAccount else {
            throw ImportError.accountResolutionFailed("相手勘定")
        }

        let income = reader.int("income") ?? reader.int("deposit") ?? 0
        let expense = reader.int("expense") ?? reader.int("withdrawal") ?? 0
        guard income > 0 || expense > 0 else {
            throw ImportError.missingAmount
        }
        guard !(income > 0 && expense > 0) else {
            throw ImportError.invalidAmountDirection
        }

        let candidate: LedgerPostingCandidateDraft
        if income > 0 {
            candidate = makeCandidateDraft(
                sourceLine: sourceLine,
                date: date,
                memo: description,
                debit: mainAccount,
                credit: counterAccount,
                amount: income
            )
        } else {
            candidate = makeCandidateDraft(
                sourceLine: sourceLine,
                date: date,
                memo: description,
                debit: counterAccount,
                credit: mainAccount,
                amount: expense
            )
        }

        return ([candidate], [], fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth))
    }

    private func mapAccountsReceivableRow(
        reader: RowReader,
        sourceLine: Int,
        resolver: AccountResolver,
        yearHint: Int?
    ) throws -> (candidates: [LedgerPostingCandidateDraft], fixedAssets: [FixedAssetImportDraft], taxYear: Int?) {
        let description = try reader.required("description", label: "摘要")
        let date = try reader.monthDayDate(yearHint: yearHint, calendar: calendar)
        let arAccount = try resolver.requiredAccount(
            fallbackLegacyAccountId: AccountingConstants.accountsReceivableAccountId,
            label: "売掛金"
        )

        var drafts: [LedgerPostingCandidateDraft] = []
        let salesAmount = reader.int("salesAmount") ?? 0
        if salesAmount > 0 {
            let creditAccount = resolver.account(
                named: reader.string("counterAccount"),
                fallbackLegacyAccountId: AccountingConstants.salesAccountId,
                allowSuspenseFallback: true
            )
            guard let creditAccount else {
                throw ImportError.accountResolutionFailed("売上相手勘定")
            }
            drafts.append(
                makeCandidateDraft(
                    sourceLine: sourceLine,
                    date: date,
                    memo: description,
                    debit: arAccount,
                    credit: creditAccount,
                    amount: salesAmount
                )
            )
        }

        let receivedAmount = reader.int("receivedAmount") ?? 0
        if receivedAmount > 0 {
            let debitAccount = resolver.account(
                named: reader.string("counterAccount"),
                fallbackLegacyAccountId: AccountingConstants.cashAccountId,
                allowSuspenseFallback: true
            )
            guard let debitAccount else {
                throw ImportError.accountResolutionFailed("入金相手勘定")
            }
            drafts.append(
                makeCandidateDraft(
                    sourceLine: sourceLine,
                    date: date,
                    memo: description,
                    debit: debitAccount,
                    credit: arAccount,
                    amount: receivedAmount
                )
            )
        }

        guard !drafts.isEmpty else {
            throw ImportError.missingAmount
        }

        return (drafts, [], fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth))
    }

    private func mapAccountsPayableRow(
        reader: RowReader,
        sourceLine: Int,
        resolver: AccountResolver,
        yearHint: Int?
    ) throws -> (candidates: [LedgerPostingCandidateDraft], fixedAssets: [FixedAssetImportDraft], taxYear: Int?) {
        let description = try reader.required("description", label: "摘要")
        let date = try reader.monthDayDate(yearHint: yearHint, calendar: calendar)
        let apAccount = try resolver.requiredAccount(
            fallbackLegacyAccountId: AccountingConstants.accountsPayableAccountId,
            label: "買掛金"
        )

        var drafts: [LedgerPostingCandidateDraft] = []
        let purchaseAmount = reader.int("purchaseAmount") ?? 0
        if purchaseAmount > 0 {
            let debitAccount = resolver.account(
                named: reader.string("counterAccount"),
                fallbackLegacyAccountId: AccountingConstants.purchasesAccountId,
                allowSuspenseFallback: true
            )
            guard let debitAccount else {
                throw ImportError.accountResolutionFailed("仕入相手勘定")
            }
            drafts.append(
                makeCandidateDraft(
                    sourceLine: sourceLine,
                    date: date,
                    memo: description,
                    debit: debitAccount,
                    credit: apAccount,
                    amount: purchaseAmount
                )
            )
        }

        let paymentAmount = reader.int("paymentAmount") ?? 0
        if paymentAmount > 0 {
            let creditAccount = resolver.account(
                named: reader.string("counterAccount"),
                fallbackLegacyAccountId: AccountingConstants.cashAccountId,
                allowSuspenseFallback: true
            )
            guard let creditAccount else {
                throw ImportError.accountResolutionFailed("支払相手勘定")
            }
            drafts.append(
                makeCandidateDraft(
                    sourceLine: sourceLine,
                    date: date,
                    memo: description,
                    debit: apAccount,
                    credit: creditAccount,
                    amount: paymentAmount
                )
            )
        }

        guard !drafts.isEmpty else {
            throw ImportError.missingAmount
        }

        return (drafts, [], fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth))
    }

    private func mapExpenseBookRow(
        reader: RowReader,
        sourceLine: Int,
        metadata: ExpenseBookMetadata,
        resolver: AccountResolver,
        yearHint: Int?
    ) throws -> (candidates: [LedgerPostingCandidateDraft], fixedAssets: [FixedAssetImportDraft], taxYear: Int?) {
        let description = try reader.required("description", label: "摘要")
        let amount = try reader.requiredInt("amount", label: "金額")
        let date = try reader.monthDayDate(yearHint: yearHint, calendar: calendar)
        let debitAccount = resolver.account(
            named: metadata.accountName,
            fallbackLegacyAccountId: AccountingConstants.suspenseAccountId,
            allowSuspenseFallback: true
        )
        let creditAccount = resolver.account(
            named: reader.string("counterAccount"),
            fallbackLegacyAccountId: AccountingConstants.suspenseAccountId,
            allowSuspenseFallback: true
        )
        guard let debitAccount, let creditAccount else {
            throw ImportError.accountResolutionFailed("経費帳勘定")
        }

        let draft = makeCandidateDraft(
            sourceLine: sourceLine,
            date: date,
            memo: description,
            debit: debitAccount,
            credit: creditAccount,
            amount: amount
        )
        return ([draft], [], fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth))
    }

    private func mapGeneralLedgerRow(
        reader: RowReader,
        sourceLine: Int,
        metadata: GeneralLedgerMetadata,
        resolver: AccountResolver,
        yearHint: Int?
    ) throws -> (candidates: [LedgerPostingCandidateDraft], fixedAssets: [FixedAssetImportDraft], taxYear: Int?) {
        let description = try reader.required("description", label: "摘要")
        let date = try reader.monthDayDate(yearHint: yearHint, calendar: calendar)
        let primaryAccount = resolver.account(
            named: metadata.accountName,
            fallbackLegacyAccountId: AccountingConstants.suspenseAccountId,
            allowSuspenseFallback: true
        )
        let counterAccount = resolver.account(
            named: reader.string("counterAccount"),
            fallbackLegacyAccountId: AccountingConstants.suspenseAccountId,
            allowSuspenseFallback: true
        )
        guard let primaryAccount, let counterAccount else {
            throw ImportError.accountResolutionFailed("総勘定元帳勘定")
        }

        let debit = reader.int("debit") ?? 0
        let credit = reader.int("credit") ?? 0
        guard debit > 0 || credit > 0 else {
            throw ImportError.missingAmount
        }
        guard !(debit > 0 && credit > 0) else {
            throw ImportError.invalidAmountDirection
        }

        let draft: LedgerPostingCandidateDraft
        if debit > 0 {
            draft = makeCandidateDraft(
                sourceLine: sourceLine,
                date: date,
                memo: description,
                debit: primaryAccount,
                credit: counterAccount,
                amount: debit
            )
        } else {
            draft = makeCandidateDraft(
                sourceLine: sourceLine,
                date: date,
                memo: description,
                debit: counterAccount,
                credit: primaryAccount,
                amount: credit
            )
        }

        return ([draft], [], fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth))
    }

    private func mapJournalRow(
        reader: RowReader,
        sourceLine: Int,
        resolver: AccountResolver,
        yearHint: Int?
    ) throws -> (candidates: [LedgerPostingCandidateDraft], fixedAssets: [FixedAssetImportDraft], taxYear: Int?) {
        let description = try reader.required("description", label: "摘要")
        let date = try reader.monthDayDate(yearHint: yearHint, calendar: calendar)
        let debitName = try reader.required("debitAccount", label: "借方科目")
        let creditName = try reader.required("creditAccount", label: "貸方科目")
        let debitAmount = try reader.requiredInt("debitAmount", label: "借方金額")
        let creditAmount = try reader.requiredInt("creditAmount", label: "貸方金額")
        guard debitAmount == creditAmount else {
            throw ImportError.unbalancedJournal
        }

        guard let debitAccount = resolver.account(named: debitName, fallbackLegacyAccountId: nil, allowSuspenseFallback: false),
              let creditAccount = resolver.account(named: creditName, fallbackLegacyAccountId: nil, allowSuspenseFallback: false)
        else {
            throw ImportError.accountResolutionFailed("仕訳帳勘定")
        }

        let draft = makeCandidateDraft(
            sourceLine: sourceLine,
            date: date,
            memo: description,
            debit: debitAccount,
            credit: creditAccount,
            amount: debitAmount
        )
        return ([draft], [], fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth))
    }

    private func mapTransportationExpenseRow(
        reader: RowReader,
        sourceLine: Int,
        metadata: TransportationExpenseMetadata,
        resolver: AccountResolver
    ) throws -> (candidates: [LedgerPostingCandidateDraft], fixedAssets: [FixedAssetImportDraft], taxYear: Int?) {
        let destination = try reader.required("destination", label: "行先")
        let purpose = try reader.required("purpose", label: "目的")
        let amount = try reader.requiredInt("amount", label: "金額")
        let date = try reader.fullDate("date", calendar: calendar, fallbackYear: metadata.year)
        let debitAccount = try resolver.requiredAccount(
            fallbackLegacyAccountId: AccountingConstants.defaultAccounts.first(where: { $0.name == "旅費交通費" })?.id
                ?? "acct-travel",
            label: "旅費交通費"
        )
        let creditAccount = try resolver.requiredAccount(
            fallbackLegacyAccountId: AccountingConstants.suspenseAccountId,
            label: "仮勘定"
        )

        let memo = [destination, purpose, reader.string("routeFrom"), reader.string("routeTo")]
            .compactMap(normalizedText)
            .joined(separator: " / ")
        let draft = makeCandidateDraft(
            sourceLine: sourceLine,
            date: date,
            memo: memo,
            debit: debitAccount,
            credit: creditAccount,
            amount: amount
        )
        return ([draft], [], fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth))
    }

    private func mapWhiteTaxRow(
        reader: RowReader,
        sourceLine: Int,
        metadata: WhiteTaxBookkeepingMetadata,
        resolver: AccountResolver
    ) throws -> (candidates: [LedgerPostingCandidateDraft], fixedAssets: [FixedAssetImportDraft], taxYear: Int?) {
        let description = try reader.required("description", label: "摘要")
        let date = try reader.monthDayDate(yearHint: metadata.fiscalYear, calendar: calendar)
        let suspense = try resolver.requiredAccount(
            fallbackLegacyAccountId: AccountingConstants.suspenseAccountId,
            label: "仮勘定"
        )

        let mappings: [(String, String?, String?, Bool)] = [
            ("salesAmount", "売上高", AccountingConstants.salesAccountId, true),
            ("miscIncome", "雑収入", AccountingConstants.otherIncomeAccountId, true),
            ("purchases", "仕入高", AccountingConstants.purchasesAccountId, false),
            ("salaries", "給料賃金", nil, false),
            ("outsourcing", "外注工賃", "acct-outsourcing", false),
            ("depreciation", "減価償却費", AccountingConstants.depreciationExpenseAccountId, false),
            ("badDebts", "貸倒金", nil, false),
            ("rent", "地代家賃", "acct-rent", false),
            ("interestDiscount", "利子割引料", "acct-repair", false),
            ("taxesDuties", "租税公課", "acct-welfare", false),
            ("packingShipping", "荷造運賃", nil, false),
            ("utilities", "水道光熱費", "acct-utilities", false),
            ("travelTransport", "旅費交通費", "acct-travel", false),
            ("communication", "通信費", "acct-communication", false),
            ("advertising", "広告宣伝費", "acct-advertising", false),
            ("entertainment", "接待交際費", "acct-entertainment", false),
            ("insurance", "損害保険料", "acct-insurance", false),
            ("repairs", "修繕費", nil, false),
            ("supplies", "消耗品費", "acct-supplies", false),
            ("welfare", "福利厚生費", nil, false),
            ("miscellaneous", "雑費", "acct-misc", false)
        ]

        var drafts: [LedgerPostingCandidateDraft] = []
        for (key, accountName, fallbackLegacyId, isRevenue) in mappings {
            guard let amount = reader.int(key), amount > 0 else {
                continue
            }

            let resolvedAccount = resolver.account(
                named: accountName,
                fallbackLegacyAccountId: fallbackLegacyId,
                allowSuspenseFallback: true
            ) ?? suspense

            let draft: LedgerPostingCandidateDraft
            if isRevenue {
                draft = makeCandidateDraft(
                    sourceLine: sourceLine,
                    date: date,
                    memo: "\(description) / \(accountName ?? key)",
                    debit: suspense,
                    credit: resolvedAccount,
                    amount: amount
                )
            } else {
                draft = makeCandidateDraft(
                    sourceLine: sourceLine,
                    date: date,
                    memo: "\(description) / \(accountName ?? key)",
                    debit: resolvedAccount,
                    credit: suspense,
                    amount: amount
                )
            }
            drafts.append(draft)
        }

        guard !drafts.isEmpty else {
            throw ImportError.missingAmount
        }

        return (drafts, [], fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth))
    }

    private func mapFixedAssetRegisterRow(
        reader: RowReader,
        sourceLine: Int,
        metadata: FixedAssetRegisterMetadata
    ) throws -> (candidates: [LedgerPostingCandidateDraft], fixedAssets: [FixedAssetImportDraft], taxYear: Int?) {
        let assetName = normalizedText(metadata.assetName) ?? normalizedText(reader.string("description")) ?? {
            ""
        }()
        guard !assetName.isEmpty else {
            throw ImportError.missingField("名称")
        }

        let acquisitionDate = try fixedAssetRegisterDate(
            rowDate: reader.string("date"),
            metadataDate: metadata.acquisitionDate
        )
        let acquisitionCost = try reader.requiredInt("acquiredAmount", label: "取得金額")
        let usefulLife = max(metadata.usefulLife, 1)
        let method = try depreciationMethod(from: metadata.depreciationMethod)
        let businessUsePercent = businessUsePercent(from: reader.double("businessUseRatio"))
        let existingAssetId = existingFixedAssetId(named: assetName)

        let input = FixedAssetUpsertInput(
            name: assetName,
            acquisitionDate: acquisitionDate,
            acquisitionCost: acquisitionCost,
            usefulLifeYears: usefulLife,
            depreciationMethod: method,
            salvageValue: 1,
            businessUsePercent: businessUsePercent,
            memo: normalizedText(reader.string("remarks"))
        )
        let draft = FixedAssetImportDraft(
            sourceLine: sourceLine,
            existingAssetId: existingAssetId,
            input: input
        )
        return ([], [draft], fiscalYear(for: acquisitionDate, startMonth: FiscalYearSettings.startMonth))
    }

    private func mapFixedAssetDepreciationRow(
        reader: RowReader,
        sourceLine: Int
    ) throws -> (candidates: [LedgerPostingCandidateDraft], fixedAssets: [FixedAssetImportDraft], taxYear: Int?) {
        let assetName = try reader.required("assetName", label: "資産名")
        let acquisitionDate = try parseDateString(try reader.required("acquisitionDate", label: "取得日"))
        let acquisitionCost = try reader.requiredInt("acquisitionCost", label: "取得価額")
        let usefulLife = try reader.requiredInt("usefulLife", label: "耐用年数")
        let method = try depreciationMethod(from: try reader.required("depreciationMethod", label: "償却方法"))
        let businessUsePercent = businessUsePercent(from: reader.double("businessUseRatio"))
        let existingAssetId = existingFixedAssetId(named: assetName)

        let input = FixedAssetUpsertInput(
            name: assetName,
            acquisitionDate: acquisitionDate,
            acquisitionCost: acquisitionCost,
            usefulLifeYears: usefulLife,
            depreciationMethod: method,
            salvageValue: 1,
            businessUsePercent: businessUsePercent,
            memo: normalizedText(reader.string("remarks"))
        )
        let draft = FixedAssetImportDraft(
            sourceLine: sourceLine,
            existingAssetId: existingAssetId,
            input: input
        )
        return ([], [draft], fiscalYear(for: acquisitionDate, startMonth: FiscalYearSettings.startMonth))
    }

    private func makeCandidateDraft(
        sourceLine: Int,
        date: Date,
        memo: String,
        debit: CanonicalAccount,
        credit: CanonicalAccount,
        amount: Int
    ) -> LedgerPostingCandidateDraft {
        LedgerPostingCandidateDraft(
            sourceLine: sourceLine,
            date: date,
            memo: memo,
            proposedLines: [
                PostingCandidateLine(
                    debitAccountId: debit.id,
                    creditAccountId: credit.id,
                    amount: Decimal(amount),
                    taxCodeId: nil,
                    legalReportLineId: debit.defaultLegalReportLineId ?? credit.defaultLegalReportLineId,
                    projectAllocationId: nil,
                    memo: memo
                )
            ],
            counterpartyId: nil
        )
    }

    private func metadataYearHint(for ledgerType: LedgerType, metadataJSON: String?) -> Int? {
        switch ledgerType {
        case .transportationExpense:
            return LedgerBridge.decodeTransportationExpenseMetadata(from: metadataJSON ?? "{}").year
        case .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice:
            return LedgerBridge.decodeWhiteTaxBookkeepingMetadata(from: metadataJSON ?? "{}").fiscalYear
        default:
            return nil
        }
    }

    private func depreciationMethod(from value: String) throws -> PPDepreciationMethod {
        switch normalizedText(value) {
        case "定率法":
            return .decliningBalance
        case "定額法", nil:
            return .straightLine
        default:
            throw ImportError.invalidDepreciationMethod
        }
    }

    private func fixedAssetRegisterDate(rowDate: String, metadataDate: String) throws -> Date {
        if let normalized = normalizedText(rowDate) {
            return try parseDateString(normalized)
        }
        if let normalized = normalizedText(metadataDate) {
            return try parseDateString(normalized)
        }
        throw ImportError.invalidDate("取得年月日")
    }

    private func parseDateString(_ value: String) throws -> Date {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.M.d", "yyyy.M.d.", "yyyy年M月d日"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP_POSIX")

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        throw ImportError.invalidDate(trimmed)
    }

    private func businessUsePercent(from ratio: Double?) -> Int {
        guard let ratio else { return 100 }
        if ratio <= 1 {
            return min(100, max(0, Int((ratio * 100).rounded())))
        }
        return min(100, max(0, Int(ratio.rounded())))
    }

    private func existingFixedAssetId(named name: String) -> UUID? {
        let descriptor = FetchDescriptor<PPFixedAsset>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try? modelContext.fetch(descriptor)
            .first(where: {
                normalizeAccountName($0.name) == normalizeAccountName(name)
            })?.id
    }

    private func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizeAccountName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private struct RowReader {
        let row: [String]
        let headerMap: [String: Int]

        func string(_ key: String) -> String {
            guard let index = headerMap[key], index < row.count else {
                return ""
            }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func required(_ key: String, label: String) throws -> String {
            guard let value = normalizedText(string(key)) else {
                throw ImportError.missingField(label)
            }
            return value
        }

        func int(_ key: String) -> Int? {
            guard let value = normalizedText(string(key)) else { return nil }
            let cleaned = value
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "円", with: "")
                .replacingOccurrences(of: "%", with: "")
            return Int(cleaned)
        }

        func requiredInt(_ key: String, label: String) throws -> Int {
            guard let value = int(key), value > 0 else {
                throw ImportError.missingField(label)
            }
            return value
        }

        func double(_ key: String) -> Double? {
            guard let value = normalizedText(string(key)) else { return nil }
            let cleaned = value
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "%", with: "")
            return Double(cleaned)
        }

        func monthDayDate(yearHint: Int?, calendar: Calendar) throws -> Date {
            let month = int("month") ?? 1
            let day = int("day") ?? 1
            let year = yearHint ?? calendar.component(.year, from: Date())
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
                throw ImportError.invalidDate("月/日")
            }
            return date
        }

        func fullDate(_ key: String, calendar: Calendar, fallbackYear: Int?) throws -> Date {
            let rawValue = try required(key, label: "日付")
            if rawValue.contains("-") || rawValue.contains("/") || rawValue.contains("年") || rawValue.contains(".") {
                return try LedgerCSVImportService.parseDateStatic(rawValue)
            }

            let parts = rawValue.split(separator: "/", omittingEmptySubsequences: true)
            if parts.count == 2,
               let month = Int(parts[0]),
               let day = Int(parts[1]),
               let year = fallbackYear ?? calendar.dateComponents([.year], from: Date()).year,
               let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
                return date
            }
            return try LedgerCSVImportService.parseDateStatic(rawValue)
        }

        private func normalizedText(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private struct AccountResolver {
        private let canonicalByNormalizedName: [String: CanonicalAccount]
        private let canonicalByLegacyId: [String: CanonicalAccount]
        private let legacyByNormalizedName: [String: PPAccount]

        init(canonicalAccounts: [CanonicalAccount], legacyAccounts: [PPAccount]) {
            self.canonicalByNormalizedName = Dictionary(
                uniqueKeysWithValues: canonicalAccounts.map {
                    (
                        Self.normalize($0.name),
                        $0
                    )
                }
            )
            self.canonicalByLegacyId = Dictionary(
                uniqueKeysWithValues: canonicalAccounts.compactMap { account in
                    guard let legacyAccountId = account.legacyAccountId else { return nil }
                    return (legacyAccountId, account)
                }
            )
            self.legacyByNormalizedName = Dictionary(
                uniqueKeysWithValues: legacyAccounts.map {
                    (
                        Self.normalize($0.name),
                        $0
                    )
                }
            )
        }

        func account(
            named rawName: String?,
            fallbackLegacyAccountId: String?,
            allowSuspenseFallback: Bool
        ) -> CanonicalAccount? {
            if let rawName,
               let normalizedName = normalized(rawName) {
                if let exact = canonicalByNormalizedName[normalizedName] {
                    return exact
                }
                if let legacyAccount = legacyByNormalizedName[normalizedName],
                   let mapped = canonicalByLegacyId[legacyAccount.id] {
                    return mapped
                }
                if let defaultDefinition = AccountingConstants.defaultAccounts.first(where: {
                    Self.normalize($0.name) == normalizedName
                }),
                   let mapped = canonicalByLegacyId[defaultDefinition.id] {
                    return mapped
                }
            }

            if let fallbackLegacyAccountId,
               let mapped = canonicalByLegacyId[fallbackLegacyAccountId] {
                return mapped
            }

            if allowSuspenseFallback {
                return canonicalByLegacyId[AccountingConstants.suspenseAccountId]
            }

            return nil
        }

        func requiredAccount(
            fallbackLegacyAccountId: String?,
            label: String
        ) throws -> CanonicalAccount {
            guard let account = account(
                named: nil,
                fallbackLegacyAccountId: fallbackLegacyAccountId,
                allowSuspenseFallback: false
            ) else {
                throw ImportError.accountResolutionFailed(label)
            }
            return account
        }

        private func normalized(_ value: String) -> String? {
            let normalized = Self.normalize(value)
            return normalized.isEmpty ? nil : normalized
        }

        private static func normalize(_ value: String) -> String {
            value
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }
    }

    enum ImportError: LocalizedError {
        case missingBusinessProfile
        case headerNotFound
        case missingField(String)
        case missingAmount
        case invalidAmountDirection
        case invalidDate(String)
        case invalidDepreciationMethod
        case unbalancedJournal
        case accountResolutionFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingBusinessProfile:
                return "事業者プロフィールが未設定のため CSV を取り込めません"
            case .headerNotFound:
                return "有効なヘッダー行が見つかりません"
            case .missingField(let field):
                return "必須フィールド「\(field)」が空です"
            case .missingAmount:
                return "金額列が見つかりません"
            case .invalidAmountDirection:
                return "借方/貸方または入出金の指定が不正です"
            case .invalidDate(let value):
                return "日付を解釈できません: \(value)"
            case .invalidDepreciationMethod:
                return "償却方法が不正です"
            case .unbalancedJournal:
                return "借方金額と貸方金額が一致しません"
            case .accountResolutionFailed(let label):
                return "\(label)を canonical account に解決できません"
            }
        }
    }

    nonisolated private static func parseDateStatic(_ value: String) throws -> Date {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP_POSIX")
        for format in ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.M.d", "yyyy.M.d.", "yyyy年M月d日"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        throw ImportError.invalidDate(trimmed)
    }
}
