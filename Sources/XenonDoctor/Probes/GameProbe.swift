import Foundation
import AppKit

/// Is this game installed and running, and can the pad reach it through the path this
/// game uses. Steam's own idea of "running" can outlive the game window, which is the
/// state the owner was in when he reached for Stop; that case gets the gentle relaunch.
struct GameProbe: Probe {
    let game: Game
    var link: Link { game.link }

    static func runningGame(_ game: Game) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == game.bundleID }
    }

    /// Steam writes one manifest per installed game into each library folder it knows.
    static func installed(_ game: Game) -> Bool {
        let name = "appmanifest_\(game.steamAppID).acf"
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
    static func steamThinksRunning(_ game: Game) -> Bool {
        let log = SteamPaths.logs.appendingPathComponent("gameprocess_log.txt")
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return false }
        var running = false
        for line in text.split(separator: "\n") where line.contains("AppID \(game.steamAppID)") {
            if line.contains("adding PID") || line.contains("Game process added") { running = true }
            if line.contains("Remove \(game.steamAppID) from running list") { running = false }
        }
        return running
    }

    func read() -> LinkState {
        if let app = GameProbe.runningGame(game) {
            if let broken = layerWhileRunning(app) { return broken }
            let launched = app.isFinishedLaunching && app.activationPolicy == .regular
            if launched && !GameProbe.steamThinksRunning(game) {
                return LinkState(link, ok: true, detail: "running, started outside Steam" + runningSuffix,
                                 hint: "It works, and the pad still reaches it. Next time launch it from Steam so cloud saves and playtime are kept.",
                                 brief: "Launch from Steam next time for cloud saves")
            }
            return LinkState(link, ok: true, detail: launched ? "running" + runningSuffix : "starting")
        }
        if GameProbe.steamThinksRunning(game) {
            return LinkState(link, ok: false, detail: "closed, but Steam still shows it running", repair: game.relaunch)
        }
        if SteamProbe.installedSteam() != nil && !GameProbe.installed(game) {
            return LinkState(link, ok: false, detail: "not installed in this Steam library",
                             repair: game.install,
                             hint: "The button opens the game's page in Steam. Click Install there, wait for the download, then come back.",
                             brief: "Click Install in Steam, then come back")
        }
        if let broken = layerWhileIdle() { return broken }
        return LinkState(link, ok: true, detail: "not running", idle: true)
    }

    /// A few words after "running" saying how the pad is reaching the game right now.
    private var runningSuffix: String {
        switch game.path {
        case .sdl: return ""
        case .gameController: return ", reading the pad directly"
        case .keyMapper: return KeyMapper.shared.isFront ? ", pad pressing its keys" : ""
        }
    }

    // MARK: the game's own input layer

    /// Broken states that only show while the game is up.
    private func layerWhileRunning(_ app: NSRunningApplication) -> LinkState? {
        switch game.path {
        case .sdl:
            if PadBlock.processBlocked(pid: app.processIdentifier) {
                return LinkState(link, ok: false, detail: "running, but it started with the old controller block", repair: game.relaunch,
                                 hint: "An older Xenon Doctor left a setting that hides the pad from this game. It is cleared now, but the game read it when it started. Save, and relaunch it.",
                                 brief: "Started with the old block; relaunch")
            }
        case .gameController:
            if !FactorioConfig.controllerEnabled() {
                return LinkState(link, ok: false, detail: "running with keyboard and mouse input", repair: .enableFactorioPad,
                                 hint: "Factorio only listens to a pad when its input method is set to game controller. The button saves your game, flips the setting, and relaunches.",
                                 brief: "Input method is keyboard; the button flips it")
            }
        case .keyMapper:
            if !KeyMapper.trusted {
                return keyMapperNotAllowed(running: true)
            }
        }
        return nil
    }

    /// Broken states worth showing before the game is launched, so the first launch works.
    private func layerWhileIdle() -> LinkState? {
        switch game.path {
        case .sdl:
            // Self-heal first; the button is for a block that comes back after clearing.
            if PadBlock.loginSessionBlocked() {
                Pin.heal()
                if PadBlock.loginSessionBlocked() {
                    return LinkState(link, ok: false, detail: "the login session hides the pad from this game", repair: .clearPadBlock,
                                     hint: "A setting from an older Xenon Doctor is back in the login session and would blind the game. The button clears it.",
                                     brief: "Old controller block is back")
                }
            }
        case .gameController:
            if !FactorioConfig.controllerEnabled() {
                return LinkState(link, ok: false, detail: "set to keyboard and mouse input", repair: .enableFactorioPad,
                                 hint: "Factorio only listens to a pad when its input method is set to game controller. One click sets it.",
                                 brief: "Input method is keyboard; one click sets it")
            }
        case .keyMapper:
            if !KeyMapper.trusted { return keyMapperNotAllowed(running: false) }
        }
        return nil
    }

    private func keyMapperNotAllowed(running: Bool) -> LinkState {
        LinkState(link, ok: false, detail: (running ? "running, " : "") + "pad cannot press its keys yet", repair: .openAccessibility,
                  hint: "Undertale cannot read a pad on a Mac, so Xenon Doctor presses its keys for you. macOS needs one switch on: in the Accessibility list, turn on Xenon Doctor, then come back here.",
                  brief: "Switch Xenon Doctor on in the Accessibility list")
    }
}
