import AppKit

/// The menu bar item. The glyph is a game controller tinted by the worst link: green all
/// fine, yellow one click fixes it, red needs a person. When something is wrong a two-word
/// hint sits next to it. The menu has a title row, then one row per link with a colored
/// dot, each broken row followed by its single button and a one-line hint. The full hints
/// and the same buttons live in the window, which the menu opens.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()
    private var snapshot: ChainSnapshot?
    private var timer: Timer?
    private var busy = false
    private var busyKind: RepairKind?
    private let doctor = DoctorWindow()
    let updater = Updater()

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        doctor.onRepair = { [weak self] kind in self?.run(kind) }
        doctor.onCheckNow = { [weak self] in self?.refresh() }
        updater.onChange = { [weak self] in DispatchQueue.main.async { self?.rebuildMenu() } }
        paintGlyph(nil)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        updater.startPolling()
    }

    func refresh() {
        guard !busy else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snap = Chain.standard().snapshot()
            DispatchQueue.main.async {
                self?.snapshot = snap
                self?.paintGlyph(snap)
                self?.rebuildMenu()
                self?.doctor.update(snap, busy: self?.busyKind)
            }
        }
    }

    // MARK: glyph

    private func paintGlyph(_ snap: ChainSnapshot?) {
        guard let button = item.button else { return }
        let sev = snap?.severity ?? .fine
        let color: NSColor = snap == nil ? .secondaryLabelColor : sev.color
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            .applying(.init(paletteColors: [color]))
        let image = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: "Xenon Doctor")?
            .withSymbolConfiguration(cfg)
        image?.isTemplate = false
        button.image = image
        if let worst = snap?.worst {
            button.title = " " + worst.shortHint
            button.imagePosition = .imageLeading
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
        button.toolTip = snap.map { "Xenon Doctor: \($0.severity.word)" } ?? "Xenon Doctor"
    }

    // MARK: menu

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    static func dot(_ color: NSColor, size: CGFloat = 12) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: size / 6, dy: size / 6)).fill()
            return true
        }
        img.isTemplate = false
        return img
    }

    private func titleRow(_ snap: ChainSnapshot) -> NSMenuItem {
        let row = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let s = NSMutableAttributedString(string: "Xenon Doctor", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.labelColor,
        ])
        s.append(NSAttributedString(string: "   \(snap.severity.word)", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: snap.severity.textColor,
        ]))
        row.attributedTitle = s
        row.isEnabled = false
        return row
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        guard let snap = snapshot else {
            let row = NSMenuItem(title: "Xenon Doctor   checking", action: nil, keyEquivalent: "")
            row.isEnabled = false
            menu.addItem(row)
            return
        }
        menu.addItem(titleRow(snap))
        menu.addItem(.separator())
        for s in snap.links {
            let row = NSMenuItem(title: "\(s.link.title): \(s.detail)", action: #selector(openStatus), keyEquivalent: "")
            row.target = self
            row.image = StatusItemController.dot(s.severity.color)
            row.isEnabled = true
            row.toolTip = s.hint
            menu.addItem(row)
            if let r = s.repair {
                let working = busy && busyKind == r
                let fix = NSMenuItem(title: working ? "\(r.title), working" : r.title,
                                     action: working ? nil : #selector(runRepair(_:)), keyEquivalent: "")
                fix.target = self
                fix.representedObject = r.rawValue
                fix.indentationLevel = 1
                fix.isEnabled = !working
                let symbol = working ? "hourglass" : (r.goesThere ? "arrow.up.right.square" : "wrench.and.screwdriver.fill")
                fix.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                menu.addItem(fix)
            }
            if let h = s.menuHint {
                let hint = NSMenuItem(title: h, action: nil, keyEquivalent: "")
                hint.indentationLevel = 1
                hint.isEnabled = false
                hint.toolTip = s.hint
                menu.addItem(hint)
            }
        }
        menu.addItem(.separator())
        addWindowItem("Open Xenon Doctor", key: "o", symbol: "macwindow", action: #selector(openStatus))
        addWindowItem("Button tester", key: "t", symbol: "dot.circle.and.hand.point.up.left.fill", action: #selector(showTester))
        addWindowItem("Controller guide", key: "g", symbol: "book.fill", action: #selector(showGuide))
        menu.addItem(.separator())
        addUpdateItem()
        let quit = NSMenuItem(title: "Quit Xenon Doctor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.isEnabled = true
        menu.addItem(quit)
    }

    private func addWindowItem(_ title: String, key: String, symbol: String, action: Selector) {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        it.isEnabled = true
        it.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        menu.addItem(it)
    }

    /// One row about updates: a newer version with its button, or a plain check.
    private func addUpdateItem() {
        switch updater.state {
        case .available(let v):
            let it = NSMenuItem(title: "Update to \(v.tag) and relaunch", action: #selector(installUpdate), keyEquivalent: "")
            it.target = self
            it.isEnabled = true
            it.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            menu.addItem(it)
        case .downloading:
            let it = NSMenuItem(title: "Updating, the app will relaunch", action: nil, keyEquivalent: "")
            it.isEnabled = false
            it.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil)
            menu.addItem(it)
        case .failed(let why):
            let it = NSMenuItem(title: "Update failed: \(why)", action: #selector(checkForUpdates), keyEquivalent: "")
            it.target = self
            it.isEnabled = true
            menu.addItem(it)
        case .idle, .upToDate, .checking:
            let title = updater.state == .checking ? "Checking for updates" : "Check for updates"
            let it = NSMenuItem(title: title, action: #selector(checkForUpdates), keyEquivalent: "")
            it.target = self
            it.isEnabled = updater.state != .checking
            menu.addItem(it)
        }
    }

    // MARK: actions

    @objc private func runRepair(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = RepairKind(rawValue: raw) else { return }
        run(kind)
    }

    private func run(_ kind: RepairKind) {
        guard !busy else { return }
        busy = true
        busyKind = kind
        rebuildMenu()
        doctor.update(snapshot, busy: kind)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = Repairs.make(kind).run()
            DispatchQueue.main.async {
                self?.busy = false
                self?.busyKind = nil
                self?.refresh()
            }
        }
    }

    @objc private func openStatus() { doctor.show(.status) }
    @objc private func showGuide() { doctor.show(.guide) }
    @objc private func showTester() { doctor.show(.tester) }
    @objc private func checkForUpdates() { updater.check(force: true) }
    @objc private func installUpdate() { updater.installAvailable() }

    func open(_ which: String) {
        switch which {
        case "guide": doctor.show(.guide)
        case "tester": doctor.show(.tester)
        case "menu":
            // Pops the menu once the first snapshot is in, so it can be screenshotted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.item.button?.performClick(nil) }
        default: doctor.show(.status)
        }
    }
}
