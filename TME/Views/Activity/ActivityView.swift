import SwiftData
import SwiftUI
import TMECore

struct ActivityView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    @State private var addingFlow: Flow?
    @State private var editing: LedgerEntry?
    @State private var editingBalance = false
    private var balance = BalanceReader()

    private var uncategorised: [LedgerEntry] { entries.filter { $0.category == nil } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MonthSummary(
                        stats: MonthStats(entries: entries, month: .now),
                        balance: balance.starting?.current(with: entries)
                    ) {
                        editingBalance = true
                    }
                }

                if !uncategorised.isEmpty {
                    Section {
                        ForEach(uncategorised) { entry in
                            UncategorisedRow(entry: entry, categories: chipCategories(for: entry.flow)) { category in
                                withAnimation { Tagging.assign(category, to: entry, in: context) }
                                TagNotifications.registerCategories(in: context)
                            } onOpen: {
                                editing = entry
                            }
                        }
                        .onDelete { delete(uncategorised, at: $0) }
                    } header: {
                        Text("Needs a category")
                    } footer: {
                        Text("Tap a category. Next time this merchant is filed for you.")
                    }
                }

                ForEach(dayGroups, id: \.day) { group in
                    Section(group.title) {
                        ForEach(group.entries) { entry in
                            Button { editing = entry } label: { EntryRow(entry: entry) }
                                .buttonStyle(.plain)
                        }
                        .onDelete { delete(group.entries, at: $0) }
                    }
                }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No entries yet", systemImage: "indianrupeesign.circle")
                    } description: {
                        Text("Add your first expense with the + button, or set up SMS auto-logging in Settings.")
                    }
                }
            }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Add expense", systemImage: "minus.circle") { addingFlow = .expense }
                        Button("Add income", systemImage: "plus.circle") { addingFlow = .income }
                    } label: {
                        Label("Add", systemImage: "plus")
                    } primaryAction: {
                        addingFlow = .expense
                    }
                    .accessibilityIdentifier("addButton")
                }
            }
            .sheet(item: $addingFlow) { flow in
                QuickAddView(initialFlow: flow)
            }
            .sheet(item: $editing) { entry in
                EntryEditView(entry: entry)
            }
            .sheet(isPresented: $editingBalance) {
                StartingBalanceEditor()
            }
            .onChange(of: router.entryToTag, initial: true) { _, id in
                guard let id else { return }
                editing = entries.first { $0.uuid == id }
                router.entryToTag = nil
            }
        }
    }

    private func chipCategories(for flow: Flow) -> [LedgerCategory] {
        Tagging.byUse(categories.filter { $0.flow == flow })
    }

    private var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        let filed = entries.filter { $0.category != nil }
        return Dictionary(grouping: filed) { calendar.startOfDay(for: $0.date) }
            .map { DayGroup(day: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    private func delete(_ list: [LedgerEntry], at offsets: IndexSet) {
        for index in offsets { context.delete(list[index]) }
        try? context.save()
    }
}

private struct DayGroup {
    let day: Date
    let entries: [LedgerEntry]

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

/// Your balance (once a starting balance is set) and this month at a glance.
private struct MonthSummary: View {
    let stats: MonthStats
    let balance: Int?
    let editBalance: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let balance {
                Button(action: editBalance) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Balance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Rupees.format(paise: balance))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("balanceValue")
                .accessibilityHint("Change your starting balance")
                Divider()
            }

            Text(stats.month.formatted(.dateTime.month(.wide)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Rupees.format(paise: stats.spentPaise))
                        .font(balance == nil
                              ? .system(.largeTitle, design: .rounded, weight: .bold)
                              : .system(.title2, design: .rounded, weight: .semibold))
                        .accessibilityIdentifier("monthSpent")
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Income")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Rupees.format(paise: stats.incomePaise))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.income)
                }
            }
            .accessibilityElement(children: .combine)

            if balance == nil {
                Button("Set starting balance", systemImage: "plus.circle", action: editBalance)
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("setBalanceButton")
            }
        }
        .padding(.vertical, 4)
    }
}

/// An entry in the list: icon, what it was, when, and how much.
struct EntryRow: View {
    let entry: LedgerEntry

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: entry.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            AmountText(paise: entry.amountPaise, flow: entry.flow)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("entry-\(entry.title)")
    }

    private var subtitle: String {
        var parts: [String] = []
        if let category = entry.category { parts.append(category.name) }
        parts.append(entry.date.formatted(date: .omitted, time: .shortened))
        if entry.source == .sms { parts.append("from SMS") }
        return parts.joined(separator: " · ")
    }
}

/// An entry waiting for a category, with one-tap category buttons.
private struct UncategorisedRow: View {
    let entry: LedgerEntry
    let categories: [LedgerCategory]
    let onPick: (LedgerCategory) -> Void
    let onOpen: () -> Void
    @State private var naming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) { EntryRow(entry: entry) }
                .buttonStyle(.plain)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories) { category in
                        CategoryChip(category: category) { onPick(category) }
                    }
                    NewCategoryChip { naming = true }
                }
            }
            .scrollClipDisabled()
        }
        .padding(.vertical, 4)
        .newCategoryAlert(isPresented: $naming, flow: entry.flow) { onPick($0) }
    }
}
