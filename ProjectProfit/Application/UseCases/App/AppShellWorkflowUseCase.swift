import Foundation

@MainActor
struct AppShellWorkflowUseCase {
    struct Ports {
        let refreshAppState: @MainActor () -> Void
        let loadRecurringPreview: @MainActor () async -> [RecurringPreviewItem]
        let readCurrentError: @MainActor () -> AppError?
        let writeCurrentError: @MainActor (AppError?) -> Void
    }

    private let ports: Ports

    init(ports: Ports) {
        self.ports = ports
    }

    func refreshAppState() {
        ports.refreshAppState()
    }

    func loadRecurringPreview() async -> [RecurringPreviewItem] {
        await ports.loadRecurringPreview()
    }

    func currentError() -> AppError? {
        ports.readCurrentError()
    }

    func setCurrentError(_ error: AppError?) {
        ports.writeCurrentError(error)
    }

    func dismissCurrentError() {
        ports.writeCurrentError(nil)
    }
}
