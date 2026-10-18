import ActivityKit
import Foundation
import SwiftData
import TMECore

/// Asks for a new payment's category: in the Dynamic Island when iOS allows
/// it, otherwise with a notification.
@MainActor
enum TagPrompt {
    static func ask(entryID: UUID, in context: ModelContext) async {
        if await TagActivities.start(entryID: entryID, in: context) { return }
        await TagNotifications.askForCategory(entryID: entryID, in: context)
    }
}

@MainActor
enum TagActivities {
    static let enabledKey = "askInDynamicIsland"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Shows the prompt for one payment, replacing any earlier one (those
    /// stay under "Needs a category"). False if it couldn't be shown.
    static func start(entryID: UUID, in context: ModelContext) async -> Bool {
        guard isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        var descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.uuid == entryID })
        descriptor.fetchLimit = 1
        guard let entry = try? context.fetch(descriptor).first else { return false }

        await endAll()

        let options = Tagging.categories(for: entry.flow, in: context).prefix(3).map {
            TagActivityAttributes.Option(id: $0.uuid.uuidString, name: $0.name, symbol: $0.symbol, colorSlot: $0.colorSlot)
        }
        let attributes = TagActivityAttributes(
            entryID: entry.uuid.uuidString,
            amountText: Rupees.format(paise: entry.amountPaise),
            isIncome: entry.flow == .income,
            merchant: entry.displayMerchant,
            options: Array(options)
        )
        let content = ActivityContent(
            state: TagActivityAttributes.ContentState(filedUnder: nil),
            staleDate: .now.addingTimeInterval(60 * 60)
        )
        let alert = AlertConfiguration(
            title: "\(attributes.headline)",
            body: "Which category?",
            sound: .default
        )
        do {
            if #available(iOS 26.0, *) {
                _ = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil,
                    style: .standard,
                    alertConfiguration: alert,
                    start: .now
                )
            } else {
                let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                await activity.update(content, alertConfiguration: alert)
            }
            return true
        } catch {
            return false
        }
    }

    /// A category button on the prompt was tapped.
    static func file(entryID: String, categoryID: String) async {
        let context = DataStore.shared.context
        guard let entryUUID = UUID(uuidString: entryID), let categoryUUID = UUID(uuidString: categoryID) else { return }
        var entryDescriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.uuid == entryUUID })
        entryDescriptor.fetchLimit = 1
        var categoryDescriptor = FetchDescriptor<LedgerCategory>(predicate: #Predicate { $0.uuid == categoryUUID })
        categoryDescriptor.fetchLimit = 1
        guard let entry = try? context.fetch(entryDescriptor).first,
              let category = try? context.fetch(categoryDescriptor).first
        else { return }
        Tagging.assign(category, to: entry, in: context)
        await markFiled(entryID: entryID, as: category.name)
        TagNotifications.registerCategories(in: context)
    }

    /// Shows "Filed under Food" for a moment, then removes the prompt.
    static func markFiled(entryID: String, as categoryName: String) async {
        for activity in Activity<TagActivityAttributes>.activities where activity.attributes.entryID == entryID {
            let content = ActivityContent(state: TagActivityAttributes.ContentState(filedUnder: categoryName), staleDate: nil)
            await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(5)))
        }
    }

    static func endAll() async {
        for activity in Activity<TagActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
