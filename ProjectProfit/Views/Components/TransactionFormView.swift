import PhotosUI
import SwiftData
import SwiftUI

struct TransactionFormView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let transaction: PPTransaction?
    let defaultProjectId: UUID?

    @State private var type: TransactionType = .expense
    @State private var amountText: String = ""
    @State private var date: Date = Date()
    @State private var categoryId: String = ""
    @State private var memo: String = ""
    @State private var allocations: [(id: UUID, projectId: UUID, ratio: Int)] = []
    @State private var isSubmitting = false
    @State private var showReceiptPreview = false
    @State private var selectedImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showRemoveImageAlert = false
    @State private var imageRemoved = false
    @State private var saveError: String?
    @State private var distributionTemplates: [DistributionRule] = []
    @State private var selectedDistributionTemplateId: UUID?
    @State private var isLoadingDistributionTemplates = false
    @State private var distributionTemplateErrorMessage: String?
    @State private var unavailableDistributionTemplateCount = 0
    // Phase 4C: 会計フィールド
    @State private var paymentAccountId: String?
    @State private var transferToAccountId: String?
    @State private var taxDeductibleRate: Int = 100
    // Phase 5: 消費税フィールド
    @State private var selectedTaxCode: TaxCode?
    @State private var isTaxIncluded: Bool = true
    @State private var taxAmountText: String = ""
    // Phase 8: 取引先
    @State private var selectedCounterpartyId: UUID?
    @State private var counterparty: String = ""

    private var isEditMode: Bool { transaction != nil }

    private var paymentAccounts: [PPAccount] {
        dataStore.accounts.filter { $0.isPaymentAccount && $0.isActive }
    }

    private var counterparties: [Counterparty] {
        dataStore.canonicalCounterparties()
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
                applySelectedCounterpartyDefaults()
            }
        )
    }

    init(transaction: PPTransaction? = nil, defaultProjectId: UUID? = nil) {
        self.transaction = transaction
        self.defaultProjectId = defaultProjectId
    }

    private var categories: [PPCategory] {
        let categoryType: CategoryType = switch type {
        case .income: .income
        case .expense, .transfer: .expense
        }
        return dataStore.activeCategories.filter { $0.type == categoryType }
    }

    private var totalRatio: Int {
        allocations.reduce(0) { $0 + $1.ratio }
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

    private var distributionTemplateLoadKey: String {
        let businessId = dataStore.businessProfile?.id.uuidString ?? "none"
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        return "\(businessId)-\(day)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    typeSection
                    receiptSection
                    amountSection
                    dateSection
                    if type != .transfer {
                        categorySection
                    }
                    accountingSection
                    consumptionTaxSection
                    lineItemsSection
                    if type != .transfer {
                        allocationSection
                    }
                    counterpartySection
                    memoSection
                }
                .padding(20)
            }
            .sheet(isPresented: $showReceiptPreview) {
                if let image = selectedImage {
                    ReceiptImagePreviewView(image: image)
                } else if let t = transaction, let path = t.receiptImagePath,
                          let view = ReceiptImagePreviewView(fileName: path)
                {
                    view
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraView(image: $selectedImage)
                    .ignoresSafeArea()
            }
            .onChange(of: photoPickerItem) { _, newItem in
                loadPhoto(from: newItem)
            }
            .alert("画像を削除", isPresented: $showRemoveImageAlert) {
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) {
                    selectedImage = nil
                    photoPickerItem = nil
                    imageRemoved = true
                }
            } message: {
                Text("添付画像を削除しますか？")
            }
            .alert("保存エラー", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "保存に失敗しました")
            }
            .navigationTitle(isEditMode ? "取引を編集" : "新規取引")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .accessibilityLabel("キャンセル")
                        .accessibilityHint("タップして入力を取り消し")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!isValid || isSubmitting)
                        .accessibilityLabel("保存")
                        .accessibilityHint(isValid ? "タップして取引を保存" : "すべての必須項目を入力してください")
                }
            }
            .onAppear { setupInitialValues() }
            .onChange(of: type) { _, _ in autoSelectCategory() }
            .task(id: distributionTemplateLoadKey) {
                await loadDistributionTemplates()
            }
        }
    }

    // MARK: - Receipt Section

    private var receiptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("添付画像")
                .font(.subheadline.weight(.medium))

            if let image = selectedImage {
                receiptImagePreview(image: image)
            } else if !imageRemoved, let t = transaction, let imagePath = t.receiptImagePath,
                      let existingImage = ReceiptImageStore.loadImage(fileName: imagePath) {
                receiptImagePreview(image: existingImage)
            } else {
                imagePickerButtons
            }
        }
    }

    private func receiptImagePreview(image: UIImage) -> some View {
        VStack(spacing: 8) {
            Button {
                showReceiptPreview = true
            } label: {
                HStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("添付画像を表示")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("添付画像を表示")

            HStack(spacing: 12) {
                Button {
                    showRemoveImageAlert = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("削除")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.error)
                }
                .accessibilityLabel("添付画像を削除")

                Spacer()

                imagePickerButtons
            }
        }
    }

    @ViewBuilder
    private var imagePickerButtons: some View {
        HStack(spacing: 12) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                        Text("撮影")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("カメラで撮影")
            }

            PhotosPicker(
                selection: $photoPickerItem,
                matching: .images
            ) {
                HStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle")
                    Text("選択")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColors.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("フォトライブラリから選択")
        }
    }

    // MARK: - Line Items Section

    @ViewBuilder
    private var lineItemsSection: some View {
        if let t = transaction, !t.lineItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("明細")
                    .font(.subheadline.weight(.medium))

                ForEach(Array(t.lineItems.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.name)
                            .font(.subheadline)

                        Spacer()

                        if item.quantity > 1 {
                            Text("×\(item.quantity)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(formatCurrency(item.subtotal))
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
            Text("金額")
                .font(.subheadline.weight(.medium))
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
        }
    }

    // MARK: - Date
    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("日付")
                .font(.subheadline.weight(.medium))
            DatePicker("日付", selection: $date, displayedComponents: .date)
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
                        .accessibilityHint("タップして\(cat.name)を選択")
                    }
                }
            }
        }
    }

    // MARK: - Accounting Fields
    private var accountingSection: some View {
        VStack(spacing: 12) {
            AccountPickerView(
                label: type == .income ? "入金先口座" : "支払元口座",
                accounts: dataStore.accounts,
                selectedAccountId: $paymentAccountId,
                filterPredicate: { $0.isPaymentAccount && $0.isActive }
            )

            if type == .transfer {
                AccountPickerView(
                    label: "振替先口座",
                    accounts: dataStore.accounts,
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

    // MARK: - Consumption Tax
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
                    .accessibilityValue(totalRatio == 100 ? "正常" : "合計が100%になるよう調整してください")
            }

            distributionTemplateSection

            ForEach(Array(allocations.enumerated()), id: \.element.id) { index, alloc in
                let projectName = dataStore.getProject(id: alloc.projectId)?.name ?? "選択"
                HStack {
                    Menu {
                        let usedIds = Set(allocations.map(\.projectId))
                        ForEach(dataStore.projects.filter { p in
                            p.isArchived != true && (!usedIds.contains(p.id) || p.id == alloc.projectId)
                        }, id: \.id) { project in
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
                    .accessibilityHint("タップしてプロジェクトを選択")

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
                        .accessibilityHint("タップしてこのプロジェクトの配分を削除")
                    }
                }
                .padding(12)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if dataStore.projects.filter({ $0.isArchived != true }).count > allocations.count {
                Button {
                    let usedIds = Set(allocations.map(\.projectId))
                    if let available = dataStore.projects.first(where: { !usedIds.contains($0.id) && $0.isArchived != true }) {
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
                .accessibilityHint("タップして按分するプロジェクトを追加")
            }
        }
    }

    @ViewBuilder
    private var distributionTemplateSection: some View {
        if isLoadingDistributionTemplates
            || !distributionTemplates.isEmpty
            || distributionTemplateErrorMessage != nil
            || unavailableDistributionTemplateCount > 0
        {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("配賦テンプレート")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isLoadingDistributionTemplates {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if !distributionTemplates.isEmpty {
                    Picker("配賦テンプレート", selection: $selectedDistributionTemplateId) {
                        Text("選択しない").tag(UUID?.none)
                        ForEach(distributionTemplates, id: \.id) { rule in
                            Text(rule.name).tag(UUID?.some(rule.id))
                        }
                    }
                    .pickerStyle(.menu)

                    Button("テンプレートを適用") {
                        applySelectedDistributionTemplate()
                    }
                    .disabled(selectedDistributionTemplateId == nil)
                } else if !isLoadingDistributionTemplates {
                    Text("適用できるテンプレートはありません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if unavailableDistributionTemplateCount > 0 {
                    Text("未対応テンプレート \(unavailableDistributionTemplateCount) 件はこの画面では適用できません。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let distributionTemplateErrorMessage {
                    Text(distributionTemplateErrorMessage)
                        .font(.caption)
                        .foregroundStyle(AppColors.error)
                }
            }
            .padding(12)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
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

    private func setupInitialValues() {
        if let t = transaction {
            type = t.type
            amountText = String(t.amount)
            date = t.date
            categoryId = t.categoryId
            memo = t.memo
            allocations = t.allocations.map { (id: UUID(), projectId: $0.projectId, ratio: $0.ratio) }
            paymentAccountId = t.paymentAccountId
            transferToAccountId = t.transferToAccountId
            taxDeductibleRate = t.effectiveTaxDeductibleRate
            selectedTaxCode = TaxCode.resolve(legacyCategory: t.taxCategory, taxRate: t.taxRate)
            isTaxIncluded = t.isTaxIncluded ?? true
            if let ta = t.taxAmount { taxAmountText = String(ta) }
            selectedCounterpartyId = t.counterpartyId
            counterparty = t.counterparty
                ?? t.counterpartyId.flatMap { dataStore.canonicalCounterparty(id: $0)?.displayName }
                ?? ""
        } else {
            if let defaultProjectId {
                allocations = [(id: UUID(), projectId: defaultProjectId, ratio: 100)]
            } else if let first = dataStore.projects.first(where: { $0.isArchived != true }) {
                allocations = [(id: UUID(), projectId: first.id, ratio: 100)]
            }
            paymentAccountId = dataStore.defaultPaymentAccountPreference ?? paymentAccounts.first?.id
            autoSelectCategory()
        }
    }

    private func autoSelectCategory() {
        if type == .transfer {
            categoryId = ""
            return
        }
        if !categories.contains(where: { $0.id == categoryId }), let first = categories.first {
            categoryId = first.id
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data)
            {
                selectedImage = uiImage
                imageRemoved = false
            }
        }
    }

    private func loadDistributionTemplates() async {
        guard let businessId = dataStore.businessProfile?.id else {
            distributionTemplates = []
            selectedDistributionTemplateId = nil
            distributionTemplateErrorMessage = nil
            unavailableDistributionTemplateCount = 0
            return
        }

        isLoadingDistributionTemplates = true
        defer { isLoadingDistributionTemplates = false }

        do {
            let useCase = DistributionTemplateUseCase(modelContext: modelContext)
            let applier = DistributionTemplateApplicationUseCase()
            let activeRules = try await useCase.activeRules(businessId: businessId, at: date)
            distributionTemplates = activeRules
                .filter { applier.isSupported($0, allocationPeriod: .month) }
                .sorted { lhs, rhs in
                    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            unavailableDistributionTemplateCount = activeRules.count - distributionTemplates.count
            if let selectedDistributionTemplateId,
               distributionTemplates.contains(where: { $0.id == selectedDistributionTemplateId }) == false
            {
                self.selectedDistributionTemplateId = nil
            }
            distributionTemplateErrorMessage = nil
        } catch {
            distributionTemplates = []
            selectedDistributionTemplateId = nil
            unavailableDistributionTemplateCount = 0
            distributionTemplateErrorMessage = error.localizedDescription
        }
    }

    private func applySelectedDistributionTemplate() {
        guard let selectedDistributionTemplateId,
              let rule = distributionTemplates.first(where: { $0.id == selectedDistributionTemplateId })
        else {
            return
        }

        do {
            let ratios = try DistributionTemplateApplicationUseCase().buildRatioAllocations(
                rule: rule,
                projects: dataStore.projects,
                referenceDate: date,
                allocationPeriod: .month
            )
            allocations = ratios.map { (id: UUID(), projectId: $0.projectId, ratio: $0.ratio) }
            distributionTemplateErrorMessage = nil
        } catch {
            distributionTemplateErrorMessage = error.localizedDescription
        }
    }

    private func applySelectedCounterpartyDefaults() {
        guard let selectedCounterparty else { return }

        counterparty = selectedCounterparty.displayName
        if let defaultTaxCodeId = selectedCounterparty.defaultTaxCodeId,
           let taxCode = TaxCode.resolve(id: defaultTaxCodeId) {
            selectedTaxCode = taxCode
        }
        if let defaultAccountId = selectedCounterparty.defaultAccountId,
           let legacyAccountId = dataStore.legacyAccountId(for: defaultAccountId) {
            paymentAccountId = legacyAccountId
        }
        if type != .transfer,
           let defaultProjectId = selectedCounterparty.defaultProjectId,
           dataStore.projects.contains(where: { $0.id == defaultProjectId && $0.isArchived != true }) {
            allocations = [(id: UUID(), projectId: defaultProjectId, ratio: 100)]
        }
    }

    private func save() {
        guard isValid, let amount = Int(amountText) else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        saveError = nil

        let allocs = type == .transfer ? [] : allocations.map { (projectId: $0.projectId, ratio: $0.ratio) }

        var imagePath: String?
        if let image = selectedImage {
            do {
                imagePath = try ReceiptImageStore.saveImage(image)
            } catch {
                // 画像保存失敗でも取引は保存する
            }
        }

        let resolvedTaxDeductibleRate: Int? = type == .expense ? taxDeductibleRate : nil
        let resolvedTransferTo: String? = type == .transfer ? transferToAccountId : nil
        let resolvedCategoryId: String = type == .transfer ? "" : categoryId

        // 消費税フィールドの解決
        let resolvedCounterpartyName = selectedCounterparty?.displayName
            ?? counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCounterparty: String? = resolvedCounterpartyName.isEmpty ? nil : resolvedCounterpartyName
        let resolvedTaxCategory: TaxCategory? = type != .transfer ? selectedTaxCode?.legacyCategory : nil
        let resolvedConsumptionTaxRate: Int? = selectedTaxCode?.isTaxable == true ? selectedTaxCode?.taxRatePercent : nil
        let resolvedIsTaxIncluded: Bool? = selectedTaxCode?.isTaxable == true ? isTaxIncluded : nil
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

        if let t = transaction {
            let didUpdate: Bool
            if selectedImage != nil {
                didUpdate = dataStore.updateTransaction(
                    id: t.id, type: type, amount: amount, date: date,
                    categoryId: resolvedCategoryId, memo: memo, allocations: allocs,
                    receiptImagePath: imagePath,
                    paymentAccountId: paymentAccountId,
                    transferToAccountId: resolvedTransferTo,
                    taxDeductibleRate: resolvedTaxDeductibleRate,
                    taxAmount: resolvedTaxAmount,
                    taxRate: resolvedConsumptionTaxRate,
                    isTaxIncluded: resolvedIsTaxIncluded,
                    taxCategory: resolvedTaxCategory,
                    counterpartyId: selectedCounterpartyId,
                    counterparty: resolvedCounterparty,
                    candidateSource: .manual
                )
                if didUpdate, let oldPath = t.receiptImagePath {
                    ReceiptImageStore.deleteImage(fileName: oldPath)
                }
            } else if imageRemoved {
                didUpdate = dataStore.updateTransaction(
                    id: t.id, type: type, amount: amount, date: date,
                    categoryId: resolvedCategoryId, memo: memo, allocations: allocs,
                    receiptImagePath: .some(nil),
                    paymentAccountId: paymentAccountId,
                    transferToAccountId: resolvedTransferTo,
                    taxDeductibleRate: resolvedTaxDeductibleRate,
                    taxAmount: resolvedTaxAmount,
                    taxRate: resolvedConsumptionTaxRate,
                    isTaxIncluded: resolvedIsTaxIncluded,
                    taxCategory: resolvedTaxCategory,
                    counterpartyId: selectedCounterpartyId,
                    counterparty: resolvedCounterparty,
                    candidateSource: .manual
                )
                if didUpdate, let oldPath = t.receiptImagePath {
                    ReceiptImageStore.deleteImage(fileName: oldPath)
                }
            } else {
                didUpdate = dataStore.updateTransaction(
                    id: t.id, type: type, amount: amount, date: date,
                    categoryId: resolvedCategoryId, memo: memo, allocations: allocs,
                    paymentAccountId: paymentAccountId,
                    transferToAccountId: resolvedTransferTo,
                    taxDeductibleRate: resolvedTaxDeductibleRate,
                    taxAmount: resolvedTaxAmount,
                    taxRate: resolvedConsumptionTaxRate,
                    isTaxIncluded: resolvedIsTaxIncluded,
                    taxCategory: resolvedTaxCategory,
                    counterpartyId: selectedCounterpartyId,
                    counterparty: resolvedCounterparty,
                    candidateSource: .manual
                )
            }
            if didUpdate {
                dismiss()
            } else {
                saveError = dataStore.lastError?.errorDescription ?? "保存に失敗しました"
            }
        } else {
            let result = dataStore.addTransactionResult(
                type: type, amount: amount, date: date,
                categoryId: resolvedCategoryId, memo: memo, allocations: allocs,
                receiptImagePath: imagePath,
                paymentAccountId: paymentAccountId,
                transferToAccountId: resolvedTransferTo,
                taxDeductibleRate: resolvedTaxDeductibleRate,
                taxAmount: resolvedTaxAmount,
                taxRate: resolvedConsumptionTaxRate,
                isTaxIncluded: resolvedIsTaxIncluded,
                taxCategory: resolvedTaxCategory,
                counterpartyId: selectedCounterpartyId,
                counterparty: resolvedCounterparty,
                candidateSource: .manual
            )
            switch result {
            case .success:
                dismiss()
            case .failure(let error):
                saveError = error.localizedDescription
            }
        }
    }
}
