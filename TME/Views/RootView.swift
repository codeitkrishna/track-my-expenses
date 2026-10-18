import SwiftUI

struct RootView: View {
    var body: some View {
        LedgerView()
            .tint(.white)
            .preferredColorScheme(.dark)
            .task {
                if !LaunchOptions.isUITesting {
                    await TagNotifications.requestPermissionIfNeeded()
                }
            }
    }
}
