import Foundation

@MainActor
struct AppShellWorkflowUseCase {
    struct Ports {
        let reloadStoreState: @MainActor () -> Void
        let refreshRecurringPreview: @MainActor () -> [RecurringPreviewItem]
        let readCurrentError: @MainActor () -> AppError?
        let writeCurrentError: @MainActor (AppError?) -> Void
    }

    private let ports: Ports

    init(ports: Ports) {
        self.ports = ports
    }

    func reloadStoreState() {
        ports.reloadStoreState()
    }

    func refreshRecurringPreview() -> [RecurringPreviewItem] {
        ports.refreshRecurringPreview()
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
