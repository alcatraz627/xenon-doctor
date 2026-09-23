import Foundation
import IOBluetooth
import CoreBluetooth

// The two calls blueutil uses to read and set radio power. They live in
// IOBluetooth.framework without public headers, so they are bound by symbol name.
@_silgen_name("IOBluetoothPreferenceGetControllerPowerState")
func btPowerGet() -> Int32
@_silgen_name("IOBluetoothPreferenceSetControllerPowerState")
func btPowerSet(_ state: Int32)

/// Is the Bluetooth radio on, and is this app allowed to use it. Off is the one state a
/// button can fix from here. Denied permission would make every pad look unpaired, so it
/// is caught on this row before the pad row can misreport it.
struct RadioProbe: Probe {
    let link = Link.radio

    static var permissionDenied: Bool {
        switch CBCentralManager.authorization {
        case .denied, .restricted: return true
        default: return false
        }
    }

    /// True until the person has answered macOS's "may Xenon Doctor use Bluetooth" prompt.
    /// Every IOBluetooth call blocks behind that prompt, which used to read as "not answering".
    static var permissionUndecided: Bool { CBCentralManager.authorization == .notDetermined }

    private static var prompter: CBCentralManager?

    /// Makes macOS show the Bluetooth prompt: creating a central manager is the trigger.
    static func askPermission() {
        DispatchQueue.main.async { if prompter == nil { prompter = CBCentralManager(delegate: nil, queue: nil) } }
    }

    func read() -> LinkState {
        if RadioProbe.permissionUndecided {
            RadioProbe.askPermission()
            return LinkState(.radio, ok: false, detail: "waiting for you to allow Bluetooth",
                             hint: "macOS is asking whether Xenon Doctor may use Bluetooth. Click Allow in that dialog; the rows fill in on their own after that.",
                             brief: "Click Allow in the Bluetooth dialog")
        }
        if btPowerGet() != 1 {
            return LinkState(.radio, ok: false, detail: "off", repair: .powerOnRadio)
        }
        if RadioProbe.permissionDenied {
            return LinkState(.radio, ok: false, detail: "on, but Xenon Doctor is not allowed to use it",
                             repair: .openBluetoothPrivacy,
                             hint: "In the Bluetooth privacy list, turn on the switch next to Xenon Doctor, then come back here.",
                             brief: "Switch Xenon Doctor on in the privacy list")
        }
        return LinkState(.radio, ok: true, detail: "on")
    }
}
