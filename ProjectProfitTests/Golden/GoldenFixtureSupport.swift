import Foundation
import PDFKit
import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
struct GoldenScenario {
    let container: ModelContainer
    let context: ModelContext
    let dataStore: ProjectProfit.DataStore
    let fixture: GoldenFixture
    let businessProfile: BusinessProfile
    let taxYearProfile: TaxYearProfile
}

@MainActor
struct GoldenFixtureLoader {
    static func load(testCase: XCTestCase) throws -> GoldenFixture {
        let bundle = Bundle(for: type(of: testCase))
        let url = bundle.url(
            forResource: "baseline_fiscal_year_2025",
            withExtension: "json",
            subdirectory: "Golden/fixtures"
        ) ?? bundle.url(
            forResource: "baseline_fiscal_year_2025",
            withExtension: "json"
        )
        XCTAssertNotNil(url, "Golden fixture should be bundled with the test target")
        let data = try Data(contentsOf: try XCTUnwrap(url))
        return try GoldenSnapshotStore.decoder.decode(GoldenFixture.self, from: data)
    }

    static func makeScenario(testCase: XCTestCase) async throws -> GoldenScenario {
        let fixture = try load(testCase: testCase)
        let container = try TestModelContainer.create()
        let context = ModelContext(container)
        let dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()

        try await applyFixtureMetadata(fixture, to: dataStore, context: context)
        try applyAccounts(fixture.accounts, to: dataStore, context: context)
        try applyCategories(fixture.categories, to: dataStore, context: context)
        let projectMap = try applyProjects(fixture.projects, to: dataStore)
        try await applyTransactions(fixture.transactions, projectMap: projectMap, to: dataStore)
        try await applyFixtureYearLockState(fixture, context: context)
        dataStore.loadData()

        let businessProfile = try XCTUnwrap(dataStore.businessProfile)
        let taxYearProfileCandidate = try await SwiftDataTaxYearProfileRepository(modelContext: context).findByBusinessAndYear(
            businessId: businessProfile.id,
            taxYear: fixture.businessProfile.fiscalYear
        )
        let taxYearProfile = try XCTUnwrap(taxYearProfileCandidate)
        XCTAssertEqual(taxYearProfile.yearLockState, .taxClose)
        return GoldenScenario(
            container: container,
            context: context,
            dataStore: dataStore,
            fixture: fixture,
            businessProfile: businessProfile,
            taxYearProfile: taxYearProfile
        )
    }

    private static func applyFixtureMetadata(
        _ fixture: GoldenFixture,
        to dataStore: ProjectProfit.DataStore,
        context: ModelContext
    ) async throws {
        let useCase = ProfileSettingsUseCase(modelContext: context)
        let state = try await useCase.load(
            defaultTaxYear: fixture.businessProfile.fiscalYear,
            sensitivePayload: dataStore.profileSensitivePayload
        )
        let command = SaveProfileSettingsCommand(
            ownerName: fixture.businessProfile.ownerName,
            ownerNameKana: fixture.businessProfile.ownerNameKana,
            businessName: fixture.businessProfile.businessName,
            businessAddress: fixture.businessProfile.address,
            postalCode: fixture.businessProfile.postalCode,
            phoneNumber: fixture.businessProfile.phoneNumber,
            openingDate: state.businessProfile.openingDate,
            taxOfficeCode: fixture.businessProfile.taxOfficeCode,
            filingStyle: fixture.businessProfile.isBlueReturn ? .blueGeneral : .white,
            blueDeductionLevel: state.taxYearProfile.blueDeductionLevel,
            bookkeepingBasis: state.taxYearProfile.bookkeepingBasis,
            vatStatus: state.taxYearProfile.vatStatus,
            vatMethod: state.taxYearProfile.vatMethod,
            simplifiedBusinessCategory: state.taxYearProfile.simplifiedBusinessCategory,
            invoiceIssuerStatusAtYear: state.taxYearProfile.invoiceIssuerStatusAtYear,
            electronicBookLevel: state.taxYearProfile.electronicBookLevel,
            yearLockState: state.taxYearProfile.yearLockState,
            taxYear: fixture.businessProfile.fiscalYear
        )
        _ = try await useCase.save(command: command, currentState: state)
        dataStore.loadData()
    }

