import SwiftUI

// Liquid Glass arrived in macOS 26. These wrappers use it there and fall back to
// flat fills and classic button styles on macOS 15, so the rest of the UI doesn't branch.

extension View {
    /// Puts the view on a Liquid Glass surface of the given shape.
    /// - Parameters:
    ///   - tint: colours the glass, to suggest state or prominence.
    ///   - interactive: makes the glass react to the pointer, like a glass button.
    ///   - fallback: what to fill the shape with before macOS 26.
    @ViewBuilder
    func glassSurface(
        in shape: some Shape,
        tint: Color? = nil,
        interactive: Bool = false,
        fallback: some ShapeStyle
    ) -> some View {
        if #available(macOS 26, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background(shape.fill(fallback))
        }
    }

    /// Makes the menu bar panel a sheet of Liquid Glass (its window is transparent),
    /// or a rounded sheet of the classic menu material before macOS 26.
    @ViewBuilder
    func glassPanel() -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.15)))
        }
    }

    /// The Liquid Glass button style, or the bordered style before macOS 26.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

/// Groups glass surfaces so the system renders them together (glass can't sample other glass).
/// `spacing` stays below the gaps in the layout so neighbouring shapes don't melt into each other.
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 2) { content }
        } else {
            content
        }
    }
}
