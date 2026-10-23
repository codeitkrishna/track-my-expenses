import Foundation
import SwiftData
import TMECore
import UIKit

/// A UPI app TME can hand a scanned payment to. Each opens on its own
/// amount screen for that UPI ID, or on the amount the shop fixed.
struct UPIApp: Identifiable, Equatable, Sendable {
    /// Its URL scheme, which iOS asks about (`LSApplicationQueriesSchemes`).
    let id: String
    let name: String
    /// What goes before the code's parameters.
    let prefix: String
    /// A letter or two in the app's colour, standing in for its icon.
    let monogram: String
    let colour: UInt32

    static let known: [UPIApp] = [
        UPIApp(id: "phonepe", name: "PhonePe", prefix: "phonepe://pay?", monogram: "Pe", colour: 0x5F259F),
        UPIApp(id: "tez", name: "Google Pay", prefix: "tez://upi/pay?", monogram: "G", colour: 0x1A73E8),
        UPIApp(id: "paytmmp", name: "Paytm", prefix: "paytmmp://pay?", monogram: "Pt", colour: 0x00A2E1),
        UPIApp(id: "credpay", name: "CRED", prefix: "credpay://upi/pay?", monogram: "C", colour: 0x3A3A3C),
        UPIApp(id: "bhim", name: "BHIM", prefix: "bhim://pay?", monogram: "B", colour: 0xE8711B),
    ]

    /// Whichever app iOS gives plain `upi://` links to: one not listed
    /// above, such as a bank's own app.
    static let other = UPIApp(id: "upi", name: "Another UPI app", prefix: "upi://pay?", monogram: "", colour: 0x3A3A3C)
}

/// A payment handed to a UPI app, logged when you come back to TME.
struct PendingPayment: Codable, Equatable, Identifiable {
    var id = UUID()
    let payee: UPIPayee
    let appName: String
    let startedAt: Date
    /// Typed in TME before paying; the app showed it as the remark.
    var note: String?
    /// TME went into the background after handing it over.
    var left = false
}

/// Scan a UPI code, pay with any UPI app, and log it on the way back.
/// iOS doesn't let payment apps report back, so TME remembers what it
/// handed over and asks when you return, with the amount filled in from
/// the code or from the bank's SMS. Either way round, a payment and its
/// SMS are logged once.
@MainActor
enum ScanPay {
    private static let pendingKey = "pendingUPIPayment"
    private static let lastAppKey = "lastUPIApp"
    /// How long after leaving for the app TME still asks about the payment.
    static let window: TimeInterval = 30 * 60

    // MARK: Apps

    /// The UPI apps on this iPhone, the one used last first. "Another UPI
    /// app" comes last, when some app takes plain UPI links.
    static func installedApps() -> [UPIApp] {
        var apps = UPIApp.known.filter(isInstalled)
        if let last = UserDefaults.standard.string(forKey: lastAppKey), let index = apps.firstIndex(where: { $0.id == last }) {
            apps.insert(apps.remove(at: index), at: 0)
        }
        if isInstalled(UPIApp.other) { apps.append(UPIApp.other) }
        return apps
    }

    private static func isInstalled(_ app: UPIApp) -> Bool {
        #if DEBUG
        if let faked = LaunchOptions.value(after: "-upiApps") {
            return faked.split(separator: ",").contains { $0 == app.id }
        }
        #endif
        guard let url = URL(string: "\(app.id)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    // MARK: Handing over

    /// Remembers the payment, then opens it in `app`. False if iOS couldn't.
    static func pay(_ payee: UPIPayee, with app: UPIApp, note: String? = nil) async -> Bool {
        guard let url = payee.link(prefix: app.prefix, note: note) else { return false }
        begin(payee, appName: app == .other ? "a UPI app" : app.name, note: note)
        UserDefaults.standard.set(app.id, forKey: lastAppKey)
        #if DEBUG
        // Tests pretend the apps are there; going to the home screen stands in
        // for paying, and the bank's SMS can arrive meanwhile.
        if LaunchOptions.value(after: "-upiApps") != nil {
            if let encoded = LaunchOptions.value(after: "-smsWhilePaying"),
               let data = Data(base64Encoded: encoded), let message = String(data: data, encoding: .utf8) {
                _ = try? SMSIngest.handle(message, in: DataStore.shared.context)
            }
            return true
        }
        #endif
        let opened = await UIApplication.shared.open(url)
        if !opened { pending = nil }
        return opened
    }

    /// Remembers a payment being handed to an app, replacing any earlier one.
    static func begin(_ payee: UPIPayee, appName: String, note: String? = nil, at date: Date = .now) {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        pending = PendingPayment(payee: payee, appName: appName, startedAt: date, note: trimmed.isEmpty ? nil : trimmed)
    }

    /// TME went into the background: the payment app is open.
    static func noteLeft() {
        guard var payment = pending, !payment.left else { return }
        payment.left = true
        pending = payment
    }

    /// The payment to ask about on the way back: handed over and left for
    /// within the last half hour.
    static func due(at now: Date = .now) -> PendingPayment? {
        guard let payment = pending else { return nil }
        guard now.timeIntervalSince(payment.startedAt) < window else {
            pending = nil
            return nil
        }
        return payment.left ? payment : nil
    }

    static func clear() {
        pending = nil
    }

    private(set) static var pending: PendingPayment? {
        get {
            UserDefaults.standard.data(forKey: pendingKey).flatMap { try? JSONDecoder().decode(PendingPayment.self, from: $0) }
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: pendingKey)
            } else {
                UserDefaults.standard.removeObject(forKey: pendingKey)
            }
        }
    }

    // MARK: Matching the bank's SMS

    /// The bank's SMS for this payment, if it was logged first: the earliest
    /// payment out since you left for the app, of `amountPaise` when that's
    /// known, not already tied to a scan.
    static func smsEntry(for payment: PendingPayment, amountPaise: Int?, in context: ModelContext) -> LedgerEntry? {
        let smsRaw = EntrySource.sms.rawValue
        let expense = Flow.expense.rawValue
        let start = payment.startedAt.addingTimeInterval(-60)
        let descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate { $0.sourceRaw == smsRaw && $0.flowRaw == expense && $0.date >= start && $0.upiID == nil },
            sortBy: [SortDescriptor(\.date)]
        )
        let candidates = (try? context.fetch(descriptor)) ?? []
        return candidates.first { amountPaise == nil || $0.amountPaise == amountPaise }
    }

    /// A payment logged from a scan and still waiting for its SMS: the same
    /// amount, out, in the half hour before the SMS arrived.
    static func scannedEntry(amountPaise: Int, near date: Date, in context: ModelContext) -> LedgerEntry? {
        let scanRaw = EntrySource.scan.rawValue
        let expense = Flow.expense.rawValue
        let start = date.addingTimeInterval(-window)
        let end = date.addingTimeInterval(5 * 60)
        var descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate {
                $0.sourceRaw == scanRaw && $0.flowRaw == expense && $0.amountPaise == amountPaise
                    && $0.reference == nil && $0.rawMessage == nil && $0.date >= start && $0.date <= end
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
