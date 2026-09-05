import AppKit

/// The menu bar item. The glyph is a game controller tinted by the worst link: green all
/// fine, yellow one click fixes it, red needs a person. When something is wrong a two-word
/// hint sits next to it. The menu has a title row, then one row per link with a colored
/// dot, each broken row followed by its single button and, when no button can help, a hint.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()
    private var snapshot: ChainSnapshot?
    private var timer: Timer?
    private var busy = false
    private var busyKind: RepairKind?
    private let guide = GuideWindow()
    private let tester = TesterWindow()

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        paintGlyph(nil)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        guard !busy else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snap = Chain.standard().snapshot()
            DispatchQueue.main.async {
                self?.snapshot = snap
                self?.paintGlyph(snap)
                self?.rebuildMenu()
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

    private static func dot(_ color: NSColor) -> NSImage {
        let img = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
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
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: snap.severity.color,
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
            let row = NSMenuItem(title: "\(s.link.title): \(s.detail)", action: nil, keyEquivalent: "")
            row.image = StatusItemController.dot(s.severity.color)
            row.isEnabled = true
            menu.addItem(row)
            if let r = s.repair {
                let working = busy && busyKind == r
                let fix = NSMenuItem(title: working ? "\(r.title), working" : r.title,
                                     action: working ? nil : #selector(runRepair(_:)), keyEquivalent: "")
                fix.target = self
                fix.representedObject = r.rawValue
                fix.indentationLevel = 1
                fix.isEnabled = !working
                fix.image = NSImage(systemSymbolName: working ? "hourglass" : "wrench.and.screwdriver.fill", accessibilityDescription: nil)
                menu.addItem(fix)
            }
            if let h = s.hint {
                let hint = NSMenuItem(title: h, action: nil, keyEquivalent: "")
                hint.indentationLevel = 1
                hint.isEnabled = false
                menu.addItem(hint)
            }
        }
        menu.addItem(.separator())
        let guideItem = NSMenuItem(title: "Controller guide", action: #selector(showGuide), keyEquivalent: "g")
        guideItem.target = self
        guideItem.isEnabled = true
        guideItem.image = NSImage(systemSymbolName: "book.fill", accessibilityDescription: nil)
        menu.addItem(guideItem)
        let testItem = NSMenuItem(title: "Button tester", action: #selector(showTester), keyEquivalent: "t")
        testItem.target = self
        testItem.isEnabled = true
        testItem.image = NSImage(systemSymbolName: "dot.circle.and.hand.point.up.left.fill", accessibilityDescription: nil)
        menu.addItem(testItem)
        let quit = NSMenuItem(title: "Quit Xenon Doctor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.isEnabled = true
        menu.addItem(quit)
    }

    @objc private func runRepair(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = RepairKind(rawValue: raw), !busy else { return }
        busy = true
        busyKind = kind
        rebuildMenu()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = Repairs.make(kind).run()
            DispatchQueue.main.async {
                self?.busy = false
                self?.busyKind = nil
                self?.refresh()
            }
        }
    }

    @objc private func showGuide() { guide.show() }
    @objc private func showTester() { tester.show() }

    func open(_ which: String) {
        if which == "guide" { guide.show() }
        if which == "tester" { tester.show() }
    }
}
