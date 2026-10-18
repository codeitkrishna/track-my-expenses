import Foundation

/// What happened to each incoming payment and its prompt, newest last.
/// Shown in Settings → Prompt history, to see why a prompt didn't appear.
@MainActor
enum PromptLog {
    struct Event: Codable, Identifiable, Equatable {
        var id = UUID()
        let date: Date
        let text: String
    }

    static let limit = 200

    static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "prompt-log.json")
    }

    static func add(_ text: String, at date: Date = .now, to url: URL = fileURL) {
        var events = load(from: url)
        events.append(Event(date: date, text: text))
        if events.count > limit { events.removeFirst(events.count - limit) }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(events).write(to: url, options: .atomic)
    }

    static func load(from url: URL = fileURL) -> [Event] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Event].self, from: data)) ?? []
    }

    static func clear(at url: URL = fileURL) {
        try? FileManager.default.removeItem(at: url)
    }
}
