# How Xenon Doctor works

Xenon Doctor is a macOS menu bar app for two Cosmic Byte Stratos Xenon gamepads, Steam, and three games: Stardew Valley, Factorio and Undertale. It watches the chain from the pad to each game and repairs a broken link with one click. It exists because the pads worked some evenings and not others, and every bad evening ended in restarting Bluetooth, Steam, the game, or the Mac.

## The chain

The three games take three different paths from the pad, and each row probes its own path. A green row that only proved the pad reaches macOS was the 0.3.2 bug: the doctor said fine while every game was blind.

```
                      ┌────────────────────────┐
 pad ──Bluetooth──▶   │ macOS HID              │
                      └──┬─────────┬────────┬──┘
                         │         │        │
                  SDL/HIDAPI  GameController  Xenon Doctor's key mapper
                         │         │        │
                     Stardew    Factorio   Undertale (as key presses)
                                 tester
                      Steam: Steam Input off for all three
```

| Link | What "fine" means | What the app checks |
|---|---|---|
| Bluetooth | radio on, and this app allowed to use it | `IOBluetoothPreferenceGetControllerPowerState`, `CBCentralManager.authorization` |
| Controller | a known pad connected and seen by macOS as a DualShock | paired devices by Bluetooth address, `GCController` list and its product category, battery from the pad's own HID report |
| Steam | installed, and its controller settings pinned (Steam Input off for every game, Home button not reaching Steam) | `NSWorkspace`, the pinned keys in `localconfig.vdf`. Whether Steam has opened the pad for its own windows is a note, not breakage: the keys cannot stop that, and the games read the pad directly |
| Stardew Valley | installed; running or cleanly not running; and nothing tells its SDL to ignore the pad | Steam's manifest and process log, the game process, `launchctl getenv SDL_GAMECONTROLLER_IGNORE_DEVICES` (cleared on the spot when found), the running game's own environment via `ps -E` |
| Factorio | as Stardew, and its input method set to game controller | the same Steam checks, plus `input-method` under `[input]` in `~/Library/Application Support/factorio/config/config.ini` |
| Undertale | as Stardew, and macOS lets Xenon Doctor press keys for it | the same Steam checks, plus `AXIsProcessTrusted` |

Each row is green (fine), yellow (one button fixes it), or red (a person has to act, and the row says what to press). A row that is fine only because nothing is happening (Steam or a game not running) wears a faded green, so dormant and working read differently at a glance. The menu shows a one-line hint under a broken row; the window's Status tab shows the full sentence.

When every row is green and a game is running, one more row appears in the menu and the window: "Choppa da Wood (enjoy the game)", with a green dot that breathes. It is the one moment the app has nothing left to say.

## A repair is judged by the chain after it

Every button runs its repair and then reads the whole chain again, and the rows show that second reading. A repair never paints its own row green: the row it touched may be fine while the fix exposed another (Fix Steam settings restarts Steam, which can change what a game row sees), and only the full re-read shows that. From the terminal, `--repair K` prints the repair's own report and then the chain, and its exit code is the chain's.

## Undertale: the key mapper

Undertale is a GameMaker game and cannot read a pad on a Mac (its own FAQ says so, and its bundled gamepad library never answered this pad). So while Undertale is the front window, Xenon Doctor turns pad presses into key presses: D-pad and left stick are the arrows (the stick engages past 0.4 and lets go under 0.3, so a diagonal does not flicker), Cross is Z, Circle, Square and a held R2 are X, Triangle and the touchpad are C, Options is Enter, Share is F4. The presses come from the pad's own HID reports, the same source as the Status row and the tester. The moment Undertale is not in front, or the pad disconnects, every held key is released. macOS only lets an app press keys with its Accessibility switch on, which is the Undertale row's one go-there button.

That switch is remembered by the app's code signature, so `build.sh` signs with the household's own certificate (`tools/signing-cert.sh` makes it once, on the Mac that builds). An ad-hoc signature changes with every build, and the switch would look on and do nothing after each update.

The pads themselves come from a small JSON registry, so a third pad is one line and no rebuild: [`pads-registry.md`](pads-registry.md).

