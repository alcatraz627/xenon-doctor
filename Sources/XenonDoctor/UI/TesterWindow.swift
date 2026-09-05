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
