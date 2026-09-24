import AppKit

/// The Controller map tab: one sub-tab per game, the pad drawn flat with every control
/// labelled in two tidy columns, a line from each label to its control, and a press on
/// the pad lighting both the control and its label. The labels come from KeyMaps; the
/// presses come from the pad's own reports, the same source as the tester.
final class MapPane: NSView {
    private let picker = NSSegmentedControl(labels: Game.all.map { $0.title }, trackingMode: .selectOne, target: nil, action: nil)
    private let map = PadMapView()
    private let chords = NSGridView()
    /// The grid's edge pins, switched off while it is hidden: an empty grid otherwise
    /// demands zero width and the window follows it.
    private var chordEdges: [NSLayoutConstraint] = []
    private var timer: Timer?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 580))
        autoresizingMask = [.width, .height]
        picker.selectedSegment = 0
        picker.target = self
        picker.action = #selector(pick)
        picker.segmentDistribution = .fillEqually
        chords.rowSpacing = 5
        chords.columnSpacing = 28
        chords.xPlacement = .leading
        map.setContentHuggingPriority(.init(1), for: .vertical)
        map.setContentCompressionResistancePriority(.init(1), for: .vertical)

        let column = NSStackView(views: [picker, map, chords])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 14, right: 20)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        // The window's own size sits at priority 500. Everything here that wants room
        // asks below that, so the tab fits the window instead of resizing it.
        let mapMin = map.heightAnchor.constraint(greaterThanOrEqualToConstant: 300)
        mapMin.priority = NSLayoutConstraint.Priority(499)
        chords.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(498), for: .vertical)
        chords.setContentHuggingPriority(NSLayoutConstraint.Priority(498), for: .vertical)
        chordEdges = [
            chords.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 20),
            chords.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -20),
        ]
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            picker.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 20),
            picker.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -20),
            map.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 20),
            map.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -20),
            mapMin,
        ] + chordEdges)
        pick()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var game: Game { Game.all[max(0, picker.selectedSegment)] }

    @objc private func pick() {
        map.actions = KeyMaps.actions(for: game)
        rebuildChords(KeyMaps.chords(for: game))
        map.needsDisplay = true
    }

    /// The chord table: three across, each cell the chord in a muted weight and what it
    /// does in the text colour, so the eye lands on the action.
    private func rebuildChords(_ list: [(String, String)]) {
        while chords.numberOfRows > 0 {
            let row = chords.row(at: 0)
            for i in 0..<row.numberOfCells { row.cell(at: i).contentView?.removeFromSuperview() }
            chords.removeRow(at: 0)
        }
        chords.isHidden = list.isEmpty
        for c in chordEdges { c.isActive = !list.isEmpty }
        let perRow = 3
        var i = 0
        while i < list.count {
            var cells: [NSView] = []
            for j in i..<min(i + perRow, list.count) {
                let (chord, action) = list[j]
                let key = NSTextField(labelWithString: chord)
                key.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
                key.textColor = .secondaryLabelColor
                let what = NSTextField(labelWithString: action)
                what.font = NSFont.systemFont(ofSize: 10)
                what.textColor = .labelColor
                for f in [key, what] {
                    f.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(498), for: .vertical)
                    f.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(498), for: .horizontal)
                    f.lineBreakMode = .byTruncatingTail
                }
                let cell = NSStackView(views: [key, what])
                cell.orientation = .vertical
                cell.alignment = .leading
                cell.spacing = 0
                cells.append(cell)
            }
            while cells.count < perRow { cells.append(NSView()) }
            chords.addRow(with: cells)
            i += perRow
        }
    }

    func select(_ game: Game) {
        if let i = Game.all.firstIndex(where: { $0.link == game.link }) { picker.selectedSegment = i; pick() }
    }

    func start() {
        PadProbe.prepare()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        guard window?.isVisible == true, !isHidden, superview != nil else { timer?.invalidate(); return }
        var pressed = Set<String>()
        if let s = PadBattery.shared.latestState() {
            pressed = s.buttons
            if hypot(s.leftX, s.leftY) > 0.5 { pressed.insert("leftStick") }
            if hypot(s.rightX, s.rightY) > 0.5 { pressed.insert("rightStick") }
            if s.leftTrigger > 0.5 { pressed.insert("L2") }
            if s.rightTrigger > 0.5 { pressed.insert("R2") }
        }
        if pressed != map.pressed {
            map.pressed = pressed
            map.needsDisplay = true
        }
    }
}

/// The flat pad, its labels, and the lines between them.
final class PadMapView: NSView {
    var actions: [String: String] = [:]
    var pressed = Set<String>()

