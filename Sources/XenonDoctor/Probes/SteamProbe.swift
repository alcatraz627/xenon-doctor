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

/// Is Steam installed, is it running, are its controller settings pinned, and has it kept
/// its hands off the pad since it started. A Steam that opened the pad is the state that
/// preceded the freeze, so it is reported as broken even though games may still work.
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
        for line in text.split(separator: "\n").reversed() {
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
        let pinned = Pin.check().isEmpty
        let opened = SteamProbe.openedPad(since: app.launchDate ?? .distantPast)
        if pinned && !opened {
            return LinkState(.steam, ok: true, detail: "running, leaving the controller to the game")
        }
        if !pinned {
            return LinkState(.steam, ok: false, detail: "running with the wrong controller settings", repair: .applyPin)
        }
        return LinkState(.steam, ok: false, detail: "has taken over the controller", repair: .restartSteam)
    }
}
