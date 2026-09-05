# Xenon Doctor: make two Stratos Xenon pads work with Steam and Stardew Valley on two Macs, every time

<!-- sessions: pad-steam-7c@2026-09-05 -->

This is the build plan for one pinned controller configuration and one small macOS menu bar app. The configuration makes the pad-to-Bluetooth-to-Steam-to-game chain deterministic. The app watches that chain, says which link is broken in plain words, and repairs it with one click. Both are tested on the MacBook Pro first and then copied to the M5 MacBook Air.

The owner's words, kept verbatim because every later hop paraphrases:

> I have dualshock controllers and a macbook. I wanna play Stardew Valley using the controllers. It works sometimes and sometimes it doesn't. Sometimes the controller doesn't register, often it struggles to connect w bluetooth, and a lot of times when when Steam shows it is connected, the controller doesn't work inside the game, or works very weirdly and not consistently. [...] do you think you could build a small mac os app that a lay person can use to diagnose, identify, and check? The whole charade of restarting the game / steam / the laptop AND especially the bluetooth connection, and hoping it works or try something again is pretty fucking tiring.

> The controllers (both of them are) Stratos Xenon Wireless controller, in the app you make do also make sure you show instructions and help guides for it. I'm not asking for support for general controller, but this model, both of my pieces SHOULD WORK FINE WITHOUT ANY FUSS I AM AT THE POINT WHERE IF IT NEEDS MORE DIAGNOSTICS I will lose my marriage

> For the local test, I don't mind having any of the games installed locally (even factorio) being tested [...] either way, stardew valley on her laptop should work, and if your fixes mean I can start using it on my laptop as well I'll be happy

## Why build anything

Two of the three gates fire, with evidence read from this Mac on 2026-09-05.

**Behaviour is wrong.** The owner reproduces three intermittent failures (pad not registering, Bluetooth not connecting, Steam connected but game input wrong). Evidence that the failures are real and not user error:

- Steam's stored Desktop configuration for this pad was a keyboard-and-mouse mapping (`~/Library/Application Support/Steam/steamapps/common/Steam Controller Configs/331921170/config/413080/controller_ps4.vdf`, group 0 `button_b` bound to `key_press SPACE`, group 9 right stick to `joystick_mouse`). A pad that receives that mapping inside a game "works very weirdly". Today the override resolves to `empty.vdf` (`~/Library/Application Support/Steam/logs/controller_ui.txt`, 2026-09-05 17:08:40), so the state drifts between sessions.
- The Bluetooth daemon logs `HID Latency Statistics events indicated HID lag issue is detected` once per second for the iClever keyboard (vid 0x04E8 pid 0x7021) that shares the radio with the pad. Reproduce with `/usr/bin/log show --last 15m --predicate 'process == "bluetoothd" AND eventMessage CONTAINS "HID lag"' --style compact` (the original capture file lived in the session scratch folder and was lost in the 17:22 reboot).
- While Steam runs, the raw pad is still visible to every other process (`gcprobe 5` with Steam up reported `category=DualShock 4 profile=GCDualShockGamepad`). The manufacturer's manual names this condition: "prevent multiple controller detections", with a Windows-only remedy (DS4Windows plus HidHide). There is no macOS equivalent, so the fix is to pin one input path.

**A cost is paid repeatedly.** The owner's restart ritual (game, Steam, laptop, Bluetooth) runs on two laptops per play session that fails, and the second laptop belongs to a non-technical spouse. The count is "often", in the owner's word, over months (Steam controller logs show PS4-type pad sessions from 2026-05-27 onward).

## What kind of work this is

Two changes wearing one name. They are planned together because the second cannot be specified until the first has a ruling, but they are built in order.

| Change | Class | What it most needs |
|---|---|---|
| A. Pin the input path | Behaviour | a reproduction of the in-game failure and a parity check that nothing else about Steam breaks |
| B. Xenon Doctor app | Capability | inheritance from the account's existing menu bar apps, a contract a reviewer can argue with, and a first slice that runs |

A is planned first. B's repair actions write the values A decides.

## What is wrong today

