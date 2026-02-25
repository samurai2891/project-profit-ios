import SwiftUI
import SwiftData

@main
struct ProjectProfitApp: App {
    @State private var notificationService = NotificationService()
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(notificationService)
                .task {
                    await notificationService.checkAuthorizationStatus()
                }
        }
        .modelContainer(for: [
            PPProject.self,
            PPTransaction.self,
            PPCategory.self,
            PPRecurringTransaction.self,
            PPAccount.self,
            PPJournalEntry.self,
            PPJournalLine.self,
            PPAccountingProfile.self,
            PPUserRule.self,
            PPFixedAsset.self
        ])
    }
}
