import AppKit
import Foundation
import Testing
@testable import TinyHand

/// Helpers the gesture tests share: cutting a hand out of a stock picture the way a person
/// would bring one, reading pixels, and a throwaway folder for your own hands.
enum TestPictures {
    /// Cuts the hand (no stick) out of a stock picture and pads it with transparency.
    static func handOnly(_ name: String, to url: URL) throws -> URL {
        let image = try #require(HandAsset.load(name)).image
        let px = try pixels(image)
        let w = image.width
        func width(_ y: Int) -> Int {
            var lo = -1, hi = -1
            for x in 0..<w where px[(y * w + x) * 4 + 3] > 128 {
                if lo < 0 { lo = x }
                hi = x
            }
            return lo < 0 ? 0 : hi - lo
        }
        var stickTop = image.height / 3
        while stickTop < image.height && width(stickTop) > 120 { stickTop += 1 }
        let hand = try #require(image.cropping(to: CGRect(x: 0, y: 0, width: w, height: stickTop)))
        let ctx = try #require(CGContext(data: nil, width: w + 80, height: stickTop + 80, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(hand, in: CGRect(x: 40, y: 40, width: w, height: stickTop))
        let padded = try #require(ctx.makeImage())
        try HandMaker.write(padded, to: url)
        return url
    }

    /// The picture's pixels as premultiplied RGBA, top row first.
    static func pixels(_ image: CGImage) throws -> [UInt8] {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try #require(CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return px
    }

    /// Runs the body with your own hands redirected to a throwaway folder (TH_HANDS_DIR), then
    /// removes the folder. The setting is process-wide, so the tests run one at a time.
    static func withHandsFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tinyhand-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        setenv("TH_HANDS_DIR", folder.appendingPathComponent("Hands").path, 1)
        defer {
            unsetenv("TH_HANDS_DIR")
            try? FileManager.default.removeItem(at: folder)
        }
        try body(folder)
    }

    /// Makes one of your own hands from the stock line hand, in the current hands folder.
    static func makeHand(in folder: URL, name: String = "Test hand") throws -> PointerStyle {
        let made = try HandMaker.make(from: try handOnly("hand_line", to: folder.appendingPathComponent("mine.png")))
        return try CustomHands.add(made.image, ink: made.ink, name: name)
    }
}