| Observation | Cost | Check that flips when fixed |
|---|---|---|
| The pad in PS4 mode presents as Sony 0x054C:0x09CC and is visible to Steam AND to every other process at once (`system_profiler SPBluetoothDataType` shows it; `gcprobe 5` with Steam running still lists it). Stardew ships its own SDL, so it may see two controllers: Steam's virtual one and the raw pad. | Duplicate or missing input in game, intermittent because it depends on which device SDL enumerates first | Stardew with the pinned per-app Steam Input value shows exactly one controller path working, verified by the owner moving the farmer with the left stick and pressing every face button, screenshot kept |
| Steam's Desktop config for pad `D02796F549AD` has been a keyboard-and-mouse mapping (file cited above) and Steam swaps configs when the game window loses focus or the game is launched outside Steam | Buttons type Space and arrows in game | Both pads' Desktop config (`configset_d02796f549ad.vdf`, `configset_d02796d0116d.vdf`) and app 413080 resolve to `empty.vdf` in `controller_ui.txt` after a Steam restart |
| Bluetooth radio is congested: bluetoothd lag warning every second for the keyboard sharing it (capture cited above) | Pad pairing or reconnect fails on some evenings and works on others | The app's Bluetooth link reads the live `log stream` for that predicate and shows "radio busy" with the named device, so the owner knows what to turn off; the check is the app showing the warning while the iClever keyboard is on and clearing it when it is off |
| Nothing on either Mac tells a lay person which of the four links is broken. Today's instruments are `system_profiler`, `hidutil`, Steam log files, and a compiled probe | Every failure becomes a restart-everything ritual | `XenonDoctor --status` prints the four links with `ok` or a named break, and matches `system_profiler` plus `gcprobe` output on the same second |
| `steam://install/413150` needed a click and Stardew was not on this Mac until 17:15 today | Cannot test end to end without the real game | `appmanifest_413150.acf` has `StateFlags 4` (already true at 17:15) and the game launches from `open steam://rungameid/413150` |

Watch, do not chase: the probe printed `press L2 Button` dozens of times in a row while the owner held the trigger. That is an analog trigger reporting each value change, not a stuck button. `Touchpad Button` appeared without being asked for; the owner may have rested a thumb on it. Neither goes in the problems above.

## What the account already does for this shape

The working directory is empty, so the sweep ran over `/Users/alcatraz627/Code` and `~/.claude` for menu bar apps, app bundling, and signing.

| Decision | How the account already does it | Evidence | Adopting or deviating | Reason if deviating |
|---|---|---|---|---|
| Project shape | SwiftPM executable, no Xcode, bare binary wrapped into a .app by a script | `/Users/alcatraz627/Code/Claude/sys-monitor/Package.swift` lines 1 to 17 (comment explains LSUIElement needs a bundle) | adopting | |
| .app assembly and ad-hoc signing | `build.sh` copies the binary into `Contents/MacOS`, copies `Resources/Info.plist`, runs `codesign --force --sign -` | `/Users/alcatraz627/Code/Claude/sys-monitor/build.sh` lines 96 to 110 | adopting | |
| Isolated dev instance so a rebuild does not kill the running app | `build.sh --dev` with a distinct bundle id and auto-quit | same file lines 56 to 92 | adopting | |
| Tests without XCTest | a `--self-test` binary mode, exit 0 or 1 | `Package.swift` lines 11 to 16; `Sources/sys-monitor/SelfTest.swift` | adopting | |
| Status item ownership | one `StatusItemController` owning the `NSStatusItem`, click routed through an `@objc` shim, right-click menu as escape hatch | `/Users/alcatraz627/Code/Claude/sys-monitor/Sources/sys-monitor/Shell/StatusItemController.swift` lines 1 to 80 | adopting | |
| Windows from an accessory app | plain owner class hosting SwiftUI via `NSHostingController`, activation dance, centre on the cursor's screen | `~/.claude/features/macos-menubar-widget.md` section 1 | adopting | |
| Distribution to another Mac | `release.sh` zips with `ditto --keepParent`; ad-hoc path means the receiver clears quarantine once or right-clicks Open | `/Users/alcatraz627/Code/Claude/sys-monitor/release.sh`; `RELEASING.md` Path A | adopting | notarization is the $99 path and is out of scope unless the owner asks |
| Bluetooth control from Swift | no prior use in the account; `blueutil` is not installed | `which blueutil` returned not found | new precedent | IOBluetooth framework: `IOBluetoothDevice(addressString:)`, `openConnection()`, and the private `IOBluetoothPreferenceSetControllerPowerState` that blueutil itself calls. Declared as a new-precedent row for the owner to see |
| Gamepad reading from Swift | no prior use in the account | sweep empty | new precedent | GameController framework; proven today by `gcprobe.swift` on this exact pad with zero permission prompts |
| Steam config files | no prior parser in the account | sweep empty | new precedent | Valve KeyValues text format; a 60-line tokenizer suffices and every write is backup-then-replace while Steam is not running |
| Logging | `os.Logger` with a subsystem per module | `StatusItemController.swift` line 34 | adopting | |
| Colour and hierarchy of the menu | house convention | `~/.claude/conventions/visual-design.md` | adopting | |

