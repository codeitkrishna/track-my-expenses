import SwiftData
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set before launch finishes so taps on banner buttons that wake the
        // app in the background are delivered here.
        UNUserNotificationCenter.current().delegate = self
        TagNotifications.registerCategories(in: DataStore.shared.context)
        #if DEBUG
        DebugHooks.run(in: DataStore.shared.context)
        #endif
        return true
    }
}

extension AppDelegate: @preconcurrency UNUserNotificationCenterDelegate {
    // Show the banner even while the app is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let typedText = (response as? UNTextInputNotificationResponse)?.userText
        let openedEntry = TagNotifications.handle(
            actionID: response.actionIdentifier,
            typedText: typedText,
            userInfo: response.notification.request.content.userInfo,
            in: DataStore.shared.context
        )
        if let openedEntry {
            AppRouter.shared.entryToTag = openedEntry
        }
        completionHandler()
    }
}
