import Foundation
import AppKit

/// Green: fine. Yellow: broken, and one button fixes it. Red: broken, and only a person can fix it.
enum Severity: Int, Comparable {
    case fine = 0, fixable = 1, needsYou = 2

    static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }

    var color: NSColor {
        switch self {
        case .fine: return .systemGreen
        case .fixable: return .systemYellow
        case .needsYou: return .systemRed
        }
    }

    var word: String {
        switch self {
        case .fine: return "all fine"
        case .fixable: return "one click to fix"
        case .needsYou: return "needs you"
        }
    }
}

/// The four links a game session depends on, in the order a person would check them.
enum Link: String, CaseIterable {
    case radio, pad, steam, game

    var title: String {
        switch self {
        case .radio: return "Bluetooth"
        case .pad: return "Controller"
        case .steam: return "Steam"
        case .game: return "Stardew Valley"
        }
    }
}

/// A repair the app can run with one click. Each maps to one Repair type.
enum RepairKind: String, CaseIterable {
    case powerOnRadio, reconnectPad, restartSteam, relaunchGame, applyPin

    var title: String {
        switch self {
        case .powerOnRadio: return "Turn Bluetooth on"
        case .reconnectPad: return "Reconnect controller"
        case .restartSteam: return "Restart Steam"
        case .relaunchGame: return "Relaunch Stardew Valley"
        case .applyPin: return "Fix Steam settings"
        }
    }
}

/// What one link looks like right now: fine, or broken with the one button that fixes it.
/// `hint` is a sentence for a person, shown when no button can help (for example,
/// "hold Share and PS until the light blinks fast").
struct LinkState {
    let link: Link
    let ok: Bool
    let detail: String
    let repair: RepairKind?
    let hint: String?

    init(_ link: Link, ok: Bool, detail: String, repair: RepairKind? = nil, hint: String? = nil) {
        self.link = link
        self.ok = ok
        self.detail = detail
        self.repair = repair
        self.hint = hint
    }

    var severity: Severity {
        if ok { return .fine }
        return repair != nil ? .fixable : .needsYou
    }

    /// Two or three words for the menu bar when this link is the problem.
    var shortHint: String {
        switch link {
        case .radio: return "Bluetooth off"
        case .pad: return detail.hasPrefix("no ") ? "pair pad" : "pad off"
        case .steam: return "Steam"
        case .game: return "game"
        }
    }
}

struct ChainSnapshot {
    let links: [LinkState]
    let takenAt: Date

    var allOK: Bool { links.allSatisfy { $0.ok } }
    var worst: LinkState? { links.max { $0.severity < $1.severity }.flatMap { $0.ok ? nil : $0 } }
    var severity: Severity { links.map { $0.severity }.max() ?? .fine }

    /// One line per link, the shape `--status` prints.
    var text: String {
        links.map { s in
            let mark = s.ok ? "ok  " : "FIX "
            var line = "\(s.link.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0)) \(mark) \(s.detail)"
            if let r = s.repair { line += "  [\(r.title)]" }
            if let h = s.hint { line += "\n       \(h)" }
            return line
        }.joined(separator: "\n")
    }
}

protocol Probe {
    func read() -> LinkState
}

protocol Repair {
    var kind: RepairKind { get }
    /// Runs the fix and returns the link state it produced, so the menu repaints from the same type.
    func run() -> LinkState
}

/// Runs every probe in order and hands back one snapshot.
struct Chain {
    let probes: [Probe]

    static func standard() -> Chain {
        Chain(probes: [RadioProbe(), PadProbe(), SteamProbe(), GameProbe()])
    }

    func snapshot() -> ChainSnapshot {
        ChainSnapshot(links: probes.map { $0.read() }, takenAt: Date())
    }
}