## What must still be true afterwards

Re-derived this session with `bash ~/.claude/scripts/atone.sh search rebuild-replaced`: nine events, the most recent 2026-08-26. This table is the guard.

| Must still hold | Why it matters | Check that would catch its loss |
|---|---|---|
| The SQUARE pad reaches macOS with every button, as `GCDualShockGamepad` | This is the healthy baseline measured today; any fix that breaks it is worse than no fix | `gcprobe 20` while the owner presses each face button, both bumpers, both triggers, both stick clicks, Options and Share: all names appear |
| The CIRCLE pad behaves the same as SQUARE | Two pads, two Steam records; a fix verified on one is not verified | Same `gcprobe 20` run with the CIRCLE pad; Steam `controller_ui.txt` shows `Serial: D02796D0116D` |
| Steam still recognises the pad as a PS4 controller and applies a config | Steam Input is how Big Picture and most Steam games take the pad | `controller_ui.txt` gains `Controller 0 connected, configuring it now` and `Type: 34` within ten seconds of Steam start |
| Other games' controller configs are untouched | The owner plays Factorio, Cyberpunk, Frostpunk, RimWorld, Oxygen Not Included on this account | `shasum` of every file under `Steam Controller Configs/331921170/config/` except the two pad files and `413080/` is unchanged before and after |
| Other Bluetooth pairings survive | Keyboard, AirPods, headsets, speakers are paired on this Mac | `system_profiler SPBluetoothDataType` lists the same devices before and after any repair, only connection state may differ |
| Karabiner-Elements keeps its keyboard rules | It is unrelated (its devices are keyboards, `~/.config/karabiner/karabiner.json` lines 1505 to 1560) | the file's `shasum` is unchanged |
| Steam's `localconfig.vdf` stays a valid file Steam accepts | A malformed write logs the owner out or loses settings | Steam starts and `loginusers.vdf` still names account 331921170; the app keeps a timestamped backup next to every file it writes |
| No new permission prompts beyond one Bluetooth prompt | A lay person will decline a prompt they do not understand | The app's `Info.plist` carries `NSBluetoothAlwaysUsageDescription` only; `gcprobe` already showed GameController needs no Input Monitoring |
| The app never runs anything unattended | Owner rule: no uninvited automation (`~/.claude/rules/unprompted-infra-scope-creep.md`) | No LaunchAgent, no login item, no timer that writes files; `--status` is read-only and the only timer refreshes the display |

## What to do, each with its proof

Change A first. P marks a row that came from the table above.

