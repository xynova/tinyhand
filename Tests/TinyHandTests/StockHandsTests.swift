import Testing
@testable import TinyHand

// HandAsset keeps a small static cache with no lock, so these cases run one at a time.
@Suite("Stock hands", .serialized)
struct StockHandsTests {
    @Test("Every stock hand has a picture TinyHand can load and measure", arguments: PointerStyle.builtInHands)
    func loadsAndMeasures(_ style: PointerStyle) throws {
        let name = try #require(style.assetName)
        let asset = try #require(HandAsset.load(name), "assets/\(name).png is missing or TinyHand could not measure it")
        #expect(asset.tip < asset.wrist, "the fingertip should sit above the wrist in \(name).png")
        #expect(asset.wrist < asset.rodEnd, "the wrist should sit above the end of the stick in \(name).png")
    }
}
