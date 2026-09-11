//
// Glass.swift
//
// macOS 26/27 Liquid Glass, used as chrome — never as the letter.
// The document plane stays opaque paper. Toolbars, the recording strip,
// sidebar and inspector take the system material so Klinote sits in the OS
// instead of on top of it.
//
// Reduce Transparency falls back to an opaque desk. Older macOS falls back
// to regularMaterial. No hand-rolled blur.
//

import SwiftUI

extension View {
    /// Liquid Glass on a continuous rounded rect. Interactive so pointer
    /// hover refracts — the macOS 27 control language.
    @ViewBuilder
    func klinoteGlass(
        cornerRadius: CGFloat = 12,
        tint: Color? = nil,
        interactive: Bool = true
    ) -> some View {
        modifier(
            NotaGlassModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                interactive: interactive
            )
        )
    }

    /// Columns and the desk around the letter are opaque. Glass belongs on
    /// the floating strip, not on a reading surface.
    @ViewBuilder
    func notaChromeSurface() -> some View {
        self.background(KlinoteColor.desk)
    }
}

private struct NotaGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?
    var interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(
                KlinoteColor.desk,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else if #available(macOS 26.0, *) {
            content.glassEffect(
                klinoteGlassStyle(tint: tint, interactive: interactive),
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            content.background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

@available(macOS 26.0, *)
private func klinoteGlassStyle(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint {
        glass = glass.tint(tint)
    }
    if interactive {
        glass = glass.interactive()
    }
    return glass
}

/// Primary action: glass prominent on macOS 26+, ink fill before that.
struct NotaGlassPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            configuration.label
                .font(KlinoteFont.emphasis())
                .padding(.horizontal, KlinoteMetrics.space16)
                .padding(.vertical, KlinoteMetrics.space8)
                .glassEffect(.regular.tint(KlinoteColor.inkFill).interactive(), in: .rect(cornerRadius: KlinoteMetrics.radiusModule))
                .opacity(configuration.isPressed ? 0.86 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
        } else {
            configuration.label
                .font(KlinoteFont.emphasis())
                .foregroundStyle(.white)
                .padding(.horizontal, KlinoteMetrics.space16)
                .padding(.vertical, KlinoteMetrics.space8)
                .background(
                    RoundedRectangle(cornerRadius: KlinoteMetrics.radiusModule, style: .continuous)
                        .fill(KlinoteColor.inkFill)
                )
                .opacity(configuration.isPressed ? 0.82 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
        }
    }
}
