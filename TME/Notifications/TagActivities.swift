import ActivityKit
import Foundation
import SwiftData
import TMECore

/// Tells you about every payment an SMS logs: asks for the category of new
/// merchants (in the Dynamic Island when iOS allows it, otherwise with a
/// notification) and quietly confirms the ones filed automatically. Each
/// step is recorded in the prompt history.
@MainActor
enum TagPrompt {
    static func follow(_ outcome: IngestOutcome, in context: ModelContext) async {
        switch outcome {
        case .needsCategory(let id):
            PromptLog.add("\(describe(id, in: context)): needs a category.")
            await ask(entryID: id, in: context)
            // The island is busy asking for the category, so this one's a banner.
            await PaydayPrompt.offer(entryID: id, inIsland: false, in: context)
        case .autoTagged(let id):
            PromptLog.add("\(describe(id, in: context)): known merchant, filed automatically.")
            // Payday: the island offers to feed your goals instead of a quiet banner.
            if await PaydayPrompt.offer(entryID: id, in: context) { return }
            await TagNotifications.announceFiled(entryID: id, in: context)
        case .duplicate:
            PromptLog.add("The same SMS arrived again; it was already logged.")
        case .ignored:
            PromptLog.add("An SMS matched your automation but isn't a transaction; ignored.")
        }
    }

    static func ask(entryID: UUID, in context: ModelContext) async {
        switch await TagActivities.start(entryID: entryID, in: context) {
        case .shown:
            PromptLog.add("Asked in the Dynamic Island.")
            return
        case .turnedOff:
            PromptLog.add("Dynamic Island prompts are off in Settings.")
        case .notAllowed:
            PromptLog.add("Live Activities are turned off for TME in iOS Settings.")
        case .refused(let reason):
            PromptLog.add("iOS refused the Dynamic Island prompt (\(reason)).")
        }
        await TagNotifications.askForCategory(entryID: entryID, in: context)
    }

    /// "₹307 out" / "₹799 in", for the history.
    static func describe(_ id: UUID, in context: ModelContext) -> String {
        var descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        guard let entry = try? context.fetch(descriptor).first else { return "A payment" }
        return "\(Rupees.format(paise: entry.amountPaise)) \(entry.flow == .income ? "in" : "out")"
    }
}

@MainActor
enum TagActivities {
    static let enabledKey = "askInDynamicIsland"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    enum StartResult: Equatable {
        case shown
        case turnedOff
        case notAllowed
        case refused(String)
    }

    /// Shows the prompt for one payment, replacing any earlier one (those
    /// stay under "Needs a category", and the prompt counts them).
    static func start(entryID: UUID, in context: ModelContext) async -> StartResult {
        guard isEnabled else { return .turnedOff }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .notAllowed }
        var descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.uuid == entryID })
        descriptor.fetchLimit = 1
        guard let entry = try? context.fetch(descriptor).first else { return .refused("payment not found") }
        let uncategorised = (try? context.fetchCount(FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.category == nil }))) ?? 1

        await endAll()

        let options = Tagging.categories(for: entry.flow, in: context).prefix(3).map {
            TagActivityAttributes.Option(id: $0.uuid.uuidString, name: $0.name, symbol: $0.symbol, colorSlot: $0.colorSlot)
        }
        let attributes = TagActivityAttributes(
            entryID: entry.uuid.uuidString,
            amountText: Rupees.format(paise: entry.amountPaise),
            isIncome: entry.flow == .income,
            merchant: entry.displayMerchant,
            options: Array(options),
            waiting: max(0, uncategorised - 1),
            fromGoal: entry.goal?.name,
            goalLine: Yardstick.line(for: entry, in: context)
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
            return .shown
        } catch {
            return .refused(error.localizedDescription)
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
        PromptLog.add("Filed under \(category.name) from the Dynamic Island.")
        await markFiled(entryID: entryID, as: category.name)
        TagNotifications.registerCategories(in: context)
    }

    /// "Not from Goa" was tapped: the payment stays, but no longer comes
    /// out of the goal.
    static func notFromGoal(entryID: String) async {
        let context = DataStore.shared.context
        guard let id = UUID(uuidString: entryID) else { return }
        var descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        guard let entry = try? context.fetch(descriptor).first else { return }
        let name = entry.goal?.name ?? "the goal"
        entry.goal = nil
        GoalRules.sync(entry, in: context)
        try? context.save()
        PromptLog.add("No longer spent from \(name), from the Dynamic Island.")
        for activity in Activity<TagActivityAttributes>.activities where activity.attributes.entryID == entryID {
            var state = activity.content.state
            state.leftGoal = true
            await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
        }
    }

    /// Shows "Filed under Food" for a moment, then removes the prompt.
    static func markFiled(entryID: String, as categoryName: String) async {
        for activity in Activity<TagActivityAttributes>.activities where activity.attributes.entryID == entryID {
            var state = activity.content.state
            state.filedUnder = categoryName
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.end(content, dismissalPolicy: .after(.now.addingTimeInterval(5)))
        }
    }

    /// Takes down every prompt, payday ones too: the island asks one
    /// thing at a time. Payments stay under "Needs a category" and paydays
    /// wait in Goals.
    static func endAll() async {
        for activity in Activity<TagActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        for activity in Activity<PaydayActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
