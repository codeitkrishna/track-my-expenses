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
    /// An expense coming out of a goal: the same buttons plus "Not from Goa".
    static let goalExpenseCategoryID = "TAG_EXPENSE_GOAL"
    static let notFromGoalActionID = "TAG_NOT_FROM_GOAL"
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
        var categories = [
            UNNotificationCategory(identifier: expenseCategoryID, actions: actions(for: .expense, in: context), intentIdentifiers: []),
            UNNotificationCategory(identifier: incomeCategoryID, actions: actions(for: .income, in: context), intentIdentifiers: []),
            PaydayPrompt.notificationCategory,
        ]
        if let goal = Goals.spendingGoal(in: context) {
            let notFromGoal = UNNotificationAction(
                identifier: notFromGoalActionID,
                title: "Not from \(goal.name)",
                options: [],
                icon: UNNotificationActionIcon(systemImageName: "arrow.uturn.backward")
            )
            categories.append(UNNotificationCategory(
                identifier: goalExpenseCategoryID,
                actions: actions(for: .expense, in: context) + [notFromGoal],
                intentIdentifiers: []
            ))
        }
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories))
    }

    static let announceFiledKey = "announceAutoFiled"

    static var announcesAutoFiled: Bool {
        UserDefaults.standard.object(forKey: announceFiledKey) as? Bool ?? true
    }

    static func askForCategory(entryID: UUID, in context: ModelContext) async {
        guard let entry = entry(withID: entryID, in: context) else { return }
        await send(for: entry, body: withGoalLine("Press and hold to pick a category.", for: entry, in: context), sound: .default, in: context)
    }

    /// A quiet "₹307 to Swiggy: filed under Food" for payments filed from
    /// merchant memory, with the same buttons to change it.
    /// Over a category's limit, it says so, with a sound.
    static func announceFiled(entryID: UUID, in context: ModelContext) async {
        guard let entry = entry(withID: entryID, in: context) else { return }
        guard announcesAutoFiled else {
            PromptLog.add("Not announced: notifications for automatic filing are off in Settings.")
            LimitAlerts.check(entry, in: context)
            return
        }
        let name = entry.category?.name ?? "its usual category"
        if let limit = LimitAlerts.message(for: entry, in: context) {
            await send(for: entry, body: "\(limit.title): \(limit.detail) Press and hold to change the category.", sound: .default, in: context)
            return
        }
        await send(for: entry, body: withGoalLine("Filed under \(name). Press and hold to change.", for: entry, in: context), sound: nil, in: context)
    }

    /// Puts "That's 2 days of saving for Goa." (or "From Goa · ₹12,400
    /// left.") first, when there's a goal to say it about.
    private static func withGoalLine(_ body: String, for entry: LedgerEntry, in context: ModelContext) -> String {
        guard let line = Yardstick.line(for: entry, in: context) else { return body }
        return "\(line). \(body)"
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
        content.categoryIdentifier = switch entry.flow {
        case .expense: entry.goal != nil && Goals.spendingGoal(in: context) != nil ? goalExpenseCategoryID : expenseCategoryID
        case .income: incomeCategoryID
        }
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
        } else if actionID == notFromGoalActionID {
            let name = entry.goal?.name ?? "the goal"
            entry.goal = nil
            GoalRules.sync(entry, in: context)
            try? context.save()
            PromptLog.add("No longer spent from \(name), from the notification.")
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
