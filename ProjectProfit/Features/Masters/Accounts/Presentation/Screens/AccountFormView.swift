import SwiftData
import SwiftUI

struct AccountFormView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let account: CanonicalAccount?
    let onSaved: (() -> Void)?

    @State private var code = ""
    @State private var name = ""
    @State private var accountType: CanonicalAccountType = .expense
    @State private var normalBalance: NormalBalance = .debit
    @State private var selectedLegalReportLineId: String?
    @State private var selectedTaxCodeId: String?
    @State private var projectAllocatable = true
    @State private var householdProrationAllowed = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEditMode: Bool { account != nil }
    private var isSystemAccount: Bool { account?.legacyAccountId != nil }

    /// code/name/accountType/normalBalance are immutable after creation
    private var isStructuralFieldsLocked: Bool { isEditMode }

    private var isValid: Bool {
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(account: CanonicalAccount? = nil, onSaved: (() -> Void)? = nil) {
        self.account = account
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            basicInfoSection
            classificationSection
            defaultSettingsSection

            if isSystemAccount {
                systemAccountNoticeSection
            }
        }
        .navigationTitle(isEditMode ? "勘定科目を編集" : "勘定科目を追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    Task { await save() }
                }
                .disabled(!isValid || isSaving)
            }
        }
        .onAppear { populateFields() }
        .alert("エラー", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var basicInfoSection: some View {
        Section("基本情報") {
            if isStructuralFieldsLocked {
                readOnlyRow(label: "勘定科目コード", value: code)
                if isSystemAccount {
                    readOnlyRow(label: "勘定科目名", value: name)
                } else {
                    TextField("勘定科目名（必須）", text: $name)
                }
            } else {
                TextField("勘定科目コード（必須）", text: $code)
                TextField("勘定科目名（必須）", text: $name)
            }
        }
    }

    private var classificationSection: some View {
        Section("分類") {
            if isStructuralFieldsLocked {
                readOnlyRow(label: "勘定科目区分", value: accountType.displayName)
                readOnlyRow(label: "正常残高", value: normalBalance.label)
            } else {
                Picker("勘定科目区分", selection: $accountType) {
                    ForEach(CanonicalAccountType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                Picker("正常残高", selection: $normalBalance) {
                    Text(NormalBalance.debit.label).tag(NormalBalance.debit)
                    Text(NormalBalance.credit.label).tag(NormalBalance.credit)
                }
            }
        }
    }

    private var defaultSettingsSection: some View {
        Section("デフォルト設定") {
            Picker("税区分", selection: $selectedTaxCodeId) {
                Text("未設定").tag(String?.none)
                ForEach(TaxCode.allCases, id: \.rawValue) { taxCode in
                    Text(taxCode.displayName).tag(String?.some(taxCode.rawValue))
                }
            }

            Picker("決算書表示行", selection: $selectedLegalReportLineId) {
                Text("未設定").tag(String?.none)
                ForEach(LegalReportLine.allCases) { line in
                    Text(line.displayName).tag(String?.some(line.rawValue))
                }
            }

            Toggle("プロジェクト配賦可能", isOn: $projectAllocatable)
            Toggle("家事按分可能", isOn: $householdProrationAllowed)
        }
    }

    private var systemAccountNoticeSection: some View {
        Section {
            Label(
                "システム科目のため、コード・名前・区分は変更できません",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func readOnlyRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private func populateFields() {
        guard let acct = account else { return }
        code = acct.code
        name = acct.name
        accountType = acct.accountType
        normalBalance = acct.normalBalance
        selectedLegalReportLineId = acct.defaultLegalReportLineId
        selectedTaxCodeId = acct.defaultTaxCodeId
        projectAllocatable = acct.projectAllocatable
        householdProrationAllowed = acct.householdProrationAllowed
    }

    private func save() async {
        guard let businessId = dataStore.businessProfile?.id else {
            errorMessage = "事業者情報が未設定です"
            return
        }
        isSaving = true
        defer { isSaving = false }

        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let accountToSave: CanonicalAccount
        if let existing = account {
            accountToSave = existing.updated(
                name: isSystemAccount ? nil : trimmedName,
                defaultLegalReportLineId: .some(selectedLegalReportLineId),
                defaultTaxCodeId: .some(selectedTaxCodeId),
                projectAllocatable: projectAllocatable,
                householdProrationAllowed: householdProrationAllowed
            )
        } else {
            accountToSave = CanonicalAccount(
                businessId: businessId,
                code: trimmedCode,
                name: trimmedName,
                accountType: accountType,
                normalBalance: normalBalance,
                defaultLegalReportLineId: selectedLegalReportLineId,
                defaultTaxCodeId: selectedTaxCodeId,
                projectAllocatable: projectAllocatable,
                householdProrationAllowed: householdProrationAllowed
            )
        }

        do {
            try await ChartOfAccountsUseCase(modelContext: modelContext).save(accountToSave)
            onSaved?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
