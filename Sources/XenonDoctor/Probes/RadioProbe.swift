import Foundation
import IOBluetooth

// The two calls blueutil uses to read and set radio power. They live in
// IOBluetooth.framework without public headers, so they are bound by symbol name.
@_silgen_name("IOBluetoothPreferenceGetControllerPowerState")
func btPowerGet() -> Int32
@_silgen_name("IOBluetoothPreferenceSetControllerPowerState")
func btPowerSet(_ state: Int32)

/// Is the Bluetooth radio on. Off is the one state a button can fix from here.
struct RadioProbe: Probe {
    func read() -> LinkState {
        if btPowerGet() == 1 {
            return LinkState(.radio, ok: true, detail: "on")
        }
        return LinkState(.radio, ok: false, detail: "off", repair: .powerOnRadio)
    }
}
