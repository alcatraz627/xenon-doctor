import Foundation
import AppKit
import IOBluetooth

/// Turn the radio on and wait for it.
struct PowerOnRadio: Repair {
    let kind = RepairKind.powerOnRadio
    func run() -> LinkState {
        btPowerSet(1)
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline && btPowerGet() != 1 { Thread.sleep(forTimeInterval: 0.2) }
        return RadioProbe().read()
    }
}

/// Ask each paired known pad to connect. If nothing answers within eight seconds, power
/// the radio off and on once and try again. A pad that is switched off cannot answer,
/// and the hint on the resulting state says what to press.
struct ReconnectPad: Repair {
    let kind = RepairKind.reconnectPad

    private func tryConnect() -> Bool {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return false }
        var any = false
        for d in devices {
            guard let addr = d.addressString, Pads.pad(forMAC: addr) != nil, !d.isConnected() else { continue }
            if d.openConnection() == kIOReturnSuccess { any = true }
        }
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if devices.contains(where: { $0.isConnected() && Pads.pad(forMAC: $0.addressString ?? "") != nil }) { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return any
    }

    func run() -> LinkState {
        if tryConnect() { return PadProbe().read() }
        btPowerSet(0)
        Thread.sleep(forTimeInterval: 2)
        btPowerSet(1)
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline && btPowerGet() != 1 { Thread.sleep(forTimeInterval: 0.2) }
        _ = tryConnect()
        return PadProbe().read()
    }
}

/// Quit Steam gently, make sure its controller settings are in place, and start it again.
/// Never a kill signal.
struct RestartSteam: Repair {
    let kind = RepairKind.restartSteam

    // Steam replies "cancel" to the quit event and then shuts down on its own, taking
    // 20 to 40 seconds. So the reply is ignored and only the process going away counts.
    static func quitSteam(timeout: TimeInterval = 75) -> Bool {
        guard let app = SteamProbe.runningSteam() else { return true }
        app.terminate()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if SteamProbe.runningSteam() == nil { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return SteamProbe.runningSteam() == nil
    }

    static func launchSteam() {
        let env = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "USER": NSUserName(),
        ]
        Shell.run("/usr/bin/open", ["-a", "Steam"], environment: env)
    }

    func run() -> LinkState {
        guard RestartSteam.quitSteam() else {
            return LinkState(.steam, ok: false, detail: "Steam did not quit; close it from its menu, then try again", repair: .restartSteam)
        }
        if !Pin.check().isEmpty {
            do { try Pin.applyKeys() } catch { }
        }
        RestartSteam.launchSteam()
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline && SteamProbe.runningSteam() == nil { Thread.sleep(forTimeInterval: 0.5) }
        Thread.sleep(forTimeInterval: 3)
        return SteamProbe().read()
    }
}

/// Apply the pin: quit Steam if needed, write the keys, relaunch.
struct ApplyPin: Repair {
    let kind = RepairKind.applyPin
    func run() -> LinkState {
        let wasRunning = SteamProbe.runningSteam() != nil
        guard RestartSteam.quitSteam() else {
            return LinkState(.steam, ok: false, detail: "Steam did not quit; close it from its menu, then try again", repair: .applyPin)
        }
        do {
            try Pin.applyKeys()
        } catch {
            return LinkState(.steam, ok: false, detail: "could not fix settings: \(error)", repair: .applyPin)
        }
        if wasRunning {
            RestartSteam.launchSteam()
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline && SteamProbe.runningSteam() == nil { Thread.sleep(forTimeInterval: 0.5) }
            Thread.sleep(forTimeInterval: 3)
        }
        return SteamProbe().read()
    }
}

/// Clear the old login-session block that hides the pad from SDL games.
struct ClearPadBlock: Repair {
    let kind = RepairKind.clearPadBlock
    func run() -> LinkState {
        Pin.heal()
        return GameProbe(game: .stardew).read()
    }
}

/// Ask the game to quit and wait for it, then launch it again through Steam.
/// Never a kill signal while a window is up.
struct RelaunchGame: Repair {
    let game: Game
    var kind: RepairKind { game.relaunch }

