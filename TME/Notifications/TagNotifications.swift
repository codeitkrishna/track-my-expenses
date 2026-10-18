import Foundation
import SwiftData
import TMECore
import UserNotifications

/// The "₹250 to Swiggy, pick a category" banner. Pressing and holding it
/// shows buttons for your most-used categories; tapping one files the entry
/// without opening the app.
@MainActor
enum TagNotifications {
    static let expenseCategoryID = "TAG_EXPENSE"
    static let incomeCategoryID = "TAG_INCOME"
    static let otherActionID = "TAG_OTHER"
    static let entryKey = "entryID"
    private static let categoryActionPrefix = "cat:"
    private static let buttonCount = 3

    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Keeps the buttons in step with which categories you use most.
    static func registerCategories(in context: ModelContext) {
        let categories = [
            UNNotificationCategory(identifier: expenseCategoryID, actions: actions(for: .expense, in: context), intentIdentifiers: []),
            UNNotificationCategory(identifier: incomeCategoryID, actions: actions(for: .income, in: context), intentIdentifiers: []),
        ]
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories))
    }

    static let announceFiledKey = "announceAutoFiled"

    static var announcesAutoFiled: Bool {
        UserDefaults.standard.object(forKey: announceFiledKey) as? Bool ?? true
    }

    static func askForCategory(entryID: UUID, in context: ModelContext) async {
        guard let entry = entry(withID: entryID, in: context) else { return }
        await send(for: entry, body: "Press and hold to pick a category.", sound: .default, in: context)
    }

    /// A quiet "₹307 to Swiggy: filed under Food" for payments filed from
    /// merchant memory, with the same buttons to change it.
    static func announceFiled(entryID: UUID, in context: ModelContext) async {
        guard announcesAutoFiled else {
            PromptLog.add("Not announced: notifications for automatic filing are off in Settings.")
            return
        }
        guard let entry = entry(withID: entryID, in: context) else { return }
        let name = entry.category?.name ?? "its usual category"
        await send(for: entry, body: "Filed under \(name). Press and hold to change.", sound: nil, in: context)
    }

    private static func send(for entry: LedgerEntry, body: String, sound: UNNotificationSound?, in context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            PromptLog.add("Notifications are off for TME in iOS Settings, so nothing was shown.")
            return
        }
        registerCategories(in: context)

        let content = UNMutableNotificationContent()
        let amount = Rupees.format(paise: entry.amountPaise)
        switch entry.flow {
        case .expense:
            content.title = entry.displayMerchant.map { "\(amount) to \($0)" } ?? "\(amount) spent"
        case .income:
            content.title = entry.displayMerchant.map { "\(amount) from \($0)" } ?? "\(amount) received"
        }
        content.body = body
        content.sound = sound
        content.threadIdentifier = "tag"
        content.categoryIdentifier = entry.flow == .expense ? expenseCategoryID : incomeCategoryID
        content.userInfo = [entryKey: entry.uuid.uuidString]

        let request = UNNotificationRequest(identifier: entry.uuid.uuidString, content: content, trigger: nil)
        do {
            try await center.add(request)
            PromptLog.add(sound == nil ? "Sent a quiet notification." : "Sent a notification.")
        } catch {
            PromptLog.add("The notification failed: \(error.localizedDescription)")
        }
    }

    /// Handles a tap on one of the banner's buttons. Returns the entry the
    /// banner was about when the user tapped the banner itself.
    @discardableResult
    static func handle(actionID: String, typedText: String?, userInfo: [AnyHashable: Any], in context: ModelContext) -> UUID? {
        guard let idString = userInfo[entryKey] as? String,
              let id = UUID(uuidString: idString),
              let entry = entry(withID: id, in: context)
        else { return nil }

        if actionID.hasPrefix(categoryActionPrefix),
           let categoryID = UUID(uuidString: String(actionID.dropFirst(categoryActionPrefix.count))),
           let category = category(withID: categoryID, in: context) {
            Tagging.assign(category, to: entry, in: context)
            PromptLog.add("Filed under \(category.name) from the notification.")
        } else if actionID == otherActionID,
                  let typedText,
                  let category = Tagging.findOrCreateCategory(named: typedText, flow: entry.flow, in: context) {
            Tagging.assign(category, to: entry, in: context)
            PromptLog.add("Filed under \(category.name) from the notification.")
        } else if actionID == UNNotificationDefaultActionIdentifier {
            return id
        }
        registerCategories(in: context)
        return nil
    }

    private static func actions(for flow: Flow, in context: ModelContext) -> [UNNotificationAction] {
        var actions: [UNNotificationAction] = Tagging.categories(for: flow, in: context)
            .prefix(buttonCount)
            .map { category in
                UNNotificationAction(
                    identifier: categoryActionPrefix + category.uuid.uuidString,
                    title: category.name,
                    options: [],
                    icon: UNNotificationActionIcon(systemImageName: category.symbol)
                )
            }
        actions.append(UNTextInputNotificationAction(
            identifier: otherActionID,
            title: "Type a category…",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "square.and.pencil"),
            textInputButtonTitle: "Save",
            textInputPlaceholder: "Category name"
        ))
        return actions
    }

    private static func entry(withID id: UUID, in context: ModelContext) -> LedgerEntry? {
        var descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func category(withID id: UUID, in context: ModelContext) -> LedgerCategory? {
        var descriptor = FetchDescriptor<LedgerCategory>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
