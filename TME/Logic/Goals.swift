import Foundation
import SwiftData
import TMECore

extension Goal {
    /// Everything put in, less anything taken back out.
    var savedPaise: Int { moves.reduce(0) { $0 + $1.amountPaise } }
    /// Payments spent from it.
    var spentPaise: Int { spends.filter { $0.flow == .expense }.reduce(0) { $0 + $1.amountPaise } }
    /// Still set aside: saved less spent, never below zero. This much is
    /// kept out of "free to spend".
    var heldPaise: Int { max(0, savedPaise - spentPaise) }
    /// Still to save before it's fully covered.
    var toGoPaise: Int { max(0, targetPaise - savedPaise) }
    /// How much of the target is saved, 0...1.
    var progress: Double {
        targetPaise > 0 ? min(1, max(0, Double(savedPaise) / Double(targetPaise))) : 0
    }
    var isFinished: Bool { finishedAt != nil }
    var isReached: Bool { targetPaise > 0 && savedPaise >= targetPaise }
    var hasSpends: Bool { spends.contains { $0.flow == .expense } }

    func isSpending(at now: Date = .now) -> Bool {
        !isFinished && (spendingUntil.map { $0 > now } ?? false)
    }
}

/// How fast your money grows: income less spending per day, over the last
/// 90 days or since your first payment. Payments spent from goals are left
/// out, since that money was put aside already.
struct GoalPace: Equatable {
    /// Paise a day; negative while spending outruns income.
    let perDay: Double
    /// Average spending a day, used to keep a month of it free.
    let spendingPerDay: Double
    let days: Int

    static let window = 90
    /// Less than a month says too little about payday to payday.
    static let minimumDays = 28

    /// Nil until there's a month of payments to go on.
    static func measure(_ entries: [LedgerEntry], now: Date = .now, calendar: Calendar = .current) -> GoalPace? {
        guard let first = entries.lazy.map(\.date).min() else { return nil }
        let windowStart = calendar.date(byAdding: .day, value: -window, to: now) ?? now
        let start = max(windowStart, first)
        let days = calendar.dateComponents([.day], from: start, to: now).day ?? 0
        guard days >= minimumDays else { return nil }
        var income = 0
        var spent = 0
        for entry in entries where entry.date >= start && entry.date <= now && entry.goal == nil {
            if entry.flow == .income { income += entry.amountPaise } else { spent += entry.amountPaise }
        }
        return GoalPace(
            perDay: Double(income - spent) / Double(days),
            spendingPerDay: Double(spent) / Double(days),
            days: days
        )
    }

    /// A month of your usual spending, kept free for bills before any of
    /// your money counts toward goals.
    var cushionPaise: Int { Int((spendingPerDay * 30).rounded()) }
}

/// When each goal will be covered if your money keeps growing as it has.
/// Free money (less a month of spending) counts first, shared out evenly;
/// after that the daily surplus is shared evenly between the goals still
/// saving. Setting money aside doesn't move these dates: only spending
/// and income do.
enum GoalForecast {
    /// Gives up past this many years.
    static let horizonDays = 365.0 * 30

    /// Arrival dates by goal; a goal is missing when it isn't in sight.
    /// `freePaise` is nil when no starting balance is set.
    static func arrivals(toGo: [UUID: Int], freePaise: Int?, pace: GoalPace?, now: Date = .now) -> [UUID: Date] {
        var remaining = toGo.filter { $0.value > 0 }.mapValues(Double.init)
        var result: [UUID: Date] = [:]
        let perDay = pace?.perDay ?? 0
        var elapsed = 0.0
        var pool = freePaise.map { Double($0 - (pace?.cushionPaise ?? 0)) } ?? 0

        if pool < 0 {
            // Spoken for already: catch up before anything counts.
            guard perDay > 0 else { return result }
            elapsed = -pool / perDay
            pool = 0
        }

        // Share out what you have now, smallest goals first so nothing
        // gets more than it needs.
        var waiting = remaining.count
        for (id, need) in remaining.sorted(by: { $0.value < $1.value }) {
            let give = min(need, pool / Double(waiting))
            pool -= give
            waiting -= 1
            remaining[id] = need - give
        }

        while true {
            for (id, need) in remaining where need < 1 {
                result[id] = now.addingTimeInterval(elapsed * 86_400)
                remaining[id] = nil
            }
            guard let smallest = remaining.values.min(), perDay > 0 else { break }
            let each = perDay / Double(remaining.count)
            let step = smallest / each
            elapsed += step
            guard elapsed <= horizonDays else { break }
            for id in remaining.keys { remaining[id]! -= each * step }
        }
        return result
    }
}

