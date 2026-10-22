import SwiftData
import SwiftUI

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @State private var editing: LedgerCategory?
    @State private var addingFlow: Flow?

    @State private var deleting: LedgerCategory?

    var body: some View {
        PanelPage {
            ForEach(Flow.allCases) { flow in
                let list = categories.filter { $0.flow == flow }
                PanelSection(flow == .expense ? "Expenses" : "Income") {
                    ForEach(list) { category in
                        Button { editing = category } label: {
                            HStack(spacing: 12) {
                                CategoryIcon(category: category, size: 32)
                                Text(category.name)
                                    .foregroundStyle(.white)
                                Spacer()
                                if category.hasLimits {
                                    Image(systemName: "gauge.with.dots.needle.33percent")
                                        .font(.footnote)
                                        .foregroundStyle(Theme.textTertiary)
                                        .accessibilityLabel("Has limits")
                                }
                                Text("\(category.entries.count)")
                                    .foregroundStyle(Theme.textTertiary)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityIdentifier("category-\(category.name)")
                        .swipeToDelete { deleting = category }
                        .confirmCard(
                            isPresented: Binding(get: { deleting?.uuid == category.uuid }, set: { if !$0 { deleting = nil } }),
                            title: "Delete \(category.name)?",
                            message: category.entries.isEmpty ? nil : "Its \(category.entries.count) payments stay, waiting for a new category.",
                            actions: [PopupAction(title: "Delete", role: .destructive) {
                                context.delete(category)
                                try? context.save()
                                TagNotifications.registerCategories(in: context)
                            }]
                        )
                    }
                    Button { addingFlow = flow } label: {
                        PanelRow("Add \(flow == .expense ? "expense" : "income") category", symbol: "plus", tint: Theme.create)
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
        }
        .navigationTitle("Categories")
        .sheet(item: $editing) { category in
            CategoryEditor(category: category, flow: category.flow)
        }
        .sheet(item: $addingFlow) { flow in
            CategoryEditor(category: nil, flow: flow)
        }
    }
}

/// Name, icon and color for a new or existing category.
struct CategoryEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allCategories: [LedgerCategory]

    let category: LedgerCategory?
    @State private var name: String
    @State private var symbol: String
    @State private var colorSlot: Int
    @State private var flow: Flow
    /// Typed limits by period; empty is none.
    @State private var limits: [LimitPeriod: String]

    static let symbols = [
        "fork.knife", "cup.and.saucer", "cart", "bag", "car", "motorcycle", "bicycle", "bus", "tram", "airplane", "fuelpump",
        "house", "bolt", "drop", "wifi", "phone", "tv", "popcorn", "gamecontroller", "music.note",
        "cross.case", "pills", "heart", "dumbbell", "book", "graduationcap", "gift", "pawprint",
        "tshirt", "scissors", "wrench.and.screwdriver", "creditcard", "banknote", "indianrupeesign.circle",
        "building.columns", "chart.line.uptrend.xyaxis", "arrow.uturn.backward.circle", "plus.circle",
        "ellipsis.circle", "tag",
    ]

    init(category: LedgerCategory?, flow: Flow) {
        self.category = category
        _flow = State(initialValue: flow)
        _name = State(initialValue: category?.name ?? "")
        _symbol = State(initialValue: category?.symbol ?? "tag")
        _colorSlot = State(initialValue: category?.colorSlot ?? 0)
        var typed: [LimitPeriod: String] = [:]
        for period in LimitPeriod.allCases {
            let paise = category?.limit(for: period) ?? 0
            typed[period] = paise > 0 ? SplitDraft.typed(paise) : ""
        }
        _limits = State(initialValue: typed)
    }

    var body: some View {
        NavigationStack {
            PanelPage {
                PanelSection {
                    HStack(spacing: 12) {
                        CategoryIcon(symbol: symbol, colorSlot: colorSlot, size: 44)
                        TextField("Name", text: $name)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .accessibilityIdentifier("categoryNameField")
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 64)
                    if category == nil {
                        WordSwitch(selection: $flow, options: Flow.allCases.map { ($0, $0.title) })
                            .padding(.vertical, 4)
                    }
                }
                if flow == .expense {
                    PanelSection(
                        "Limits",
                        footer: Text("When a payment goes over, TME tells you, with how much later it makes your goal. Payments spent from a goal don't count.")
                    ) {
                        ForEach(LimitPeriod.allCases) { period in
                            HStack {
                                Text(period.title)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("₹")
                                    .foregroundStyle(Theme.textTertiary)
                                TextField("No limit", text: Binding(get: { limits[period] ?? "" }, set: { limits[period] = $0 }))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: 120)
                                    .accessibilityIdentifier("limit-\(period.rawValue)")
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                        }
                    }
                }
                PanelSection("Colour") {
                    HStack(spacing: 0) {
                        ForEach(-1..<Palette.slots.count, id: \.self) { slot in
                            Button { colorSlot = slot } label: {
                                Circle()
                                    .fill(Palette.color(slot: slot))
                                    .frame(width: 26, height: 26)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: colorSlot == slot ? 2 : 0).padding(-4))
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(slot == -1 ? "Gray" : "Colour \(slot + 1)")
                        }
                    }
                    .padding(.horizontal, 8)
                }
                PanelSection("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                        ForEach(Self.symbols, id: \.self) { candidate in
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
            .navigationTitle(category == nil ? "New category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved: LedgerCategory
        if let category {
            saved = category
            category.name = trimmed
            category.symbol = symbol
            category.colorSlot = colorSlot
        } else {
            saved = LedgerCategory(
                name: trimmed,
                symbol: symbol,
                flow: flow,
                colorSlot: colorSlot,
                sortOrder: (allCategories.map(\.sortOrder).max() ?? 0) + 1
            )
            context.insert(saved)
        }
        for period in LimitPeriod.allCases {
            let paise = flow == .expense ? EntryWriter.paise(fromTyped: limits[period] ?? "") ?? 0 : 0
            saved.setLimit(paise, for: period)
        }
        try? context.save()
        TagNotifications.registerCategories(in: context)
        dismiss()
    }
}
