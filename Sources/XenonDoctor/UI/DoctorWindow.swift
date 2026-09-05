import AppKit

/// The one window: three tabs. Status mirrors the menu with room for the full hints and
/// the same buttons, Tester is the live pad schematic, Guide is the Stratos Xenon guide.
/// The menu stays the fast path; this is where a person reads when something is wrong.
final class DoctorWindow {
    enum Tab: Int { case status = 0, tester = 1, guide = 2 }

    private var window: NSWindow?
    fileprivate var tabs: NSTabView?
    private let status = StatusPane()
    fileprivate let tester = TesterPane()

    /// Called with the repair a Status-tab button asks for; the menu controller runs it.
    var onRepair: ((RepairKind) -> Void)? {
        get { status.onRepair }
        set { status.onRepair = newValue }
    }
    var onCheckNow: (() -> Void)? {
        get { status.onCheckNow }
        set { status.onCheckNow = newValue }
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func resize(to size: NSSize) {
        guard let w = window else { return }
        w.setContentSize(size)
        GuideWindow.center(w)
    }

    func update(_ snap: ChainSnapshot?, busy: RepairKind?) {
        status.update(snap, busy: busy)
    }

    func show(_ tab: Tab) {
        Trace.log("show \(tab) window=\(window == nil ? "nil" : "built")")
        if window == nil { build() }
        Trace.log("built; tabs=\(tabs?.numberOfTabViewItems ?? -1)")
        tabs?.selectTabViewItem(at: tab.rawValue)
        if tab == .tester { tester.start() }
        GuideWindow.center(window!)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        Trace.log("ordered front; visible=\(window?.isVisible ?? false) frame=\(window?.frame ?? .zero) selected=\(tabs?.selectedTabViewItem?.label ?? "none")")
    }

    /// Cycles tabs from the keyboard: Ctrl-Tab forward, Ctrl-Shift-Tab back.
    func step(_ delta: Int) {
        guard let tv = tabs else { return }
        let n = tv.numberOfTabViewItems
        let cur = tv.indexOfTabViewItem(tv.selectedTabViewItem ?? tv.tabViewItem(at: 0))
        let next = ((cur + delta) % n + n) % n
        tv.selectTabViewItem(at: next)
        if next == Tab.tester.rawValue { tester.start() }
    }

    private func build() {
        let w = DoctorPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 640),
                            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.owner = self
        w.title = "Xenon Doctor"
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 560, height: 480)
        let tv = NSTabView(frame: NSRect(x: 0, y: 0, width: 640, height: 640))
        tv.tabViewType = .topTabsBezelBorder
        tv.autoresizingMask = [.width, .height]

        let statusItem = NSTabViewItem(identifier: "status")
        statusItem.label = "Status"
        statusItem.view = status.scrollView()
        tv.addTabViewItem(statusItem)

        let testerItem = NSTabViewItem(identifier: "tester")
        testerItem.label = "Button tester"
        testerItem.view = tester
        tv.addTabViewItem(testerItem)

        let guideItem = NSTabViewItem(identifier: "guide")
        guideItem.label = "Controller guide"
        guideItem.view = GuideWindow.scrollView()
        tv.addTabViewItem(guideItem)

        w.contentView = tv
        tabs = tv
        window = w
    }
}

/// The window itself, so the usual keys work without a main menu: a menu bar app has
/// no Close item, so Cmd-W would otherwise do nothing.
final class DoctorPanel: NSWindow {
    weak var owner: DoctorWindow?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""
        if flags == .command && key == "w" {
            performClose(nil)
            return true
        }
        // Ctrl-Tab arrives as a tab character (0x09) or, with Shift, as a back-tab (0x19).
        let isTab = event.keyCode == 48
        if isTab && flags.contains(.control) {
            owner?.step(flags.contains(.shift) ? -1 : 1)
            return true
        }
        if flags == .command, let n = Int(key), (1...3).contains(n) {
            owner?.step(0)  // keeps the tester timer honest if the index lands there
            owner?.tabs?.selectTabViewItem(at: n - 1)
            if n == 2 { owner?.tester.start() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// The Status tab: the four links laid out with their full text, each broken one with its
/// button under it, so nothing is abbreviated the way the menu has to abbreviate.
final class StatusPane {
    var onRepair: ((RepairKind) -> Void)?
    var onCheckNow: (() -> Void)?

    private let stack = NSStackView()
    private let scroll = NSScrollView()
    private var built = false

    func scrollView() -> NSScrollView {
        if !built {
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 10
            stack.edgeInsets = NSEdgeInsets(top: 22, left: 26, bottom: 22, right: 26)
            stack.translatesAutoresizingMaskIntoConstraints = false
            let doc = FlippedView()
            doc.addSubview(stack)
            doc.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: doc.topAnchor),
                stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            ])
            scroll.documentView = doc
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true  // the rows fit; the bar only appears if they ever do not
            scroll.drawsBackground = false
            NSLayoutConstraint.activate([
                doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            ])
            built = true
        }
        return scroll
    }

    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.isSelectable = false
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    private func row(_ views: [NSView], spacing: CGFloat = 8, indent: CGFloat = 0) -> NSStackView {
        let h = NSStackView(views: views)
        h.orientation = .horizontal
        h.alignment = .firstBaseline
        h.spacing = spacing
        h.edgeInsets = NSEdgeInsets(top: 0, left: indent, bottom: 0, right: 0)
        return h
    }

