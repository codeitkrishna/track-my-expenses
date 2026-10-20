#if DEBUG
import Foundation
import OSLog
import SwiftData

let debugLog = Logger(subsystem: "tme.debug", category: "hooks")

/// Launch arguments for tests and screenshots:
///   -seedDemo              fill the store with a month of sample entries
///   -seedLots              a heavy month: 300 payments, for scroll performance
///   -simulateSMS <base64>  handle a bank SMS as the automation would
@MainActor
enum DebugHooks {
    static func run(in context: ModelContext) {
        debugLog.notice("run: args=\(LaunchOptions.arguments.dropFirst().joined(separator: " ").prefix(80), privacy: .public) uiTesting=\(LaunchOptions.isUITesting)")
        if LaunchOptions.arguments.contains("-seedLots") {
            DemoData.insertLots(into: context)
        }
        if LaunchOptions.arguments.contains("-seedDemo") {
            DemoData.insert(into: context)
            let count = (try? context.fetchCount(FetchDescriptor<LedgerEntry>())) ?? -1
            debugLog.notice("seeded: entries=\(count)")
        }
        // Base64, because UI-test launch arguments lose the line breaks bank SMS rely on.
        if let encoded = LaunchOptions.value(after: "-simulateSMS"),
           let data = Data(base64Encoded: encoded),
           let message = String(data: data, encoding: .utf8) {
            if let outcome = try? SMSIngest.handle(message, in: context) {
                Task { await TagPrompt.follow(outcome, in: context) }
            }
        }
    }
}

@MainActor
enum DemoData {
    /// Ten payments a day for the month so far, spread over every expense category.
    static func insertLots(into context: ModelContext) {
        let categories = ((try? context.fetch(FetchDescriptor<LedgerCategory>())) ?? []).filter { $0.flow == .expense }
        let merchants = ["SWIGGY", "ZOMATO", "UBER", "OLA", "BIGBASKET", "AMAZON", "FLIPKART", "BESCOM", "APOLLO PHARMACY", "STARBUCKS"]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days = max(calendar.component(.day, from: today), 1)
        for dayIndex in 0..<days {
            let date = calendar.date(byAdding: .day, value: -dayIndex, to: today) ?? today
            for payment in 0..<10 {
                let time = calendar.date(bySettingHour: 8 + payment, minute: 5 * payment, second: 0, of: date) ?? date
                context.insert(LedgerEntry(
                    amountPaise: (60 + (dayIndex * 37 + payment * 53) % 900) * 100,
                    flow: .expense,
                    date: min(time, .now),
                    merchant: merchants[(dayIndex + payment) % merchants.count],
                    category: categories.isEmpty ? nil : categories[(dayIndex + payment) % categories.count],
                    source: .sms
                ))
            }
        }
        try? context.save()
    }

    static func insert(into context: ModelContext) {
        let categories = (try? context.fetch(FetchDescriptor<LedgerCategory>())) ?? []
        func category(_ name: String) -> LedgerCategory? { categories.first { $0.name == name } }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ daysAgo: Int, _ hour: Int) -> Date {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: 15, second: 0, of: date) ?? date
        }

        let samples: [(Int, Int, Int, Flow, String?, String, String)] = [
            (0, 13, 245_00, .expense, "SWIGGY", "Food", ""),
            (0, 9, 60_00, .expense, nil, "Food", "Chai and samosa"),
            (1, 20, 1_240_00, .expense, "BIGBASKET", "Groceries", ""),
            (1, 9, 180_00, .expense, "UBER", "Transport", ""),
            (2, 21, 499_00, .expense, "NETFLIX", "Entertainment", ""),
            (3, 13, 320_00, .expense, "ZOMATO", "Food", ""),
            (4, 18, 2_150_00, .expense, "AMAZON", "Shopping", ""),
            (5, 10, 1_830_00, .expense, "BESCOM", "Bills", ""),
            (6, 9, 210_00, .expense, "UBER", "Transport", ""),
            (7, 14, 650_00, .expense, "APOLLO PHARMACY", "Health", ""),
            (8, 12, 18_000_00, .expense, nil, "Rent", "October rent"),
            (9, 19, 380_00, .expense, "SWIGGY", "Food", ""),
            (10, 11, 50_000_00, .income, "ACME PVT LTD", "Salary", ""),
            (12, 20, 899_00, .expense, "BIGBASKET", "Groceries", ""),
            (13, 8, 140_00, .expense, "UBER", "Transport", ""),
            (15, 21, 1_199_00, .income, "AMAZON", "Refund", ""),
        ]
        for (daysAgo, hour, paise, flow, merchant, categoryName, note) in samples {
            context.insert(LedgerEntry(
                amountPaise: paise,
                flow: flow,
                date: day(daysAgo, hour),
                note: note,
                merchant: merchant,
                category: category(categoryName),
                source: merchant == nil ? .manual : .sms
            ))
        }
        // Two fresh alerts still waiting for a category.
        context.insert(LedgerEntry(amountPaise: 120_00, flow: .expense, date: day(0, 17), merchant: "RAPIDO", source: .sms))
        context.insert(LedgerEntry(amountPaise: 2_000_00, flow: .income, date: day(0, 11), merchant: "UPWORK", source: .sms))
        try? context.save()
    }
}
#endif
