import Foundation

/// 年分別の税務プロフィール
/// 年分ごとに1つ存在し、その年の申告方式・消費税状態等を保持する
struct TaxYearProfile: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let businessId: UUID
    let taxYear: Int
    let filingStyle: FilingStyle
    let blueDeductionLevel: BlueDeductionLevel
    let bookkeepingBasis: BookkeepingBasis
    let vatStatus: VatStatus
    let vatMethod: VatMethod
    let simplifiedBusinessCategory: Int?
    let invoiceIssuerStatusAtYear: InvoiceIssuerStatus
    let electronicBookLevel: ElectronicBookLevel
    let etaxSubmissionPlanned: Bool
    let yearLockState: YearLockState
    let taxPackVersion: String
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        businessId: UUID,
        taxYear: Int,
        filingStyle: FilingStyle = .blueGeneral,
        blueDeductionLevel: BlueDeductionLevel = .sixtyFive,
        bookkeepingBasis: BookkeepingBasis = .doubleEntry,
        vatStatus: VatStatus = .exempt,
        vatMethod: VatMethod = .general,
        simplifiedBusinessCategory: Int? = nil,
        invoiceIssuerStatusAtYear: InvoiceIssuerStatus = .unknown,
        electronicBookLevel: ElectronicBookLevel = .none,
        etaxSubmissionPlanned: Bool = false,
        yearLockState: YearLockState = .open,
        taxPackVersion: String = "2025-v1",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.businessId = businessId
        self.taxYear = taxYear
        self.filingStyle = filingStyle
        self.blueDeductionLevel = blueDeductionLevel
        self.bookkeepingBasis = bookkeepingBasis
        self.vatStatus = vatStatus
        self.vatMethod = vatMethod
        self.simplifiedBusinessCategory = simplifiedBusinessCategory
        self.invoiceIssuerStatusAtYear = invoiceIssuerStatusAtYear
        self.electronicBookLevel = electronicBookLevel
        self.etaxSubmissionPlanned = etaxSubmissionPlanned
        self.yearLockState = yearLockState
        self.taxPackVersion = taxPackVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// この年分で青色申告か
    var isBlueReturn: Bool {
        filingStyle.isBlue
    }

    /// この年分で消費税課税事業者か
    var isTaxable: Bool {
        vatStatus == .taxable
    }

    /// この年分で簡易課税か
    var isSimplifiedTaxation: Bool {
        vatMethod == .simplified
    }

    /// この年分で2割特例適用か
    var isTwoTenthsSpecial: Bool {
        vatMethod == .twoTenths
    }

    /// イミュータブル更新
    func updated(
        filingStyle: FilingStyle? = nil,
        blueDeductionLevel: BlueDeductionLevel? = nil,
        bookkeepingBasis: BookkeepingBasis? = nil,
        vatStatus: VatStatus? = nil,
        vatMethod: VatMethod? = nil,
        simplifiedBusinessCategory: Int?? = nil,
        invoiceIssuerStatusAtYear: InvoiceIssuerStatus? = nil,
        electronicBookLevel: ElectronicBookLevel? = nil,
        etaxSubmissionPlanned: Bool? = nil,
        yearLockState: YearLockState? = nil,
        taxPackVersion: String? = nil
    ) -> TaxYearProfile {
        TaxYearProfile(
            id: self.id,
            businessId: self.businessId,
            taxYear: self.taxYear,
            filingStyle: filingStyle ?? self.filingStyle,
            blueDeductionLevel: blueDeductionLevel ?? self.blueDeductionLevel,
            bookkeepingBasis: bookkeepingBasis ?? self.bookkeepingBasis,
            vatStatus: vatStatus ?? self.vatStatus,
            vatMethod: vatMethod ?? self.vatMethod,
            simplifiedBusinessCategory: simplifiedBusinessCategory ?? self.simplifiedBusinessCategory,
            invoiceIssuerStatusAtYear: invoiceIssuerStatusAtYear ?? self.invoiceIssuerStatusAtYear,
            electronicBookLevel: electronicBookLevel ?? self.electronicBookLevel,
            etaxSubmissionPlanned: etaxSubmissionPlanned ?? self.etaxSubmissionPlanned,
            yearLockState: yearLockState ?? self.yearLockState,
            taxPackVersion: taxPackVersion ?? self.taxPackVersion,
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }
}
