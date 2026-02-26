import SwiftUI

struct LegalDocumentLedgerView: View {
    @Environment(DataStore.self) private var dataStore

    @State private var selectedCategory: RetentionCategory?
    @State private var records: [PPDocumentRecord] = []
    @State private var logs: [PPComplianceLog] = []
    @State private var alertMessage: String?
    @State private var pendingWarningDeleteId: UUID?
    @State private var pendingWarningMessage: String?
    @State private var showShareSheet = false
    @State private var shareItem: Any = ""

    private var filteredRecords: [PPDocumentRecord] {
        guard let selectedCategory else { return records }
        return records.filter { $0.retentionCategory == selectedCategory }
    }

    var body: some View {
        List {
            Section {
                Picker("保存区分", selection: Binding(
                    get: { selectedCategory?.rawValue ?? "all" },
                    set: { selectedCategory = $0 == "all" ? nil : RetentionCategory(rawValue: $0) }
                )) {
                    Text("すべて").tag("all")
                    ForEach(RetentionCategory.allCases, id: \.rawValue) { category in
                        Text(category.label).tag(category.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("書類一覧 (\(filteredRecords.count))") {
                if filteredRecords.isEmpty {
                    Text("該当する書類はありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredRecords, id: \.id) { record in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.documentType.label)
                                        .font(.subheadline.weight(.semibold))
                                    Text(record.originalFileName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(record.retentionCategory.label)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(AppColors.primary.opacity(0.1))
                                    .foregroundStyle(AppColors.primary)
                                    .clipShape(Capsule())
                            }
                            Text("発行日: \(formatDate(record.issueDate)) / 保存期限: \(formatDate(record.retentionDeadline))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let warning = record.retentionWarningMessage() {
                                Text(warning)
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.warning)
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
                                    let attempt = dataStore.requestDocumentDeletion(id: record.id)
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

            Section("監査ログ（最新10件）") {
                if logs.isEmpty {
                    Text("監査ログはありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logs.prefix(10), id: \.id) { log in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.message)
                                .font(.caption)
                            Text(formatDate(log.createdAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("書類台帳")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .sheet(isPresented: $showShareSheet) {
            ShareSheetView(activityItems: [shareItem])
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
                let attempt = dataStore.confirmDocumentDeletion(id: id, reason: "書類台帳から手動削除")
                handleDeleteAttempt(attempt)
                pendingWarningDeleteId = nil
                pendingWarningMessage = nil
            }
        } message: {
            Text(pendingWarningMessage ?? "")
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
        records = dataStore.listDocumentRecords()
        logs = dataStore.listComplianceLogs(limit: 10)
    }
}
