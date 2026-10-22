#if DEBUG
import Foundation
import OSLog
import SwiftData
import UIKit

let debugLog = Logger(subsystem: "tme.debug", category: "hooks")

/// Launch arguments for tests and screenshots:
///   -seedDemo              fill the store with a month of sample entries
///   -seedLots              a heavy month: 300 payments, for scroll performance
///   -seedGoals             three months of payments, a balance, and goals
///   -simulateSMS <base64>  handle a bank SMS as the automation would
@MainActor
enum DebugHooks {
    static func run(in context: ModelContext) {
        debugLog.notice("run: args=\(LaunchOptions.arguments.dropFirst().joined(separator: " ").prefix(80), privacy: .public) uiTesting=\(LaunchOptions.isUITesting)")
        if LaunchOptions.arguments.contains("-seedLots") {
            DemoData.insertLots(into: context)
        }
        if LaunchOptions.arguments.contains("-seedGoals") {
            DemoData.insertGoals(into: context)
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

    /// Three months of salary, rent and everyday spending, a starting
    /// balance, three goals under way, one on the shelf, and today's
    /// salary still waiting to feed them.
    static func insertGoals(into context: ModelContext) {
        let categories = (try? context.fetch(FetchDescriptor<LedgerCategory>())) ?? []
        func category(_ name: String) -> LedgerCategory? { categories.first { $0.name == name } }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ daysAgo: Int, _ hour: Int = 13) -> Date {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            return min(.now, calendar.date(bySettingHour: hour, minute: 10, second: 0, of: date) ?? date)
        }

        BalanceStore.save(StartingBalance(paise: 40_000_00, asOf: day(95, 0)))
        var salaries: [LedgerEntry] = []
        for daysAgo in [85, 55, 25] {
            let salary = LedgerEntry(amountPaise: 85_000_00, flow: .income, date: day(daysAgo, 10), merchant: "ACME PVT LTD", category: category("Salary"), source: .sms)
            context.insert(salary)
            salaries.append(salary)
            context.insert(LedgerEntry(amountPaise: 22_000_00, flow: .expense, date: day(daysAgo - 1, 9), note: "Rent", category: category("Rent")))
        }
        let everyday: [(String, String, Int)] = [
            ("SWIGGY", "Food", 340_00), ("BIGBASKET", "Groceries", 1_180_00), ("UBER", "Transport", 210_00),
            ("ZOMATO", "Food", 410_00), ("AMAZON", "Shopping", 1_650_00), ("BLUE TOKAI", "Food", 280_00),
        ]
        var foodOrders: [LedgerEntry] = []
        for daysAgo in 1...92 {
            let (merchant, name, paise) = everyday[daysAgo % everyday.count]
            let entry = LedgerEntry(amountPaise: paise + (daysAgo * 37) % 120 * 100 + 7_00, flow: .expense, date: day(daysAgo, 12 + daysAgo % 8), merchant: merchant, category: category(name), source: .sms)
            context.insert(entry)
            if name == "Food" { foodOrders.append(entry) }
        }

        let goa = Goal(name: "Goa trip", targetPaise: 60_000_00, symbol: "beach.umbrella", colorSlot: 1)
        goa.photo = DemoPhotos.beach()
        goa.createdAt = day(80)
        goa.arriveBy = calendar.date(byAdding: .day, value: 14, to: today)
        goa.roundUpRupees = 10
        goa.roundUpSince = day(80)
        goa.paydayPercent = 10
        goa.isYardstick = true
        let camera = Goal(name: "New camera", targetPaise: 85_000_00, symbol: "camera", colorSlot: 6)
        camera.createdAt = day(60)
        camera.arriveBy = calendar.date(byAdding: .day, value: 45, to: today)
        camera.arriveByIsEstimate = true
        camera.sharePercent = 10
        camera.shareCategoryID = category("Food")?.uuid
        camera.shareSince = day(60)
        camera.paydayPaise = 5_000_00
        let rainyDay = Goal(name: "Rainy-day fund", targetPaise: 1_00_000_00, symbol: "umbrella", colorSlot: 5)
        rainyDay.createdAt = day(90)
        let ladakh = Goal(name: "Ladakh ride", targetPaise: 45_000_00, symbol: "mountain.2", colorSlot: 0)
        ladakh.photo = DemoPhotos.mountains()
        ladakh.createdAt = day(260)
        ladakh.finishedAt = day(30)
        for goal in [goa, camera, rainyDay, ladakh] { context.insert(goal) }

        Goals.move(10_000_00, for: goa, at: day(78), in: context)
        Goals.move(20_000_00, for: camera, at: day(58), in: context)
        Goals.move(1_00_000_00, for: rainyDay, at: day(88), in: context)
        Goals.move(45_000_00, for: ladakh, at: day(200), in: context)
        for salary in salaries {
            Goals.move(8_500_00, for: goa, kind: .payday, entry: salary, at: salary.date, in: context)
        }
        try? context.save()
        let all = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        for entry in all { GoalRules.sync(entry, in: context) }
        let ladakhHotel = LedgerEntry(amountPaise: 44_200_00, flow: .expense, date: day(32), merchant: "LEH HOMESTAYS", category: category("Travel") ?? category("Shopping"), source: .sms)
        context.insert(ladakhHotel)
        ladakhHotel.goal = ladakh

        if let salary = category("Salary") { Tagging.remember(salary, for: "ACME PVT LTD", in: context) }
        category("Food")?.weeklyLimitPaise = 500_00
        category("Food")?.dailyLimitPaise = 400_00
        category("Groceries")?.monthlyLimitPaise = 6_000_00
        category("Shopping")?.monthlyLimitPaise = 10_000_00
        // Today's salary, not yet fed to the goals.
        context.insert(LedgerEntry(amountPaise: 85_000_00, flow: .income, date: day(0, 10), merchant: "ACME PVT LTD", category: category("Salary"), source: .sms))
        try? context.save()
    }
}

/// Drawn stand-ins for goal photos, so screenshots don't need a photo library.
@MainActor
enum DemoPhotos {
    private static func draw(_ body: (CGContext, CGSize) -> Void) -> Data? {
        let size = CGSize(width: 1200, height: 800)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { body($0.cgContext, size) }
        return image.jpegData(compressionQuality: 0.85)
    }

