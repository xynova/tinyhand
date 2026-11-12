import AppKit
import ApplicationServices

if let idx = CommandLine.arguments.firstIndex(of: "--render-test") {
    let out = CommandLine.arguments.count > idx + 1 ? CommandLine.arguments[idx + 1] : "/tmp/armtest.png"
    RenderTest.run(outPath: out)
    exit(0)
}

if let idx = CommandLine.arguments.firstIndex(of: "--ax-status") {
    let out = CommandLine.arguments.count > idx + 1 ? CommandLine.arguments[idx + 1] : "/tmp/tinyhand-ax.txt"
    let mask: CGEventMask = 1 << CGEventType.leftMouseDown.rawValue
    let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: { _, _, e, _ in Unmanaged.passUnretained(e) }, userInfo: nil)
    let text = "trusted=\(AXIsProcessTrusted()) tap=\(tap != nil) bundle=\(Bundle.main.bundlePath)\n"
    try? text.write(toFile: out, atomically: true, encoding: .utf8)
    exit(0)
}

if let idx = CommandLine.arguments.firstIndex(of: "--toolbar-test") {
    _ = NSApplication.shared
    let bar = Toolbar()
    // --select <id> puts that hand on the toolbar (and selects it); default lavender.
    let selected = CommandLine.arguments.firstIndex(of: "--select")
        .flatMap { CommandLine.arguments.count > $0 + 1 ? PointerStyle(rawValue: CommandLine.arguments[$0 + 1]) : nil }
    bar.select(selected ?? .lavender)
    bar.setNeedsPermission(CommandLine.arguments.contains("--needs-permission"))
    let out = CommandLine.arguments.count > idx + 1 ? CommandLine.arguments[idx + 1] : "/tmp/toolbar.png"
    if let data = bar.snapshot()?.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: out))
        print("rendered \(out)")
    }
    if CommandLine.arguments.contains("--hint") {
        bar.showHint([("Click", "to tap"), ("Drag", "to draw"), ("Hold ⌥", "to click for real"), ("Esc", "to exit")])
        if let data = bar.snapshotHint()?.representation(using: .png, properties: [:]) {
            let hintOut = out.replacingOccurrences(of: ".png", with: "-hint.png")
            try? data.write(to: URL(fileURLWithPath: hintOut))
            print("rendered \(hintOut)")
        }
    }
    // --preview: the gesture preview shown when hovering the selected hand.
    if CommandLine.arguments.contains("--preview"), let style = selected {
        bar.previewGestures(of: style)
        if let data = bar.snapshotGesturePreview()?.representation(using: .png, properties: [:]) {
            let previewOut = out.replacingOccurrences(of: ".png", with: "-preview.png")
            try? data.write(to: URL(fileURLWithPath: previewOut))
            print("rendered \(previewOut)")
        }
    }
    if CommandLine.arguments.contains("--ink"), let data = bar.snapshotInkTray()?.representation(using: .png, properties: [:]) {
        let trayOut = out.replacingOccurrences(of: ".png", with: "-ink.png")
        try? data.write(to: URL(fileURLWithPath: trayOut))
        print("rendered \(trayOut)")
    }
    exit(0)
}

if let idx = CommandLine.arguments.firstIndex(of: "--settings-test") {
    _ = NSApplication.shared
    let out = CommandLine.arguments.count > idx + 1 ? CommandLine.arguments[idx + 1] : "/tmp/settings.png"
    let section = CommandLine.arguments.count > idx + 2 ? SettingsSection(rawValue: CommandLine.arguments[idx + 2]) ?? .general : .general
    let dark = ProcessInfo.processInfo.environment["TH_DARK"] != nil
    if let image = SettingsWindow().snapshot(section, dark: dark),
       let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: out))
        print("rendered \(out)")
    }
    exit(0)
}

if let idx = CommandLine.arguments.firstIndex(of: "--welcome-test") {
    _ = NSApplication.shared
    let out = CommandLine.arguments.count > idx + 1 ? CommandLine.arguments[idx + 1] : "/tmp/welcome.png"
    let welcome = WelcomeWindow()
    welcome.simulateUntrusted = CommandLine.arguments.contains("--untrusted")
    if let data = welcome.snapshot()?.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: out))
        print("rendered \(out)")
    }
    exit(0)
}

if let idx = CommandLine.arguments.firstIndex(of: "--make-hand"), CommandLine.arguments.count > idx + 2 {
    let input = URL(fileURLWithPath: CommandLine.arguments[idx + 1])
    let output = URL(fileURLWithPath: CommandLine.arguments[idx + 2])
    do {
        let made = try HandMaker.make(from: input)
        try HandMaker.write(made.image, to: output)
        print(String(format: "ok %06X", made.ink))
    } catch let problem as HandMaker.Problem {
        print("rejected: \(problem.message)")
        exit(1)
    } catch {
        print("failed: \(error)")
        exit(1)
    }
    exit(0)
}

// --picker-test <out>: draws the hand picker from Settings.
if let idx = CommandLine.arguments.firstIndex(of: "--picker-test") {
    _ = NSApplication.shared
    let out = CommandLine.arguments.count > idx + 1 ? CommandLine.arguments[idx + 1] : "/tmp/picker.png"
    let dark = ProcessInfo.processInfo.environment["TH_DARK"] != nil
    if let data = snapshotPointerPicker(dark: dark)?.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: out))
        print("rendered \(out)")
    }
    exit(0)
}

// --make-gesture <hand picture> <gesture source> <out>: puts a gesture on a hand's own stick,
// the same way Settings does for your own hands. Name the result <hand>_<slot>.
if let idx = CommandLine.arguments.firstIndex(of: "--make-gesture"), CommandLine.arguments.count > idx + 3 {
    let hand = URL(fileURLWithPath: CommandLine.arguments[idx + 1])
    let source = URL(fileURLWithPath: CommandLine.arguments[idx + 2])
    let output = URL(fileURLWithPath: CommandLine.arguments[idx + 3])
    guard let pointing = NSImage(contentsOf: hand)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("failed: can't read \(hand.path)")
        exit(1)
    }
    do {
        try HandMaker.write(try HandMaker.makeGesture(from: source, matching: pointing), to: output)
        print("ok")
    } catch let problem as HandMaker.Problem {
        print("rejected: \(problem.message)")
        exit(1)
    } catch {
        print("failed: \(error)")
        exit(1)
    }
    exit(0)
}

if CommandLine.arguments.contains("--e2e-test") {
    E2ETest.run()
    exit(0)
}

if CommandLine.arguments.contains("--click-test") {
    _ = NSApplication.shared
    OverlayController().runClickTest()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
