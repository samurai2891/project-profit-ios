import SwiftUI

/// Legacy entry point kept as a thin compatibility wrapper.
/// Forwarding to `SettingsMainView` prevents the old settings screen from drifting.
struct SettingsView: View {
    private let reloadStoreState: @MainActor () -> Void

    init(reloadStoreState: @escaping @MainActor () -> Void = {}) {
        self.reloadStoreState = reloadStoreState
    }

    var body: some View {
        SettingsMainView(reloadStoreState: reloadStoreState)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
