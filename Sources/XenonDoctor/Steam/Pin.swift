import Foundation

/// The Steam settings that keep Steam out of the controller's way, and the launch agent
/// that keeps Steam's hands off the pad. Measured on 2026-09-05; see pin.md in the plan.
enum Pin {
    /// Paths under UserLocalConfigStore in localconfig.vdf, with the value each must hold.
    static let keys: [([String], String)] = [
        (["SteamController_PSSupport"], "0"),
        (["Controller_CheckGuideButton"], "0"),
        (["SteamController_Enable_Chord"], "0"),
        (["apps", GameProbe.steamAppID, "UseSteamControllerConfig"], "0"),
    ]

    static let agentLabel = "com.xenondoctor.steam-env"
    static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    /// Keys whose value is missing or wrong, as "path=expected". Empty means pinned.
    static func check() -> [String] {
        guard let url = SteamPaths.localConfig(),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let root = try? KeyValues.parse(text),
              let store = root.child("UserLocalConfigStore") else {
            return ["localconfig.vdf unreadable"]
        }
        var missing: [String] = []
        for (path, want) in keys where store.get(path: path) != want {
            missing.append(path.joined(separator: "/") + "=" + want)
        }
        if !FileManager.default.fileExists(atPath: agentURL.path) {
            missing.append("launch agent \(agentLabel)")
        }
        return missing
    }

    /// Is the ignore list in the login session right now, which is what a Steam started
    /// from the Dock or as a login item inherits. The plist on disk is not enough: it
    /// takes effect at the next login, and a bootout leaves the file and drops the value.
    static func sessionHasIgnoreList() -> Bool {
        let (status, out) = Shell.run("/bin/launchctl", ["getenv", "SDL_GAMECONTROLLER_IGNORE_DEVICES"])
        return status == 0 && out.trimmingCharacters(in: .whitespacesAndNewlines) == Pads.sdlIgnoreValue
    }

    enum ApplyError: Error, CustomStringConvertible {
        case steamRunning, noConfig, parse(Error), write(Error)
        var description: String {
            switch self {
            case .steamRunning: return "Steam is running; it overwrites this file when it quits"
            case .noConfig: return "could not find one Steam account folder"
            case .parse(let e): return "could not read localconfig.vdf: \(e)"
            case .write(let e): return "could not write: \(e)"
            }
        }
    }

    /// Writes the four keys with a timestamped backup beside the file. Refuses while Steam runs.
    static func applyKeys() throws {
        guard SteamProbe.runningSteam() == nil else { throw ApplyError.steamRunning }
        guard let url = SteamPaths.localConfig() else { throw ApplyError.noConfig }
        let text: String
        let root: KVNode
        do {
            text = try String(contentsOf: url, encoding: .utf8)
            root = try KeyValues.parse(text)
        } catch { throw ApplyError.parse(error) }
        let store = root.child("UserLocalConfigStore") ?? {
            let n = KVNode(key: "UserLocalConfigStore"); root.children.append(n); return n
        }()
        for (path, want) in keys { store.set(path: path, value: want) }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingLastPathComponent().appendingPathComponent("localconfig.vdf.xenondoctor-\(stamp).bak")
        do {
            try text.write(to: backup, atomically: true, encoding: .utf8)
            try KeyValues.serialize(root).write(to: url, atomically: true, encoding: .utf8)
        } catch { throw ApplyError.write(error) }
    }

    /// Test helper: puts Steam and the login session back to how a fresh Mac looks.
    /// Removes the four keys (with a backup), unloads and deletes the agent, clears the
    /// variable from the login session. Refuses while Steam runs, like applyKeys.
    static func unpin() throws {
        guard SteamProbe.runningSteam() == nil else { throw ApplyError.steamRunning }
        guard let url = SteamPaths.localConfig() else { throw ApplyError.noConfig }
        let text: String
        let root: KVNode
        do {
            text = try String(contentsOf: url, encoding: .utf8)
            root = try KeyValues.parse(text)
        } catch { throw ApplyError.parse(error) }
        if let store = root.child("UserLocalConfigStore") {
            for (path, _) in keys {
                var node = store
                var ok = true
                for k in path.dropLast() {
                    guard let next = node.child(k) else { ok = false; break }
                    node = next
                }
                if ok, let last = path.last { node.children.removeAll { $0.key == last } }
            }
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingLastPathComponent().appendingPathComponent("localconfig.vdf.xenondoctor-unpin-\(stamp).bak")
        do {
            try text.write(to: backup, atomically: true, encoding: .utf8)
            try KeyValues.serialize(root).write(to: url, atomically: true, encoding: .utf8)
        } catch { throw ApplyError.write(error) }
        _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(agentLabel)"])
        _ = Shell.run("/bin/launchctl", ["unsetenv", "SDL_GAMECONTROLLER_IGNORE_DEVICES"])
        if FileManager.default.fileExists(atPath: agentURL.path) {
            try FileManager.default.removeItem(at: agentURL)
        }
    }

    /// Installs the launch agent from the app bundle (or the source tree) and loads it now.
    static func installAgent() throws {
        let fm = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("\(agentLabel).plist"),
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources/\(agentLabel).plist"),
        ].compactMap { $0 }
        guard let src = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
            throw NSError(domain: "XenonDoctor", code: 1, userInfo: [NSLocalizedDescriptionKey: "agent plist not found next to the app"])
        }
        try fm.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: agentURL.path) { try fm.removeItem(at: agentURL) }
        try fm.copyItem(at: src, to: agentURL)
        _ = Shell.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", agentURL.path])
        _ = Shell.run("/bin/launchctl", ["setenv", "SDL_GAMECONTROLLER_IGNORE_DEVICES", Pads.sdlIgnoreValue])
    }
}

/// Runs a command and returns its exit status and output. Used for launchctl and open.
enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String], environment: [String: String]? = nil) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let env = environment { p.environment = env }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
