import Foundation

/// One pad in the registry: the pencil mark on its back and its Bluetooth address.
struct KnownPad: Codable, Equatable {
    let mark: String
    let mac: String
    var note: String?

    /// IOBluetooth writes addresses as lowercase with dashes; System Settings shows
    /// uppercase with colons. Compare on the bare hex.
    var bareMAC: String { KnownPad.bare(mac) }

    static func bare(_ s: String) -> String {
        s.lowercased().filter { $0.isHexDigit }
    }
}

/// The pad model the app is for and the household's pads of that model. This is the
/// whole file the app reads; edit it, or use `--add-pad`, to bring a third pad in.
struct PadRegistry: Codable, Equatable {
    var model: String
    var vendorID: String
    var productID: String
    var pads: [KnownPad]

    static let builtIn = PadRegistry(
        model: "Cosmic Byte Stratos Xenon (reports as a DualShock 4)",
        vendorID: "0x054C",
        productID: "0x09CC",
        pads: [
            KnownPad(mark: "SQUARE", mac: "D0:27:96:F5:49:AD", note: "Aakarsh's pad"),
            KnownPad(mark: "CIRCLE", mac: "D0:27:96:D0:11:6D", note: "the other pad"),
        ]
    )

    static func decode(_ data: Data) throws -> PadRegistry {
        try JSONDecoder().decode(PadRegistry.self, from: data)
    }

    func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }
}

/// Where the registry comes from, first match wins: the user's file in Application
/// Support, then the copy inside the app bundle, then the built-in list. The user's file
/// is what `--add-pad` writes, so an added pad survives an app update.
enum Pads {
    static let userFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/XenonDoctor/pads.json")

    static var bundledFile: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("pads.json")
    }

    private static var cached: (PadRegistry, String)?

    /// The registry and a word for where it was read from.
    static func load() -> (registry: PadRegistry, source: String) {
        if let c = cached { return c }
        let out: (PadRegistry, String)
        if let data = try? Data(contentsOf: userFile), let r = try? PadRegistry.decode(data) {
            out = (r, userFile.path)
        } else if let url = bundledFile, let data = try? Data(contentsOf: url), let r = try? PadRegistry.decode(data) {
            out = (r, "app bundle")
        } else {
            out = (.builtIn, "built in")
        }
        cached = out
        return out
    }

    static func reload() { cached = nil }

    static var registry: PadRegistry { load().registry }
    static var known: [KnownPad] { registry.pads }

    static var vendorID: Int { Int(registry.vendorID.dropFirst(2), radix: 16) ?? 0x054C }
    static var productID: Int { Int(registry.productID.dropFirst(2), radix: 16) ?? 0x09CC }
    /// SDL's ignore-list syntax for the pad, the value Steam's environment must carry.
    static var sdlIgnoreValue: String { "\(registry.vendorID.lowercased())/\(registry.productID.lowercased())" }

    static func pad(forMAC mac: String) -> KnownPad? {
        let b = KnownPad.bare(mac)
        return known.first { $0.bareMAC == b }
    }

    enum RegistryError: Error, CustomStringConvertible {
        case badMAC(String), duplicate(String), notFound(String)
        var description: String {
            switch self {
            case .badMAC(let m): return "\(m) is not a Bluetooth address (six pairs of hex, like D0:27:96:F5:49:AD)"
            case .duplicate(let m): return "a pad with that mark or address already exists: \(m)"
            case .notFound(let m): return "no pad marked \(m)"
            }
        }
    }

    /// Adds a pad and writes the user's file. The mark is uppercased so rows read alike.
    static func add(mark: String, mac: String, note: String?) throws {
        let bare = KnownPad.bare(mac)
        guard bare.count == 12 else { throw RegistryError.badMAC(mac) }
        var r = registry
        let m = mark.uppercased()
        if r.pads.contains(where: { $0.mark == m || $0.bareMAC == bare }) { throw RegistryError.duplicate(m) }
        let formatted = stride(from: 0, to: 12, by: 2).map { String(bare[bare.index(bare.startIndex, offsetBy: $0)..<bare.index(bare.startIndex, offsetBy: $0 + 2)]) }
            .joined(separator: ":").uppercased()
        r.pads.append(KnownPad(mark: m, mac: formatted, note: note))
        try save(r)
    }

    static func remove(mark: String) throws {
        var r = registry
        let m = mark.uppercased()
        guard r.pads.contains(where: { $0.mark == m }) else { throw RegistryError.notFound(m) }
        r.pads.removeAll { $0.mark == m }
        try save(r)
    }

    static func save(_ r: PadRegistry) throws {
        try FileManager.default.createDirectory(at: userFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try r.encoded().write(to: userFile, options: .atomic)
        reload()
    }

    /// The registry as text, the shape `--pads` prints.
    static func describe() -> String {
        let (r, source) = load()
        var lines = ["\(r.model)", "vendor \(r.vendorID) product \(r.productID), Steam ignore list \(sdlIgnoreValue)", "read from: \(source)", ""]
        for p in r.pads {
            lines.append("\(p.mark.padding(toLength: 8, withPad: " ", startingAt: 0)) \(p.mac)  \(p.note ?? "")")
        }
        lines.append("")
        lines.append("add one:    XenonDoctor --add-pad MARK D0:27:96:xx:xx:xx \"whose pad\"")
        lines.append("remove one: XenonDoctor --remove-pad MARK")
        lines.append("file:       \(userFile.path)")
        return lines.joined(separator: "\n")
    }
}
