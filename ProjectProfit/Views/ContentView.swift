import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationService.self) private var notificationService
    @State private var dataStore: DataStore?
    @State private var ledgerDataStore: LedgerDataStore?

    var body: some View {
        Group {
            if let store = dataStore, let ledgerStore = ledgerDataStore {
                MainTabView()
                    .environment(store)
                    .environment(ledgerStore)
            } else {
                ProgressView("読み込み中...")
            }
        }
        .task {
            let store = DataStore(modelContext: modelContext)
            let notifService = notificationService
            store.onRecurringScheduleChanged = { recurrings in
                Task { @MainActor in await notifService.rescheduleAll(recurringTransactions: recurrings) }
            }
            store.loadData()
            store.recalculateAllPartialPeriodProjects()
            _ = store.processRecurringTransactions()
            await notificationService.rescheduleAll(recurringTransactions: store.recurringTransactions)
            self.dataStore = store
            self.ledgerDataStore = LedgerDataStore(modelContext: modelContext)
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
                ProjectsView()
            }
            .tabItem {
                Label("プロジェクト", systemImage: "folder.fill")
            }

            NavigationStack {
                TransactionsView()
            }
            .tabItem {
                Label("取引履歴", systemImage: "list.bullet.rectangle")
            }

            NavigationStack {
                ReportView()
            }
            .tabItem {
                Label("レポート", systemImage: "chart.bar.doc.horizontal.fill")
            }

            NavigationStack {
                SettingsView()
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
