import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationService.self) private var notificationService
    @State private var dataStore: DataStore?
    @State private var hasInitialized = false
    @State private var pendingRecurringCount = 0
    @State private var showRecurringPreview = false

    var body: some View {
        Group {
            if let store = dataStore {
                MainTabView()
                    .environment(store)
                    .sheet(isPresented: $showRecurringPreview) {
                        RecurringPreviewView()
                            .environment(store)
                    }
            } else {
                ProgressView("読み込み中...")
            }
        }
        .task {
            guard !hasInitialized else { return }
            hasInitialized = true

            let store = DataStore(modelContext: modelContext)
            let appBootstrapWorkflowUseCase = AppBootstrapWorkflowUseCase()
            let notifService = notificationService
            store.onRecurringScheduleChanged = { recurrings in
                Task { @MainActor in
                    await notifService.rescheduleAll(recurringTransactions: recurrings)
                    refreshRecurringPreviewState(for: store)
                }
            }
            try? await appBootstrapWorkflowUseCase.initialize(dataStore: store)
            await notificationService.rescheduleAll(recurringTransactions: store.recurringTransactions)
            self.dataStore = store
            refreshRecurringPreviewState(for: store)
        }
    }

    @MainActor
    private func refreshRecurringPreviewState(for store: DataStore) {
        let recurringWorkflowUseCase = RecurringWorkflowUseCase(dataStore: store)
        let pendingItems = recurringWorkflowUseCase.previewRecurringTransactions()
        pendingRecurringCount = pendingItems.count
        if pendingRecurringCount > 0 {
            showRecurringPreview = true
        }
    }
}

struct MainTabView: View {
    @Environment(DataStore.self) private var dataStore

    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { dataStore.lastError != nil },
            set: { if !$0 { dataStore.lastError = nil } }
        )
    }

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("ダッシュボード", systemImage: "house.fill")
            }

            NavigationStack {
                EvidenceInboxView()
            }
            .tabItem {
                Label("証憑", systemImage: "doc.text.viewfinder")
            }

            NavigationStack {
                ApprovalQueueView()
            }
            .tabItem {
                Label("承認", systemImage: "checklist")
            }

            NavigationStack {
                TransactionsView()
            }
            .tabItem {
                Label("取引履歴", systemImage: "list.bullet.rectangle")
            }

            NavigationStack {
                FilingDashboardView()
            }
            .tabItem {
                Label("確定申告", systemImage: "doc.text.fill")
            }

            NavigationStack {
                SettingsMainView(reloadStoreState: {
                    dataStore.loadData()
                    dataStore.recalculateAllPartialPeriodProjects()
                })
            }
            .tabItem {
                Label("設定", systemImage: "gearshape.fill")
            }
        }
        .tint(AppColors.primary)
        .alert("エラー", isPresented: showErrorBinding) {
            Button("OK", role: .cancel) {
                dataStore.lastError = nil
            }
        } message: {
            Text(dataStore.lastError?.errorDescription ?? "不明なエラーが発生しました")
        }
    }
}
