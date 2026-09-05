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

    func read() -> LinkState {
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
