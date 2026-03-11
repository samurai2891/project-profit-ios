import Foundation

@MainActor
struct AppBootstrapWorkflowUseCase {
    struct Ports {
        let reloadStoreState: @MainActor () -> Void
        let loadProfile: @MainActor (Int?) async -> Bool
    }

    private let ports: Ports

    init(ports: Ports) {
        self.ports = ports
    }

    func initialize(defaultTaxYear: Int? = nil) async {
        ports.reloadStoreState()
        _ = await ports.loadProfile(defaultTaxYear)
        ports.reloadStoreState()
    }
}
