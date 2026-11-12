import AppKit
import Foundation
import Testing
@testable import TinyHand

struct HandGesture: CustomTestStringConvertible {
    let style: PointerStyle
    let gesture: Gesture
    var testDescription: String { "\(style.rawValue) \(gesture.slot)" }
}

let allHandGestures: [HandGesture] = PointerStyle.builtInHands.flatMap { style in
    style.gestures.map { HandGesture(style: style, gesture: $0) }
}

// HandAsset keeps a small static cache with no lock, so these cases run one at a time.
@Suite("Gesture hands", .serialized)
struct GestureHandsTests {
    @Test("Line art has gestures in slots 1, 2 and 9, and lists only 1 and 2")
    func lineArtSlots() throws {
        let line = try #require(PointerStyle(rawValue: "line"))
        #expect(line.gestures.map(\.slot) == [1, 2, 9])
        #expect(line.gestures.map(\.assetName) == ["hand_line_1", "hand_line_2", "hand_line_9"])
        #expect(line.listedGestures.map(\.slot) == [1, 2], "⌃⇧9 works but isn't shown")
        #expect(line.gesture(slot: 2)?.label == "Gesture 2")
        #expect(line.gesture(slot: 2)?.shortcut == "⌃⇧2")
        #expect(line.gesture(slot: 3) == nil)
    }

    @Test("Every gesture picture loads, and its stick sits where the pointing picture's stick does",
          arguments: allHandGestures)
    func gestureMatchesPointing(_ item: HandGesture) throws {
        let pointingName = try #require(item.style.assetName)
        let gestureName = item.gesture.assetName
        let pointing = try #require(HandAsset.load(pointingName), "\(pointingName) is missing or could not be measured")
        let gesture = try #require(HandAsset.load(gestureName), "\(gestureName) is missing or could not be measured")

        #expect(gesture.image.width == pointing.image.width && gesture.image.height == pointing.image.height,
                "\(gestureName) should be the same size as \(pointingName)")
        #expect(abs(gesture.rodX - pointing.rodX) < 0.005, "the stick in \(gestureName) is not where it is in \(pointingName)")
        #expect(abs(gesture.rodEnd - pointing.rodEnd) < 0.005, "the stick in \(gestureName) does not end where it does in \(pointingName)")
    }

    @Test("Every gesture picture is fully transparent around the hand", arguments: allHandGestures)
    func transparentAroundHand(_ item: HandGesture) throws {
        let name = item.gesture.assetName
        let asset = try #require(HandAsset.load(name))
        let px = try TestPictures.pixels(asset.image)
        let w = asset.image.width, h = asset.image.height
        // Every row above the top of the hand, across the whole width, is background.
        let clearRows = max(1, Int(asset.handTop * CGFloat(h)) - 10)
        var most: UInt8 = 0
        for y in 0..<clearRows {
            for x in 0..<w { most = max(most, px[(y * w + x) * 4 + 3]) }
        }
        #expect(most == 0, "\(name) has a faint background (alpha up to \(most)) where it should be transparent")
    }

    @Test("A gesture picture is the hand's picture name and a slot from 1 to 9, and anything else is ignored")
    func parsing() {
        #expect(Gesture.parse("hand_line_2", hand: "hand_line") == Gesture(slot: 2, assetName: "hand_line_2"))
        #expect(Gesture.parse("hand_line", hand: "hand_line") == nil)
        #expect(Gesture.parse("hand_line_0", hand: "hand_line") == nil, "slots start at 1")
        #expect(Gesture.parse("hand_line_10", hand: "hand_line") == nil, "slots end at 9")
        #expect(Gesture.parse("hand_line_x", hand: "hand_line") == nil)
        #expect(Gesture.parse("hand_line_2_shaka", hand: "hand_line") == nil, "gestures have numbers, not names")
        #expect(Gesture.parse("hand_lineart_1", hand: "hand_line") == nil, "another hand's picture")
    }

    @Test("A hand without gestures has none")
    func handWithoutGestures() {
        #expect(PointerStyle.lavender.gestures.isEmpty)
        #expect(PointerStyle.lavender.gesture(slot: 1) == nil)
    }

    @Test("The hand shows a gesture only if it is one of its own, and drops it when the hand changes")
    @MainActor
    func armViewGestures() throws {
        _ = NSApplication.shared
        let view = ArmView(frame: NSRect(x: 0, y: 0, width: 420, height: 560))
        let line = try #require(PointerStyle(rawValue: "line"))
        // The unlisted ⌃⇧9 shows like any other gesture.
        let ok = try #require(line.gesture(slot: 9))

        view.setStyle(line)
        view.setGesture(ok)
        #expect(view.gesture == ok)
        view.setGesture(nil)
        #expect(view.gesture == nil)

        view.setGesture(ok)
        view.setStyle(.lavender)
        #expect(view.gesture == nil, "changing hands should go back to pointing")
        view.setGesture(ok)
        #expect(view.gesture == nil, "another hand's gesture keeps this hand pointing")
    }

    @Test("A gesture added to your own hand sits on that hand's stick, and goes when the hand goes")
    func customHandGesture() throws {
        try TestPictures.withHandsFolder { folder in
            // Source pictures the way a person would bring them: the hand alone, no stick, on transparency.
            let gestureSource = try TestPictures.handOnly("hand_line_1", to: folder.appendingPathComponent("Surfer.png"))
            let hand = try TestPictures.makeHand(in: folder)
            defer { CustomHands.remove(hand) }
            #expect(hand.gestures.isEmpty)

            let gesture = try CustomHands.addGesture(to: hand, from: gestureSource)
            #expect(gesture.slot == 1)
            #expect(gesture.assetName == "\(try #require(hand.assetName))_1", "named by slot, not by the file it came from")
            #expect(hand.gestures == [gesture])

            let handName = try #require(hand.assetName)
            let pointing = try #require(HandAsset.load(handName))
            let shown = try #require(HandAsset.load(gesture.assetName))
            #expect(abs(shown.rodX - pointing.rodX) < 0.005, "the gesture's stick moved sideways")
            #expect(abs(shown.rodEnd - pointing.rodEnd) < 0.005, "the gesture's stick changed length")
            #expect(abs(shown.wrist - pointing.wrist) < 0.01, "the gesture's wrist is not where the hand's wrist is")

            try CustomHands.removeGesture(gesture, from: hand)
            #expect(hand.gestures.isEmpty)
            let left = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Hands").path)
            #expect(!left.contains { $0.hasSuffix("_1.png") }, "the gesture's picture should be deleted")
        }
    }
}
