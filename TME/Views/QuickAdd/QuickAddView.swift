import SwiftData
import SwiftUI
import TMECore

/// Log a new payment.
struct QuickAddView: View {
    var initialFlow: Flow = .expense
    /// Money lent or spent for this friend: the whole amount is theirs to pay back.
    var forFriend: String?

    var body: some View {
        EntryComposer(mode: .add(initialFlow), forFriend: forFriend)
    }
}

/// Change or delete one payment.
struct EntryEditView: View {
    let entry: LedgerEntry

    var body: some View {
        EntryComposer(mode: .edit(entry))
    }
}

/// The amount in big light numerals over a plain keypad, categories one tap
/// above, one Save. Built for one hand and no system keyboard.
struct EntryComposer: View {
    enum Mode {
        case add(Flow)
        case edit(LedgerEntry)
        /// Back from paying a scanned code in a UPI app; `logged` is the
        /// bank's SMS for it, if that came first.
        case paid(PendingPayment, logged: LedgerEntry?)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    /// Every payment so far, for suggesting who this one went to.
    @Query(sort: \LedgerEntry.date, order: .reverse) private var pastEntries: [LedgerEntry]
    @Query(filter: #Predicate<Goal> { $0.finishedAt == nil }, sort: \Goal.createdAt) private var openGoals: [Goal]

    /// The text fields; while one is in use the system keyboard replaces the keypad.
    enum Field { case receiver, note }

    let mode: Mode
    @State private var flow: Flow
    @State private var digits: String
    @State private var category: LedgerCategory?
    @State private var note: String
    /// Who was paid, or who paid.
    @State private var receiver: String
    @State private var date: Date
    /// Friends sharing this payment, and how.
    @State private var split: SplitDraft
    /// The goal this payment comes out of.
    @State private var goal: Goal?
    /// A new payment starts out from the goal being spent from, once.
    @State private var pickedDefaultGoal = false
    @State private var splitting = false
    @State private var choosingWhen = false
    @State private var naming = false
    @State private var showingSMS = false
    @State private var confirmingDelete = false
    @State private var savedCount = 0
    /// The note field is showing (focus can only go to a field on screen).
    @State private var writingNote = false
    @FocusState private var focus: Field?

    init(mode: Mode, forFriend: String? = nil) {
        self.mode = mode
        switch mode {
        case .add(let flow):
            _flow = State(initialValue: flow)
            _digits = State(initialValue: "")
            _category = State(initialValue: nil)
            _note = State(initialValue: "")
            _receiver = State(initialValue: forFriend ?? "")
            _date = State(initialValue: .now)
            var draft = SplitDraft()
            if let forFriend {
                draft.add(forFriend)
                draft.includesMe = false
            }
            _split = State(initialValue: draft)
        case .edit(let entry):
            _flow = State(initialValue: entry.flow)
            _digits = State(initialValue: Self.typed(entry.amountPaise))
            _category = State(initialValue: entry.category)
            _note = State(initialValue: entry.note)
            _receiver = State(initialValue: entry.displayMerchant ?? "")
            _date = State(initialValue: entry.date)
            _split = State(initialValue: SplitDraft(entry: entry))
            _goal = State(initialValue: entry.goal)
            _pickedDefaultGoal = State(initialValue: true)
        case .paid(let payment, let logged):
            _flow = State(initialValue: .expense)
            _digits = State(initialValue: (logged?.amountPaise ?? payment.payee.amountPaise).map(Self.typed) ?? "")
            _category = State(initialValue: logged?.category)
            _note = State(initialValue: payment.note ?? "")
            _receiver = State(initialValue: payment.payee.displayName)
            _date = State(initialValue: logged?.date ?? .now)
            _split = State(initialValue: SplitDraft())
        }
    }

    /// A split that's set up but doesn't add up for the amount typed.
    private var splitIsOff: Bool {
        !split.isEmpty && split.parts(total: paise ?? 0) == nil
    }

    private var editing: LedgerEntry? {
        if case .edit(let entry) = mode { entry } else { nil }
    }

    private var payment: PendingPayment? {
        if case .paid(let payment, _) = mode { payment } else { nil }
    }

    private var paise: Int? { EntryWriter.paise(fromTyped: digits) }

    private var choices: [LedgerCategory] {
        Tagging.byUse(categories.filter { $0.flow == flow })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let payment {
                    PaidHeader(payment: payment)
                        .padding(.top, 4)
                } else {
                    FlowSwitch(flow: $flow)
                        .padding(.top, 4)
                }
                Spacer(minLength: 12)
                AmountDisplay(digits: digits, flow: flow)
                if let amountSource {
                    Text(amountSource)
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityIdentifier("amountSource")
                }
                receiverField
                    .padding(.top, 2)
                if focus == .receiver {
                    ReceiverSuggestions(names: suggestions, categoryFor: rememberedCategory) { pick($0) }
                        .padding(.top, 10)
                        .transition(.opacity)
                }
                details
                    .padding(.top, 14)
                Spacer(minLength: 12)
                if focus != .receiver {
                    categoryRail
                }
                if focus == nil {
                    Keypad(digits: $digits)
                        .padding(.top, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                saveButton
                    .padding(.top, 10)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .animation(.snappy, value: focus)
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if payment != nil {
                        // Leaves nothing behind: the next time it's a new scan.
                        Button("Didn't pay") { dismiss() }
                            .accessibilityIdentifier("didntPay")
                    } else {
                        Button("Cancel", systemImage: "xmark") { dismiss() }
                    }
                }
                if editing != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                            .confirmCard(
                                isPresented: $confirmingDelete,
                                title: "Delete this payment?",
                                actions: [PopupAction(title: "Delete", role: .destructive, identifier: "confirmDeletePayment") {
                                    if let editing {
                                        context.delete(editing)
                                        try? context.save()
                                    }
                                    dismiss()
                                }]
                            )
                    }
                }
            }
            .onChange(of: flow) {
                if category?.flow != flow { category = nil }
                if flow == .income { goal = nil }
            }
            .onAppear {
                // The shop's category from last time, by name.
                if payment != nil, category == nil {
                    category = rememberedCategory(for: receiver)
                }
                guard !pickedDefaultGoal else { return }
                pickedDefaultGoal = true
                if flow == .expense { goal = Goals.spendingGoal(in: context) }
            }
            .onChange(of: focus) {
                if focus != .note { writingNote = false }
            }
            .onDisappear {
                // Logged or not, it's been asked about.
                if payment != nil { ScanPay.clear() }
            }
            .sensoryFeedback(.success, trigger: savedCount)
            .sensoryFeedback(.selection, trigger: category?.uuid)
            .newCategoryAlert(isPresented: $naming, flow: flow) { category = $0 }
            .sheet(isPresented: $showingSMS) {
                if let editing { SMSDetails(entry: editing) }
            }
            .sheet(isPresented: $splitting) {
                SplitEditor(draft: $split, total: paise ?? 0)
            }
        }
        .presentationBackground(Theme.canvas)
    }

    // MARK: Pieces

    /// "to Swiggy" (or "from Acme") under the amount; suggests people and
    /// places paid before once two letters are typed.
    private var receiverField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(flow == .expense ? "to" : "from")
                .foregroundStyle(Theme.textTertiary)
            TextField("someone", text: $receiver)
                .focused($focus, equals: .receiver)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { pick(receiver) }
                .fixedSize()
                .foregroundStyle(.white)
                .accessibilityLabel(flow == .expense ? "Paid to" : "Received from")
                .accessibilityIdentifier("receiverField")
            if let editing, editing.source == .sms || editing.upiID != nil {
                Button { showingSMS = true } label: {
                    Image(systemName: editing.rawMessage == nil && editing.source != .sms ? "qrcode" : "message")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(editing.rawMessage == nil && editing.source != .sms ? "How it was paid" : "The bank's message")
                .accessibilityIdentifier("smsButton")
            }
            if flow == .expense, !openGoals.isEmpty || goal != nil {
                goalMenu
            }
        }
        .font(.body)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { focus = .receiver }
    }

    /// Past receivers matching what's typed (two letters or more, any
    /// case): names starting with it first, then the most paid.
    private var suggestions: [String] {
        let typed = receiver.trimmingCharacters(in: .whitespaces)
        guard typed.count >= 2 else { return [] }
        var counts: [String: Int] = [:]
        for entry in pastEntries {
            if let name = entry.displayMerchant { counts[name, default: 0] += 1 }
        }
        return counts.keys
            .filter { $0.localizedCaseInsensitiveContains(typed) && $0.localizedCaseInsensitiveCompare(typed) != .orderedSame }
            .sorted { a, b in
                let aStarts = a.lowercased().hasPrefix(typed.lowercased())
                let bStarts = b.lowercased().hasPrefix(typed.lowercased())
                if aStarts != bStarts { return aStarts }
                if counts[a] != counts[b] { return counts[a, default: 0] > counts[b, default: 0] }
                return a.localizedCompare(b) == .orderedAscending
            }
            .prefix(8)
            .map { $0 }
    }

    /// What this receiver was filed under: the remembered choice, else the
    /// category their past payments used most.
    private func rememberedCategory(for name: String) -> LedgerCategory? {
        if let remembered = Tagging.rememberedCategory(for: name, flow: flow, in: context) {
            return remembered
        }
        let theirs = pastEntries.filter { $0.flow == flow && $0.displayMerchant == name }.compactMap(\.category)
        let counts = Dictionary(grouping: theirs, by: \.uuid).mapValues(\.count)
        return theirs.max { counts[$0.uuid, default: 0] < counts[$1.uuid, default: 0] }
    }

    /// Takes a receiver, and the category they were filed under last time
    /// if none is picked yet.
    private func pick(_ name: String) {
        receiver = name.trimmingCharacters(in: .whitespaces)
        if category == nil, !receiver.isEmpty, let remembered = rememberedCategory(for: receiver) {
            category = remembered
        }
        focus = nil
    }

    /// Note, when, and the bank's message for an SMS payment.
    private var details: some View {
        HStack(spacing: 6) {
            if writingNote || !note.isEmpty {
                TextField("Note", text: $note)
                    .focused($focus, equals: .note)
                    .submitLabel(.done)
                    .onSubmit { focus = nil }
                    .task(id: writingNote) {
                        if writingNote { focus = .note }
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Theme.surface, in: Capsule())
                    .frame(maxWidth: 180)
                    .accessibilityIdentifier("noteField")
            } else {
                Button { writingNote = true } label: {
                    Label("Note", systemImage: "pencil")
                        .detail()
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("addNoteButton")
            }
            Button { splitting = true } label: {
                Label(splitLabel, systemImage: "person.2")
                    .detail(highlighted: !split.isEmpty, warning: splitIsOff)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("splitButton")
            Button { choosingWhen = true } label: {
                Text(whenLabel)
                    .detail()
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("When")
            .accessibilityValue(date.formatted(date: .long, time: .shortened))
            .accessibilityIdentifier("whenButton")
            .dateCard(isPresented: $choosingWhen, selection: $date, in: Date.distantPast...Date.now.addingTimeInterval(86_400), showsTime: true)
        }
        .frame(maxWidth: .infinity)
    }

    /// Which goal it's spent from, finishing the sentence: "to Swiggy
    /// from Goa trip". Just a target until one is picked.
    private var goalMenu: some View {
        ChoiceMenu(title: "Spent from") {
            [ChoiceSection(rows: [ChoiceRow(title: "No goal", symbol: "minus.circle", isSelected: goal == nil, identifier: "goal-none") { goal = nil }]
                + openGoals.map { option in
                    ChoiceRow(title: option.name, symbol: "target", isSelected: goal?.uuid == option.uuid, identifier: "goalChoice-\(option.name)") { goal = option }
                })]
        } label: {
            if let goal {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("from")
                        .foregroundStyle(Theme.textTertiary)
                    Text(goal.name.count > 16 ? goal.name.prefix(15) + "…" : goal.name)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .fixedSize()
            } else {
                Image(systemName: "target")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
        }
        .accessibilityLabel(goal.map { "Spent from \($0.name)" } ?? "Spent from a goal")
        .accessibilityIdentifier("goalButton")
    }

    /// "Split" or "Split · 2".
    private var splitLabel: String {
        split.isEmpty ? "Split" : "Split · \(split.friends.count)"
    }

    /// "Today 14:32", "Yesterday 09:15", "18 Oct 20:15".
    private var whenLabel: String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday \(time)" }
        return date.formatted(.dateTime.day().month(.abbreviated)) + " " + time
    }

    /// "+" for a new category, then two rows of chips, most used first,
    /// scrolling sideways together.
    private var categoryRail: some View {
        let rows = [choices.enumerated().filter { $0.offset % 2 == 0 }.map(\.element),
                    choices.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)]
        return HStack(spacing: 10) {
            NewCategoryChip(identifier: "pickNewCategory", compact: true) { naming = true }
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows.indices, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(rows[row]) { choice in
                                CategoryChip(category: choice, isSelected: category?.uuid == choice.uuid, idPrefix: "pick") {
                                    category = category?.uuid == choice.uuid ? nil : choice
                                }
                            }
                        }
                    }
                }
                .padding(.trailing, 20)
            }
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03)],
                               startPoint: .leading, endPoint: .trailing)
            )
            .padding(.trailing, -20)
        }
        .frame(height: 80)
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(saveTitle)
                .font(.headline)
                .foregroundStyle(paise == nil ? Theme.textTertiary : .black)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.glassProminent)
        .tint(flow == .income ? Theme.income : .white)
        .disabled(paise == nil || splitIsOff)
        .animation(.snappy, value: saveTitle)
        .accessibilityIdentifier("saveButton")
    }

    private var saveTitle: String {
        guard let paise else { return "Save" }
        if splitIsOff { return "Split doesn't add up" }
        let amount = Rupees.format(paise: paise)
        return category.map { "Save \(amount) · \($0.name)" } ?? "Save \(amount)"
    }

    private func save() {
        guard let paise else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = receiver.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .add:
            insert(paise: paise, note: trimmed, name: name)
        case .edit(let entry):
            update(entry, paise: paise, note: trimmed, name: name)
        case .paid(let payment, _):
            // The bank's SMS may have come first, even while this was open:
            // then this is that payment, now with the shop's name.
            if let logged = ScanPay.smsEntry(for: payment, amountPaise: paise, in: context) {
                logged.upiID = payment.payee.address
                if let category, let bankName = logged.merchant {
                    Tagging.remember(category, for: bankName, in: context)
                }
                update(logged, paise: paise, note: trimmed, name: name)
            } else {
                insert(paise: paise, note: trimmed, name: name, source: .scan, upiID: payment.payee.address)
            }
        }
        // Next time this receiver shows up, by hand or by SMS, it's filed the same way.
        if !name.isEmpty, let category {
            Tagging.remember(category, for: name, in: context)
        }
        try? context.save()
        TagNotifications.registerCategories(in: context)
        savedCount += 1
        dismiss()
    }

    private func update(_ editing: LedgerEntry, paise: Int, note trimmed: String, name: String) {
        editing.amountPaise = paise
        editing.flow = flow
        editing.note = trimmed
        editing.date = date
        // Keep the bank's spelling unless the name was actually changed.
        if name != (editing.displayMerchant ?? "") {
            editing.merchant = name.isEmpty ? nil : name
        }
        editing.goal = flow == .expense ? goal : nil
        let sameCategory = category != nil && category?.uuid == editing.category?.uuid
        if let category, category.uuid != editing.category?.uuid {
            Tagging.assign(category, to: editing, in: context)
        } else if category == nil {
            editing.category = nil
        }
        if !split.isEmpty || !editing.shares.isEmpty {
            Splits.apply(split, to: editing, in: context)
        }
        GoalRules.sync(editing, in: context)
        // A new amount under the same category can still go over a limit.
        if sameCategory {
            try? context.save()
            LimitAlerts.check(editing, in: context)
        }
    }

    private func insert(paise: Int, note trimmed: String, name: String, source: EntrySource = .manual, upiID: String? = nil) {
        let entry = LedgerEntry(amountPaise: paise, flow: flow, date: date, note: trimmed, merchant: name.isEmpty ? nil : name, source: source)
        entry.upiID = upiID
        context.insert(entry)
        entry.goal = flow == .expense ? goal : nil
        if let category {
            // With a receiver this also files their waiting payments, as tagging does elsewhere.
            Tagging.assign(category, to: entry, in: context)
        }
        if !split.isEmpty {
            Splits.apply(split, to: entry, in: context)
        }
        GoalRules.sync(entry, in: context)
    }

    /// Where a paid amount came from, under it, while it's unchanged.
    private var amountSource: String? {
        guard case .paid(let payment, let logged) = mode else { return nil }
        if let logged, paise == logged.amountPaise { return "From your bank's SMS" }
        if let fixed = payment.payee.amountPaise, paise == fixed { return "Set by the shop" }
        return digits.isEmpty ? "Type what you paid" : nil
    }

    /// 5000000 paise → "50000"; 1050 → "10.50".
    private static func typed(_ paise: Int) -> String {
        paise % 100 == 0 ? "\(paise / 100)" : String(format: "%d.%02d", paise / 100, paise % 100)
    }
}

