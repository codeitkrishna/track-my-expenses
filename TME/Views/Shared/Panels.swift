import SwiftUI

// The app's own grouped screens, in place of the system's List and Form:
// a matte page, sections as raised cards with a small spaced caption over
// them, and rows at least 52 points tall.

/// A scrolling page on the matte canvas, never wider than the screen.
struct PanelPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .containerRelativeFrame(.horizontal)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas)
    }
}

/// A caption, a card of rows with hairlines between them, and a note under it.
struct PanelSection<Content: View>: View {
    var title: String?
    var footer: Text?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, footer: Text? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                MonoLabel(title)
                    .padding(.horizontal, 4)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        row
                        if index < rows.count - 1 {
                            Rectangle()
                                .fill(Theme.hairline)
                                .frame(height: 0.5)
                                .padding(.leading, 16)
                        }
                    }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if let footer {
                footer
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 26)
    }
}

/// A row: an icon, a title, and whatever goes on the right.
struct PanelRow<Trailing: View>: View {
    var symbol: String?
    var tint: Color = .white
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, symbol: String? = nil, tint: Color = .white, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            Text(title)
                .foregroundStyle(tint)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// The arrow on a row that opens another page.
struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textTertiary)
    }
}

/// "Label    value" in a section.
struct PanelValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

/// A paragraph of text inside a section.
struct PanelText: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Two choices as words with a line under the chosen one, as at the top of
/// the payment composer. In place of a segmented control.
struct WordSwitch<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @Namespace private var line

    var body: some View {
        HStack(spacing: 28) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(.snappy) { selection = option.value }
                } label: {
                    VStack(spacing: 7) {
                        Text(option.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selection == option.value ? .white : Theme.textTertiary)
                        ZStack {
                            if selection == option.value {
                                Capsule().fill(.white).matchedGeometryEffect(id: "line", in: line)
                            }
                        }
                        .frame(width: 18, height: 2)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
