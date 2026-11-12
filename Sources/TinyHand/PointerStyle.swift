import AppKit

// A pose a hand can show instead of pointing, while ⌃⇧ and its key are held.
// A hand's gestures come from its picture files: the hand's own picture name, then _<key>, where
// the key is one letter or digit. hand_line_s.webp is Line art's ⌃⇧S, and custom-1a2b3c4d_2.png
// is a custom hand's ⌃⇧2. Gestures have keys, not names: the picture shows what each one is.
struct Gesture: Hashable {
    /// Every key a gesture can use, in the order gestures are listed: digits, then letters.
    static let keys: [Character] = Array("1234567890abcdefghijklmnopqrstuvwxyz")

    /// Lower case, as in the file name.
    let key: Character
    let assetName: String

    var shortcut: String { "⌃⇧\(key.uppercased())" }

    /// What people and screen readers call it, such as "Gesture S".
    var label: String { "Gesture \(key.uppercased())" }

    /// Where it comes in lists: digits first, then letters.
    var order: Int { Gesture.keys.firstIndex(of: key) ?? Gesture.keys.count }

    // Stock gestures that work but aren't listed: not counted on the badge, and not in the
    // tooltip, the toolbar preview or Settings. Line art's ⌃⇧M is the middle finger.
    private static let unlisted: Set<String> = ["hand_line_m"]

    /// Whether the badge, the tooltip, the toolbar preview and Settings show this gesture.
    var isListed: Bool { !Gesture.unlisted.contains(assetName) }

    /// Reads a gesture from a picture name, given the hand's own picture name.
    static func parse(_ fileBase: String, hand base: String) -> Gesture? {
        guard fileBase.hasPrefix(base + "_") else {
            return nil
        }
        let rest = fileBase.dropFirst(base.count + 1).lowercased()
        guard rest.count == 1, let key = rest.first, keys.contains(key) else {
            return nil
        }
        return Gesture(key: key, assetName: fileBase)
    }
}

// Finds each hand's gestures among its picture files, and remembers them until told to forget.
enum GestureCatalog {
    private static var known: [String: [Gesture]] = [:]

    static func gestures(for style: PointerStyle) -> [Gesture] {
        guard let base = style.assetName else {
            return []
        }
        if let hit = known[base] {
            return hit
        }
        // A key's picture can be in more than one folder, or be both a WebP and a PNG; it is
        // the same gesture, and HandAsset picks which file to load.
        var byKey: [Character: Gesture] = [:]
        for folder in HandAsset.pictureFolders(custom: style.isCustom) {
            for file in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
                let url = URL(fileURLWithPath: file)
                guard HandAsset.pictureTypes.contains(url.pathExtension.lowercased()),
                      let gesture = Gesture.parse(url.deletingPathExtension().lastPathComponent, hand: base) else {
                    continue
                }
                byKey[gesture.key] = gesture
            }
        }
        let list = byKey.values.sorted { $0.order < $1.order }
        known[base] = list
        return list
    }

    static func forget(_ style: PointerStyle) {
        if let base = style.assetName {
            known[base] = nil
        }
    }
}

struct PointerStyle: Hashable {
    let rawValue: String

    private init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init?(rawValue: String) {
        guard PointerStyle.allCases.contains(where: { $0.rawValue == rawValue }) else {
            return nil
        }
        self.rawValue = rawValue
    }

    static let lavender = PointerStyle("lavender")
    static let glove = PointerStyle("glove")
    static let coral = PointerStyle("coral")
    static let plush = PointerStyle("plush")
    static let robot = PointerStyle("robot")
    static let laser = PointerStyle("laser")

