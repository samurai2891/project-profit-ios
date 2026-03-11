import SwiftUI

struct ReceiptReviewView: View {
    @Environment(\.modelContext) private var modelContext

    let receiptData: ReceiptData
    let ocrText: String
    let receiptImage: UIImage?
    let evidenceSourceType: EvidenceSourceType
    let originalFileData: Data?
    let defaultProjectId: UUID?
    let onIntakeSucceeded: (() -> Void)?
    let onDismiss: () -> Void

    @State private var amountText: String = ""
    @State private var date: Date = Date()
    @State private var type: TransactionType = .expense
    @State private var categoryId: String = ""
    @State private var memo: String = ""
    @State private var allocations: [(id: UUID, projectId: UUID, ratio: Int)] = []
    @State private var editableLineItems: [EditableLineItem] = []
    @State private var isSubmitting = false
    @State private var isInitialized = false
    @State private var showImagePreview = false
    @State private var saveError: String?
    @State private var paymentAccountId: String?
    @State private var transferToAccountId: String?
    @State private var taxDeductibleRate: Int = 100
    @State private var selectedTaxCode: TaxCode?
    @State private var isTaxIncluded: Bool = true
    @State private var taxAmountText: String = ""
    @State private var selectedCounterpartyId: UUID?
    @State private var counterparty: String = ""
    @State private var formSnapshot: TransactionFormSnapshot = .empty

    init(
        receiptData: ReceiptData,
        ocrText: String,
        receiptImage: UIImage? = nil,
        evidenceSourceType: EvidenceSourceType = .manualNoFile,
        originalFileData: Data? = nil,
        defaultProjectId: UUID? = nil,
        onIntakeSucceeded: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.receiptData = receiptData
        self.ocrText = ocrText
        self.receiptImage = receiptImage
        self.evidenceSourceType = evidenceSourceType
        self.originalFileData = originalFileData
        self.defaultProjectId = defaultProjectId
        self.onIntakeSucceeded = onIntakeSucceeded
        self.onDismiss = onDismiss
    }

    private var categories: [PPCategory] {
        transactionFormQueryUseCase.categories(for: type, snapshot: formSnapshot)
    }

    private var typeBadgeColor: Color {
        switch type {
        case .income: AppColors.success
        case .expense: AppColors.error
        case .transfer: AppColors.warning
        }
    }

    private var totalRatio: Int {
        allocations.reduce(0) { $0 + $1.ratio }
    }

    private var counterparties: [Counterparty] {
        formSnapshot.counterparties
    }

    private var selectedCounterparty: Counterparty? {
        guard let selectedCounterpartyId else { return nil }
        return counterparties.first { $0.id == selectedCounterpartyId }
    }

    private var counterpartyPickerSelection: Binding<UUID?> {
        Binding(
            get: { selectedCounterpartyId },
            set: { newValue in
                selectedCounterpartyId = newValue
                applySelectedCounterpartyDefaults(preserveExternalProjectSelection: false)
            }
        )
    }

    private var isValid: Bool {
        guard let amount = Int(amountText), amount > 0 else { return false }
        if type == .transfer {
            guard let from = paymentAccountId, !from.isEmpty,
                  let to = transferToAccountId, !to.isEmpty else { return false }
            return from != to
        }
        return !categoryId.isEmpty && !allocations.isEmpty && totalRatio == 100
    }

    private var transactionFormQueryUseCase: TransactionFormQueryUseCase {
        TransactionFormQueryUseCase(modelContext: modelContext)
    }

