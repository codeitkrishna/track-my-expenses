import Foundation
import SwiftData

/// The one database the app, its Shortcuts actions and its notification
/// buttons all share. Actions run inside the app's process, so they see the
/// same store even when the app isn't open.
@MainActor
final class DataStore {
    static let shared = DataStore()

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init(inMemory: Bool = LaunchOptions.isUITesting) {
        let schema = Schema([LedgerEntry.self, LedgerCategory.self, MerchantRule.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not open the database: \(error)")
        }
        DefaultCategories.seedIfNeeded(in: container.mainContext)
        Tagging.migrateRuleKeys(in: container.mainContext)
    }
}

/// Launch arguments used by UI tests and screenshots.
enum LaunchOptions {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// Fresh in-memory data and no permission prompts.
    static var isUITesting: Bool { arguments.contains("-uiTesting") }

    static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
