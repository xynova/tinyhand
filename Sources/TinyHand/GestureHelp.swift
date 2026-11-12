import AppKit

/// What TinyHand tells people about a hand's gestures: the badge on the hand and the text when
/// you hover over it. Hovering also previews the gestures' pictures (Toolbar, SettingsView).
enum GestureHelp {
    /// The colour of the count badge, on the toolbar and in Settings.
    static let badgeColor = NSColor(srgbRed: 0.48, green: 0.38, blue: 0.94, alpha: 1)

    /// The badge on a hand that has gestures: how many it has. Nil for a hand without any.
    static func badge(for style: PointerStyle) -> String? {
        let count = style.listedGestures.count
        return count > 0 ? "\(count)" : nil
    }

    /// The hover text and accessibility description, such as "Line art. Gestures: ⌃⇧1, ⌃⇧2".
    static func summary(for style: PointerStyle) -> String {
        let gestures = style.listedGestures
        guard !gestures.isEmpty else {
            return style.title
        }
        let heading = gestures.count == 1 ? "Gesture" : "Gestures"
        return "\(style.title). \(heading): " + gestures.map(\.shortcut).joined(separator: ", ")
    }
}
