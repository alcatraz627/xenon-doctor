import Foundation
import AppKit

/// Is Stardew Valley running. Steam's own idea of "running" can outlive the game window,
/// which is the state the owner was in when he reached for Stop; that case is reported
/// with the gentle relaunch as its button.
struct GameProbe: Probe {
    static let bundleID = "com.concernedape.stardewvalley"
    static let steamAppID = "413150"

    static func runningGame() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
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
            if app.isFinishedLaunching && app.activationPolicy == .regular {
                return LinkState(.game, ok: true, detail: "running")
            }
            return LinkState(.game, ok: true, detail: "starting")
        }
        if GameProbe.steamThinksRunning() {
            return LinkState(.game, ok: false, detail: "closed, but Steam still shows it running",
                             repair: .relaunchGame)
        }
        return LinkState(.game, ok: true, detail: "not running")
    }
}