    private static func applyFixtureYearLockState(
        _ fixture: GoldenFixture,
        context: ModelContext
    ) async throws {
        let fiscalYear = fixture.businessProfile.fiscalYear
        let businessProfile = try XCTUnwrap(
            try await SwiftDataBusinessProfileRepository(modelContext: context).findDefault(),
            "Golden fixture should create a canonical business profile before year lock setup"
        )
        let descriptor = FetchDescriptor<TaxYearProfileEntity>(
            predicate: #Predicate {
                $0.businessId == businessProfile.id && $0.taxYear == fiscalYear
            }
        )
        let entity = try XCTUnwrap(
            try context.fetch(descriptor).first,
            "Golden fixture should create a tax year profile before year lock setup"
        )
        // Golden fixtures replay a known snapshot and intentionally bypass closing preflight.
        entity.yearLockStateRaw = YearLockState.taxClose.rawValue
        entity.updatedAt = Date()
        try context.save()
    }

    private static func applyAccounts(
        _ fixtureAccounts: [GoldenAccount],
        to dataStore: ProjectProfit.DataStore,
        context: ModelContext
    ) throws {
        for fixtureAccount in fixtureAccounts {
            if let existing = dataStore.accounts.first(where: { $0.id == fixtureAccount.id }) {
                existing.code = fixtureAccount.code
                existing.name = fixtureAccount.name
                existing.accountType = accountType(from: fixtureAccount.accountType)
            } else {
                context.insert(
                    PPAccount(
                        id: fixtureAccount.id,
                        code: fixtureAccount.code,
                        name: fixtureAccount.name,
                        accountType: accountType(from: fixtureAccount.accountType)
                    )
                )
            }
        }
        try context.save()
    }

    private static func applyCategories(
        _ fixtureCategories: [GoldenCategory],
        to dataStore: ProjectProfit.DataStore,
        context: ModelContext
    ) throws {
        for fixtureCategory in fixtureCategories {
            if let existing = dataStore.categories.first(where: { $0.id == fixtureCategory.id }) {
                existing.name = fixtureCategory.name
                existing.type = categoryType(from: fixtureCategory.type)
            } else {
                context.insert(
                    PPCategory(
                        id: fixtureCategory.id,
                        name: fixtureCategory.name,
                        type: categoryType(from: fixtureCategory.type),
                        icon: "tag"
                    )
                )
            }
        }
        try context.save()
    }

    private static func applyProjects(_ fixtureProjects: [GoldenProject], to dataStore: ProjectProfit.DataStore) throws -> [String: UUID] {
        var projectMap: [String: UUID] = [:]
        let dateFormatter = GoldenSnapshotStore.dateFormatter

        for fixtureProject in fixtureProjects {
            let startDate = fixtureProject.startDate.flatMap { dateFormatter.date(from: $0) }
            let completedAt = fixtureProject.completedAt.flatMap { dateFormatter.date(from: $0) }
            let project = mutations(dataStore).addProject(
                name: fixtureProject.name,
                description: fixtureProject.name,
                startDate: startDate,
                plannedEndDate: completedAt
            )
            let status = projectStatus(from: fixtureProject.status)
            mutations(dataStore).updateProject(
                id: project.id,
                status: status,
                startDate: .some(startDate),
                completedAt: .some(completedAt)
            )
            projectMap[fixtureProject.id] = project.id
        }

        return projectMap
    }

    private static func applyTransactions(
        _ fixtureTransactions: [GoldenTransaction],
        projectMap: [String: UUID],
        to dataStore: ProjectProfit.DataStore
    ) async throws {
        for fixtureTransaction in fixtureTransactions {
            let allocations = (fixtureTransaction.allocations ?? []).compactMap { allocation -> (UUID, Int)? in
                guard let projectId = projectMap[allocation.projectId] else {
                    return nil
                }
                return (projectId, allocation.ratio)
            }
            let date = try XCTUnwrap(GoldenSnapshotStore.dateFormatter.date(from: fixtureTransaction.date))
            let transaction = mutations(dataStore).addTransaction(
                type: transactionType(from: fixtureTransaction.type),
                amount: fixtureTransaction.amount,
                date: date,
                categoryId: fixtureTransaction.categoryId,
                memo: fixtureTransaction.memo,
                allocations: allocations,
                paymentAccountId: inferredPaymentAccountId(for: fixtureTransaction),
                transferToAccountId: inferredTransferAccountId(for: fixtureTransaction),
                taxRate: fixtureTransaction.taxRate,
                isTaxIncluded: fixtureTransaction.isTaxIncluded,
                counterparty: fixtureTransaction.counterparty,
                candidateSource: .manual
            )
            XCTAssertNotNil(transaction.journalEntryId)
        }
    }

    private static func inferredPaymentAccountId(for transaction: GoldenTransaction) -> String? {
        switch transaction.type {
        case "income":
            return transaction.counterparty == nil ? AccountingConstants.cashAccountId : AccountingConstants.accountsReceivableAccountId
        case "expense":
            return AccountingConstants.cashAccountId
        case "transfer":
            return AccountingConstants.bankAccountId
        default:
            return nil
        }
    }

    private static func inferredTransferAccountId(for transaction: GoldenTransaction) -> String? {
        transaction.type == "transfer" ? AccountingConstants.cashAccountId : nil
    }

    private static func accountType(from rawValue: String) -> AccountType {
        switch rawValue {
        case "asset":
            return .asset
        case "liability":
            return .liability
        case "equity":
            return .equity
        case "revenue":
            return .revenue
        default:
            return .expense
        }
    }

    private static func transactionType(from rawValue: String) -> TransactionType {
        switch rawValue {
        case "income":
            return .income
        case "transfer":
            return .transfer
        default:
            return .expense
        }
    }

    private static func categoryType(from rawValue: String) -> CategoryType {
        rawValue == "income" ? .income : .expense
    }

    private static func projectStatus(from rawValue: String) -> ProjectStatus {
        switch rawValue {
        case "completed":
            return .completed
        case "paused":
            return .paused
        default:
            return .active
        }
    }
}

