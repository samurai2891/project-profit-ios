import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var dataStore: DataStore?

    var body: some View {
        Group {
            if let store = dataStore {
                MainTabView()
                    .environment(store)
            } else {
                ProgressView("読み込み中...")
            }
        }
        .task {
            let store = DataStore(modelContext: modelContext)
            store.loadData()
            _ = store.processRecurringTransactions()
            self.dataStore = store
        }
    }
}

struct MainTabView: View {
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
                SettingsView()
            }
            .tabItem {
                Label("設定", systemImage: "gearshape.fill")
            }
        }
        .tint(AppColors.primary)
    }
}
