import SwiftData
import SwiftUI

@main
struct TMEApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // UI tests start from a clean slate: no starting balance or other settings.
        if LaunchOptions.isUITesting, let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
            PromptLog.clear()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppRouter.shared)
                .onOpenURL { url in
                    // tmetracker://entry/<id> from the Dynamic Island prompt.
                    if url.host() == "entry", let id = UUID(uuidString: url.lastPathComponent) {
                        AppRouter.shared.entryToTag = id
                    }
                }
        }
        .modelContainer(DataStore.shared.container)
    }
}

enum AppTab: String {
    case activity
    case dashboard
    case settings
}

/// App-wide navigation requests, such as "open the entry this banner was about".
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var tab: AppTab = .activity
    var entryToTag: UUID? {
        didSet { if entryToTag != nil { tab = .activity } }
    }

    init() {
        #if DEBUG
        if let tab = LaunchOptions.value(after: "-tab").flatMap(AppTab.init(rawValue:)) {
            self.tab = tab
        }
        #endif
    }
}