    private static func gradient(_ context: CGContext, _ colors: [UInt32], from: CGPoint, to: CGPoint) {
        let cgColors = colors.map { UIColor(hex: $0).cgColor } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) else { return }
        context.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// A sunset over the sea, a palm on the left.
    static func beach() -> Data? {
        draw { context, size in
            let horizon = size.height * 0.6
            context.saveGState()
            context.clip(to: CGRect(x: 0, y: 0, width: size.width, height: horizon))
            gradient(context, [0x141e46, 0x6a3093, 0xf0705a, 0xffc96b], from: .zero, to: CGPoint(x: 0, y: horizon))
            context.restoreGState()
            context.setFillColor(UIColor(hex: 0xfff1c1).cgColor)
            context.fillEllipse(in: CGRect(x: size.width * 0.58, y: horizon - 110, width: 220, height: 220))
            context.saveGState()
            context.clip(to: CGRect(x: 0, y: horizon, width: size.width, height: size.height * 0.25))
            gradient(context, [0x3a4d7a, 0x13284a], from: CGPoint(x: 0, y: horizon), to: CGPoint(x: 0, y: size.height * 0.85))
            context.restoreGState()
            context.setFillColor(UIColor(hex: 0xffd889).withAlphaComponent(0.7).cgColor)
            for row in 0..<9 {
                let y = horizon + 8 + CGFloat(row) * 20
                let width = 200 - CGFloat(row) * 14
                context.fill(CGRect(x: size.width * 0.58 + 110 - width / 2, y: y, width: width, height: 4))
            }
            context.saveGState()
            context.clip(to: CGRect(x: 0, y: size.height * 0.85, width: size.width, height: size.height * 0.15))
            gradient(context, [0xc99a6b, 0x7a5a3e], from: CGPoint(x: 0, y: size.height * 0.85), to: CGPoint(x: 0, y: size.height))
            context.restoreGState()
            // A palm: a leaning trunk and a crown of fronds.
            context.setFillColor(UIColor(hex: 0x120a12).cgColor)
            context.setStrokeColor(UIColor(hex: 0x120a12).cgColor)
            context.setLineWidth(26)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: 150, y: size.height))
            context.addQuadCurve(to: CGPoint(x: 250, y: 260), control: CGPoint(x: 140, y: 520))
            context.strokePath()
            let crown = CGPoint(x: 250, y: 260)
            for angle in stride(from: -170.0, through: 10.0, by: 30.0) {
                let radians = angle * .pi / 180
                let tip = CGPoint(x: crown.x + cos(radians) * 230, y: crown.y + sin(radians) * 120 + 90)
                context.setLineWidth(16)
                context.move(to: crown)
                context.addQuadCurve(to: tip, control: CGPoint(x: crown.x + cos(radians) * 120, y: crown.y + sin(radians) * 140))
                context.strokePath()
            }
        }
    }

    /// Snowy peaks over a high desert road.
    static func mountains() -> Data? {
        draw { context, size in
            gradient(context, [0x3d7cc9, 0x9cc4ec, 0xe6eff7], from: .zero, to: CGPoint(x: 0, y: size.height * 0.7))
            func ridge(_ points: [CGPoint], _ color: UInt32) {
                context.setFillColor(UIColor(hex: color).cgColor)
                context.move(to: CGPoint(x: 0, y: size.height))
                for point in points { context.addLine(to: point) }
                context.addLine(to: CGPoint(x: size.width, y: size.height))
                context.closePath()
                context.fillPath()
            }
            ridge([CGPoint(x: 0, y: 420), CGPoint(x: 260, y: 210), CGPoint(x: 470, y: 380), CGPoint(x: 720, y: 160), CGPoint(x: 1000, y: 360), CGPoint(x: 1200, y: 250)], 0x7f8fa8)
            context.setFillColor(UIColor.white.cgColor)
            for (x, y) in [(260.0, 210.0), (720.0, 160.0), (1200.0, 250.0)] {
                context.move(to: CGPoint(x: x, y: y))
                context.addLine(to: CGPoint(x: x - 70, y: y + 70))
                context.addLine(to: CGPoint(x: x + 70, y: y + 70))
                context.closePath()
                context.fillPath()
            }
            ridge([CGPoint(x: 0, y: 560), CGPoint(x: 300, y: 450), CGPoint(x: 640, y: 540), CGPoint(x: 900, y: 470), CGPoint(x: 1200, y: 560)], 0xa47b55)
            ridge([CGPoint(x: 0, y: 660), CGPoint(x: 1200, y: 640)], 0x5b4636)
            context.setFillColor(UIColor(hex: 0x2c2420).cgColor)
            context.move(to: CGPoint(x: 560, y: 650))
            context.addLine(to: CGPoint(x: 640, y: 650))
            context.addLine(to: CGPoint(x: 900, y: size.height))
            context.addLine(to: CGPoint(x: 300, y: size.height))
            context.closePath()
            context.fillPath()
        }
    }
}
#endif
