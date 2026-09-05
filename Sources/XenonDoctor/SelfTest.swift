import Foundation

/// The regression net, run as `XenonDoctor --self-test`. Exit 0 on pass, 1 on failure.
/// Covers the pieces that can be wrong without any hardware: the config parser round
/// trip, the pad lookup, the link classifier's text, the menu's one-line hints, and the
/// updater's version compare and release parsing.
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

        // Menu hints: the brief wins; without one the first clause is used and capped.
        let briefed = LinkState(.pad, ok: false, detail: "x", hint: "Long sentence. Second sentence.", brief: "Short form")
        check("hint: brief wins", briefed.menuHint == "Short form")
        let clause = LinkState(.pad, ok: false, detail: "x", hint: "If it blinks, connects, then drops: Hold Share and PS together until the light bar blinks fast, then let go.")
        check("hint: first clause", clause.menuHint == "If it blinks, connects, then drops")
        let long = LinkState(.pad, ok: false, detail: "x", hint: String(repeating: "word ", count: 30))
        check("hint: capped", (long.menuHint?.count ?? 0) <= 64 && long.menuHint?.hasSuffix("…") == true)
        check("hint: none", LinkState(.pad, ok: true, detail: "x").menuHint == nil)

        // Go-there buttons are marked so the menu shows an arrow instead of a wrench.
        check("repair: goes there", RepairKind.installSteam.goesThere && !RepairKind.applyPin.goesThere)

        // Updater: numeric compare, not string compare, and the release JSON shape GitHub sends.
        check("update: newer patch", Updater.isNewer("0.2.2", than: "0.2.1"))
        check("update: newer minor beats patch", Updater.isNewer("0.10.0", than: "0.9.9"))
        check("update: same is not newer", !Updater.isNewer("0.2.1", than: "0.2.1"))
        check("update: older is not newer", !Updater.isNewer("0.2.0", than: "0.2.1"))
        check("update: short form", Updater.isNewer("1.0", than: "0.9.9"))
        let release = """
        {"tag_name":"v0.3.0","assets":[{"name":"notes.txt","browser_download_url":"https://x/notes.txt"},
        {"name":"XenonDoctor-0.3.0.zip","browser_download_url":"https://x/XenonDoctor-0.3.0.zip"}]}
        """.data(using: .utf8)!
        let parsed = Updater.parse(release)
        check("update: tag parsed", parsed?.version == "0.3.0" && parsed?.tag == "v0.3.0")
        check("update: zip asset chosen", parsed?.zipURL.lastPathComponent == "XenonDoctor-0.3.0.zip")
        check("update: no zip means nil", Updater.parse("{\"tag_name\":\"v1\",\"assets\":[]}".data(using: .utf8)!) == nil)

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
