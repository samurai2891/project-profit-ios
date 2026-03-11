import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TransactionDocumentsView: View {
    @Environment(\.modelContext) private var modelContext

    let transaction: PPTransaction

    @State private var records: [PPDocumentRecord] = []
    @State private var selectedDocumentType: LegalDocumentType = .receipt
    @State private var issueDate: Date = Date()
    @State private var note: String = ""

    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showShareSheet = false
    @State private var shareItem: Any = ""

    @State private var alertMessage: String?
    @State private var pendingWarningDeleteId: UUID?
    @State private var pendingWarningMessage: String?

    private var documentWorkflowUseCase: DocumentWorkflowUseCase {
        DocumentWorkflowUseCase(modelContext: modelContext)
    }

    var body: some View {
        List {
            addSection
            documentListSection
        }
        .navigationTitle("書類添付")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onChange(of: photoPickerItem) { _, newItem in
            handlePhotoSelection(newItem)
        }
        .alert("通知", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .alert("保存期間内の削除", isPresented: Binding(
            get: { pendingWarningDeleteId != nil && pendingWarningMessage != nil },
            set: { if !$0 { pendingWarningDeleteId = nil; pendingWarningMessage = nil } }
        )) {
            Button("キャンセル", role: .cancel) {
                pendingWarningDeleteId = nil
                pendingWarningMessage = nil
            }
            Button("削除する", role: .destructive) {
                guard let id = pendingWarningDeleteId else { return }
                let result = documentWorkflowUseCase.confirmDeletion(id: id, reason: "保存期間内削除を手動承認")
                handleDeleteAttempt(result)
                pendingWarningDeleteId = nil
                pendingWarningMessage = nil
            }
        } message: {
            Text(pendingWarningMessage ?? "")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheetView(activityItems: [shareItem])
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.image, UTType.pdf, UTType.data],
            allowsMultipleSelection: false
        ) { result in
            handleFileImportResult(result)
        }
    }

    private var addSection: some View {
        Section("書類を追加") {
            Picker("書類種別", selection: $selectedDocumentType) {
                ForEach(LegalDocumentType.allCases, id: \.rawValue) { type in
                    Text(type.label).tag(type)
                }
            }
            DatePicker("発行日", selection: $issueDate, displayedComponents: .date)
            TextField("メモ（任意）", text: $note)
            HStack(spacing: 12) {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    Label("写真から追加", systemImage: "photo.on.rectangle")
                }
                Button {
                    showFileImporter = true
                } label: {
                    Label("ファイルから追加", systemImage: "doc.badge.plus")
                }
            }
            .font(.subheadline)
        }
    }

    private var documentListSection: some View {
        Section("添付済み書類 (\(records.count))") {
            if records.isEmpty {
                Text("添付された書類はありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records, id: \.id) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.documentType.label)
                                    .font(.subheadline.weight(.medium))
                                Text(record.originalFileName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(record.retentionYears)年")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppColors.primary.opacity(0.1))
                                .foregroundStyle(AppColors.primary)
                                .clipShape(Capsule())
                        }
                        HStack {
                            Text("保存期限: \(formatDate(record.retentionDeadline))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let message = record.retentionWarningMessage() {
                                Text(message.contains("保存期間") ? "保存期間内" : "")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(AppColors.warning)
                            }
                        }
                        HStack(spacing: 16) {
                            Button("共有") {
                                guard let url = ReceiptImageStore.documentFileURL(fileName: record.storedFileName) else {
                                    alertMessage = "ファイルが見つかりません"
                                    return
                                }
                                shareItem = url
                                showShareSheet = true
                            }
                            .font(.caption.weight(.medium))

                            Button("削除", role: .destructive) {
                                let attempt = documentWorkflowUseCase.requestDeletion(id: record.id)
                                if case .warningRequired(let message) = attempt {
                                    pendingWarningDeleteId = record.id
                                    pendingWarningMessage = message
                                } else {
                                    handleDeleteAttempt(attempt)
                                }
                            }
                            .font(.caption.weight(.medium))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                await MainActor.run { alertMessage = "画像データの読み込みに失敗しました" }
                return
            }
            await MainActor.run {
                saveDocument(data: data, fileName: "photo.jpg", mimeType: "image/jpeg")
                photoPickerItem = nil
            }
        }
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                alertMessage = "ファイルアクセスに失敗しました"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                saveDocument(data: data, fileName: url.lastPathComponent, mimeType: nil)
            } catch {
                alertMessage = "ファイル読み込みに失敗しました"
            }
        case .failure:
            alertMessage = "ファイル選択に失敗しました"
        }
    }

    private func saveDocument(data: Data, fileName: String, mimeType: String?) {
        let result = documentWorkflowUseCase.addDocument(
            input: DocumentAddInput(
                transactionId: transaction.id,
                documentType: selectedDocumentType,
                originalFileName: fileName,
                fileData: data,
                mimeType: mimeType,
                issueDate: issueDate,
                note: note
            )
        )
        switch result {
        case .success:
            alertMessage = "書類を追加しました"
            note = ""
            refresh()
        case .failure(let error):
            alertMessage = error.localizedDescription
        }
    }

    private func handleDeleteAttempt(_ attempt: DocumentDeleteAttempt) {
        switch attempt {
        case .deleted:
            alertMessage = "書類を削除しました"
            refresh()
        case .warningRequired(let message):
            pendingWarningMessage = message
        case .failed(let message):
            alertMessage = message
        }
    }

    private func refresh() {
        records = documentWorkflowUseCase.listDocuments(transactionId: transaction.id)
    }
}
