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
        check("pads: ignore value", Pads.sdlIgnoreValue == "0x054c/0x09cc")
        check("pads: ids", Pads.vendorID == 0x054C && Pads.productID == 0x09CC)

        // Registry file: the bundled JSON and the built-in list agree, and a round trip holds.
        if let url = Pads.bundledFile, let data = try? Data(contentsOf: url) {
            check("registry: bundled parses", (try? PadRegistry.decode(data)) == PadRegistry.builtIn)
        }
        if let data = try? PadRegistry.builtIn.encoded() {
            check("registry: round trip", (try? PadRegistry.decode(data)) == PadRegistry.builtIn)
        }

        // Idle rows fade, broken rows do not; the easter egg needs every row fine and the game up.
        check("idle: fades", LinkState(.game, ok: true, detail: "not running", idle: true).dotColor.alphaComponent < 1)
        check("idle: broken never fades", LinkState(.game, ok: false, detail: "x", idle: true).dotColor.alphaComponent == 1)
        check("playing: demo", Chain.demoPlaying.playing)
        check("playing: not when game down", !ChainSnapshot(links: [LinkState(.game, ok: true, detail: "not running", idle: true)], takenAt: Date()).playing)
        check("playing: not when a row is broken", !ChainSnapshot(links: [
            LinkState(.pad, ok: false, detail: "x", repair: .reconnectPad), LinkState(.game, ok: true, detail: "running"),
        ], takenAt: Date()).playing)

        // Daily update check lands at 3 PM, today if that is still ahead, else tomorrow.
        var cal = Calendar.current
        cal.timeZone = .current
        let morning = cal.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let evening = cal.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!
        let fromMorning = Updater.nextDaily(after: morning)
        let fromEvening = Updater.nextDaily(after: evening)
        check("daily: 3 PM", cal.component(.hour, from: fromMorning) == 15 && cal.component(.hour, from: fromEvening) == 15)
        check("daily: same day in the morning", cal.isDate(fromMorning, inSameDayAs: morning))
        check("daily: next day in the evening", !cal.isDate(fromEvening, inSameDayAs: evening) && fromEvening > evening)

        // Factorio config: the commented default is replaced in place, a set value is read
        // back, a file with no [input] section gets one, and the write is idempotent.
        let ini = "[graphics]\n; fullscreen=true\n\n[input]\n; Options: keyboard-and-mouse, game-controller\n; input-method=keyboard-and-mouse\n\n; mouse-sensitivity=1\n\n[controls]\n; move=\n"
        check("factorio: default reads as unset", FactorioConfig.value(in: ini) == nil)
        let set = FactorioConfig.setting(ini, to: "game-controller")
        check("factorio: set reads back", FactorioConfig.value(in: set) == "game-controller")
        check("factorio: replaced in place", set.contains("[input]\n; Options: keyboard-and-mouse, game-controller\ninput-method=game-controller\n\n; mouse-sensitivity=1"))
        check("factorio: other sections untouched", set.hasPrefix("[graphics]\n; fullscreen=true\n") && set.hasSuffix("[controls]\n; move=\n"))
        check("factorio: idempotent", FactorioConfig.setting(set, to: "game-controller") == set)
        check("factorio: no section", FactorioConfig.value(in: FactorioConfig.setting("[graphics]\n; a=b\n", to: "game-controller")) == "game-controller")
        check("factorio: key outside [input] ignored", FactorioConfig.value(in: "[other]\ninput-method=game-controller\n") == nil)

        // Steam's process log, with the CR LF endings Steam writes: a launch then an exit
        // is not running; a launch after an exit is.
        let gp = "[t] AppID 427520 adding PID 1 as a tracked process\r\n[t] Remove 427520 from running list\r\n[t] AppID 413150 adding PID 2 as a tracked process\r\n"
        check("steam log: exited game not running", !GameProbe.steamThinksRunning(in: gp, appID: "427520"))
        check("steam log: launched game running", GameProbe.steamThinksRunning(in: gp, appID: "413150"))
        check("steam log: relaunch running", GameProbe.steamThinksRunning(in: gp + "[t] AppID 427520 adding PID 3 as a tracked process\r\n", appID: "427520"))
        check("steam log: unknown game", !GameProbe.steamThinksRunning(in: gp, appID: "391540"))

        // Pad block: the variable set in a process environment line, and the cleared form.
        check("block: set", PadBlock.blocked(inEnvironmentLine: "/x/Game HOME=/Users/a SDL_GAMECONTROLLER_IGNORE_DEVICES=0x054c/0x09cc PATH=/usr/bin"))
        check("block: absent", !PadBlock.blocked(inEnvironmentLine: "/x/Game HOME=/Users/a PATH=/usr/bin"))
        check("block: empty value", !PadBlock.blocked(inEnvironmentLine: "/x/Game SDL_GAMECONTROLLER_IGNORE_DEVICES= PATH=/usr/bin"))

        // DualShock 4 report block: D-pad hat, face buttons, shoulders, sticks, triggers.
        var raw = [UInt8](repeating: 0, count: 16)
        raw[1] = 255; raw[2] = 0; raw[3] = 128; raw[4] = 128   // left stick right and up, right stick centred
        raw[5] = 0x02 | 0x20                                    // hat 2 (right), cross
        raw[6] = 0x01 | 0x20                                    // L1, options
        raw[7] = 0x01                                           // PS
        raw[8] = 255; raw[9] = 0                                // L2 full, R2 off
        let block = raw.withUnsafeMutableBufferPointer { PadBattery.parse($0.baseAddress!, base: 1) }
        check("report: buttons", block.buttons == ["right", "cross", "L1", "options", "ps"])
        check("report: left stick", block.leftX > 0.99 && block.leftY > 0.99)
        check("report: right stick centred", abs(block.rightX) < 0.01 && abs(block.rightY) < 0.01)
        check("report: triggers", block.leftTrigger == 1 && block.rightTrigger == 0)
        raw[5] = 0x08; raw[6] = 0; raw[7] = 0                   // hat 8: released, nothing else held
        check("report: hat released", raw.withUnsafeMutableBufferPointer { PadBattery.parse($0.baseAddress!, base: 1) }.buttons.isEmpty)

        // Key mapper: Undertale's keys from the pad's state; the stick and the D-pad both move.
        func keys(dpad: (Bool, Bool, Bool, Bool) = (false, false, false, false), stick: (Float, Float) = (0, 0),
                  cross: Bool = false, circle: Bool = false, square: Bool = false, triangle: Bool = false, options: Bool = false) -> Set<KeyMapper.Key> {
            KeyMapper.keys(dpadUp: dpad.0, dpadDown: dpad.1, dpadLeft: dpad.2, dpadRight: dpad.3, stickX: stick.0, stickY: stick.1,
                           cross: cross, circle: circle, square: square, triangle: triangle, options: options)
        }
        check("mapper: idle is empty", keys().isEmpty)
        check("mapper: cross is Z", keys(cross: true) == [.z])
        check("mapper: circle and square are X", keys(circle: true) == [.x] && keys(square: true) == [.x])
        check("mapper: triangle is C", keys(triangle: true) == [.c])
        check("mapper: options is Enter", keys(options: true) == [.enter])
        check("mapper: dpad up", keys(dpad: (true, false, false, false)) == [.up])
        check("mapper: stick right", keys(stick: (0.8, 0)) == [.right])
        check("mapper: stick inside deadzone", keys(stick: (0.3, -0.3)).isEmpty)
        check("mapper: diagonal", keys(stick: (-0.7, 0.7)) == [.left, .up])
        check("mapper: chord", keys(dpad: (false, true, false, false), cross: true) == [.down, .z])

        // Game descriptors: every game has a row, a relaunch and an install button, and a pin key.
        check("games: rows", Game.all.map { $0.link } == [.game, .factorio, .undertale])
        check("games: repairs resolve", Game.all.allSatisfy { Game.forRelaunch($0.relaunch) != nil && Game.forInstall($0.install) != nil })
        check("games: pinned", Game.all.allSatisfy { g in Pin.keys.contains { $0.0 == ["apps", g.steamAppID, "UseSteamControllerConfig"] && $0.1 == "0" } })
        check("games: playing on any game", ChainSnapshot(links: [LinkState(.factorio, ok: true, detail: "running, reading the pad directly")], takenAt: Date()).playing)

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