struct GoldenJournalBookSnapshot: Codable, Equatable {
    let fiscalYear: Int
    let entries: [GoldenJournalEntrySnapshot]
}

struct GoldenJournalEntrySnapshot: Codable, Equatable {
    let date: String
    let entryType: String
    let memo: String
    let isPosted: Bool
    let lines: [GoldenJournalLineSnapshot]
}

struct GoldenJournalLineSnapshot: Codable, Equatable {
    let accountId: String
    let debit: Int
    let credit: Int
    let displayOrder: Int
}

struct GoldenTrialBalanceSnapshot: Codable, Equatable {
    let fiscalYear: Int
    let debitTotal: Int
    let creditTotal: Int
    let isBalanced: Bool
    let rows: [GoldenTrialBalanceRowSnapshot]
}

struct GoldenTrialBalanceRowSnapshot: Codable, Equatable {
    let code: String
    let name: String
    let accountType: String
    let debit: Int
    let credit: Int
    let balance: Int
}

struct GoldenEtaxFormSnapshot: Codable, Equatable {
    let fiscalYear: Int
    let formType: String
    let totalRevenue: Int
    let totalExpenses: Int
    let netIncome: Int
    let fields: [GoldenEtaxFieldSnapshot]
}

struct GoldenEtaxFieldSnapshot: Codable, Equatable {
    let id: String
    let fieldLabel: String
    let section: String
    let taxLine: String?
    let valueType: String
    let value: String
}

