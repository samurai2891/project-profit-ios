import SwiftUI
import SwiftData

/// 確定申告ダッシュボード
struct FilingDashboardView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.modelContext) private var modelContext

    @State private var selectedFiscalYear: Int
    @State private var preflightIssues: [String] = []
    @State private var isCheckingPreflight = false
    @State private var yearLockState: YearLockState = .open

    init() {
        let fy = currentFiscalYear(startMonth: FiscalYearSettings.startMonth) - 1
        _selectedFiscalYear = State(initialValue: fy)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                yearSelector
                yearLockSection
                preflightSection
                workflowSection
            }
            .padding(16)
        }
        .navigationTitle("確定申告")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshState()
        }
        .onChange(of: selectedFiscalYear) {
            Task { await refreshState() }
        }
    }

    // MARK: - Year Selector

    private var yearSelector: some View {
        HStack {
            Button {
                selectedFiscalYear -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(AppColors.primary)
            }

            Spacer()

            Text("\(String(selectedFiscalYear))年分")
                .font(.headline)

            Spacer()

            Button {
                selectedFiscalYear += 1
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppColors.primary)
            }
        }
    }

    // MARK: - Year Lock

    private var yearLockSection: some View {
        let isLocked = yearLockState != .open

        return HStack(spacing: 12) {
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .foregroundStyle(isLocked ? AppColors.success : AppColors.warning)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(isLocked ? "年度確定済（\(yearLockState.displayName)）" : "年度未確定")
                    .font(.subheadline.weight(.medium))
                Text(isLocked
                    ? "この年度の仕訳は変更できません"
                    : "仕訳の追加・変更が可能です")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Preflight

    private var preflightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("申告前チェック")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if isCheckingPreflight {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if preflightIssues.isEmpty && !isCheckingPreflight {
                Label("問題なし", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.success)
            } else {
                ForEach(preflightIssues, id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                }
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Workflow

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("申告ワークフロー")
                .font(.subheadline.weight(.semibold))

            NavigationLink {
                AccountingHomeView()
            } label: {
                workflowRow(
                    icon: "doc.text.magnifyingglass",
                    title: "帳簿・決算書",
                    subtitle: "仕訳帳・元帳・試算表・決算書の確認"
                )
            }

            NavigationLink {
                EtaxExportView()
            } label: {
                workflowRow(
                    icon: "square.and.arrow.up",
                    title: "e-Tax出力",
                    subtitle: "確定申告データの出力"
                )
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func workflowRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppColors.primary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Data

    private func refreshState() async {
        yearLockState = dataStore.yearLockState(for: selectedFiscalYear)

        isCheckingPreflight = true
        defer { isCheckingPreflight = false }

        guard let businessId = dataStore.businessProfile?.id else {
            preflightIssues = []
            return
        }

        do {
            let useCase = FilingPreflightUseCase(modelContext: modelContext)
            let report = try useCase.preflightReport(
                businessId: businessId,
                taxYear: selectedFiscalYear,
                context: .export
            )
            preflightIssues = report.blockingIssues.map(\.message)
        } catch {
            preflightIssues = [error.localizedDescription]
        }
    }
}
