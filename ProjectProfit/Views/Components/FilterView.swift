import SwiftUI

struct FilterView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var filter: TransactionFilter

    @State private var projects: [PPProject] = []
    @State private var categories: [PPCategory] = []
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var hasStartDate = false
    @State private var hasEndDate = false
    @State private var projectId: UUID?
    @State private var categoryId: String?
    @State private var type: TransactionType?
    @State private var amountMinText: String = ""
    @State private var amountMaxText: String = ""
    @State private var counterpartyText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("期間") {
                    Toggle("開始日", isOn: $hasStartDate)
                    if hasStartDate {
                        DatePicker("開始日", selection: $startDate, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                    }
                    Toggle("終了日", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("終了日", selection: $endDate, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                    }
                }

                Section("プロジェクト") {
                    Picker("プロジェクト", selection: $projectId) {
                        Text("すべて").tag(UUID?.none)
                        ForEach(projects, id: \.id) { p in
                            Text(p.name).tag(UUID?.some(p.id))
                        }
                    }
                }

                Section("カテゴリ") {
                    Picker("カテゴリ", selection: $categoryId) {
                        Text("すべて").tag(String?.none)
                        ForEach(categories, id: \.id) { c in
                            Text(c.name).tag(String?.some(c.id))
                        }
                    }
                }

                Section("種類") {
                    Picker("種類", selection: $type) {
                        Text("すべて").tag(TransactionType?.none)
                        Text("収益").tag(TransactionType?.some(.income))
                        Text("経費").tag(TransactionType?.some(.expense))
                        Text("振替").tag(TransactionType?.some(.transfer))
                    }
                    .pickerStyle(.segmented)
                }

                Section("取引先") {
                    TextField("取引先名で検索", text: $counterpartyText)
                }

                Section("金額範囲") {
                    HStack {
                        Text("最低金額")
                            .foregroundStyle(.secondary)
                        TextField("¥0", text: $amountMinText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("最高金額")
                            .foregroundStyle(.secondary)
                        TextField("上限なし", text: $amountMaxText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Button("フィルターをリセット", role: .destructive) {
                        resetFilter()
                    }
                }
            }
            .navigationTitle("フィルター")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("適用") { applyFilter() }
                }
            }
            .onAppear {
                loadCurrentFilter()
                loadSourceData()
            }
        }
    }

    private func loadSourceData() {
        let projectSnapshot = ProjectQueryUseCase(modelContext: modelContext).listSnapshot()
        let categorySnapshot = CategoryQueryUseCase(modelContext: modelContext).snapshot()
        projects = projectSnapshot.activeProjects + projectSnapshot.archivedProjects
        categories = categorySnapshot.categories
    }

    private func loadCurrentFilter() {
        if let start = filter.startDate {
            hasStartDate = true
            startDate = start
        }
        if let end = filter.endDate {
            hasEndDate = true
            endDate = end
        }
        projectId = filter.projectId
        categoryId = filter.categoryId
        type = filter.type
        amountMinText = filter.amountMin.map(String.init) ?? ""
        amountMaxText = filter.amountMax.map(String.init) ?? ""
        counterpartyText = filter.counterparty ?? ""
    }

    private func applyFilter() {
        let trimmedCounterparty = counterpartyText.trimmingCharacters(in: .whitespaces)
        filter = TransactionFilter(
            startDate: hasStartDate ? startDate : nil,
            endDate: hasEndDate ? endDate : nil,
            projectId: projectId,
            categoryId: categoryId,
            type: type,
            amountMin: Int(amountMinText),
            amountMax: Int(amountMaxText),
            counterparty: trimmedCounterparty.isEmpty ? nil : trimmedCounterparty
        )
        dismiss()
    }

    private func resetFilter() {
        hasStartDate = false
        hasEndDate = false
        projectId = nil
        categoryId = nil
        type = nil
        amountMinText = ""
        amountMaxText = ""
        counterpartyText = ""
    }
}
