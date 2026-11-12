import AppKit

enum RenderTest {
    /// Writes a render-test picture and says where, or says why not and exits 1, so a script
    /// never trusts a "rendered" line for a file that wasn't written.
    static func save(_ data: Data?, to path: String) {
        guard let data = data else {
            print("failed: nothing to render for \(path)")
            exit(1)
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("rendered \(path)")
        } catch {
            print("failed: \(error)")
            exit(1)
        }
    }

    static func run(outPath: String) {
        _ = NSApplication.shared

        let panel = CGSize(width: 420, height: 560)
        // Every style pointing, then each style's gestures. TH_STYLE=<id> draws just that style.
        var styles = PointerStyle.allCases
        if let only = ProcessInfo.processInfo.environment["TH_STYLE"] {
            styles = styles.filter { $0.rawValue == only }
        }
        let panels: [(style: PointerStyle, gesture: Gesture?)] =
            styles.map { ($0, nil) } + styles.flatMap { s in s.gestures.map { (s, $0) } }
        let target = CGPoint(x: panel.width - 230, y: 380)
        let w = Int(panel.width) * panels.count
        let h = Int(panel.height)

        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            exit(3)
        }

        for (i, item) in panels.enumerated() {
            let style = item.style
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(i) * panel.width, y: 0)
            ctx.setFillColor(CGColor(red: 0.93, green: 0.94, blue: 0.92, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: panel.width, height: panel.height))

            let view = ArmView(frame: NSRect(origin: .zero, size: panel))
            view.setStyle(style)
            view.setGesture(item.gesture)
            let resting = ProcessInfo.processInfo.environment["TH_RESTING"] != nil
            if !resting {
                view.press()
                view.held = true
            }
            let center = CGPoint(x: target.x + 40, y: target.y - 8)
            let a0 = atan2(target.y - center.y, target.x - center.x)
            for k in 0...60 {
                let a = a0 + CGFloat(k) / 60 * 2 * .pi
                let p = CGPoint(x: center.x + 40 * cos(a), y: center.y + 32 * sin(a))
                if k == 0 {
                    view.ink.begin(at: p, width: view.inkWidth)
                } else {
                    view.ink.extend(to: p)
                }
            }
            view.ink.extend(to: target)
            if resting {
                view.ink.clear()
            }
            view.aim(cursor: target)
            view.layer?.render(in: ctx)

            if style != .laser && ProcessInfo.processInfo.environment["TH_NO_MARKER"] == nil {
                ctx.setFillColor(CGColor(red: 0.95, green: 0.8, blue: 0.1, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: target.x - 3, y: target.y - 3, width: 6, height: 6))
            }
            ctx.restoreGState()
        }

        guard let cg = ctx.makeImage() else {
            exit(4)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            exit(5)
        }
        try? data.write(to: URL(fileURLWithPath: outPath))
        print("rendered \(outPath)  \(w)x\(h)")
    }
}
