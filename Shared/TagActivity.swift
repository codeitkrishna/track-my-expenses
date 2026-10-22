import ActivityKit
import AppIntents
import Foundation

/// The Dynamic Island / Lock Screen prompt asking which category a new
/// payment belongs to. Shared by the app (which starts it) and the widget
/// extension (which draws it).
struct TagActivityAttributes: ActivityAttributes {
    struct Option: Codable, Hashable {
        let id: String
        let name: String
        let symbol: String
        let colorSlot: Int
    }

    struct ContentState: Codable, Hashable {
        /// The category name once the payment has been filed.
        var filedUnder: String?
        /// "Not from Goa" was tapped: the payment no longer comes out of
        /// `fromGoal`.
        var leftGoal = false
    }

    let entryID: String
    /// Already formatted, e.g. "₹250".
    let amountText: String
    let isIncome: Bool
    let merchant: String?
    /// The most-used categories, shown as buttons.
    let options: [Option]
    /// Other payments still waiting for a category.
    let waiting: Int
    /// The goal this payment came out of (it's being spent from).
    var fromGoal: String? = nil
    /// "That's 2 days of saving for Goa", or "From Goa · ₹12,400 left".
    var goalLine: String? = nil

    var headline: String {
        switch (isIncome, merchant) {
        case (false, let merchant?): "\(amountText) to \(merchant)"
        case (true, let merchant?): "\(amountText) from \(merchant)"
        case (false, nil): "\(amountText) spent"
        case (true, nil): "\(amountText) received"
        }
    }

    /// Opens the app on this payment.
    var entryURL: URL? { URL(string: "tmetracker://entry/\(entryID)") }
}

/// A category button on the prompt. Runs inside the app's process.
struct TagEntryIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "File Payment"
    static let isDiscoverable = false

    @Parameter(title: "Payment")
    var entryID: String

    @Parameter(title: "Category")
    var categoryID: String

    init() {}

    init(entryID: String, categoryID: String) {
        self.entryID = entryID
        self.categoryID = categoryID
    }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await TagActivities.file(entryID: entryID, categoryID: categoryID)
        #endif
        return .result()
    }
}

/// "Not from Goa" on the prompt: the payment stops coming out of the goal
/// it was spent from. Runs inside the app's process.
struct NotFromGoalIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Not From Goal"
    static let isDiscoverable = false

    @Parameter(title: "Payment")
    var entryID: String

    init() {}

    init(entryID: String) {
        self.entryID = entryID
    }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await TagActivities.notFromGoal(entryID: entryID)
        #endif
        return .result()
    }
}
