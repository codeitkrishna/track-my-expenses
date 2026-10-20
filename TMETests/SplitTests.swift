import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import TME

@MainActor
struct SplitTests {
    let store = DataStore(inMemory: true)
    var context: ModelContext { store.context }

    private func draft(_ names: [String], mode: SplitMode = .equal, includesMe: Bool = true) -> SplitDraft {
        var draft = SplitDraft()
        names.forEach { draft.add($0) }
        draft.mode = mode
        draft.includesMe = includesMe
        return draft
    }

    @Test func equalSplitIncludesYouAndKeepsOddPaise() {
        let parts = draft(["Prakhar", "Riya"]).parts(total: 100_00)
        #expect(parts == SplitDraft.Parts(friends: [33_33, 33_33], mine: 33_34))
    }

    @Test func equalSplitWithoutYouCoversEverything() {
        let parts = draft(["Prakhar", "Riya", "Aman"], includesMe: false).parts(total: 100_00)
        #expect(parts?.friends.reduce(0, +) == 100_00)
        #expect(parts?.mine == 0)
    }

    @Test func addingTheSameFriendTwiceKeepsOne() {
        var split = draft(["Prakhar"])
        split.add("prakhar ")
        #expect(split.friends.count == 1)
    }

    @Test func amountsLeaveTheRestToYou() {
        var split = draft(["Prakhar", "Riya"], mode: .amounts)
        split.friends[0].amountText = "300"
        split.friends[1].amountText = "250.50"
        #expect(split.parts(total: 900_00) == SplitDraft.Parts(friends: [300_00, 250_50], mine: 349_50))

        split.friends[1].amountText = "700"
        #expect(split.parts(total: 900_00) == nil, "More than the payment")
        #expect(split.unassigned(total: 900_00) == -100_00)
    }

    @Test func amountsWithoutYouMustCoverThePayment() {
        var split = draft(["Prakhar"], mode: .amounts, includesMe: false)
        split.friends[0].amountText = "500"
        #expect(split.parts(total: 900_00) == nil)
        #expect(split.unassigned(total: 900_00) == 400_00)
        split.friends[0].amountText = "900"
        #expect(split.parts(total: 900_00) == SplitDraft.Parts(friends: [900_00], mine: 0))
    }

    @Test func percentagesSplitTheTotal() {
        var split = draft(["Prakhar", "Riya"], mode: .percent)
        split.friends[0].percentText = "50"
        split.friends[1].percentText = "25"
        #expect(split.parts(total: 1_000_00) == SplitDraft.Parts(friends: [500_00, 250_00], mine: 250_00))
        split.friends[1].percentText = "60"
        #expect(split.parts(total: 1_000_00) == nil, "Over 100%")
    }

    @Test func savingASplitTracksWhatFriendsOwe() throws {
        let dinner = LedgerEntry(amountPaise: 900_00, flow: .expense, date: .now.addingTimeInterval(-86_400), note: "Dinner")
        let movie = LedgerEntry(amountPaise: 700_00, flow: .expense, date: .now, note: "Movie")
        context.insert(dinner)
        context.insert(movie)
        Splits.apply(draft(["Prakhar", "Riya"]), to: dinner, in: context)
        Splits.apply(draft(["prakhar"], includesMe: true), to: movie, in: context)
        try context.save()

        let friends = try context.fetch(FetchDescriptor<Friend>())
        #expect(friends.count == 2, "The same friend, however it's typed")
        let prakhar = try #require(friends.first { $0.name == "Prakhar" })
        #expect(prakhar.owedPaise == 300_00 + 350_00)
        #expect(prakhar.openShares.map { $0.entry?.note } == ["Movie", "Dinner"], "Newest payment first")
        #expect(dinner.myPartPaise == 300_00)
        #expect(SplitDraft(entry: dinner).friends.map(\.name) == ["Prakhar", "Riya"])
    }

