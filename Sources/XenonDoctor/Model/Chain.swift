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
    /// Fine because nothing is happening (Steam or the game not running). Drawn as a
    /// faded green so a row that is merely dormant reads differently from one at work.
    let idle: Bool

    init(_ link: Link, ok: Bool, detail: String, repair: RepairKind? = nil, hint: String? = nil, brief: String? = nil, idle: Bool = false) {
        self.link = link
        self.ok = ok
        self.detail = detail
        self.repair = repair
        self.hint = hint
        self.brief = brief
        self.idle = idle
    }

    var severity: Severity {
        if ok { return .fine }
        return repair != nil ? .fixable : .needsYou
    }

    var dotColor: NSColor {
        ok && idle ? NSColor.systemGreen.withAlphaComponent(0.4) : severity.color
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

    /// Every link fine and the game up: the one moment the app has nothing left to say.
    var playing: Bool {
        allOK && links.contains { $0.link == .game && $0.detail.hasPrefix("running") }
    }
    static let playingLine = "Choppa da Wood (enjoy the game)"

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
    var link: Link { get }
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

    /// Probes that are still running from an earlier snapshot. A system call that never
    /// returns (seen: the Bluetooth power-state query, four threads deep) must not stall
    /// the rows or spawn a new stuck thread every five seconds.
    private static var inFlight = Set<Link>()
    private static var lastGood = [Link: LinkState]()
    private static let lock = NSLock()
    static let probeTimeout: TimeInterval = 6

    func snapshot() -> ChainSnapshot {
        if ProcessInfo.processInfo.environment["XENON_DEMO"] == "playing" { return Chain.demoPlaying }
        let group = DispatchGroup()
        var fresh = [Link: LinkState]()
        for p in probes {
            Chain.lock.lock()
            let busy = Chain.inFlight.contains(p.link)
            if !busy { Chain.inFlight.insert(p.link) }
            Chain.lock.unlock()
            if busy { continue }
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let s = p.read()
                Chain.lock.lock()
                fresh[s.link] = s
                Chain.lastGood[s.link] = s
                Chain.inFlight.remove(s.link)
                Chain.lock.unlock()
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + Chain.probeTimeout)
        Chain.lock.lock()
        let links = Link.allCases.map { link in
            fresh[link] ?? Chain.lastGood[link].map { Chain.stale($0) } ?? Chain.notAnswering(link)
        }
        Chain.lock.unlock()
        return ChainSnapshot(links: links, takenAt: Date())
    }

    /// The row shown while a probe has not come back: what the person can do about it.
    static func notAnswering(_ link: Link) -> LinkState {
        switch link {
        case .radio:
            return LinkState(.radio, ok: false, detail: "not answering",
                             hint: "macOS's Bluetooth service is not replying. Turn Bluetooth off and on from the menu bar; if that does not help, restart the Mac.",
                             brief: "Turn Bluetooth off and on from the menu bar")
        case .pad:
            return LinkState(.pad, ok: false, detail: "not answering",
                             hint: "The Bluetooth device list is not replying. Turn Bluetooth off and on from the menu bar.",
                             brief: "Turn Bluetooth off and on from the menu bar")
        default:
            return LinkState(link, ok: false, detail: "not answering", hint: "The check is taking too long; it retries on its own.", brief: "Retrying")
        }
    }

    /// A previous answer carried forward while the current read is still running.
    static func stale(_ s: LinkState) -> LinkState {
        LinkState(s.link, ok: s.ok, detail: s.detail + " (last reading)", repair: s.repair, hint: s.hint, brief: s.brief, idle: s.idle)
    }

    /// A screenshot aid: the all-green, game-running picture without launching a game.
    static let demoPlaying = ChainSnapshot(links: [
        LinkState(.radio, ok: true, detail: "on"),
        LinkState(.pad, ok: true, detail: "SQUARE connected, battery 85%"),
        LinkState(.steam, ok: true, detail: "running, leaving the controller to the game"),
        LinkState(.game, ok: true, detail: "running"),
    ], takenAt: Date())
}
