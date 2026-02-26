import SwiftUI

struct ProfileSettingsView: View {
    static let secureStoreFailureMessage = "機微情報はKeychainへ保存できなかったため、平文では保存していません。端末設定を確認して再試行してください。"

    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    @State private var businessName: String = ""
    @State private var ownerName: String = ""
    @State private var ownerNameKana: String = ""
    @State private var postalCode: String = ""
    @State private var address: String = ""
    @State private var phoneNumber: String = ""
    @State private var dateOfBirth: Date = Date()
    @State private var hasDateOfBirth: Bool = false
    @State private var businessCategory: String = ""
    @State private var myNumberFlag: Bool = false
    @State private var includeSensitiveInExport: Bool = true
    @State private var saveErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                basicInfoSection
                addressSection
                contactSection
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
                Button("保存") {
                    if saveProfile() {
                        dismiss()
                    }
                }
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.primary)
            }
        }
        .onAppear {
            loadProfile()
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

    // MARK: - Reusable Field Row

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

    // MARK: - Load / Save

    private func loadProfile() {
        guard let profile = dataStore.accountingProfile else { return }

        businessName = profile.businessName
        ownerName = profile.ownerName
        let secure = ProfileSecureStore.load(profileId: profile.id)

        ownerNameKana = secure?.ownerNameKana ?? profile.ownerNameKana ?? ""
        postalCode = secure?.postalCode ?? profile.postalCode ?? ""
        address = secure?.address ?? profile.address ?? ""
        phoneNumber = secure?.phoneNumber ?? profile.phoneNumber ?? ""
        businessCategory = secure?.businessCategory ?? profile.businessCategory ?? ""
        myNumberFlag = secure?.myNumberFlag ?? profile.myNumberFlag ?? false
        includeSensitiveInExport = secure?.includeSensitiveInExport ?? true

        if let dob = secure?.dateOfBirth ?? profile.dateOfBirth {
            dateOfBirth = dob
            hasDateOfBirth = true
        }

        if secure == nil, hasLegacySensitiveFields(profile: profile) {
            let migrated = ProfileSensitivePayload.fromLegacyProfile(
                ownerNameKana: profile.ownerNameKana,
                postalCode: profile.postalCode,
                address: profile.address,
                phoneNumber: profile.phoneNumber,
                dateOfBirth: profile.dateOfBirth,
                businessCategory: profile.businessCategory,
                myNumberFlag: profile.myNumberFlag,
                includeSensitiveInExport: includeSensitiveInExport
            )
            if ProfileSecureStore.save(migrated, profileId: profile.id) {
                clearLegacySensitiveFields(profile: profile)
                profile.updatedAt = Date()
                dataStore.save()
            }
        }
    }

    @discardableResult
    private func saveProfile() -> Bool {
        guard let profile = dataStore.accountingProfile else { return false }

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

        guard ProfileSecureStore.save(payload, profileId: profile.id) else {
            saveErrorMessage = Self.secureStoreFailureMessage
            return false
        }

        profile.businessName = businessName
        profile.ownerName = ownerName
        clearLegacySensitiveFields(profile: profile)
        profile.updatedAt = Date()
        dataStore.save()
        saveErrorMessage = nil
        return true
    }

    private func hasLegacySensitiveFields(profile: PPAccountingProfile) -> Bool {
        profile.ownerNameKana != nil ||
        profile.postalCode != nil ||
        profile.address != nil ||
        profile.phoneNumber != nil ||
        profile.dateOfBirth != nil ||
        profile.businessCategory != nil ||
        profile.myNumberFlag != nil
    }

    private func clearLegacySensitiveFields(profile: PPAccountingProfile) {
        profile.ownerNameKana = nil
        profile.postalCode = nil
        profile.address = nil
        profile.phoneNumber = nil
        profile.dateOfBirth = nil
        profile.businessCategory = nil
        profile.myNumberFlag = nil
    }
}
