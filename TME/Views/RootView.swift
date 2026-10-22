import SwiftUI

struct RootView: View {
    var body: some View {
        LedgerView()
            // The hold-for-more fan, above the top bar and everything else.
            .overlay { RadialLayer() }
            .tint(.white)
            .preferredColorScheme(.dark)
            .task {
                if !LaunchOptions.isUITesting {
                    await TagNotifications.requestPermissionIfNeeded()
                }
            }
    }
}
