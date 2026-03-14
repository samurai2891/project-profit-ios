import SwiftUI
import SwiftData

/// 確定申告ダッシュボード
struct FilingDashboardView: View {
    @Environment(\.modelContext) private var modelContext

    enum WorkflowDestinationID: String, Equatable {
        case booksWorkspace
        case withholding
        case closingEntry
        case etaxExport
    }

    struct WorkflowItem: Equatable {
        let icon: String
        let title: String
        let subtitle: String
        let destinationID: WorkflowDestinationID
    }

    static let booksWorkspaceTitle = "帳簿ワークスペース"
    static let booksWorkspaceSubtitle = "仕訳確認・分析・申告準備の入口"
    static let workflowItems: [WorkflowItem] = [
        WorkflowItem(
            icon: "books.vertical",
            title: booksWorkspaceTitle,
            subtitle: booksWorkspaceSubtitle,
            destinationID: .booksWorkspace
        ),
        WorkflowItem(
            icon: "doc.text.magnifyingglass",
            title: "支払調書",
            subtitle: "源泉徴収の年次一覧と支払先単票を確認",
            destinationID: .withholding
        ),
        WorkflowItem(
            icon: "doc.badge.gearshape",
            title: "決算仕訳",
            subtitle: "締め処理前の最終確認と仕訳生成",
            destinationID: .closingEntry
        ),
        WorkflowItem(
            icon: "square.and.arrow.up",
            title: "e-Tax出力",
            subtitle: "確定申告データの出力",
            destinationID: .etaxExport
        ),
    ]

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
        .task(id: selectedFiscalYear) {
            await refreshState(for: selectedFiscalYear)
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

            ForEach(Self.workflowItems, id: \.destinationID) { item in
                NavigationLink {
                    workflowDestination(for: item.destinationID)
                } label: {
                    workflowRow(
                        icon: item.icon,
                        title: item.title,
                        subtitle: item.subtitle
                    )
                }
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func workflowDestination(for destinationID: Self.WorkflowDestinationID) -> some View {
        switch destinationID {
        case .booksWorkspace:
            BooksWorkspaceView()
        case .withholding:
            WithholdingStatementView(initialFiscalYear: selectedFiscalYear)
        case .closingEntry:
            ClosingEntryView()
        case .etaxExport:
            EtaxExportView()
        }
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

    private func refreshState(for fiscalYear: Int) async {
        isCheckingPreflight = true
        defer { isCheckingPreflight = false }

        do {
            let snapshot = try await FilingDashboardQueryUseCase(modelContext: modelContext)
                .snapshot(fiscalYear: fiscalYear)
            guard !Task.isCancelled, fiscalYear == selectedFiscalYear else {
                return
            }
            yearLockState = snapshot.yearLockState
            preflightIssues = snapshot.preflightIssues
        } catch {
            guard !Task.isCancelled, fiscalYear == selectedFiscalYear else {
                return
            }
            yearLockState = .open
            preflightIssues = [error.localizedDescription]
        }
    }
}
