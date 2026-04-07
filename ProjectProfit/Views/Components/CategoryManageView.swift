import SwiftUI

/// Legacy entry point kept as a thin compatibility wrapper.
/// Forwarding to `CategoryListView` keeps category management on the canonical screen.
struct CategoryManageView: View {
    var body: some View {
        CategoryListView()
    }
}

#Preview {
    NavigationStack {
        CategoryManageView()
    }
}
