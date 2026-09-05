import AppKit
import GameController

/// What the pad sends right now, plus what has been seen since the window opened, so the
/// tester can tick off "every face button pressed" style checks and warn about a stick
/// that never rests at centre or a trigger that never reaches the end.
final class PadReadings {
    var connected = false
    var name = ""
    var battery: Float = -1
    var pressed = Set<String>()
    var seen = Set<String>()
    var leftStick = CGPoint.zero
    var rightStick = CGPoint.zero
    var leftTrigger: Float = 0
    var rightTrigger: Float = 0
    var leftTriggerMax: Float = 0
    var rightTriggerMax: Float = 0
    var leftStickMaxMag: CGFloat = 0
    var rightStickMaxMag: CGFloat = 0
    var leftRestMin: CGFloat = 1
    var rightRestMin: CGFloat = 1

    func reset() {
        seen.removeAll()
        leftTriggerMax = 0; rightTriggerMax = 0
        leftStickMaxMag = 0; rightStickMaxMag = 0
        leftRestMin = 1; rightRestMin = 1
    }

    func update(from c: GCController) {
        connected = true
        name = c.vendorName ?? "controller"
        battery = c.battery?.batteryLevel ?? -1
        guard let g = c.extendedGamepad else { return }
        pressed.removeAll()
        func b(_ key: String, _ input: GCControllerButtonInput?) {
            guard let i = input, i.isPressed else { return }
            pressed.insert(key); seen.insert(key)
        }
        b("cross", g.buttonA); b("circle", g.buttonB); b("square", g.buttonX); b("triangle", g.buttonY)
        b("L1", g.leftShoulder); b("R1", g.rightShoulder)
        b("L3", g.leftThumbstickButton); b("R3", g.rightThumbstickButton)
        b("share", g.buttonOptions); b("options", g.buttonMenu); b("ps", g.buttonHome)
        if let ds = g as? GCDualShockGamepad { b("touchpad", ds.touchpadButton) }
        b("up", g.dpad.up); b("down", g.dpad.down); b("left", g.dpad.left); b("right", g.dpad.right)
        leftTrigger = g.leftTrigger.value; rightTrigger = g.rightTrigger.value
        leftTriggerMax = max(leftTriggerMax, leftTrigger); rightTriggerMax = max(rightTriggerMax, rightTrigger)
        if leftTrigger > 0.5 { seen.insert("L2") }
        if rightTrigger > 0.5 { seen.insert("R2") }
        leftStick = CGPoint(x: CGFloat(g.leftThumbstick.xAxis.value), y: CGFloat(g.leftThumbstick.yAxis.value))
        rightStick = CGPoint(x: CGFloat(g.rightThumbstick.xAxis.value), y: CGFloat(g.rightThumbstick.yAxis.value))
        let lm = hypot(leftStick.x, leftStick.y), rm = hypot(rightStick.x, rightStick.y)
        leftStickMaxMag = max(leftStickMaxMag, lm); rightStickMaxMag = max(rightStickMaxMag, rm)
        leftRestMin = min(leftRestMin, lm); rightRestMin = min(rightRestMin, rm)
    }
}

/// A schematic of the pad. Pressed things fill with color; the sticks show where they are.
final class ControllerView: NSView {
    var readings = PadReadings()

    override var isFlipped: Bool { false }

