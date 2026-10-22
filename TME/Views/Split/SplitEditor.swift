import SwiftData
import SwiftUI
import TMECore

/// Who shares a payment and how: equally, by amount or by percentage, with
/// or without you.
struct SplitEditor: View {
    @Binding var draft: SplitDraft
    /// The payment's amount, in paise.
    let total: Int

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Friend.createdAt) private var known: [Friend]
    @State private var newName = ""
    @FocusState private var nameFocused: Bool
    @Namespace private var pill

    private var parts: SplitDraft.Parts? { draft.parts(total: total) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        MonoLabel("Split")
                        HeroAmount(paise: total, size: 44)
                    }
                    modePicker
                    people
                    addFriend
                    status
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !draft.isEmpty {
                        Button("Remove split", role: .destructive) {
                            draft = SplitDraft()
                            dismiss()
                        }
                        .accessibilityIdentifier("removeSplit")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(!draft.isEmpty && parts == nil)
                        .accessibilityIdentifier("splitDone")
                }
            }
            .animation(.snappy, value: draft)
            .sensoryFeedback(.selection, trigger: draft.mode)
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.canvas)
    }

    // MARK: Pieces

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(SplitMode.allCases) { mode in
                Button {
                    draft.mode = mode
                } label: {
                    Text(mode.title)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(draft.mode == mode ? .black : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background {
                            if draft.mode == mode {
                                Capsule().fill(.white).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(draft.mode == mode ? .isSelected : [])
                .accessibilityIdentifier("splitMode-\(mode.rawValue)")
            }
        }
        .padding(3)
        .background(Theme.surface, in: Capsule())
    }

    private var people: some View {
        VStack(spacing: 0) {
            // You: in or out, with whatever's left after friends.
            HStack(spacing: 12) {
                Avatar(name: "You")
                Text("You")
                    .foregroundStyle(.white)
                Spacer()
                if draft.includesMe {
                    Text(parts.map { Rupees.format(paise: $0.mine) } ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                InstrumentSwitch(isOn: $draft.includesMe)
                    .accessibilityLabel("Include you")
                    .accessibilityIdentifier("splitIncludesMe")
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }

            ForEach($draft.friends) { $person in
                let index = draft.friends.firstIndex { $0.id == person.id } ?? 0
                HStack(spacing: 12) {
                    Avatar(name: person.name)
                    Text(person.name)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    switch draft.mode {
                    case .equal:
                        Text(parts.map { Rupees.format(paise: $0.friends[index]) } ?? "—")
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    case .amounts:
                        field("0", text: $person.amountText, prefix: "₹")
                            .accessibilityIdentifier("splitAmount-\(person.name)")
                    case .percent:
                        HStack(spacing: 8) {
                            if let parts {
                                Text(Rupees.format(paise: parts.friends[index]))
                                    .font(.footnote)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            field("0", text: $person.percentText, suffix: "%")
                                .accessibilityIdentifier("splitPercent-\(person.name)")
                        }
                    }
                    Button {
                        draft.remove(person)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Remove \(person.name)")
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
                .transition(.opacity)
                .accessibilityIdentifier("splitPerson-\(person.name)")
            }
        }
    }

    /// Friends you've split with before (most often first), filtered by what's typed.
    private var suggestions: [Friend] {
        let typed = newName.trimmingCharacters(in: .whitespaces)
        return known
            .filter { friend in !draft.friends.contains { $0.id == friend.name.lowercased() } }
            .filter { typed.isEmpty || $0.name.localizedCaseInsensitiveContains(typed) }
            .sorted { $0.shares.count > $1.shares.count }
            .prefix(8)
            .map { $0 }
    }

    private var addFriend: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                TextField("Add a friend", text: $newName)
                    .focused($nameFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(addTyped)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("splitFriendField")
                if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add", action: addTyped)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("splitAddFriend")
                }
            }
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { friend in
                            Button {
                                draft.add(friend.name)
                                newName = ""
                            } label: {
                                HStack(spacing: 7) {
                                    Avatar(name: friend.name, size: 20)
                                    Text(friend.name)
                                }
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .padding(.leading, 6)
                                .padding(.trailing, 13)
                                .frame(height: 34)
                                .background(Capsule().fill(Theme.surface))
                                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityIdentifier("splitSuggest-\(friend.name)")
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)
            }
        }
    }

    private func addTyped() {
        draft.add(newName)
        newName = ""
    }

    @ViewBuilder private var status: some View {
        if draft.isEmpty {
            Text("Add the friends sharing this payment. Split it equally, by amount, or by percentage.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        } else if let parts {
            let owed = parts.friends.reduce(0, +)
            Text("\(Rupees.format(paise: owed)) owed to you by \(draft.friends.count == 1 ? draft.friends[0].name : "\(draft.friends.count) friends")")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("splitStatus")
        } else {
            let left = draft.unassigned(total: total)
            Text(statusProblem(left))
                .font(.footnote)
                .foregroundStyle(Theme.expense)
                .accessibilityIdentifier("splitStatus")
        }
    }

    private func statusProblem(_ left: Int) -> String {
        switch draft.mode {
        case .amounts:
            left > 0 ? "\(Rupees.format(paise: left)) left to share out" : "\(Rupees.format(paise: -left)) more than the payment"
        case .percent:
            left > 0 ? "\((Double(left) / 100).formatted())% left to share out" : "\((Double(-left) / 100).formatted())% over 100%"
        case .equal:
            "Type the amount first"
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, prefix: String? = nil, suffix: String? = nil) -> some View {
        HStack(spacing: 2) {
            if let prefix { Text(prefix).foregroundStyle(Theme.textTertiary) }
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
            if let suffix { Text(suffix).foregroundStyle(Theme.textTertiary) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Theme.surface, in: Capsule())
    }
}

/// A friend's initial in a quiet circle.
struct Avatar: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.surfaceRaised, in: Circle())
            .accessibilityHidden(true)
    }
}
