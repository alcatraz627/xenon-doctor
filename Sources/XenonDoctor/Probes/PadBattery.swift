import Foundation
import IOKit.hid

/// The pad's battery, read from the report the pad itself sends over Bluetooth. macOS's
/// GameController layer reports zero for this pad, so the app listens to the raw HID
/// reports instead: a DualShock 4 carries its charge in one byte of every input report.
///
/// Over Bluetooth the pad sends a short report (id 0x01) with no battery byte until
/// something asks it for a feature report, after which it switches to the full report
/// (id 0x11) for the rest of the connection. The game does that ask on its own; the app
/// does it too, so the level is known before the game starts. Nothing is written to
/// the pad, and the device is opened shared, never seized.
final class PadBattery {
    static let shared = PadBattery()

    struct Reading {
        let percent: Int
        let charging: Bool
        let at: Date
    }

    private var manager: IOHIDManager?
    private var buffers: [UnsafeMutableRawPointer: UnsafeMutablePointer<UInt8>] = [:]
    private var readings: [String: Reading] = [:]
    private let lock = NSLock()
    private var started = false
    private static let bufferSize = 128

    /// Starts listening on the main run loop. Safe to call many times.
    func start() {
        lock.lock(); defer { lock.unlock() }
        guard !started else { return }
        started = true
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [kIOHIDVendorIDKey: Pads.vendorID, kIOHIDProductIDKey: Pads.productID]
        IOHIDManagerSetDeviceMatching(m, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, device in
            guard let ctx = ctx else { return }
            Unmanaged<PadBattery>.fromOpaque(ctx).takeUnretainedValue().attach(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, device in
            guard let ctx = ctx else { return }
            Unmanaged<PadBattery>.fromOpaque(ctx).takeUnretainedValue().detach(device)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
    }

    /// The latest reading for a pad, by its Bluetooth address, or nil when the pad has not
    /// reported since it connected. Readings older than a minute are treated as gone.
    func reading(forMAC mac: String) -> Reading? {
        lock.lock(); defer { lock.unlock() }
        guard let r = readings[KnownPad.bare(mac)] else { return nil }
        return Date().timeIntervalSince(r.at) < 60 ? r : nil
    }

    /// The freshest reading from any pad, for surfaces that do not know which pad they show.
    func latest() -> Reading? {
        lock.lock(); defer { lock.unlock() }
        return readings.values.filter { Date().timeIntervalSince($0.at) < 60 }.max { $0.at < $1.at }
    }

    private func attach(_ device: IOHIDDevice) {
        let key = Unmanaged.passUnretained(device).toOpaque()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: PadBattery.bufferSize)
        lock.lock(); buffers[key] = buf; lock.unlock()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buf, CFIndex(PadBattery.bufferSize), { ctx, result, sender, _, reportID, report, length in
            guard let ctx = ctx, let sender = sender, result == kIOReturnSuccess else { return }
            let dev = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            Unmanaged<PadBattery>.fromOpaque(ctx).takeUnretainedValue().handle(dev, reportID: UInt8(reportID), report: report, length: Int(length))
        }, ctx)
        // Ask once for the calibration feature report; the pad answers by switching to
        // full input reports. Either id does it on a DualShock 4; the clone gets both.
        for id in [0x05, 0x02] as [CFIndex] {
            var fb = [UInt8](repeating: 0, count: 64)
            fb[0] = UInt8(id)
            var len: CFIndex = 64
            _ = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, id, &fb, &len)
        }
    }

    private func detach(_ device: IOHIDDevice) {
        let key = Unmanaged.passUnretained(device).toOpaque()
        lock.lock()
        if let buf = buffers.removeValue(forKey: key) { buf.deallocate() }
        if let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String {
            readings.removeValue(forKey: KnownPad.bare(serial))
        }
        lock.unlock()
    }

    private func handle(_ device: IOHIDDevice, reportID: UInt8, report: UnsafeMutablePointer<UInt8>, length: Int) {
        // Layout of the state block is the same for both transports; Bluetooth's full
        // report puts it two bytes further in. Battery byte: low nibble is the level in
        // tenths, bit 4 says a cable is attached.
        let batteryByte: UInt8
        switch reportID {
        case 0x11 where length >= 34: batteryByte = report[32]
        case 0x01 where length >= 32: batteryByte = report[30]
        default: return
        }
        let level = Int(batteryByte & 0x0F)
        let cable = batteryByte & 0x10 != 0
        let percent = cable ? (level >= 11 ? 100 : min(level * 10, 100)) : min(level * 10 + 5, 100)
        guard let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String else { return }
        lock.lock()
        readings[KnownPad.bare(serial)] = Reading(percent: percent, charging: cable, at: Date())
        lock.unlock()
    }
}
