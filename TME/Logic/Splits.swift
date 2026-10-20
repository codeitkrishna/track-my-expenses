import Foundation
import SwiftData

/// How a payment is divided.
enum SplitMode: String, CaseIterable, Identifiable, Sendable {
    case equal
    case amounts
    case percent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equal: "Equal"
        case .amounts: "Amounts"
        case .percent: "%"
        }
    }
}

/// A split while it's being set up: who's in it and how it's divided.
struct SplitDraft: Equatable {
    struct Person: Identifiable, Equatable {
        var id: String { name.lowercased() }
        var name: String
        /// Their part in rupees, as typed (amounts mode).
        var amountText = ""
        /// Their part in percent, as typed (percent mode).
        var percentText = ""
    }

    /// Each friend's part and yours, in paise.
    struct Parts: Equatable {
        var friends: [Int]
        var mine: Int
    }

    var mode: SplitMode = .equal
    /// You're one of the people sharing the cost.
    var includesMe = true
    var friends: [Person] = []

    var isEmpty: Bool { friends.isEmpty }

    /// Adds a friend once, whatever the case it's typed in.
    mutating func add(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !friends.contains(where: { $0.id == trimmed.lowercased() }) else { return }
        friends.append(Person(name: trimmed))
    }

    mutating func remove(_ person: Person) {
        friends.removeAll { $0.id == person.id }
    }

    /// The parts for `total` paise, or nil while they don't add up.
    func parts(total: Int) -> Parts? {
        guard total > 0, !friends.isEmpty else { return nil }
        switch mode {
        case .equal:
            let people = friends.count + (includesMe ? 1 : 0)
            let each = total / people
            var leftover = total - each * people
            var shares = Array(repeating: each, count: friends.count)
            if includesMe {
                // Odd paise stay with you.
                return Parts(friends: shares, mine: each + leftover)
            }
            for index in shares.indices where leftover > 0 {
                shares[index] += 1
                leftover -= 1
            }
            return Parts(friends: shares, mine: 0)

        case .amounts:
            let typed = friends.map { BalanceStore.paise(fromTyped: $0.amountText) ?? 0 }
            guard typed.allSatisfy({ $0 >= 0 }) else { return nil }
            let mine = total - typed.reduce(0, +)
            guard mine >= 0, includesMe || mine == 0 else { return nil }
            return Parts(friends: typed, mine: mine)

        case .percent:
            let percents = friends.map { Double($0.percentText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
            let sum = percents.reduce(0, +)
            guard percents.allSatisfy({ $0 >= 0 }), sum <= 100.0001, includesMe || abs(sum - 100) < 0.0001 else { return nil }
            var shares = percents.map { Int((Double(total) * $0 / 100).rounded()) }
            var mine = total - shares.reduce(0, +)
            if !includesMe, let last = shares.indices.last {
                // Rounding leftovers go to the last friend so everything is covered.
                shares[last] += mine
                mine = 0
            }
            return mine >= 0 ? Parts(friends: shares, mine: mine) : nil
        }
    }

    /// What still needs assigning (positive) or is over (negative), in
    /// paise for amounts and hundredths of a percent for percent.
    func unassigned(total: Int) -> Int {
        switch mode {
        case .equal:
            return 0
        case .amounts:
            let typed = friends.map { BalanceStore.paise(fromTyped: $0.amountText) ?? 0 }.reduce(0, +)
            return total - typed
        case .percent:
            let typed = friends.map { Double($0.percentText.replacingOccurrences(of: ",", with: ".")) ?? 0 }.reduce(0, +)
            return Int(((100 - typed) * 100).rounded())
        }
    }

    /// The split as it was saved on `entry`.
    init(entry: LedgerEntry) {
        mode = entry.splitModeRaw.flatMap(SplitMode.init(rawValue:)) ?? .equal
        includesMe = entry.splitIncludesMe
        friends = entry.shares
            .sorted { ($0.friend?.createdAt ?? .distantPast) < ($1.friend?.createdAt ?? .distantPast) }
            .compactMap { share in
                guard let name = share.friend?.name else { return nil }
                return Person(
                    name: name,
                    amountText: Self.typed(share.amountPaise),
                    percentText: share.percent.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? ""
                )
            }
    }

    init() {}

    /// 30000 paise → "300"; 1050 → "10.50".
    static func typed(_ paise: Int) -> String {
        paise % 100 == 0 ? "\(paise / 100)" : String(format: "%d.%02d", paise / 100, paise % 100)
    }
}

@MainActor
enum Splits {
    /// Saves `draft` as `entry`'s split: friends found by name (or added),
    /// one share each. A friend who already paid back keeps that, as long
    /// as their part didn't change.
    static func apply(_ draft: SplitDraft, to entry: LedgerEntry, in context: ModelContext) {
        let parts = draft.parts(total: entry.amountPaise)
        let previous = entry.shares
        entry.shares = []
        for share in previous { context.delete(share) }

        guard let parts, !draft.friends.isEmpty else {
            entry.splitModeRaw = nil
            entry.splitIncludesMe = true
            return
        }
        entry.splitModeRaw = draft.mode.rawValue
        entry.splitIncludesMe = draft.includesMe
        for (person, paise) in zip(draft.friends, parts.friends) where paise > 0 {
            let friend = findOrCreateFriend(named: person.name, in: context)
            let percent = draft.mode == .percent ? Double(person.percentText.replacingOccurrences(of: ",", with: ".")) : nil
            let share = SplitShare(friend: friend, amountPaise: paise, percent: percent)
            if let old = previous.first(where: { $0.friend?.uuid == friend.uuid }), old.settled, old.amountPaise == paise {
                share.settled = true
                share.settledAt = old.settledAt
            }
            context.insert(share)
            share.entry = entry
        }
    }

    /// Records that `friend` paid back everything they owe.
    static func settle(_ friend: Friend, at date: Date = .now) {
        for share in friend.shares where !share.settled {
            share.settled = true
            share.settledAt = date
        }
    }

    static func findOrCreateFriend(named rawName: String, in context: ModelContext) -> Friend {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = (try? context.fetch(FetchDescriptor<Friend>())) ?? []
        if let existing = all.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let friend = Friend(name: name)
        context.insert(friend)
        return friend
    }
}

extension LedgerEntry {
    /// Your own part of this payment, after friends' shares.
    var myPartPaise: Int { amountPaise - shares.reduce(0) { $0 + $1.amountPaise } }
}
