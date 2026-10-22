import ActivityKit
import Foundation
import SwiftData
import TMECore
import UserNotifications

/// Offers to feed your goals when a big sum comes in: in the Dynamic
/// Island when iOS allows it, otherwise with a notification. Each step is
/// recorded in the prompt history.
@MainActor
enum PaydayPrompt {
    static let categoryID = "PAYDAY"
    static let acceptActionID = "PAYDAY_ACCEPT"
    static let skipActionID = "PAYDAY_SKIP"
    static let entryKey = "paydayEntryID"

    static var notificationCategory: UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoryID,
            actions: [
                UNNotificationAction(
                    identifier: acceptActionID,
                    title: "Set it aside",
                    options: [],
                    icon: UNNotificationActionIcon(systemImageName: "target")
                ),
                UNNotificationAction(identifier: skipActionID, title: "Not now", options: []),
            ],
            intentIdentifiers: []
        )
    }

    /// Offers to set part of this money aside, if any goal asks for a share
    /// of it. Returns whether it was offered.
    @discardableResult
    static func offer(entryID: UUID, inIsland: Bool = true, in context: ModelContext) async -> Bool {
        guard let entry = entry(withID: entryID, in: context), Payday.isOpen(entry) else { return false }
        let parts = Payday.plan(for: entry, goals: Goals.active(in: context))
        guard !parts.isEmpty else { return false }
        if inIsland, await start(entry, parts: parts) {
            PromptLog.add("Offered to feed your goals in the Dynamic Island.")
            return true
        }
        await notify(entry, parts: parts, in: context)
        return true
    }

    /// A button on the prompt was tapped.
    static func answer(entryID: String, accept: Bool) async {
        guard let text = resolve(entryID: entryID, accept: accept) else { return }
        await close(entryID: entryID, saying: text)
    }

    /// Sets the money aside (or not) and says what happened.
    @discardableResult
    static func resolve(entryID: String, accept: Bool) -> String? {
        let context = DataStore.shared.context
        guard let id = UUID(uuidString: entryID), let entry = entry(withID: id, in: context) else { return nil }
        let text: String
        if accept {
            let total = Payday.accept(entry, in: context)
            text = total > 0 ? "Set aside \(Rupees.format(paise: total))" : "Already set aside"
            PromptLog.add("\(text) for your goals.")
        } else {
            Payday.decline(entry)
            text = "Not this time"
            PromptLog.add("Didn't set anything aside this time.")
        }
        return text
    }

    /// Shows the answer on the prompt for a moment, then takes it down.
    static func close(entryID: String, saying text: String) async {
        for activity in Activity<PaydayActivityAttributes>.activities where activity.attributes.entryID == entryID {
            let content = ActivityContent(state: PaydayActivityAttributes.ContentState(answer: text), staleDate: nil)
            await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(5)))
        }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["payday-\(entryID)"])
    }

    /// Handles the notification's buttons. Returns false when the
    /// notification wasn't a payday one.
    static func handle(actionID: String, userInfo: [AnyHashable: Any]) -> Bool {
        guard let entryID = userInfo[entryKey] as? String else { return false }
        if actionID == acceptActionID || actionID == skipActionID {
            if let text = resolve(entryID: entryID, accept: actionID == acceptActionID) {
                Task { await close(entryID: entryID, saying: text) }
            }
        } else {
            AppRouter.shared.showGoals = true
        }
        return true
    }

    private static func start(_ entry: LedgerEntry, parts: [Payday.Part]) async -> Bool {
        guard TagActivities.isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        await TagActivities.endAll()
        let total = parts.reduce(0) { $0 + $1.paise }
        let attributes = PaydayActivityAttributes(
            entryID: entry.uuid.uuidString,
            amountText: Rupees.format(paise: entry.amountPaise),
            source: entry.displayMerchant,
            filedUnder: entry.category?.name,
            parts: parts.map {
                PaydayActivityAttributes.Part(name: $0.goal.name, amountText: Rupees.format(paise: $0.paise), colorSlot: $0.goal.colorSlot)
            },
            totalText: Rupees.format(paise: total)
        )
        let content = ActivityContent(
            state: PaydayActivityAttributes.ContentState(answer: nil),
            staleDate: .now.addingTimeInterval(6 * 60 * 60)
        )
        let alert = AlertConfiguration(
            title: "\(attributes.headline)",
            body: "Feed your goals? \(attributes.totalText)",
            sound: .default
        )
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil,
                style: .standard,
                alertConfiguration: alert,
                start: .now
            )
            return true
        } catch {
            PromptLog.add("iOS refused the payday prompt (\(error.localizedDescription)).")
            return false
        }
    }

    private static func notify(_ entry: LedgerEntry, parts: [Payday.Part], in context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            PromptLog.add("Notifications are off, so the payday offer waits in Goals.")
            return
        }
        TagNotifications.registerCategories(in: context)
        let total = parts.reduce(0) { $0 + $1.paise }
        let content = UNMutableNotificationContent()
        let amount = Rupees.format(paise: entry.amountPaise)
        content.title = entry.displayMerchant.map { "\(amount) from \($0)" } ?? "\(amount) came in"
        let split = parts.map { "\($0.goal.name) \(Rupees.format(paise: $0.paise))" }.joined(separator: " · ")
        content.body = "Feed your goals? \(split). Press and hold to set \(Rupees.format(paise: total)) aside."
        content.sound = .default
        content.threadIdentifier = "payday"
        content.categoryIdentifier = categoryID
        content.userInfo = [entryKey: entry.uuid.uuidString]
        let request = UNNotificationRequest(identifier: "payday-\(entry.uuid.uuidString)", content: content, trigger: nil)
        do {
            try await center.add(request)
            PromptLog.add("Offered to feed your goals in a notification.")
        } catch {
            PromptLog.add("The payday notification failed: \(error.localizedDescription)")
        }
    }

    private static func entry(withID id: UUID, in context: ModelContext) -> LedgerEntry? {
        var descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
