import SwiftData
import SwiftUI
import TMECore

/// How to make bank SMS log themselves with a Shortcuts automation.
struct SMSSetupView: View {
    static let keywords = ["debited", "credited", "spent", "Sent Rs"]

    var body: some View {
        List {
            Section {
                Text("Apps can't read your messages, but a Shortcuts automation can hand each bank alert to TME the moment it arrives. TME logs it and asks for a category.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Set it up once") {
                Step(number: 1, text: "Open the **Shortcuts** app and create a new **Automation**.")
                Step(number: 2, text: "Choose the **Message** trigger. Set **Message Contains** to `debited`. Leave the sender empty: banks' sender names can't be picked.")
                Step(number: 3, text: "Choose **Run Immediately**, and turn off **Notify When Run**.")
                Step(number: 4, text: "Add the action **Log Bank SMS** (from TME). Tap its **Message** field and pick **Shortcut Input**.")
                Step(number: 5, text: "Repeat for the other words your bank uses. Each automation can only match one word.")
            }
            Section {
                ForEach(Self.keywords, id: \.self) { word in
                    HStack {
                        Text(word)
                            .font(.body.monospaced())
                        Spacer()
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = word }
                            .labelStyle(.iconOnly)
                    }
                }
            } header: {
                Text("Words to use")
            } footer: {
                Text("OTPs, bill reminders and offers are ignored even if they contain these words. Use **Test a bank SMS** to check your bank's format.")
            }
            Section("Good to know") {
                Text("If the same payment arrives twice, it's only logged once.")
                Text("Once you've filed a merchant, its payments are filed automatically and you won't be asked again.")
                Text("Some banks skip the SMS for small UPI payments, such as HDFC for ₹100 and under. Add those with the quick-add button.")
            }
            .font(.callout)
        }
        .navigationTitle("Auto-log bank SMS")
    }
}

/// Paste an SMS and see what TME reads from it.
struct SMSTesterView: View {
    @Environment(\.modelContext) private var context
    @State private var message = ""
    @State private var outcome: String?

    var body: some View {
        let parsed = BankSMSParser.parse(message)
        List {
            Section {
                TextField("Paste a bank SMS here", text: $message, axis: .vertical)
                    .lineLimit(4...10)
                    .accessibilityIdentifier("smsTesterField")
            } footer: {
                Text("Long-press a bank SMS in Messages, tap Copy, and paste it here.")
            }

            if !message.isEmpty {
                Section("What TME reads") {
                    if let parsed {
                        LabeledContent("Type", value: parsed.kind == .expense ? "Expense" : "Income")
                        LabeledContent("Amount", value: Rupees.format(paise: parsed.amountPaise))
                        LabeledContent("Merchant", value: parsed.counterparty ?? "Not found")
                        LabeledContent("Account", value: parsed.accountTail.map { "••\($0)" } ?? "Not found")
                        LabeledContent("Reference", value: parsed.reference ?? "Not found")
                    } else {
                        Label("Not a transaction, so it would be ignored.", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                if parsed != nil {
                    Section {
                        Button("Log it now", systemImage: "plus.circle") { log() }
                    } footer: {
                        if let outcome { Text(outcome) }
                    }
                }
            }
        }
        .navigationTitle("Test a bank SMS")
    }

    private func log() {
        do {
            let result = try SMSIngest.handle(message, in: context)
            switch result {
            case .ignored: outcome = "Ignored: not a transaction."
            case .duplicate: outcome = "Already logged."
            case .autoTagged: outcome = "Logged and filed automatically."
            case .needsCategory: outcome = "Logged. Pick its category from the prompt, or in Activity."
            }
            Task { await TagPrompt.follow(result, in: context) }
        } catch {
            outcome = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

/// How to get an always-on-screen button for quick adds.
struct FloatingButtonSetupView: View {
    var body: some View {
        List {
            Section {
                Text("iPhone apps can't float a button over other apps, but iPhone's own **AssistiveTouch** button can: it stays on screen, you can drag it anywhere, and it can run TME's actions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("1. Make the shortcuts") {
                Step(number: 1, text: "In **Shortcuts**, tap **+**, add the action **Add Expense** (TME) and name the shortcut \"Add Expense\".")
                Step(number: 2, text: "Do the same for **Add Income** and **Add Category**.")
                Step(number: 3, text: "Make one more with the action **Open App → TME**, named \"Open TME\".")
            }
            Section("2. Turn on the button") {
                Step(number: 4, text: "Go to **Settings → Accessibility → Touch → AssistiveTouch** and turn it on.")
                Step(number: 5, text: "**Customize Top Level Menu**: set it to 3 icons and pick Add Expense, Add Income and Add Category.")
                Step(number: 6, text: "Under **Custom Actions**, set **Long Press** to **Open Menu** and **Single-Tap** to **Open TME**.")
            }
            Section("How it works") {
                Text("Long-press the button and tap Add Expense: a small prompt asks for the amount and category over whatever app you're in. TME doesn't open.")
                Text("Prefer no button? **Settings → Accessibility → Touch → Back Tap** can run Add Expense when you double-tap the back of the phone.")
            }
            .font(.callout)
        }
        .navigationTitle("Floating button")
    }
}

private struct Step: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Palette.chart, in: Circle())
            Text(text)
                .font(.callout)
        }
        .padding(.vertical, 2)
    }
}
