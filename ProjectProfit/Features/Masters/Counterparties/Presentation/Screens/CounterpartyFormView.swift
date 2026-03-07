import SwiftData
import SwiftUI

struct CounterpartyFormView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let counterparty: Counterparty?
    let onSaved: (() -> Void)?

    @State private var displayName = ""
    @State private var kana = ""
    @State private var legalName = ""
    @State private var invoiceRegistrationNumber = ""
    @State private var invoiceIssuerStatus: InvoiceIssuerStatus = .unknown
    @State private var address = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var notes = ""
    @State private var selectedDefaultAccountId: UUID?
    @State private var selectedTaxCodeId: String?
    @State private var selectedDefaultProjectId: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var registrationNumberError: String?

    private var isEditMode: Bool { counterparty != nil }
    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && registrationNumberError == nil
    }
    private var availableAccounts: [CanonicalAccount] {
        dataStore.canonicalAccounts().filter { $0.archivedAt == nil }
    }
    private var availableProjects: [PPProject] {
        dataStore.projects.filter { $0.isArchived != true }
    }

    init(counterparty: Counterparty?, onSaved: (() -> Void)? = nil) {
        self.counterparty = counterparty
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            Section("基本情報") {
                TextField("取引先名（必須）", text: $displayName)
                TextField("フリガナ", text: $kana)
                TextField("法人名・正式名称", text: $legalName)
            }

            Section("インボイス情報") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("登録番号（T + 13桁数字）", text: $invoiceRegistrationNumber)
                        .keyboardType(.asciiCapable)
                        .onChange(of: invoiceRegistrationNumber) { _, newValue in
                            validateRegistrationNumber(newValue)
                        }
                    if let error = registrationNumberError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(AppColors.error)
                    }
                }

                Picker("適格請求書発行事業者", selection: $invoiceIssuerStatus) {
                    ForEach(InvoiceIssuerStatus.allCases, id: \.self) { status in
                        Text(status.displayName).tag(status)
                    }
                }
            }

            Section("連絡先") {
                TextField("住所", text: $address)
                TextField("電話番号", text: $phone)
                    .keyboardType(.phonePad)
                TextField("メールアドレス", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
            }

            Section("デフォルト設定") {
                Picker("勘定科目", selection: $selectedDefaultAccountId) {
                    Text("未設定").tag(UUID?.none)
                    ForEach(availableAccounts, id: \.id) { account in
                        Text("\(account.code) \(account.name)").tag(UUID?.some(account.id))
                    }
                }

                Picker("税区分", selection: $selectedTaxCodeId) {
                    Text("未設定").tag(String?.none)
                    ForEach(TaxCode.allCases, id: \.rawValue) { code in
                        Text(code.displayName).tag(String?.some(code.rawValue))
                    }
                }

                Picker("プロジェクト", selection: $selectedDefaultProjectId) {
                    Text("未設定").tag(UUID?.none)
                    ForEach(availableProjects) { project in
                        Text(project.name).tag(UUID?.some(project.id))
                    }
                }
            }

            Section("メモ") {
                TextField("メモ", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle(isEditMode ? "取引先を編集" : "取引先を追加")
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

    private func populateFields() {
        guard let cp = counterparty else { return }
        displayName = cp.displayName
        kana = cp.kana ?? ""
        legalName = cp.legalName ?? ""
        invoiceRegistrationNumber = cp.normalizedInvoiceRegistrationNumber ?? cp.invoiceRegistrationNumber ?? ""
        invoiceIssuerStatus = cp.invoiceIssuerStatus
        address = cp.address ?? ""
        phone = cp.phone ?? ""
        email = cp.email ?? ""
        notes = cp.notes ?? ""
        selectedDefaultAccountId = cp.defaultAccountId
        selectedTaxCodeId = cp.defaultTaxCodeId
        selectedDefaultProjectId = cp.defaultProjectId
    }

    private func validateRegistrationNumber(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            registrationNumberError = nil
            return
        }
        let pattern = /^T?\d{13}$/
        if trimmed.wholeMatch(of: pattern) != nil {
            registrationNumberError = nil
        } else {
            registrationNumberError = "T + 13桁の数字で入力してください"
        }
    }

    private func save() async {
        guard let businessId = dataStore.businessProfile?.id else {
            errorMessage = "事業者情報が未設定です"
            return
        }
        isSaving = true
        defer { isSaving = false }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKana = kana.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLegalName = legalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRegNum = RegistrationNumberNormalizer.normalize(invoiceRegistrationNumber)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let newCounterparty: Counterparty
        if let existing = counterparty {
            newCounterparty = Counterparty(
                id: existing.id,
                businessId: existing.businessId,
                displayName: trimmedName,
                kana: trimmedKana.isEmpty ? nil : trimmedKana,
                legalName: trimmedLegalName.isEmpty ? nil : trimmedLegalName,
                corporateNumber: existing.corporateNumber,
                invoiceRegistrationNumber: trimmedRegNum,
                invoiceIssuerStatus: invoiceIssuerStatus,
                statusEffectiveFrom: existing.statusEffectiveFrom,
                statusEffectiveTo: existing.statusEffectiveTo,
                address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                defaultAccountId: selectedDefaultAccountId,
                defaultTaxCodeId: selectedTaxCodeId,
                defaultProjectId: selectedDefaultProjectId,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                createdAt: existing.createdAt,
                updatedAt: Date()
            )
        } else {
            newCounterparty = Counterparty(
                businessId: businessId,
                displayName: trimmedName,
                kana: trimmedKana.isEmpty ? nil : trimmedKana,
                legalName: trimmedLegalName.isEmpty ? nil : trimmedLegalName,
                invoiceRegistrationNumber: trimmedRegNum,
                invoiceIssuerStatus: invoiceIssuerStatus,
                address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                defaultAccountId: selectedDefaultAccountId,
                defaultTaxCodeId: selectedTaxCodeId,
                defaultProjectId: selectedDefaultProjectId,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
        }

        do {
            try await CounterpartyMasterUseCase(modelContext: modelContext).save(newCounterparty)
            onSaved?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
