import Foundation
import AppKit

/// Where Steam keeps the files this app reads and writes.
enum SteamPaths {
    static let bundleID = "com.valvesoftware.steam"
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Steam")
    static let logs = root.appendingPathComponent("logs")
    static let controllerUILog = logs.appendingPathComponent("controller_ui.txt")
    static let userdata = root.appendingPathComponent("userdata")

    /// The one Steam account folder, or nil when there are none or several.
    static func localConfig() -> URL? {
        guard let ids = try? FileManager.default.contentsOfDirectory(atPath: userdata.path) else { return nil }
        let accounts = ids.filter { Int($0) != nil && $0 != "0" }
        guard accounts.count == 1, let id = accounts.first else { return nil }
        return userdata.appendingPathComponent("\(id)/config/localconfig.vdf")
    }
}

/// Is Steam installed, is it running, and are its controller settings pinned. The verdict
/// rests only on the keys the Fix button writes. Whether Steam has opened the pad for its
/// own windows is shown as a note, never as breakage: measured 2026-09-05, the keys do not
/// stop that open, so no button here could change it, and the games read the pad directly.
struct SteamProbe: Probe {
    let link = Link.steam

    static func runningSteam() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == SteamPaths.bundleID }
    }

    static func installedSteam() -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: SteamPaths.bundleID)
    }

    /// True when Steam's controller log shows it configured a pad after `since`.
    static func openedPad(since: Date) -> Bool {
        guard let text = try? String(contentsOf: SteamPaths.controllerUILog, encoding: .utf8) else { return false }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt.timeZone = .current
        // Steam's logs end lines with CR LF; split on any newline or the file is one line.
        for line in text.split(whereSeparator: { $0.isNewline }).reversed() {
            guard line.contains("Controller 0 connected, configuring it now") else { continue }
            let stamp = line.dropFirst().prefix(19)
            if let d = fmt.date(from: String(stamp)) {
                if d >= since { return true }
                return false
            }
        }
        return false
    }

    func read() -> LinkState {
        guard SteamProbe.installedSteam() != nil else {
            return LinkState(.steam, ok: false, detail: "not installed", repair: .installSteam,
                             hint: "The button opens Steam's download page. Install it, sign in once, then come back here.",
                             brief: "Install Steam, sign in, come back")
        }
        guard let app = SteamProbe.runningSteam() else {
            if !Pin.check().isEmpty {
                return LinkState(.steam, ok: false, detail: "not running, and its next start would grab the controller",
                                 repair: .applyPin)
            }
            return LinkState(.steam, ok: true, detail: "not running (starts with the game)", idle: true)
        }
        if !Pin.check().isEmpty {
            return LinkState(.steam, ok: false, detail: "running with the wrong controller settings", repair: .applyPin)
        }
        if SteamProbe.openedPad(since: app.launchDate ?? .distantPast) {
            return LinkState(.steam, ok: true, detail: "running, Steam Input off for the games",
                             hint: "Steam has the pad open for its own windows, which the settings cannot stop. The games read the pad directly, so this changes nothing for them.",
                             brief: "Steam uses the pad for its own windows only")
        }
        return LinkState(.steam, ok: true, detail: "running, Steam Input off for the games")
    }
}