    /// Asks the game to quit and waits; false when it is still up after the wait.
    static func quit(_ game: Game, timeout: TimeInterval = 20) -> Bool {
        guard let app = GameProbe.runningGame(game) else { return true }
        app.terminate()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && GameProbe.runningGame(game) != nil { Thread.sleep(forTimeInterval: 0.5) }
        return GameProbe.runningGame(game) == nil
    }

    static func launch(_ game: Game, wait: TimeInterval = 30) {
        Shell.run("/usr/bin/open", ["steam://rungameid/\(game.steamAppID)"],
                  environment: ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path])
        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline && GameProbe.runningGame(game) == nil { Thread.sleep(forTimeInterval: 0.5) }
    }

    func run() -> LinkState {
        guard RelaunchGame.quit(game) else {
            return LinkState(game.link, ok: false, detail: "the game did not quit; save and exit from its menu", repair: kind)
        }
        RelaunchGame.launch(game)
        return GameProbe(game: game).read()
    }
}

/// Set Factorio's input method to game controller. Factorio rewrites its config when it
/// quits, so a running Factorio is asked to quit first (it offers to save), then relaunched.
struct EnableFactorioPad: Repair {
    let kind = RepairKind.enableFactorioPad
    func run() -> LinkState {
        let wasRunning = GameProbe.runningGame(.factorio) != nil
        guard RelaunchGame.quit(.factorio) else {
            return LinkState(.factorio, ok: false, detail: "Factorio did not quit; save and exit from its menu, then try again", repair: kind)
        }
        do {
            try FactorioConfig.enableController()
        } catch {
            return LinkState(.factorio, ok: false, detail: "could not change the setting: \(error)", repair: kind)
        }
        if wasRunning { RelaunchGame.launch(.factorio) }
        return GameProbe(game: .factorio).read()
    }
}

/// Open the one place where a person has to finish the job: a privacy pane, a download
/// page, a Steam store page. Reads the link again after a moment so the row can update
/// the instant the person comes back.
struct GoThere: Repair {
    let kind: RepairKind

    var url: URL {
        switch kind {
        case .openBluetoothPrivacy:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!
        case .openAccessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .installSteam:
            return URL(string: "https://store.steampowered.com/about/")!
        default:
            let id = Game.forInstall(kind)?.steamAppID ?? Game.stardew.steamAppID
            return URL(string: "steam://install/\(id)")!
        }
    }

    func run() -> LinkState {
        if kind == .openAccessibility {
            KeyMapper.requestTrust()
        } else {
            NSWorkspace.shared.open(url)
        }
        Thread.sleep(forTimeInterval: 1.5)
        switch kind {
        case .openBluetoothPrivacy: return RadioProbe().read()
        case .openAccessibility: return GameProbe(game: .undertale).read()
        case .installSteam: return SteamProbe().read()
        default: return GameProbe(game: Game.forInstall(kind) ?? .stardew).read()
        }
    }
}

enum Repairs {
    static func make(_ kind: RepairKind) -> Repair {
        switch kind {
        case .powerOnRadio: return PowerOnRadio()
        case .reconnectPad: return ReconnectPad()
        case .restartSteam: return RestartSteam()
        case .applyPin: return ApplyPin()
        case .clearPadBlock: return ClearPadBlock()
        case .relaunchGame, .relaunchFactorio, .relaunchUndertale: return RelaunchGame(game: Game.forRelaunch(kind) ?? .stardew)
        case .enableFactorioPad: return EnableFactorioPad()
        case .openBluetoothPrivacy, .openAccessibility, .installSteam, .installGame, .installFactorio, .installUndertale: return GoThere(kind: kind)
        }
    }

    /// Runs one repair, then reads the whole chain again. A repair is judged by the chain
    /// after it, never by its own report: the row it touched may be fine while the fix
    /// broke or exposed another, and only the full re-read shows that.
    static func runAndReread(_ kind: RepairKind) -> (repaired: LinkState, chain: ChainSnapshot) {
        let own = make(kind).run()
        let chain = Chain.standard().snapshot(fresh: true)
        return (own, chain)
    }
}