    private func fill(_ path: NSBezierPath, on: Bool, onColor: NSColor = .controlAccentColor) {
        (on ? onColor : NSColor.quaternaryLabelColor).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func label(_ text: String, at p: CGPoint, color: NSColor = .labelColor, size: CGFloat = 11) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: color]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        s.draw(at: CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2))
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = readings
        let W = bounds.width, H = bounds.height
        let dim = r.connected ? 1.0 : 0.35

        // Body
        let body = NSBezierPath(roundedRect: NSRect(x: W * 0.08, y: H * 0.12, width: W * 0.84, height: H * 0.62), xRadius: 40, yRadius: 40)
        NSColor.controlBackgroundColor.withAlphaComponent(dim).setFill(); body.fill()
        NSColor.separatorColor.setStroke(); body.lineWidth = 1.5; body.stroke()

        // Triggers (fill by value) and bumpers
        for (side, trig, bump) in [("L", r.leftTrigger, "L1"), ("R", r.rightTrigger, "R1")] {
            let x = side == "L" ? W * 0.14 : W * 0.72
            let tRect = NSRect(x: x, y: H * 0.80, width: W * 0.14, height: H * 0.14)
            let t = NSBezierPath(roundedRect: tRect, xRadius: 6, yRadius: 6)
            fill(t, on: false)
            let level = NSRect(x: tRect.minX, y: tRect.minY, width: tRect.width, height: tRect.height * CGFloat(trig))
            NSColor.controlAccentColor.setFill(); NSBezierPath(roundedRect: level, xRadius: 6, yRadius: 6).fill()
            label("\(side)2 \(Int(trig * 100))%", at: CGPoint(x: tRect.midX, y: tRect.midY), color: trig > 0.5 ? .white : .labelColor)
            let bRect = NSRect(x: x, y: H * 0.745, width: W * 0.14, height: H * 0.05)
            fill(NSBezierPath(roundedRect: bRect, xRadius: 4, yRadius: 4), on: r.pressed.contains(bump))
            label(bump, at: CGPoint(x: bRect.midX, y: bRect.midY), color: r.pressed.contains(bump) ? .white : .labelColor, size: 9)
        }

        // D-pad
        let dc = CGPoint(x: W * 0.22, y: H * 0.55)
        let arm: CGFloat = 26, thick: CGFloat = 20
        let dpad: [(String, NSRect)] = [
            ("up", NSRect(x: dc.x - thick / 2, y: dc.y + 4, width: thick, height: arm)),
            ("down", NSRect(x: dc.x - thick / 2, y: dc.y - 4 - arm, width: thick, height: arm)),
            ("left", NSRect(x: dc.x - 4 - arm, y: dc.y - thick / 2, width: arm, height: thick)),
            ("right", NSRect(x: dc.x + 4, y: dc.y - thick / 2, width: arm, height: thick)),
        ]
        for (k, rect) in dpad { fill(NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4), on: r.pressed.contains(k)) }

        // Face buttons with PlayStation colors
        let fc = CGPoint(x: W * 0.78, y: H * 0.55)
        let faces: [(String, CGPoint, String, NSColor)] = [
            ("triangle", CGPoint(x: fc.x, y: fc.y + 30), "△", .systemGreen),
            ("cross", CGPoint(x: fc.x, y: fc.y - 30), "✕", .systemBlue),
            ("square", CGPoint(x: fc.x - 30, y: fc.y), "□", .systemPink),
            ("circle", CGPoint(x: fc.x + 30, y: fc.y), "○", .systemRed),
        ]
        for (k, p, glyph, color) in faces {
            let on = r.pressed.contains(k)
            fill(NSBezierPath(ovalIn: NSRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26)), on: on, onColor: color)
            label(glyph, at: p, color: on ? .white : color, size: 13)
        }

        // Sticks
        for (side, pos, key) in [("L", r.leftStick, "L3"), ("R", r.rightStick, "R3")] {
            let c = CGPoint(x: side == "L" ? W * 0.36 : W * 0.64, y: H * 0.30)
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - 26, y: c.y - 26, width: 52, height: 52))
            fill(ring, on: r.pressed.contains(key))
            let knob = CGPoint(x: c.x + pos.x * 18, y: c.y + pos.y * 18)
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: knob.x - 8, y: knob.y - 8, width: 16, height: 16)).fill()
            label(key, at: CGPoint(x: c.x, y: c.y - 38), color: .secondaryLabelColor, size: 9)
        }

        // Share, Options, PS, touchpad
        let tp = NSRect(x: W * 0.40, y: H * 0.56, width: W * 0.20, height: H * 0.12)
        fill(NSBezierPath(roundedRect: tp, xRadius: 6, yRadius: 6), on: r.pressed.contains("touchpad"))
        label("touchpad", at: CGPoint(x: tp.midX, y: tp.midY), color: r.pressed.contains("touchpad") ? .white : .tertiaryLabelColor, size: 9)
        let share = NSRect(x: W * 0.355, y: H * 0.58, width: 14, height: 22)
        fill(NSBezierPath(roundedRect: share, xRadius: 4, yRadius: 4), on: r.pressed.contains("share"))
        label("Share", at: CGPoint(x: share.midX, y: share.minY - 9), color: .secondaryLabelColor, size: 8)
        let opts = NSRect(x: W * 0.631, y: H * 0.58, width: 14, height: 22)
        fill(NSBezierPath(roundedRect: opts, xRadius: 4, yRadius: 4), on: r.pressed.contains("options"))
        label("Options", at: CGPoint(x: opts.midX, y: opts.minY - 9), color: .secondaryLabelColor, size: 8)
        let psc = CGPoint(x: W * 0.5, y: H * 0.42)
        fill(NSBezierPath(ovalIn: NSRect(x: psc.x - 11, y: psc.y - 11, width: 22, height: 22)), on: r.pressed.contains("ps"))
        label("PS", at: psc, color: r.pressed.contains("ps") ? .white : .labelColor, size: 9)

        if !r.connected {
            label("No controller reaching the Mac", at: CGPoint(x: W / 2, y: H * 0.06), color: .systemRed, size: 12)
        }
    }
}

