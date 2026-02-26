import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(DataStore.self) private var dataStore
    @AppStorage(FiscalYearSettings.userDefaultsKey) private var fiscalStartMonth = FiscalYearSettings.defaultStartMonth
    @State private var showCategorySheet = false
    @State private var showDeleteAlert = false
    @State private var showFileImporter = false
    @State private var showImportResultAlert = false
    @State private var importResult: CSVImportResult?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Stats
                statsSection

                // Fiscal Year
                fiscalYearSection

                // Retention Policy
                retentionPolicySection

                // Management
                managementSection

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

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("管理")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
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

                Divider().padding(.leading, 70)

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
}
