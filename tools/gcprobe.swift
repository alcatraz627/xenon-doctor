// Ask macOS's own game controller layer what it sees, and stream button presses for a few seconds.
// This is the same layer Stardew (through SDL) consults, so it separates
// "controller reaches the Mac" from "Steam or the game drops it".
//
// Build:  swiftc -O -o tools/gcprobe tools/gcprobe.swift
// Run:    tools/gcprobe 6        (seconds to listen)
import Foundation
import GameController

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "6") ?? 6
var seen = 0

func describe(_ c: GCController) {
    seen += 1
    let cat = c.productCategory
    let vendor = c.vendorName ?? "?"
    let kind: String
    if c.extendedGamepad is GCDualShockGamepad { kind = "GCDualShockGamepad" }
    else if c.extendedGamepad is GCDualSenseGamepad { kind = "GCDualSenseGamepad" }
    else if c.extendedGamepad is GCXboxGamepad { kind = "GCXboxGamepad" }
    else if c.extendedGamepad != nil { kind = "GCExtendedGamepad (generic)" }
    else { kind = "no extended gamepad profile" }
    print("controller #\(seen): vendor=\(vendor) category=\(cat) profile=\(kind) attachedToDevice=\(c.isAttachedToDevice) battery=\(c.battery?.batteryLevel ?? -1)")
    c.extendedGamepad?.valueChangedHandler = { _, element in
        let name = element.localizedName ?? element.aliases.first ?? "element"
        if let b = element as? GCControllerButtonInput, b.isPressed { print("  press \(name)") }
    }
}

GCController.startWirelessControllerDiscovery { }
NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { n in
    if let c = n.object as? GCController { describe(c) }
}
for c in GCController.controllers() { describe(c) }
print("GameController framework: \(GCController.controllers().count) controller(s) at start; listening \(Int(seconds))s for input")
RunLoop.main.run(until: Date().addingTimeInterval(seconds))
print("done, total controllers seen: \(seen)")
