import Foundation

/// The two Stratos Xenon pads this app exists for, by the pencil mark on each and its
/// Bluetooth address. Both report as Sony vendor 0x054C product 0x09CC (a DualShock 4).
struct KnownPad {
    let mark: String
    let mac: String

    /// IOBluetooth writes addresses as lowercase with dashes; System Settings shows
    /// uppercase with colons. Compare on the bare hex.
    var bareMAC: String { KnownPad.bare(mac) }

    static func bare(_ s: String) -> String {
        s.lowercased().filter { $0.isHexDigit }
    }
}

enum Pads {
    static let vendorID: Int = 0x054C
    static let productID: Int = 0x09CC
    /// SDL's ignore-list syntax for the pad, the value Steam's environment must carry.
    static let sdlIgnoreValue = "0x054c/0x09cc"

    static let known: [KnownPad] = [
        KnownPad(mark: "SQUARE", mac: "D0:27:96:F5:49:AD"),
        KnownPad(mark: "CIRCLE", mac: "D0:27:96:D0:11:6D"),
    ]

    static func pad(forMAC mac: String) -> KnownPad? {
        let b = KnownPad.bare(mac)
        return known.first { $0.bareMAC == b }
    }
}