    /// Where each control sits on the pad, in the tester's scene units (x from -8 to 8).
    static let anchors: [String: CGPoint] = [
        "L2": CGPoint(x: -5.2, y: 3.4), "L1": CGPoint(x: -5.2, y: 2.7), "R2": CGPoint(x: 5.2, y: 3.4), "R1": CGPoint(x: 5.2, y: 2.7),
        "up": CGPoint(x: -4.6, y: 1.35), "down": CGPoint(x: -4.6, y: -0.15), "left": CGPoint(x: -5.35, y: 0.6), "right": CGPoint(x: -3.85, y: 0.6),
        "triangle": CGPoint(x: 4.6, y: 1.65), "cross": CGPoint(x: 4.6, y: -0.45), "square": CGPoint(x: 3.55, y: 0.6), "circle": CGPoint(x: 5.65, y: 0.6),
        "leftStick": CGPoint(x: -2.3, y: -1.3), "rightStick": CGPoint(x: 2.3, y: -1.3), "L3": CGPoint(x: -2.3, y: -2.45), "R3": CGPoint(x: 2.3, y: -2.45),
        "touchpad": CGPoint(x: 0, y: 1.4), "share": CGPoint(x: -2.35, y: 1.6), "options": CGPoint(x: 2.35, y: 1.6), "ps": CGPoint(x: 0, y: -0.5),
    ]
    static let faceColors: [String: NSColor] = ["triangle": .systemGreen, "cross": .systemBlue, "square": .systemPink, "circle": .systemRed]

    override var isFlipped: Bool { false }

