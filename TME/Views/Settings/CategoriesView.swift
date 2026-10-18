import SwiftData
import SwiftUI

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @State private var editing: LedgerCategory?
    @State private var addingFlow: Flow?

    var body: some View {
        List {
            ForEach(Flow.allCases) { flow in
                let list = categories.filter { $0.flow == flow }
                Section(flow == .expense ? "Expenses" : "Income") {
                    ForEach(list) { category in
                        Button { editing = category } label: {
                            HStack(spacing: 12) {
                                CategoryIcon(category: category, size: 32)
                                Text(category.name)
                                Spacer()
                                Text("\(category.entries.count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(list[index]) }
                        try? context.save()
                        TagNotifications.registerCategories(in: context)
                    }
                    Button("Add \(flow == .expense ? "expense" : "income") category", systemImage: "plus") {
                        addingFlow = flow
                    }
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
    private let flow: Flow

    static let symbols = [
        "fork.knife", "cup.and.saucer", "cart", "bag", "car", "bus", "tram", "airplane", "fuelpump",
        "house", "bolt", "drop", "wifi", "phone", "tv", "popcorn", "gamecontroller", "music.note",
        "cross.case", "pills", "heart", "dumbbell", "book", "graduationcap", "gift", "pawprint",
        "tshirt", "scissors", "wrench.and.screwdriver", "creditcard", "banknote", "indianrupeesign.circle",
        "building.columns", "chart.line.uptrend.xyaxis", "arrow.uturn.backward.circle", "plus.circle",
        "ellipsis.circle", "tag",
    ]

    init(category: LedgerCategory?, flow: Flow) {
        self.category = category
        self.flow = flow
        _name = State(initialValue: category?.name ?? "")
        _symbol = State(initialValue: category?.symbol ?? "tag")
        _colorSlot = State(initialValue: category?.colorSlot ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        CategoryIcon(symbol: symbol, colorSlot: colorSlot, size: 44)
                        TextField("Name", text: $name)
                            .font(.title3)
                            .accessibilityIdentifier("categoryNameField")
                    }
                }
                Section("Colour") {
                    HStack(spacing: 10) {
                        ForEach(-1..<Palette.slots.count, id: \.self) { slot in
                            Button { colorSlot = slot } label: {
                                Circle()
                                    .fill(Palette.color(slot: slot))
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().strokeBorder(.primary, lineWidth: colorSlot == slot ? 2 : 0).padding(-3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(slot == -1 ? "Gray" : "Colour \(slot + 1)")
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 12) {
                        ForEach(Self.symbols, id: \.self) { candidate in
                            Button { symbol = candidate } label: {
                                Image(systemName: candidate)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(candidate == symbol ? Palette.color(slot: colorSlot).opacity(0.2) : .clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
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
        if let category {
            category.name = trimmed
            category.symbol = symbol
            category.colorSlot = colorSlot
        } else {
            context.insert(LedgerCategory(
                name: trimmed,
                symbol: symbol,
                flow: flow,
                colorSlot: colorSlot,
                sortOrder: (allCategories.map(\.sortOrder).max() ?? 0) + 1
            ))
        }
        try? context.save()
        TagNotifications.registerCategories(in: context)
        dismiss()
    }
}
