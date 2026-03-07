import SwiftData
import SwiftUI

// MARK: - DistributionTemplateListView

struct DistributionTemplateListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DataStore.self) private var dataStore

    @State private var rules: [DistributionRule] = []
    @State private var isLoading = false
    @State private var loadErrorMessage: String?
    @State private var editorDraft: DistributionTemplateRuleDraft?
    @State private var saveErrorMessage: String?
    @State private var deleteTargetId: UUID?

    private var sortedProjects: [PPProject] {
        dataStore.projects.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        List {
            if let loadErrorMessage {
                Section {
                    Text(loadErrorMessage)
                        .font(.caption)
                        .foregroundStyle(AppColors.error)
                } header: {
                    Text("読み込みエラー")
                }
            }

            if rules.isEmpty && !isLoading && loadErrorMessage == nil {
                Section {
                    ContentUnavailableView(
                        "配賦テンプレートは未登録です",
                        systemImage: "square.split.2x2",
                        description: Text("共通費の配賦ルールをここで管理します。")
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            } else if !rules.isEmpty {
                Section {
                    ForEach(rules, id: \.id) { rule in
                        ruleRow(rule)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("削除", role: .destructive) {
                                    deleteTargetId = rule.id
                                }
                                Button("編集") {
                                    editorDraft = DistributionTemplateRuleDraft(
                                        rule: rule,
                                        availableProjects: sortedProjects
                                    )
                                }
                                .tint(AppColors.primary)
                            }
                    }
                } header: {
                    HStack {
                        Text("テンプレート")
                        Spacer()
                        Text("\(rules.count)件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView("配賦テンプレートを読み込み中...")
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationTitle("配賦テンプレート")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if dataStore.businessProfile != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorDraft = DistributionTemplateRuleDraft(
                            availableProjects: sortedProjects
                        )
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("配賦テンプレートを追加")
                }
            }
        }
        .task(id: dataStore.businessProfile?.id) {
            await loadRules()
        }
        .refreshable {
            await loadRules()
        }
        .sheet(item: $editorDraft) { draft in
            DistributionTemplateEditorSheet(
                draft: draft,
                onSave: { updatedDraft in
                    await saveRule(updatedDraft)
                }
            )
        }
        .alert("削除確認", isPresented: Binding(
            get: { deleteTargetId != nil },
            set: { if !$0 { deleteTargetId = nil } }
        )) {
            Button("キャンセル", role: .cancel) { deleteTargetId = nil }
            Button("削除", role: .destructive) {
                if let id = deleteTargetId {
                    Task { await deleteRule(id) }
                }
            }
        } message: {
            Text("この配賦テンプレートを削除しますか？")
        }
        .alert(
            "保存エラー",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    // MARK: - Rule Row

    @ViewBuilder
    private func ruleRow(_ rule: DistributionRule) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(rule.name)
                    .font(.body.weight(.medium))

                if isActive(rule) {
                    Text("有効")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.success)
                        .clipShape(Capsule())
                }
            }

            Text(basisSummary(for: rule))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(effectivePeriodLabel(for: rule))
                .font(.caption)
                .foregroundStyle(.secondary)

            if !rule.weights.isEmpty {
                Text(weightSummary(for: rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data Operations

    private func loadRules() async {
        guard let businessId = dataStore.businessProfile?.id else {
            rules = []
            loadErrorMessage = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            rules = try await DistributionTemplateUseCase(modelContext: modelContext)
                .rules(businessId: businessId)
                .sorted { lhs, rhs in
                    if lhs.effectiveFrom == rhs.effectiveFrom {
                        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    }
                    return lhs.effectiveFrom > rhs.effectiveFrom
                }
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = error.localizedDescription
        }
    }

    private func saveRule(_ draft: DistributionTemplateRuleDraft) async {
        guard let businessId = dataStore.businessProfile?.id else {
            saveErrorMessage = "事業者プロフィールが見つかりません。"
            return
        }

        do {
            let rule = try draft.makeRule(businessId: businessId)
            try await DistributionTemplateUseCase(modelContext: modelContext).save(rule)
            await loadRules()
            saveErrorMessage = nil
            editorDraft = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func deleteRule(_ id: UUID) async {
        do {
            try await DistributionTemplateUseCase(modelContext: modelContext).delete(id)
            await loadRules()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func isActive(_ rule: DistributionRule) -> Bool {
        let now = Date()
        guard rule.effectiveFrom <= now else { return false }
        if let effectiveTo = rule.effectiveTo, effectiveTo < now {
            return false
        }
        return true
    }

    private func basisSummary(for rule: DistributionRule) -> String {
        "\(rule.scope.displayName) / \(rule.basis.displayName) / \(rule.roundingPolicy.displayName)"
    }

    private func effectivePeriodLabel(for rule: DistributionRule) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .medium
        let from = formatter.string(from: rule.effectiveFrom)
        if let effectiveTo = rule.effectiveTo {
            return "\(from) - \(formatter.string(from: effectiveTo))"
        }
        return "\(from) -"
    }

    private func weightSummary(for rule: DistributionRule) -> String {
        rule.weights.compactMap { weight in
            let projectName = dataStore.getProject(id: weight.projectId)?.name
                ?? weight.projectId.uuidString
            return "\(projectName): \(NSDecimalNumber(decimal: weight.weight).stringValue)"
        }
        .joined(separator: ", ")
    }
}

// MARK: - DistributionTemplateEditorSheet

private struct DistributionTemplateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: DistributionTemplateRuleDraft
    let onSave: (DistributionTemplateRuleDraft) async -> Void

    init(
        draft: DistributionTemplateRuleDraft,
        onSave: @escaping (DistributionTemplateRuleDraft) async -> Void
    ) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                effectivePeriodSection
                if draft.scope == .selectedProjects {
                    projectSelectionSection
                }
                if draft.scope == .selectedProjects
                    && draft.basis == .fixedWeight
                    && !draft.selectedProjectIds.isEmpty
                {
                    weightSection
                }
            }
            .navigationTitle(draft.isNew ? "配賦テンプレート追加" : "配賦テンプレート編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await onSave(draft) }
                    }
                }
            }
        }
    }

    private var basicInfoSection: some View {
        Section("基本情報") {
            TextField("テンプレート名", text: $draft.name)

            Picker("対象範囲", selection: $draft.scope) {
                ForEach(DistributionScope.allCases, id: \.self) { scope in
                    Text(scope.displayName).tag(scope)
                }
            }

            Picker("配賦基準", selection: $draft.basis) {
                ForEach(DistributionBasis.allCases, id: \.self) { basis in
                    Text(basis.displayName).tag(basis)
                }
            }

            Picker("端数調整", selection: $draft.roundingPolicy) {
                ForEach(RoundingPolicy.allCases, id: \.self) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
        }
    }

    private var effectivePeriodSection: some View {
        Section("適用期間") {
            DatePicker("開始日", selection: $draft.effectiveFrom, displayedComponents: .date)

            Toggle("終了日を設定", isOn: $draft.hasEffectiveTo)

            if draft.hasEffectiveTo {
                DatePicker("終了日", selection: $draft.effectiveTo, displayedComponents: .date)
            }
        }
    }

    private var projectSelectionSection: some View {
        Section("対象プロジェクト") {
            if draft.availableProjects.isEmpty {
                Text("プロジェクトがありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.availableProjects, id: \.id) { project in
                    Toggle(
                        project.name,
                        isOn: Binding(
                            get: { draft.selectedProjectIds.contains(project.id) },
                            set: { isSelected in
                                draft.setProject(project.id, selected: isSelected)
                            }
                        )
                    )
                }
            }
        }
    }

    private var weightSection: some View {
        Section("重み") {
            ForEach(draft.selectedProjects, id: \.id) { project in
                TextField(
                    project.name,
                    text: Binding(
                        get: { draft.weightText(for: project.id) },
                        set: { draft.setWeightText($0, for: project.id) }
                    )
                )
                .keyboardType(.decimalPad)
            }
        }
    }
}

// MARK: - DistributionTemplateRuleDraft

private struct DistributionTemplateRuleDraft: Identifiable {
    let id: UUID
    let createdAt: Date
    let isNew: Bool
    let availableProjects: [PPProject]
    var name: String
    var scope: DistributionScope
    var basis: DistributionBasis
    var roundingPolicy: RoundingPolicy
    var effectiveFrom: Date
    var hasEffectiveTo: Bool
    var effectiveTo: Date
    var selectedProjectIds: Set<UUID>
    var weightTexts: [UUID: String]

    var selectedProjects: [PPProject] {
        availableProjects.filter { selectedProjectIds.contains($0.id) }
    }

    init(availableProjects: [PPProject]) {
        let now = Date()
        self.id = UUID()
        self.createdAt = now
        self.isNew = true
        self.availableProjects = availableProjects
        self.name = ""
        self.scope = .allActiveProjectsInMonth
        self.basis = .equal
        self.roundingPolicy = .lastProjectAdjust
        self.effectiveFrom = now
        self.hasEffectiveTo = false
        self.effectiveTo = now
        self.selectedProjectIds = []
        self.weightTexts = [:]
    }

    init(rule: DistributionRule, availableProjects: [PPProject]) {
        self.id = rule.id
        self.createdAt = rule.createdAt
        self.isNew = false
        self.availableProjects = availableProjects
        self.name = rule.name
        self.scope = rule.scope
        self.basis = rule.basis
        self.roundingPolicy = rule.roundingPolicy
        self.effectiveFrom = rule.effectiveFrom
        self.hasEffectiveTo = rule.effectiveTo != nil
        self.effectiveTo = rule.effectiveTo ?? rule.effectiveFrom
        self.selectedProjectIds = Set(rule.weights.map(\.projectId))
        self.weightTexts = Dictionary(
            uniqueKeysWithValues: rule.weights.map { weight in
                (weight.projectId, NSDecimalNumber(decimal: weight.weight).stringValue)
            }
        )
    }

    mutating func setProject(_ projectId: UUID, selected: Bool) {
        if selected {
            selectedProjectIds.insert(projectId)
            if weightTexts[projectId] == nil {
                weightTexts[projectId] = "1.0"
            }
        } else {
            selectedProjectIds.remove(projectId)
            weightTexts[projectId] = nil
        }
    }

    func weightText(for projectId: UUID) -> String {
        weightTexts[projectId] ?? "1.0"
    }

    mutating func setWeightText(_ value: String, for projectId: UUID) {
        weightTexts[projectId] = value
    }

    func makeRule(businessId: UUID) throws -> DistributionRule {
        try DistributionRuleBuilder().build(
            id: id,
            createdAt: createdAt,
            businessId: businessId,
            name: name,
            scope: scope,
            basis: basis,
            roundingPolicy: roundingPolicy,
            effectiveFrom: effectiveFrom,
            effectiveTo: hasEffectiveTo ? effectiveTo : nil,
            selectedProjectIds: selectedProjectIds,
            weightTexts: weightTexts
        )
    }
}
