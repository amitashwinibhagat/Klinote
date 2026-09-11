//
// Tokens.swift
//
// The design system from DESIGN.md, in code. If this file and DESIGN.md
// disagree, DESIGN.md wins and this file is wrong.
//
// Two rules encoded here:
//   1. Ground, text and selection resolve from macOS semantic colours, so
//      light mode, dark mode, increased contrast and the user's accent
//      preference all work without a second palette.
//   2. `ink`, `record` and `caution` mean exactly one thing each and are never
//      used decoratively.
//

import SwiftUI

enum NotaColor {
    // Ground
    static let desk = Color(nsColor: .windowBackgroundColor)
    static let document = Color(nsColor: .textBackgroundColor)
    static let margin = Color(nsColor: .underPageBackgroundColor)
    static let recessed = Color(nsColor: .controlBackgroundColor)

    // Line and text
    static let hairline = Color(nsColor: .separatorColor)
    static let primary = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let tertiary = Color(nsColor: .tertiaryLabelColor)
    static let accent = Color(nsColor: .controlAccentColor)

    /// The letterhead. Identity lives in the document, not the chrome.
    static let ink = dynamic(
        light: NSColor(srgbRed: 0.086, green: 0.196, blue: 0.310, alpha: 1),
        dark: NSColor(srgbRed: 0.612, green: 0.765, blue: 0.898, alpha: 1)
    )

    /// Solid fill for the primary action, with white text in both appearances.
    static let inkFill = dynamic(
        light: NSColor(srgbRed: 0.086, green: 0.196, blue: 0.310, alpha: 1),
        dark: NSColor(srgbRed: 0.180, green: 0.373, blue: 0.561, alpha: 1)
    )

    /// The act of recording. Nothing else, ever.
    static let record = dynamic(
        light: NSColor(srgbRed: 0.753, green: 0.224, blue: 0.169, alpha: 1),
        dark: NSColor(srgbRed: 1.000, green: 0.420, blue: 0.369, alpha: 1)
    )

    /// A missing required section. Nothing else, ever.
    static let caution = dynamic(
        light: NSColor(srgbRed: 0.698, green: 0.416, blue: 0.000, alpha: 1),
        dark: NSColor(srgbRed: 1.000, green: 0.702, blue: 0.251, alpha: 1)
    )

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

enum NotaFont {
    /// The letter itself.
    static func document(_ size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func ui(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Uppercase, tracked, small. Section tabs and field labels.
    static func tab(_ size: CGFloat = 11, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func label(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    /// Timestamps, encounter references, durations. Always tabular.
    static func data(_ size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum NotaMetrics {
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let space48: CGFloat = 48

    static let radiusDocument: CGFloat = 10
    static let radiusModule: CGFloat = 8
    static let radiusChip: CGFloat = 4

    static let marginColumnWidth: CGFloat = 320
    static let sidebarWidth: CGFloat = 260
    /// 68 characters at 14 pt New York, in points.
    static let documentMeasure: CGFloat = 560

    static let motionState: Double = 0.16
    static let motionLayout: Double = 0.22
    static let motionAssemble: Double = 0.42
}

// MARK: - Environment

private struct ReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when the user has asked for reduced motion. Read once, honour
    /// everywhere.
    var notaReduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }
}
