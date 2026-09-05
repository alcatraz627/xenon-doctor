import Foundation

/// One-line debug notes to stderr, on only when XENON_TRACE is set in the environment.
/// Read them with `open -n XenonDoctor.app --stderr /path/to/file --args --window`.
enum Trace {
    static let enabled = ProcessInfo.processInfo.environment["XENON_TRACE"] != nil

    static func log(_ line: String) {
        guard enabled else { return }
        FileHandle.standardError.write(("[xenon] " + line + "\n").data(using: .utf8)!)
    }
}
