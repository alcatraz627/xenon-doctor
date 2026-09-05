import Foundation
import AppKit

/// Green: fine. Yellow: broken, and one button fixes it. Red: broken, and only a person can fix it.
enum Severity: Int, Comparable {
    case fine = 0, fixable = 1, needsYou = 2

    static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }

    /// For dots and glyphs, where a bright yellow reads well.
    var color: NSColor {
        switch self {
        case .fine: return .systemGreen
        case .fixable: return .systemYellow
        case .needsYou: return .systemRed
        }
    }

    /// For words. System yellow vanishes on a light menu, so text gets an amber that
    /// keeps the same meaning and stays readable; dark menus keep the bright yellow.
    var textColor: NSColor {
        switch self {
        case .fine: return .systemGreen
        case .needsYou: return .systemRed
        case .fixable:
            return NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return dark ? .systemYellow : NSColor(srgbRed: 0.66, green: 0.45, blue: 0.0, alpha: 1)
            }
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

/// A button the app can offer. The first five repair something; the last three take the
/// person to the one place where the fix lives, because the app cannot do it for them.
enum RepairKind: String, CaseIterable {
    case powerOnRadio, reconnectPad, restartSteam, relaunchGame, applyPin
    case openBluetoothPrivacy, installSteam, installGame

    var title: String {
        switch self {
        case .powerOnRadio: return "Turn Bluetooth on"
        case .reconnectPad: return "Reconnect controller"
        case .restartSteam: return "Restart Steam"
        case .relaunchGame: return "Relaunch Stardew Valley"
        case .applyPin: return "Fix Steam settings"
        case .openBluetoothPrivacy: return "Open Bluetooth privacy settings"
        case .installSteam: return "Get Steam"
        case .installGame: return "Install Stardew Valley in Steam"
        }
    }

    /// True for the buttons that open a window elsewhere and leave the person to finish.
    var goesThere: Bool {
        switch self {
        case .openBluetoothPrivacy, .installSteam, .installGame: return true
        default: return false
        }
    }
}

/// What one link looks like right now: fine, or broken with the one button that fixes it.
/// `hint` is the full sentence for a person, shown in the window. `brief` is its one-line
/// form for the menu; when a probe gives none, the menu shows the hint's first clause.
struct LinkState {
    let link: Link
    let ok: Bool
    let detail: String
    let repair: RepairKind?
    let hint: String?
    let brief: String?

    init(_ link: Link, ok: Bool, detail: String, repair: RepairKind? = nil, hint: String? = nil, brief: String? = nil) {
        self.link = link
        self.ok = ok
        self.detail = detail
        self.repair = repair
        self.hint = hint
        self.brief = brief
    }

    var severity: Severity {
        if ok { return .fine }
        return repair != nil ? .fixable : .needsYou
    }

    /// Two or three words for the menu bar when this link is the problem.
    var shortHint: String {
        switch link {
        case .radio: return "Bluetooth"
        case .pad: return detail.hasPrefix("no ") ? "pair pad" : "pad off"
        case .steam: return "Steam"
        case .game: return "game"
        }
    }

    /// One line for the menu, capped so the menu never grows a paragraph.
    var menuHint: String? {
        if let b = brief { return b }
        guard let h = hint else { return nil }
        let firstClause = h.split(whereSeparator: { $0 == "." || $0 == ":" }).first.map(String.init) ?? h
        let trimmed = firstClause.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 64 ? String(trimmed.prefix(61)) + "…" : trimmed
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
