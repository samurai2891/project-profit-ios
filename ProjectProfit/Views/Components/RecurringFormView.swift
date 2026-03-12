import PhotosUI
import SwiftData
import SwiftUI

struct RecurringFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationService.self) private var notificationService
    @Environment(\.dismiss) private var dismiss

    let recurring: PPRecurringTransaction?

    // MARK: - State

    @State private var name: String
    @State private var type: TransactionType
    @State private var amountText: String
    @State private var frequency: RecurringFrequency
    @State private var dayOfMonth: Int
    @State private var monthOfYear: Int
    @State private var selectedCategoryId: String?
    @State private var allocationMode: AllocationMode
    @State private var allocations: [(id: UUID, projectId: UUID, ratio: Int)]
    @State private var memo: String
    @State private var isActive: Bool
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var yearlyAmortizationMode: YearlyAmortizationMode

    // Phase 4C: 会計フィールド
    @State private var paymentAccountId: String?
    @State private var transferToAccountId: String?
    @State private var taxDeductibleRate: Int
    // Phase 8: 取引先
    @State private var selectedCounterpartyId: UUID?
    @State private var counterparty: String

    @State private var showValidationError = false
    @State private var validationMessage = ""
    @State private var selectedImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showReceiptPreview = false
    @State private var showRemoveImageAlert = false
    @State private var imageRemoved = false
    @State private var distributionTemplates: [DistributionRule] = []
    @State private var selectedDistributionTemplateId: UUID?
    @State private var isLoadingDistributionTemplates = false
    @State private var distributionTemplateErrorMessage: String?
    @State private var unavailableDistributionTemplateCount = 0
    @State private var pendingDistributionApproval: DistributionTemplateApplicationUseCase.ApprovalPreview?
    @State private var formSnapshot: RecurringFormSnapshot = .empty

    private var isEditMode: Bool { recurring != nil }

    // MARK: - Initialization

    init(recurring: PPRecurringTransaction? = nil) {
        self.recurring = recurring
        self._name = State(initialValue: recurring?.name ?? "")
        self._type = State(initialValue: recurring?.type ?? .expense)
        self._amountText = State(initialValue: recurring.map { String($0.amount) } ?? "")
        self._frequency = State(initialValue: recurring?.frequency ?? .monthly)
        self._dayOfMonth = State(initialValue: recurring?.dayOfMonth ?? 1)
        self._monthOfYear = State(initialValue: recurring?.monthOfYear ?? 1)
        self._selectedCategoryId = State(initialValue: recurring?.categoryId)
        self._allocationMode = State(initialValue: recurring?.allocationMode ?? .manual)
        self._allocations = State(
            initialValue: recurring?.allocations.map { (id: UUID(), projectId: $0.projectId, ratio: $0.ratio) } ?? []
        )
        self._memo = State(initialValue: recurring?.memo ?? "")
        self._isActive = State(initialValue: recurring?.isActive ?? true)
        self._hasEndDate = State(initialValue: recurring?.endDate != nil)
        self._endDate = State(initialValue: recurring?.endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: Date())!)
        self._yearlyAmortizationMode = State(initialValue: recurring?.yearlyAmortizationMode ?? .lumpSum)
        // Phase 9A: 会計フィールドの初期化（定期取引モデルから読込）
        self._paymentAccountId = State(initialValue: recurring?.paymentAccountId)
        self._transferToAccountId = State(initialValue: recurring?.transferToAccountId)
        self._taxDeductibleRate = State(initialValue: recurring?.taxDeductibleRate ?? 100)
        self._selectedCounterpartyId = State(initialValue: recurring?.counterpartyId)
        self._counterparty = State(initialValue: recurring?.counterparty ?? "")
    }

    // MARK: - Computed Properties

    private var filteredCategories: [PPCategory] {
        recurringQueryUseCase.categories(for: type, snapshot: formSnapshot)
    }

    private var parsedAmount: Int? {
        Int(amountText)
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
                applySelectedCounterpartyDefaults()
            }
        )
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedAmount != nil
            && (parsedAmount ?? 0) > 0
            && dayOfMonth >= 1
            && dayOfMonth <= 28
    }

    private var hasPendingDistributionApproval: Bool {
        pendingDistributionApproval != nil
    }

    private var templateReferenceDate: Date {
        let calendar = Calendar.current
        let today = todayDate()
        let currentYear = calendar.component(.year, from: today)
        let month = frequency == .yearly ? monthOfYear : calendar.component(.month, from: today)
        return calendar.date(from: DateComponents(year: currentYear, month: month, day: dayOfMonth)) ?? today
    }

    private var distributionTemplateLoadKey: String {
        let businessId = formSnapshot.businessId?.uuidString ?? "none"
        let referenceDay = Int(Calendar.current.startOfDay(for: templateReferenceDate).timeIntervalSince1970)
        return "\(businessId)-\(referenceDay)"
    }

    private var distributionTemplateAllocationPeriod: DistributionTemplateApplicationUseCase.AllocationPeriod {
        frequency == .yearly ? .year : .month
    }

    private var recurringQueryUseCase: RecurringQueryUseCase {
        RecurringQueryUseCase(modelContext: modelContext)
    }

    private var recurringWorkflowUseCase: RecurringWorkflowUseCase {
        RecurringWorkflowUseCase(
            modelContext: modelContext,
            onRecurringScheduleChanged: { recurrings in
                Task { @MainActor in
                    await notificationService.rescheduleAll(recurringTransactions: recurrings)
                }
            }
        )
    }

    private var activeProjects: [PPProject] {
        recurringQueryUseCase.activeProjects(snapshot: formSnapshot)
    }

    private var distributionTemplateApplicationUseCase: DistributionTemplateApplicationUseCase {
        DistributionTemplateApplicationUseCase()
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.surface
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        nameField
                        typeToggle
                        amountField
                        frequencySection
                        dayOfMonthSection
                        if frequency == .yearly {
                            yearlyAmortizationSection
                        }
                        categorySection
                        accountingSection
                        distributionTemplateSection
                        allocationModeSection
                        if allocationMode == .manual {
                            RecurringProjectAllocationSection(
                                projects: activeProjects,
                                allocations: $allocations
                            )
                        } else {
                            equalAllInfoSection
                        }
                        counterpartyField
                        memoField
                        RecurringReceiptImageSection(
                            recurring: recurring,
                            selectedImage: $selectedImage,
                            photoPickerItem: $photoPickerItem,
                            showCamera: $showCamera,
                            showReceiptPreview: $showReceiptPreview,
                            showRemoveImageAlert: $showRemoveImageAlert,
                            imageRemoved: imageRemoved
                        )
                        endDateSection

                        if isEditMode {
                            activeToggle
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(isEditMode ? "定期取引を編集" : "定期取引を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .foregroundStyle(isFormValid ? AppColors.primary : AppColors.muted)
                        .disabled(!isFormValid || hasPendingDistributionApproval)
                }
            }
            .alert("入力エラー", isPresented: $showValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
            .sheet(isPresented: $showCamera) {
                CameraView(image: $selectedImage)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showReceiptPreview) {
                if let image = selectedImage {
                    ReceiptImagePreviewView(image: image)
                } else if let r = recurring, let path = r.receiptImagePath,
                          let view = ReceiptImagePreviewView(fileName: path) {
                    view
                }
            }
            .onChange(of: photoPickerItem) { _, newItem in
                loadPhoto(from: newItem)
            }
            .task {
                loadFormSnapshot()
            }
            .onChange(of: amountText) { _, _ in invalidatePendingDistributionApproval() }
            .onChange(of: frequency) { _, _ in invalidatePendingDistributionApproval() }
            .onChange(of: dayOfMonth) { _, _ in invalidatePendingDistributionApproval() }
            .onChange(of: monthOfYear) { _, _ in invalidatePendingDistributionApproval() }
            .onChange(of: selectedDistributionTemplateId) { _, _ in invalidatePendingDistributionApproval() }
            .task(id: distributionTemplateLoadKey) {
                await loadDistributionTemplates()
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
        }
    }

    // MARK: - Name Field

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("名前")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("サーバー代", text: $name)
                .textFieldStyle(.roundedBorder)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Type Toggle

    private var typeToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("種類")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("種類", selection: $type) {
                Text("経費").tag(TransactionType.expense)
                Text("収益").tag(TransactionType.income)
                Text("振替").tag(TransactionType.transfer)
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: type) { _, _ in
            selectedCategoryId = nil
        }
    }

    // MARK: - Amount Field

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("金額")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("¥")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                TextField("0", text: $amountText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Frequency Section

    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("頻度")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("頻度", selection: $frequency) {
                Text("毎月").tag(RecurringFrequency.monthly)
                Text("毎年").tag(RecurringFrequency.yearly)
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Day of Month Section

    private var dayOfMonthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("登録日")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                if frequency == .yearly {
                    Picker("月", selection: $monthOfYear) {
                        ForEach(1...12, id: \.self) { month in
                            Text("\(month)月").tag(month)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Picker("日", selection: $dayOfMonth) {
                    ForEach(1...28, id: \.self) { day in
                        Text("\(day)日").tag(day)
                    }
                }
                .pickerStyle(.menu)

                Spacer()
            }

            Text("※ 29日以降は月末の不一致を避けるため選択できません")
                .font(.caption2)
                .foregroundStyle(AppColors.muted)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Yearly Amortization Section

    private var yearlyAmortizationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("登録方法")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("登録方法", selection: $yearlyAmortizationMode) {
                Text("一括登録").tag(YearlyAmortizationMode.lumpSum)
                Text("月次分割").tag(YearlyAmortizationMode.monthlySpread)
            }
            .pickerStyle(.segmented)

            if yearlyAmortizationMode == .monthlySpread {
                Text("年額を開始月から年末までの対象月数で分割し、毎月\(dayOfMonth)日に登録します")
                    .font(.caption)
                    .foregroundStyle(AppColors.primary)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Category Section

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("カテゴリ")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filteredCategories) { category in
                        categoryChip(category)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func categoryChip(_ category: PPCategory) -> some View {
        let isSelected = selectedCategoryId == category.id

        return Button(action: {
            if isSelected {
                selectedCategoryId = nil
            } else {
                selectedCategoryId = category.id
            }
        }) {
            Text(category.name)
                .font(.caption)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? AppColors.primary : AppColors.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : AppColors.muted.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Accounting Section

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
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Allocation Mode Section

    private var allocationModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("配分方式")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("配分方式", selection: $allocationMode) {
                Text("全体（均等割）").tag(AllocationMode.equalAll)
                Text("プロジェクト指定").tag(AllocationMode.manual)
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: allocationMode) { _, newMode in
            if newMode == .equalAll {
                allocations = []
            }
        }
    }

    @ViewBuilder
    private var distributionTemplateSection: some View {
        if isLoadingDistributionTemplates
            || !distributionTemplates.isEmpty
            || distributionTemplateErrorMessage != nil
            || unavailableDistributionTemplateCount > 0
            || pendingDistributionApproval != nil
        {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("配賦テンプレート")
                        .font(.caption)
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

                    Button("テンプレートをプレビュー") {
                        previewSelectedDistributionTemplate()
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

                if let pendingDistributionApproval {
                    distributionApprovalCard(preview: pendingDistributionApproval)
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func distributionApprovalCard(
        preview: DistributionTemplateApplicationUseCase.ApprovalPreview
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("承認待ちプレビュー")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.primary)

            Text(preview.ruleName)
                .font(.subheadline.weight(.semibold))

            distributionApprovalStateView(title: "変更前", state: preview.currentState)

            if let proposedState = preview.proposedState {
                distributionApprovalStateView(title: "変更後", state: proposedState)
            }

            if !preview.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(preview.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.warning)
                    }
                }
            }

            HStack {
                Button("破棄", role: .destructive) {
                    discardPendingDistributionApproval()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("承認して反映") {
                    applyPendingDistributionApproval()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func distributionApprovalStateView(
        title: String,
        state: DistributionTemplateApplicationUseCase.ApprovalState
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            switch state {
            case .equalAll:
                Text(AllocationMode.equalAll.label)
                    .font(.subheadline)
            case let .manual(allocations):
                if allocations.isEmpty {
                    Text("未設定")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(allocations, id: \.projectId) { allocation in
                            let name = recurringQueryUseCase.projectName(
                                id: allocation.projectId,
                                snapshot: formSnapshot
                            ) ?? "不明なプロジェクト"
                            HStack {
                                Text(name)
                                Spacer()
                                Text("\(allocation.ratio)%")
                                    .foregroundStyle(.secondary)
                                Text(formatCurrency(allocation.amount))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private var equalAllInfoSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(AppColors.primary)
            Text("取引登録時に全アクティブプロジェクトへ均等配分されます")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Counterparty Field

    private var counterpartyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("取引先")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !counterparties.isEmpty {
                Picker("登録済み取引先", selection: counterpartyPickerSelection) {
                    Text("選択しない").tag(UUID?.none)
                    ForEach(counterparties, id: \.id) { counterparty in
                        Text(counterparty.displayName).tag(UUID?.some(counterparty.id))
                    }
                }
                .pickerStyle(.menu)
            }

            TextField("取引先名（任意）", text: $counterparty)
                .onChange(of: counterparty) { _, newValue in
                    guard let selectedCounterparty else { return }
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty || trimmed != selectedCounterparty.displayName {
                        selectedCounterpartyId = nil
                    }
                }
                .textFieldStyle(.roundedBorder)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Memo Field

    private var memoField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("メモ")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("メモ（任意）", text: $memo, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - End Date Section

    private var endDateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("終了日を設定", isOn: $hasEndDate)
                .font(.subheadline)
                .tint(AppColors.primary)

            if hasEndDate {
                DatePicker(
                    "終了日",
                    selection: $endDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .environment(\.locale, Locale(identifier: "ja_JP"))

                Text("この日以降は新しい取引が自動登録されません。過去の取引はそのまま保持されます。")
                    .font(.caption2)
                    .foregroundStyle(AppColors.muted)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Active Toggle

    private var activeToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("有効/無効")
                    .font(.subheadline)
                Text(isActive ? "この定期取引は有効です" : "この定期取引は停止中です")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isActive)
                .labelsHidden()
                .tint(AppColors.primary)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Image Helpers

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

    private func loadFormSnapshot() {
        formSnapshot = recurringQueryUseCase.formSnapshot()
        if counterparty.isEmpty, let selectedCounterparty {
            counterparty = selectedCounterparty.displayName
        }
    }

    private func loadDistributionTemplates() async {
        guard let businessId = formSnapshot.businessId else {
            distributionTemplates = []
            selectedDistributionTemplateId = nil
            distributionTemplateErrorMessage = nil
            unavailableDistributionTemplateCount = 0
            return
        }

        isLoadingDistributionTemplates = true
        defer { isLoadingDistributionTemplates = false }

        do {
            let templates = try await recurringQueryUseCase.activeDistributionTemplates(
                businessId: businessId,
                at: templateReferenceDate,
                allocationPeriod: distributionTemplateAllocationPeriod
            )
            distributionTemplates = templates.supportedRules
            unavailableDistributionTemplateCount = templates.unsupportedCount
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

    private func previewSelectedDistributionTemplate() {
        guard let selectedDistributionTemplateId,
              let rule = distributionTemplates.first(where: { $0.id == selectedDistributionTemplateId })
        else {
            return
        }

        let preview = distributionTemplateApplicationUseCase.makeApprovalPreview(
            rule: rule,
            currentState: distributionTemplateApplicationUseCase.currentApprovalState(
                allocationMode: allocationMode,
                allocations: allocations.map { (projectId: $0.projectId, ratio: $0.ratio) },
                totalAmount: parsedAmount ?? 0
            ),
            projects: formSnapshot.projects,
            referenceDate: templateReferenceDate,
            totalAmount: parsedAmount ?? 0,
            allocationPeriod: distributionTemplateAllocationPeriod,
            supportsEqualAllMode: true
        )

        guard preview.isApprovable else {
            pendingDistributionApproval = nil
            distributionTemplateErrorMessage = preview.warnings.first ?? "配賦プレビューを生成できませんでした。"
            return
        }

        pendingDistributionApproval = preview
        distributionTemplateErrorMessage = nil
    }

    private func applyPendingDistributionApproval() {
        guard let pendingDistributionApproval else { return }
        do {
            let approved = try distributionTemplateApplicationUseCase.approve(pendingDistributionApproval)
            allocationMode = approved.allocationMode
            allocations = approved.allocations.map { allocation in
                (id: UUID(), projectId: allocation.projectId, ratio: allocation.ratio)
            }
            self.pendingDistributionApproval = nil
            distributionTemplateErrorMessage = nil
        } catch {
            distributionTemplateErrorMessage = error.localizedDescription
        }
    }

    private func discardPendingDistributionApproval() {
        pendingDistributionApproval = nil
    }

    private func invalidatePendingDistributionApproval() {
        guard pendingDistributionApproval != nil else { return }
        pendingDistributionApproval = nil
    }

    private func applySelectedCounterpartyDefaults() {
        guard let selectedCounterpartyId,
              let defaults = recurringQueryUseCase.counterpartyDefaults(
                for: selectedCounterpartyId,
                type: type,
                snapshot: formSnapshot
              )
        else {
            return
        }

        counterparty = defaults.displayName
        paymentAccountId = defaults.paymentAccountId
        if type != .transfer, let defaultProjectId = defaults.projectId {
            allocationMode = .manual
            allocations = [(id: UUID(), projectId: defaultProjectId, ratio: 100)]
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty else {
            validationMessage = "名前を入力してください"
            showValidationError = true
            return
        }

        guard let amount = parsedAmount, amount > 0 else {
            validationMessage = "有効な金額を入力してください"
            showValidationError = true
            return
        }

        guard dayOfMonth >= 1 && dayOfMonth <= 28 else {
            validationMessage = "登録日は1〜28の間で入力してください"
            showValidationError = true
            return
        }

        if allocationMode == .manual {
            guard !allocations.isEmpty else {
                validationMessage = "プロジェクト配分を1件以上設定してください"
                showValidationError = true
                return
            }
            let totalRatio = allocations.reduce(0) { $0 + $1.ratio }
            if totalRatio != 100 {
                validationMessage = "プロジェクト配分の合計は100%にしてください"
                showValidationError = true
                return
            }
        }

        guard let categoryId = selectedCategoryId, !categoryId.isEmpty else {
            validationMessage = "カテゴリを選択してください"
            showValidationError = true
            return
        }
        guard !hasPendingDistributionApproval else {
            validationMessage = "配賦テンプレートのプレビューを承認または破棄してください"
            showValidationError = true
            return
        }
        let resolvedMonthOfYear = frequency == .yearly ? monthOfYear : nil
        let resolvedEndDate: Date? = hasEndDate ? endDate : nil
        let resolvedAmortizationMode: YearlyAmortizationMode = frequency == .yearly ? yearlyAmortizationMode : .lumpSum

        var imagePath: String?
        if let image = selectedImage {
            do {
                imagePath = try ReceiptImageStore.saveImage(image)
            } catch {
                // 画像保存失敗でも定期取引は保存する
            }
        }

        // Phase 9A: 会計フィールド解決
        let resolvedPaymentAccountId: String? = paymentAccountId
        let resolvedTransferToAccountId: String? = transferToAccountId
        let resolvedTaxDeductibleRate: Int? = taxDeductibleRate == 100 ? nil : taxDeductibleRate
        let resolvedCounterpartyName = selectedCounterparty?.displayName
            ?? counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCounterparty: String? = resolvedCounterpartyName.isEmpty ? nil : resolvedCounterpartyName
        let resolvedReceiptImagePath: String?
        if selectedImage != nil {
            resolvedReceiptImagePath = imagePath
        } else if imageRemoved {
            resolvedReceiptImagePath = nil
        } else {
            resolvedReceiptImagePath = recurring?.receiptImagePath
        }

        let input = RecurringUpsertInput(
            name: trimmedName,
            type: type,
            amount: amount,
            categoryId: categoryId,
            memo: memo,
            allocationMode: allocationMode,
            allocations: allocations.map { RecurringAllocationInput(projectId: $0.projectId, ratio: $0.ratio) },
            frequency: frequency,
            dayOfMonth: dayOfMonth,
            monthOfYear: resolvedMonthOfYear,
            isActive: isActive,
            endDate: resolvedEndDate,
            yearlyAmortizationMode: resolvedAmortizationMode,
            receiptImagePath: resolvedReceiptImagePath,
            paymentAccountId: resolvedPaymentAccountId,
            transferToAccountId: resolvedTransferToAccountId,
            taxDeductibleRate: resolvedTaxDeductibleRate,
            counterpartyId: selectedCounterpartyId,
            counterparty: resolvedCounterparty
        )

        if let existing = recurring {
            if selectedImage != nil || imageRemoved {
                if let oldPath = existing.receiptImagePath {
                    ReceiptImageStore.deleteImage(fileName: oldPath)
                }
            }
            recurringWorkflowUseCase.updateRecurring(id: existing.id, input: input)
        } else {
            recurringWorkflowUseCase.createRecurring(input: input)
        }

        dismiss()
    }
}

#Preview {
    RecurringFormView()
        .modelContainer(try! ModelContainer(
            for: PPProject.self,
            PPTransaction.self,
            PPCategory.self,
            PPRecurringTransaction.self,
            DistributionRuleEntity.self
        ))
        .environment(NotificationService())
}
