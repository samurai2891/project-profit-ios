import SwiftData
import SwiftUI
import UIKit

private enum ApprovalQueueFilter: String, CaseIterable, Identifiable {
    case pending = "pending"
    case draft = "draft"
    case needsReview = "needsReview"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending:
            return "全待機"
        case .draft:
            return "下書き"
        case .needsReview:
            return "要確認"
        }
    }
}

struct ApprovalQueueView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var candidates: [PostingCandidate] = []
    @State private var counterpartiesById: [UUID: Counterparty] = [:]
    @State private var selectedFilter: ApprovalQueueFilter = .pending
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filteredCandidates: [PostingCandidate] {
        switch selectedFilter {
        case .pending:
            return candidates
        case .draft:
            return candidates.filter { $0.status == .draft }
        case .needsReview:
            return candidates.filter { $0.status == .needsReview }
        }
    }

    private var approvalQueueQueryUseCase: ApprovalQueueQueryUseCase {
        ApprovalQueueQueryUseCase(modelContext: modelContext)
    }

    var body: some View {
        List {
            Section {
                Picker("表示", selection: $selectedFilter) {
                    ForEach(ApprovalQueueFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("承認待ち (\(filteredCandidates.count))") {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if filteredCandidates.isEmpty {
                    ContentUnavailableView(
                        "承認待ち候補はありません",
                        systemImage: "checkmark.seal",
                        description: Text("Evidence から作成された候補がここに表示されます")
                    )
                } else {
                    ForEach(filteredCandidates, id: \.id) { candidate in
                        NavigationLink {
                            ApprovalCandidateDetailView(candidateId: candidate.id) {
                                Task { await loadCandidates() }
                            }
                        } label: {
                            candidateRow(candidate)
                        }
                    }
                }
            }
        }
        .navigationTitle("Approval Queue")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reloadKey) {
            await loadCandidates()
        }
        .refreshable {
            await loadCandidates()
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
        approvalQueueQueryUseCase.reloadKey(selectedFilterRawValue: selectedFilter.rawValue)
    }

    @ViewBuilder
    private func candidateRow(_ candidate: PostingCandidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.counterpartyId.flatMap { counterpartiesById[$0]?.displayName } ?? candidate.memo ?? "摘要なし")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(candidate.source.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(candidate.status.displayName)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(candidate.status).opacity(0.12))
                    .foregroundStyle(statusColor(candidate.status))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                Label(formatDate(candidate.candidateDate), systemImage: "calendar")
                Label(formatAmount(totalAmount(candidate)), systemImage: "yensign")
                if candidate.proposedLines.contains(where: { $0.projectAllocationId != nil }) {
                    Label("配賦あり", systemImage: "square.split.2x2")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func loadCandidates() async {
        guard let businessId = approvalQueueQueryUseCase.currentBusinessId() else {
            candidates = []
            counterpartiesById = [:]
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let workflow = PostingWorkflowUseCase(modelContext: modelContext)
            candidates = try await workflow
                .pendingCandidates(businessId: businessId)
            let counterparties = try await CounterpartyMasterUseCase(modelContext: modelContext)
                .loadCounterparties(businessId: businessId)
            counterpartiesById = Dictionary(uniqueKeysWithValues: counterparties.map { ($0.id, $0) })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func totalAmount(_ candidate: PostingCandidate) -> Decimal {
        candidate.proposedLines.reduce(Decimal.zero) { $0 + $1.amount }
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

    private func statusColor(_ status: CandidateStatus) -> Color {
        switch status {
        case .draft:
            return AppColors.muted
        case .needsReview:
            return AppColors.warning
        case .approved:
            return AppColors.success
        case .rejected:
            return AppColors.error
        }
    }
}

private struct CandidateLineDraft: Identifiable {
    let id: UUID
    var debitAccountId: UUID?
    var creditAccountId: UUID?
    var amountText: String
    var taxCodeId: String?
    var projectAllocationId: UUID?
    var memo: String

    init(line: PostingCandidateLine) {
        self.id = line.id
        self.debitAccountId = line.debitAccountId
        self.creditAccountId = line.creditAccountId
        self.amountText = NSDecimalNumber(decimal: line.amount).stringValue
        self.taxCodeId = line.taxCodeId
        self.projectAllocationId = line.projectAllocationId
        self.memo = line.memo ?? ""
    }

    init() {
        self.id = UUID()
        self.debitAccountId = nil
        self.creditAccountId = nil
        self.amountText = ""
        self.taxCodeId = nil
        self.projectAllocationId = nil
        self.memo = ""
    }
}

private struct CanonicalAccountPickerView: View {
    let label: String
    let accounts: [CanonicalAccount]
    @Binding var selectedAccountId: UUID?

    private var activeAccounts: [CanonicalAccount] {
        accounts
            .filter { $0.archivedAt == nil }
            .sorted {
                if $0.displayOrder == $1.displayOrder {
                    return $0.code < $1.code
                }
                return $0.displayOrder < $1.displayOrder
            }
    }

    private var groupedAccounts: [(CanonicalAccountType, [CanonicalAccount])] {
        let grouped = Dictionary(grouping: activeAccounts, by: \.accountType)
        return CanonicalAccountType.allCases.compactMap { type in
            guard let items = grouped[type], !items.isEmpty else {
                return nil
            }
            return (type, items)
        }
    }

    private var selectedAccountName: String {
        guard let selectedAccountId,
              let account = activeAccounts.first(where: { $0.id == selectedAccountId }) else {
            return "選択してください"
        }
        return "\(account.code) \(account.name)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                Button("未設定") {
                    selectedAccountId = nil
                }

                ForEach(groupedAccounts, id: \.0) { accountType, items in
                    Section(accountType.displayName) {
                        ForEach(items, id: \.id) { account in
                            Button {
                                selectedAccountId = account.id
                            } label: {
                                HStack {
                                    Text("\(account.code) \(account.name)")
                                    if selectedAccountId == account.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedAccountName)
                        .font(.subheadline)
                        .foregroundStyle(selectedAccountId != nil ? .primary : .secondary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }
            .accessibilityLabel(label)
            .accessibilityValue(selectedAccountName)
        }
    }
}

struct ApprovalCandidateDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let candidateId: UUID
    var onStatusChanged: (() -> Void)?

    @State private var candidate: PostingCandidate?
    @State private var evidence: EvidenceDocument?
    @State private var counterparties: [Counterparty] = []
    @State private var lineDrafts: [CandidateLineDraft] = []
    @State private var memo = ""
    @State private var selectedCounterpartyId: UUID?
    @State private var generatedJournal: CanonicalJournalEntry?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var approvalQueueQueryUseCase: ApprovalQueueQueryUseCase {
        ApprovalQueueQueryUseCase(modelContext: modelContext)
    }

    var body: some View {
        Group {
            if let candidate {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection(candidate)
                        if let evidence {
                            evidenceSection(evidence)
                        }
                        candidateMetaSection(candidate)
                        linesSection
                    }
                    .padding(16)
                }
                .navigationTitle("候補レビュー")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button("保存") {
                                Task { await saveCandidateDraft() }
                            }
                            .disabled(!hasSavableLines)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    actionBar
                }
            } else if isLoading {
                ProgressView()
            } else {
                ContentUnavailableView("候補が見つかりません", systemImage: "exclamationmark.triangle")
            }
        }
        .task(id: candidateId) {
            await load()
        }
        .alert("処理エラー", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var isCandidateYearLocked: Bool {
        guard let candidate else { return false }
        return approvalQueueQueryUseCase.isYearLocked(date: candidate.candidateDate)
    }

    private var hasSavableLines: Bool {
        lineDrafts.contains { draft in
            (draft.debitAccountId != nil || draft.creditAccountId != nil)
                && ((Decimal(string: draft.amountText) ?? 0) > 0)
        }
    }

    private var canonicalAccounts: [CanonicalAccount] {
        approvalQueueQueryUseCase.canonicalAccounts()
    }

    @ViewBuilder
    private func headerSection(_ candidate: PostingCandidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formatDate(candidate.candidateDate))
                    .font(.headline)
                Spacer()
                Text(candidate.status.displayName)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor(candidate.status).opacity(0.12))
                    .foregroundStyle(statusColor(candidate.status))
                    .clipShape(Capsule())
            }

            if let generatedJournal {
                NavigationLink {
                    JournalDetailView(entry: projectedEntry(for: generatedJournal))
                } label: {
                    Label("承認済み仕訳 \(generatedJournal.voucherNo)", systemImage: "doc.text")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func evidenceSection(_ evidence: EvidenceDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("証憑")
                .font(.subheadline.weight(.medium))

            if let image = previewImage(for: evidence) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text(evidence.originalFilename)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func candidateMetaSection(_ candidate: PostingCandidate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("候補情報")
                .font(.subheadline.weight(.medium))

            Menu {
                Button("未設定") {
                    selectedCounterpartyId = nil
                }
                ForEach(counterparties, id: \.id) { counterparty in
                    Button(counterparty.displayName) {
                        selectedCounterpartyId = counterparty.id
                    }
                }
            } label: {
                metaRow(
                    title: "取引先",
                    value: selectedCounterpartyId.flatMap { id in
                        counterparties.first(where: { $0.id == id })?.displayName
                    } ?? "未設定"
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("摘要")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("摘要", text: $memo, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }

            if let evidence {
                HStack(spacing: 12) {
                    if let amount = evidence.structuredFields?.totalAmount {
                        Label(formatAmount(amount), systemImage: "yensign")
                    }
                    Label(candidate.source.displayName, systemImage: "tray.and.arrow.down")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("仕訳候補行")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    lineDrafts.append(CandidateLineDraft())
                } label: {
                    Label("行追加", systemImage: "plus.circle")
                }
                .font(.caption)
            }

            ForEach(Array(lineDrafts.enumerated()), id: \.element.id) { index, _ in
                lineEditor(index: index)
            }
        }
    }

    private func lineEditor(index: Int) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("行 \(index + 1)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if lineDrafts.count > 1 {
                    Button(role: .destructive) {
                        lineDrafts.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .font(.caption)
                }
            }

            CanonicalAccountPickerView(
                label: "借方科目",
                accounts: canonicalAccounts,
                selectedAccountId: Binding(
                    get: { lineDrafts[index].debitAccountId },
                    set: { lineDrafts[index].debitAccountId = $0 }
                )
            )

            CanonicalAccountPickerView(
                label: "貸方科目",
                accounts: canonicalAccounts,
                selectedAccountId: Binding(
                    get: { lineDrafts[index].creditAccountId },
                    set: { lineDrafts[index].creditAccountId = $0 }
                )
            )

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("金額")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("0", text: Binding(
                        get: { lineDrafts[index].amountText },
                        set: { lineDrafts[index].amountText = $0 }
                    ))
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("税区分")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Menu {
                        Button("未設定") {
                            lineDrafts[index].taxCodeId = nil
                        }
                        ForEach(TaxCode.allCases, id: \.rawValue) { taxCode in
                            Button(taxCode.displayName) {
                                lineDrafts[index].taxCodeId = taxCode.rawValue
                            }
                        }
                    } label: {
                        pickerLabel(
                            lineDrafts[index].taxCodeId.flatMap { TaxCode.resolve(id: $0)?.displayName } ?? "未設定"
                        )
                    }
                }
            }

            Menu {
                Button("未設定") {
                    lineDrafts[index].projectAllocationId = nil
                }
                ForEach(approvalQueueQueryUseCase.availableProjects(), id: \.id) { project in
                    Button(project.name) {
                        lineDrafts[index].projectAllocationId = project.id
                    }
                }
            } label: {
                metaRow(
                    title: "プロジェクト",
                    value: approvalQueueQueryUseCase.projectName(id: lineDrafts[index].projectAllocationId) ?? "未設定"
                )
            }

            TextField("行メモ", text: Binding(
                get: { lineDrafts[index].memo },
                set: { lineDrafts[index].memo = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
        }
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button("却下", role: .destructive) {
                Task { await rejectCandidate() }
            }
            .buttonStyle(.bordered)
            .disabled(isSaving || candidate == nil)

            Button("承認して仕訳作成") {
                Task { await approveCandidate() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || !hasSavableLines || candidate == nil || isCandidateYearLocked)

            if isCandidateYearLocked {
                Text("年度ロック中")
                    .font(.caption)
                    .foregroundStyle(AppColors.warning)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }

    private func metaRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(AppColors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func pickerLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(AppColors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let workflow = PostingWorkflowUseCase(modelContext: modelContext)
            candidate = try await workflow.candidate(candidateId)
            if let candidate, let evidenceId = candidate.evidenceId {
                evidence = try await EvidenceCatalogUseCase(modelContext: modelContext).evidence(evidenceId)
            } else {
                evidence = nil
            }
            if let businessId = approvalQueueQueryUseCase.currentBusinessId() {
                counterparties = try await CounterpartyMasterUseCase(modelContext: modelContext)
                    .loadCounterparties(businessId: businessId)
            } else {
                counterparties = []
            }
            if let candidate {
                lineDrafts = candidate.proposedLines.map(CandidateLineDraft.init(line:))
                memo = candidate.memo ?? ""
                selectedCounterpartyId = candidate.counterpartyId
            } else {
                lineDrafts = []
                memo = ""
                selectedCounterpartyId = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveCandidateDraft() async {
        await persistCandidate(approveAfterSave: false)
    }

    private func approveCandidate() async {
        await persistCandidate(approveAfterSave: true)
    }

    private func rejectCandidate() async {
        guard let candidate else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await PostingWorkflowUseCase(modelContext: modelContext).rejectCandidate(candidate.id)
            onStatusChanged?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistCandidate(approveAfterSave: Bool) async {
        guard let candidate else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let updated = try buildUpdatedCandidate(from: candidate)
            let workflow = PostingWorkflowUseCase(modelContext: modelContext)
            try await workflow.saveCandidate(updated)
            self.candidate = updated
            if approveAfterSave {
                let journal = try await workflow.approveCandidate(
                    candidateId: updated.id,
                    description: normalizedOptionalString(memo)
                )
                guard let approvedCandidate = try await workflow.candidate(updated.id) else {
                    throw AppError.invalidInput(message: "承認後の候補を再取得できませんでした")
                }
                generatedJournal = journal
                self.candidate = approvedCandidate
                onStatusChanged?()
            } else {
                onStatusChanged?()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildUpdatedCandidate(from current: PostingCandidate) throws -> PostingCandidate {
        let lines = lineDrafts.compactMap { draft -> PostingCandidateLine? in
            let amount = Decimal(string: draft.amountText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            guard amount > 0 else {
                return nil
            }

            let debitAccountId = draft.debitAccountId
            let creditAccountId = draft.creditAccountId
            guard debitAccountId != nil || creditAccountId != nil else {
                return nil
            }

            return PostingCandidateLine(
                id: draft.id,
                debitAccountId: debitAccountId,
                creditAccountId: creditAccountId,
                amount: amount,
                taxCodeId: draft.taxCodeId,
                legalReportLineId: nil,
                projectAllocationId: draft.projectAllocationId,
                memo: normalizedOptionalString(draft.memo),
                evidenceLineReferenceId: nil
            )
        }

        if lines.isEmpty {
            throw PostingWorkflowUseCaseError.candidateHasNoLines(current.id)
        }

        return current.updated(
            proposedLines: lines,
            counterpartyId: selectedCounterpartyId,
            memo: normalizedOptionalString(memo)
        )
    }

    private func previewImage(for evidence: EvidenceDocument) -> UIImage? {
        guard evidence.mimeType.hasPrefix("image/"),
              let data = ReceiptImageStore.loadDocumentData(fileName: evidence.originalFilePath)
        else {
            return nil
        }
        return UIImage(data: data)
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

    private func normalizedOptionalString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

    private func statusColor(_ status: CandidateStatus) -> Color {
        switch status {
        case .draft:
            return AppColors.muted
        case .needsReview:
            return AppColors.warning
        case .approved:
            return AppColors.success
        case .rejected:
            return AppColors.error
        }
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
