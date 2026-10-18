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

    static func askForCategory(entryID: UUID, in context: ModelContext) async {
        guard let entry = entry(withID: entryID, in: context) else { return }
        registerCategories(in: context)

        let content = UNMutableNotificationContent()
        let amount = Rupees.format(paise: entry.amountPaise)
        switch entry.flow {
        case .expense:
            content.title = entry.displayMerchant.map { "\(amount) to \($0)" } ?? "\(amount) spent"
        case .income:
            content.title = entry.displayMerchant.map { "\(amount) from \($0)" } ?? "\(amount) received"
        }
        content.body = "Press and hold to pick a category."
        content.sound = .default
        content.threadIdentifier = "tag"
        content.categoryIdentifier = entry.flow == .expense ? expenseCategoryID : incomeCategoryID
        content.userInfo = [entryKey: entry.uuid.uuidString]

        let request = UNNotificationRequest(identifier: entry.uuid.uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
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
        } else if actionID == otherActionID,
                  let typedText,
                  let category = Tagging.findOrCreateCategory(named: typedText, flow: entry.flow, in: context) {
            Tagging.assign(category, to: entry, in: context)
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
            title: "Other…",
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
