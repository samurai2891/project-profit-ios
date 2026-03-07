import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(DataStore.self) private var dataStore
    @AppStorage(FiscalYearSettings.userDefaultsKey) private var fiscalStartMonth = FiscalYearSettings.defaultStartMonth
    @State private var showCategorySheet = false
    @State private var showDeleteAlert = false
    @State private var showFileImporter = false
    @State private var showRestoreImporter = false
    @State private var showImportResultAlert = false
    @State private var importResult: CSVImportResult?
    @State private var showBackupShareSheet = false
    @State private var backupShareURL: URL?
    @State private var cachedRestoreSnapshotURL: URL?
    @State private var restoreDryRunReport: RestoreDryRunReport?
    @State private var migrationDryRunReport: MigrationDryRunReport?
    @State private var operationMessage: String?
    @State private var showOperationAlert = false
    @State private var selectedBackupYear = currentFiscalYear(startMonth: FiscalYearSettings.startMonth)

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Stats
                statsSection

                // Fiscal Year
                fiscalYearSection

                // Retention Policy
                retentionPolicySection

                // Business Settings
                businessSettingsSection

                // Master Management
                masterManagementSection

                // Data
                dataSection

                // App Info
                appInfoSection
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.large)
        .alert("データを削除", isPresented: $showDeleteAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                dataStore.deleteAllData()
            }
        } message: {
            Text("すべてのデータを削除しますか？この操作は取り消せません。")
        }
        .sheet(isPresented: $showCategorySheet) {
            CategoryManageView()
        }
        .sheet(isPresented: $showBackupShareSheet) {
            if let backupShareURL {
                ShareSheetView(activityItems: [backupShareURL])
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else {
                    importResult = CSVImportResult(successCount: 0, errorCount: 1, errors: ["ファイルへのアクセスが拒否されました。"])
                    showImportResultAlert = true
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let csvString = try String(contentsOf: url, encoding: .utf8)
                    importResult = dataStore.importTransactions(from: csvString)
                } catch {
                    importResult = CSVImportResult(successCount: 0, errorCount: 1, errors: ["ファイルの読み込みに失敗しました: \(error.localizedDescription)"])
                }
                showImportResultAlert = true
            case .failure(let error):
                importResult = CSVImportResult(successCount: 0, errorCount: 1, errors: ["ファイル選択エラー: \(error.localizedDescription)"])
                showImportResultAlert = true
            }
        }
        .fileImporter(
            isPresented: $showRestoreImporter,
            allowedContentTypes: [.appleArchive, .data],
            allowsMultipleSelection: false
        ) { result in
            handleRestoreSelection(result)
        }
        .alert("インポート結果", isPresented: $showImportResultAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let result = importResult {
                if result.errorCount == 0 {
                    Text("\(result.successCount)件の取引をインポートしました。")
                } else {
                    Text("成功: \(result.successCount)件\nエラー: \(result.errorCount)件\n\(result.errors.prefix(3).joined(separator: "\n"))")
                }
            }
        }
        .alert("データ処理", isPresented: $showOperationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(operationMessage ?? "")
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("データ統計")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 0) {
                statItem(icon: "folder.fill", value: dataStore.projects.count, label: "プロジェクト")
                Divider().frame(height: 40)
                statItem(icon: "list.bullet.rectangle", value: dataStore.transactions.count, label: "取引")
                Divider().frame(height: 40)
                statItem(icon: "repeat", value: dataStore.recurringTransactions.count, label: "定期取引")
            }
            .padding(20)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("データ統計 プロジェクト\(dataStore.projects.count)件 取引\(dataStore.transactions.count)件 定期取引\(dataStore.recurringTransactions.count)件")
        }
    }

    private func statItem(icon: String, value: Int, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppColors.primary)
            Text("\(value)")
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Fiscal Year

    private var fiscalYearSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("会計年度")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title3)
                        .foregroundStyle(AppColors.warning)
                        .frame(width: 40, height: 40)
                        .background(AppColors.warning.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("会計年度の開始月")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(fiscalYearPeriodPreview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker("開始月", selection: $fiscalStartMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text("\(month)月").tag(month)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("会計年度の開始月")
                }
                .padding(16)
            }
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain)
        }
    }

    private var fiscalYearPeriodPreview: String {
        let fy = currentFiscalYear(startMonth: fiscalStartMonth)
        return fiscalYearPeriodLabel(fy, startMonth: fiscalStartMonth)
    }

    // MARK: - Management

    private var retentionPolicySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("法定保存期間")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 10) {
                retentionRow(title: "帳簿", years: "7年", detail: "仕訳帳・総勘定元帳・現金出納帳等")
                retentionRow(title: "決算関係書類", years: "7年", detail: "損益計算書・貸借対照表・棚卸表等")
                retentionRow(title: "現金預金取引等関係書類", years: "7年", detail: "領収証・小切手控・預金通帳・借用証等")
                retentionRow(title: "その他の書類", years: "5年", detail: "請求書・見積書・契約書・納品書・送り状等")
            }
            .padding(16)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func retentionRow(title: String, years: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(years)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColors.primary.opacity(0.12))
                    .foregroundStyle(AppColors.primary)
                    .clipShape(Capsule())
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var businessSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("事業設定")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                NavigationLink {
                    ProfileSettingsView()
                } label: {
                    menuRow(
                        icon: "person.text.rectangle",
                        iconColor: AppColors.warning,
                        title: "申告者情報",
                        subtitle: "e-Tax用の個人情報を設定"
                    )
                }

                Divider().padding(.leading, 70)

                NavigationLink {
                    RecurringView()
                } label: {
                    menuRow(
                        icon: "repeat",
                        iconColor: AppColors.success,
                        title: "定期取引",
                        subtitle: "毎月・毎年の自動登録を管理"
                    )
                }
            }
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var masterManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("マスタ管理")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                NavigationLink {
                    CounterpartyListView()
                } label: {
                    menuRow(
                        icon: "person.2.fill",
                        iconColor: AppColors.primary,
                        title: "取引先管理",
                        subtitle: "取引先マスタの追加・編集・削除"
                    )
                }

                Divider().padding(.leading, 70)

                NavigationLink {
                    ChartOfAccountsView()
                } label: {
                    menuRow(
                        icon: "text.book.closed.fill",
                        iconColor: AppColors.success,
                        title: "勘定科目管理",
                        subtitle: "勘定科目の追加・編集・無効化"
                    )
                }

                Divider().padding(.leading, 70)

                NavigationLink {
                    DistributionTemplateSettingsView()
                } label: {
                    menuRow(
                        icon: "square.split.2x2",
                        iconColor: AppColors.success,
                        title: "配賦テンプレート",
                        subtitle: "共通費の配賦ルールを管理"
                    )
                }

                Divider().padding(.leading, 70)

                Button {
                    showCategorySheet = true
                } label: {
                    menuRow(
                        icon: "chart.pie.fill",
                        iconColor: AppColors.primary,
                        title: "カテゴリ管理",
                        subtitle: "収益・経費カテゴリの追加・編集"
                    )
                }
            }
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func menuRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("データ")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                Button {
                    showFileImporter = true
                } label: {
                    menuRow(
                        icon: "square.and.arrow.down",
                        iconColor: AppColors.primary,
                        title: "CSVインポート",
                        subtitle: "CSVファイルから取引データを読み込み"
                    )
                }
                .accessibilityLabel("CSVインポート")
                .accessibilityHint("タップしてCSVファイルから取引データを読み込み")

                Divider().padding(.leading, 70)

                HStack(spacing: 14) {
                    Image(systemName: "archivebox")
                        .font(.title3)
                        .foregroundStyle(AppColors.success)
                        .frame(width: 40, height: 40)
                        .background(AppColors.success.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("年分バックアップ")
                            .font(.body.weight(.medium))
                        Text("対象年を選んで snapshot を共有")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker("年分", selection: $selectedBackupYear) {
                        ForEach(availableBackupYears, id: \.self) { year in
                            Text("\(year)年分").tag(year)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(16)

                Divider().padding(.leading, 70)

                Button {
                    exportBackup(scope: .taxYear(selectedBackupYear))
                } label: {
                    menuRow(
                        icon: "square.and.arrow.up",
                        iconColor: AppColors.success,
                        title: "年分バックアップを共有",
                        subtitle: "Apple Archive で 1 ファイル出力"
                    )
                }

                Divider().padding(.leading, 70)

                Button {
                    exportBackup(scope: .full)
                } label: {
                    menuRow(
                        icon: "shippingbox",
                        iconColor: AppColors.warning,
                        title: "全体バックアップを共有",
                        subtitle: "全データと原本ファイルを 1 ファイル出力"
                    )
                }

                Divider().padding(.leading, 70)

                Button {
                    showRestoreImporter = true
                } label: {
                    menuRow(
                        icon: "doc.badge.arrow.up",
                        iconColor: AppColors.primary,
                        title: "復元を検査",
                        subtitle: "snapshot を読み込み dry-run を実行"
                    )
                }

                if let restoreDryRunReport {
                    Divider().padding(.leading, 70)

                    Button {
                        applyRestore()
                    } label: {
                        menuRow(
                            icon: "arrow.clockwise.circle",
                            iconColor: restoreDryRunReport.canApply ? AppColors.error : AppColors.muted,
                            title: "復元を実行",
                            subtitle: restoreDryRunReport.canApply ? "rollback snapshot を作成して置換復元" : "dry-run の issue を解消すると実行可能"
                        )
                    }
                    .disabled(!restoreDryRunReport.canApply || cachedRestoreSnapshotURL == nil)
                }

                Divider().padding(.leading, 70)

                Button {
                    runMigrationDryRun()
                } label: {
                    menuRow(
                        icon: "chart.bar.doc.horizontal",
                        iconColor: AppColors.primary,
                        title: "移行 dry-run",
                        subtitle: "件数差分と孤児データを確認"
                    )
                }

                if let migrationDryRunReport, migrationDryRunReport.deltas.contains(where: { $0.executeSupported && $0.legacyCount > 0 }) {
                    Divider().padding(.leading, 70)

                    Button {
                        executeMigration()
                    } label: {
                        menuRow(
                            icon: "arrow.triangle.2.circlepath",
                            iconColor: AppColors.warning,
                            title: "移行を実行",
                            subtitle: "レガシーデータをcanonicalモデルに変換"
                        )
                    }
                }

                Divider().padding(.leading, 70)

                Button {
                    showDeleteAlert = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundStyle(AppColors.error)
                            .frame(width: 40, height: 40)
                            .background(AppColors.error.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("すべてのデータを削除")
                                .font(.body.weight(.medium))
                                .foregroundStyle(AppColors.error)
                            Text("プロジェクト、取引、設定を初期化")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(16)
                }
                .accessibilityLabel("すべてのデータを削除")
                .accessibilityHint("タップして削除確認画面を表示 この操作は取り消せません")
            }
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if let restoreDryRunReport {
                restoreReportSection(report: restoreDryRunReport)
            }

            if let migrationDryRunReport {
                migrationReportSection(report: migrationDryRunReport)
            }
        }
    }

    // MARK: - App Info

    private var appInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("アプリ情報")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                Text("Project Profit")
                    .font(.title3.bold())
                Text("バージョン \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("個人事業主向けプロジェクト別経費トラッカー")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Project Profit バージョン \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0") 個人事業主向けプロジェクト別経費トラッカー")
        }
    }

    private var availableBackupYears: [Int] {
        let years = Set(
            dataStore.transactions.map { fiscalYear(for: $0.date, startMonth: fiscalStartMonth) }
                + dataStore.inventoryRecords.map(\.fiscalYear)
                + [dataStore.currentTaxYearProfile?.taxYear, dataStore.accountingProfile?.fiscalYear].compactMap { $0 }
        )
        let sorted = years.sorted(by: >)
        if sorted.isEmpty {
            return [currentFiscalYear(startMonth: fiscalStartMonth)]
        }
        return sorted
    }

    private func exportBackup(scope: BackupScope) {
        do {
            let result = try BackupService(modelContext: dataStore.modelContext).export(scope: scope)
            backupShareURL = result.archiveURL
            showBackupShareSheet = true
            let warningText = result.manifest.warnings.isEmpty ? "warning なし" : "warning \(result.manifest.warnings.count)件"
            operationMessage = "backup を作成しました: \(result.archiveURL.lastPathComponent)\n\(warningText)"
            showOperationAlert = true
        } catch {
            operationMessage = "backup 作成に失敗しました: \(error.localizedDescription)"
            showOperationAlert = true
        }
    }

    private func handleRestoreSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                operationMessage = "復元ファイルへのアクセスが拒否されました。"
                showOperationAlert = true
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let cachedURL = try cacheRestoreSnapshot(from: url)
                cachedRestoreSnapshotURL = cachedURL
                restoreDryRunReport = try RestoreService(modelContext: dataStore.modelContext).dryRun(snapshotURL: cachedURL)
                operationMessage = restoreDryRunReport?.canApply == true ? "復元 dry-run が完了しました。" : "復元 dry-run に issue があります。"
                showOperationAlert = true
            } catch {
                operationMessage = "復元 dry-run に失敗しました: \(error.localizedDescription)"
                showOperationAlert = true
            }
        case .failure(let error):
            operationMessage = "復元ファイルの選択に失敗しました: \(error.localizedDescription)"
            showOperationAlert = true
        }
    }

    private func applyRestore() {
        guard let cachedRestoreSnapshotURL else { return }
        do {
            let result = try RestoreService(modelContext: dataStore.modelContext).apply(snapshotURL: cachedRestoreSnapshotURL)
            dataStore.loadData()
            restoreDryRunReport = result.report
            operationMessage = "復元を実行しました。rollback: \(result.rollbackArchiveURL.lastPathComponent)"
            showOperationAlert = true
        } catch {
            operationMessage = "復元に失敗しました: \(error.localizedDescription)"
            showOperationAlert = true
        }
    }

    private func runMigrationDryRun() {
        do {
            migrationDryRunReport = try MigrationReportRunner(modelContext: dataStore.modelContext).dryRun()
            operationMessage = "移行 dry-run を更新しました。"
            showOperationAlert = true
        } catch {
            operationMessage = "移行 dry-run に失敗しました: \(error.localizedDescription)"
            showOperationAlert = true
        }
    }

    private func executeMigration() {
        guard let businessId = dataStore.businessProfile?.id else {
            operationMessage = "事業者情報が未設定です"
            showOperationAlert = true
            return
        }

        do {
            let executor = LegacyDataMigrationExecutor(modelContext: dataStore.modelContext)
            let result = try executor.execute(businessId: businessId)

            let summary = "移行完了: 取引 \(result.transactionsMigrated)件, 仕訳 \(result.journalsMigrated)件, 書類 \(result.documentsMigrated)件"
            if result.hasErrors {
                operationMessage = summary + "\nエラー: \(result.errors.prefix(3).joined(separator: "\n"))"
            } else {
                operationMessage = summary
            }

            migrationDryRunReport = try MigrationReportRunner(modelContext: dataStore.modelContext).dryRun()
            dataStore.loadData()
            showOperationAlert = true
        } catch {
            operationMessage = "移行に失敗しました: \(error.localizedDescription)"
            showOperationAlert = true
        }
    }

    private func cacheRestoreSnapshot(from url: URL) throws -> URL {
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString).aar")
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.copyItem(at: url, to: targetURL)
        return targetURL
    }

    @ViewBuilder
    private func restoreReportSection(report: RestoreDryRunReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("復元 dry-run")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                Text(report.manifest.scope.label)
                    .font(.headline)
                Text("issue: \(report.issues.count) / warning: \(report.warnings.count)")
                    .font(.caption)
                    .foregroundStyle(report.canApply ? AppColors.success : AppColors.error)
                if !report.issues.isEmpty {
                    Text(report.issues.prefix(3).joined(separator: "\n"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !report.conflicts.isEmpty {
                    Text(report.conflicts.prefix(3).map { "\($0.modelName): existing \($0.existingCount) / incoming \($0.incomingCount)" }.joined(separator: "\n"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private func migrationReportSection(report: MigrationDryRunReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("移行 dry-run")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                Text("delta: \(report.deltas.count) / orphan: \(report.orphanRecords.count) / warning: \(report.warnings.count)")
                    .font(.caption)
                    .foregroundStyle(report.hasIssues ? AppColors.warning : AppColors.success)
                Text(report.deltas.prefix(4).map { "\($0.modelName): legacy \($0.legacyCount) / canonical \($0.canonicalCount)" }.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !report.orphanRecords.isEmpty {
                    Text(report.orphanRecords.prefix(3).map { "\($0.area) \($0.message)" }.joined(separator: "\n"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}
