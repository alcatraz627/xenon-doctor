import Foundation
import IOBluetooth
import GameController

/// Which known pad is paired, which is connected, and whether macOS's own game
/// controller layer sees it as a DualShock. That layer is what Stardew reads through, so a
/// pad that is "connected" in Bluetooth but absent or misread there is the drop the owner
/// keeps hitting. The pad has other modes that show up as a different kind of controller;
/// that is caught here too, with the two buttons that put it back.
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

    /// The last Bluetooth reading, for surfaces on the main thread (the tester's device
    /// card) that must never call IOBluetooth themselves: it can block for good.
    private static var latestLock = NSLock()
    private static var latestSeen: [Seen] = []
    static var latest: [Seen] {
        latestLock.lock(); defer { latestLock.unlock() }
        return latestSeen
    }

    func pairedKnownPads() -> [Seen] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        var out: [Seen] = []
        for d in devices {
            guard let addr = d.addressString, let pad = Pads.pad(forMAC: addr) else { continue }
            if out.contains(where: { $0.pad.mark == pad.mark }) { continue }
            let connected = d.isConnected()
            out.append(Seen(pad: pad, connected: connected, name: d.name ?? "", rssi: connected ? Int(d.rawRSSI()) : 127))
        }
        PadProbe.latestLock.lock()
        PadProbe.latestSeen = out
        PadProbe.latestLock.unlock()
        return out
    }

    /// GameController needs a run loop turn to enumerate. Half a second is enough in
    /// practice, and the same turn lets the battery listener receive a report.
    func gameControllerPads() -> [GCController] {
        PadBattery.shared.start()
        GCController.startWirelessControllerDiscovery { }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        return GCController.controllers()
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

    func read() -> LinkState {
        let paired = pairedKnownPads()
        if paired.isEmpty {
            return LinkState(.pad, ok: false, detail: "no Stratos Xenon paired to this Mac",
                             hint: "Pair it once: " + PadProbe.pairingHint,
                             brief: "Pair it: " + PadProbe.pairingBrief)
        }
        let connected = paired.filter { $0.connected }
        if connected.isEmpty {
            let marks = paired.map { $0.pad.mark }.joined(separator: " and ")
            return LinkState(.pad, ok: false, detail: "\(marks) paired, not connected",
                             repair: .reconnectPad,
                             hint: "If it blinks, connects, then drops: " + PadProbe.pairingHint,
                             brief: "Blinks then drops? " + PadProbe.pairingBrief)
        }
        let gc = gameControllerPads()
        let marks = connected.map { $0.pad.mark }.joined(separator: " and ")
        let dualShocks = gc.filter { PadProbe.isDualShock($0) }
        if dualShocks.isEmpty, let other = gc.first {
            let kind = other.productCategory.isEmpty ? "another kind of controller" : "a \(other.productCategory)"
            return LinkState(.pad, ok: false, detail: "\(marks) connected in the wrong mode, seen as \(kind)",
                             hint: "Turn the pad off (hold PS for ten seconds), then hold Share and PS together until the light bar blinks fast. That puts it back in PS4 mode.",
                             brief: "Wrong mode: turn off, then Share + PS")
        }
        if dualShocks.isEmpty {
            return LinkState(.pad, ok: false, detail: "\(marks) connected but macOS is not reading it",
                             repair: .reconnectPad, hint: PadProbe.pairingHint, brief: PadProbe.pairingBrief)
        }
        var detail = "\(marks) connected"
        if connected.count == 1, let battery = PadProbe.batteryText(for: connected[0].pad, controller: dualShocks.first) {
            detail += ", \(battery)"
        }
        if connected.count > 1 {
            return LinkState(.pad, ok: true, detail: detail,
                             hint: "Two pads are on. Stardew listens to the first one; if the wrong pad is in charge, hold PS on the other for ten seconds to turn it off.",
                             brief: "Two pads on; the game takes the first")
        }
        return LinkState(.pad, ok: true, detail: detail)
    }
}
