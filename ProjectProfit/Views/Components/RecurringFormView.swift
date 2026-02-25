import PhotosUI
import SwiftData
import SwiftUI

struct RecurringFormView: View {
    @Environment(DataStore.self) private var dataStore
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

    @State private var showValidationError = false
    @State private var validationMessage = ""
    @State private var selectedImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showReceiptPreview = false
    @State private var showRemoveImageAlert = false
    @State private var imageRemoved = false

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
    }

    // MARK: - Computed Properties

    private var filteredCategories: [PPCategory] {
        switch type {
        case .expense, .transfer:
            return dataStore.categories.filter { $0.type == .expense }
        case .income:
            return dataStore.categories.filter { $0.type == .income }
        }
    }

    private var parsedAmount: Int? {
        Int(amountText)
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedAmount != nil
            && (parsedAmount ?? 0) > 0
            && dayOfMonth >= 1
            && dayOfMonth <= 28
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
                        allocationModeSection
                        if allocationMode == .manual {
                            projectAllocationSection
                        } else {
                            equalAllInfoSection
                        }
                        memoField
                        receiptImageSection
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
                        .disabled(!isFormValid)
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
                Text("年額を12ヶ月で分割し、毎月\(dayOfMonth)日に登録します")
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

    // MARK: - Project Allocation Section

    private var totalRatio: Int {
        allocations.reduce(0) { $0 + $1.ratio }
    }

    private var projectAllocationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("プロジェクト配分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("合計: \(totalRatio)%")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(totalRatio == 100 ? AppColors.success : AppColors.error)
            }

            if dataStore.projects.filter({ $0.isArchived != true }).isEmpty {
                Text("プロジェクトがありません")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.muted)
            } else {
                ForEach(Array(allocations.enumerated()), id: \.element.id) { index, alloc in
                    let projectName = dataStore.getProject(id: alloc.projectId)?.name ?? "選択"
                    HStack {
                        Menu {
                            let usedIds = Set(allocations.map(\.projectId))
                            ForEach(dataStore.projects.filter { p in
                                p.isArchived != true && (!usedIds.contains(p.id) || p.id == alloc.projectId)
                            }, id: \.id) { project in
                                Button(project.name) {
                                    var updated = allocations
                                    updated[index] = (id: alloc.id, projectId: project.id, ratio: alloc.ratio)
                                    allocations = updated
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

                        Spacer()

                        HStack(spacing: 4) {
                            TextField("0", text: Binding(
                                get: { String(allocations[index].ratio) },
                                set: { newValue in
                                    let clamped = min(100, max(0, Int(newValue) ?? 0))
                                    var updated = allocations
                                    updated[index] = (id: alloc.id, projectId: alloc.projectId, ratio: clamped)
                                    allocations = updated
                                }
                            ))
                            .keyboardType(.numberPad)
                            .frame(width: 50)
                            .multilineTextAlignment(.center)
                            .padding(6)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border))

                            Text("%")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if allocations.count > 1 {
                            Button {
                                allocations = allocations.filter { $0.id != alloc.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppColors.error)
                            }
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
                            allocations = allocations + [(id: UUID(), projectId: available.id, ratio: 0)]
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
                }
            }
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

    // MARK: - Receipt Image Section

    private var receiptImageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("添付画像")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let image = selectedImage {
                receiptImagePreviewRow(image: image)
            } else if !imageRemoved, let r = recurring, let imagePath = r.receiptImagePath,
                      let existingImage = ReceiptImageStore.loadImage(fileName: imagePath) {
                receiptImagePreviewRow(image: existingImage)
            } else {
                recurringImagePickerButtons
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func receiptImagePreviewRow(image: UIImage) -> some View {
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

                recurringImagePickerButtons
            }
        }
    }

    @ViewBuilder
    private var recurringImagePickerButtons: some View {
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
            let totalRatio = allocations.reduce(0) { $0 + $1.ratio }
            if totalRatio > 0 && totalRatio != 100 {
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

        if let existing = recurring {
            if selectedImage != nil {
                if let oldPath = existing.receiptImagePath {
                    ReceiptImageStore.deleteImage(fileName: oldPath)
                }
                dataStore.updateRecurring(
                    id: existing.id,
                    name: trimmedName,
                    type: type,
                    amount: amount,
                    categoryId: categoryId,
                    memo: memo,
                    allocationMode: allocationMode,
                    allocations: allocations.map { (projectId: $0.projectId, ratio: $0.ratio) },
                    frequency: frequency,
                    dayOfMonth: dayOfMonth,
                    monthOfYear: resolvedMonthOfYear,
                    isActive: isActive,
                    endDate: resolvedEndDate,
                    yearlyAmortizationMode: resolvedAmortizationMode,
                    receiptImagePath: imagePath
                )
            } else if imageRemoved {
                if let oldPath = existing.receiptImagePath {
                    ReceiptImageStore.deleteImage(fileName: oldPath)
                }
                dataStore.updateRecurring(
                    id: existing.id,
                    name: trimmedName,
                    type: type,
                    amount: amount,
                    categoryId: categoryId,
                    memo: memo,
                    allocationMode: allocationMode,
                    allocations: allocations.map { (projectId: $0.projectId, ratio: $0.ratio) },
                    frequency: frequency,
                    dayOfMonth: dayOfMonth,
                    monthOfYear: resolvedMonthOfYear,
                    isActive: isActive,
                    endDate: resolvedEndDate,
                    yearlyAmortizationMode: resolvedAmortizationMode,
                    receiptImagePath: .some(nil)
                )
            } else {
                dataStore.updateRecurring(
                    id: existing.id,
                    name: trimmedName,
                    type: type,
                    amount: amount,
                    categoryId: categoryId,
                    memo: memo,
                    allocationMode: allocationMode,
                    allocations: allocations.map { (projectId: $0.projectId, ratio: $0.ratio) },
                    frequency: frequency,
                    dayOfMonth: dayOfMonth,
                    monthOfYear: resolvedMonthOfYear,
                    isActive: isActive,
                    endDate: resolvedEndDate,
                    yearlyAmortizationMode: resolvedAmortizationMode
                )
            }
        } else {
            dataStore.addRecurring(
                name: trimmedName,
                type: type,
                amount: amount,
                categoryId: categoryId,
                memo: memo,
                allocationMode: allocationMode,
                allocations: allocations.map { (projectId: $0.projectId, ratio: $0.ratio) },
                frequency: frequency,
                dayOfMonth: dayOfMonth,
                monthOfYear: resolvedMonthOfYear,
                endDate: resolvedEndDate,
                yearlyAmortizationMode: resolvedAmortizationMode,
                receiptImagePath: imagePath
            )
        }

        dismiss()
    }
}

#Preview {
    RecurringFormView()
        .environment(DataStore(modelContext: try! ModelContext(ModelContainer(for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self))))
}
