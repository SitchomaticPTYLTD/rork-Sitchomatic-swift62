import SwiftUI

/// JoePointIgnition app entry point.
///
/// Minimal, clean MVVM architecture with strict Swift 6.2 concurrency.
/// No legacy compatibility layers, no simulator targets, no `#available` checks.
@main
struct JoePointApp: App {

    @State private var tunnelConfigurator = TunnelConfigurator.shared

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .preferredColorScheme(.dark)
                .task {
                    await tunnelConfigurator.loadConfiguration()
                }
        }
    }
}
