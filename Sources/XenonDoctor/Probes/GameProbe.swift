import Foundation
import AppKit

/// Is Stardew Valley installed and running. Steam's own idea of "running" can outlive the
/// game window, which is the state the owner was in when he reached for Stop; that case is
/// reported with the gentle relaunch as its button.
struct GameProbe: Probe {
    static let bundleID = "com.concernedape.stardewvalley"
    static let steamAppID = "413150"

    static func runningGame() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }

    /// Steam writes one manifest per installed game into each library folder it knows.
    static func installed() -> Bool {
        let name = "appmanifest_\(steamAppID).acf"
        var libraries = [SteamPaths.root.appendingPathComponent("steamapps")]
        let listing = SteamPaths.root.appendingPathComponent("steamapps/libraryfolders.vdf")
        if let text = try? String(contentsOf: listing, encoding: .utf8),
           let root = try? KeyValues.parse(text),
           let folders = root.child("libraryfolders") {
            for entry in folders.children {
                if let path = entry.get(path: ["path"]) {
                    libraries.append(URL(fileURLWithPath: path).appendingPathComponent("steamapps"))
                }
            }
        }
        return libraries.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent(name).path) }
    }

    /// Steam lists the game as running in its process log until it sees the exit.
    static func steamThinksRunning() -> Bool {
        let log = SteamPaths.logs.appendingPathComponent("gameprocess_log.txt")
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return false }
        var running = false
        for line in text.split(separator: "\n") where line.contains("AppID \(steamAppID)") {
            if line.contains("adding PID") || line.contains("Game process added") { running = true }
            if line.contains("Remove \(steamAppID) from running list") { running = false }
        }
        return running
    }

    func read() -> LinkState {
        if let app = GameProbe.runningGame() {
            let launched = app.isFinishedLaunching && app.activationPolicy == .regular
            if launched && !GameProbe.steamThinksRunning() {
                return LinkState(.game, ok: true, detail: "running, started outside Steam",
                                 hint: "It works, and the pad still reaches it. Next time launch it from Steam so cloud saves and playtime are kept.",
                                 brief: "Launch from Steam next time for cloud saves")
            }
            return LinkState(.game, ok: true, detail: launched ? "running" : "starting")
        }
        if GameProbe.steamThinksRunning() {
            return LinkState(.game, ok: false, detail: "closed, but Steam still shows it running",
                             repair: .relaunchGame)
        }
        if SteamProbe.installedSteam() != nil && !GameProbe.installed() {
            return LinkState(.game, ok: false, detail: "not installed in this Steam library",
                             repair: .installGame,
                             hint: "The button opens the game's page in Steam. Click Install there, wait for the download, then come back.",
                             brief: "Click Install in Steam, then come back")
        }
        return LinkState(.game, ok: true, detail: "not running")
    }
}
