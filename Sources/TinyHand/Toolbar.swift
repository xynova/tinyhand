import AppKit

final class Toolbar {
    var onPick: ((PointerStyle) -> Void)?
    var onToggleSound: (() -> Void)?
    var onExit: (() -> Void)?
    var onFixPermission: (() -> Void)?

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class Button: NSButton {
        // Set for hands with gestures: called with true when the pointer enters, false when it leaves.
        var onHover: ((Bool) -> Void)? {
            didSet { updateTrackingAreas() }
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            if onHover != nil {
                addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                               owner: self, userInfo: nil))
            }
        }

        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }
    }

    private let panel: Panel
    private let stack = NSStackView()
    private var styleButtons: [PointerStyle: Button] = [:]
    private var shownStyles: [PointerStyle] = []
    private var current: PointerStyle?
    private var inkButton: Button?
    private var swatches: [InkChoice: Button] = [:]
    private var inkOpen = false
    private let permissionButton = Button()
    private var soundButton: Button?
    private(set) var revealed = false

    private let tray: Panel
    private let trayStack = NSStackView()
    private var hint: Panel?
    private var preview: Panel?
    private var previewedKeys: [Character] = []

    var frame: CGRect { inkOpen ? panel.frame.union(tray.frame) : panel.frame }

    init() {
        panel = Panel(contentRect: CGRect(x: 0, y: 0, width: 300, height: 56),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.alphaValue = 0

        let background = NSVisualEffectView.darkGlass(radius: 16)
        panel.contentView = background

        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        tray = Panel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 40),
                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        tray.isOpaque = false
        tray.backgroundColor = .clear
        tray.hasShadow = true
        tray.hidesOnDeactivate = false
        tray.isFloatingPanel = true
        tray.becomesKeyOnlyIfNeeded = true
        tray.level = panel.level
        tray.collectionBehavior = panel.collectionBehavior
        tray.alphaValue = 0
        let trayBackground = NSVisualEffectView.darkGlass(radius: 14)
        tray.contentView = trayBackground
        trayStack.orientation = .horizontal
        trayStack.spacing = 2
        trayStack.edgeInsets = NSEdgeInsets(top: 5, left: 6, bottom: 5, right: 6)
        trayStack.translatesAutoresizingMaskIntoConstraints = false
        trayBackground.addSubview(trayStack)
        NSLayoutConstraint.activate([
            trayStack.leadingAnchor.constraint(equalTo: trayBackground.leadingAnchor),
            trayStack.trailingAnchor.constraint(equalTo: trayBackground.trailingAnchor),
            trayStack.topAnchor.constraint(equalTo: trayBackground.topAnchor),
            trayStack.bottomAnchor.constraint(equalTo: trayBackground.bottomAnchor),
        ])

        stack.addArrangedSubview(Toolbar.divider())
        let ink = makeButton(image: nil, tip: "Ink colour") { [weak self] in
            self?.toggleInk()
        }
        inkButton = ink
        stack.addArrangedSubview(ink)
        let sound = makeButton(symbol: "speaker.wave.2.fill", tip: "Tap sound") { [weak self] in
            self?.onToggleSound?()
        }
        soundButton = sound
        stack.addArrangedSubview(sound)
        stack.addArrangedSubview(makeButton(symbol: "xmark", tip: "Exit  (Esc)") { [weak self] in
            self?.onExit?()
        })

        permissionButton.bezelStyle = .rounded
        permissionButton.isBordered = false
        permissionButton.wantsLayer = true
        permissionButton.layer?.cornerRadius = 10
        permissionButton.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.9).cgColor
        permissionButton.attributedTitle = NSAttributedString(string: "  Allow clicks & drawing  ", attributes: [
            .foregroundColor: NSColor.black,
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
        ])
        permissionButton.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        permissionButton.imagePosition = .imageLeading
        permissionButton.contentTintColor = .black
        permissionButton.toolTip = "TinyHand needs Accessibility permission to intercept clicks and draw"
        permissionButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        permissionButton.target = self
        permissionButton.action = #selector(fixPermission)
        permissionButton.isHidden = true
        stack.addArrangedSubview(permissionButton)

        rebuildStyles()
        background.removeFocusRings()
        resize()
        refreshInk()
        NotificationCenter.default.addObserver(forName: Preferences.changed, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildStyles()
            self?.refreshInk()
        }
        // Adding or removing a gesture keeps the pinned hands the same but changes their badge,
        // tooltip and hover preview, so the buttons are made again.
        NotificationCenter.default.addObserver(forName: CustomHands.changed, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildStyles(force: true)
        }
    }

    private func toggleInk() {
        setInkOpen(!inkOpen)
    }

    private func setInkOpen(_ open: Bool) {
        guard open != inkOpen, let ink = inkButton else {
            return
        }
        inkOpen = open
        if open {
            if swatches.isEmpty {
                for choice in InkChoice.allCases {
                    let b = makeButton(image: nil, tip: choice.title, side: 30) { [weak self] in
                        Preferences.inkChoice = choice
                        self?.setInkOpen(false)
                    }
                    b.layer?.cornerRadius = 15
                    swatches[choice] = b
                    trayStack.addArrangedSubview(b)
                }
                tray.contentView?.removeFocusRings()
                trayStack.layoutSubtreeIfNeeded()
                tray.setContentSize(trayStack.fittingSize)
            }
            refreshInk()
            let r = panel.convertToScreen(ink.convert(ink.bounds, to: nil))
            let size = tray.frame.size
            tray.setFrameOrigin(CGPoint(x: r.midX - size.width / 2, y: panel.frame.maxY + 8))
            tray.invalidateShadow()
            tray.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                tray.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                tray.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self = self, !self.inkOpen else {
                    return
                }
                self.tray.orderOut(nil)
            })
        }
        refreshInk()
    }

    private func refreshInk() {
        guard let ink = inkButton else {
            return
        }
        let style = current ?? PointerStyle.saved
        ink.image = Toolbar.inkDot(Preferences.inkChoice.resolved(for: style))
        ink.layer?.backgroundColor = inkOpen ? NSColor(white: 1, alpha: 0.18).cgColor : NSColor.clear.cgColor
        let hidden = !Preferences.showInkButton
        if ink.isHidden != hidden {
            ink.isHidden = hidden
            if hidden {
                setInkOpen(false)
            }
            resizeKeepingCenter()
        }
        for (choice, b) in swatches {
            b.image = choice.color.map(Toolbar.inkDot) ?? Toolbar.rainbowDot()
            b.layer?.backgroundColor = choice == Preferences.inkChoice ? NSColor(white: 1, alpha: 0.2).cgColor : NSColor.clear.cgColor
        }
    }

    private func resizeKeepingCenter() {
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.minY)
        resize()
        panel.setFrameOrigin(CGPoint(x: center.x - panel.frame.width / 2, y: center.y))
    }

    private func rebuildStyles(force: Bool = false) {
        var styles = Preferences.pinnedStyles
        if let c = current, !styles.contains(c) {
            styles.append(c)
        }
        if styles == shownStyles && !force {
            return
        }
        shownStyles = styles
        // The button under the pointer is about to go, so its mouseExited never comes.
        hideGesturePreview()
        for b in styleButtons.values {
            actions[b] = nil
            b.removeFromSuperview()
        }
        styleButtons = [:]
        for (i, style) in styles.enumerated() {
            let b = makeButton(image: Toolbar.icon(for: style), tip: GestureHelp.summary(for: style)) { [weak self] in
                self?.onPick?(style)
            }
            if let count = GestureHelp.badge(for: style) {
                let badge = Toolbar.badge(count)
                b.addSubview(badge)
                NSLayoutConstraint.activate([
                    badge.topAnchor.constraint(equalTo: b.topAnchor, constant: 1),
                    badge.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -1),
                ])
                b.onHover = { [weak self, weak b] inside in
                    guard let self = self, let b = b else {
                        return
                    }
                    if inside {
                        self.showGesturePreview(style, over: b)
                    } else {
                        self.hideGesturePreview()
                    }
                }
            }
            styleButtons[style] = b
            stack.insertArrangedSubview(b, at: i)
        }
        if let c = current {
            highlight(c)
        }
        resizeKeepingCenter()
    }

    func setSoundOn(_ on: Bool) {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let name = on ? "speaker.wave.2.fill" : "speaker.slash.fill"
        let tip = on ? "Tap sound on — click to mute" : "Tap sound off — click to unmute"
        soundButton?.image = NSImage(systemSymbolName: name, accessibilityDescription: tip)?.withSymbolConfiguration(config)
        soundButton?.toolTip = tip
        soundButton?.contentTintColor = NSColor(white: 1, alpha: on ? 0.85 : 0.45)
    }

    func center(of style: PointerStyle) -> CGPoint? {
        guard let b = styleButtons[style], let w = b.window else {
            return nil
        }
        let r = w.convertToScreen(b.convert(b.bounds, to: nil))
        return CGPoint(x: r.midX, y: r.midY)
    }

    func snapshot() -> NSBitmapImageRep? {
        guard let view = panel.contentView else {
            return nil
        }
        view.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        view.layer?.backgroundColor = nil
        return rep
    }

    func snapshotInkTray() -> NSBitmapImageRep? {
        setInkOpen(true)
        return Toolbar.snapshot(of: tray.contentView)
    }

    // A borderless dark panel that floats with the toolbar and lets clicks through: the base of
    // the hint and the gesture preview.
    private func floatingPanel(radius: CGFloat) -> (Panel, NSVisualEffectView) {
        let p = Panel(contentRect: CGRect(x: 0, y: 0, width: 300, height: 40),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.level = panel.level
        p.collectionBehavior = panel.collectionBehavior
        let bg = NSVisualEffectView.darkGlass(radius: radius)
        p.contentView = bg
        return (p, bg)
    }

    // Draws a panel's content on the toolbar's dark background, for the render tests.
    private static func snapshot(of view: NSView?) -> NSBitmapImageRep? {
        guard let view = view else {
            return nil
        }
        view.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    func showHint(_ parts: [(key: String, text: String)]) {
        hideHint()
        let (p, bg) = floatingPanel(radius: 12)
        p.alphaValue = 0
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 9, left: 16, bottom: 9, right: 16)
        row.translatesAutoresizingMaskIntoConstraints = false
        for part in parts {
            let text = NSMutableAttributedString(string: part.key, attributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
                .foregroundColor: NSColor.white,
            ])
            text.append(NSAttributedString(string: " " + part.text, attributes: [
                .font: NSFont.systemFont(ofSize: 12.5),
                .foregroundColor: NSColor(white: 1, alpha: 0.7),
            ]))
            row.addArrangedSubview(NSTextField(labelWithAttributedString: text))
        }
        bg.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            row.topAnchor.constraint(equalTo: bg.topAnchor),
            row.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
        ])
        row.layoutSubtreeIfNeeded()
        p.setContentSize(row.fittingSize)
        p.setFrameOrigin(CGPoint(x: panel.frame.midX - p.frame.width / 2, y: panel.frame.maxY + 12))
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 1
        }
        hint = p
    }

    func snapshotHint() -> NSBitmapImageRep? {
        Toolbar.snapshot(of: hint?.contentView)
    }

    func hideHint() {
        guard let p = hint else {
            return
        }
        hint = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.orderOut(nil)
        })
    }

    /// Shows a hand's gestures above the toolbar: each one's picture, name and shortcut.
    func previewGestures(of style: PointerStyle) {
        guard let b = styleButtons[style] else {
            return
        }
        showGesturePreview(style, over: b)
    }

    private func showGesturePreview(_ style: PointerStyle, over button: NSView) {
        hideGesturePreview()
        let gestures = style.gestures
        guard !gestures.isEmpty else {
            return
        }
        hideHint()
        let (p, bg) = floatingPanel(radius: 14)

        let title = NSTextField(labelWithString: "\(style.title) gestures")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .white
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .top
        for gesture in gestures {
            let picture = NSImageView()
            picture.image = HandAsset.thumbnail(gesture.assetName)
            picture.imageScaling = .scaleProportionallyUpOrDown
            picture.widthAnchor.constraint(equalToConstant: 52).isActive = true
            picture.heightAnchor.constraint(equalToConstant: 52).isActive = true
            let keys = NSTextField(labelWithString: gesture.shortcut)
            keys.font = .systemFont(ofSize: 11, weight: .semibold)
            keys.textColor = NSColor(white: 1, alpha: 0.7)
            let column = NSStackView(views: [picture, keys])
            column.orientation = .vertical
            column.spacing = 3
            column.setAccessibilityElement(true)
            column.setAccessibilityLabel("\(gesture.label), \(gesture.shortcut)")
            row.addArrangedSubview(column)
        }
        let stackAll = NSStackView(views: [title, row])
        stackAll.orientation = .vertical
        stackAll.alignment = .leading
        stackAll.spacing = 8
        stackAll.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stackAll)
        // The padding is set here rather than as the stack's edge insets: the stack left its
        // right inset out of its fitting size, so the last picture touched the panel's edge.
        let pad = NSEdgeInsets(top: 10, left: 14, bottom: 12, right: 14)
        let content = stackAll.fittingSize
        NSLayoutConstraint.activate([
            stackAll.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: pad.left),
            stackAll.topAnchor.constraint(equalTo: bg.topAnchor, constant: pad.top),
            stackAll.widthAnchor.constraint(equalToConstant: content.width),
            stackAll.heightAnchor.constraint(equalToConstant: content.height),
        ])
        p.setContentSize(NSSize(width: pad.left + content.width + pad.right,
                                height: pad.top + content.height + pad.bottom))

        // Above the hand's button, kept over the toolbar.
        var midX = panel.frame.midX
        if let w = button.window {
            midX = w.convertToScreen(button.convert(button.bounds, to: nil)).midX
        }
        let x = min(max(midX - p.frame.width / 2, panel.frame.minX), panel.frame.maxX - p.frame.width)
        p.setFrameOrigin(CGPoint(x: x, y: panel.frame.maxY + 10))
        p.orderFrontRegardless()
        preview = p
        previewedKeys = gestures.map(\.key)
    }

    func hideGesturePreview() {
        preview?.orderOut(nil)
        preview = nil
        previewedKeys = []
    }

    /// The small count badge on a hand that has gestures.
    private static func badge(_ text: String) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = GestureHelp.badgeColor.cgColor
        v.layer?.cornerRadius = 8
        v.layer?.borderWidth = 1.5
        v.layer?.borderColor = NSColor(white: 0.16, alpha: 1).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.setAccessibilityElement(false)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 9.5, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(label)
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 16),
            v.heightAnchor.constraint(equalToConstant: 16),
            label.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    func select(_ style: PointerStyle) {
        current = style
        rebuildStyles()
        highlight(style)
        refreshInk()
    }

    private func highlight(_ style: PointerStyle) {
        for (s, b) in styleButtons {
            b.layer?.backgroundColor = s == style ? NSColor(white: 1, alpha: 0.18).cgColor : NSColor.clear.cgColor
        }
    }

    func setNeedsPermission(_ needed: Bool) {
        guard permissionButton.isHidden == needed else {
            return
        }
        permissionButton.isHidden = !needed
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.minY)
        resize()
        panel.setFrameOrigin(CGPoint(x: center.x - panel.frame.width / 2, y: center.y))
    }

    func place(on screen: NSScreen) {
        setInkOpen(false)
        let f = panel.frame
        panel.setFrameOrigin(CGPoint(x: screen.frame.midX - f.width / 2, y: screen.visibleFrame.minY + 14))
    }

    func show() {
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    func hide() {
        setInkOpen(false)
        hideHint()
        hideGesturePreview()
        revealed = false
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    func setRevealed(_ value: Bool) {
        guard value != revealed else {
            return
        }
        revealed = value
        if !value {
            setInkOpen(false)
        }
        panel.ignoresMouseEvents = !value
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = value ? 0.15 : 0.35
            panel.animator().alphaValue = value ? 1 : 0
        }
    }

    private func resize() {
        stack.layoutSubtreeIfNeeded()
        let size = stack.fittingSize
        panel.setContentSize(size)
        panel.invalidateShadow()
    }

    private var actions: [Button: () -> Void] = [:]

    private func makeButton(image: NSImage? = nil, symbol: String? = nil, tip: String, side: CGFloat = 40, action: @escaping () -> Void) -> Button {
        let b = Button()
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.imageScaling = .scaleProportionallyUpOrDown
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        b.wantsLayer = true
        b.layer?.cornerRadius = 10
        if let image = image {
            b.image = image
        }
        if let symbol = symbol {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(config)
            b.contentTintColor = NSColor(white: 1, alpha: 0.85)
            b.imageScaling = .scaleNone
        }
        b.widthAnchor.constraint(equalToConstant: side).isActive = true
        b.heightAnchor.constraint(equalToConstant: side).isActive = true
        b.target = self
        b.action = #selector(tapped(_:))
        actions[b] = action
        return b
    }

    @objc private func tapped(_ sender: Button) {
        actions[sender]?()
    }

    @objc private func fixPermission() {
        onFixPermission?()
    }

    private static func inkDot(_ color: CGColor) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r: CGFloat = 13
            NSColor(white: 0, alpha: 0.35).setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - r - 1.5, y: c.y - r - 2.5, width: 2 * r + 3, height: 2 * r + 3)).fill()
            (NSColor(cgColor: color) ?? .white).setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
            NSColor(white: 1, alpha: 0.35).setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - r * 0.55, y: c.y + r * 0.15, width: r * 0.7, height: r * 0.5)).fill()
            return true
        }
    }

    private static func rainbowDot() -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r: CGFloat = 13
            NSColor(white: 0, alpha: 0.35).setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - r - 1.5, y: c.y - r - 2.5, width: 2 * r + 3, height: 2 * r + 3)).fill()
            let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple]
            for (i, color) in colors.enumerated() {
                let path = NSBezierPath()
                path.move(to: c)
                path.appendArc(withCenter: c, radius: r, startAngle: CGFloat(i) * 60 + 90, endAngle: CGFloat(i + 1) * 60 + 90)
                path.close()
                color.setFill()
                path.fill()
            }
            return true
        }
    }

    private static func divider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.18).cgColor
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return v
    }

    static func icon(for style: PointerStyle) -> NSImage? {
        if let name = style.assetName {
            return HandAsset.thumbnail(name)
        }
        return NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let red = NSColor(cgColor: Ink.red) ?? .systemRed
            let glow = NSGradient(colors: [red.withAlphaComponent(0.55), red.withAlphaComponent(0)])
            glow?.draw(in: NSBezierPath(ovalIn: rect.insetBy(dx: 14, dy: 14)), relativeCenterPosition: .zero)
            red.setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)).fill()
            NSColor(srgbRed: 1, green: 0.86, blue: 0.82, alpha: 0.95).setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)).fill()
            return true
        }
    }
}

// MARK: - Test and render-test hooks
// Called by --toolbar-test (main.swift) and by GestureHelpTests, to inspect the toolbar
// without a person hovering or clicking.
extension Toolbar {
    var isPreviewingGestures: Bool { preview != nil }

    /// The preview panel's size, in points.
    var gesturePreviewSize: CGSize? { preview?.frame.size }

    /// The keys of the gestures the preview shows.
    var gesturesInPreview: [Character] { previewedKeys }

    func snapshotGesturePreview() -> NSBitmapImageRep? {
        Toolbar.snapshot(of: preview?.contentView)
    }

    /// The badge text on a hand's toolbar button, if it has one.
    func badgeText(of style: PointerStyle) -> String? {
        styleButtons[style]?.subviews.compactMap { $0.subviews.first as? NSTextField }.first?.stringValue
    }

    /// The tooltip on a hand's toolbar button.
    func tooltip(of style: PointerStyle) -> String? {
        styleButtons[style]?.toolTip
    }
}