struct GoldenConsumptionTaxWorksheetSnapshot: Codable, Equatable {
    let fiscalYear: Int
    let outputTaxTotal: Int
    let rawInputTaxTotal: Int
    let deductibleInputTaxTotal: Int
    let taxPayable: Int
    let lines: [GoldenConsumptionTaxWorksheetLineSnapshot]
}

struct GoldenConsumptionTaxWorksheetLineSnapshot: Codable, Equatable {
    let journalDate: String
    let direction: String
    let taxCode: String
    let accountId: String
    let counterpartyName: String?
    let taxableAmount: Int
    let taxAmount: Int
    let deductibleTaxAmount: Int
    let purchaseCreditMethod: String?
    let totalRate: String
    let nationalRate: String
    let localRate: String
}

struct GoldenMigrationReportSnapshot: Codable, Equatable {
    let deltas: [GoldenMigrationDeltaSnapshot]
    let orphanRecords: [GoldenMigrationOrphanSnapshot]
    let warnings: [String]
}

struct GoldenMigrationDeltaSnapshot: Codable, Equatable {
    let modelName: String
    let legacyCount: Int
    let canonicalCount: Int
    let executeSupported: Bool
}

struct GoldenMigrationOrphanSnapshot: Codable, Equatable {
    let area: String
    let identifier: String
    let message: String
}

struct GoldenLedgerExportSnapshot: Codable, Equatable {
    let fiscalYear: Int
    let ledgers: [GoldenLedgerArtifactSnapshot]
}

struct GoldenLedgerArtifactSnapshot: Codable, Equatable {
    let target: String
    let formats: [String]
    let csvLines: [String]
    let csvContainsInvoiceColumn: Bool
    let csvContainsCarryForward: Bool
    let csvContainsRunningBalanceOrTotal: Bool
    let pdfPageCount: Int
    let pdfLines: [String]
}

@MainActor
struct GoldenSnapshotBuilder {
    static func journalBookSnapshot(from scenario: GoldenScenario) -> GoldenJournalBookSnapshot {
        let projected = scenario.dataStore.projectedCanonicalJournals(fiscalYear: scenario.fixture.businessProfile.fiscalYear)
        let linesByEntryId = Dictionary(grouping: projected.lines, by: \ .entryId)
        let entries = projected.entries
            .sorted {
                if $0.date == $1.date {
                    return $0.memo < $1.memo
                }
                return $0.date < $1.date
            }
            .map { entry in
                GoldenJournalEntrySnapshot(
                    date: GoldenSnapshotStore.string(from: entry.date),
                    entryType: entry.entryType.rawValue,
                    memo: entry.memo,
                    isPosted: entry.isPosted,
                    lines: (linesByEntryId[entry.id] ?? [])
                        .sorted { $0.displayOrder < $1.displayOrder }
                        .map {
                            GoldenJournalLineSnapshot(
                                accountId: $0.accountId,
                                debit: $0.debit,
                                credit: $0.credit,
                                displayOrder: $0.displayOrder
                            )
                        }
                )
            }
        return GoldenJournalBookSnapshot(fiscalYear: scenario.fixture.businessProfile.fiscalYear, entries: entries)
    }

    static func trialBalanceSnapshot(from scenario: GoldenScenario) -> GoldenTrialBalanceSnapshot {
        let projected = scenario.dataStore.projectedCanonicalJournals(fiscalYear: scenario.fixture.businessProfile.fiscalYear)
        let report = AccountingReportService.generateTrialBalance(
            fiscalYear: scenario.fixture.businessProfile.fiscalYear,
            accounts: scenario.dataStore.accounts,
            journalEntries: projected.entries,
            journalLines: projected.lines,
            startMonth: FiscalYearSettings.startMonth
        )
        return GoldenTrialBalanceSnapshot(
            fiscalYear: report.fiscalYear,
            debitTotal: report.debitTotal,
            creditTotal: report.creditTotal,
            isBalanced: report.isBalanced,
            rows: report.rows.map {
                GoldenTrialBalanceRowSnapshot(
                    code: $0.code,
                    name: $0.name,
                    accountType: $0.accountType.rawValue,
                    debit: $0.debit,
                    credit: $0.credit,
                    balance: $0.balance
                )
            }
        )
    }

