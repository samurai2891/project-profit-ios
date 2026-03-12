import SwiftData
import SwiftUI

struct JournalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let entry: PPJournalEntry

    @State private var canonicalEntry: CanonicalJournalEntry?
    @State private var reversalEntry: CanonicalJournalEntry?
    @State private var reopenedCandidate: PostingCandidate?
    @State private var showCancelConfirmation = false
    @State private var actionErrorMessage: String?

    private var detailSnapshot: JournalDetailSnapshot {
        JournalReadQueryUseCase(modelContext: modelContext).detailSnapshot(entryId: entry.id)
    }

    private var lines: [PPJournalLine] {
        detailSnapshot.lines
    }

    private var debitTotal: Int {
        lines.reduce(0) { $0 + $1.debit }
    }

    private var creditTotal: Int {
        lines.reduce(0) { $0 + $1.credit }
    }

    private var isBalanced: Bool {
        debitTotal == creditTotal
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                linesSection
                totalsSection
            }
            .padding(20)
        }
        .navigationTitle("仕訳詳細")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: entry.id) {
            await loadCanonicalEntry()
        }
        .toolbar {
            if canCancelEntry {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") {
                        showCancelConfirmation = true
                    }
                }
            }
        }
        .alert("この仕訳を取消して再レビューへ戻しますか？", isPresented: $showCancelConfirmation) {
            Button("取消して戻す", role: .destructive) {
                Task { await cancelAndReopen() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("反対仕訳を作成し、承認待ち候補を新しく作成します。")
        }
        .alert(
            "取消できません",
            isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formatDate(entry.date))
                    .font(.headline)
                Spacer()
                Text(entry.entryType.label)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }

            if !entry.memo.isEmpty {
                Text(entry.memo)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                statusLabel("投稿状態", value: entry.isPosted ? "投稿済" : "未投稿",
                           color: entry.isPosted ? AppColors.success : AppColors.warning)
                statusLabel("貸借", value: isBalanced ? "一致" : "不一致",
                           color: isBalanced ? AppColors.success : AppColors.error)
                if canonicalEntry?.lockedAt != nil {
                    statusLabel("取消", value: "済み", color: AppColors.warning)
                }
            }

            if let reversalEntry {
                NavigationLink {
                    JournalDetailView(entry: projectedEntry(for: reversalEntry))
                } label: {
                    Label("取消仕訳 \(reversalEntry.voucherNo)", systemImage: "arrow.uturn.backward.circle")
                        .font(.caption.weight(.medium))
                }
            }

            if let reopenedCandidate {
                NavigationLink {
                    ApprovalCandidateDetailView(candidateId: reopenedCandidate.id)
                } label: {
                    Label("再レビュー候補", systemImage: "checklist")
                        .font(.caption.weight(.medium))
                }
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statusLabel(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(label): \(value)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Lines

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("仕訳明細")
                .font(.subheadline.weight(.medium))

            ForEach(lines, id: \.id) { line in
                lineRow(line)
            }
        }
    }

    private func lineRow(_ line: PPJournalLine) -> some View {
        let accountName = detailSnapshot.accountNamesById[line.accountId] ?? line.accountId

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(accountName)
                    .font(.subheadline)
                if !line.memo.isEmpty {
                    Text(line.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if line.debit > 0 {
                    HStack(spacing: 4) {
                        Text("借方")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(formatCurrency(line.debit))
                            .font(.subheadline.weight(.medium).monospacedDigit())
                    }
                }
                if line.credit > 0 {
                    HStack(spacing: 4) {
                        Text("貸方")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(formatCurrency(line.credit))
                            .font(.subheadline.weight(.medium).monospacedDigit())
                    }
                }
            }
        }
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Totals

    private var totalsSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("借方合計")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatCurrency(debitTotal))
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("貸方合計")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatCurrency(creditTotal))
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
        }
        .padding(16)
        .background(isBalanced ? AppColors.success.opacity(0.1) : AppColors.error.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var canCancelEntry: Bool {
        guard let canonicalEntry else {
            return false
        }
        return canonicalEntry.approvedAt != nil && canonicalEntry.lockedAt == nil
    }

    private func loadCanonicalEntry() async {
        do {
            canonicalEntry = try await PostingWorkflowUseCase(modelContext: modelContext).journal(entry.id)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func cancelAndReopen() async {
        do {
            let workflow = PostingWorkflowUseCase(modelContext: modelContext)
            let result = try await workflow.cancelAndReopenJournal(
                journalId: entry.id,
                reason: entry.memo
            )
            reversalEntry = result.reversal
            reopenedCandidate = result.reopened
            canonicalEntry = try await workflow.journal(entry.id)
        } catch {
            actionErrorMessage = error.localizedDescription
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