Three of the buttons do not repair anything themselves. They open the one place where the person has to finish: the Bluetooth privacy list when the app has been denied Bluetooth, Steam's download page when Steam is missing, the game's Steam page when the game is missing. Two states are shown green with a note rather than as breakage: two pads connected at once (the game takes the first), and the game started outside Steam (it plays, but cloud saves want Steam).

## Probes run with a deadline

The four probes run concurrently and the snapshot waits six seconds for them. A probe that has not answered shows its row as "not answering" with what the person can do (turn Bluetooth off and on; restart the Mac), and a probe still running from an earlier cycle is not started again, so a system call that never returns cannot pile up threads. This exists because `IOBluetoothPreferenceGetControllerPowerState` blocked for good inside the app on 2026-09-05 while the same call from the command line answered at once; without the deadline the Status tab stayed empty. The tester's device card reads pad details from the pad probe's last result for the same reason: no IOBluetooth call ever runs on the main thread.

## The button tester

The Button tester tab is a SceneKit scene (`ControllerView.swift`): the pad's outline extruded into a slab, raised caps and wells for the controls, three lights and a camera. Readings from GameController light the pressed control's material, lean the stick knobs, and fill the triggers; the light bar glows when a pad is connected. Dragging orbits the camera with SceneKit's own control, scrolling zooms, a double click re-centres. The outline's `flatness` is set low because SceneKit polygonises the path at that tolerance and the default turns the grips into octagons. The scene fills whatever height the tab has; under it, when a pad is connected, a card names the pad (mark and whose it is), its address, what it is paired as, signal, battery, and what macOS calls it, followed by the checklist of controls to try. With no pad, a red line sits on the scene and the checklist says what to press.

## The window's keys

Cmd-W closes the window, Ctrl-Tab and Ctrl-Shift-Tab cycle the tabs, Cmd-1, Cmd-2 and Cmd-3 jump to one. A menu bar app has no main menu, so these are handled by the window itself (`DoctorPanel`). The guide ends with a Docs section linking the repository, README, this document and the releases page, and under that the household's mascot turning slowly, which is an easter egg the owner asked for by name.

## Battery

macOS's GameController layer reports zero for this pad, so the app reads the pad's own input report over HID (`PadBattery.swift`). A DualShock 4 over Bluetooth sends a short report until something asks it for a feature report, then switches to the full report `0x11`, whose byte 32 holds the charge in tenths and a cable flag. The app asks once when the pad appears and reads the byte from every report after. Nothing is written to the pad, and the device is opened shared, so the game is not disturbed.

## Why Steam Input is kept off

The pads are DualShock 4 clones. With Steam Input on, Steam recognises them as PS4 controllers and applies its own layouts inside games. On this Mac that path produced a keyboard-and-mouse mapping inside the game once, hundreds of virtual device add-and-remove events per session, and one display freeze that needed the power button. All three games are better served with Steam Input off: Stardew and Factorio read the pad directly, and Undertale gets its keys from Xenon Doctor.

The pin is a set of keys in `localconfig.vdf`: PlayStation support off, the Home button not focusing Steam, the chord layer off, and Steam Input forced off per game for each of the three games. Steam only writes that file when it quits, so the Fix button quits Steam, writes, and relaunches. The measured record is in `.claude/output/20260905-1715-xenon-doctor-change/pin.md`.

Versions 0.2 through 0.3.2 also put `SDL_GAMECONTROLLER_IGNORE_DEVICES` into the login session through a launch agent so Steam's own SDL would skip the pad. That variable is read by every SDL program, so it blinded Stardew too. It is gone; the app clears it on every launch and the Stardew row clears it again whenever it reappears.

## Repairs

| Button | What it does |
|---|---|
| Turn Bluetooth on | powers the radio on and waits |
| Reconnect controller | asks each paired pad to connect; if none answers in eight seconds, cycles the radio once and asks again |
| Fix Steam settings | quits Steam and waits for it to exit (Steam answers "cancel" and then exits on its own, up to 75 s), writes the pinned keys with a backup beside the file, relaunches Steam |
| Clear the stale controller block | clears the old login-session variable again; offered only when it came back after the app cleared it |
| Set up Factorio for the pad | writes `input-method=game-controller` and binds copy, paste, search, blueprint library, undo and redo to L2 and R2 chords (Factorio ships them on Steam Deck paddles), with a backup beside the file; a running Factorio is asked to quit first (it offers to save), then relaunched |
| Allow Xenon Doctor to press keys | lists the app under Accessibility and opens that pane; the person flips the switch |
| Relaunch Stardew Valley, Factorio, Undertale | asks the game to quit, waits, launches it again through Steam. Never a kill signal |

