import Foundation

/// The money you started with, as of a date. Entries from that moment on
/// move the balance; earlier ones are already part of it.
struct StartingBalance: Equatable {
    var paise: Int
    var asOf: Date

    /// The running balance: start + income − spending since `asOf`.
    func current(with entries: [LedgerEntry]) -> Int {
        entries.reduce(paise) { total, entry in
            guard entry.date >= asOf else { return total }
            return entry.flow == .income ? total + entry.amountPaise : total - entry.amountPaise
        }
    }
}

/// Where the starting balance is kept (on this iPhone, in its backups).
enum BalanceStore {
    static let paiseKey = "startingBalancePaise"
    static let dateKey = "startingBalanceAsOf"

    static var defaults: UserDefaults { .standard }

    static func load(from defaults: UserDefaults = defaults) -> StartingBalance? {
        let seconds = defaults.double(forKey: dateKey)
        guard seconds > 0 else { return nil }
        return StartingBalance(paise: defaults.integer(forKey: paiseKey), asOf: Date(timeIntervalSince1970: seconds))
    }

    static func save(_ balance: StartingBalance?, to defaults: UserDefaults = defaults) {
        if let balance {
            defaults.set(balance.paise, forKey: paiseKey)
            defaults.set(balance.asOf.timeIntervalSince1970, forKey: dateKey)
        } else {
            defaults.removeObject(forKey: paiseKey)
            defaults.removeObject(forKey: dateKey)
        }
    }

    /// Reads "-1,250.50" or "50000" as paise; zero and negatives allowed.
    static func paise(fromTyped text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        var paise = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &paise, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
