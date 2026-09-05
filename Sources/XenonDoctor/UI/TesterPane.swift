import AppKit
import GameController

/// The Button tester tab. The 3D pad fills whatever height the tab has, a warning sits on
/// it when no pad reaches the Mac, and under it come the pad's own details (which pad,
/// address, link, battery, what macOS calls it) and the checklist of controls to try.
/// Polls the pad thirty times a second while the tab is on screen and stops when it is not.
final class TesterPane: NSView {
    private let scene = ControllerView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    private let warning = NSTextField(labelWithString: "No controller reaching the Mac")
    private let card = NSStackView()
    private let cardTitle = NSTextField(labelWithString: "")
    private let cardGrid = NSGridView()
    private let checks = NSTextField(wrappingLabelWithString: "")
    private var timer: Timer?
    private let readings = PadReadings()
    private var lastCardKey = ""

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 580))
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.width, .height]

        // The scene stretches; everything under it keeps its natural height.
        scene.translatesAutoresizingMaskIntoConstraints = false
        scene.setContentHuggingPriority(.init(1), for: .vertical)
        scene.setContentCompressionResistancePriority(.init(1), for: .vertical)

        warning.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        warning.textColor = .systemRed
        warning.alignment = .center
        warning.translatesAutoresizingMaskIntoConstraints = false
        scene.addSubview(warning)

        cardTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        cardGrid.rowSpacing = 3
        cardGrid.columnSpacing = 14
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = 6
        card.addArrangedSubview(cardTitle)
        card.addArrangedSubview(cardGrid)
        card.isHidden = true

        checks.font = NSFont.systemFont(ofSize: 12)
        checks.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let reset = NSButton(title: "Start over", target: self, action: #selector(resetChecks))
        reset.bezelStyle = .rounded
        let tip = NSTextField(labelWithString: "drag to orbit, scroll to zoom, double-click to re-centre")
        tip.font = NSFont.systemFont(ofSize: 10)
        tip.textColor = .tertiaryLabelColor
        let bar = NSStackView(views: [reset, NSView(), tip])
        bar.orientation = .horizontal
        bar.alignment = .centerY

        let column = NSStackView(views: [scene, card, checks, bar])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.distribution = .fill
        column.edgeInsets = NSEdgeInsets(top: 8, left: 24, bottom: 16, right: 24)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            scene.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 24),
            scene.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -24),
            scene.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            card.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 24),
            checks.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 24),
            checks.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -24),
            bar.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 24),
            bar.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -24),
            warning.centerXAnchor.constraint(equalTo: scene.centerXAnchor),
            warning.bottomAnchor.constraint(equalTo: scene.bottomAnchor, constant: -6),
        ])
        scene.readings = readings
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func start() {
        GCController.startWirelessControllerDiscovery { }
        PadBattery.shared.start()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    @objc private func resetChecks() { readings.reset() }

    private func tick() {
        guard window?.isVisible == true, !isHidden, superview != nil else { timer?.invalidate(); return }
        var controller: GCController?
        if let c = GCController.controllers().first(where: { $0.extendedGamepad != nil }) {
            readings.update(from: c)
            controller = c
        } else {
            readings.connected = false
        }
        scene.apply()
        warning.isHidden = readings.connected
        updateCard(controller)
        checks.attributedStringValue = checklist()
    }

    // MARK: device card

    /// Which known pad is connected, from the pad probe's last reading. Never asks
    /// IOBluetooth from here: that call can block the main thread for good.
    private func connectedPad() -> PadProbe.Seen? {
        PadProbe.latest.first { $0.connected }
    }

    private func updateCard(_ controller: GCController?) {
        guard readings.connected, let c = controller else {
            card.isHidden = true
            lastCardKey = ""
            return
        }
        let found = connectedPad()
        var rows: [(String, String)] = []
        var title = c.vendorName ?? "Controller"
        if let seen = found {
            let pad = seen.pad
            title = "\(pad.mark) pad"
            if let note = pad.note { title += "  ·  \(note)" }
            rows.append(("Address", pad.mac))
            rows.append(("Paired as", seen.name.isEmpty ? "—" : seen.name))
            let rssi = seen.rssi
            if rssi != 127 && rssi != 0 { rows.append(("Signal", "\(rssi) dBm" + (rssi > -60 ? ", strong" : rssi > -75 ? ", fine" : ", weak"))) }
            if let b = PadBattery.shared.reading(forMAC: pad.mac) {
                rows.append(("Battery", b.charging ? "\(b.percent)%, charging" : "\(b.percent)%"))
            } else if readings.battery > 0 {
                rows.append(("Battery", "\(Int(readings.battery * 100))%"))
            } else {
                rows.append(("Battery", "reading…"))
            }
        } else {
            rows.append(("Address", "not one of the registered pads"))
        }
        rows.append(("Link", "Bluetooth, read by the game directly; Steam ignores it"))
        rows.append(("macOS sees", "\(c.vendorName ?? "controller"), \(c.productCategory)"))
        if let ds = c.extendedGamepad as? GCDualShockGamepad, ds.touchpadButton.isPressed == false {
            rows.append(("Layout", "DualShock 4: sticks, D-pad, four faces, L1 L2 R1 R2, Share, Options, PS, touchpad"))
        }
        let key = title + rows.map { $0.0 + $0.1 }.joined()
        guard key != lastCardKey else { return }
        lastCardKey = key
        cardTitle.stringValue = title
        while cardGrid.numberOfRows > 0 { cardGrid.removeRow(at: 0) }
        for (k, v) in rows {
            let kl = NSTextField(labelWithString: k)
            kl.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            kl.textColor = .secondaryLabelColor
            let vl = NSTextField(labelWithString: v)
            vl.font = NSFont.systemFont(ofSize: 11)
            vl.textColor = .labelColor
            vl.lineBreakMode = .byTruncatingTail
            cardGrid.addRow(with: [kl, vl])
        }
        // Column placement can only be set once a row exists; an empty grid has no columns.
        if cardGrid.numberOfColumns > 0 { cardGrid.column(at: 0).xPlacement = .trailing }
        card.isHidden = false
    }

    // MARK: checklist

    private func checklist() -> NSAttributedString {
        let r = readings
        let out = NSMutableAttributedString()
        func row(_ done: Bool?, _ text: String) {
            let mark: String, color: NSColor
            switch done {
            case .some(true): mark = "✓"; color = .systemGreen
            case .some(false): mark = "○"; color = .secondaryLabelColor
            case .none: mark = "!"; color = .systemOrange
            }
            out.append(NSAttributedString(string: mark + "  ", attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 12, weight: .bold)]))
            out.append(NSAttributedString(string: text + "\n", attributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 12)]))
        }
        guard r.connected else {
            row(nil, "No controller. Press PS once. If it blinks and drops, hold Share and PS until the light bar blinks fast.")
            return out
        }
        out.append(NSAttributedString(string: "Try each control\n", attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11, weight: .semibold)]))
        let faces: Set<String> = ["cross", "circle", "square", "triangle"]
        let dpad: Set<String> = ["up", "down", "left", "right"]
        row(faces.isSubset(of: r.seen), "Press all four face buttons")
        row(dpad.isSubset(of: r.seen), "Press all four D-pad directions")
        row(r.seen.contains("L1") && r.seen.contains("R1"), "Press L1 and R1")
        row(r.leftTriggerMax > 0.95 && r.rightTriggerMax > 0.95, "Pull L2 and R2 all the way")
        row(r.leftStickMaxMag > 0.9 && r.rightStickMaxMag > 0.9, "Push both sticks to the edge")
        row(r.seen.contains("L3") && r.seen.contains("R3"), "Click both sticks in")
        row(r.seen.contains("share") && r.seen.contains("options"), "Press Share and Options")
        row(r.seen.contains("ps"), "Tap PS once (the game may pause)")
        row(r.seen.contains("touchpad"), "Click the touchpad")
        if r.leftRestMin > 0.08 { row(nil, String(format: "Left stick never rests at centre, drift %.0f%%", r.leftRestMin * 100)) }
        if r.rightRestMin > 0.08 { row(nil, String(format: "Right stick never rests at centre, drift %.0f%%", r.rightRestMin * 100)) }
        if r.leftTriggerMax > 0.3 && r.leftTriggerMax < 0.95 { row(nil, String(format: "L2 only reaches %.0f%%", r.leftTriggerMax * 100)) }
        if r.rightTriggerMax > 0.3 && r.rightTriggerMax < 0.95 { row(nil, String(format: "R2 only reaches %.0f%%", r.rightTriggerMax * 100)) }
        let raw = PadBattery.shared.latest()
        let percent = raw?.percent ?? (r.battery > 0 ? Int(r.battery * 100) : 100)
        if percent < 20 && raw?.charging != true { row(nil, "Battery low, charge the pad") }
        return out
    }
}
