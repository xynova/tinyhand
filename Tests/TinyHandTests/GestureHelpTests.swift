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
        #expect(GestureHelp.badge(for: try line) == "2", "the unlisted ⌃⇧M isn't counted")
        #expect(GestureHelp.badge(for: .lavender) == nil)
        #expect(GestureHelp.badge(for: .laser) == nil)
    }

    @Test("The hover text lists each gesture's shortcut")
    func summary() throws {
        #expect(GestureHelp.summary(for: try line) == "Line art. Gestures: ⌃⇧O, ⌃⇧S", "the unlisted ⌃⇧M isn't listed")
        #expect(GestureHelp.summary(for: .lavender) == "Lavender toy")
    }

    @Test("A hand with one gesture says Gesture, not Gestures")
    func summaryOne() throws {
        try TestPictures.withHandsFolder { folder in
            let hand = try TestPictures.makeHand(in: folder)
            defer { CustomHands.remove(hand) }
            try CustomHands.addGesture(to: hand, from: try TestPictures.handOnly("hand_line_s", to: folder.appendingPathComponent("wave.png")))
            #expect(GestureHelp.summary(for: hand) == "Test hand. Gesture: ⌃⇧W")
        }
    }

    @Test("Every gesture key is its own key on the keyboard, and the shortcuts never use Option or Command")
    func shortcuts() {
        let codes = OverlayController.gestureKeyCodes
        #expect(Set(codes.keys) == Set(Gesture.keys), "every letter and digit has a key code")
        #expect(Set(codes.values).count == codes.count, "no two keys share a key code")
        #expect(codes["s"] == kVK_ANSI_S && codes["1"] == kVK_ANSI_1)
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
        #expect(bar.badgeText(of: line) == "2")
        #expect(bar.tooltip(of: line) == GestureHelp.summary(for: line))

        bar.previewGestures(of: line)
        #expect(bar.isPreviewingGestures)
        #expect(bar.gesturesInPreview == ["o", "s"], "the unlisted ⌃⇧M isn't previewed")
        let preview = try #require(bar.snapshotGesturePreview())
        #expect(preview.pixelsWide > 100 && preview.pixelsHigh > 60)
        bar.hideGesturePreview()
        #expect(!bar.isPreviewingGestures)

        bar.select(.lavender)
        #expect(bar.badgeText(of: .lavender) == nil)
        bar.previewGestures(of: .lavender)
        #expect(!bar.isPreviewingGestures, "a hand without gestures has nothing to preview")
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

    @Test("A hand takes a gesture on every letter and digit, and refuses one more")
    func everyKey() throws {
        try withHand { hand, folder in
            // Every key but z as a copy of the hand's picture (quicker than fitting 35 gestures),
            // then z through Settings' way of adding one.
            let base = try #require(hand.assetName)
            let picture = folder.appendingPathComponent("Hands/\(base).png")
            for key in Gesture.keys where key != "z" {
                try FileManager.default.copyItem(at: picture, to: folder.appendingPathComponent("Hands/\(base)_\(key).png"))
            }
            GestureCatalog.forget(hand)
            #expect(CustomHands.freeKeys(for: hand) == ["z"])
            let source = try handOnly("hand_line_s", to: folder.appendingPathComponent("wave.png"))
            #expect(try CustomHands.addGesture(to: hand, from: source).key == "z", "wave.png suggests W, which is taken")
            #expect(hand.gestures.map(\.key) == Gesture.keys)
            #expect(throws: HandMaker.Problem.self) { try CustomHands.addGesture(to: hand, from: source) }
        }
    }

    @Test("A gesture goes on the key picked, else the one its file name suggests, else the first free one")
    func pickedKey() throws {
        try withHand { hand, folder in
            let wave = try handOnly("hand_line_s", to: folder.appendingPathComponent("wave.png"))
            #expect(CustomHands.freeKeys(for: hand) == Gesture.keys)

            let five = try CustomHands.addGesture(to: hand, from: wave, key: "5")
            #expect(five.key == "5")
            #expect(five.assetName.hasSuffix("_5"))
            #expect(!CustomHands.freeKeys(for: hand).contains("5"))
            #expect(throws: HandMaker.Problem.self) { try CustomHands.addGesture(to: hand, from: wave, key: "5") }

            #expect(try CustomHands.addGesture(to: hand, from: wave).key == "w", "wave.png suggests W")
            #expect(try CustomHands.addGesture(to: hand, from: wave).key == "1", "W is taken now, so the first free key")
            #expect(try CustomHands.addGesture(to: hand, from: wave, key: "Q").key == "q", "a capital picks the same key")
        }
    }

    @Test("A file name suggests its first letter or digit, if that key is free")
    func suggestedKey() {
        func suggest(_ name: String, free: [Character] = Gesture.keys) -> Character? {
            CustomHands.suggestedKey(for: URL(fileURLWithPath: "/x/\(name)"), free: free)
        }
        #expect(suggest("Shaka.png") == "s")
        #expect(suggest("2 thumbs.png") == "2")
        #expect(suggest("_peace.png") == "p", "skips what isn't a letter or digit")
        #expect(suggest("Shaka.png", free: ["a", "b"]) == nil, "S is taken")
        #expect(suggest("ChatGPT Image Nov 12, 2026, 10_15_02 PM.png") == nil, "an image tool's default name says nothing")
    }

    @Test("The key menu offers only the free keys, and follows the picked file's name until changed")
    @MainActor
    func keyChooser() {
        _ = NSApplication.shared
        let chooser = GestureKeyChooser(free: ["2", "a", "s"])
        #expect(chooser.titles == ["⌃⇧2", "⌃⇧A", "⌃⇧S"])
        #expect(chooser.selectedKey == "2")
        chooser.follow(URL(fileURLWithPath: "/x/Shaka.png"))
        #expect(chooser.selectedKey == "s")
        chooser.follow(URL(fileURLWithPath: "/x/thumbs.png"))
        #expect(chooser.selectedKey == "s", "T isn't free, so the pick stays")
        chooser.select(key: "x")
        #expect(chooser.selectedKey == "s", "a key that isn't free can't be picked")
        #expect(chooser.view.frame.width > 100)
    }

    @Test("Removing your hand removes its gesture pictures too")
    func removeHandRemovesGestures() throws {
        try withHand(keep: true) { hand, folder in
            let source = try handOnly("hand_line_o", to: folder.appendingPathComponent("okay.png"))
            try CustomHands.addGesture(to: hand, from: source)
            let hands = folder.appendingPathComponent("Hands")
            #expect(try FileManager.default.contentsOfDirectory(atPath: hands.path).contains { $0.hasSuffix("_o.png") })
            CustomHands.remove(hand)
            #expect(!(try FileManager.default.contentsOfDirectory(atPath: hands.path).contains { $0.hasSuffix("_o.png") }))
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
