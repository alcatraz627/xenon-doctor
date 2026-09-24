import Foundation
import IOKit.hid

/// The pad's battery, read from the report the pad itself sends over Bluetooth. macOS's
/// GameController layer reports zero for this pad, so the app listens to the raw HID
/// reports instead: a DualShock 4 carries its charge in one byte of every input report.
///
/// Over Bluetooth the pad sends a short report (id 0x01) with no battery byte until
/// something asks it for a feature report, after which it switches to the full report
/// (id 0x11) for the rest of the connection. The game does that ask on its own; the app
/// does not, so it neither freezes on a pad that will not answer nor disturbs the pad a
/// game is reading. The level is known once a game is running. The device is opened
/// shared, never seized.
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
    /// Pads attached right now, by bare serial (the pad's Bluetooth address), with the
    /// time each appeared. This is the one answer to "is a pad connected" that every
    /// surface reads, because it comes from the HID layer the games read through.
    private var attached: [String: Date] = [:]
    private let lock = NSLock()
    private var started = false
    private static let bufferSize = 128

    /// The known pads attached at the HID layer, in the order they appeared.
    func attachedPads() -> [KnownPad] {
        lock.lock(); defer { lock.unlock() }
        return attached.sorted { $0.value < $1.value }.compactMap { Pads.pad(forMAC: $0.key) }
    }

    /// True when any device with the pad's vendor and product id is attached, known or not.
    var anyAttached: Bool {
        lock.lock(); defer { lock.unlock() }
        return !attached.isEmpty
    }

    /// Starts listening on the main run loop. Safe to call many times.
    func start() {
        lock.lock()
        if started { lock.unlock(); return }
        started = true
        lock.unlock()
        // No self.lock during IOKit setup: IOHIDManagerOpen calls attach on the main run
        // loop, which needs the same lock; holding it here deadlocked against a probe thread.
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
        let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
        lock.lock()
        buffers[key] = buf
        if let s = serial { attached[KnownPad.bare(s)] = Date() }
        lock.unlock()
        NotificationCenter.default.post(name: PadBattery.padsChanged, object: nil)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buf, CFIndex(PadBattery.bufferSize), { ctx, result, sender, _, reportID, report, length in
            guard let ctx = ctx, let sender = sender, result == kIOReturnSuccess else { return }
            let dev = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            Unmanaged<PadBattery>.fromOpaque(ctx).takeUnretainedValue().handle(dev, reportID: UInt8(reportID), report: report, length: Int(length))
        }, ctx)
        // No feature report is sent. A synchronous IOHIDDeviceGetReport here froze the app
        // for good when the pad did not answer, and it also flipped the pad's report mode
        // under any game reading it. Battery comes only from the full reports (id 0x11) the
        // game triggers on its own.
    }

    private func detach(_ device: IOHIDDevice) {
        let key = Unmanaged.passUnretained(device).toOpaque()
        lock.lock()
        if let buf = buffers.removeValue(forKey: key) { buf.deallocate() }
        if let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String {
            readings.removeValue(forKey: KnownPad.bare(serial))
            attached.removeValue(forKey: KnownPad.bare(serial))
        }
        lock.unlock()
        NotificationCenter.default.post(name: PadBattery.padsChanged, object: nil)
    }

    /// Posted on the main thread when a pad attaches or detaches, so the rows re-read at once.
    static let padsChanged = Notification.Name("XenonDoctor.padsChanged")

    /// What the pad's sticks, triggers and buttons are doing right now, straight from its
    /// report. This is what the tester draws and the Undertale mapper reads, so neither
    /// depends on macOS's game controller layer noticing the pad.
    struct State: Equatable {
        var buttons = Set<String>()
        var leftX: Float = 0, leftY: Float = 0, rightX: Float = 0, rightY: Float = 0
        var leftTrigger: Float = 0, rightTrigger: Float = 0
        var at = Date.distantPast
    }

    private var states: [String: State] = [:]
    /// Called on the main thread with every report that changes the state of a pad.
    var onState: ((KnownPad?, State) -> Void)?

    /// The latest state of a pad, or nil when it has sent nothing for two seconds.
    func state(forMAC mac: String) -> State? {
        lock.lock(); defer { lock.unlock() }
        guard let s = states[KnownPad.bare(mac)], Date().timeIntervalSince(s.at) < 2 else { return nil }
        return s
    }

    /// The freshest state from any pad.
    func latestState() -> State? {
        lock.lock(); defer { lock.unlock() }
        return states.values.filter { Date().timeIntervalSince($0.at) < 2 }.max { $0.at < $1.at }
    }

    /// The DualShock 4 state block: sticks, D-pad and buttons, triggers. `base` is where
    /// the block starts in the report (1 for the short report, 3 for the full one).
    static func parse(_ report: UnsafeMutablePointer<UInt8>, base: Int) -> State {
        func axis(_ b: UInt8) -> Float { (Float(b) - 127.5) / 127.5 }
        var s = State()
        s.leftX = axis(report[base]); s.leftY = -axis(report[base + 1])
        s.rightX = axis(report[base + 2]); s.rightY = -axis(report[base + 3])
        let b1 = report[base + 4], b2 = report[base + 5], b3 = report[base + 6]
        switch b1 & 0x0F {
        case 0: s.buttons.insert("up")
        case 1: s.buttons.formUnion(["up", "right"])
        case 2: s.buttons.insert("right")
        case 3: s.buttons.formUnion(["down", "right"])
        case 4: s.buttons.insert("down")
        case 5: s.buttons.formUnion(["down", "left"])
        case 6: s.buttons.insert("left")
        case 7: s.buttons.formUnion(["up", "left"])
        default: break
        }
        if b1 & 0x10 != 0 { s.buttons.insert("square") }
        if b1 & 0x20 != 0 { s.buttons.insert("cross") }
        if b1 & 0x40 != 0 { s.buttons.insert("circle") }
        if b1 & 0x80 != 0 { s.buttons.insert("triangle") }
        if b2 & 0x01 != 0 { s.buttons.insert("L1") }
        if b2 & 0x02 != 0 { s.buttons.insert("R1") }
        if b2 & 0x10 != 0 { s.buttons.insert("share") }
        if b2 & 0x20 != 0 { s.buttons.insert("options") }
        if b2 & 0x40 != 0 { s.buttons.insert("L3") }
        if b2 & 0x80 != 0 { s.buttons.insert("R3") }
        if b3 & 0x01 != 0 { s.buttons.insert("ps") }
        if b3 & 0x02 != 0 { s.buttons.insert("touchpad") }
        s.leftTrigger = Float(report[base + 7]) / 255
        s.rightTrigger = Float(report[base + 8]) / 255
        return s
    }

    private func handle(_ device: IOHIDDevice, reportID: UInt8, report: UnsafeMutablePointer<UInt8>, length: Int) {
        // The state block sits at byte 1 of the short report (id 0x01) and byte 3 of the
        // full one (id 0x11). Battery is two bytes past the block's end and only in the
        // full report or the 64-byte short one: low nibble is the level in tenths, bit 4
        // says a cable is attached.
        let base: Int
        let batteryByte: UInt8?
        switch reportID {
        case 0x11 where length >= 12: base = 3; batteryByte = length >= 34 ? report[32] : nil
        case 0x01 where length >= 10: base = 1; batteryByte = length >= 32 ? report[30] : nil
        default: return
        }
        guard let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String else { return }
        let mac = KnownPad.bare(serial)
        var state = PadBattery.parse(report, base: base)
        state.at = Date()
        lock.lock()
        let previous = states[mac]
        states[mac] = state
        if let b = batteryByte {
            let level = Int(b & 0x0F)
            let cable = b & 0x10 != 0
            let percent = cable ? (level >= 11 ? 100 : min(level * 10, 100)) : min(level * 10 + 5, 100)
            readings[mac] = Reading(percent: percent, charging: cable, at: Date())
        }
        lock.unlock()
        if let cb = onState, previous.map({ $0.buttons != state.buttons || $0.leftX != state.leftX || $0.leftY != state.leftY }) ?? true {
            let pad = Pads.pad(forMAC: mac)
            if Thread.isMainThread { cb(pad, state) } else { DispatchQueue.main.async { cb(pad, state) } }
        }
    }
}
