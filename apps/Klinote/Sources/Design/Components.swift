//
// Components.swift
//
// The shared vocabulary. Every interactive component here implements its full
// state set; a control that ships with half of them does not ship.
//

import SwiftUI

// MARK: - Rules

/// The only 2 pt rule in the product. It marks the letterhead.
struct LetterheadRule: View {
    var body: some View {
        Rectangle()
            .fill(KlinoteColor.ink.opacity(0.22))
            .frame(height: 2)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(KlinoteColor.hairline)
            .frame(height: 1)
    }
}

struct DashedRule: View {
    var body: some View {
        Rectangle()
            .fill(KlinoteColor.caution)
            .frame(height: 1)
            .overlay(
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(KlinoteColor.caution)
            )
    }
}

// MARK: - Labels

/// Uppercase, tracked, small. A section tab or a field label.
struct TabLabel: View {
    let text: String
    var tone: Color = KlinoteColor.secondary

    var body: some View {
        Text(text.uppercased())
            .font(KlinoteFont.tab())
            .tracking(0.6)
            .foregroundStyle(tone)
    }
}

struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(KlinoteFont.label())
            .foregroundStyle(KlinoteColor.secondary)
    }
}

// MARK: - Section state

enum SectionState {
    case filled
    case emptyOptional
    case missingRequired
    case edited

    var word: String? {
        switch self {
        case .filled: nil
        case .emptyOptional: "optional"
        case .missingRequired: "missing"
        case .edited: "edited"
        }
    }

    var tone: Color {
        switch self {
        case .filled: KlinoteColor.secondary
        case .emptyOptional: KlinoteColor.tertiary
        case .missingRequired: KlinoteColor.caution
        case .edited: KlinoteColor.ink
        }
    }
}

/// A section header: the tab, its state word, and a rule. State is a word
/// first and a colour second, and never colour alone.
struct SectionHeader: View {
    let title: String
    let state: SectionState

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space8) {
            HStack(alignment: .firstTextBaseline, spacing: KlinoteMetrics.space8) {
                TabLabel(text: title, tone: state == .missingRequired ? KlinoteColor.caution : KlinoteColor.ink)
                if let word = state.word {
                    Text(word)
                        .font(KlinoteFont.label())
                        .foregroundStyle(state.tone)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: KlinoteMetrics.radiusChip, style: .continuous)
                                .strokeBorder(state.tone.opacity(0.5), lineWidth: 1)
                        )
                }
                Spacer(minLength: 0)
            }
            if state == .missingRequired {
                DashedRule()
            } else {
                Hairline()
            }
        }
    }
}

// MARK: - Primary action

struct KlinotePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(KlinoteFont.ui(13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, KlinoteMetrics.space16)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(KlinoteColor.inkFill)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

// MARK: - Recording

/// The lamp. One red thing in the interface, and it means one thing.
struct RecordingLamp: View {
    let isRecording: Bool
    let isPaused: Bool
    @Environment(\.klinoteReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(isPaused ? Color.clear : KlinoteColor.record)
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(KlinoteColor.record, lineWidth: 1.5)
            )
            .frame(width: 10, height: 10)
            .opacity(isRecording && !isPaused && pulse && !reduceMotion ? 0.45 : 1)
            .animation(
                reduceMotion || !isRecording || isPaused
                    ? nil
                    : .easeInOut(duration: 2).repeatForever(autoreverses: true),
                value: pulse
            )
            .onAppear { pulse = true }
            .accessibilityLabel(isPaused ? "Recording paused" : (isRecording ? "Recording" : "Not recording"))
    }
}

/// The trace: a graticule with a live signal. It reports; it does not
/// decorate. Under Reduce Motion it becomes a static level meter.
struct TraceView: View {
    let level: Double
    let isActive: Bool
    var samples: [Double] = []
    var isPaused: Bool = false
    var reduceMotion: Bool = false

    var body: some View {
        Canvas { context, size in
            drawGraticule(in: &context, size: size)

            guard isActive || isPaused else { return }

            if reduceMotion {
                drawLevelMeter(in: &context, size: size)
            } else {
                drawTrace(in: &context, size: size)
            }
        }
        .opacity(isPaused ? 0.45 : 1)
        .accessibilityHidden(true)
        .drawingGroup()
    }

    private func drawGraticule(in context: inout GraphicsContext, size: CGSize) {
        let step: CGFloat = 8
        var grid = Path()
        var x: CGFloat = 0
        while x <= size.width {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        var y: CGFloat = 0
        while y <= size.height {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        context.stroke(grid, with: .color(KlinoteColor.hairline.opacity(0.4)), lineWidth: 0.5)
    }

    private func drawTrace(in context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        let mid = size.height / 2
        let amplitude = max(1, size.height * 0.42)
        let source = samples.isEmpty ? [level] : samples
        let last = CGFloat(max(source.count - 1, 1))
        for (index, sample) in source.enumerated() {
            let x = CGFloat(index) / last * size.width
            let y = mid - CGFloat(sample) * amplitude
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.stroke(path, with: .color(KlinoteColor.record), lineWidth: 1.5)
    }

    private func drawLevelMeter(in context: inout GraphicsContext, size: CGSize) {
        let bars = 8
        let gap: CGFloat = 2
        let barWidth = (size.width - gap * CGFloat(bars - 1)) / CGFloat(bars)
        let lit = Int((Double(bars) * min(1, max(0, level))).rounded())
        for index in 0..<bars {
            let rect = CGRect(
                x: CGFloat(index) * (barWidth + gap),
                y: size.height * 0.15,
                width: barWidth,
                height: size.height * 0.7
            )
            let colour = index < lit ? KlinoteColor.record : KlinoteColor.hairline.opacity(0.4)
            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(colour))
        }
    }
}

// MARK: - Empty state

/// Empty states teach the interface. They never say "nothing here".
struct EmptyState: View {
    let title: String
    let message: String
    var action: (title: String, handler: () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: KlinoteMetrics.space12) {
            Text(title)
                .font(KlinoteFont.ui(15, weight: .semibold))
                .foregroundStyle(KlinoteColor.primary)
            Text(message)
                .font(KlinoteFont.ui())
                .foregroundStyle(KlinoteColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.title, action: action.handler)
                    .buttonStyle(KlinotePrimaryButtonStyle())
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
    }
}
