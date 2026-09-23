import Foundation

/// The setting that blinded every SDL game in 0.3.2: an SDL ignore list in the login
/// session, which every process started from that session inherits. Two places it can
/// still hide: the session itself, and a game that started before it was cleared.
enum PadBlock {
    static let variable = "SDL_GAMECONTROLLER_IGNORE_DEVICES"

    /// True when the login session still carries the variable.
    static func loginSessionBlocked() -> Bool {
        let (status, out) = Shell.run("/bin/launchctl", ["getenv", variable])
        return status == 0 && !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when a running process carries the variable. macOS only shows the environment
    /// of processes it let this user start (Steam and its games qualify; Dock-launched apps
    /// hide theirs), so a false here is "not seen", which is the right default.
    static func processBlocked(pid: pid_t) -> Bool {
        let (status, out) = Shell.run("/bin/ps", ["-Ewww", "-o", "command=", "-p", "\(pid)"])
        return status == 0 && blocked(inEnvironmentLine: out)
    }

    static func blocked(inEnvironmentLine line: String) -> Bool {
        line.contains(" \(variable)=") && !line.contains(" \(variable)= ")
    }
}
