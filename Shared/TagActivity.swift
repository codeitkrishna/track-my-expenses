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
