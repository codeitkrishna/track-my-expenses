import SwiftData
import SwiftUI
import TMECore

/// Everyone you split with: who owes you, and how much.
struct FriendsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Friend.name) private var friends: [Friend]
    @State private var adding = false
    @State private var newName = ""
    @State private var deleting: Friend?

    var body: some View {
        let owing = friends.filter { $0.owedPaise > 0 }.sorted { $0.owedPaise > $1.owedPaise }
        let settled = friends.filter { $0.owedPaise == 0 }
        let total = owing.reduce(0) { $0 + $1.owedPaise }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel("Owed to you")
                    HeroAmount(paise: total)
                        .accessibilityIdentifier("friendsTotal")
                    Text(summary(owing: owing.count, total: total))
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.top, 8)
                .padding(.bottom, 26)

                ForEach(owing) { friend in
                    row(friend)
                }
                if !settled.isEmpty {
                    MonoLabel("Settled up")
                        .padding(.top, 30)
                        .padding(.bottom, 4)
                    ForEach(settled) { friend in
                        row(friend)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .animation(.snappy, value: total)
        }
        .background(Theme.canvas)
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add friend", systemImage: "person.badge.plus") { adding = true }
                    .accessibilityIdentifier("addFriendButton")
            }
        }
        .alert("Add a friend", isPresented: $adding) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { newName = "" }
            Button("Add") {
                if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    _ = Splits.findOrCreateFriend(named: newName, in: context)
                    try? context.save()
                }
                newName = ""
            }
        }
    }

    private func summary(owing: Int, total: Int) -> String {
        if friends.isEmpty { return "Split a payment with friends to see who owes you." }
        if total == 0 { return "Everyone's settled up." }
        return owing == 1 ? "by 1 friend" : "by \(owing) friends"
    }

    private func row(_ friend: Friend) -> some View {
        NavigationLink {
            FriendDetail(friend: friend)
        } label: {
            HStack(spacing: 14) {
                Avatar(name: friend.name, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.name)
                        .foregroundStyle(.white)
                    Text(detail(friend))
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 8)
                if friend.owedPaise > 0 {
                    Text(Rupees.format(paise: friend.owedPaise))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .opacity(friend.owedPaise > 0 ? 1 : 0.55)
        }
        .buttonStyle(RowPressStyle())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
        .contextMenu {
            Button("Remove friend", systemImage: "trash", role: .destructive) { deleting = friend }
        }
        .confirmationDialog(
            "Remove \(friend.name)?",
            isPresented: Binding(get: { deleting?.uuid == friend.uuid }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                context.delete(friend)
                try? context.save()
                deleting = nil
            }
        } message: {
            Text("Their splits are removed too. The payments themselves stay.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("friend-\(friend.name)")
    }

    private func detail(_ friend: Friend) -> String {
        let open = friend.openShares.count
        if open > 0 { return open == 1 ? "1 payment" : "\(open) payments" }
        return friend.shares.isEmpty ? "No splits yet" : "All paid back"
    }
}

/// One friend: what they owe you and the payments it came from. Mark one
/// paid, settle everything, add money you lent them, or share the list.
struct FriendDetail: View {
    @Environment(\.modelContext) private var context
    let friend: Friend
    @State private var adding = false
    @State private var settlingAll = false
    @State private var settling: SplitShare?
    /// The payment being taken off this friend's account, or deleted.
    @State private var removing: SplitShare?
    /// The payment open for editing: amount, category, split.
    @State private var editing: LedgerEntry?
    @State private var card: Image?
    @State private var paidCount = 0

    var body: some View {
        let open = friend.openShares
        let paidBack = friend.shares
            .filter { $0.settled && $0.entry != nil }
            .sorted { ($0.settledAt ?? .distantPast) > ($1.settledAt ?? .distantPast) }
        let owed = friend.owedPaise
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel(owed > 0 ? "\(friend.name) owes you" : "\(friend.name) · settled up")
                    HeroAmount(paise: owed)
                        .accessibilityIdentifier("friendOwed")
                }
                .padding(.top, 8)

                actions(owed: owed)
                    .padding(.top, 22)

                if !open.isEmpty {
                    MonoLabel(open.count == 1 ? "From 1 payment" : "From \(open.count) payments")
                        .padding(.top, 34)
                        .padding(.bottom, 4)
                    ForEach(open) { share in
                        ShareRow(share: share, onOpen: { editing = share.entry }) { settling = share }
                            .swipeToDelete(identifier: "swipeRemove") { removing = share }
                            .contextMenu { removeActions(share) }
                            .modifier(rowDialogs(share))
                    }
                }
                if !paidBack.isEmpty {
                    MonoLabel("Paid back")
                        .padding(.top, 34)
                        .padding(.bottom, 4)
                    ForEach(paidBack) { share in
                        ShareRow(share: share, onOpen: { editing = share.entry }, onPaid: nil)
                            .swipeToDelete(identifier: "swipeRemove") { removing = share }
                            .contextMenu {
                                Button("Mark as not paid", systemImage: "arrow.uturn.backward") {
                                    withAnimation(.snappy) {
                                        share.settled = false
                                        share.settledAt = nil
                                        try? context.save()
                                    }
                                }
                                removeActions(share)
                            }
                            .modifier(rowDialogs(share))
                    }
                }
                if !open.isEmpty || !paidBack.isEmpty {
                    Text("Tap a payment to edit it, swipe it left to delete it, tap ✓ when it's paid back.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 18)
                }
                if open.isEmpty && paidBack.isEmpty {
                    Text("Nothing split with \(friend.name) yet. Split a payment, or add money you lent them.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 30)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .animation(.snappy, value: owed)
        }
        .background(Theme.canvas)
        .navigationTitle(friend.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            QuickAddView(initialFlow: .expense, forFriend: friend.name)
        }
        .sheet(item: $editing) { entry in
            EntryEditView(entry: entry)
        }
        .sensoryFeedback(.success, trigger: paidCount)
        .task(id: cardKey(open)) {
            card = renderCard(open: open, owed: owed)
        }
    }

    /// "Paid back?" and "Delete or remove?" for one payment, opening next to its row.
    private func rowDialogs(_ share: SplitShare) -> RowDialogs {
        RowDialogs(
            share: share,
            friendName: friend.name,
            settling: Binding(get: { settling?.uuid == share.uuid }, set: { if !$0 { settling = nil } }),
            removing: Binding(get: { removing?.uuid == share.uuid }, set: { if !$0 { removing = nil } }),
            markPaid: {
                withAnimation(.snappy) {
                    share.settled = true
                    share.settledAt = .now
                    try? context.save()
                }
                settling = nil
                paidCount += 1
            },
            deletePayment: { deletePayment(of: share) },
            remove: { remove(share) }
        )
    }

    @ViewBuilder private func removeActions(_ share: SplitShare) -> some View {
        Button("Edit", systemImage: "pencil") { editing = share.entry }
        Button("Delete payment", systemImage: "trash", role: .destructive) { deletePayment(of: share) }
        Button("Only remove from \(friend.name)", systemImage: "person.badge.minus", role: .destructive) { remove(share) }
    }

    /// Takes this payment off the friend's account; the payment stays.
    private func remove(_ share: SplitShare) {
        withAnimation(.snappy) {
            let entry = share.entry
            entry?.shares.removeAll { $0.uuid == share.uuid }
            context.delete(share)
            if let entry, entry.shares.isEmpty {
                entry.splitModeRaw = nil
                entry.splitIncludesMe = true
            }
            try? context.save()
        }
        removing = nil
    }

    /// Deletes the payment itself, with every friend's part of it.
    private func deletePayment(of share: SplitShare) {
        withAnimation(.snappy) {
            if let entry = share.entry { context.delete(entry) }
            try? context.save()
        }
        removing = nil
    }

    private func actions(owed: Int) -> some View {
        HStack(spacing: 10) {
            if owed > 0, let card {
                ShareLink(
                    item: card,
                    preview: SharePreview("\(friend.name) owes \(Rupees.format(paise: owed))", image: card)
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .actionPill(primary: true)
                }
                .accessibilityIdentifier("shareOwed")
            }
            Button { adding = true } label: {
                Label("Add", systemImage: "plus")
                    .actionPill()
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Add money spent or lent for \(friend.name)")
            .accessibilityIdentifier("addForFriend")
            if owed > 0 {
                Button { settlingAll = true } label: {
                    Label("Settle all", systemImage: "checkmark")
                        .actionPill()
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("settleAll")
                .confirmationDialog("\(friend.name) paid you \(Rupees.format(paise: owed))?", isPresented: $settlingAll, titleVisibility: .visible) {
                    Button("Mark everything as paid") {
                        withAnimation(.snappy) {
                            Splits.settle(friend)
                            try? context.save()
                        }
                        paidCount += 1
                    }
                }
            }
        }
    }

    /// Changes whenever the shared picture would.
    private func cardKey(_ open: [SplitShare]) -> String {
        open.map { "\($0.uuid)-\($0.amountPaise)" }.joined(separator: ",")
    }

    private func renderCard(open: [SplitShare], owed: Int) -> Image? {
        guard owed > 0 else { return nil }
        let renderer = ImageRenderer(content: OwedCard(name: friend.name, owed: owed, shares: open))
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}

private struct RowDialogs: ViewModifier {
    let share: SplitShare
    let friendName: String
    @Binding var settling: Bool
    @Binding var removing: Bool
    let markPaid: () -> Void
    let deletePayment: () -> Void
    let remove: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "\(friendName) paid \(Rupees.format(paise: share.amountPaise)) for \(share.entry?.title ?? "this")?",
                isPresented: $settling,
                titleVisibility: .visible
            ) {
                Button("Mark as paid", action: markPaid)
            }
            .confirmationDialog(
                "\(Rupees.format(paise: share.amountPaise)) · \(share.entry?.title ?? "Payment")",
                isPresented: $removing,
                titleVisibility: .visible
            ) {
                Button("Delete payment", role: .destructive, action: deletePayment)
                Button("Only remove from \(friendName)", role: .destructive, action: remove)
            } message: {
                Text("Deleting removes the payment from your tracker too. Or keep the payment and just take it off \(friendName)'s account.")
            }
    }
}

/// One payment in a friend's list: when, what, their part of the total.
/// Tap it to edit the payment; ✓ marks it paid back.
private struct ShareRow: View {
    let share: SplitShare
    let onOpen: () -> Void
    /// Mark just this one as paid; nil once it has been.
    let onPaid: (() -> Void)?

    var body: some View {
        let total = share.entry?.amountPaise ?? 0
        HStack(alignment: .center, spacing: 12) {
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: 12) {
                    MonoLabel((share.entry?.date ?? .now).formatted(.dateTime.day().month(.abbreviated)))
                        .frame(width: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(share.entry?.title ?? "Payment")
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("of \(Rupees.format(paise: total))" + (total > 0 ? " · \(percent(Double(share.amountPaise) / Double(total)))" : ""))
                            .font(.footnote)
                            .foregroundStyle(Theme.textTertiary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    Text(Rupees.format(paise: share.amountPaise))
                        .monospacedDigit()
                        .foregroundStyle(onPaid == nil ? Theme.textTertiary : .white)
                        .strikethrough(onPaid == nil, color: Theme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityIdentifier("open-\(share.entry?.title ?? "")")
            if let onPaid {
                Button(action: onPaid) {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.income)
                        .frame(width: 32, height: 32)
                        .background(Theme.income.opacity(0.14), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Paid back")
                .accessibilityIdentifier("paid-\(share.entry?.title ?? "")")
            }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("share-\(share.entry?.title ?? "")")
    }
}

/// The picture shared with a friend: what they owe on top, the payments
/// it came from below, in the app's look.
struct OwedCard: View {
    let name: String
    let owed: Int
    let shares: [SplitShare]

    /// "Food · Team dinner": the category and note, leaving out whatever
    /// the payment's name already says.
    static func details(of entry: LedgerEntry?) -> String? {
        guard let entry else { return nil }
        var parts: [String] = []
        if let category = entry.category?.name, category != entry.title { parts.append(category) }
        let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty, note != entry.title { parts.append(note) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Soft colours for the card: light enough to read on black.
    private enum Ink {
        static let brand = Color(hex: 0xB9A8FF)
        static let date = Color(hex: 0x9FC9FF)
        static let name = Color(hex: 0x8DEBC7)
        static let owes = Color(hex: 0xFFBE9F)
    }

    /// A category's own colour, lightened for text.
    private static func light(_ slot: Int?) -> Color {
        Palette.color(slot: slot ?? -1).mix(with: .white, by: 0.42)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MonoLabel("TME · Split", color: Ink.brand)
                Spacer()
                MonoLabel(Date.now.formatted(.dateTime.day().month(.abbreviated).year()), color: Ink.date)
            }
            Text("\(Text(name).foregroundStyle(Ink.name).fontWeight(.medium)) \(Text("owes you").foregroundStyle(Ink.owes))")
                .font(.title3)
                .padding(.top, 28)
            HeroAmount(paise: owed, size: 64)
                .padding(.top, 2)
            Rectangle().fill(Theme.hairline).frame(height: 1)
                .padding(.vertical, 22)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(shares) { share in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        MonoLabel((share.entry?.date ?? .now).formatted(.dateTime.day().month(.abbreviated)), color: Ink.date.opacity(0.85))
                            .frame(width: 56, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(share.entry?.title ?? "Payment")
                                .foregroundStyle(.white)
                            if let details = Self.details(of: share.entry) {
                                Text(details)
                                    .font(.footnote)
                                    .foregroundStyle(Self.light(share.entry?.category?.colorSlot))
                            }
                            Text("of \(Rupees.format(paise: share.entry?.amountPaise ?? 0))")
                                .font(.footnote)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer(minLength: 8)
                        Text(Rupees.format(paise: share.amountPaise))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
                .padding(.vertical, 22)
            MonoLabel(shares.count == 1 ? "1 payment" : "\(shares.count) payments", color: Ink.brand)
        }
        .padding(28)
        .frame(width: 390)
        .background(Theme.canvas)
        .environment(\.colorScheme, .dark)
    }
}

private extension View {
    /// The friend screen's buttons: Share in white, the rest quiet.
    func actionPill(primary: Bool = false) -> some View {
        font(.subheadline.weight(.medium))
            .foregroundStyle(primary ? .black : .white)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(primary ? Color.white : Theme.surfaceRaised, in: Capsule())
    }
}