    private static let builtIn: [(id: String, title: String, ink: CGColor)] = [
        ("lavender", "Lavender toy", Ink.purple),
        ("glove", "Cursor glove", Ink.purple),
        ("coral", "Coral vinyl", Ink.red),
        ("plush", "Plush", Ink.hex(0x2F86F0)),
        ("robot", "Robot", Ink.hex(0x16A87A)),
        ("pink", "Bubblegum", Ink.hex(0xEE4F98)),
        ("blue", "Sky", Ink.hex(0x2F86F0)),
        ("mint", "Mint", Ink.hex(0x16A87A)),
        ("lemon", "Lemon", Ink.hex(0xF2B705)),
        ("black", "Midnight", Ink.hex(0x1D1D21)),
        ("chrome", "Chrome", Ink.hex(0x6B7380)),
        ("holo", "Holo", Ink.purple),
        ("fuzzy", "Fuzzy", Ink.purple),
        ("wood", "Wood", Ink.hex(0x9A5E2C)),
        ("marble", "Marble", Ink.hex(0x6B7380)),
        ("terrazzo", "Terrazzo", Ink.hex(0xF0561D)),
        ("glass", "Glass", Ink.hex(0x1597E5)),
        ("jelly", "Jelly", Ink.hex(0xA33FE6)),
        ("pastel", "Pastel", Ink.hex(0xEE4F98)),
        ("pixel", "Pixel", Ink.hex(0x1D1D21)),
        ("lowpoly", "Low poly", Ink.purple),
        ("knit", "Knit", Ink.purple),
        ("skeleton", "Skeleton", Ink.hex(0x9A5E2C)),
        ("astro", "Astronaut", Ink.hex(0x2F86F0)),
        ("space", "Space", Ink.red),
        ("monster", "Monster", Ink.hex(0x3E9E2E)),
        ("water", "Water", Ink.hex(0x1597E5)),
        ("lava", "Lava", Ink.hex(0xF0561D)),
        ("grass", "Grass", Ink.hex(0x3E9E2E)),
        ("cactus", "Cactus", Ink.hex(0x3E9E2E)),
        ("choco", "Chocolate", Ink.hex(0x9A5E2C)),
        ("cloud", "Cloud", Ink.hex(0x2F86F0)),
        ("mech", "Mech", Ink.hex(0xF0561D)),
        ("neon", "Neon", Ink.hex(0xE0309A)),
        ("leaf", "Leaf", Ink.hex(0x3E9E2E)),
        ("cookie", "Gingerbread", Ink.hex(0x9A5E2C)),
        ("line", "Line art", Ink.hex(0x1D1D21)),
    ]

    /// This hand's gestures, digits then letters, including unlisted ones.
    var gestures: [Gesture] {
        GestureCatalog.gestures(for: self)
    }

    /// The gestures people are shown: all of them except unlisted ones.
    var listedGestures: [Gesture] {
        gestures.filter(\.isListed)
    }

    func gesture(key: Character) -> Gesture? {
        gestures.first { $0.key == key }
    }

    static var builtInHands: [PointerStyle] {
        builtIn.map { PointerStyle($0.id) }
    }

    static var customHands: [PointerStyle] {
        CustomHands.all.map { PointerStyle($0.id) }
    }

    static var allCases: [PointerStyle] {
        builtInHands + customHands + [.laser]
    }

    static let defaultPinned: [PointerStyle] = [.lavender, .glove, .coral, .plush, .robot, .laser]

    var isCustom: Bool {
        CustomHands.hand(rawValue) != nil
    }

    var title: String {
        if self == .laser {
            return "Laser dot"
        }
        if let custom = CustomHands.hand(rawValue) {
            return custom.name
        }
        return PointerStyle.builtIn.first { $0.id == rawValue }?.title ?? rawValue
    }

    var assetName: String? {
        if self == .laser {
            return nil
        }
        if isCustom {
            return rawValue
        }
        return "hand_\(rawValue)"
    }

    var inkColor: CGColor {
        if self == .laser {
            return Ink.red
        }
        if let custom = CustomHands.hand(rawValue) {
            return Ink.hex(custom.ink)
        }
        return PointerStyle.builtIn.first { $0.id == rawValue }?.ink ?? Ink.purple
    }

    private static let defaultsKey = "pointerStyle"

    static var saved: PointerStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey)
            if raw == "dot" {
                return .laser
            }
            if raw == "sunny" {
                return .coral
            }
            return raw.flatMap(PointerStyle.init(rawValue:)) ?? .lavender
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

struct HandAsset {
    let image: CGImage
    let aspect: CGFloat
    let handTop: CGFloat
    let tip: CGFloat
    let wrist: CGFloat
    let rodEnd: CGFloat
    let tipX: CGFloat
    let rodX: CGFloat
    let handMinX: CGFloat
    let handMaxX: CGFloat

    private static var cache: [String: HandAsset] = [:]
    private static var recent: [String] = []
    private static let cacheLimit = 2

    static func load(_ name: String) -> HandAsset? {
        if let hit = cache[name] {
            touch(name)
            return hit
        }
        guard let image = loadImage(name), let asset = measure(image) else {
            return nil
        }
        cache[name] = asset
        touch(name)
        return asset
    }

    private static func touch(_ name: String) {
        recent.removeAll { $0 == name }
        recent.append(name)
        while recent.count > cacheLimit {
            cache[recent.removeFirst()] = nil
        }
    }

    private static var thumbnails: [String: NSImage] = [:]

    static func forget(_ name: String) {
        cache[name] = nil
        recent.removeAll { $0 == name }
        thumbnails[name] = nil
    }

    static func cachedThumbnail(_ name: String) -> NSImage? {
        thumbnails[name]
    }

    static func preloadThumbnails(_ names: [String], done: (() -> Void)? = nil) {
        let missing = names.filter { thumbnails[$0] == nil }
        guard !missing.isEmpty else {
            done?()
            return
        }
        DispatchQueue.global(qos: .utility).async {
            var built: [(String, NSImage)] = []
            for name in missing {
                autoreleasepool {
                    if let thumb = loadImage(name).flatMap(measure)?.thumbnail {
                        built.append((name, thumb))
                    }
                }
            }
            DispatchQueue.main.async {
                for (name, thumb) in built where thumbnails[name] == nil {
                    thumbnails[name] = thumb
                }
                done?()
            }
        }
    }

