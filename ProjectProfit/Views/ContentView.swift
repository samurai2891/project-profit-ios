import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationService.self) private var notificationService
    @State private var appStore: DataStore?
    @State private var hasInitialized = false
    @State private var pendingRecurringCount = 0
    @State private var showRecurringPreview = false

    private let appShellWorkflowUseCase = AppShellWorkflowUseCase()

    var body: some View {
        Group {
            if let store = appStore {
                MainTabView(
                    store: store,
                    appShellWorkflowUseCase: appShellWorkflowUseCase
                )
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
            self.appStore = store
            refreshRecurringPreviewState(for: store)
        }
    }

    @MainActor
    private func refreshRecurringPreviewState(for store: DataStore) {
        let pendingItems = appShellWorkflowUseCase.refreshRecurringPreview(dataStore: store)
        pendingRecurringCount = pendingItems.count
        if pendingRecurringCount > 0 {
            showRecurringPreview = true
        }
    }
}

struct MainTabView: View {
    let store: DataStore
    let appShellWorkflowUseCase: AppShellWorkflowUseCase

    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { appShellWorkflowUseCase.currentError(dataStore: store) != nil },
            set: { if !$0 { appShellWorkflowUseCase.dismissCurrentError(dataStore: store) } }
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
                    appShellWorkflowUseCase.reloadStoreState(dataStore: store)
                })
            }
            .tabItem {
                Label("設定", systemImage: "gearshape.fill")
            }
        }
        .tint(AppColors.primary)
        .alert("エラー", isPresented: showErrorBinding) {
            Button("OK", role: .cancel) {
                appShellWorkflowUseCase.dismissCurrentError(dataStore: store)
            }
        } message: {
            Text(appShellWorkflowUseCase.currentError(dataStore: store)?.errorDescription ?? "不明なエラーが発生しました")
        }
    }
}
