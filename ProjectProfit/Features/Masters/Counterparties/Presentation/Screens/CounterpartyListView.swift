import SwiftData
import SwiftUI

struct CounterpartyListView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.modelContext) private var modelContext

    @State private var counterparties: [Counterparty] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAddForm = false
    @State private var deleteTargetId: UUID?

    private var filteredCounterparties: [Counterparty] {
        guard !searchText.isEmpty else { return counterparties }
        let query = searchText.lowercased()
        return counterparties.filter { cp in
            cp.displayName.lowercased().contains(query)
                || cp.kana?.lowercased().contains(query) == true
                || cp.invoiceRegistrationNumber?.contains(query) == true
                || cp.corporateNumber?.contains(query) == true
        }
    }

    var body: some View {
        List {
            if isLoading && counterparties.isEmpty {
                ProgressView("取引先を読み込み中...")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if counterparties.isEmpty {
                ContentUnavailableView(
                    "取引先が登録されていません",
                    systemImage: "person.2",
                    description: Text("右上の＋ボタンから取引先を追加できます")
                )
            } else {
                ForEach(filteredCounterparties, id: \.id) { counterparty in
                    NavigationLink {
                        CounterpartyFormView(counterparty: counterparty) {
                            Task { await loadCounterparties() }
                        }
                    } label: {
                        counterpartyRow(counterparty)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteTargetId = counterparty.id
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("取引先管理")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "名前・T番号で検索")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("取引先を追加")
            }
        }
        .task(id: dataStore.businessProfile?.id) {
            await loadCounterparties()
        }
        .refreshable {
            await loadCounterparties()
        }
        .sheet(isPresented: $showAddForm, onDismiss: {
            Task { await loadCounterparties() }
        }) {
            NavigationStack {
                CounterpartyFormView(counterparty: nil) {
                    showAddForm = false
                    Task { await loadCounterparties() }
                }
            }
        }
        .alert("取引先を削除", isPresented: Binding(
            get: { deleteTargetId != nil },
            set: { if !$0 { deleteTargetId = nil } }
        )) {
            Button("キャンセル", role: .cancel) { deleteTargetId = nil }
            Button("削除", role: .destructive) {
                if let id = deleteTargetId {
                    Task { await deleteCounterparty(id) }
                }
            }
        } message: {
            Text("この取引先を削除しますか？")
        }
        .alert("エラー", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func counterpartyRow(_ counterparty: Counterparty) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(counterparty.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(counterparty.invoiceIssuerStatus.displayName)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(issuerStatusColor(counterparty.invoiceIssuerStatus).opacity(0.12))
                    .foregroundStyle(issuerStatusColor(counterparty.invoiceIssuerStatus))
                    .clipShape(Capsule())
            }
            if let kana = counterparty.kana, !kana.isEmpty {
                Text(kana)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let regNum = counterparty.normalizedInvoiceRegistrationNumber {
                Text(regNum)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func issuerStatusColor(_ status: InvoiceIssuerStatus) -> Color {
        switch status {
        case .registered: AppColors.success
        case .unregistered: AppColors.warning
        case .unknown: AppColors.muted
        }
    }

    private func loadCounterparties() async {
        guard let businessId = dataStore.businessProfile?.id else {
            counterparties = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await CounterpartyMasterUseCase(modelContext: modelContext)
                .loadCounterparties(businessId: businessId)
            counterparties = loaded.sorted {
                ($0.kana ?? $0.displayName) < ($1.kana ?? $1.displayName)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCounterparty(_ id: UUID) async {
        do {
            try await CounterpartyMasterUseCase(modelContext: modelContext).delete(id)
            await loadCounterparties()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