    static func thumbnail(_ name: String) -> NSImage? {
        if let hit = thumbnails[name] {
            return hit
        }
        let asset = cache[name] ?? loadImage(name).flatMap(measure)
        guard let thumb = asset?.thumbnail else {
            return nil
        }
        thumbnails[name] = thumb
        return thumb
    }

    var thumbnail: NSImage {
        let h = CGFloat(image.height)
        let w = CGFloat(image.width)
        let handW = (handMaxX - handMinX) * w
        let handH = (wrist - handTop) * h
        let side = max(handW, handH) * 1.06
        let cx = (handMinX + handMaxX) / 2 * w
        let cy = (handTop + wrist) / 2 * h
        let rect = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        let cropped = image.cropping(to: rect) ?? image
        let px = 128
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return NSImage(cgImage: cropped, size: NSSize(width: 64, height: 64))
        }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: px, height: px))
        guard let small = ctx.makeImage() else {
            return NSImage(cgImage: cropped, size: NSSize(width: 64, height: 64))
        }
        return NSImage(cgImage: small, size: NSSize(width: 64, height: 64))
    }

    static func resized(_ image: CGImage, height: Int) -> CGImage? {
        let width = max(1, Int((CGFloat(image.width) * CGFloat(height) / CGFloat(image.height)).rounded()))
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    private static func measure(_ image: CGImage) -> HandAsset? {
        let w = image.width
        let h = image.height
        var alpha = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &alpha, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else {
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        func count(_ y: Int) -> Int {
            var n = 0
            let row = y * w
            for x in 0..<w where alpha[row + x] > 128 {
                n += 1
            }
            return n
        }
        func center(_ y: Int) -> CGFloat {
            let row = y * w
            var lo = -1
            var hi = -1
            for x in 0..<w where alpha[row + x] > 128 {
                if lo < 0 {
                    lo = x
                }
                hi = x
            }
            return lo < 0 ? 0.5 : CGFloat(lo + hi) / 2 / CGFloat(w)
        }

        let counts = (0..<h).map(count)
        guard let top = counts.firstIndex(where: { $0 > 0 }) else {
            return nil
        }
        let searchEnd = min(h, top + Int(0.45 * Double(h)))
        let maxW = counts[top..<searchEnd].max() ?? 0
        guard maxW > 0,
              let fist = (top..<h).first(where: { Double(counts[$0]) > 0.6 * Double(maxW) }),
              let wrist = (fist..<h).first(where: { Double(counts[$0]) < 0.35 * Double(maxW) }) else {
            return nil
        }
        let rodW = counts[min(h - 1, wrist + h / 50)]
        let lastRow = counts.lastIndex(where: { $0 > 0 }) ?? (h - 1)
        let from = min(h - 1, wrist + h / 33)
        let handle = (from..<h).first(where: { Double(counts[$0]) > 1.8 * Double(rodW) })
        let rodEnd = handle ?? lastRow

        var minX = w
        var maxX = 0
        for y in top..<wrist {
            let row = y * w
            for x in 0..<w where alpha[row + x] > 128 {
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }

        let fh = CGFloat(h)
        return HandAsset(
            image: image,
            aspect: CGFloat(w) / fh,
            handTop: max(0, CGFloat(top) - 0.004 * fh) / fh,
            tip: CGFloat(top) / fh,
            wrist: CGFloat(wrist) / fh,
            rodEnd: CGFloat(rodEnd) / fh,
            tipX: center(min(h - 1, top + h / 200)),
            rodX: center((wrist + rodEnd) / 2),
            handMinX: CGFloat(minX) / CGFloat(w),
            handMaxX: CGFloat(maxX) / CGFloat(w)
        )
    }

    /// Built-in hand pictures are WebP or PNG; each folder is checked for WebP first.
    static let pictureTypes = ["webp", "png"]

    /// Where hand pictures live, in the order they are looked for. Your own hands live in their
    /// own folder; built-in hands in the app bundle, beside the program, or in assets/ when run
    /// from the source tree. Gesture pictures are found in the same places.
    static func pictureFolders(custom: Bool) -> [URL] {
        if custom {
            return [CustomHands.directory]
        }
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        return [Bundle.main.resourceURL, exeDir, exeDir.appendingPathComponent("assets"),
                URL(fileURLWithPath: "assets")].compactMap { $0 }
    }

    private static func loadImage(_ name: String) -> CGImage? {
        var urls = [CustomHands.directory.appendingPathComponent("\(name).png")]
        for folder in pictureFolders(custom: false) {
            for type in pictureTypes {
                urls.append(folder.appendingPathComponent("\(name).\(type)"))
            }
        }
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            if let image = NSImage(contentsOf: url),
               let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return cg
            }
        }
        return nil
    }
}
