import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Activity", systemImage: "list.bullet.rectangle", value: AppTab.activity) {
                ActivityView()
            }
            Tab("Dashboard", systemImage: "chart.bar.xaxis", value: AppTab.dashboard) {
                DashboardView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .task {
            if !LaunchOptions.isUITesting {
                await TagNotifications.requestPermissionIfNeeded()
            }
        }
    }
}