    func update(_ snap: ChainSnapshot?, busy: RepairKind?) {
        Trace.log("status update: built=\(built) snap=\(snap != nil)")
        guard built else { return }
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        Trace.log("status update: cleared")

        // Header: the same glyph as the menu bar, the app name, the one state word.
        let sev = snap?.severity ?? .fine
        let glyphCfg = NSImage.SymbolConfiguration(pointSize: 30, weight: .semibold).applying(.init(paletteColors: [snap == nil ? .secondaryLabelColor : sev.color]))
        let glyph = NSImageView(image: NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)!.withSymbolConfiguration(glyphCfg)!)
        let name = label("Xenon Doctor", size: 20, weight: .bold)
        let word = label(snap == nil ? "checking" : sev.word, size: 14, weight: .semibold, color: snap == nil ? .secondaryLabelColor : sev.textColor)
        let titles = NSStackView(views: [name, word])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 1
        let header = NSStackView(views: [glyph, titles])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        stack.addArrangedSubview(header)
        stack.setCustomSpacing(18, after: header)
        Trace.log("status update: header added")

        guard let snap = snap else { return }
        for s in snap.links {
            Trace.log("status update: row \(s.link)")
            let dot = NSImageView(image: StatusItemController.dot(s.dotColor, size: 14))
            let title = label(s.link.title, weight: .semibold)
            let detail = label(s.detail, color: .secondaryLabelColor)
            let head = row([dot, title, detail])
            stack.addArrangedSubview(head)
            stack.setCustomSpacing(4, after: head)
            if let r = s.repair {
                let working = busy == r
                let b = NSButton(title: working ? "\(r.title), working…" : r.title, target: self, action: #selector(tap(_:)))
                b.bezelStyle = .rounded
                b.controlSize = .regular
                b.isEnabled = !working && busy == nil
                b.identifier = NSUserInterfaceItemIdentifier(r.rawValue)
                if let img = NSImage(systemSymbolName: r.goesThere ? "arrow.up.right.square" : "wrench.and.screwdriver.fill", accessibilityDescription: nil) {
                    b.image = img
                    b.imagePosition = .imageLeading
                }
                let br = row([b], indent: 22)
                stack.addArrangedSubview(br)
                stack.setCustomSpacing(4, after: br)
            }
            if let h = s.hint {
                let hint = label(h, size: 12, color: .secondaryLabelColor)
                let hr = row([hint], indent: 22)
                stack.addArrangedSubview(hr)
                hint.widthAnchor.constraint(lessThanOrEqualToConstant: 520).isActive = true
            }
            stack.setCustomSpacing(14, after: stack.arrangedSubviews.last!)
        }

        if snap.playing {
            // The fifth row, only while the game is up: a breathing green dot and the line.
            let dot = NSImageView(image: StatusItemController.dot(.systemGreen, size: 14))
            dot.wantsLayer = true
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = 1.0
            breathe.toValue = 0.3
            breathe.duration = 0.9
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.layer?.add(breathe, forKey: "breathe")
            let egg = row([dot, label(ChainSnapshot.playingLine, weight: .semibold)])
            stack.addArrangedSubview(egg)
            stack.setCustomSpacing(14, after: egg)
        }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let when = DateFormatter.localizedString(from: snap.takenAt, dateStyle: .none, timeStyle: .medium)
        let foot = label("Rows read at \(when)  ·  Xenon Doctor \(version)  ·  updates checked daily at 3 PM", size: 11, color: .tertiaryLabelColor)
        let check = NSButton(title: "Check now", target: self, action: #selector(checkNow))
        check.bezelStyle = .rounded
        check.controlSize = .small
        let footer = row([foot, check], spacing: 12)
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(footer)
        DispatchQueue.main.async { [self] in
            Trace.log("status pane: rows=\(stack.arrangedSubviews.count) scroll=\(scroll.frame) doc=\(scroll.documentView?.frame ?? .zero) stack=\(stack.frame) inWindow=\(scroll.window != nil) hidden=\(scroll.isHiddenOrHasHiddenAncestor)")
        }
    }

    @objc private func tap(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let kind = RepairKind(rawValue: raw) else { return }
        onRepair?(kind)
    }

    @objc private func checkNow() { onCheckNow?() }
}

/// A document view that lays out from the top, so a short status list sits under the tabs
/// instead of at the bottom of the scroll area.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
