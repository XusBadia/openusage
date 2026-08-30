import SwiftUI

@main
struct UsageCompanionApp: App {
    @State private var store = MobileDashboardStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task { await store.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await store.refresh() }
                }
        }
    }
}