    static func blueReturnSnapshot(from scenario: GoldenScenario) -> GoldenEtaxFormSnapshot {
        let fiscalYear = scenario.fixture.businessProfile.fiscalYear
        let projected = scenario.dataStore.projectedCanonicalJournals(fiscalYear: fiscalYear)
        let canonical = scenario.dataStore.canonicalExportProfiles(for: fiscalYear)
        let form = EtaxFieldPopulator.populate(
            fiscalYear: fiscalYear,
            profitLoss: AccountingReportService.generateProfitLoss(
                fiscalYear: fiscalYear,
                accounts: scenario.dataStore.accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: FiscalYearSettings.startMonth
            ),
            balanceSheet: AccountingReportService.generateBalanceSheet(
                fiscalYear: fiscalYear,
                accounts: scenario.dataStore.accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: FiscalYearSettings.startMonth
            ),
            formType: .blueReturn,
            accounts: scenario.dataStore.accounts,
            businessProfile: canonical?.business,
            taxYearProfile: canonical?.taxYear,
            sensitivePayload: canonical?.sensitive,
            inventoryRecord: scenario.dataStore.getInventoryRecord(fiscalYear: fiscalYear)
        )
        return GoldenEtaxFormSnapshot(
            fiscalYear: form.fiscalYear,
            formType: form.formType.rawValue,
            totalRevenue: form.totalRevenue,
            totalExpenses: form.totalExpenses,
            netIncome: form.netIncome,
            fields: form.fields
                .sorted { $0.id < $1.id }
                .map {
                    GoldenEtaxFieldSnapshot(
                        id: $0.id,
                        fieldLabel: $0.fieldLabel,
                        section: $0.section.rawValue,
                        taxLine: $0.taxLine?.rawValue,
                        valueType: valueType(of: $0.value),
                        value: $0.value.exportText
                    )
                }
        )
    }

    static func consumptionTaxWorksheetSnapshot(from scenario: GoldenScenario) async throws -> GoldenConsumptionTaxWorksheetSnapshot {
        let accounts = try await ChartOfAccountsUseCase(modelContext: scenario.context).accounts(businessId: scenario.businessProfile.id)
        let counterparties = try await CounterpartyMasterUseCase(modelContext: scenario.context).loadCounterparties(businessId: scenario.businessProfile.id)
        let journals = try await PostingWorkflowUseCase(modelContext: scenario.context).journals(
            businessId: scenario.businessProfile.id,
            taxYear: scenario.fixture.businessProfile.fiscalYear
        )
        let worksheet = ConsumptionTaxReportService.generateWorksheet(
            fiscalYear: scenario.fixture.businessProfile.fiscalYear,
            taxYearProfile: scenario.taxYearProfile,
            journalEntries: journals,
            accounts: accounts,
            counterparties: counterparties,
            pack: try? await BundledTaxYearPackProvider(bundle: .main).pack(for: scenario.fixture.businessProfile.fiscalYear),
            startMonth: FiscalYearSettings.startMonth
        )
        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let counterpartyMap = Dictionary(uniqueKeysWithValues: counterparties.map { ($0.id, $0) })
        return GoldenConsumptionTaxWorksheetSnapshot(
            fiscalYear: worksheet.fiscalYear,
            outputTaxTotal: worksheet.outputTaxTotal,
            rawInputTaxTotal: worksheet.rawInputTaxTotal,
            deductibleInputTaxTotal: worksheet.deductibleInputTaxTotal,
            taxPayable: worksheet.taxPayable,
            lines: worksheet.lines.map {
                let account = accountMap[$0.accountId]
                return GoldenConsumptionTaxWorksheetLineSnapshot(
                    journalDate: GoldenSnapshotStore.string(from: $0.journalDate),
                    direction: $0.direction.rawValue,
                    taxCode: $0.taxCode.rawValue,
                    accountId: account?.legacyAccountId ?? account?.code ?? $0.accountId.uuidString,
                    counterpartyName: $0.counterpartyId.flatMap { counterpartyMap[$0]?.displayName },
                    taxableAmount: $0.taxableAmount,
                    taxAmount: $0.taxAmount,
                    deductibleTaxAmount: $0.deductibleTaxAmount,
                    purchaseCreditMethod: $0.purchaseCreditMethod?.rawValue,
                    totalRate: GoldenSnapshotStore.decimalString($0.taxRateBreakdown.totalRate),
                    nationalRate: GoldenSnapshotStore.decimalString($0.taxRateBreakdown.nationalRate),
                    localRate: GoldenSnapshotStore.decimalString($0.taxRateBreakdown.localRate)
                )
            }
        )
    }

