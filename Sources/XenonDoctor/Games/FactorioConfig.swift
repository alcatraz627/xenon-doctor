import Foundation

/// Factorio's one switch that matters here: the input method in its config.ini. Factorio
/// reads pads through Apple's GameController layer, but only when this is set to
/// `game-controller`; the default is keyboard and mouse, and the game rewrites the whole
/// file when it quits, so the app only writes it while Factorio is not running.
enum FactorioConfig {
    static let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/factorio/config/config.ini")
    static let key = "input-method"
    static let want = "game-controller"

    static func controllerEnabled() -> Bool {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return false }
        return value(in: text) == want
    }

    /// The live value of input-method under [input]; nil when the line is missing or
    /// commented out, which Factorio treats as its default, keyboard and mouse.
    static func value(in text: String) -> String? {
        var inInput = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inInput = line == "[input]"; continue }
            guard inInput, !line.hasPrefix(";"), let eq = line.firstIndex(of: "=") else { continue }
            if line[..<eq].trimmingCharacters(in: .whitespaces) == key {
                return line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// The same text with input-method set under [input]. The commented default line
    /// Factorio writes is replaced in place so the file keeps its shape; a file with no
    /// [input] section gets one appended.
    static func setting(_ text: String, to value: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inInput = false
        var sectionStart: Int?
        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                if inInput { break }
                inInput = line == "[input]"
                if inInput { sectionStart = i }
                continue
            }
            guard inInput else { continue }
            var body = line
            if body.hasPrefix(";") { body = body.dropFirst().trimmingCharacters(in: .whitespaces) }
            if let eq = body.firstIndex(of: "="), body[..<eq].trimmingCharacters(in: .whitespaces) == key {
                lines[i] = "\(key)=\(value)"
                return lines.joined(separator: "\n")
            }
        }
        if let start = sectionStart {
            lines.insert("\(key)=\(value)", at: start + 1)
        } else {
            if let last = lines.last, !last.isEmpty { lines.append("") }
            lines.append("[input]")
            lines.append("\(key)=\(value)")
        }
        return lines.joined(separator: "\n")
    }

    enum WriteError: Error, CustomStringConvertible {
        case running, write(Error)
        var description: String {
            switch self {
            case .running: return "Factorio is running; it overwrites this file when it quits"
            case .write(let e): return "could not write: \(e)"
            }
        }
    }

    /// Writes input-method=game-controller with a backup beside the file. Refuses while
    /// Factorio runs. A missing file (Factorio never launched) gets a minimal one.
    static func enableController() throws {
        guard GameProbe.runningGame(.factorio) == nil else { throw WriteError.running }
        let fm = FileManager.default
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let out = setting(text, to: want)
        do {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !text.isEmpty {
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                try text.write(to: file.deletingLastPathComponent().appendingPathComponent("config.ini.xenondoctor-\(stamp).bak"),
                               atomically: true, encoding: .utf8)
            }
            try out.write(to: file, atomically: true, encoding: .utf8)
        } catch { throw WriteError.write(error) }
    }
}