/// The tester window: schematic on top, checks and warnings underneath, a reset button.
final class TesterWindow {
    private var window: NSWindow?
    private var view: ControllerView?
    private var checks: NSTextField?
    private var timer: Timer?
    private let readings = PadReadings()

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Button tester"
            let cv = ControllerView(frame: NSRect(x: 20, y: 250, width: 600, height: 290))
            cv.readings = readings
            w.contentView?.addSubview(cv)
            let c = NSTextField(wrappingLabelWithString: "")
            c.font = NSFont.systemFont(ofSize: 12)
            c.frame = NSRect(x: 24, y: 48, width: 592, height: 190)
            w.contentView?.addSubview(c)
            let reset = NSButton(title: "Start over", target: self, action: #selector(resetChecks))
            reset.frame = NSRect(x: 24, y: 12, width: 110, height: 28)
            w.contentView?.addSubview(reset)
            w.isReleasedWhenClosed = false
            window = w
            view = cv
            checks = c
        }
        GCController.startWirelessControllerDiscovery { }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        GuideWindow.center(window!)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func resetChecks() { readings.reset() }

    private func tick() {
        guard let w = window, w.isVisible else { timer?.invalidate(); return }
        if let c = GCController.controllers().first(where: { $0.extendedGamepad != nil }) {
            readings.update(from: c)
        } else {
            readings.connected = false
        }
        view?.needsDisplay = true
        checks?.attributedStringValue = checklist()
    }

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
        var head = "\(r.name)"
        if r.battery > 0 { head += ", battery \(Int(r.battery * 100))%" }
        out.append(NSAttributedString(string: head + "\n", attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)]))
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
        if r.battery <= 0 { row(false, "Battery: this pad gives no reading over Bluetooth; charge it when the light bar blinks orange") }
        if r.leftRestMin > 0.08 { row(nil, String(format: "Left stick never rests at centre, drift %.0f%%", r.leftRestMin * 100)) }
        if r.rightRestMin > 0.08 { row(nil, String(format: "Right stick never rests at centre, drift %.0f%%", r.rightRestMin * 100)) }
        if r.leftTriggerMax > 0.3 && r.leftTriggerMax < 0.95 { row(nil, String(format: "L2 only reaches %.0f%%", r.leftTriggerMax * 100)) }
        if r.rightTriggerMax > 0.3 && r.rightTriggerMax < 0.95 { row(nil, String(format: "R2 only reaches %.0f%%", r.rightTriggerMax * 100)) }
        // This pad reports zero when it has no battery reading, so only a real low value warns.
        if r.battery > 0 && r.battery < 0.2 { row(nil, "Battery low, charge the pad") }
        return out
    }
}