    static func migrationReportSnapshot(from scenario: GoldenScenario) throws -> GoldenMigrationReportSnapshot {
        let report = try MigrationReportRunner(modelContext: scenario.context).dryRun()
        return GoldenMigrationReportSnapshot(
            deltas: report.deltas
                .sorted { $0.modelName < $1.modelName }
                .map {
                GoldenMigrationDeltaSnapshot(
                    modelName: $0.modelName,
                    legacyCount: $0.legacyCount,
                    canonicalCount: $0.canonicalCount,
                    executeSupported: $0.executeSupported
                )
            },
            orphanRecords: report.orphanRecords
                .sorted {
                    ($0.area, $0.identifier, $0.message) < ($1.area, $1.identifier, $1.message)
                }
                .map {
                GoldenMigrationOrphanSnapshot(
                    area: $0.area,
                    identifier: $0.identifier,
                    message: $0.message
                )
            },
            warnings: report.warnings.sorted()
        )
    }

    static func ledgerExportSnapshot(from scenario: GoldenScenario) throws -> GoldenLedgerExportSnapshot {
        let fiscalYear = scenario.fixture.businessProfile.fiscalYear
        let transportationBook = try seedTransportationExpenseBookIfNeeded(in: scenario.context, fiscalYear: fiscalYear)
        try seedFixedAssetIfNeeded(in: scenario.context, fiscalYear: fiscalYear)

        let artifacts = try [
            exportLedgerArtifact(
                target: .cashBook,
                fiscalYear: fiscalYear,
                context: scenario.context,
                subLedgerOptions: .init(type: .cashBook, startDate: nil, endDate: nil, accountFilter: nil, counterpartyFilter: nil)
            ),
            exportLedgerArtifact(
                target: .bankAccountBook,
                fiscalYear: fiscalYear,
                context: scenario.context,
                subLedgerOptions: .init(type: .depositBook, startDate: nil, endDate: nil, accountFilter: nil, counterpartyFilter: nil)
            ),
            exportLedgerArtifact(
                target: .accountsReceivableBook,
                fiscalYear: fiscalYear,
                context: scenario.context,
                subLedgerOptions: .init(type: .accountsReceivableBook, startDate: nil, endDate: nil, accountFilter: nil, counterpartyFilter: nil)
            ),
            exportLedgerArtifact(
                target: .accountsPayableBook,
                fiscalYear: fiscalYear,
                context: scenario.context,
                subLedgerOptions: .init(type: .accountsPayableBook, startDate: nil, endDate: nil, accountFilter: nil, counterpartyFilter: nil)
            ),
            exportLedgerArtifact(
                target: .expenseBook,
                fiscalYear: fiscalYear,
                context: scenario.context,
                subLedgerOptions: .init(type: .expenseBook, startDate: nil, endDate: nil, accountFilter: "acct-rent", counterpartyFilter: nil)
            ),
            exportLedgerArtifact(
                target: .generalLedger,
                fiscalYear: fiscalYear,
                context: scenario.context,
                ledgerOptions: .init(accountId: "acct-rent", accountName: "地代家賃", accountCode: "622")
            ),
            exportLedgerArtifact(
                target: .journalBook,
                fiscalYear: fiscalYear,
                context: scenario.context
            ),
            exportLedgerArtifact(
                target: .transportationExpense,
                fiscalYear: fiscalYear,
                context: scenario.context,
                ledgerBookSelectionOptions: .init(bookId: transportationBook.id, ledgerType: .transportationExpense)
            ),
            exportLedgerArtifact(
                target: .whiteTaxBookkeeping,
                fiscalYear: fiscalYear,
                context: scenario.context
            ),
            exportLedgerArtifact(
                target: .fixedAssetRegister,
                fiscalYear: fiscalYear,
                context: scenario.context
            ),
            exportLedgerArtifact(
                target: .fixedAssetDepreciation,
                fiscalYear: fiscalYear,
                context: scenario.context
            ),
        ]

        return GoldenLedgerExportSnapshot(
            fiscalYear: fiscalYear,
            ledgers: artifacts.sorted { $0.target < $1.target }
        )
    }