| ID | Directive | Check |
|---|---|---|
| A1 | Reproduce the in-game matrix on this Mac with the SQUARE pad: launch Stardew from Steam with the per-app Steam Input setting at each of default, forced on, forced off; the owner moves the farmer, opens the menu, presses every face button; record which mode gives one clean controller | Three rows in `A1-matrix.md` next to this plan, each with the `controller_ui.txt` lines for app 413150 and the owner's one-word verdict; a screenshot of the in-game controls screen for the winning mode |
| A2 | Pin the winning value for app 413150 and remove keyboard-and-mouse Desktop bindings for both pads, written while Steam is quit, with a backup | `localconfig.vdf` `apps/413150/UseSteamControllerConfig` equals the winner; after a Steam restart `controller_ui.txt` shows `empty.vdf` for app 413080 for both serials |
| A3 (P) | Prove the pin survives a Steam restart and a Mac reboot | Same `controller_ui.txt` lines after `killall steam_osx; open -a Steam`, and again after the owner reboots |
| A4 | Run the same matrix once with Factorio to confirm the pin is not Stardew-specific (owner offered it) | One row appended to `A1-matrix.md` |
| B1 | SwiftPM package `XenonDoctor` at `/Users/alcatraz627/Code/Personal/controlelr` with `build.sh`, `Resources/Info.plist` (LSUIElement, Bluetooth usage string), and `--self-test` | `swift build -c release` exits 0; `./build.sh` produces `XenonDoctor.app`; `codesign -dv XenonDoctor.app` prints an ad-hoc signature |
| B2 | `--status` prints the four links: Bluetooth radio, pad (by SQUARE or CIRCLE, battery percent), Steam (running, sees pad), game (Stardew running) | Output agrees with `system_profiler SPBluetoothDataType`, `gcprobe 4`, `pgrep steam_osx`, and `pgrep "Stardew Valley"` taken in the same minute, in each of: pad off, pad on Steam off, pad on Steam on, game running |
| B3 | Menu bar item shows one glyph for the whole chain and a dropdown with one line per link, each line either "fine" or one repair button | Screenshot read for each of the four broken states; sibling rows compared for identical type scale and alignment per `~/.claude/rules/ui-visual-verification.md` |
| B4 | Repair: Reconnect pad. `IOBluetoothDevice(addressString:).openConnection()` for the known MACs; if that fails within 8 s, power-cycle the radio via the IOBluetooth preference call and retry once | Turn the pad off, invoke `--repair reconnect`, the pad is connected within 20 s and `gcprobe 4` lists it |
| B5 | Repair: Restart Steam with the pin. Quit Steam, re-apply A2's values, `open -a Steam`, wait for `controller_ui.txt` to show the pad | `--repair steam` ends with `Type: 34` in the log within 30 s |
| B6 | Repair: Quit a stuck game and relaunch it via `steam://rungameid/413150` | `--repair game` with a frozen Stardew process leaves one fresh `Stardew Valley` process |
| B7 | Bluetooth congestion indicator from `log stream --predicate 'process == "bluetoothd"'` filtered to the HID lag line, naming the offending vendor and product as words | With the iClever keyboard on, the Bluetooth link shows "radio busy: iClever keyboard"; with it off, the line clears within 10 s |
| B8 | Guide window for the Stratos Xenon: pairing (Home + Share 4 s), mode switch (Share + Options 2 s toggles X-input and D-input), which mode the Mac wants (PS4 mode, the pad reports as a DualShock 4), LED meanings as far as the manual states them, "which pad is which" (SQUARE, CIRCLE), what to do when nothing works (wired USB-C cable) | Screenshot read; every combination in the guide is one the owner or the manual has confirmed, none invented |
| B9 | Live button tester window using GameController so a lay person sees presses light up | Screenshot with two buttons held shows exactly those two lit |
| B10 (P) | `--self-test`: Valve KeyValues parse and write round-trip on a copy of today's `localconfig.vdf`, MAC-to-pad-name mapping, link classifier on canned inputs | exit 0; a deliberately corrupted fixture makes it exit 1 |
| B11 | Package: `release.sh` zips the .app; install notes say right-click, Open, then Open again | Unzip on this Mac in a fresh folder, clear quarantine, launch, `--status` works |
| B12 (P) | Run B2 through B9 with the CIRCLE pad | Same checks, `Serial: D02796D0116D` in Steam's log |
| B13 | Copy to the M5 Air, pair both pads there, apply A2 there, run B2 and B4 and the Stardew A1 winner | The owner's spouse launches Stardew and plays with either pad; a `--status` capture from the Air kept next to this plan |

## Shape of the code

