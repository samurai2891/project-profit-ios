import SwiftUI

struct ReceiptReviewView: View {
    @Environment(DataStore.self) private var dataStore

    let receiptData: ReceiptData
    let receiptImage: UIImage?
    let defaultProjectId: UUID?
    let onDismiss: () -> Void

    @State private var amountText: String = ""
    @State private var date: Date = Date()
    @State private var categoryId: String = ""
    @State private var memo: String = ""
    @State private var allocations: [(id: UUID, projectId: UUID, ratio: Int)] = []
    @State private var editableLineItems: [EditableLineItem] = []
    @State private var isSubmitting = false
    @State private var isInitialized = false
    @State private var showImagePreview = false
    @State private var saveError: String?

    init(receiptData: ReceiptData, receiptImage: UIImage? = nil, defaultProjectId: UUID? = nil, onDismiss: @escaping () -> Void) {
        self.receiptData = receiptData
        self.receiptImage = receiptImage
        self.defaultProjectId = defaultProjectId
        self.onDismiss = onDismiss
    }

    private var expenseCategories: [PPCategory] {
        dataStore.categories.filter { $0.type == .expense }
    }

    private var totalRatio: Int {
        allocations.reduce(0) { $0 + $1.ratio }
    }

    private var isValid: Bool {
        guard let amount = Int(amountText), amount > 0 else { return false }
        return !categoryId.isEmpty && !allocations.isEmpty && totalRatio == 100
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ocrBanner
                receiptImageSection
                amountSection
                dateSection
                categorySection
                LineItemsEditView(items: $editableLineItems)
                allocationSection
                memoSection
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("登録") { save() }
                    .disabled(!isValid || isSubmitting)
                    .accessibilityLabel("登録")
                    .accessibilityHint(isValid ? "タップしてレシートの取引を登録" : "すべての必須項目を入力してください")
            }
        }
        .onAppear { setupFromReceiptData() }
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
                Text("レシート読み取り結果")
                    .font(.subheadline.weight(.medium))
                Text("内容を確認して必要に応じて修正してください")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(AppColors.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("レシート読み取り結果。内容を確認して必要に応じて修正してください")
    }

    // MARK: - Receipt Image

    @ViewBuilder
    private var receiptImageSection: some View {
        if let image = receiptImage {
            VStack(alignment: .leading, spacing: 8) {
                Text("レシート画像")
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
                .accessibilityLabel("レシート画像をプレビュー")
                .accessibilityHint("タップして全画面表示")
            }
        }
    }

    // MARK: - Amount

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("金額")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("経費")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.error.opacity(0.12))
                    .foregroundStyle(AppColors.error)
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(expenseCategories, id: \.id) { cat in
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

            if dataStore.projects.count > allocations.count {
                addProjectButton
            }
        }
    }

    private func allocationRow(index: Int, alloc: (id: UUID, projectId: UUID, ratio: Int)) -> some View {
        let projectName = dataStore.getProject(id: alloc.projectId)?.name ?? "選択"
        return HStack {
            Menu {
                ForEach(dataStore.projects, id: \.id) { project in
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
            if let available = dataStore.projects.first(where: { !usedIds.contains($0.id) }) {
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

    private func setupFromReceiptData() {
        guard !isInitialized else { return }
        isInitialized = true

        amountText = receiptData.totalAmount > 0 ? String(receiptData.totalAmount) : ""
        date = receiptData.parsedDate
        categoryId = receiptData.categoryId
        memo = receiptData.formattedMemo
        editableLineItems = receiptData.lineItems.map { EditableLineItem(from: $0) }

        // Validate category exists
        if !expenseCategories.contains(where: { $0.id == categoryId }) {
            categoryId = expenseCategories.first?.id ?? "cat-other-expense"
        }

        // Default allocation - use defaultProjectId if provided
        if let projectId = defaultProjectId, dataStore.projects.contains(where: { $0.id == projectId }) {
            allocations = [(id: UUID(), projectId: projectId, ratio: 100)]
        } else if let firstProject = dataStore.projects.first {
            allocations = [(id: UUID(), projectId: firstProject.id, ratio: 100)]
        }
    }

    private func save() {
        guard isValid, let amount = Int(amountText) else { return }
        isSubmitting = true
        saveError = nil

        // Validate amount is positive
        guard amount > 0 else { return }

        // Validate date is not in the future
        let validDate = min(date, Date())

        // Save receipt image with error handling
        var imagePath: String?
        if let image = receiptImage {
            do {
                imagePath = try ReceiptImageStore.saveImage(image)
                // Verify the image was actually saved
                if let path = imagePath, !ReceiptImageStore.imageExists(fileName: path) {
                    AppLogger.receipt.error("Receipt image save verification failed")
                    imagePath = nil
                }
            } catch {
                AppLogger.receipt.error("Failed to save receipt image: \(error.localizedDescription)")
                // Continue without image - don't block transaction save
            }
        }

        // Convert line items
        let lineItems = editableLineItems
            .filter { !$0.name.isEmpty && $0.unitPrice > 0 }
            .map { $0.toReceiptLineItem() }

        let allocs = allocations.map { (projectId: $0.projectId, ratio: $0.ratio) }
        dataStore.addTransaction(
            type: .expense,
            amount: amount,
            date: validDate,
            categoryId: categoryId,
            memo: memo,
            allocations: allocs,
            receiptImagePath: imagePath,
            lineItems: lineItems
        )

        onDismiss()
    }
}