## The one failure no button fixes

After a crash or forced restart the Mac loses the pad's Bluetooth service record. The pad only serves that record while in pairing mode. A PS press then connects for two seconds and drops. The fix is to hold Share and PS until the light bar blinks fast. The app shows that line whenever a pad is paired but not connected.

## Updates

The app asks `https://api.github.com/repos/alcatraz627/xenon-doctor/releases/latest` once a day at 3 PM, and at launch only when the last check is more than a day old (the time is kept in the app's defaults). The rows themselves are re-read every five seconds; that is local and never touches the network. When the tag is newer than the running version (numeric compare, so 0.10 beats 0.9), the menu grows a row, "Update to vX and relaunch". That row downloads the release zip, unpacks it with `ditto`, moves the running bundle aside into the temp folder, moves the new one into its place, and starts it with `open -n` before quitting. A file the app downloads itself carries no quarantine flag, so the new copy opens with no right-click step. The swap is exercised from the terminal with `--update --force`, which reinstalls the current release over a copy of the app.

## Command modes

```
XenonDoctor --status          every row as text, exit 1 when any is not fine
XenonDoctor --repair K        one repair, then the whole chain again; exit code is the chain's
XenonDoctor --self-test       parser round trip, pad lookup, classifier, Factorio config edit, key table, version compare; exit 0 on pass
XenonDoctor --unpin           test reset: remove the pinned keys and any old launch agent
XenonDoctor --pads            print the pad registry and where it was read from
XenonDoctor --add-pad M MAC   add a pad of the same model; --remove-pad M takes it out
XenonDoctor --check-update    print the latest release against this build
XenonDoctor --update          install the latest release over this bundle; --force reinstalls the same version
XenonDoctor --window          open the window on the Status tab
XenonDoctor --tester          open the window on the Button tester tab
XenonDoctor --guide           open the window on the Controller guide tab
XenonDoctor --menu            pop the menu two seconds after launch, for screenshots
XenonDoctor --window --frame 1100x900   open at a given size, to check a layout
```

Add `--light` or `--dark` after any window flag to force that appearance for the app only. `XENON_DEMO=playing` in the environment makes every row green with the game running, to see the fifth row without launching a game. Set `XENON_TRACE=1` in the environment for one-line notes on stderr about the window (`open -n XenonDoctor.app --env XENON_TRACE=1 --stderr trace.txt --args --window`). Screenshots of the window come from `tools/winshot`, which lists and captures windows by the owner's display name, "Xenon Doctor"; System Events cannot see a menu bar app's windows.

## Layout

```
Sources/XenonDoctor/
  main.swift              command modes and app start
  Model/Chain.swift       Link, Severity, LinkState, ChainSnapshot, Probe, Repair
  Model/Games.swift       the three games: bundle id, Steam id, which input path each uses
  Model/Pads.swift        the pad registry: JSON file, lookup by address, add and remove
  Probes/                 one file per shared link, GameProbe for every game, PadBlock for the old
                          login-session variable, PadBattery for the HID battery byte
  Games/FactorioConfig.swift   read and set input-method in Factorio's config.ini
  Games/KeyMapper.swift        pad presses to key presses for Undertale, Accessibility check
  Steam/KeyValues.swift   Valve's config text format, parse and write
  Steam/Pin.swift         the pinned keys, heal, unpin
  Repairs/Repairs.swift   the repairs, the go-there buttons, and the re-read after each
  UI/                     status item and menu, the tabbed window, tester pane, the SceneKit pad model, guide text
  Updater.swift           GitHub release check, download, swap, relaunch
  Trace.swift             XENON_TRACE stderr notes
  SelfTest.swift          --self-test
Resources/                Info.plist, pads.json, beanu-boss.png, AppIcon.icns
tools/                    gcprobe and btctl (standalone probes), makeicon, winshot, signing-cert.sh
```
