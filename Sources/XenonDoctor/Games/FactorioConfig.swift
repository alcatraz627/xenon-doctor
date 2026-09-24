import Foundation

/// The lines in Factorio's config.ini that put the pad to work. Factorio reads pads
/// through Apple's GameController layer, but only when the input method says so, and
/// four of its stock controller bindings sit on Steam Deck back paddles this pad does not
/// have (copy, paste, search, blueprint library), with undo and redo unbound. Factorio
/// rewrites the whole file when it quits, so the app only writes while it is not running.
enum FactorioConfig {
    static let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/factorio/config/config.ini")

    struct Line: Equatable {
        let section: String
        let key: String
        let value: String
    }

    static let inputMethod = Line(section: "input", key: "input-method", value: "game-controller")

    /// Chords Factorio leaves free, in its own names: LT and RT are L2 and R2, start is
    /// Options, Y is Triangle, X is Square.
    static let chords: [Line] = [
        Line(section: "controls", key: "copy-controller", value: "controller-lefttrigger + controller-righttrigger + controller-dpleft"),
        Line(section: "controls", key: "paste-controller", value: "controller-lefttrigger + controller-righttrigger + controller-dpright"),
        Line(section: "controls", key: "focus-search-controller", value: "controller-lefttrigger + controller-start"),
        Line(section: "controls", key: "toggle-blueprint-library-controller", value: "controller-lefttrigger + controller-righttrigger + controller-start"),
        Line(section: "controls", key: "undo-controller", value: "controller-lefttrigger + controller-righttrigger + controller-y"),
        Line(section: "controls", key: "redo-controller", value: "controller-lefttrigger + controller-righttrigger + controller-x"),
    ]

    static var wanted: [Line] { [inputMethod] + chords }

    static func controllerEnabled() -> Bool {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return false }
        return value(in: text, section: inputMethod.section, key: inputMethod.key) == inputMethod.value
    }

    /// The wanted lines the file does not carry yet, so the row can name them.
    static func missing() -> [Line] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return wanted }
        return wanted.filter { value(in: text, section: $0.section, key: $0.key) != $0.value }
    }

    /// The live value of a key in a section; nil when the line is missing or commented
    /// out, which Factorio treats as its default.
    static func value(in text: String, section: String, key: String) -> String? {
        var inSection = false
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inSection = line == "[\(section)]"; continue }
            guard inSection, !line.hasPrefix(";"), let eq = line.firstIndex(of: "=") else { continue }
            if line[..<eq].trimmingCharacters(in: .whitespaces) == key {
                return line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// The same text with one key set in its section. The commented default line Factorio
    /// writes is replaced in place so the file keeps its shape; a missing section is added.
    static func setting(_ text: String, _ line: Line) -> String {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).map(String.init)
        var inSection = false
        var sectionStart: Int?
        for (i, raw) in lines.enumerated() {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("[") {
                if inSection { break }
                inSection = l == "[\(line.section)]"
                if inSection { sectionStart = i }
                continue
            }
            guard inSection else { continue }
            var body = l
            if body.hasPrefix(";") { body = body.dropFirst().trimmingCharacters(in: .whitespaces) }
            if let eq = body.firstIndex(of: "="), body[..<eq].trimmingCharacters(in: .whitespaces) == line.key {
                lines[i] = "\(line.key)=\(line.value)"
                return lines.joined(separator: "\n")
            }
        }
        if let start = sectionStart {
            lines.insert("\(line.key)=\(line.value)", at: start + 1)
        } else {
            if let last = lines.last, !last.isEmpty { lines.append("") }
            lines.append("[\(line.section)]")
            lines.append("\(line.key)=\(line.value)")
        }
        return lines.joined(separator: "\n")
    }

    static func setting(_ text: String, _ all: [Line]) -> String {
        all.reduce(text) { setting($0, $1) }
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

    /// Writes every wanted line with a backup beside the file. Refuses while Factorio
    /// runs. A missing file (Factorio never launched) gets a minimal one.
    static func enableController() throws {
        guard GameProbe.runningGame(.factorio) == nil else { throw WriteError.running }
        let fm = FileManager.default
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let out = setting(text, wanted)
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
