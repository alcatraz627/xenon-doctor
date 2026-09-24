import Foundation
import AppKit
import GameController
import ApplicationServices

/// Turns pad presses into key presses for Undertale, which cannot read a pad on a Mac.
/// Only while Undertale is the front window; the moment it is not, every held key is
/// released. macOS lets an app press keys only with its Accessibility switch on.
///
/// The table is Undertale's own keyboard: arrows move, Z confirms, X cancels, C opens
/// the menu, Enter also confirms.
final class KeyMapper {
    static let shared = KeyMapper()

    /// Virtual key codes on a US layout; Undertale reads codes, not characters.
    enum Key: UInt16, CaseIterable {
        case z = 0x06, x = 0x07, c = 0x08, enter = 0x24
        case left = 0x7B, right = 0x7C, down = 0x7D, up = 0x7E
    }

    /// True when macOS lets this app post key events.
    static var trusted: Bool { AXIsProcessTrusted() }

    /// Asks macOS to list this app under Accessibility (the switch stays off until the
    /// person flips it) and opens that pane.
    static func requestTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private(set) var held = Set<Key>()
    private var started = false
    /// The last time a key went down, for the row's "pad pressing its keys" wording.
    private(set) var lastPress: Date?

    var isFront: Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Game.undertale.bundleID }

    /// Listens to the pad's own reports (the same source as the Status row and the
    /// tester), with macOS's game controller layer as a fallback. Safe to call twice.
    func start() {
        guard !started else { return }
        started = true
        PadBattery.shared.onState = { [weak self] _, s in
            self?.apply(KeyMapper.keys(dpadUp: s.buttons.contains("up"), dpadDown: s.buttons.contains("down"),
                                       dpadLeft: s.buttons.contains("left"), dpadRight: s.buttons.contains("right"),
                                       stickX: s.leftX, stickY: s.leftY,
                                       cross: s.buttons.contains("cross"), circle: s.buttons.contains("circle"),
                                       square: s.buttons.contains("square"), triangle: s.buttons.contains("triangle"),
                                       options: s.buttons.contains("options")))
        }
        for c in GCController.controllers() { hook(c) }
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            if let c = n.object as? GCController { self?.hook(c) }
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            self?.releaseAll()
        }
        NotificationCenter.default.addObserver(forName: PadBattery.padsChanged, object: nil, queue: .main) { [weak self] _ in
            if !PadBattery.shared.anyAttached { self?.releaseAll() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, !self.isFront else { return }
            self.releaseAll()
        }
    }

    private func hook(_ c: GCController) {
        guard let pad = c.extendedGamepad else { return }
        pad.valueChangedHandler = { [weak self] pad, _ in
            // The report path wins while it is alive; this only fills in when it is not.
            guard PadBattery.shared.latestState() == nil else { return }
            self?.apply(KeyMapper.keys(for: pad))
        }
    }

    /// The keys the pad's current state asks for. Pure, so the self-test can check it.
    static func keys(for pad: GCExtendedGamepad) -> Set<Key> {
        keys(dpadUp: pad.dpad.up.isPressed, dpadDown: pad.dpad.down.isPressed,
             dpadLeft: pad.dpad.left.isPressed, dpadRight: pad.dpad.right.isPressed,
             stickX: pad.leftThumbstick.xAxis.value, stickY: pad.leftThumbstick.yAxis.value,
             cross: pad.buttonA.isPressed, circle: pad.buttonB.isPressed,
             square: pad.buttonX.isPressed, triangle: pad.buttonY.isPressed,
             options: pad.buttonMenu.isPressed)
    }

    static func keys(dpadUp: Bool, dpadDown: Bool, dpadLeft: Bool, dpadRight: Bool,
                     stickX: Float, stickY: Float,
                     cross: Bool, circle: Bool, square: Bool, triangle: Bool, options: Bool) -> Set<Key> {
        var out = Set<Key>()
        let edge: Float = 0.5
        if dpadUp || stickY > edge { out.insert(.up) }
        if dpadDown || stickY < -edge { out.insert(.down) }
        if dpadLeft || stickX < -edge { out.insert(.left) }
        if dpadRight || stickX > edge { out.insert(.right) }
        if cross { out.insert(.z) }
        if circle || square { out.insert(.x) }
        if triangle { out.insert(.c) }
        if options { out.insert(.enter) }
        return out
    }

    private func apply(_ wanted: Set<Key>) {
        guard isFront, KeyMapper.trusted else { releaseAll(); return }
        for k in held.subtracting(wanted) { post(k, down: false) }
        for k in wanted.subtracting(held) { post(k, down: true); lastPress = Date() }
        held = wanted
    }

    private func releaseAll() {
        for k in held { post(k, down: false) }
        held.removeAll()
    }

    private func post(_ key: Key, down: Bool) {
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: key.rawValue, keyDown: down) else { return }
        e.post(tap: .cghidEventTap)
    }
}
