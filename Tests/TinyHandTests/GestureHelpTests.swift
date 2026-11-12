import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import TinyHand

// Everything that tells people about gestures: the badge, the hover text and preview, and
// the shortcuts. HandAsset's cache has no lock, so these run one at a time.
@Suite("Finding the gestures", .serialized)
struct GestureHelpTests {
    private var line: PointerStyle {
        get throws { try #require(PointerStyle(rawValue: "line")) }
    }

    @Test("The badge shows how many gestures a hand has, and only on hands that have some")
    func badge() throws {
        #expect(GestureHelp.badge(for: try line) == "3")
        #expect(GestureHelp.badge(for: .lavender) == nil)
        #expect(GestureHelp.badge(for: .laser) == nil)
    }

    @Test("The hover text lists each gesture's shortcut")
    func summary() throws {
        #expect(GestureHelp.summary(for: try line) == "Line art. Gestures: ⌃⇧1, ⌃⇧2, ⌃⇧3")
        #expect(GestureHelp.summary(for: .lavender) == "Lavender toy")
    }

    @Test("A hand with one gesture says Gesture, not Gestures")
    func summaryOne() throws {
        try TestPictures.withHandsFolder { folder in
            let hand = try TestPictures.makeHand(in: folder)
            defer { CustomHands.remove(hand) }
            try CustomHands.addGesture(to: hand, from: try TestPictures.handOnly("hand_line_2", to: folder.appendingPathComponent("wave.png")))
            #expect(GestureHelp.summary(for: hand) == "Test hand. Gesture: ⌃⇧1")
        }
    }

    @Test("⌃⇧1 to ⌃⇧9 are nine different keys, and never use Option or Command")
    func shortcuts() {
        let keys = OverlayController.gestureKeys
        #expect(keys.map(\.slot) == Array(Gesture.slots))
        #expect(Set(keys.map(\.keyCode)).count == keys.count)
        let modifiers = Int(OverlayController.gestureModifiers)
        #expect(modifiers & controlKey != 0 && modifiers & shiftKey != 0)
        // Option is the default "click for real" key, which hides the hand while held, and holding
        // it for a gesture made the pointer lose clicks. Command draws arrowheads.
        #expect(modifiers & optionKey == 0, "gesture shortcuts must not use Option")
        #expect(modifiers & cmdKey == 0, "gesture shortcuts must not use Command")
    }

    @Test("On the toolbar, a hand with gestures has a badge, lists them on hover, and previews them")
    @MainActor
    func toolbar() throws {
        _ = NSApplication.shared
        let bar = Toolbar()
        let line = try line
        bar.select(line)
        #expect(bar.badgeText(of: line) == "3")
        #expect(bar.tooltip(of: line) == GestureHelp.summary(for: line))

        bar.previewGestures(of: line)
        #expect(bar.isPreviewingGestures)
        let preview = try #require(bar.snapshotGesturePreview())
        #expect(preview.pixelsWide > 100 && preview.pixelsHigh > 60)
        bar.hideGesturePreview()
        #expect(!bar.isPreviewingGestures)

        bar.select(.lavender)
        #expect(bar.badgeText(of: .lavender) == nil)
        bar.previewGestures(of: .lavender)
        #expect(!bar.isPreviewingGestures, "a hand without gestures has nothing to preview")
    }

    @Test("In the hand picker, hovering a hand with gestures shows them, and other hands don't")
    @MainActor
    func pickerPreview() throws {
        _ = NSApplication.shared
        let plain = try #require(snapshotPointerPicker(hovered: nil))
        let hoverLine = try #require(snapshotPointerPicker(hovered: try line))
        let hoverLavender = try #require(snapshotPointerPicker(hovered: .lavender))
        #expect(hoverLine.pixelsHigh > plain.pixelsHigh, "the gesture strip should appear under the picker")
        #expect(hoverLavender.pixelsHigh == plain.pixelsHigh, "no strip for a hand without gestures")
    }
}

// Adding gestures to your own hands, in a throwaway hands folder.
@Suite("Your own hands' gestures", .serialized)
struct CustomGestureTests {
    @Test("A gesture picture without a transparent background is refused")
    func opaqueRefused() throws {
        try withHand { hand, folder in
            let opaque = folder.appendingPathComponent("opaque.png")
            let ctx = try #require(CGContext(data: nil, width: 400, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
            let image = try #require(ctx.makeImage())
            try HandMaker.write(image, to: opaque)
            #expect(throws: HandMaker.Problem.self) { try CustomHands.addGesture(to: hand, from: opaque) }
            #expect(hand.gestures.isEmpty)
        }
    }

    @Test("A hand takes nine gestures, in slots 1 to 9, and refuses a tenth")
    func nineSlots() throws {
        try withHand { hand, folder in
            let source = try handOnly("hand_line_2", to: folder.appendingPathComponent("wave.png"))
            for _ in Gesture.slots {
                try CustomHands.addGesture(to: hand, from: source)
            }
            #expect(hand.gestures.map(\.slot) == Array(Gesture.slots))
            #expect(throws: HandMaker.Problem.self) { try CustomHands.addGesture(to: hand, from: source) }
        }
    }

    @Test("Removing your hand removes its gesture pictures too")
    func removeHandRemovesGestures() throws {
        try withHand(keep: true) { hand, folder in
            let source = try handOnly("hand_line_3", to: folder.appendingPathComponent("okay.png"))
            try CustomHands.addGesture(to: hand, from: source)
            let hands = folder.appendingPathComponent("Hands")
            #expect(try FileManager.default.contentsOfDirectory(atPath: hands.path).contains { $0.hasSuffix("_1.png") })
            CustomHands.remove(hand)
            #expect(!(try FileManager.default.contentsOfDirectory(atPath: hands.path).contains { $0.hasSuffix("_1.png") }))
        }
    }

    @Test("Gestures can't be added to stock hands from Settings")
    func stockHandsRefused() throws {
        let line = try #require(PointerStyle(rawValue: "line"))
        let url = URL(fileURLWithPath: "/nonexistent.png")
        #expect(throws: HandMaker.Problem.self) { try CustomHands.addGesture(to: line, from: url) }
    }

    // Makes one of your own hands in a throwaway hands folder, runs the body, then removes the
    // hand (unless the body does) and the folder.
    private func withHand(keep: Bool = false, _ body: (PointerStyle, URL) throws -> Void) throws {
        try TestPictures.withHandsFolder { folder in
            let hand = try TestPictures.makeHand(in: folder)
            defer {
                if !keep { CustomHands.remove(hand) }
            }
            try body(hand, folder)
        }
    }

    private func handOnly(_ name: String, to url: URL) throws -> URL {
        try TestPictures.handOnly(name, to: url)
    }
}
