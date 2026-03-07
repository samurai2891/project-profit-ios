import SwiftData
import SwiftUI
import UIKit

struct EvidenceInboxView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.modelContext) private var modelContext

    @State private var evidences: [EvidenceDocument] = []
    @State private var selectedStatus: ComplianceStatus?
    @State private var searchForm = EvidenceSearchFormState()
    @State private var showScanner = false
    @State private var showSearchFilters = false
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isReindexing = false

    private var isCurrentYearLocked: Bool {
        let currentYear = currentFiscalYear(startMonth: FiscalYearSettings.startMonth)
        let state = dataStore.yearLockState(for: currentYear)
        return state != .open && !state.allowsNormalPosting
    }

    var body: some View {
        List {
            if isCurrentYearLocked {
                Section {
                    Label("現在の年度はロック中のため、新規証憑の取込はできません", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                }
            }

            Section {
                Picker(
                    "ステータス",
                    selection: Binding(
                        get: { selectedStatus?.rawValue ?? "all" },
                        set: { selectedStatus = $0 == "all" ? nil : ComplianceStatus(rawValue: $0) }
                    )
                ) {
                    Text("すべて").tag("all")
                    ForEach(ComplianceStatus.allCases, id: \.rawValue) { status in
                        Text(statusLabel(status)).tag(status.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("証憑 (\(evidences.count))") {
                if isLoading || isReindexing {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if evidences.isEmpty {
                    ContentUnavailableView(
                        "証憑はありません",
                        systemImage: "tray",
                        description: Text(searchForm.hasActiveFilters ? "検索条件を見直してください" : "右上の書類読取から証憑を取り込みます")
                    )
                } else {
                    ForEach(evidences, id: \.id) { evidence in
                        NavigationLink {
                            EvidenceDetailView(evidence: evidence)
                        } label: {
                            evidenceRow(evidence)
                        }
                    }
                }
            }
        }
        .navigationTitle("証憑Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Menu {
                        Button("検索条件") {
                            showSearchFilters = true
                        }
                        Button("再索引") {
                            Task { await rebuildEvidenceIndex() }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("検索条件")
                    .accessibilityHint("証憑検索条件と再索引を開きます")

                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "doc.text.viewfinder")
                    }
                    .accessibilityLabel("書類読取")
                    .accessibilityHint("新しい証憑を取り込みます")
                    .disabled(isCurrentYearLocked)
                }
            }
        }
        .task(id: reloadKey) {
            await loadEvidence()
        }
        .searchable(
            text: Binding(
                get: { searchForm.textQuery },
                set: { searchForm.textQuery = $0 }
            ),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "ファイル名 / OCR / 取引先 / ハッシュ"
        )
        .sheet(isPresented: $showScanner, onDismiss: {
            Task { await loadEvidence() }
        }) {
            ReceiptScannerView()
        }
        .sheet(isPresented: $showSearchFilters) {
            EvidenceSearchFilterSheet(
                form: $searchForm,
                projects: dataStore.projects
            )
        }
        .alert("読み込みエラー", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var reloadKey: String {
        [
            dataStore.businessProfile?.id.uuidString ?? "none",
            selectedStatus?.rawValue ?? "all",
            searchForm.reloadToken,
        ].joined(separator: ":")
    }

    @ViewBuilder
    private func evidenceRow(_ evidence: EvidenceDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(evidence.structuredFields?.counterpartyName ?? evidence.originalFilename)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(evidence.legalDocumentType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(statusLabel(evidence.complianceStatus))
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(evidence.complianceStatus).opacity(0.12))
                    .foregroundStyle(statusColor(evidence.complianceStatus))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                if let totalAmount = evidence.structuredFields?.totalAmount {
                    Label(formatAmount(totalAmount), systemImage: "yensign")
                }
                if let issueDate = evidence.issueDate {
                    Label(formatDate(issueDate), systemImage: "calendar")
                }
                Label(sourceLabel(evidence.sourceType), systemImage: "tray.and.arrow.down")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !evidence.linkedProjectIds.isEmpty {
                Text(projectLabels(for: evidence.linkedProjectIds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadEvidence() async {
        guard let businessId = dataStore.businessProfile?.id else {
            evidences = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let criteria = searchForm.makeCriteria(
                businessId: businessId,
                complianceStatus: selectedStatus
            )
            evidences = try await EvidenceCatalogUseCase(modelContext: modelContext).search(criteria)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rebuildEvidenceIndex() async {
        guard let businessId = dataStore.businessProfile?.id else { return }
        isReindexing = true
        defer { isReindexing = false }

        do {
            try SearchIndexRebuilder(modelContext: modelContext)
                .rebuildEvidenceIndex(businessId: businessId)
            await loadEvidence()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func projectLabels(for ids: [UUID]) -> String {
        ids.compactMap { dataStore.getProject(id: $0)?.name }
            .joined(separator: " / ")
    }

    private func formatAmount(_ amount: Decimal) -> String {
        let number = NSDecimalNumber(decimal: amount)
        return NumberFormatter.currency.string(from: number) ?? number.stringValue
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    private func sourceLabel(_ sourceType: EvidenceSourceType) -> String {
        switch sourceType {
        case .camera: "カメラ"
        case .photoLibrary: "写真"
        case .scannedPDF: "スキャンPDF"
        case .emailAttachment: "メール添付"
        case .importedPDF: "PDF取込"
        case .manualNoFile: "手入力"
        }
    }

    private func statusLabel(_ status: ComplianceStatus) -> String {
        switch status {
        case .compliant: "適合"
        case .pendingReview: "確認待ち"
        case .nonCompliant: "不適合"
        case .unknown: "不明"
        }
    }

    private func statusColor(_ status: ComplianceStatus) -> Color {
        switch status {
        case .compliant: AppColors.success
        case .pendingReview: AppColors.warning
        case .nonCompliant: AppColors.error
        case .unknown: AppColors.muted
        }
    }
}

private struct EvidenceDetailView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.modelContext) private var modelContext

    let evidence: EvidenceDocument

    @State private var candidates: [PostingCandidate] = []
    @State private var journals: [CanonicalJournalEntry] = []
    @State private var relatedRecordsError: String?
    @State private var showShareSheet = false

    private var previewImage: UIImage? {
        guard evidence.mimeType.hasPrefix("image/"),
              let data = ReceiptImageStore.loadDocumentData(fileName: evidence.originalFilePath)
        else {
            return nil
        }
        return UIImage(data: data)
    }

    private var documentURL: URL? {
        ReceiptImageStore.documentFileURL(fileName: evidence.originalFilePath)
    }

    var body: some View {
        List {
            if let previewImage {
                Section("原本") {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            Section("基本情報") {
                detailRow("書類種別", evidence.legalDocumentType.displayName)
                detailRow("保存区分", storageCategoryLabel(evidence.storageCategory))
                detailRow("ファイル名", evidence.originalFilename)
                if let issueDate = evidence.issueDate {
                    detailRow("発行日", formatDate(issueDate))
                }
                detailRow("受領日", formatDate(evidence.receivedAt))
            }

            if let structuredFields = evidence.structuredFields {
                Section("抽出結果") {
                    if let counterpartyName = structuredFields.counterpartyName {
                        detailRow("取引先", counterpartyName)
                    }
                    if let totalAmount = structuredFields.totalAmount {
                        detailRow("金額", formatAmount(totalAmount))
                    }
                    if let confidence = structuredFields.confidence {
                        detailRow("信頼度", "\(Int(confidence * 100))%")
                    }
                    ForEach(structuredFields.lineItems, id: \.id) { item in
                        detailRow(item.description, formatAmount(item.lineAmount))
                    }
                }
            }

            if let ocrText = evidence.ocrText, !ocrText.isEmpty {
                Section("OCR") {
                    Text(ocrText)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }

            if !candidates.isEmpty {
                Section("仕訳候補") {
                    ForEach(candidates, id: \.id) { candidate in
                        NavigationLink {
                            ApprovalCandidateDetailView(candidateId: candidate.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.status.displayName)
                                        .font(.subheadline.weight(.medium))
                                    if let memo = candidate.memo, !memo.isEmpty {
                                        Text(memo)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(formatAmount(candidate.proposedLines.reduce(Decimal.zero) { $0 + $1.amount }))
                                    .font(.caption.weight(.medium).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !journals.isEmpty {
                Section("確定仕訳") {
                    ForEach(journals, id: \.id) { journal in
                        NavigationLink {
                            JournalDetailView(entry: projectedEntry(for: journal))
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(journal.voucherNo)
                                        .font(.subheadline.weight(.medium))
                                    Text(journal.description.isEmpty ? "摘要なし" : journal.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(formatAmount(journal.totalDebit))
                                    .font(.caption.weight(.medium).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if documentURL != nil {
                Section {
                    Button("共有") {
                        showShareSheet = true
                    }
                }
            }
        }
        .navigationTitle("証憑詳細")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await loadRelatedRecords() }
        }
        .sheet(isPresented: $showShareSheet) {
            if let documentURL {
                ShareSheetView(activityItems: [documentURL])
            }
        }
        .alert("関連データ読み込みエラー", isPresented: Binding(
            get: { relatedRecordsError != nil },
            set: { if !$0 { relatedRecordsError = nil } }
        )) {
            Button("OK", role: .cancel) { relatedRecordsError = nil }
        } message: {
            Text(relatedRecordsError ?? "")
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func storageCategoryLabel(_ category: StorageCategory) -> String {
        switch category {
        case .paperScan: "紙スキャン"
        case .electronicTransaction: "電子取引"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    private func formatAmount(_ amount: Decimal) -> String {
        let number = NSDecimalNumber(decimal: amount)
        return NumberFormatter.currency.string(from: number) ?? number.stringValue
    }

    private func loadRelatedRecords() async {
        do {
            let workflow = PostingWorkflowUseCase(modelContext: modelContext)
            candidates = try await workflow.candidates(evidenceId: evidence.id)
            journals = dataStore.canonicalJournalEntries(evidenceId: evidence.id)
        } catch {
            relatedRecordsError = error.localizedDescription
        }
    }

    private func projectedEntry(for journal: CanonicalJournalEntry) -> PPJournalEntry {
        PPJournalEntry(
            id: journal.id,
            sourceKey: "canonical:\(journal.id.uuidString)",
            date: journal.journalDate,
            entryType: journal.entryType == .closing ? .closing : (journal.entryType == .opening ? .opening : .auto),
            memo: journal.description,
            isPosted: journal.approvedAt != nil,
            createdAt: journal.createdAt,
            updatedAt: journal.updatedAt
        )
    }
}

private extension NumberFormatter {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "JPY"
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
