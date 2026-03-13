import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationService.self) private var notificationService
    @State private var appStore: DataStore?
    @State private var hasInitialized = false
    @State private var pendingRecurringCount = 0
    @State private var showRecurringPreview = false

    var body: some View {
        Group {
            if let store = appStore {
                MainTabView(
                    store: store,
                    appShellWorkflowUseCase: appShellWorkflowUseCase(for: store)
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
            let notifService = notificationService
            store.onRecurringScheduleChanged = { recurrings in
                Task { @MainActor in
                    await notifService.rescheduleAll(recurringTransactions: recurrings)
                    refreshRecurringPreviewState(for: store)
                }
            }
            await appBootstrapWorkflowUseCase(for: store).initialize()
            await notificationService.rescheduleAll(recurringTransactions: store.recurringTransactions)
            self.appStore = store
            refreshRecurringPreviewState(for: store)
        }
    }

    @MainActor
    private func refreshRecurringPreviewState(for store: DataStore) {
        let pendingItems = appShellWorkflowUseCase(for: store).loadRecurringPreview()
        pendingRecurringCount = pendingItems.count
        if pendingRecurringCount > 0 {
            showRecurringPreview = true
        }
    }

    @MainActor
    private func appBootstrapWorkflowUseCase(for store: DataStore) -> AppBootstrapWorkflowUseCase {
        AppBootstrapWorkflowUseCase(
            ports: .init(
                refreshAppState: {
                    appStateRefreshWorkflowUseCase(for: store).refreshAppState()
                },
                prepareCanonicalProfile: { defaultTaxYear in
                    await profileSettingsWorkflowUseCase(for: store).loadProfile(defaultTaxYear: defaultTaxYear)
                }
            )
        )
    }

    @MainActor
    private func appShellWorkflowUseCase(for store: DataStore) -> AppShellWorkflowUseCase {
        AppShellWorkflowUseCase(
            ports: .init(
                refreshAppState: {
                    appStateRefreshWorkflowUseCase(for: store).refreshAppState()
                },
                loadRecurringPreview: {
                    RecurringWorkflowUseCase(modelContext: store.modelContext).previewRecurringTransactions()
                },
                readCurrentError: { store.lastError },
                writeCurrentError: { store.lastError = $0 }
            )
        )
    }

    @MainActor
    private func appStateRefreshWorkflowUseCase(for store: DataStore) -> AppStateRefreshWorkflowUseCase {
        AppStateRefreshWorkflowUseCase(
            ports: .init(
                loadAppState: {
                    store.loadData()
                },
                recalculatePartialPeriodProjects: {
                    store.recalculateAllPartialPeriodProjects()
                }
            )
        )
    }

    @MainActor
    private func profileSettingsWorkflowUseCase(for store: DataStore) -> ProfileSettingsWorkflowUseCase {
        ProfileSettingsWorkflowUseCase(
            modelContext: store.modelContext,
            ports: .init(
                readSensitivePayload: { store.profileSensitivePayload },
                readCurrentTaxYear: { store.currentTaxYearProfile?.taxYear },
                applyState: { store.applyProfileSettingsState($0) },
                persistSensitivePayload: { payload, businessProfileId in
                    store.persistSensitivePayload(payload, businessProfileId: businessProfileId)
                },
                setLastError: { store.lastError = $0 }
            )
        )
    }
}

struct MainTabView: View {
    let store: DataStore
    let appShellWorkflowUseCase: AppShellWorkflowUseCase

    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { appShellWorkflowUseCase.currentError() != nil },
            set: { if !$0 { appShellWorkflowUseCase.dismissCurrentError() } }
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
                    appShellWorkflowUseCase.refreshAppState()
                })
            }
            .tabItem {
                Label("設定", systemImage: "gearshape.fill")
            }
        }
        .tint(AppColors.primary)
        .alert("エラー", isPresented: showErrorBinding) {
            Button("OK", role: .cancel) {
                appShellWorkflowUseCase.dismissCurrentError()
            }
        } message: {
            Text(appShellWorkflowUseCase.currentError()?.errorDescription ?? "不明なエラーが発生しました")
        }
    }
}
