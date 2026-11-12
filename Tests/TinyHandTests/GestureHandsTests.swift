import AppKit
import Foundation
import Testing
@testable import TinyHand

struct HandGesture: CustomTestStringConvertible {
    let style: PointerStyle
    let gesture: Gesture
    var testDescription: String { "\(style.rawValue) \(gesture.key)" }
}

let allHandGestures: [HandGesture] = PointerStyle.builtInHands.flatMap { style in
    style.gestures.map { HandGesture(style: style, gesture: $0) }
}

// HandAsset keeps a small static cache with no lock, so these cases run one at a time.
@Suite("Gesture hands", .serialized)
struct GestureHandsTests {
    @Test("Line art has gestures on S, O and M, and lists only S and O")
    func lineArtKeys() throws {
        let line = try #require(PointerStyle(rawValue: "line"))
        #expect(Set(line.gestures.map(\.assetName)) == ["hand_line_s", "hand_line_o", "hand_line_m"])
        #expect(line.gestures.map(\.key) == ["m", "o", "s"], "listed digits first, then letters in order")
        #expect(line.listedGestures.map(\.key) == ["o", "s"], "⌃⇧M works but isn't shown")
        #expect(line.gesture(key: "s")?.label == "Gesture S")
        #expect(line.gesture(key: "s")?.shortcut == "⌃⇧S")
        #expect(line.gesture(key: "x") == nil)
    }

    @Test("Gestures are listed digits first, then letters")
    func keyOrder() {
        let keys: [Character] = ["s", "2", "a", "0", "1"]
        let sorted = keys.map { Gesture(key: $0, assetName: "x") }.sorted { $0.order < $1.order }.map(\.key)
        #expect(sorted == ["1", "2", "0", "a", "s"], "0 comes after 9, as on the keyboard")
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

    @Test("A gesture picture is the hand's picture name and one letter or digit, and anything else is ignored")
    func parsing() {
        #expect(Gesture.parse("hand_line_s", hand: "hand_line") == Gesture(key: "s", assetName: "hand_line_s"))
        #expect(Gesture.parse("hand_line_2", hand: "hand_line") == Gesture(key: "2", assetName: "hand_line_2"))
        #expect(Gesture.parse("hand_line_0", hand: "hand_line")?.key == "0")
        #expect(Gesture.parse("hand_line_S", hand: "hand_line")?.key == "s", "a capital in the file name is the same key")
        #expect(Gesture.parse("hand_line", hand: "hand_line") == nil)
        #expect(Gesture.parse("hand_line_10", hand: "hand_line") == nil, "one character only")
        #expect(Gesture.parse("hand_line_-", hand: "hand_line") == nil)
        #expect(Gesture.parse("hand_line_é", hand: "hand_line") == nil, "plain letters only")
        #expect(Gesture.parse("hand_line_shaka", hand: "hand_line") == nil, "gestures have keys, not names")
        #expect(Gesture.parse("hand_lineart_s", hand: "hand_line") == nil, "another hand's picture")
    }

    @Test("A hand without gestures has none")
    func handWithoutGestures() {
        #expect(PointerStyle.lavender.gestures.isEmpty)
        #expect(PointerStyle.lavender.gesture(key: "s") == nil)
    }

    @Test("The hand shows a gesture only if it is one of its own, and drops it when the hand changes")
    @MainActor
    func armViewGestures() throws {
        _ = NSApplication.shared
        let view = ArmView(frame: NSRect(x: 0, y: 0, width: 420, height: 560))
        let line = try #require(PointerStyle(rawValue: "line"))
        // The unlisted ⌃⇧M shows like any other gesture.
        let ok = try #require(line.gesture(key: "m"))

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
            let gestureSource = try TestPictures.handOnly("hand_line_s", to: folder.appendingPathComponent("Surfer.png"))
            let hand = try TestPictures.makeHand(in: folder)
            defer { CustomHands.remove(hand) }
            #expect(hand.gestures.isEmpty)

            let gesture = try CustomHands.addGesture(to: hand, from: gestureSource)
            #expect(gesture.key == "s", "Surfer.png suggests S")
            #expect(gesture.assetName == "\(try #require(hand.assetName))_s", "named by key, not by the file it came from")
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
            #expect(!left.contains { $0.hasSuffix("_s.png") }, "the gesture's picture should be deleted")
        }
    }
}
