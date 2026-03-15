import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BankCardReconciliationView: View {
    @Environment(\.modelContext) private var modelContext

    static let titleText = "銀行/カード照合"
    static let subtitleText = "明細取込、未照合チェック、候補起票をまとめて行います"

    @State private var filter = StatementReconciliationFilter()
    @State private var snapshot = StatementReconciliationSnapshot(
        imports: [],
        lines: [],
        availablePaymentAccounts: [],
        unmatchedCount: 0
    )
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showImportSheet = false
    @State private var selectedLine: StatementLineRecord?

    private var queryUseCase: StatementReconciliationQueryUseCase {
        StatementReconciliationQueryUseCase(modelContext: modelContext)
    }

    var body: some View {
        List {
            Section {
                Text(Self.subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            filterSection
            summarySection
            importsSection
            linesSection
        }
        .navigationTitle(Self.titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImportSheet = true
                } label: {
                    Label("取込", systemImage: "square.and.arrow.down")
                }
            }
        }
        .task(id: reloadKey) {
            await loadSnapshot()
        }
        .refreshable {
            await loadSnapshot()
        }
        .sheet(isPresented: $showImportSheet, onDismiss: {
            Task { await loadSnapshot() }
        }) {
            StatementImportSheet {
                Task { await loadSnapshot() }
            }
        }
        .sheet(item: $selectedLine, onDismiss: {
            Task { await loadSnapshot() }
        }) { line in
            StatementLineDetailView(lineId: line.id) {
                Task { await loadSnapshot() }
            }
        }
        .alert("読み込みエラー", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: filter.statementKind) { _, newValue in
            guard let selectedAccountId = filter.paymentAccountId else { return }
            let supported = snapshot.availablePaymentAccounts.contains { $0.id == selectedAccountId }
            if !supported {
                filter.paymentAccountId = nil
            }
            if newValue == nil {
                Task { await loadSnapshot() }
            }
        }
    }

    private var reloadKey: String {
        [
            filter.statementKind?.rawValue ?? "all",
            filter.paymentAccountId ?? "all",
            filter.matchState?.rawValue ?? "all",
            filter.startDate.map { String(Int($0.timeIntervalSince1970)) } ?? "none",
            filter.endDate.map { String(Int($0.timeIntervalSince1970)) } ?? "none",
        ].joined(separator: ":")
    }

    private var filterSection: some View {
        Section("フィルタ") {
            Picker(
                "種別",
                selection: Binding(
                    get: { filter.statementKind?.rawValue ?? "all" },
                    set: { filter.statementKind = $0 == "all" ? nil : StatementKind(rawValue: $0) }
                )
            ) {
                Text("すべて").tag("all")
                ForEach(StatementKind.allCases) { kind in
                    Text(kind.displayName).tag(kind.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Menu {
                Button("すべて") {
                    filter.paymentAccountId = nil
                }
                ForEach(snapshot.availablePaymentAccounts, id: \.id) { account in
                    Button("\(account.code) \(account.name)") {
                        filter.paymentAccountId = account.id
                    }
                }
            } label: {
                filterRow(
                    title: "口座",
                    value: snapshot.availablePaymentAccounts.first { $0.id == filter.paymentAccountId }
                        .map { "\($0.code) \($0.name)" } ?? "すべて"
                )
            }

            Menu {
                Button("すべて") {
                    filter.matchState = nil
                }
                ForEach(StatementMatchState.allCases) { state in
                    Button(state.displayName) {
                        filter.matchState = state
                    }
                }
            } label: {
                filterRow(
                    title: "照合状態",
                    value: filter.matchState?.displayName ?? "すべて"
                )
            }

            DatePicker(
                "開始日",
                selection: Binding(
                    get: { filter.startDate ?? defaultStartDate },
                    set: { filter.startDate = $0 }
                ),
                displayedComponents: .date
            )
            DatePicker(
                "終了日",
                selection: Binding(
                    get: { filter.endDate ?? Date() },
                    set: { filter.endDate = $0 }
                ),
                displayedComponents: .date
            )

            if filter.startDate != nil || filter.endDate != nil {
                Button("期間フィルタをクリア", role: .destructive) {
                    filter.startDate = nil
                    filter.endDate = nil
                }
                .font(.caption)
            }
        }
    }

    private var summarySection: some View {
        Section("未照合サマリー") {
            HStack {
                Label("未照合", systemImage: "exclamationmark.circle")
                Spacer()
                Text("\(snapshot.unmatchedCount)件")
                    .font(.headline)
            }
            .foregroundStyle(snapshot.unmatchedCount > 0 ? AppColors.warning : AppColors.success)
        }
    }

    @ViewBuilder
    private var importsSection: some View {
        Section("取込一覧 (\(snapshot.imports.count))") {
            if isLoading && snapshot.imports.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if snapshot.imports.isEmpty {
                ContentUnavailableView(
                    "取込履歴はありません",
                    systemImage: "tray",
                    description: Text("右上の取込から銀行またはカード明細を追加します")
                )
            } else {
                ForEach(snapshot.imports.prefix(10), id: \.id) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(record.originalFileName)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(record.statementKind.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(snapshot.availablePaymentAccounts.first { $0.id == record.paymentAccountId }?.name ?? record.paymentAccountId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatDateTime(record.importedAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var linesSection: some View {
        Section("明細一覧 (\(snapshot.lines.count))") {
            if isLoading && snapshot.lines.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if snapshot.lines.isEmpty {
                ContentUnavailableView(
                    "表示できる明細はありません",
                    systemImage: "list.bullet.rectangle",
                    description: Text("フィルタ条件を見直すか、明細を取り込んでください")
                )
            } else {
                ForEach(snapshot.lines, id: \.id) { line in
                    Button {
                        selectedLine = line
                    } label: {
                        lineRow(line)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func lineRow(_ line: StatementLineRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.description)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(formatDate(line.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(line.matchState.displayName)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(line.matchState).opacity(0.12))
                    .foregroundStyle(statusColor(line.matchState))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                Text(line.direction.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatAmount(line.amount))
                    .font(.caption.weight(.medium))
                if let counterparty = line.counterparty, !counterparty.isEmpty {
                    Text(counterparty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if line.suggestedCandidateId != nil || line.suggestedJournalId != nil {
                HStack(spacing: 8) {
                    if line.suggestedCandidateId != nil {
                        Label("候補提案あり", systemImage: "sparkles")
                    }
                    if line.suggestedJournalId != nil {
                        Label("仕訳提案あり", systemImage: "doc.text")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var defaultStartDate: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    }

    private func filterRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func loadSnapshot() async {
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await queryUseCase.snapshot(filter: filter)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "JPY"
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? NSDecimalNumber(decimal: amount).stringValue
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func statusColor(_ state: StatementMatchState) -> Color {
        switch state {
        case .unmatched:
            return AppColors.warning
        case .candidateMatched:
            return AppColors.primary
        case .journalMatched:
            return AppColors.success
        }
    }
}

private struct StatementImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let onImported: () -> Void

    @State private var statementKind: StatementKind = .bank
    @State private var paymentAccounts: [PPAccount] = []
    @State private var selectedPaymentAccountId: String?
    @State private var selectedRequest: StatementImportRequest?
    @State private var preview: StatementImportPreview?
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var showFileImporter = false

    private var useCase: StatementImportUseCase {
        StatementImportUseCase(modelContext: modelContext)
    }

    private var filteredPaymentAccounts: [PPAccount] {
        paymentAccounts.filter {
            switch statementKind {
            case .bank:
                return $0.subtype == .ordinaryDeposit
            case .card:
                return $0.subtype == .creditCard
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("取込設定") {
                    Picker("種別", selection: $statementKind) {
                        ForEach(StatementKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    Menu {
                        ForEach(filteredPaymentAccounts, id: \.id) { account in
                            Button("\(account.code) \(account.name)") {
                                selectedPaymentAccountId = account.id
                            }
                        }
                    } label: {
                        HStack {
                            Text("対象口座")
                            Spacer()
                            Text(filteredPaymentAccounts.first { $0.id == selectedPaymentAccountId }?.name ?? "選択してください")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        showFileImporter = true
                    } label: {
                        Label("CSV / PDF を選択", systemImage: "doc.badge.plus")
                    }
                    .disabled(selectedPaymentAccountId == nil)
                }

                if let request = selectedRequest {
                    Section("選択ファイル") {
                        Text(request.originalFileName)
                    }
                }

                if let preview {
                    Section("プレビュー") {
                        HStack {
                            Text("検出形式")
                            Spacer()
                            Text(preview.fileSource.rawValue.uppercased())
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("抽出行数")
                            Spacer()
                            Text("\(preview.parsedLineCount)行")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("行エラー")
                            Spacer()
                            Text("\(preview.lineErrors.count)件")
                                .foregroundStyle(preview.lineErrors.isEmpty ? AppColors.success : AppColors.warning)
                        }
                        ForEach(preview.sampleLines, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                        }
                        if !preview.lineErrors.isEmpty {
                            ForEach(preview.lineErrors.prefix(5)) { lineError in
                                Text("行\(lineError.line): \(lineError.reason)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section {
                        Button {
                            Task { await performImport() }
                        } label: {
                            HStack {
                                Spacer()
                                if isImporting {
                                    ProgressView()
                                } else {
                                    Text("取込実行")
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                            }
                        }
                        .disabled(isImporting || selectedRequest == nil)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("明細取込")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task {
                await loadPaymentAccounts()
            }
            .onChange(of: statementKind) { _, _ in
                if filteredPaymentAccounts.contains(where: { $0.id == selectedPaymentAccountId }) == false {
                    selectedPaymentAccountId = filteredPaymentAccounts.first?.id
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText, UTType.pdf],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
    }

    private func loadPaymentAccounts() async {
        do {
            let snapshot = try TransactionFormQueryUseCase(modelContext: modelContext).snapshot()
            paymentAccounts = snapshot.accounts.filter { $0.isPaymentAccount && $0.isActive }
            if selectedPaymentAccountId == nil {
                selectedPaymentAccountId = filteredPaymentAccounts.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first,
                  let paymentAccountId = selectedPaymentAccountId else { return }
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "ファイルへのアクセスが拒否されました"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let fileData = try Data(contentsOf: url)
                let request = StatementImportRequest(
                    fileData: fileData,
                    originalFileName: url.lastPathComponent,
                    mimeType: url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "text/csv",
                    statementKind: statementKind,
                    paymentAccountId: paymentAccountId
                )
                selectedRequest = request
                errorMessage = nil
                preview = nil
                Task {
                    do {
                        preview = try await useCase.preview(request: request)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } catch {
                errorMessage = "ファイルの読み込みに失敗しました: \(error.localizedDescription)"
            }

        case .failure(let error):
            if (error as NSError).code == NSUserCancelledError {
                return
            }
            errorMessage = "ファイル選択エラー: \(error.localizedDescription)"
        }
    }

    private func performImport() async {
        guard let request = selectedRequest else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            _ = try await useCase.importStatement(request: request)
            onImported()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct StatementLineDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let lineId: UUID
    let onChanged: () -> Void

    @State private var line: StatementLineRecord?
    @State private var candidateOptions: [PostingCandidate] = []
    @State private var journalOptions: [CanonicalJournalEntry] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showCreateCandidate = false

    private var repository: any StatementRepository {
        SwiftDataStatementRepository(modelContext: modelContext)
    }

    private var queryUseCase: StatementReconciliationQueryUseCase {
        StatementReconciliationQueryUseCase(modelContext: modelContext)
    }

    private var matchService: StatementMatchService {
        StatementMatchService(modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let line {
                    List {
                        Section("明細") {
                            detailRow("日付", value: formatDate(line.date))
                            detailRow("摘要", value: line.description)
                            detailRow("金額", value: formatAmount(line.amount))
                            detailRow("区分", value: line.direction.displayName)
                            detailRow("口座", value: line.paymentAccountId)
                            if let counterparty = line.counterparty, !counterparty.isEmpty {
                                detailRow("取引先", value: counterparty)
                            }
                            if let reference = line.reference, !reference.isEmpty {
                                detailRow("参照番号", value: reference)
                            }
                            detailRow("照合状態", value: line.matchState.displayName)
                        }

                        Section("提案操作") {
                            if let suggestedJournalId = line.suggestedJournalId,
                               let journal = journalOptions.first(where: { $0.id == suggestedJournalId }) {
                                Button("提案仕訳を採用") {
                                    Task { await applyJournalMatch(journal.id) }
                                }
                                Text(journalLabel(journal))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let suggestedCandidateId = line.suggestedCandidateId,
                               let candidate = candidateOptions.first(where: { $0.id == suggestedCandidateId }) {
                                Button("提案候補を採用") {
                                    Task { await applyCandidateMatch(candidate.id) }
                                }
                                Text(candidateLabel(candidate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section("手動選択") {
                            if !candidateOptions.isEmpty {
                                Menu {
                                    ForEach(candidateOptions, id: \.id) { candidate in
                                        Button(candidateLabel(candidate)) {
                                            Task { await applyCandidateMatch(candidate.id) }
                                        }
                                    }
                                } label: {
                                    Label("候補を手動選択", systemImage: "checklist")
                                }
                            }

                            if !journalOptions.isEmpty {
                                Menu {
                                    ForEach(journalOptions, id: \.id) { journal in
                                        Button(journalLabel(journal)) {
                                            Task { await applyJournalMatch(journal.id) }
                                        }
                                    }
                                } label: {
                                    Label("仕訳を手動選択", systemImage: "doc.text")
                                }
                            }

                            Button("照合を解除", role: .destructive) {
                                Task { await clearMatch() }
                            }

                            if StatementLinePrefill(line: line) != nil {
                                Button("この明細から候補を起票") {
                                    showCreateCandidate = true
                                }
                            }
                        }
                    }
                } else if isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView("明細が見つかりません", systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle("明細詳細")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await load()
            }
            .sheet(isPresented: $showCreateCandidate) {
                if let line, let prefill = StatementLinePrefill(line: line) {
                    TransactionFormView(
                        prefill: prefill,
                        onCandidateSaved: { candidate in
                            Task {
                                _ = try? await matchService.linkCreatedCandidate(lineId: line.id, candidateId: candidate.id)
                                onChanged()
                                await load()
                            }
                        }
                    )
                }
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
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            line = try await repository.findLine(lineId)
            if let line {
                candidateOptions = try await queryUseCase.candidateOptions(for: line)
                journalOptions = try await queryUseCase.journalOptions(for: line)
            } else {
                candidateOptions = []
                journalOptions = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyCandidateMatch(_ candidateId: UUID) async {
        do {
            line = try await matchService.matchCandidate(lineId: lineId, candidateId: candidateId)
            onChanged()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyJournalMatch(_ journalId: UUID) async {
        do {
            line = try await matchService.matchJournal(lineId: lineId, journalId: journalId)
            onChanged()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearMatch() async {
        do {
            line = try await matchService.clearMatch(lineId: lineId)
            onChanged()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func candidateLabel(_ candidate: PostingCandidate) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d"
        return "\(formatter.string(from: candidate.candidateDate)) \(candidate.memo ?? "摘要なし")"
    }

    private func journalLabel(_ journal: CanonicalJournalEntry) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d"
        return "\(formatter.string(from: journal.journalDate)) \(journal.voucherNo) \(journal.description)"
    }

    private func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "JPY"
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? NSDecimalNumber(decimal: amount).stringValue
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