```
XenonDoctor/
  Package.swift                 platforms macOS 14, one executable target
  build.sh                      from sys-monitor, names changed, --dev kept
  release.sh                    from sys-monitor
  Resources/Info.plist          LSUIElement=1, NSBluetoothAlwaysUsageDescription
  Resources/pads.json           [{"mark":"SQUARE","mac":"D0:27:96:F5:49:AD"},
                                 {"mark":"CIRCLE","mac":"D0:27:96:D0:11:6D"}]
  Resources/guide.md            the Stratos Xenon guide, rendered in the app
  Sources/XenonDoctor/
    main.swift                  --status | --repair <link> | --self-test | (no args) menu bar app
    Model/Chain.swift           enum Link { radio, pad, steam, game }
                                struct LinkState { ok: Bool; detail: String; repair: Repair? }
                                struct ChainSnapshot { links: [Link: LinkState]; takenAt: Date }
    Model/Pads.swift            KnownPad(mark, mac); loads pads.json
    Probes/RadioProbe.swift     IOBluetoothHostController.powerState; bluetoothd lag lines
    Probes/PadProbe.swift       GCController list, battery, live input publisher
    Probes/SteamProbe.swift     pgrep steam_osx; tail controller_ui.txt; read localconfig.vdf
    Probes/GameProbe.swift      pgrep "Stardew Valley"; appmanifest state
    Repairs/ReconnectPad.swift  IOBluetoothDevice.openConnection, radio power cycle fallback
    Repairs/RestartSteam.swift  quit, pin, relaunch, wait for log
    Repairs/RelaunchGame.swift  kill, steam://rungameid
    Steam/KeyValues.swift       Valve KeyValues parse and serialise
    Steam/Pin.swift             the A2 values, applied with backup
    UI/StatusItemController.swift  glyph = worst link; menu = four rows + repair
    UI/GuideWindow.swift        NSHostingController over a SwiftUI markdown view
    UI/TesterWindow.swift       GameController live view
    SelfTest.swift              B10
```

Contract a reviewer can argue with:

```swift
protocol Probe { func read() async -> LinkState }
protocol Repair { var title: String { get }; func run() async throws -> LinkState }
final class Chain { func snapshot() async -> ChainSnapshot }   // runs all four probes
```

Every probe is read-only. Every repair returns the link state it produced, so the menu re-renders from the same type that painted it. No repair is ever invoked by a timer.

## The first thing that runs

`swift run XenonDoctor --status` on this Mac, with the SQUARE pad connected and Steam running, printing:

```
radio  ok     Bluetooth on, 2 HID devices, lag warnings: iClever keyboard
pad    ok     SQUARE (Aakarsh Controller) connected, battery 95%
steam  ok     running, sees pad D02796F549AD as PS4 controller
game   off    Stardew Valley not running
```

Proof it worked: the same four facts read independently in the same minute from `system_profiler SPBluetoothDataType`, `gcprobe 4`, `tail -n 5 controller_ui.txt`, and `pgrep`. This slice exists before any menu bar code, so the first failure signal arrives on day one.

## Order of work and what stays untouched

1. A1 today, now that Stardew is installed. Factorio (A4) in the same sitting.
2. A2 and A3 the same day, because the pin is the fix and the app is the way to keep it.
3. B1 and B2 (the first slice), then B4 and B5 (the two repairs that map to the owner's ritual), then B3 (the menu), then B7 to B9, then B10 to B11.
4. B12 with the CIRCLE pad before anything goes near the Air.
5. B13 on the Air, in one visit, with both pads.

Untouched by any step: Karabiner's config, every Bluetooth pairing that is not one of the two pads, every Steam controller config that is not the two pads or app 413080 or app 413150, Steam login state, the Anthropic credentials on this machine.

Model plan: none. This work runs in the main session; there is no fan-out and no sub-agent seat, per the fable-does-it-itself ruling.

## Not authorized by this plan

- Launch at login for the app (`SMAppService`). The owner may want it once the app has earned trust. Listed so it is a decision, not a drift.
- Support for pads other than the two Stratos Xenons. The owner said this model only.
- Notarization for the Air. Right-click Open is the free path; notarization is a $99 decision.
- The Cosmic Byte 2.4 GHz X-input dongle. It would bypass Bluetooth entirely, but it presents as an Xbox 360 class device and macOS has no native driver for that; unverified, and out of scope until the Bluetooth path is proven insufficient.
- A wired USB-C fallback shown in the guide as the last resort. Steam once saw one pad over USB as vendor 0x11C0 product 0x4001; whether that is a full data connection is unverified.
