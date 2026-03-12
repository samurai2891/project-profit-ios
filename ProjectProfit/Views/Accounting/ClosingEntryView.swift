import SwiftData
import SwiftUI

struct ClosingEntryView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.modelContext) private var modelContext

    private struct DisplayLine: Identifiable {
        let id: UUID
        let accountName: String
        let debit: Int
        let credit: Int
    }

    @State private var selectedYear: Int
    @State private var showDeleteConfirmation = false
    @State private var showRegenerateConfirmation = false
    @State private var pendingStateTransition: YearLockState?
    @State private var preflightReport: FilingPreflightReport?
    @State private var stateTransitionErrorMessage: String?

    init() {
        let currentYear = Calendar.current.component(.year, from: Date())
        _selectedYear = State(initialValue: currentYear)
    }

    private var queryUseCase: ClosingQueryUseCase {
        ClosingQueryUseCase(modelContext: modelContext)
    }

    private var snapshot: ClosingEntrySnapshot {
        queryUseCase.snapshot(year: selectedYear)
    }

    private var closingWorkflowUseCase: ClosingWorkflowUseCase {
        ClosingWorkflowUseCase(
            modelContext: modelContext,
            reloadJournalState: {
                dataStore.refreshJournalEntries()
                dataStore.refreshJournalLines()
            },
            applyTaxYearProfile: { profile in
                if dataStore.currentTaxYearProfile?.taxYear == profile.taxYear {
                    dataStore.currentTaxYearProfile = profile
                }
            },
            setError: { dataStore.lastError = $0 }
        )
    }

    private var canonicalClosingEntry: CanonicalJournalEntry? {
        snapshot.closingEntry
    }

    private var hasClosingEntry: Bool {
        canonicalClosingEntry != nil
    }

    private var closingLines: [DisplayLine] {
        snapshot.displayLines.map { line in
            DisplayLine(
                id: line.id,
                accountName: line.accountName,
                debit: line.debit,
                credit: line.credit
            )
        }
    }

    private var currentYearState: YearLockState {
        snapshot.yearState
    }

    private var availableStateTransitions: [YearLockState] {
        YearLockState.allCases.filter { candidate in
            candidate != currentYearState &&
                TaxStatusMachine.isValidLockTransition(from: currentYearState, to: candidate)
        }
    }

    private var canEditClosingEntry: Bool {
        currentYearState.allowsAdjustingEntries
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                yearPicker
                statusSection
                preflightSection
                if hasClosingEntry {
                    closingLinesSection
                }
                actionButtons
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .navigationTitle("決算仕訳")
        .task(id: selectedYear) {
            refreshPreflightReport()
        }
        .alert("決算仕訳を削除しますか？", isPresented: $showDeleteConfirmation) {
            Button("削除", role: .destructive) {
                closingWorkflowUseCase.deleteClosingEntry(for: selectedYear)
                refreshPreflightReport()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("\(selectedYear)年の決算仕訳を削除します。")
        }
        .alert("決算仕訳を再生成しますか？", isPresented: $showRegenerateConfirmation) {
            Button("再生成", role: .destructive) {
                _ = closingWorkflowUseCase.regenerateClosingEntry(for: selectedYear)
                refreshPreflightReport()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("既存の決算仕訳を削除して、最新データで再生成します。")
        }
        .alert(
            pendingStateTransitionTitle,
            isPresented: Binding(
                get: { pendingStateTransition != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingStateTransition = nil
                    }
                }
            )
        ) {
            Button("変更", role: .destructive) {
                guard let pendingStateTransition else { return }
                if shouldRunPreflight(for: pendingStateTransition),
                   let report = closingPreflightReport(for: pendingStateTransition),
                   report.isBlocking
                {
                    preflightReport = report
                    stateTransitionErrorMessage = report.blockingIssues.map(\.message).joined(separator: "\n")
                    self.pendingStateTransition = nil
                    return
                }
                if !closingWorkflowUseCase.transitionFiscalYearState(pendingStateTransition, for: selectedYear) {
                    stateTransitionErrorMessage = dataStore.lastError?.localizedDescription ?? "年度状態の更新に失敗しました"
                } else {
                    refreshPreflightReport()
                }
                self.pendingStateTransition = nil
            }
            Button("キャンセル", role: .cancel) {
                pendingStateTransition = nil
            }
        } message: {
            Text(pendingStateTransitionMessage)
        }
        .alert(
            "年度状態を更新できません",
            isPresented: Binding(
                get: { stateTransitionErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        stateTransitionErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(stateTransitionErrorMessage ?? "")
        }
    }

    // MARK: - Year Picker

    private var yearPicker: some View {
        HStack {
            Text("年度")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("年度", selection: $selectedYear) {
                let currentYear = Calendar.current.component(.year, from: Date())
                ForEach((currentYear - 5)...(currentYear), id: \.self) { year in
                    Text("\(year)年").tag(year)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: hasClosingEntry ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(hasClosingEntry ? AppColors.success : .secondary)
                Text(hasClosingEntry ? "決算仕訳 生成済み" : "決算仕訳 未生成")
                    .font(.headline)
            }

            Label(currentYearState.displayName, systemImage: currentYearState == .open ? "lock.open" : "lock.fill")
                .font(.caption)
                .foregroundStyle(currentYearState == .open ? .secondary : AppColors.warning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var preflightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("締め前チェック")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let report = preflightReport, report.isBlocking {
                    Label("要対応", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                } else {
                    Label("問題なし", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.success)
                }
            }

            if let report = preflightReport, !report.issues.isEmpty {
                ForEach(report.issues, id: \.id) { issue in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "info.circle.fill")
                            .foregroundStyle(issue.severity == .error ? AppColors.error : AppColors.warning)
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("税務締め前の blocking issue はありません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Closing Lines

    private var closingLinesSection: some View {
        let lines = closingLines
        return VStack(alignment: .leading, spacing: 8) {
            Text("仕訳明細")
                .font(.subheadline.weight(.medium))

            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                HStack {
                    Text(line.accountName)
                        .font(.subheadline)
                    Spacer()
                    if line.debit > 0 {
                        Text("借方 ¥\(line.debit.formatted())")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(AppColors.primary)
                    }
                    if line.credit > 0 {
                        Text("貸方 ¥\(line.credit.formatted())")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(AppColors.muted)
                    }
                }
                .padding(.vertical, 4)

                if index < lines.count - 1 {
                    Divider()
                }
            }
        }
        .padding(14)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 8) {
            ForEach(Array(availableStateTransitions.enumerated()), id: \.element) { index, targetState in
                if index == 0 {
                    Button {
                        pendingStateTransition = targetState
                    } label: {
                        Label("\(targetState.displayName)へ変更", systemImage: transitionSystemImage(for: targetState))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        pendingStateTransition = targetState
                    } label: {
                        Label("\(targetState.displayName)へ変更", systemImage: transitionSystemImage(for: targetState))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !hasClosingEntry {
                Button {
                    _ = closingWorkflowUseCase.generateClosingEntry(for: selectedYear)
                    refreshPreflightReport()
                } label: {
                    Label("決算仕訳を生成", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canEditClosingEntry)
            } else {
                Button {
                    showRegenerateConfirmation = true
                } label: {
                    Label("再生成", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canEditClosingEntry)

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("削除", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canEditClosingEntry)
            }
        }
    }

    private var pendingStateTransitionTitle: String {
        guard let pendingStateTransition else {
            return ""
        }
        return "\(selectedYear)年度を\(pendingStateTransition.displayName)に変更しますか？"
    }

    private var pendingStateTransitionMessage: String {
        guard let pendingStateTransition else {
            return ""
        }
        return "現在の状態は\(currentYearState.displayName)です。\(pendingStateTransition.displayName)へ変更します。"
    }

    private func transitionSystemImage(for state: YearLockState) -> String {
        switch state {
        case .open:
            return "lock.open"
        case .softClose:
            return "lock"
        case .taxClose:
            return "checkmark.seal"
        case .filed:
            return "doc.text"
        case .finalLock:
            return "lock.shield"
        }
    }

    private func refreshPreflightReport() {
        preflightReport = closingPreflightReport(for: .taxClose)
    }

    private func closingPreflightReport(for state: YearLockState) -> FilingPreflightReport? {
        guard let businessId = snapshot.businessId else {
            return nil
        }
        do {
            return try FilingPreflightUseCase(modelContext: modelContext).preflightReport(
                businessId: businessId,
                taxYear: selectedYear,
                context: .closing(targetState: state)
            )
        } catch {
            stateTransitionErrorMessage = error.localizedDescription
            return nil
        }
    }

    private func shouldRunPreflight(for state: YearLockState) -> Bool {
        switch state {
        case .taxClose, .filed, .finalLock:
            return true
        case .open, .softClose:
            return false
        }
    }
}
