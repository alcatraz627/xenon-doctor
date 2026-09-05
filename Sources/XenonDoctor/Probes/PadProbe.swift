import Foundation
import IOBluetooth
import GameController

/// Which known pad is paired, which is connected, and whether macOS's own game
/// controller layer sees it. That layer is what Stardew reads through, so a pad that
/// is "connected" in Bluetooth but absent here is the drop the owner keeps hitting.
struct PadProbe: Probe {
    static let pairingHint = "Hold Share and PS together until the light bar blinks fast, then let go."

    struct Seen {
        let pad: KnownPad
        let connected: Bool
    }

    func pairedKnownPads() -> [Seen] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        var out: [Seen] = []
        for d in devices {
            guard let addr = d.addressString, let pad = Pads.pad(forMAC: addr) else { continue }
            if out.contains(where: { $0.pad.mark == pad.mark }) { continue }
            out.append(Seen(pad: pad, connected: d.isConnected()))
        }
        return out
    }

    /// GameController needs a run loop turn to enumerate. Half a second is enough in practice.
    func gameControllerPads() -> [GCController] {
        GCController.startWirelessControllerDiscovery { }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        return GCController.controllers().filter { $0.productCategory.contains("DualShock") || ($0.vendorName ?? "").contains("Controller") }
    }

    func read() -> LinkState {
        let paired = pairedKnownPads()
        if paired.isEmpty {
            return LinkState(.pad, ok: false, detail: "no Stratos Xenon paired to this Mac",
                             hint: "Pair it once: " + PadProbe.pairingHint)
        }
        let connected = paired.filter { $0.connected }
        if connected.isEmpty {
            let marks = paired.map { $0.pad.mark }.joined(separator: " and ")
            return LinkState(.pad, ok: false, detail: "\(marks) paired, not connected",
                             repair: .reconnectPad,
                             hint: "If it blinks, connects, then drops: " + PadProbe.pairingHint)
        }
        let gc = gameControllerPads()
        let marks = connected.map { $0.pad.mark }.joined(separator: " and ")
        if gc.isEmpty {
            return LinkState(.pad, ok: false, detail: "\(marks) connected but macOS is not reading it",
                             repair: .reconnectPad, hint: PadProbe.pairingHint)
        }
        var detail = "\(marks) connected"
        if let level = gc.first?.battery?.batteryLevel, level > 0 {
            detail += ", battery \(Int(level * 100))%"
        }
        return LinkState(.pad, ok: true, detail: detail)
    }
}