    @Test func payingBackOneOrAll() throws {
        let dinner = LedgerEntry(amountPaise: 900_00, flow: .expense, note: "Dinner")
        let cab = LedgerEntry(amountPaise: 400_00, flow: .expense, note: "Cab")
        context.insert(dinner)
        context.insert(cab)
        Splits.apply(draft(["Prakhar"]), to: dinner, in: context)
        Splits.apply(draft(["Prakhar"]), to: cab, in: context)
        let prakhar = try #require(try context.fetch(FetchDescriptor<Friend>()).first)
        #expect(prakhar.owedPaise == 450_00 + 200_00)

        let cabShare = try #require(prakhar.shares.first { $0.entry?.note == "Cab" })
        cabShare.settled = true
        #expect(prakhar.owedPaise == 450_00)

        Splits.settle(prakhar)
        #expect(prakhar.owedPaise == 0)
        let allPaid = prakhar.shares.allSatisfy(\.settled)
        #expect(allPaid)
    }

    @Test func resavingKeepsWhatWasPaidBack() throws {
        let dinner = LedgerEntry(amountPaise: 900_00, flow: .expense)
        context.insert(dinner)
        Splits.apply(draft(["Prakhar", "Riya"]), to: dinner, in: context)
        let prakhar = try #require(try context.fetch(FetchDescriptor<Friend>()).first { $0.name == "Prakhar" })
        Splits.settle(prakhar)

        // Saving the payment again with the same split leaves Prakhar paid up.
        Splits.apply(SplitDraft(entry: dinner), to: dinner, in: context)
        #expect(prakhar.owedPaise == 0)
        #expect(dinner.shares.count == 2)
    }

    @Test func lendingPutsEverythingOnTheFriend() throws {
        let loan = LedgerEntry(amountPaise: 2_000_00, flow: .expense, merchant: "Prakhar")
        context.insert(loan)
        Splits.apply(draft(["Prakhar"], includesMe: false), to: loan, in: context)
        let prakhar = try #require(try context.fetch(FetchDescriptor<Friend>()).first)
        #expect(prakhar.owedPaise == 2_000_00)
        #expect(loan.myPartPaise == 0)
    }

    @Test func sharedPictureRenders() throws {
        let food = try #require(try context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.name == "Food" })
        let transport = try #require(try context.fetch(FetchDescriptor<LedgerCategory>()).first { $0.name == "Transport" })
        let dinner = LedgerEntry(amountPaise: 1_800_00, flow: .expense, date: .now.addingTimeInterval(-86_400), note: "Team dinner", merchant: "Toit", category: food)
        let cab = LedgerEntry(amountPaise: 640_00, flow: .expense, merchant: "Uber", category: transport)
        #expect(OwedCard.details(of: dinner) == "Food · Team dinner")
        #expect(OwedCard.details(of: cab) == "Transport")
        context.insert(dinner)
        context.insert(cab)
        Splits.apply(draft(["Prakhar", "Riya"]), to: dinner, in: context)
        Splits.apply(draft(["Prakhar"]), to: cab, in: context)
        let prakhar = try #require(try context.fetch(FetchDescriptor<Friend>()).first { $0.name == "Prakhar" })

        let renderer = ImageRenderer(content: OwedCard(name: prakhar.name, owed: prakhar.owedPaise, shares: prakhar.openShares))
        renderer.scale = 3
        let image = try #require(renderer.uiImage)
        #expect(image.size.width == 390)
        #expect(image.size.height > 300)
        if let directory = ProcessInfo.processInfo.environment["TME_SHOTS_DIR"], let png = image.pngData() {
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("26-share-card.png"))
        }
    }

    @Test func removingTheSplitClearsShares() throws {
        let dinner = LedgerEntry(amountPaise: 900_00, flow: .expense)
        context.insert(dinner)
        Splits.apply(draft(["Prakhar"]), to: dinner, in: context)
        Splits.apply(SplitDraft(), to: dinner, in: context)
        try context.save()
        #expect(dinner.shares.isEmpty)
        #expect(try context.fetch(FetchDescriptor<SplitShare>()).isEmpty)
    }
}