    private static func valueType(of value: EtaxFieldValue) -> String {
        switch value {
        case .number:
            return "number"
        case .text:
            return "text"
        case .flag:
            return "flag"
        }
    }

    private static func exportLedgerArtifact(
        target: ExportCoordinator.ExportTarget,
        fiscalYear: Int,
        context: ModelContext,
        ledgerOptions: ExportCoordinator.LedgerExportOptions? = nil,
        subLedgerOptions: ExportCoordinator.SubLedgerExportOptions? = nil,
        ledgerBookSelectionOptions: ExportCoordinator.LedgerBookSelectionOptions? = nil
    ) throws -> GoldenLedgerArtifactSnapshot {
        let csvURL = try ExportCoordinator.export(
            target: target,
            format: .csv,
            fiscalYear: fiscalYear,
            modelContext: context,
            ledgerOptions: ledgerOptions,
            subLedgerOptions: subLedgerOptions,
            ledgerBookSelectionOptions: ledgerBookSelectionOptions
        )
        let pdfURL = try ExportCoordinator.export(
            target: target,
            format: .pdf,
            fiscalYear: fiscalYear,
            modelContext: context,
            ledgerOptions: ledgerOptions,
            subLedgerOptions: subLedgerOptions,
            ledgerBookSelectionOptions: ledgerBookSelectionOptions
        )

        let csvText = try String(contentsOf: csvURL, encoding: .utf8)
        let pdfData = try Data(contentsOf: pdfURL)
        let csvLines = normalizedLines(csvText)
        let pdfLines = normalizedPDFLines(pdfData)

        return GoldenLedgerArtifactSnapshot(
            target: target.label,
            formats: ["csv", "pdf"],
            csvLines: Array(csvLines.prefix(14)),
            csvContainsInvoiceColumn: csvLines.contains { $0.contains("インボイス") },
            csvContainsCarryForward: csvLines.contains { $0.contains("前期より繰越") },
            csvContainsRunningBalanceOrTotal: csvLines.contains {
                $0.contains("残高") || $0.contains("累計") || $0.contains("差引残高")
            },
            pdfPageCount: PDFDocument(data: pdfData)?.pageCount ?? 0,
            pdfLines: Array(pdfLines.prefix(20))
        )
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizedPDFLines(_ data: Data) -> [String] {
        guard let document = PDFDocument(data: data) else {
            return []
        }
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        return normalizedLines(text)
    }

    private static func seedTransportationExpenseBookIfNeeded(
        in context: ModelContext,
        fiscalYear: Int
    ) throws -> SDLedgerBook {
        FeatureFlags.useLegacyLedger = true
        let store = LedgerDataStore(modelContext: context, accessMode: .readWrite)
        if let existing = store.books(ofType: .transportationExpense).sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            return existing
        }

        let metadata = TransportationExpenseMetadata(
            year: fiscalYear,
            monthPeriod: 3,
            department: "開発",
            employeeName: "山田太郎",
            requestDate: "\(fiscalYear)-03-31",
            settlementDate: "\(fiscalYear)-03-31"
        )
        guard let book = store.createBook(
            ledgerType: .transportationExpense,
            title: "交通費精算書",
            metadataJSON: LedgerBridge.encodeTransportationExpenseMetadata(metadata)
        ) else {
            throw XCTSkip("failed to seed transportation expense book")
        }
        store.addEntry(
            to: book.id,
            entry: TransportationExpenseEntry(
                id: UUID(),
                date: "\(fiscalYear)-03-05",
                destination: "渋谷",
                purpose: "打ち合わせ",
                transportMethod: "電車",
                routeFrom: "新宿",
                routeTo: "渋谷",
                tripType: .roundTrip,
                amount: 1296
            )
        )
        return book
    }