/// "Paid with PhonePe?" over the UPI ID, in place of expense or income.
private struct PaidHeader: View {
    let payment: PendingPayment

    var body: some View {
        VStack(spacing: 5) {
            Text("Paid with \(payment.appName)?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(payment.payee.address)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("paidHeader")
    }
}

/// Expense or income as two words; a short line slides under the chosen one.
private struct FlowSwitch: View {
    @Binding var flow: Flow
    @Namespace private var line

    var body: some View {
        HStack(spacing: 28) {
            ForEach(Flow.allCases) { option in
                Button {
                    withAnimation(.snappy) { flow = option }
                } label: {
                    VStack(spacing: 7) {
                        Text(option.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(flow == option ? .white : Theme.textTertiary)
                        ZStack {
                            if flow == option {
                                Capsule()
                                    .fill(option == .income ? Theme.income : .white)
                                    .matchedGeometryEffect(id: "line", in: line)
                            }
                        }
                        .frame(width: 18, height: 2)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(flow == option ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: flow)
    }
}

/// The typed amount, big and light, with digits that roll in.
struct AmountDisplay: View {
    let digits: String
    let flow: Flow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(flow == .income ? "+₹" : "₹")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(digits.isEmpty ? "0" : Self.grouped(digits))
                .font(.system(size: 72, weight: .light))
                .tracking(-1.5)
                .foregroundStyle(digits.isEmpty ? Theme.textTertiary : (flow == .income ? Theme.income : .white))
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: digits)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Amount")
        .accessibilityValue(digits.isEmpty ? "0" : "₹\(Self.grouped(digits))")
        .accessibilityIdentifier("amountField")
    }

    /// "245000.5" → "2,45,000.5", keeping what's been typed after the point.
    static func grouped(_ typed: String) -> String {
        let parts = typed.split(separator: ".", omittingEmptySubsequences: false)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.numberStyle = .decimal
        let whole = formatter.string(from: NSNumber(value: Int(parts[0]) ?? 0)) ?? String(parts[0])
        return parts.count > 1 ? whole + "." + parts[1] : whole
    }
}

/// Plain light digits; a soft disc lights up under the finger.
struct Keypad: View {
    @Binding var digits: String
    @State private var taps = 0

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "delete"]]

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 2) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        Button { press(key) } label: {
                            Group {
                                if key == "delete" {
                                    Image(systemName: "delete.left")
                                        .font(.system(size: 22, weight: .light))
                                } else {
                                    Text(key)
                                        .font(.system(size: 30, weight: .light))
                                }
                            }
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(KeyStyle())
                        .accessibilityLabel(key == "delete" ? "Delete" : key == "." ? "Decimal point" : key)
                        .accessibilityIdentifier("key-\(key)")
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                if key == "delete" { digits = ""; taps += 1 }
                            }
                        )
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: taps)
    }

    private func press(_ key: String) {
        taps += 1
        switch key {
        case "delete":
            if !digits.isEmpty { digits.removeLast() }
        case ".":
            if !digits.contains(".") { digits = digits.isEmpty ? "0." : digits + "." }
        default:
            if let point = digits.firstIndex(of: "."), digits.distance(from: point, to: digits.endIndex) > 2 { return }
            if !digits.contains("."), digits.count >= 9 { return }
            digits = digits == "0" ? key : digits + key
        }
    }
}

