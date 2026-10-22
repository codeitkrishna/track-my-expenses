import SwiftUI
import TMECore
import UIKit

/// Letters on a departure board: each one sits on its own flap and flips
/// through the alphabet to its new value, a beat after the one before.
struct SplitFlapText: View {
    let text: String
    var color: Color = .white
    var size: CGFloat = 15

    var body: some View {
        let letters = Array(text.uppercased())
        HStack(spacing: size * 0.12) {
            ForEach(letters.indices, id: \.self) { index in
                FlapCell(target: letters[index], delay: Double(index) * 0.03, color: color, size: size)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.lowercased().localizedCapitalized)
    }
}

private struct FlapCell: View {
    let target: Character
    let delay: Double
    let color: Color
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Character = " "
    @State private var angle: Double = 0

    /// The order the flaps turn in.
    private static let drum = Array(" ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    /// No more than this many turns per change, however far apart.
    private static let maxTurns = 6

    var body: some View {
        let isSpace = shown == " "
        Text(String(shown))
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: size * 0.82, height: size * 1.5)
            .background(RoundedRectangle(cornerRadius: size * 0.16).fill(Color(white: isSpace && target == " " ? 0.07 : 0.12)))
            .overlay {
                // The split between the top and bottom flap.
                Rectangle().fill(Color.black.opacity(0.75)).frame(height: max(1, size * 0.06))
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .task(id: target) { await turn(to: target) }
    }

    private func turn(to target: Character) async {
        guard shown != target else { return }
        if reduceMotion {
            shown = target
            return
        }
        try? await Task.sleep(for: .seconds(delay))
        for letter in Self.path(from: shown, to: target) {
            withAnimation(.easeIn(duration: 0.035)) { angle = -90 }
            try? await Task.sleep(for: .milliseconds(35))
            shown = letter
            angle = 90
            withAnimation(.easeOut(duration: 0.04)) { angle = 0 }
            try? await Task.sleep(for: .milliseconds(40))
            if Task.isCancelled { break }
        }
        shown = target
        angle = 0
    }

    /// The last few letters on the drum on the way to `target`; a letter
    /// that isn't on the drum just drops into place.
    private static func path(from start: Character, to target: Character) -> [Character] {
        guard let from = drum.firstIndex(of: start), let to = drum.firstIndex(of: target) else { return [target] }
        var steps: [Character] = []
        var index = from
        while index != to {
            index = (index + 1) % drum.count
            steps.append(drum[index])
        }
        return Array(steps.suffix(maxTurns))
    }
}

/// A goal's picture: blurred and washed out while there's a long way to
/// go, sharp once it's saved. Without a photo, its symbol on its colour.
struct GoalPicture: View {
    let goal: Goal
    /// How sharp to draw it, 0...1.
    let progress: Double

    var body: some View {
        let radius = 26 * pow(1 - min(1, max(0, progress)), 1.3)
        Color.clear
            .overlay {
                if let image = GoalPhotos.image(for: goal) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    SymbolField(symbol: goal.symbol, colorSlot: goal.colorSlot)
                }
            }
            .blur(radius: radius, opaque: true)
            .saturation(0.3 + 0.7 * progress)
            .clipped()
            .animation(.easeInOut(duration: 0.9), value: progress)
            .accessibilityHidden(true)
    }
}

/// A goal without a photo: its symbol, large, over a wash of its colour.
struct SymbolField: View {
    let symbol: String
    let colorSlot: Int

    var body: some View {
        let tint = Palette.color(slot: colorSlot)
        ZStack {
            LinearGradient(colors: [tint.opacity(0.55), tint.opacity(0.12)], startPoint: .topTrailing, endPoint: .bottomLeading)
            Image(systemName: symbol)
                .font(.system(size: 96, weight: .light))
                .foregroundStyle(tint.mix(with: .white, by: 0.35))
                .offset(x: 70, y: -18)
        }
        .background(Theme.surface)
    }
}

/// Decoded photos, so scrolling doesn't decode them again.
@MainActor
enum GoalPhotos {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for goal: Goal) -> UIImage? {
        guard let data = goal.photo else { return nil }
        let key = "\(goal.uuid.uuidString)-\(data.count)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Shrinks a picked photo to at most 1400 points on its long side.
    static func prepare(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1400 / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.82)
    }
}

/// What the board shows for a goal, ready to print.
struct BoardText {
    let label: String
    let value: String
    var valueColor: Color = .white
    /// The second line: on time, late, early.
    var remark: String?
    var remarkColor: Color = Theme.textSecondary

    init(_ board: GoalBoard, now: Date = .now) {
        switch board {
        case .finished(let date):
            label = "Done"
            value = BoardText.date(date, now: now)
            valueColor = Theme.income
        case .spending(let until):
            label = "Status"
            value = "Spending"
            remark = until > now.addingTimeInterval(365 * 86_400) ? "Until you stop" : "Until \(BoardText.date(until, now: now))"
        case .arrived:
            label = "Status"
            value = "Arrived"
            valueColor = Theme.income
        case .boarding:
            label = "Status"
            value = "Boarding"
            valueColor = Theme.income
            remark = "You have it now"
            remarkColor = Theme.income
        case .due(let date, let late):
            label = "Arrives"
            value = BoardText.date(date, now: now)
            if let late {
                switch late {
                case 1...: remark = late == 1 ? "Delayed 1 day" : "Delayed \(late) days"; remarkColor = Theme.expense
                case ...(-1): remark = late == -1 ? "Early 1 day" : "Early \(-late) days"; remarkColor = Theme.income
                default: remark = "On time"; remarkColor = Theme.income
                }
            }
        case .learning:
            label = "Arrives"
            value = "---"
            remark = "Learning your pace"
        case .stalled:
            label = "Arrives"
            value = "---"
            remark = "Stalled"
            remarkColor = Theme.expense
        }
    }

    /// "14 MAR", or "14 MAR 27" in another year.
    static func date(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let style = sameYear
            ? Date.FormatStyle().day(.twoDigits).month(.abbreviated)
            : Date.FormatStyle().day(.twoDigits).month(.abbreviated).year(.twoDigits)
        return date.formatted(style.locale(Locale(identifier: "en_GB"))).uppercased()
    }
}

/// The amounts that matter for where a goal is: saved while saving, left
/// once it's being spent.
struct GoalAmounts {
    let headline: Int
    let label: String
    let detail: String

    init(_ goal: Goal) {
        let target = Rupees.format(paise: goal.targetPaise)
        if goal.hasSpends {
            headline = goal.heldPaise
            label = "Left"
            detail = "\(Rupees.format(paise: goal.spentPaise)) spent of \(Rupees.format(paise: goal.savedPaise))"
        } else if goal.isReached {
            headline = goal.savedPaise
            label = "Saved"
            detail = "Fully saved"
        } else {
            headline = goal.savedPaise
            label = "Saved"
            detail = "of \(target) · \(Rupees.format(paise: goal.toGoPaise)) to go"
        }
    }
}

/// Symbols that suit things people save for.
enum GoalSymbols {
    static let all = [
        "airplane", "beach.umbrella", "mountain.2", "tent", "car", "motorcycle", "scooter", "bicycle", "house",
        "sofa", "laptopcomputer", "iphone", "camera", "headphones", "gamecontroller", "guitars", "watch.analog",
        "gift", "heart", "graduationcap", "book", "dumbbell", "pawprint", "shield", "star",
    ]
}
