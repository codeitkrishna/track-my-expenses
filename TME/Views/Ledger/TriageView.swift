import SwiftData
import SwiftUI
import TMECore

/// Payments waiting for a category, one card at a time: tap where it goes
/// and the next one slides up.
struct TriageView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<LedgerEntry> { $0.category == nil }, sort: \LedgerEntry.date, order: .reverse)
    private var waiting: [LedgerEntry]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    /// Skipped payments go to the back of the queue.
    @State private var skipped: [UUID] = []
    /// The top card under a finger.
    @State private var drag: CGSize = .zero
    @State private var filed = 0
    @State private var naming = false

    private var queue: [LedgerEntry] {
        waiting.filter { !skipped.contains($0.uuid) } + skipped.compactMap { id in waiting.first { $0.uuid == id } }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let current = queue.first {
                    ZStack(alignment: .top) {
                        ForEach(Array(queue.prefix(3).enumerated()), id: \.element.id) { index, entry in
                            let isTop = index == 0
                            TriageCard(entry: entry, isBehind: !isTop)
                                .scaleEffect(1 - CGFloat(index) * 0.06, anchor: .top)
                                .offset(y: CGFloat(index) * -12)
                                .offset(isTop ? drag : .zero)
                                .rotationEffect(.degrees(isTop ? Double(drag.width) / 22 : 0), anchor: .bottom)
                                .opacity(isTop ? 1 : 0.55 - Double(index) * 0.2)
                                .zIndex(Double(-index))
                                .gesture(isTop ? skipDrag(current) : nil)
                                .transition(.asymmetric(insertion: .opacity, removal: .fling))
                        }
                    }
                    .padding(.top, 36)

                    VStack(alignment: .leading, spacing: 14) {
                        MonoLabel(current.flow == .expense ? "Spent on" : "Came in as")
                        FlowLayout(spacing: 8) {
                            ForEach(Tagging.byUse(categories.filter { $0.flow == current.flow })) { category in
                                CategoryChip(category: category, idPrefix: "tag") { file(current, under: category) }
                            }
                            NewCategoryChip(identifier: "tagNewCategory") { naming = true }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 34)
                    .id(current.uuid)
                    .transition(.opacity)
                    .newCategoryAlert(isPresented: $naming, flow: current.flow) { file(current, under: $0) }

                    Spacer()
                    if queue.count > 1 {
                        Button("Skip for now") { skip(current, toward: -1) }
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.bottom, 12)
                        .accessibilityIdentifier("skipButton")
                    }
                } else {
                    AllFiled(count: filed)
                        .task {
                            try? await Task.sleep(for: .seconds(0.9))
                            dismiss()
                        }
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("closeTriage")
                }
                ToolbarItem(placement: .principal) {
                    if !queue.isEmpty {
                        MonoLabel(queue.count == 1 ? "Last one" : "\(queue.count) to file", color: Theme.textSecondary)
                            .contentTransition(.numericText())
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.success, trigger: filed)
        }
        .presentationBackground(Theme.canvas)
    }

    /// Files just the card on top (not the receiver's other waiting
    /// payments) and flings it away; the next one rises into place.
    private func file(_ entry: LedgerEntry, under category: LedgerCategory) {
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
            Tagging.assign(category, to: entry, in: context, alsoFileOthers: false)
            skipped.removeAll { $0 == entry.uuid }
        }
        TagNotifications.registerCategories(in: context)
        filed += 1
    }

    /// Drag the top card aside to skip it.
    private func skipDrag(_ entry: LedgerEntry) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { drag = CGSize(width: $0.translation.width, height: $0.translation.height * 0.2) }
            .onEnded { value in
                if abs(value.translation.width) > 110 {
                    skip(entry, toward: value.translation.width > 0 ? 1 : -1)
                } else {
                    withAnimation(.spring(duration: 0.35, bounce: 0.3)) { drag = .zero }
                }
            }
    }

    /// Sends the card off-screen, then to the back of the queue.
    private func skip(_ entry: LedgerEntry, toward direction: CGFloat) {
        withAnimation(.easeIn(duration: 0.2)) { drag = CGSize(width: direction * 520, height: 0) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { drag = .zero }
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) { skipped.append(entry.uuid) }
        }
    }
}

/// The payment being filed: who, how much, when.
private struct TriageCard: View {
    let entry: LedgerEntry
    /// Waiting behind the top card: just its edge shows.
    var isBehind = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel(entry.title, color: Theme.textSecondary)
                Spacer()
                MonoLabel(source)
            }
            HeroAmount(paise: entry.amountPaise, size: 52, color: entry.flow == .income ? Theme.income : .white)
            Text(entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(22)
        .opacity(isBehind ? 0 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityHidden(isBehind)
        .accessibilityIdentifier(isBehind ? "" : "triageCard")
    }

    private var source: String {
        var parts: [String] = [entry.flow == .income ? "In" : "Out"]
        if entry.source == .sms { parts.append("SMS") }
        if entry.source == .scan { parts.append("Scanned") }
        if let tail = entry.accountTail { parts.append("••\(tail)") }
        return parts.joined(separator: " · ")
    }
}

private struct AllFiled: View {
    let count: Int

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: count)
            Text(count == 1 ? "Filed" : "All filed")
                .font(.title3.weight(.light))
                .foregroundStyle(.white)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("allFiled")
    }
}

/// A filed card leaving: out to the side with a slight tilt, like a card
/// tossed off the stack.
private struct Fling: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: -460 * progress, y: -24 * progress)
            .rotationEffect(.degrees(-14 * Double(progress)), anchor: .bottom)
            .opacity(1 - Double(progress) * 0.5)
    }
}

private extension AnyTransition {
    static var fling: AnyTransition {
        .modifier(active: Fling(progress: 1), identity: Fling(progress: 0))
    }
}
