import Foundation
import SwiftData
import TMECore
import UserNotifications

/// "Food is over this week's limit: ₹2,800 of ₹2,000. Goa trip is 2 days
/// later." Sent when a payment takes its category over a limit.
@MainActor
enum LimitAlerts {
    struct Message {
        /// "Food is over this week's limit".
        let title: String
        /// "₹2,800 of ₹2,000 this week. Goa trip is 2 days later."
        let detail: String
    }

    /// Tells you when `entry` took its category over a limit.
    static func check(_ entry: LedgerEntry, in context: ModelContext) {
        guard let message = message(for: entry, in: context) else { return }
        let id = entry.uuid.uuidString
        Task { await send(message, id: id) }
    }

    static func message(for entry: LedgerEntry, in context: ModelContext, now: Date = .now) -> Message? {
        let crossed = Limits.crossed(by: entry, in: context, now: now)
        guard let shortest = crossed.first, let category = entry.category else { return nil }
        let worst = crossed.max { $0.overPaise < $1.overPaise } ?? shortest
        var detail = crossed
            .map { "\(Rupees.format(paise: $0.spentPaise)) of \(Rupees.format(paise: $0.limitPaise)) \($0.period.current)" }
            .joined(separator: ", ") + "."
        let goals = (try? context.fetch(FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        if let cost = Limits.goalCost(overPaise: worst.overPaise, goals: goals, entries: entries, now: now) {
            detail += " \(cost)."
        }
        return Message(title: "\(category.name) is over \(shortest.period.currentPossessive) limit", detail: detail)
    }

    private static func send(_ message: Message, id: String) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            PromptLog.add("\(message.title); notifications are off, so it wasn't shown.")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.detail
        content.sound = .default
        content.threadIdentifier = "limits"
        do {
            try await center.add(UNNotificationRequest(identifier: "limit-\(id)", content: content, trigger: nil))
            PromptLog.add("\(message.title): told you.")
        } catch {
            PromptLog.add("The limit notification failed: \(error.localizedDescription)")
        }
    }
}