    private var availableProjects: [PPProject] {
        formSnapshot.projects
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ocrBanner
                receiptImageSection
                typeSection
                amountSection
                dateSection
                if type != .transfer {
                    categorySection
                }
                accountingSection
                consumptionTaxSection
                LineItemsEditView(items: $editableLineItems)
                if type != .transfer {
                    allocationSection
                }
                counterpartySection
                memoSection
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("登録") { save() }
                    .disabled(!isValid || isSubmitting)
                    .accessibilityLabel("登録")
                    .accessibilityHint(isValid ? "タップして証憑を登録" : "すべての必須項目を入力してください")
            }
        }
        .task {
            refreshFormSnapshot()
            setupFromReceiptData()
        }
        .onChange(of: type) { _, _ in
            ensureValidCategorySelection()
        }
        .alert("保存エラー", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "保存に失敗しました")
        }
        .sheet(isPresented: $showImagePreview) {
            if let image = receiptImage {
                ReceiptImagePreviewView(image: image)
            }
        }
    }

    // MARK: - OCR Banner

    private var ocrBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.viewfinder")
                .foregroundStyle(AppColors.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("書類読み取り結果")
                    .font(.subheadline.weight(.medium))
                Text("\(receiptData.documentType.label) / 推定精度 \(Int(receiptData.confidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(AppColors.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("書類読み取り結果。内容を確認して必要に応じて修正してください")
    }

    // MARK: - Receipt Image

    @ViewBuilder
    private var receiptImageSection: some View {
        if let image = receiptImage {
            VStack(alignment: .leading, spacing: 8) {
                Text("添付画像")
                    .font(.subheadline.weight(.medium))

                Button {
                    showImagePreview = true
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption)
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .padding(8)
                        }
                }
                .accessibilityLabel("添付画像をプレビュー")
                .accessibilityHint("タップして全画面表示")
            }
        }
    }

    // MARK: - Type

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("種類")
                .font(.subheadline.weight(.medium))
            HStack(spacing: 12) {
                typeButton(for: .expense, label: "経費", icon: "arrow.down.circle.fill", activeColor: AppColors.error)
                typeButton(for: .income, label: "収益", icon: "arrow.up.circle.fill", activeColor: AppColors.success)
                typeButton(for: .transfer, label: "振替", icon: "arrow.left.arrow.right.circle.fill", activeColor: AppColors.warning)
            }
        }
    }

    private func typeButton(for txType: TransactionType, label: String, icon: String, activeColor: Color) -> some View {
        let isSelected = type == txType
        return Button {
            type = txType
        } label: {
            HStack {
                Image(systemName: icon)
                Text(label)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? activeColor : AppColors.surface)
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? activeColor : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("種類: \(label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("タップして\(label)を選択")
    }

    // MARK: - Amount

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("金額")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(type.label)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(typeBadgeColor.opacity(0.12))
                    .foregroundStyle(typeBadgeColor)
                    .clipShape(Capsule())
            }
            HStack {
                Text("¥")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("0", text: $amountText)
                    .keyboardType(.numberPad)
                    .font(.system(size: 28, weight: .semibold))
                    .accessibilityLabel("金額")
                    .accessibilityValue(amountText.isEmpty ? "未入力" : "\(amountText)円")
            }
            .padding(16)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Tax information (reference)
            if receiptData.taxAmount > 0 || receiptData.subtotalAmount > 0 {
                taxInfoView
            }
        }
    }

    @ViewBuilder
    private var taxInfoView: some View {
        HStack(spacing: 16) {
            if receiptData.subtotalAmount > 0 {
                Label {
                    Text("税抜 ¥\(receiptData.subtotalAmount.formatted())")
                        .font(.caption)
                } icon: {
                    Image(systemName: "minus.circle")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("税抜金額 \(receiptData.subtotalAmount)円")
            }
            if receiptData.taxAmount > 0 {
                Label {
                    Text("消費税 ¥\(receiptData.taxAmount.formatted())")
                        .font(.caption)
                } icon: {
                    Image(systemName: "percent")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("消費税 \(receiptData.taxAmount)円")
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Date

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("日付")
                .font(.subheadline.weight(.medium))
            DatePicker("日付", selection: $date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .accessibilityLabel("日付")
                .accessibilityValue(formatDate(date))
        }
    }

    // MARK: - Category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("カテゴリ")
                .font(.subheadline.weight(.medium))
            if categories.isEmpty {
                Text("この種類のカテゴリがありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.id) { cat in
                            let isSelected = categoryId == cat.id
                            Button {
                                categoryId = cat.id
                            } label: {
                                Text(cat.name)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(isSelected ? AppColors.primary : AppColors.surface)
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(isSelected ? AppColors.primary : AppColors.border, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("カテゴリ: \(cat.name)")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }

    // MARK: - Accounting / Tax

    private var accountingSection: some View {
        VStack(spacing: 12) {
            AccountPickerView(
                label: type == .income ? "入金先口座" : "支払元口座",
                accounts: formSnapshot.accounts,
                selectedAccountId: $paymentAccountId,
                filterPredicate: { $0.isPaymentAccount && $0.isActive }
            )

            if type == .transfer {
                AccountPickerView(
                    label: "振替先口座",
                    accounts: formSnapshot.accounts,
                    selectedAccountId: $transferToAccountId,
                    filterPredicate: { $0.isPaymentAccount && $0.isActive }
                )
            }

            if type == .expense {
                TaxDeductibleRateView(rate: $taxDeductibleRate)
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var consumptionTaxSection: some View {
        if type != .transfer {
            VStack(alignment: .leading, spacing: 8) {
                Text("消費税")
                    .font(.subheadline.weight(.medium))

                VStack(spacing: 12) {
                    TaxCodePickerView(selectedTaxCode: $selectedTaxCode)

                    if let tc = selectedTaxCode, tc.isTaxable {
                        Toggle("税込金額", isOn: $isTaxIncluded)
                            .font(.subheadline)

                        HStack {
                            Text("消費税額")
                                .font(.subheadline)
                            Spacer()
                            if isTaxIncluded, let amount = Int(amountText), amount > 0 {
                                let computed = amount * tc.taxRatePercent / (100 + tc.taxRatePercent)
                                Text(formatCurrency(computed))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else {
                                TextField("0", text: $taxAmountText)
                                    .keyboardType(.numberPad)
                                    .frame(width: 100)
                                    .multilineTextAlignment(.trailing)
                                    .font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                }
                .padding(16)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Allocation

    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("プロジェクト配分")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("合計: \(totalRatio)%")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(totalRatio == 100 ? AppColors.success : AppColors.error)
                    .accessibilityLabel("配分合計 \(totalRatio)%")
            }

            ForEach(Array(allocations.enumerated()), id: \.element.id) { index, alloc in
                allocationRow(index: index, alloc: alloc)
            }

            if availableProjects.count > allocations.count {
                addProjectButton
            }
        }
    }

    private func allocationRow(index: Int, alloc: (id: UUID, projectId: UUID, ratio: Int)) -> some View {
        let projectName = transactionFormQueryUseCase.projectName(
            id: alloc.projectId,
            snapshot: formSnapshot
        ) ?? "選択"
        return HStack {
            Menu {
                ForEach(availableProjects, id: \.id) { project in
                    Button(project.name) {
                        allocations[index].projectId = project.id
                    }
                }
            } label: {
                Text(projectName)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.primary.opacity(0.1))
                    .foregroundStyle(AppColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("プロジェクト: \(projectName)")

            Spacer()

            HStack(spacing: 4) {
                TextField("0", text: Binding(
                    get: { String(allocations[index].ratio) },
                    set: { allocations[index].ratio = min(100, max(0, Int($0) ?? 0)) }
                ))
                .keyboardType(.numberPad)
                .frame(width: 50)
                .multilineTextAlignment(.center)
                .padding(6)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border))
                .accessibilityLabel("\(projectName)の配分率")
                .accessibilityValue("\(alloc.ratio)%")

                Text("%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            if allocations.count > 1 {
                Button {
                    allocations.remove(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.error)
                }
                .accessibilityLabel("\(projectName)を配分から削除")
            }
        }
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var addProjectButton: some View {
        Button {
            let usedIds = Set(allocations.map(\.projectId))
            if let available = availableProjects.first(where: { !usedIds.contains($0.id) }) {
                allocations.append((id: UUID(), projectId: available.id, ratio: 0))
            }
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("プロジェクトを追加（按分）")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppColors.primary)
            .frame(maxWidth: .infinity)
            .padding(12)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColors.border, style: StrokeStyle(lineWidth: 1, dash: [6]))
            )
        }
        .accessibilityLabel("プロジェクトを追加")
        .accessibilityHint("按分するプロジェクトを追加")
    }

    // MARK: - Counterparty

    private var counterpartySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("取引先")
                .font(.subheadline.weight(.medium))
            if !counterparties.isEmpty {
                Picker("登録済み取引先", selection: counterpartyPickerSelection) {
                    Text("選択しない").tag(UUID?.none)
                    ForEach(counterparties, id: \.id) { counterparty in
                        Text(counterparty.displayName).tag(UUID?.some(counterparty.id))
                    }
                }
                .pickerStyle(.menu)
            }
            TextField("取引先名を入力...", text: $counterparty)
                .onChange(of: counterparty) { _, newValue in
                    guard let selectedCounterparty else { return }
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty || trimmed != selectedCounterparty.displayName {
                        selectedCounterpartyId = nil
                    }
                }
                .padding(14)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("取引先")
                .accessibilityValue(counterparty.isEmpty ? "未入力" : counterparty)
        }
    }

    // MARK: - Memo

    private var memoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("メモ")
                .font(.subheadline.weight(.medium))
            TextField("取引の詳細を入力...", text: $memo, axis: .vertical)
                .lineLimit(2...4)
                .padding(14)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("メモ")
                .accessibilityValue(memo.isEmpty ? "未入力" : memo)
        }
    }

    // MARK: - Logic

    private func applySelectedCounterpartyDefaults(preserveExternalProjectSelection: Bool) {
        guard let selectedCounterpartyId,
              let defaults = transactionFormQueryUseCase.counterpartyDefaults(
                for: selectedCounterpartyId,
                type: type,
                snapshot: formSnapshot
              ) else {
            return
        }

        counterparty = defaults.displayName
        if let taxCode = defaults.taxCode {
            selectedTaxCode = taxCode
        }
        if let paymentAccountId = defaults.paymentAccountId {
            self.paymentAccountId = paymentAccountId
        }
        if type != .transfer,
           !preserveExternalProjectSelection,
           let defaultProjectId = defaults.projectId {
            allocations = [(id: UUID(), projectId: defaultProjectId, ratio: 100)]
        }
    }

    private func initialMatchedCounterparty() -> Counterparty? {
        if let registrationNumber = RegistrationNumberNormalizer.normalize(receiptData.registrationNumber) {
            return counterparties.first { $0.normalizedInvoiceRegistrationNumber == registrationNumber }
        }
        let normalizedStoreName = receiptData.storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedStoreName.isEmpty else { return nil }
        return counterparties.first {
            $0.displayName.compare(
                normalizedStoreName,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
            ) == .orderedSame
        }
    }

    private func setupFromReceiptData() {
        guard !isInitialized else { return }
        isInitialized = true

        type = receiptData.suggestedTransactionType
        amountText = receiptData.totalAmount > 0 ? String(receiptData.totalAmount) : ""
        date = receiptData.parsedDate
        categoryId = receiptData.categoryId
        memo = receiptData.formattedMemo
        editableLineItems = receiptData.lineItems.map { EditableLineItem(from: $0) }
        paymentAccountId = formSnapshot.defaultPaymentAccountId
            ?? transactionFormQueryUseCase.paymentAccounts(snapshot: formSnapshot).first?.id
        if receiptData.taxAmount > 0 {
            selectedTaxCode = .standard10
            taxAmountText = String(receiptData.taxAmount)
        }
        counterparty = receiptData.storeName

        // Validate category exists for selected transaction type
        ensureValidCategorySelection()

        // Default allocation - use defaultProjectId if provided
        if let projectId = defaultProjectId, availableProjects.contains(where: { $0.id == projectId }) {
            allocations = [(id: UUID(), projectId: projectId, ratio: 100)]
        } else if let firstProject = availableProjects.first {
            allocations = [(id: UUID(), projectId: firstProject.id, ratio: 100)]
        }

        if let matchedCounterparty = initialMatchedCounterparty() {
            selectedCounterpartyId = matchedCounterparty.id
            applySelectedCounterpartyDefaults(preserveExternalProjectSelection: defaultProjectId != nil)
        }
    }

    private func save() {
        guard isValid, let amount = Int(amountText) else { return }
        isSubmitting = true
        saveError = nil
        Task { @MainActor in
            defer { isSubmitting = false }

            guard amount > 0 else { return }

            let validDate = min(date, Date())
            let lineItems = editableLineItems
                .filter { !$0.name.isEmpty && $0.unitPrice > 0 }
                .map {
                    LineItem(
                        name: $0.name,
                        quantity: $0.quantity,
                        unitPrice: $0.unitPrice,
                        subtotal: $0.quantity * $0.unitPrice
                    )
                }
            let linkedProjectIds = type == .transfer ? [] : allocations.map(\.projectId)
            let resolvedCategoryId = type == .transfer ? "" : categoryId
            let resolvedTransferTo: String? = type == .transfer ? transferToAccountId : nil
            let resolvedTaxCodeId = type != .transfer ? selectedTaxCode?.rawValue : nil
            let resolvedIsTaxIncluded = selectedTaxCode?.isTaxable == true ? isTaxIncluded : false
            let resolvedTaxAmount: Int?
            if let tc = selectedTaxCode, tc.isTaxable {
                if isTaxIncluded {
                    resolvedTaxAmount = amount * tc.taxRatePercent / (100 + tc.taxRatePercent)
                } else {
                    resolvedTaxAmount = Int(taxAmountText)
                }
            } else {
                resolvedTaxAmount = nil
            }
            let resolvedCounterpartyName = selectedCounterparty?.displayName
                ?? counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedCounterparty = resolvedCounterpartyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let originalFileName = generatedOriginalFileName()

            do {
                let isPDFSource = originalFileData != nil
                    && (evidenceSourceType == .importedPDF || evidenceSourceType == .scannedPDF)
                let fileData: Data
                let mimeType: String

                if isPDFSource, let pdfData = originalFileData {
                    fileData = pdfData
                    mimeType = "application/pdf"
                } else {
                    guard let receiptImage else {
                        throw ReceiptEvidenceIntakeUseCaseError.invalidFileData
                    }
                    fileData = try ReceiptImageStore.jpegData(for: receiptImage)
                    mimeType = "image/jpeg"
                }

                let request = ReceiptEvidenceIntakeRequest(
                    receiptData: receiptData,
                    ocrText: ocrText,
                    sourceType: evidenceSourceType,
                    fileData: fileData,
                    originalFileName: originalFileName,
                    mimeType: mimeType,
                    reviewedAmount: amount,
                    reviewedDate: validDate,
                    transactionType: type,
                    categoryId: resolvedCategoryId,
                    memo: memo,
                    lineItems: lineItems,
                    linkedProjectIds: linkedProjectIds,
                    paymentAccountId: paymentAccountId,
                    transferToAccountId: resolvedTransferTo,
                    taxDeductibleRate: type == .expense ? taxDeductibleRate : 100,
                    taxCodeId: resolvedTaxCodeId,
                    isTaxIncluded: resolvedIsTaxIncluded,
                    taxAmount: resolvedTaxAmount,
                    registrationNumber: receiptData.registrationNumber,
                    counterpartyId: selectedCounterpartyId,
                    counterpartyName: resolvedCounterparty.isEmpty ? nil : resolvedCounterparty
                )
                _ = try await ReceiptEvidenceIntakeUseCase(modelContext: modelContext).intake(request)
                onIntakeSucceeded?()
                onDismiss()
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    private func refreshFormSnapshot() {
        formSnapshot = (try? transactionFormQueryUseCase.snapshot()) ?? .empty
    }

    private func generatedOriginalFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let prefix: String
        switch evidenceSourceType {
        case .camera:
            prefix = "camera"
        case .photoLibrary:
            prefix = "photo"
        case .scannedPDF:
            prefix = "scan"
        case .emailAttachment:
            prefix = "mail"
        case .importedPDF:
            prefix = "import"
        case .manualNoFile:
            prefix = "manual"
        }
        let isPDFSource = originalFileData != nil
            && (evidenceSourceType == .importedPDF || evidenceSourceType == .scannedPDF)
        let ext = isPDFSource ? "pdf" : "jpg"
        return "\(prefix)-receipt-\(timestamp).\(ext)"
    }

    private func ensureValidCategorySelection() {
        if type == .transfer {
            categoryId = ""
            return
        }
        if !categories.contains(where: { $0.id == categoryId }) {
            categoryId = categories.first?.id ?? fallbackCategoryId(for: type)
        }
    }

    private func fallbackCategoryId(for transactionType: TransactionType) -> String {
        switch transactionType {
        case .income: "cat-other-income"
        case .expense, .transfer: "cat-other-expense"
        }
    }
}