private struct KeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 56)
            .background {
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.13 : 0))
                    .frame(width: 62, height: 62)
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: configuration.isPressed ? 0.03 : 0.35), value: configuration.isPressed)
    }
}

/// What the bank's SMS said about this payment.
private struct SMSDetails: View {
    let entry: LedgerEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PanelPage {
                PanelSection {
                    if let merchant = entry.displayMerchant { PanelValueRow(title: "Merchant", value: merchant) }
                    if let upiID = entry.upiID { PanelValueRow(title: "UPI ID", value: upiID) }
                    if let tail = entry.accountTail { PanelValueRow(title: "Account", value: "••\(tail)") }
                    if let reference = entry.reference { PanelValueRow(title: "Reference", value: reference) }
                }
                if let raw = entry.rawMessage {
                    PanelSection("Message") {
                        Text(raw)
                            .font(.callout)
                            .foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
            }
            .navigationTitle(entry.rawMessage == nil && entry.source != .sms ? "Paid by scanning" : "From your bank")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.canvas)
    }
}

private extension View {
    /// A quiet capsule for the details under the amount; white when set.
    func detail(highlighted: Bool = false, warning: Bool = false) -> some View {
        font(.subheadline)
            .foregroundStyle(warning ? Theme.expense : (highlighted ? .white : Theme.textSecondary))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(highlighted ? Theme.surfaceRaised : Theme.surface, in: Capsule())
    }
}

/// Past receivers matching what's typed, one tap each, with a dot for the
/// category they were last filed under.
private struct ReceiverSuggestions: View {
    let names: [String]
    let categoryFor: (String) -> LedgerCategory?
    let pick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(names, id: \.self) { name in
                    Button { pick(name) } label: {
                        HStack(spacing: 7) {
                            if let category = categoryFor(name) {
                                Circle()
                                    .fill(Palette.color(slot: category.colorSlot))
                                    .frame(width: 7, height: 7)
                            }
                            Text(name)
                                .lineLimit(1)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background(Capsule().fill(Theme.surface))
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("suggest-\(name)")
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
        .frame(height: names.isEmpty ? 0 : 36)
        .opacity(names.isEmpty ? 0 : 1)
        .animation(.snappy(duration: 0.2), value: names)
    }
}
