import PhotosUI
import SwiftData
import SwiftUI
import TMECore

/// Name, amount, date and picture for a new or existing goal.
struct GoalEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @Query private var entries: [LedgerEntry]

    let goal: Goal?
    @State private var name: String
    @State private var amountText: String
    @State private var hasDate: Bool
    @State private var arriveBy: Date
    @State private var symbol: String
    @State private var colorSlot: Int
    @State private var photo: Data?
    @State private var picked: PhotosPickerItem?
    @State private var loadingPhoto = false
    @FocusState private var nameFocused: Bool
    private var balance = BalanceReader()

    init(goal: Goal?) {
        self.goal = goal
        _name = State(initialValue: goal?.name ?? "")
        _amountText = State(initialValue: goal.map { SplitDraft.typed($0.targetPaise) } ?? "")
        _hasDate = State(initialValue: goal.map { $0.arriveBy != nil && !$0.arriveByIsEstimate } ?? false)
        _arriveBy = State(initialValue: goal?.arriveBy ?? Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now)
        _symbol = State(initialValue: goal?.symbol ?? "airplane")
        _colorSlot = State(initialValue: goal?.colorSlot ?? 0)
        _photo = State(initialValue: goal?.photo)
    }

    private var target: Int? { EntryWriter.paise(fromTyped: amountText) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            PanelPage {
                picture
                    .padding(.top, 8)

                PanelSection {
                    TextField("Goa trip, a camera, a rainy-day fund…", text: $name)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .focused($nameFocused)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                        .accessibilityIdentifier("goalNameField")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("₹")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(Theme.textTertiary)
                        TextField("How much it costs", text: $amountText)
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(.white)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("goalAmountField")
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 64)
                }

                PanelSection(footer: Text(hasDate
                    ? "The board shows whether you're on time for it at your pace."
                    : "Leave it off and TME sets one from your pace. The board then shows whether you're keeping to it.")
                ) {
                    PanelRow("Arrive by a date", symbol: "calendar") {
                        InstrumentSwitch(isOn: $hasDate.animation())
                            .accessibilityLabel("Arrive by a date")
                            .accessibilityIdentifier("goalDateToggle")
                    }
                    if hasDate {
                        CalendarGrid(selection: $arriveBy, in: Date.now...Date.distantFuture)
                            .padding(12)
                    }
                }

                if photo == nil {
                    PanelSection("Colour") {
                        HStack(spacing: 0) {
                            ForEach(0..<Palette.slots.count, id: \.self) { slot in
                                Button { colorSlot = slot } label: {
                                    Circle()
                                        .fill(Palette.color(slot: slot))
                                        .frame(width: 26, height: 26)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: colorSlot == slot ? 2 : 0).padding(-4))
                                        .frame(maxWidth: .infinity, minHeight: 52)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Colour \(slot + 1)")
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    PanelSection("Icon") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                            ForEach(GoalSymbols.all, id: \.self) { candidate in
                                Button { symbol = candidate } label: {
                                    Image(systemName: candidate)
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(candidate == symbol ? Palette.color(slot: colorSlot).opacity(0.25) : .clear)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(candidate)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle(goal == nil ? "New goal" : "Edit goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty || target == nil)
                        .accessibilityIdentifier("saveGoalButton")
                }
            }
            .onChange(of: picked) {
                guard let picked else { return }
                loadingPhoto = true
                Task {
                    if let data = try? await picked.loadTransferable(type: Data.self), let prepared = GoalPhotos.prepare(data) {
                        photo = prepared
                    }
                    loadingPhoto = false
                }
            }
            .onAppear { if goal == nil { nameFocused = true } }
        }
        .presentationBackground(Theme.canvas)
    }

    /// The photo (or icon on its colour) with the buttons to change it.
    @ViewBuilder
    private var picture: some View {
        // The picker's label is built off the main actor.
        let pickTitle = photo == nil ? "Add a photo" : "Change"
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let photo, let image = UIImage(data: photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    SymbolField(symbol: symbol, colorSlot: colorSlot)
                }
            }
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay {
                if loadingPhoto { ProgressView().tint(.white) }
            }
            HStack(spacing: 8) {
                if photo != nil {
                    Button { photo = nil; picked = nil } label: {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Remove photo")
                }
                PhotosPicker(selection: $picked, matching: .images) {
                    Label(pickTitle, systemImage: "photo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(.white, in: Capsule())
                }
                .accessibilityIdentifier("goalPhotoButton")
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func save() {
        guard let target, !trimmedName.isEmpty else { return }
        let saved: Goal
        if let goal {
            saved = goal
        } else {
            saved = Goal(name: trimmedName, targetPaise: target, symbol: symbol, colorSlot: colorSlot)
            context.insert(saved)
        }
        saved.name = trimmedName
        saved.targetPaise = target
        saved.symbol = symbol
        saved.colorSlot = colorSlot
        saved.photo = photo
        if hasDate {
            saved.arriveBy = Calendar.current.startOfDay(for: arriveBy).addingTimeInterval(12 * 3600)
            saved.arriveByIsEstimate = false
        } else if goal == nil || !saved.arriveByIsEstimate {
            // No date of your own: schedule it for when your pace says.
            let open = goals.filter { !$0.isFinished && $0.uuid != saved.uuid } + [saved]
            saved.arriveBy = Goals.forecast(open, entries: entries, balance: balance.starting).arrivals[saved.uuid]
            saved.arriveByIsEstimate = true
        }
        try? context.save()
        dismiss()
    }
}
