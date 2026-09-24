import Foundation
import IOBluetooth
import GameController

/// Which known pad is connected, and whether macOS's game controller layer sees it as a
/// DualShock. "Connected" is answered by the HID layer (the device list every game reads
/// through, by the pad's serial, which is its Bluetooth address); the Bluetooth stack is
/// only asked when no pad is attached, to say whether one is paired. The tester reads the
/// same two lists, so the two tabs cannot disagree about whether a pad is there.
struct PadProbe: Probe {
    let link = Link.pad
    static let pairingHint = "Hold Share and PS together until the light bar blinks fast, then let go."
    static let pairingBrief = "Hold Share + PS until it blinks fast"

    struct Seen {
        let pad: KnownPad
        let connected: Bool
        let name: String
        let rssi: Int
    }

    /// The last reading, for the tester's device card. Written here, read on the main
    /// thread; the card never asks IOBluetooth itself, because that call can block for good.
    private static var latestLock = NSLock()
    private static var latestSeen: [Seen] = []
    static var latest: [Seen] {
        latestLock.lock(); defer { latestLock.unlock() }
        return latestSeen
    }

    private static func remember(_ seen: [Seen]) {
        latestLock.lock()
        latestSeen = seen
        latestLock.unlock()
    }

    /// Starts the two listeners this probe and the tester share. Must run on the main
    /// thread once, before any read: GameController and the HID manager deliver on the
    /// main run loop, and starting discovery from a worker thread left the list empty on
    /// the main thread while a worker saw the pad, which is how the two tabs disagreed.
    static func prepare() {
        PadBattery.shared.start()
        // No wireless discovery scan: a paired pad reaches GameController on its own, and
        // an inquiry scan degrades every Bluetooth link while it runs, which read as input
        // lag in the games. Versions up to 0.3.2 scanned every five seconds.
    }

    /// Paired known pads from the Bluetooth stack. Only called when no pad is attached.
    func pairedKnownPads() -> [Seen] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        var out: [Seen] = []
        for d in devices {
            guard let addr = d.addressString, let pad = Pads.pad(forMAC: addr) else { continue }
            if out.contains(where: { $0.pad.mark == pad.mark }) { continue }
            let connected = d.isConnected()
            out.append(Seen(pad: pad, connected: connected, name: d.name ?? "", rssi: connected ? Int(d.rawRSSI()) : 127))
        }
        return out
    }

    static func isDualShock(_ c: GCController) -> Bool {
        c.productCategory.contains("DualShock") || c.extendedGamepad is GCDualShockGamepad
    }

    /// "battery 70%" or "charging 70%", from the pad's own report first, GameController second.
    static func batteryText(for pad: KnownPad, controller: GCController?) -> String? {
        if let r = PadBattery.shared.reading(forMAC: pad.mac) {
            return r.charging ? "charging \(r.percent)%" : "battery \(r.percent)%"
        }
        if let level = controller?.battery?.batteryLevel, level > 0 {
            return "battery \(Int(level * 100))%"
        }
        return nil
    }

    /// The pads attached at the HID layer and the controllers GameController lists. A cold
    /// process (the --status command) is given a moment for both to fill.
    static func attachedNow(wait: TimeInterval = 2.5) -> (pads: [KnownPad], any: Bool, gc: [GCController]) {
        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline {
            if PadBattery.shared.anyAttached || !GCController.controllers().isEmpty { break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        // The game controller layer can trail the HID layer by several seconds on a cold
        // process; give it that long before calling the pad unread.
        let gcDeadline = Date().addingTimeInterval(wait * 2)
        while PadBattery.shared.anyAttached && GCController.controllers().isEmpty && Date() < gcDeadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        return (PadBattery.shared.attachedPads(), PadBattery.shared.anyAttached, GCController.controllers())
    }

    func read() -> LinkState {
        let now = PadProbe.attachedNow()
        let dualShocks = now.gc.filter { PadProbe.isDualShock($0) }

        if !now.pads.isEmpty {
            let marks = now.pads.map { $0.mark }.joined(separator: " and ")
            PadProbe.remember(now.pads.map { Seen(pad: $0, connected: true, name: now.gc.first?.vendorName ?? "", rssi: 127) })
            if dualShocks.isEmpty, let other = now.gc.first {
                let kind = other.productCategory.isEmpty ? "another kind of controller" : "a \(other.productCategory)"
                return LinkState(.pad, ok: false, detail: "\(marks) connected in the wrong mode, seen as \(kind)",
                                 hint: "Turn the pad off (hold PS for ten seconds), then hold Share and PS together until the light bar blinks fast. That puts it back in PS4 mode.",
                                 brief: "Wrong mode: turn off, then Share + PS")
            }
            if dualShocks.isEmpty {
                // The pad's reports reach this app, so Stardew and Undertale are fine; only
                // Factorio reads through the layer that has not picked the pad up.
                return LinkState(.pad, ok: false, detail: "\(marks) connected, but macOS's game layer has not picked it up",
                                 repair: .reconnectPad,
                                 hint: "The pad reaches the Mac (the tester works), but the layer Factorio reads through has not noticed it. Reconnect puts it back; Stardew and Undertale are unaffected.",
                                 brief: "Factorio's layer missed it; Reconnect fixes")
            }
            var detail = "\(marks) connected"
            if now.pads.count == 1, let battery = PadProbe.batteryText(for: now.pads[0], controller: dualShocks.first) {
                detail += ", \(battery)"
            }
            if now.pads.count > 1 {
                return LinkState(.pad, ok: true, detail: detail,
                                 hint: "Two pads are on. The game listens to the first one; if the wrong pad is in charge, hold PS on the other for ten seconds to turn it off.",
                                 brief: "Two pads on; the game takes the first")
            }
            return LinkState(.pad, ok: true, detail: detail)
        }

        if now.any || !now.gc.isEmpty {
            // Something with this pad's ids is attached, but it is not in the registry.
            PadProbe.remember([])
            return LinkState(.pad, ok: false, detail: "a Stratos Xenon is connected that is not in the pad list",
                             hint: "Add it once from a terminal: XenonDoctor --add-pad MARK address. Its address is in System Settings, Bluetooth, under the pad's name.",
                             brief: "Unknown pad; add it with --add-pad")
        }

        // Nothing attached: ask the Bluetooth stack whether a pad is at least paired. Not
        // before the person has allowed Bluetooth; the call would block behind the prompt.
        if RadioProbe.permissionUndecided {
            PadProbe.remember([])
            return LinkState(.pad, ok: false, detail: "waiting for you to allow Bluetooth", brief: "Click Allow in the Bluetooth dialog")
        }
        let paired = pairedKnownPads()
        PadProbe.remember(paired)
        if paired.isEmpty {
            return LinkState(.pad, ok: false, detail: "no Stratos Xenon paired to this Mac",
                             hint: "Pair it once: " + PadProbe.pairingHint,
                             brief: "Pair it: " + PadProbe.pairingBrief)
        }
        let marks = paired.map { $0.pad.mark }.joined(separator: " and ")
        return LinkState(.pad, ok: false, detail: "\(marks) paired, not connected",
                         repair: .reconnectPad,
                         hint: "Press PS once. If it blinks, connects, then drops: " + PadProbe.pairingHint,
                         brief: "Press PS. Blinks then drops? " + PadProbe.pairingBrief)
    }
}
