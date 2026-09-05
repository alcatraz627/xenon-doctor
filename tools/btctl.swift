// Small Bluetooth control tool: read or set the radio power, list what is paired
// and connected, and ask a known pad to connect. This is the reconnect repair the
// app will ship, exercised first as a command so each step can be watched in
// the Bluetooth daemon's log.
//
// Build:  swiftc -O -framework IOBluetooth -o tools/btctl tools/btctl.swift
// Usage:  btctl status | on | off | cycle | list | connect <MAC> | disconnect <MAC>
import Foundation
import IOBluetooth

// These two are the calls blueutil uses. They live in IOBluetooth.framework but
// are not in the public headers, so they are declared by symbol name here.
@_silgen_name("IOBluetoothPreferenceGetControllerPowerState")
func btPowerGet() -> Int32
@_silgen_name("IOBluetoothPreferenceSetControllerPowerState")
func btPowerSet(_ state: Int32)

func waitForPower(_ want: Int32, timeout: TimeInterval = 8) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if btPowerGet() == want { return true }
        Thread.sleep(forTimeInterval: 0.2)
    }
    return btPowerGet() == want
}

func list() {
    guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
        print("no paired devices"); return
    }
    for d in devices {
        let name = d.name ?? "?"
        let addr = d.addressString ?? "?"
        let state = d.isConnected() ? "connected" : "not connected"
        print("\(addr)  \(state)  \(name)")
    }
}

func device(_ mac: String) -> IOBluetoothDevice? {
    IOBluetoothDevice(addressString: mac)
}

let args = CommandLine.arguments.dropFirst()
guard let cmd = args.first else {
    print("usage: btctl status | on | off | cycle | list | connect <MAC> | disconnect <MAC>")
    exit(2)
}

switch cmd {
case "status":
    print(btPowerGet() == 1 ? "on" : "off")
case "on":
    btPowerSet(1)
    print(waitForPower(1) ? "on" : "failed to power on")
case "off":
    btPowerSet(0)
    print(waitForPower(0) ? "off" : "failed to power off")
case "cycle":
    btPowerSet(0)
    let offOK = waitForPower(0)
    Thread.sleep(forTimeInterval: 2)
    btPowerSet(1)
    let onOK = waitForPower(1)
    print("cycle: off=\(offOK) on=\(onOK)")
case "list":
    list()
case "connect":
    guard args.count >= 2, let d = device(args.dropFirst().first!) else { print("need MAC"); exit(2) }
    if d.isConnected() { print("already connected"); exit(0) }
    let r = d.openConnection()
    // openConnection is synchronous when no target is given; r is an IOReturn.
    print(r == kIOReturnSuccess ? "connected" : String(format: "openConnection failed: 0x%08x", r))
    Thread.sleep(forTimeInterval: 1)
    print(d.isConnected() ? "state: connected" : "state: not connected")
case "disconnect":
    guard args.count >= 2, let d = device(args.dropFirst().first!) else { print("need MAC"); exit(2) }
    let r = d.closeConnection()
    print(r == kIOReturnSuccess ? "disconnected" : String(format: "closeConnection failed: 0x%08x", r))
default:
    print("unknown command \(cmd)"); exit(2)
}
