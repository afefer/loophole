import AppKit

/// The Pi-hole logo as a monochrome template image for the menu bar, so macOS tints it to match
/// the bar (light, dark, or highlighted). Solid while blocking is on, dimmed otherwise.
@MainActor
enum MenuBarIcon {
    private static let height: CGFloat = 18

    /// `nil` when running outside the app bundle (e.g. `swift run`), where the logo isn't available.
    private static let logo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "pi-hole-menubar", withExtension: "svg"),
              let image = NSImage(contentsOf: url), image.size.height > 0
        else { return nil }
        image.size = NSSize(width: (height * image.size.width / image.size.height).rounded(), height: height)
        return image
    }()

    private static let solid = template(opacity: 1)
    private static let dimmed = template(opacity: 0.45)

    static func image(blockingOn: Bool) -> NSImage? {
        blockingOn ? solid : dimmed
    }

    /// Template images use only the alpha channel. `pi-hole-menubar.svg` is the logo in black with the
    /// darker-red segments at 55% opacity, so they come out as a second, softer shade of the tint.
    private static func template(opacity: CGFloat) -> NSImage? {
        guard let logo else { return nil }
        let image = NSImage(size: logo.size, flipped: false) { rect in
            logo.draw(in: rect, from: .zero, operation: .sourceOver, fraction: opacity)
            return true
        }
        image.isTemplate = true
        return image
    }
}
