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

/// The tester tab: schematic on top, checks and warnings underneath, a reset button.
/// Polls the pad thirty times a second while the tab is on screen and stops when it is not.
final class TesterPane: NSView {
    private let view: ControllerView
    private let checks: NSTextField
    private var timer: Timer?
    private let readings = PadReadings()

    init() {
        view = ControllerView(frame: NSRect(x: 20, y: 270, width: 600, height: 290))
        checks = NSTextField(wrappingLabelWithString: "")
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 580))
        autoresizingMask = [.width, .height]
        view.readings = readings
        view.autoresizingMask = [.width, .minYMargin]
        addSubview(view)
        checks.font = NSFont.systemFont(ofSize: 12)
        checks.frame = NSRect(x: 24, y: 56, width: 592, height: 200)
        checks.autoresizingMask = [.width, .height]
        addSubview(checks)
        let reset = NSButton(title: "Start over", target: self, action: #selector(resetChecks))
        reset.frame = NSRect(x: 24, y: 16, width: 110, height: 28)
        reset.autoresizingMask = [.maxXMargin, .maxYMargin]
        addSubview(reset)
        let tip = NSTextField(labelWithString: "drag to orbit, scroll to zoom, double-click to re-centre")
        tip.font = NSFont.systemFont(ofSize: 10)
        tip.textColor = .tertiaryLabelColor
        tip.alignment = .right
        tip.frame = NSRect(x: 300, y: 22, width: 316, height: 16)
        tip.autoresizingMask = [.minXMargin, .maxYMargin]
        addSubview(tip)
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
        if let c = GCController.controllers().first(where: { $0.extendedGamepad != nil }) {
            readings.update(from: c)
        } else {
            readings.connected = false
        }
        view.apply()
        checks.attributedStringValue = checklist()
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
        let raw = PadBattery.shared.latest()
        if let b = raw {
            head += b.charging ? ", charging \(b.percent)%" : ", battery \(b.percent)%"
        } else if r.battery > 0 {
            head += ", battery \(Int(r.battery * 100))%"
        }
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
        if raw == nil && r.battery <= 0 { row(false, "Battery: no reading yet; it appears a few seconds after the pad connects") }
        if r.leftRestMin > 0.08 { row(nil, String(format: "Left stick never rests at centre, drift %.0f%%", r.leftRestMin * 100)) }
        if r.rightRestMin > 0.08 { row(nil, String(format: "Right stick never rests at centre, drift %.0f%%", r.rightRestMin * 100)) }
        if r.leftTriggerMax > 0.3 && r.leftTriggerMax < 0.95 { row(nil, String(format: "L2 only reaches %.0f%%", r.leftTriggerMax * 100)) }
        if r.rightTriggerMax > 0.3 && r.rightTriggerMax < 0.95 { row(nil, String(format: "R2 only reaches %.0f%%", r.rightTriggerMax * 100)) }
        let percent = raw?.percent ?? (r.battery > 0 ? Int(r.battery * 100) : 100)
        if percent < 20 && raw?.charging != true { row(nil, "Battery low, charge the pad") }
        return out
    }
}
