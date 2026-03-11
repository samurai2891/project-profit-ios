import SwiftUI

struct ManualJournalFormView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var memo = ""
    @State private var saveError: String?
    @State private var lines: [JournalLineInput] = [
        JournalLineInput(),
        JournalLineInput(),
    ]

    struct JournalLineInput: Identifiable {
        let id = UUID()
        var accountId: String?
        var debitText: String = ""
        var creditText: String = ""
        var memo: String = ""
    }

    private var debitTotal: Int {
        lines.reduce(0) { $0 + (Int($1.debitText) ?? 0) }
    }

    private var creditTotal: Int {
        lines.reduce(0) { $0 + (Int($1.creditText) ?? 0) }
    }

    private var isBalanced: Bool {
        debitTotal == creditTotal && debitTotal > 0
    }

    private var hasValidLines: Bool {
        let validLines = lines.filter { line in
            line.accountId != nil && ((Int(line.debitText) ?? 0) > 0 || (Int(line.creditText) ?? 0) > 0)
        }
        return validLines.count >= 2
    }

    private var isValid: Bool {
        isBalanced && hasValidLines
    }

    private var isLegacyEditingDisabled: Bool {
        !dataStore.isLegacyTransactionEditingEnabled
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if isLegacyEditingDisabled {
                        canonicalCutoverNotice
                    }
                    headerSection
                    linesSection
                    balanceSection
                    addLineButton
                }
                .padding(16)
                .disabled(isLegacyEditingDisabled)
            }
            .navigationTitle("手動仕訳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!isValid || isLegacyEditingDisabled)
                }
            }
            .alert(
                "保存できません",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { isPresented in
                        if !isPresented {
                            saveError = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("日付")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DatePicker("日付", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "ja_JP"))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("摘要")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("摘要を入力...", text: $memo)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Lines

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("仕訳明細")
                .font(.subheadline.weight(.medium))

            ForEach(Array(lines.enumerated()), id: \.element.id) { index, _ in
                lineInputRow(index: index)
            }
        }
    }

    private func lineInputRow(index: Int) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("行 \(index + 1)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if lines.count > 2 {
                    Button {
                        lines.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.error)
                            .font(.caption)
                    }
                }
            }

            AccountPickerView(
                label: "勘定科目",
                accounts: dataStore.accounts,
                selectedAccountId: Binding(
                    get: { lines[index].accountId },
                    set: { lines[index].accountId = $0 }
                ),
                filterPredicate: { $0.isActive }
            )

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("借方")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("0", text: Binding(
                        get: { lines[index].debitText },
                        set: { newValue in
                            lines[index].debitText = newValue
                            if (Int(newValue) ?? 0) > 0 {
                                lines[index].creditText = ""
                            }
                        }
                    ))
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("貸方")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("0", text: Binding(
                        get: { lines[index].creditText },
                        set: { newValue in
                            lines[index].creditText = newValue
                            if (Int(newValue) ?? 0) > 0 {
                                lines[index].debitText = ""
                            }
                        }
                    ))
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                }
            }

            TextField("行メモ（任意）", text: Binding(
                get: { lines[index].memo },
                set: { lines[index].memo = $0 }
            ))
            .font(.caption)
            .textFieldStyle(.roundedBorder)
        }
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Balance Check

    private var balanceSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("借方合計")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatCurrency(debitTotal))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }

            Spacer()

            Image(systemName: isBalanced ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isBalanced ? AppColors.success : AppColors.error)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("貸方合計")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatCurrency(creditTotal))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
        }
        .padding(16)
        .background(isBalanced ? AppColors.success.opacity(0.1) : AppColors.error.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Add Line

    private var addLineButton: some View {
        Button {
            lines.append(JournalLineInput())
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("仕訳行を追加")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppColors.primary)
            .frame(maxWidth: .infinity)
            .padding(12)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColors.border, style: StrokeStyle(lineWidth: 1, dash: [6]))
            )
        }
    }

    private var canonicalCutoverNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("手動仕訳の登録は停止中です", systemImage: "arrow.trianglehead.branch")
                .font(.subheadline.weight(.semibold))
            Text("canonical 正本へ切り替え済みです。証憑タブから取り込み、承認タブで仕訳を確定してください。決算整理は決算仕訳画面から実行します。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.warning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Save

    private func save() {
        guard isValid else { return }
        saveError = AppError.legacyManualJournalMutationDisabled.errorDescription
    }
}
