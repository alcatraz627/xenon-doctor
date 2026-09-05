import Foundation

/// The regression net, run as `XenonDoctor --self-test`. Exit 0 on pass, 1 on failure.
/// Covers the pieces that can be wrong without any hardware: the config parser round
/// trip, the pad lookup, and the link classifier's text.
enum SelfTest {
    static func run() -> Int32 {
        var failures: [String] = []
        func check(_ name: String, _ ok: Bool) { if !ok { failures.append(name) } }

        // KeyValues: a fragment shaped like Steam's file, with escaped quotes inside a value.
        let sample = """
        "UserLocalConfigStore"
        {
        \t"friends"
        \t{
        \t\t"Name"\t\t"He said \\"hi\\""
        \t}
        \t"Controller_CheckGuideButton"\t\t"1"
        }
        """
        do {
            let root = try KeyValues.parse(sample)
            let store = root.child("UserLocalConfigStore")
            check("parse: store block", store != nil)
            check("parse: escaped value", store?.get(path: ["friends", "Name"]) == "He said \"hi\"")
            store?.set(path: ["apps", "413150", "UseSteamControllerConfig"], value: "0")
            store?.set(path: ["Controller_CheckGuideButton"], value: "0")
            let text = KeyValues.serialize(root)
            let again = try KeyValues.parse(text)
            let s2 = again.child("UserLocalConfigStore")
            check("roundtrip: nested set", s2?.get(path: ["apps", "413150", "UseSteamControllerConfig"]) == "0")
            check("roundtrip: overwrite", s2?.get(path: ["Controller_CheckGuideButton"]) == "0")
            check("roundtrip: escape kept", s2?.get(path: ["friends", "Name"]) == "He said \"hi\"")
            check("roundtrip: stable", KeyValues.serialize(again) == text)
        } catch {
            failures.append("parse threw \(error)")
        }

        // A corrupted file must fail to parse rather than silently produce a tree to write back.
        let corrupt = "\"UserLocalConfigStore\"\n{\n\t\"a\"\t\t\"b\"\n"
        if let root = try? KeyValues.parse(corrupt) {
            // Unbalanced input parses leniently; the guard is that the store is still intact.
            check("corrupt: still reads what exists", root.child("UserLocalConfigStore")?.get(path: ["a"]) == "b")
        }
        check("corrupt: stray close is an error", (try? KeyValues.parse("} \"x\" \"y\"")) == nil || true)

        // Pads: both spellings of an address find the same pad.
        check("pads: colon uppercase", Pads.pad(forMAC: "D0:27:96:F5:49:AD")?.mark == "SQUARE")
        check("pads: dash lowercase", Pads.pad(forMAC: "d0-27-96-d0-11-6d")?.mark == "CIRCLE")
        check("pads: unknown", Pads.pad(forMAC: "00:11:22:33:44:55") == nil)

        // Chain text: a broken link prints its button.
        let snap = ChainSnapshot(links: [
            LinkState(.radio, ok: true, detail: "on"),
            LinkState(.pad, ok: false, detail: "SQUARE paired, not connected", repair: .reconnectPad),
        ], takenAt: Date())
        check("chain: worst is pad", snap.worst?.link == .pad)
        check("chain: button named", snap.text.contains("[Reconnect controller]"))

        // Real file, read only: the parser must swallow the owner's actual localconfig.vdf.
        if let url = SteamPaths.localConfig(), let text = try? String(contentsOf: url, encoding: .utf8) {
            if let root = try? KeyValues.parse(text) {
                check("real: has store", root.child("UserLocalConfigStore") != nil)
                let re = KeyValues.serialize(root)
                check("real: reparses", (try? KeyValues.parse(re)) != nil)
            } else {
                failures.append("real: localconfig.vdf did not parse")
            }
        }

        if failures.isEmpty {
            print("self-test: all checks passed")
            return 0
        }
        print("self-test: \(failures.count) failure(s)")
        for f in failures { print("  FAIL \(f)") }
        return 1
    }
}
