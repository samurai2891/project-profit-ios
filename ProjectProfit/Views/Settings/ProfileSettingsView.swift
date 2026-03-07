import SwiftUI

struct ProfileSettingsView: View {
    static let secureStoreFailureMessage = "機微情報はKeychainへ保存できなかったため、平文では保存していません。端末設定を確認して再試行してください。"

    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    @State private var businessName: String = ""
    @State private var ownerName: String = ""
    @State private var ownerNameKana: String = ""
    @State private var taxOfficeCode: String = ""
    @State private var postalCode: String = ""
    @State private var address: String = ""
    @State private var phoneNumber: String = ""
    @State private var dateOfBirth: Date = Date()
    @State private var hasDateOfBirth: Bool = false
    @State private var businessCategory: String = ""
    @State private var myNumberFlag: Bool = false
    @State private var includeSensitiveInExport: Bool = true
    @State private var filingStyle: FilingStyle = .blueGeneral
    @State private var blueDeductionLevel: BlueDeductionLevel = .sixtyFive
    @State private var bookkeepingBasis: BookkeepingBasis = .doubleEntry
    @State private var vatStatus: VatStatus = .exempt
    @State private var vatMethod: VatMethod = .general
    @State private var simplifiedBusinessCategory: SimplifiedBusinessCategoryOption = .first
    @State private var invoiceIssuerStatusAtYear: InvoiceIssuerStatus = .unknown
    @State private var electronicBookLevel: ElectronicBookLevel = .none
    @State private var yearLockState: YearLockState = .open
    @State private var currentTaxYear: Int = Calendar.current.component(.year, from: Date())
    @State private var saveErrorMessage: String?
    @State private var isLoadingProfile = false
    @State private var isSavingProfile = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                taxYearSummarySection
                basicInfoSection
                addressSection
                contactSection
                taxSection
                otherSection
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("申告者情報")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSavingProfile ? "保存中..." : "保存") {
                    Task { await saveProfile() }
                }
                .disabled(isSavingProfile || isLoadingProfile)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.primary)
            }
        }
        .task {
            await loadProfile()
        }
        .alert(
            "保存エラー",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        saveErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private var taxYearSummarySection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("対象年分")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("\(currentTaxYear)年")
                    .font(.title3.weight(.semibold))
            }
            Spacer()
            if isLoadingProfile {
                ProgressView()
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 基本情報

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("基本情報")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                fieldRow(label: "屋号", text: $businessName, placeholder: "例: 山田デザイン事務所")

                Divider().padding(.leading, 16)

                fieldRow(label: "氏名", text: $ownerName, placeholder: "例: 山田太郎")

                Divider().padding(.leading, 16)

                fieldRow(label: "氏名カナ", text: $ownerNameKana, placeholder: "例: ヤマダタロウ")
            }
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 住所

    private var addressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("住所")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                fieldRow(label: "郵便番号", text: $postalCode, placeholder: "例: 1000001", keyboardType: .numberPad)

                Divider().padding(.leading, 16)

                fieldRow(label: "住所", text: $address, placeholder: "例: 東京都千代田区千代田1-1")

                Divider().padding(.leading, 16)

                fieldRow(label: "税務署", text: $taxOfficeCode, placeholder: "例: 1234")
            }
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 連絡先

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("連絡先")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                fieldRow(label: "電話番号", text: $phoneNumber, placeholder: "例: 09012345678", keyboardType: .phonePad)
            }
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 税務設定

    private var taxSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("税務設定")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                pickerRow(label: "申告方式", selection: $filingStyle, values: FilingStyle.allCases)

                Divider().padding(.leading, 16)

                pickerRow(label: "控除額", selection: $blueDeductionLevel, values: BlueDeductionLevel.allCases)
                    .disabled(!filingStyle.isBlue)
                    .opacity(filingStyle.isBlue ? 1 : 0.5)

                Divider().padding(.leading, 16)

                pickerRow(label: "記帳方式", selection: $bookkeepingBasis, values: BookkeepingBasis.allCases)

                Divider().padding(.leading, 16)

                pickerRow(label: "消費税", selection: $vatStatus, values: VatStatus.allCases)

                Divider().padding(.leading, 16)

                pickerRow(label: "計算方式", selection: $vatMethod, values: VatMethod.allCases)
                    .disabled(vatStatus == .exempt)
                    .opacity(vatStatus == .exempt ? 0.5 : 1)

                if vatStatus == .taxable && vatMethod == .simplified {
                    Divider().padding(.leading, 16)

                    pickerRow(label: "業種区分", selection: $simplifiedBusinessCategory, values: SimplifiedBusinessCategoryOption.allCases)
                }

                Divider().padding(.leading, 16)

                pickerRow(label: "インボイス", selection: $invoiceIssuerStatusAtYear, values: InvoiceIssuerStatus.allCases)

                Divider().padding(.leading, 16)

                pickerRow(label: "電子帳簿", selection: $electronicBookLevel, values: ElectronicBookLevel.allCases)

                Divider().padding(.leading, 16)

                pickerRow(label: "年度状態", selection: $yearLockState, values: YearLockState.allCases)
            }
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .onChange(of: filingStyle) { _, newValue in
            if !newValue.isBlue {
                blueDeductionLevel = .none
            }
            if newValue == .blueCashBasis {
                bookkeepingBasis = .cashBasis
            }
        }
        .onChange(of: vatStatus) { _, newValue in
            if newValue == .exempt {
                vatMethod = .general
            }
        }
    }

    // MARK: - その他

    private var otherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("その他")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                HStack {
                    Text("生年月日")
                        .font(.body)
                        .frame(width: 80, alignment: .leading)

                    Spacer()

                    DatePicker(
                        "生年月日",
                        selection: $dateOfBirth,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .onChange(of: dateOfBirth) {
                        hasDateOfBirth = true
                    }
                }
                .padding(16)

                Divider().padding(.leading, 16)

                fieldRow(label: "事業種類", text: $businessCategory, placeholder: "例: ソフトウェア開発")

                Divider().padding(.leading, 16)

                HStack {
                    Text("マイナンバー提出")
                        .font(.body)

                    Spacer()

                    Toggle("マイナンバー提出", isOn: $myNumberFlag)
                        .labelsHidden()
                }
                .padding(16)

                Divider().padding(.leading, 16)

                HStack {
                    Text("機微情報を出力")
                        .font(.body)

                    Spacer()

                    Toggle("機微情報を出力", isOn: $includeSensitiveInExport)
                        .labelsHidden()
                }
                .padding(16)
            }
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Reusable Rows

    private func fieldRow(
        label: String,
        text: Binding<String>,
        placeholder: String = "",
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .frame(width: 80, alignment: .leading)

            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
                .multilineTextAlignment(.trailing)
        }
        .padding(16)
    }

    private func pickerRow<Value: Hashable & CaseIterable & CustomStringConvertible>(
        label: String,
        selection: Binding<Value>,
        values: Value.AllCases
    ) -> some View where Value.AllCases: RandomAccessCollection {
        HStack {
            Text(label)
                .font(.body)
                .frame(width: 80, alignment: .leading)

            Spacer()

            Picker(label, selection: selection) {
                ForEach(Array(values), id: \.self) { value in
                    Text(value.description).tag(value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(16)
    }

    // MARK: - Load / Save

    private func loadProfile() async {
        isLoadingProfile = true
        defer { isLoadingProfile = false }

        _ = await dataStore.reloadProfileSettings()

        let secure = dataStore.profileSensitivePayload

        if let profile = dataStore.businessProfile {
            businessName = profile.businessName
            ownerName = profile.ownerName
            ownerNameKana = secure?.ownerNameKana ?? profile.ownerNameKana
            taxOfficeCode = profile.taxOfficeCode ?? ""
            postalCode = secure?.postalCode ?? profile.postalCode
            address = secure?.address ?? profile.businessAddress
            phoneNumber = secure?.phoneNumber ?? profile.phoneNumber
        } else {
            businessName = ""
            ownerName = ""
            ownerNameKana = secure?.ownerNameKana ?? ""
            taxOfficeCode = ""
            postalCode = secure?.postalCode ?? ""
            address = secure?.address ?? ""
            phoneNumber = secure?.phoneNumber ?? ""
        }

        if let taxProfile = dataStore.currentTaxYearProfile {
            currentTaxYear = taxProfile.taxYear
            filingStyle = taxProfile.filingStyle
            blueDeductionLevel = taxProfile.blueDeductionLevel
            bookkeepingBasis = taxProfile.bookkeepingBasis
            vatStatus = taxProfile.vatStatus
            vatMethod = taxProfile.vatMethod
            simplifiedBusinessCategory = SimplifiedBusinessCategoryOption(rawValue: taxProfile.simplifiedBusinessCategory ?? 1) ?? .first
            invoiceIssuerStatusAtYear = taxProfile.invoiceIssuerStatusAtYear
            electronicBookLevel = taxProfile.electronicBookLevel
            yearLockState = taxProfile.yearLockState
        } else {
            currentTaxYear = Calendar.current.component(.year, from: Date())
        }

        businessCategory = secure?.businessCategory ?? ""
        myNumberFlag = secure?.myNumberFlag ?? false
        includeSensitiveInExport = secure?.includeSensitiveInExport ?? true

        if let dob = secure?.dateOfBirth {
            dateOfBirth = dob
            hasDateOfBirth = true
        } else {
            hasDateOfBirth = false
        }
    }

    private func saveProfile() async {
        isSavingProfile = true
        defer { isSavingProfile = false }

        let payload = ProfileSensitivePayload.fromLegacyProfile(
            ownerNameKana: ownerNameKana,
            postalCode: postalCode,
            address: address,
            phoneNumber: phoneNumber,
            dateOfBirth: hasDateOfBirth ? dateOfBirth : nil,
            businessCategory: businessCategory,
            myNumberFlag: myNumberFlag,
            includeSensitiveInExport: includeSensitiveInExport
        )

        let command = SaveProfileSettingsCommand(
            ownerName: ownerName,
            ownerNameKana: ownerNameKana,
            businessName: businessName,
            businessAddress: address,
            postalCode: postalCode,
            phoneNumber: phoneNumber,
            openingDate: dataStore.profileOpeningDate,
            taxOfficeCode: taxOfficeCode.isEmpty ? nil : taxOfficeCode,
            filingStyle: filingStyle,
            blueDeductionLevel: blueDeductionLevel,
            bookkeepingBasis: bookkeepingBasis,
            vatStatus: vatStatus,
            vatMethod: vatMethod,
            simplifiedBusinessCategory: vatStatus == .taxable && vatMethod == .simplified ? simplifiedBusinessCategory.rawValue : nil,
            invoiceIssuerStatusAtYear: invoiceIssuerStatusAtYear,
            electronicBookLevel: electronicBookLevel,
            yearLockState: yearLockState,
            taxYear: currentTaxYear
        )

        switch await dataStore.saveProfileSettings(command: command, sensitivePayload: payload) {
        case .success:
            saveErrorMessage = nil
            dismiss()
        case .failure(let error):
            saveErrorMessage = error.localizedDescription.isEmpty ? Self.secureStoreFailureMessage : error.localizedDescription
        }
    }
}

extension FilingStyle: CustomStringConvertible {
    var description: String { displayName }
}

extension BlueDeductionLevel: CustomStringConvertible {
    var description: String { displayName }
}

extension BookkeepingBasis: CustomStringConvertible {
    var description: String { displayName }
}

extension VatStatus: CustomStringConvertible {
    var description: String { displayName }
}

extension VatMethod: CustomStringConvertible {
    var description: String { displayName }
}

private enum SimplifiedBusinessCategoryOption: Int, CaseIterable, CustomStringConvertible {
    case first = 1
    case second = 2
    case third = 3
    case fourth = 4
    case fifth = 5
    case sixth = 6

    var description: String {
        switch self {
        case .first: "第1種"
        case .second: "第2種"
        case .third: "第3種"
        case .fourth: "第4種"
        case .fifth: "第5種"
        case .sixth: "第6種"
        }
    }
}

extension InvoiceIssuerStatus: CustomStringConvertible {
    var description: String { displayName }
}

extension ElectronicBookLevel: CustomStringConvertible {
    var description: String { displayName }
}

extension YearLockState: CustomStringConvertible {
    var description: String { displayName }
}