    private struct Layout {
        let scale: CGFloat
        let origin: CGPoint   // view point of scene (0, 0)
        let columnWidth: CGFloat
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }
    }

    private func geometry() -> Layout {
        let columnWidth = min(170, max(140, bounds.width * 0.24))
        let padWidth = bounds.width - 2 * columnWidth - 16
        let scale = min(padWidth / 16.4, (bounds.height - 24) / 10.6)
        // The pad spans y from -6.2 to 3.9 in scene units; centre that span vertically.
        let origin = CGPoint(x: bounds.midX, y: bounds.midY - (3.9 - 6.2) / 2 * scale)
        return Layout(scale: scale, origin: origin, columnWidth: columnWidth)
    }

    /// Label rows per column, top to bottom by where the control sits on the pad.
    private func rows(left: Bool) -> [String] {
        KeyMaps.controls.filter { KeyMaps.isLeft($0) == left }
            .sorted { (PadMapView.anchors[$0]?.y ?? 0) > (PadMapView.anchors[$1]?.y ?? 0) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let l = geometry()
        drawPad(l)
        for left in [true, false] { drawColumn(l, left: left) }
    }

    private func drawPad(_ l: Layout) {
        let s = l.scale
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            let p = l.point(CGPoint(x: x, y: y))
            return NSRect(x: p.x - w * s / 2, y: p.y - h * s / 2, width: w * s, height: h * s)
        }
        let shell = NSColor(white: 0.22, alpha: 1)
        let outline = NSBezierPath(roundedRect: rect(0, 0.4, 16, 5.2), xRadius: 2.4 * s, yRadius: 2.4 * s)
        outline.appendRoundedRect(rect(-5.8, -3.45, 3.6, 5.5), xRadius: 1.7 * s, yRadius: 1.7 * s)
        outline.appendRoundedRect(rect(5.8, -3.45, 3.6, 5.5), xRadius: 1.7 * s, yRadius: 1.7 * s)
        outline.windingRule = .nonZero
        shell.setFill()
        outline.fill()

        func control(_ path: NSBezierPath, _ key: String, base: NSColor) {
            let on = pressed.contains(key)
            (on ? NSColor.controlAccentColor : base).setFill()
            path.fill()
            if on {
                NSColor.controlAccentColor.withAlphaComponent(0.5).setStroke()
                path.lineWidth = 3
                path.stroke()
            }
        }
        let dark = NSColor(white: 0.32, alpha: 1)
        let well = NSColor(white: 0.14, alpha: 1)
        // Triggers and bumpers along the top edge.
        for (side, x) in [("L", CGFloat(-5.2)), ("R", CGFloat(5.2))] {
            control(NSBezierPath(roundedRect: rect(x, 3.4, 2.4, 1.0), xRadius: 0.2 * s, yRadius: 0.2 * s), "\(side)2", base: dark)
            control(NSBezierPath(roundedRect: rect(x, 2.7, 2.4, 0.45), xRadius: 0.15 * s, yRadius: 0.15 * s), "\(side)1", base: dark)
        }
        // D-pad in its well.
        well.setFill(); NSBezierPath(ovalIn: rect(-4.6, 0.6, 3.4, 3.4)).fill()
        for (k, w, h, dx, dy) in [("up", 0.7, 1.0, 0.0, 0.75), ("down", 0.7, 1.0, 0.0, -0.75), ("left", 1.0, 0.7, -0.75, 0.0), ("right", 1.0, 0.7, 0.75, 0.0)] as [(String, CGFloat, CGFloat, CGFloat, CGFloat)] {
            control(NSBezierPath(roundedRect: rect(-4.6 + dx, 0.6 + dy, w, h), xRadius: 0.12 * s, yRadius: 0.12 * s), k, base: dark)
        }
        // Face buttons in their well.
        well.setFill(); NSBezierPath(ovalIn: rect(4.6, 0.6, 3.8, 3.8)).fill()
        for (k, p) in PadMapView.anchors where PadMapView.faceColors[k] != nil {
            let c = PadMapView.faceColors[k]!
            control(NSBezierPath(ovalIn: rect(p.x, p.y, 0.9, 0.9)), k, base: c.blended(withFraction: 0.45, of: NSColor(white: 0.2, alpha: 1)) ?? c)
        }
        // Sticks: ring, then knob; the knob lights for the stick, the ring for its click.
        for (side, x) in [("L", CGFloat(-2.3)), ("R", CGFloat(2.3))] {
            well.setFill(); NSBezierPath(ovalIn: rect(x, -1.3, 2.5, 2.5)).fill()
            control(NSBezierPath(ovalIn: rect(x, -1.3, 2.1, 2.1)), "\(side)3", base: NSColor(white: 0.2, alpha: 1))
            control(NSBezierPath(ovalIn: rect(x, -1.3, 1.4, 1.4)), side == "L" ? "leftStick" : "rightStick", base: NSColor(white: 0.3, alpha: 1))
        }
        // Touchpad, Share, Options, PS, light bar.
        control(NSBezierPath(roundedRect: rect(0, 1.4, 3.6, 1.7), xRadius: 0.15 * s, yRadius: 0.15 * s), "touchpad", base: NSColor(white: 0.27, alpha: 1))
        control(NSBezierPath(roundedRect: rect(-2.35, 1.6, 0.35, 0.9), xRadius: 0.1 * s, yRadius: 0.1 * s), "share", base: dark)
        control(NSBezierPath(roundedRect: rect(2.35, 1.6, 0.35, 0.9), xRadius: 0.1 * s, yRadius: 0.1 * s), "options", base: dark)
        control(NSBezierPath(ovalIn: rect(0, -0.5, 0.8, 0.8)), "ps", base: dark)
        NSColor.systemBlue.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: rect(0, 2.75, 3.0, 0.22), xRadius: 0.06 * s, yRadius: 0.06 * s).fill()
    }

    private func drawColumn(_ l: Layout, left: Bool) {
        let keys = rows(left: left)
        let top = bounds.maxY - 10, bottom = bounds.minY + 10
        let step = (top - bottom) / CGFloat(max(keys.count, 1))
        let x0 = left ? bounds.minX : bounds.maxX - l.columnWidth
        let nameFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let actionFont = NSFont.systemFont(ofSize: 10)
        for (i, key) in keys.enumerated() {
            let y = top - step * (CGFloat(i) + 0.5)
            let on = pressed.contains(key)
            let action = actions[key]
            let color: NSColor = on ? .controlAccentColor : (action == nil ? .tertiaryLabelColor : .labelColor)
            let name = NSAttributedString(string: KeyMaps.name(key), attributes: [.font: nameFont, .foregroundColor: color])
            let detail = NSAttributedString(string: action ?? "nothing", attributes: [.font: actionFont, .foregroundColor: on ? NSColor.controlAccentColor : (action == nil ? NSColor.tertiaryLabelColor : NSColor.secondaryLabelColor)])
            let nameSize = name.size(), detailSize = detail.size()
            let textX = left ? x0 : x0 + l.columnWidth - max(nameSize.width, detailSize.width)
            if on {
                let pill = NSRect(x: textX - 6, y: y - detailSize.height - 1, width: max(nameSize.width, detailSize.width) + 12, height: nameSize.height + detailSize.height + 4)
                NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
                NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
            }
            name.draw(at: CGPoint(x: textX, y: y))
            detail.draw(at: CGPoint(x: textX, y: y - detailSize.height + 1))
            // The line: from the label's inner edge to the control, with a dot on the control.
            guard let a = PadMapView.anchors[key] else { continue }
            let anchor = l.point(a)
            let from = CGPoint(x: left ? x0 + max(nameSize.width, detailSize.width) + 8 : x0 + l.columnWidth - max(nameSize.width, detailSize.width) - 8, y: y + 2)
            let line = NSBezierPath()
            line.move(to: from)
            // A short horizontal run out of the column, then straight to the control, so
            // the lines fan from a tidy edge instead of from each label's ragged end.
            let edge = left ? x0 + l.columnWidth - 4 : x0 + 4
            let elbowX = left ? max(from.x, edge) : min(from.x, edge)
            line.line(to: CGPoint(x: elbowX, y: from.y))
            line.line(to: anchor)
            (on ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor.withAlphaComponent(0.5)).setStroke()
            line.lineWidth = on ? 1.6 : 0.8
            line.stroke()
            (on ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).setFill()
            NSBezierPath(ovalIn: NSRect(x: anchor.x - 2, y: anchor.y - 2, width: 4, height: 4)).fill()
        }
    }
}