    private static func seedFixedAssetIfNeeded(
        in context: ModelContext,
        fiscalYear: Int
    ) throws {
        let descriptor = FetchDescriptor<PPFixedAsset>()
        if ((try? context.fetch(descriptor).count) ?? 0) > 0 {
            return
        }

        let calendar = Calendar(identifier: .gregorian)
        let acquisitionDate = calendar.date(from: DateComponents(year: fiscalYear, month: 1, day: 10)) ?? Date()
        context.insert(
            PPFixedAsset(
                name: "MacBook Pro",
                acquisitionDate: acquisitionDate,
                acquisitionCost: 360_000,
                usefulLifeYears: 4,
                depreciationMethod: .straightLine,
                memo: "golden fixture asset",
                businessUsePercent: 100
            )
        )
        try context.save()
    }
}

enum GoldenSnapshotStore {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder = JSONDecoder()

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static var shouldUpdate: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["UPDATE_GOLDEN_SNAPSHOTS"] == "1"
            || environment["SIMCTL_CHILD_UPDATE_GOLDEN_SNAPSHOTS"] == "1"
    }

    static func assertSnapshot<T: Codable & Equatable>(
        _ snapshot: T,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let url = expectedSnapshotURL(named: name)
        if shouldUpdate {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(snapshot).write(to: url)
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail(
                "Golden snapshot missing: \(url.path). UPDATE_GOLDEN_SNAPSHOTS=1 で生成してください。",
                file: file,
                line: line
            )
            return
        }

        let data = try Data(contentsOf: url)
        let expected = try decoder.decode(T.self, from: data)
        XCTAssertEqual(snapshot, expected, file: file, line: line)
    }

    static func string(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static func expectedSnapshotURL(named name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("expected", isDirectory: true)
            .appendingPathComponent("\(name).json")
    }
}

struct GoldenFixture: Codable {
    let businessProfile: GoldenBusinessProfile
    let projects: [GoldenProject]
    let transactions: [GoldenTransaction]
    let categories: [GoldenCategory]
    let accounts: [GoldenAccount]
}

struct GoldenBusinessProfile: Codable {
    let businessName: String
    let ownerName: String
    let ownerNameKana: String
    let fiscalYear: Int
    let isBlueReturn: Bool
    let bookkeepingMode: String
    let address: String
    let postalCode: String
    let phoneNumber: String
    let taxOfficeCode: String
}

struct GoldenProject: Codable {
    let id: String
    let name: String
    let status: String
    let startDate: String?
    let completedAt: String?
}

struct GoldenTransaction: Codable {
    let id: String
    let type: String
    let amount: Int
    let date: String
    let categoryId: String
    let memo: String
    let taxRate: Int?
    let isTaxIncluded: Bool?
    let counterparty: String?
    let allocations: [GoldenAllocation]?
}

struct GoldenAllocation: Codable {
    let projectId: String
    let ratio: Int
    let amount: Int
}

struct GoldenCategory: Codable {
    let id: String
    let name: String
    let type: String
}

struct GoldenAccount: Codable {
    let id: String
    let code: String
    let name: String
    let accountType: String
}
