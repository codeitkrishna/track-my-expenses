import ActivityKit
import AppIntents
import Foundation

/// "₹62,000 in. Feed your goals?" in the Dynamic Island and on the Lock
/// Screen, when a big sum comes in and goals have asked for a share of it.
/// Shared by the app (which starts it) and the widget extension (which
/// draws it).
struct PaydayActivityAttributes: ActivityAttributes {
    struct Part: Codable, Hashable {
        let name: String
        /// Already formatted, e.g. "₹5,000".
        let amountText: String
        let colorSlot: Int
    }

    struct ContentState: Codable, Hashable {
        /// Nil while waiting; then "Set aside ₹11,200" or "Not this time".
        var answer: String?
    }

    let entryID: String
    /// What came in, e.g. "₹62,000".
    let amountText: String
    let source: String?
    /// Its category, when it's already filed.
    let filedUnder: String?
    let parts: [Part]
    /// All of `parts` together, e.g. "₹11,200".
    let totalText: String

    var headline: String {
        source.map { "\(amountText) from \($0)" } ?? "\(amountText) came in"
    }

    /// Opens the goals.
    var goalsURL: URL? { URL(string: "tmetracker://goals") }
}

/// "Set aside ₹11,200" on the payday prompt. Runs inside the app's process.
struct SetAsideIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Set Aside for Goals"
    static let isDiscoverable = false

    @Parameter(title: "Payment")
    var entryID: String

    init() {}

    init(entryID: String) {
        self.entryID = entryID
    }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await PaydayPrompt.answer(entryID: entryID, accept: true)
        #endif
        return .result()
    }
}

/// "Not now" on the payday prompt.
struct SkipPaydayIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip Setting Aside"
    static let isDiscoverable = false

    @Parameter(title: "Payment")
    var entryID: String

    init() {}

    init(entryID: String) {
        self.entryID = entryID
    }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await PaydayPrompt.answer(entryID: entryID, accept: false)
        #endif
        return .result()
    }
}
