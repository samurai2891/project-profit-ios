import Foundation

@MainActor
struct AppStateRefreshWorkflowUseCase {
    struct Ports {
        let loadAppState: @MainActor () -> Void
        let recalculatePartialPeriodProjects: @MainActor () -> Void
    }

    private let ports: Ports

    init(ports: Ports) {
        self.ports = ports
    }

    func refreshAppState() {
        ports.loadAppState()
        ports.recalculatePartialPeriodProjects()
    }
}

@MainActor
struct AppBootstrapWorkflowUseCase {
    struct Ports {
        let refreshAppState: @MainActor () -> Void
        let prepareCanonicalProfile: @MainActor (Int?) async -> Bool
    }

    private let ports: Ports

    init(ports: Ports) {
        self.ports = ports
    }

    func initialize(defaultTaxYear: Int? = nil) async {
        ports.refreshAppState()
        _ = await ports.prepareCanonicalProfile(defaultTaxYear)
        ports.refreshAppState()
    }
}
