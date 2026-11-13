import AppKit

/// The Loophole mark for the menu bar, drawn as a template image so macOS tints it to match the bar.
/// Template images only carry opacity, so the shield gets its faceted, two-tone look from two
/// strengths of the same tint: a bright left face and a softer right face.
///
/// A whole shield means blocking is on; a shield with a hole punched through it means there is a
/// loophole — blocking is off or paused. It is dimmed when there is no connection.
@MainActor
enum MenuBarIcon {
    private static let size = NSSize(width: 16, height: 18)

    private static let solid = template(punched: false, opacity: 1)
    private static let punched = template(punched: true, opacity: 1)
    private static let unavailable = template(punched: false, opacity: 0.4)

    /// - Parameter dimsWhenUnavailable: the menu bar dims the shield when there is no connection;
    ///   the badge inside the panel shows that with colour instead and keeps it at full strength.
    static func image(for status: AppModel.Status, dimsWhenUnavailable: Bool = true) -> NSImage {
        switch status {
        case .enabled: solid
        case .disabled: punched
        case .notConfigured, .unknown, .failed: dimsWhenUnavailable ? unavailable : solid
        }
    }

    private static func template(punched: Bool, opacity: CGFloat) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            shieldPath(in: rect, punched: punched).addClip()
            let (left, right) = rect.divided(atDistance: rect.width / 2, from: .minXEdge)
            NSColor.black.withAlphaComponent(opacity).setFill()
            left.fill()
            NSColor.black.withAlphaComponent(opacity * 0.62).setFill()
            right.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The shield outline (the same shape as the app icon, see scripts/make-icon.swift),
    /// with the hole as a second subpath filled by the even-odd rule.
    private static func shieldPath(in rect: CGRect, punched: Bool) -> NSBezierPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let path = NSBezierPath()
        path.move(to: point(0.50, 0.97))
        path.curve(to: point(0.89, 0.81), controlPoint1: point(0.62, 0.90), controlPoint2: point(0.76, 0.84))
        path.line(to: point(0.89, 0.50))
        path.curve(to: point(0.50, 0.03), controlPoint1: point(0.89, 0.27), controlPoint2: point(0.72, 0.11))
        path.curve(to: point(0.11, 0.50), controlPoint1: point(0.28, 0.11), controlPoint2: point(0.11, 0.27))
        path.line(to: point(0.11, 0.81))
        path.curve(to: point(0.50, 0.97), controlPoint1: point(0.24, 0.84), controlPoint2: point(0.38, 0.90))
        path.close()
        if punched {
            // A little larger than in the app icon, so the hole survives at menu bar size.
            let hole = rect.width * 0.40
            path.appendOval(in: CGRect(
                x: rect.midX - hole / 2, y: rect.minY + rect.height * 0.53 - hole / 2, width: hole, height: hole
            ))
            path.windingRule = .evenOdd
        }
        return path
    }
}
