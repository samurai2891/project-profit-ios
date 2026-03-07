import SwiftUI
import SwiftData

@main
struct ProjectProfitApp: App {
    @State private var notificationService = NotificationService()
    private let notificationDelegate = NotificationDelegate()
    private let sharedModelContainer: ModelContainer
    private static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        NSClassFromString("XCTestCase") != nil

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        do {
            sharedModelContainer = try ModelContainerFactory.makeAppContainer()
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if Self.isRunningTests {
                EmptyView()
            } else {
                ContentView()
                    .environment(notificationService)
                    .task {
                        await notificationService.checkAuthorizationStatus()
                    }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
