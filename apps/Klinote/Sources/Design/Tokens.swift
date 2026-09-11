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

enum KlinoteColor {
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

enum KlinoteFont {
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

    // MARK: Named roles
    //
    // The sizes below were already being used consistently — every one of the
    // sixteen `ui(12)`s in this product is a caption or an explanation — but
    // they were reached by typing a number, which is how `ui(11)` and `ui(13)`
    // appear next to them one release later. A role with a name cannot drift.
    // These are the only sizes the interface uses, and DESIGN.md lists them.

    /// Explanatory text under a control, a promise, or an error. 12 pt.
    static func caption(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 12, weight: weight)
    }

    /// A heading inside a sheet or an empty state. 15 pt.
    static func panelHeading(_ weight: Font.Weight = .semibold) -> Font {
        .system(size: 15, weight: weight)
    }

    /// One thing a patient or clinician said, in the evidence margin. 12.5 pt:
    /// deliberately a half step under the note body so quoted speech reads as
    /// source material rather than as the note itself.
    static func utterance(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 12.5, weight: weight)
    }

    /// The line under the wordmark on the first-run and About screens.
    static func tagline() -> Font {
        .system(size: 16, weight: .medium, design: .serif)
    }

    /// Chip text and sentence numbers: the smallest step in the product.
    static func micro(_ weight: Font.Weight = .semibold) -> Font {
        .system(size: 9, weight: weight)
    }

    /// Counts and row metadata in the margins. 10 pt, tabular.
    static func microData() -> Font {
        .system(size: 10, weight: .regular, design: .monospaced)
    }

    /// The recording clock and menu-bar titles. 12 pt, tabular.
    static func clock() -> Font {
        .system(size: 12, weight: .regular, design: .monospaced)
    }

    /// Body text at emphasis: a button label, a selected sentence's heading.
    /// DESIGN.md's "Emphasis" row, which had been written as `ui(13, .semibold)`
    /// in four places.
    static func emphasis() -> Font {
        .system(size: 13, weight: .semibold)
    }

    /// The document's own title, at the top of the letter. 19 pt.
    static func documentTitle() -> Font {
        .system(size: 19, weight: .semibold, design: .serif)
    }

    /// The number in the margin that ties a sentence to its evidence.
    static func microNumber() -> Font {
        .system(size: 9, weight: .regular, design: .monospaced)
    }

    /// Document text that is not the note: unfiled statements, a suggested
    /// name, a transcript being pasted. One step under the note body so it
    /// reads as material under discussion rather than as the record.
    static func documentMinor() -> Font {
        .system(size: 13, weight: .regular, design: .serif)
    }
}

enum KlinoteMetrics {
    // MARK: Layout scale — 4 · 8 · 12 · 16 · 24 · 32 · 48

    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let space48: CGFloat = 48

    // MARK: Inline scale
    //
    // The layout scale starts at 4. Chips, a field label against its value, and
    // the inside of a row need finer steps, and those were being written as
    // raw 1, 2, 5 and 6 in a dozen places — which is indistinguishable from
    // carelessness to anyone reading the screen. Two named steps instead, so
    // every gap in the product comes from a decision rather than a mood.

    static let inline2: CGFloat = 2
    static let inline6: CGFloat = 6

    /// The 2 pt mark that carries selection and the letterhead. Recurring, so
    /// named; nothing else in the product may be 2 pt.
    static let ruleWidth: CGFloat = 2

    // MARK: Radii — 10 · 8 · 4 · 2, and nothing else

    static let radiusDocument: CGFloat = 10
    static let radiusModule: CGFloat = 8
    static let radiusChip: CGFloat = 4
    static let radiusLamp: CGFloat = 2

    // MARK: Modal chrome
    //
    // One sheet family, so one width and one inset. These were 520/620 and
    // 24/32 across three sibling sheets, which reads as three products.

    static let sheetWidth: CGFloat = 620
    static let sheetInset: CGFloat = 24
    static let sheetMinHeight: CGFloat = 220

    // MARK: Symbol sizes — 11 · 13, and nothing else

    static let iconSmall: CGFloat = 11
    static let iconRegular: CGFloat = 13

    /// Tracking for the wordmark, as a fraction of its size. The three copies
    /// of the mark had hand-tuned -0.4, -0.6 and -0.8, which is this ratio
    /// rounded; one component now derives it.
    static let wordmarkTracking: CGFloat = -0.03

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
    var klinoteReduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }
}