/// What the departure board says about a goal.
enum GoalBoard: Equatable {
    case finished(Date)
    case spending(until: Date)
    /// Everything's saved.
    case arrived
    /// Your free money covers what's left: you could finish it now.
    case boarding
    /// Due on this date. `lateDays` compares it with `arriveBy`: positive
    /// is delayed, negative early, nil when there's nothing to compare.
    case due(Date, lateDays: Int?)
    /// Under a month of payments: no pace yet.
    case learning
    /// Spending outruns income, so it isn't getting closer.
    case stalled

    static func status(of goal: Goal, arrival: Date?, hasPace: Bool, now: Date = .now, calendar: Calendar = .current) -> GoalBoard {
        if let finished = goal.finishedAt { return .finished(finished) }
        if goal.isSpending(at: now), let until = goal.spendingUntil { return .spending(until: until) }
        if goal.isReached { return .arrived }
        guard let arrival else { return hasPace ? .stalled : .learning }
        if arrival.timeIntervalSince(now) < 60 { return .boarding }
        // Days between the dates on the board, whatever the time of day.
        let late = goal.arriveBy.flatMap {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: arrival)).day
        }
        return .due(arrival, lateDays: late)
    }
}

/// The goals' side of the money: what's set aside, what's free, and the
/// changes you make by hand.
@MainActor
enum Goals {
    /// Goals not on the shelf, oldest first.
    static func active(in context: ModelContext) -> [Goal] {
        let all = (try? context.fetch(FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return all.filter { !$0.isFinished }
    }

    /// Kept out of your balance for goals still open.
    static func setAside(_ goals: [Goal]) -> Int {
        goals.filter { !$0.isFinished }.reduce(0) { $0 + $1.heldPaise }
    }

    /// Puts money in (positive) or takes it back out (negative).
    static func move(_ paise: Int, for goal: Goal, kind: GoalMoveKind = .manual, entry: LedgerEntry? = nil, at date: Date = .now, in context: ModelContext) {
        guard paise != 0 else { return }
        let move = GoalMove(amountPaise: paise, kind: kind, date: date)
        context.insert(move)
        move.goal = goal
        move.entry = entry
    }

    /// The goal new payments come out of right now, if any.
    static func spendingGoal(at date: Date = .now, in context: ModelContext) -> Goal? {
        active(in: context).filter { $0.isSpending(at: date) }.max { ($0.spendingUntil ?? .distantPast) < ($1.spendingUntil ?? .distantPast) }
    }

    /// New payments come out of `goal` until `until`; any other goal stops.
    static func startSpending(from goal: Goal, until: Date, in context: ModelContext) {
        for other in active(in: context) where other.uuid != goal.uuid && other.spendingUntil != nil {
            other.spendingUntil = nil
        }
        goal.spendingUntil = until
    }

    /// One goal at a time measures payments.
    static func setYardstick(_ goal: Goal, _ on: Bool, in context: ModelContext) {
        if on {
            for other in (try? context.fetch(FetchDescriptor<Goal>())) ?? [] where other.uuid != goal.uuid {
                other.isYardstick = false
            }
        }
        goal.isYardstick = on
    }

    /// One goal at a time takes the round-ups, so a payment is only ever
    /// rounded once.
    static func setRoundUp(_ goal: Goal, rupees: Int, at date: Date = .now, in context: ModelContext) {
        if rupees > 0 {
            for other in (try? context.fetch(FetchDescriptor<Goal>())) ?? [] where other.uuid != goal.uuid {
                other.roundUpRupees = 0
            }
            if goal.roundUpRupees == 0 { goal.roundUpSince = date }
        }
        goal.roundUpRupees = rupees
    }

    /// Onto the shelf. What's still set aside goes back to free money.
    static func finish(_ goal: Goal, at date: Date = .now) {
        goal.finishedAt = date
        goal.spendingUntil = nil
        goal.isYardstick = false
        goal.roundUpRupees = 0
        goal.sharePercent = 0
        goal.paydayPaise = 0
        goal.paydayPercent = 0
    }

    /// The day `goal` would be covered at your pace, with the goals
    /// you're saving for alongside it.
    static func forecast(_ goals: [Goal], entries: [LedgerEntry], balance: StartingBalance?, now: Date = .now) -> (pace: GoalPace?, arrivals: [UUID: Date]) {
        let pace = GoalPace.measure(entries, now: now)
        let saving = goals.filter { !$0.isFinished && !$0.isSpending(at: now) }
        let free = balance.map { $0.current(with: entries) - setAside(goals) }
        let toGo = Dictionary(uniqueKeysWithValues: saving.map { ($0.uuid, $0.toGoPaise) })
        return (pace, GoalForecast.arrivals(toGo: toGo, freePaise: free, pace: pace, now: now))
    }
}

/// Goals that fill themselves from your payments: a round-up of each one,
/// or a share of everything in one category. Only payments made since a
/// rule was turned on count.
@MainActor
enum GoalRules {
    /// Brings what `entry` set aside in line with the rules. Money set
    /// aside under a rule that's since been turned off stays put.
    static func sync(_ entry: LedgerEntry, in context: ModelContext) {
        let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        for goal in goals where !goal.isFinished {
            if goal.roundUpRupees > 0 {
                settle(.roundUp, for: goal, entry: entry, paise: roundUp(of: entry, for: goal), in: context)
            }
            if goal.sharePercent > 0, goal.shareCategoryID != nil {
                settle(.share, for: goal, entry: entry, paise: share(of: entry, for: goal), in: context)
            }
        }
    }

    /// ₹243 rounded up to ₹10 sets aside ₹7.
    static func roundUp(of entry: LedgerEntry, for goal: Goal) -> Int {
        guard counts(entry, for: goal, since: goal.roundUpSince), goal.roundUpRupees > 0 else { return 0 }
        let step = goal.roundUpRupees * 100
        let over = entry.amountPaise % step
        return over == 0 ? 0 : step - over
    }

    /// 10% of a ₹450 Food payment sets aside ₹45.
    static func share(of entry: LedgerEntry, for goal: Goal) -> Int {
        guard counts(entry, for: goal, since: goal.shareSince),
              let categoryID = goal.shareCategoryID, entry.category?.uuid == categoryID
        else { return 0 }
        return Int((Double(entry.amountPaise) * Double(goal.sharePercent) / 100).rounded())
    }

    /// Spending made since the rule started, and not from this goal itself.
    private static func counts(_ entry: LedgerEntry, for goal: Goal, since: Date?) -> Bool {
        guard entry.flow == .expense, let since, entry.date >= since else { return false }
        return entry.goal?.uuid != goal.uuid
    }

    private static func settle(_ kind: GoalMoveKind, for goal: Goal, entry: LedgerEntry, paise: Int, in context: ModelContext) {
        let existing = entry.goalMoves.first { $0.goal?.uuid == goal.uuid && $0.kind == kind }
        // Nothing past the target.
        let room = goal.toGoPaise + (existing?.amountPaise ?? 0)
        let amount = min(paise, room)
        if let existing {
            if amount > 0 {
                existing.amountPaise = amount
            } else {
                entry.goalMoves.removeAll { $0.uuid == existing.uuid }
                context.delete(existing)
            }
        } else if amount > 0 {
            Goals.move(amount, for: goal, kind: kind, entry: entry, at: entry.date, in: context)
        }
    }
}

/// When a big sum comes in, offer to set part of it aside: each goal says
/// how much it takes (a fixed amount or a percent), up to what it still needs.
@MainActor
enum Payday {
    static let thresholdKey = "paydayThresholdPaise"
    static let answeredKey = "paydayAnswered"
    static let defaultThreshold = 10_000_00
    /// Offered for this long after the money comes in.
    static let window: TimeInterval = 3 * 86_400

    static var thresholdPaise: Int {
        UserDefaults.standard.object(forKey: thresholdKey) as? Int ?? defaultThreshold
    }

    struct Part: Identifiable {
        var id: UUID { goal.uuid }
        let goal: Goal
        let paise: Int
    }

    /// What each goal would take of `entry`, never more than came in.
    static func plan(for entry: LedgerEntry, goals: [Goal]) -> [Part] {
        guard entry.flow == .income else { return [] }
        var left = entry.amountPaise
        var parts: [Part] = []
        for goal in goals where !goal.isFinished && goal.toGoPaise > 0 {
            let asked = goal.paydayPaise > 0
                ? goal.paydayPaise
                : Int((Double(entry.amountPaise) * Double(goal.paydayPercent) / 100).rounded())
            let paise = min(asked, goal.toGoPaise, left)
            guard paise > 0 else { continue }
            parts.append(Part(goal: goal, paise: paise))
            left -= paise
        }
        return parts
    }

    /// Big enough, recent, and not answered yet.
    static func isOpen(_ entry: LedgerEntry, now: Date = .now) -> Bool {
        entry.flow == .income
            && entry.amountPaise >= thresholdPaise
            && now.timeIntervalSince(entry.date) < window
            && !answered.contains(entry.uuid.uuidString)
            && !entry.goalMoves.contains { $0.kind == .payday }
    }

    /// The latest money in still waiting for an answer, and its plan.
    static func pending(entries: [LedgerEntry], goals: [Goal], now: Date = .now) -> (entry: LedgerEntry, parts: [Part])? {
        for entry in entries.sorted(by: { $0.date > $1.date }) where entry.flow == .income && isOpen(entry, now: now) {
            let parts = plan(for: entry, goals: goals)
            if !parts.isEmpty { return (entry, parts) }
        }
        return nil
    }

    /// Sets the plan aside and returns the total.
    @discardableResult
    static func accept(_ entry: LedgerEntry, in context: ModelContext) -> Int {
        guard !entry.goalMoves.contains(where: { $0.kind == .payday }) else { return 0 }
        let parts = plan(for: entry, goals: Goals.active(in: context))
        for part in parts {
            Goals.move(part.paise, for: part.goal, kind: .payday, entry: entry, in: context)
        }
        markAnswered(entry)
        try? context.save()
        return parts.reduce(0) { $0 + $1.paise }
    }

    static func decline(_ entry: LedgerEntry) {
        markAnswered(entry)
    }

    private static var answered: [String] {
        UserDefaults.standard.stringArray(forKey: answeredKey) ?? []
    }

    private static func markAnswered(_ entry: LedgerEntry) {
        var list = answered
        guard !list.contains(entry.uuid.uuidString) else { return }
        list.append(entry.uuid.uuidString)
        UserDefaults.standard.set(Array(list.suffix(100)), forKey: answeredKey)
    }
}

/// Puts a payment in terms of a goal: "That's 2 days of saving for Goa".
@MainActor
enum Yardstick {
    static func line(for entry: LedgerEntry, in context: ModelContext, now: Date = .now) -> String? {
        if let goal = entry.goal, entry.flow == .expense {
            return "From \(goal.name) · \(Rupees.format(paise: goal.heldPaise)) left"
        }
        guard entry.flow == .expense else { return nil }
        let goals = Goals.active(in: context)
        guard let goal = goals.first(where: \.isYardstick) else { return nil }
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        let saving = goals.filter { !$0.isSpending(at: now) && !$0.isReached }.count
        return line(paise: entry.amountPaise, goal: goal, pace: GoalPace.measure(entries, now: now), sharedBy: max(1, saving))
    }

    /// Days (or hours) of this goal's share of your daily surplus; a
    /// percent of its target while there's no pace to go on.
    static func line(paise: Int, goal: Goal, pace: GoalPace?, sharedBy: Int) -> String? {
        if let pace, pace.perDay > 0 {
            let days = Double(paise) / (pace.perDay / Double(sharedBy))
            if days >= 1.5 { return "That's \(Int(days.rounded())) days of saving for \(goal.name)" }
            if days >= 0.75 { return "That's a day of saving for \(goal.name)" }
            let hours = Int((days * 24).rounded())
            if hours >= 1 { return "That's \(hours == 1 ? "an hour" : "\(hours) hours") of saving for \(goal.name)" }
            return nil
        }
        guard goal.targetPaise > 0 else { return nil }
        let percent = Int((Double(paise) / Double(goal.targetPaise) * 100).rounded())
        return percent >= 1 ? "That's \(percent)% of \(goal.name)" : nil
    }

    /// "Goa trip is 2 days later": how much further off spending this
    /// pushes the goal; a percent of it while there's no pace.
    static func delay(paise: Int, goal: Goal, pace: GoalPace?, sharedBy: Int) -> String? {
        if let pace, pace.perDay > 0 {
            let days = Double(paise) / (pace.perDay / Double(sharedBy))
            if days >= 1.5 { return "\(goal.name) is \(Int(days.rounded())) days later" }
            if days >= 0.75 { return "\(goal.name) is a day later" }
            let hours = max(1, Int((days * 24).rounded()))
            return "\(goal.name) is \(hours == 1 ? "an hour" : "\(hours) hours") later"
        }
        guard goal.targetPaise > 0 else { return nil }
        let percent = max(1, Int((Double(paise) / Double(goal.targetPaise) * 100).rounded()))
        return "That's \(percent)% of \(goal.name)"
    }
}
