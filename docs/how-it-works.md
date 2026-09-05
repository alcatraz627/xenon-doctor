# How Xenon Doctor works

Xenon Doctor is a macOS menu bar app for two Cosmic Byte Stratos Xenon gamepads, Steam, and Stardew Valley. It watches a four-link chain and repairs a broken link with one click. It exists because the pads worked some evenings and not others, and every bad evening ended in restarting Bluetooth, Steam, the game, or the Mac.

## The chain

```
 pad ──Bluetooth──▶ macOS ──GameController──▶ Stardew Valley
                      │
                      └── Steam (kept out of the way)
```

| Link | What "fine" means | What the app checks |
|---|---|---|
| Bluetooth | radio on, and this app allowed to use it | `IOBluetoothPreferenceGetControllerPowerState`, `CBCentralManager.authorization` |
| Controller | a known pad connected and seen by macOS as a DualShock | paired devices by Bluetooth address, `GCController` list and its product category, battery from the pad's own HID report |
| Steam | installed; running with the ignore list, pin in place, has not opened the pad; or not running with the agent loaded so its next start inherits the list | `NSWorkspace`, Steam's process environment, four keys in `localconfig.vdf`, `launchctl getenv`, `controller_ui.txt` since Steam started |
| Stardew Valley | installed; running, or cleanly not running | `appmanifest_413150.acf` in each Steam library, the game process, Steam's `gameprocess_log.txt` for a game Steam still lists as running |

Each row is green (fine), yellow (one button fixes it), or red (a person has to act, and the row says what to press). A row that is fine only because nothing is happening (Steam or the game not running) wears a faded green, so dormant and working read differently at a glance. The menu shows a one-line hint under a broken row; the window's Status tab shows the full sentence.

When all four rows are green and the game is running, a fifth row appears in the menu and the window: "Choppa da Wood (enjoy the game)", with a green dot that breathes. It is the one moment the app has nothing left to say.

The pads themselves come from a small JSON registry, so a third pad is one line and no rebuild: [`pads-registry.md`](pads-registry.md).

Three of the buttons do not repair anything themselves. They open the one place where the person has to finish: the Bluetooth privacy list when the app has been denied Bluetooth, Steam's download page when Steam is missing, the game's Steam page when the game is missing. Two states are shown green with a note rather than as breakage: two pads connected at once (the game takes the first), and the game started outside Steam (it plays, but cloud saves want Steam).

## The button tester

The Button tester tab is a SceneKit scene (`ControllerView.swift`): the pad's outline extruded into a slab, raised caps and wells for the controls, three lights and a camera. Readings from GameController light the pressed control's material, lean the stick knobs, and fill the triggers; the light bar glows when a pad is connected. Dragging orbits the camera with SceneKit's own control, scrolling zooms, a double click re-centres. The outline's `flatness` is set low because SceneKit polygonises the path at that tolerance and the default turns the grips into octagons.

## Battery

macOS's GameController layer reports zero for this pad, so the app reads the pad's own input report over HID (`PadBattery.swift`). A DualShock 4 over Bluetooth sends a short report until something asks it for a feature report, then switches to the full report `0x11`, whose byte 32 holds the charge in tenths and a cable flag. The app asks once when the pad appears and reads the byte from every report after. Nothing is written to the pad, and the device is opened shared, so the game is not disturbed.

## Why Steam is kept out

The pads are DualShock 4 clones. Steam recognises them as PS4 controllers, opens them, and creates a virtual keyboard and mouse for its desktop layout. On this Mac that path produced a keyboard-and-mouse mapping inside the game once, hundreds of virtual device add-and-remove events per session, and one display freeze that needed the power button. Stardew Valley reads the pad directly through its own SDL and plays cleanly that way.

Steam's own settings cannot stop it opening the pad. Its controller layer is SDL, and SDL honours an environment variable:

```
SDL_GAMECONTROLLER_IGNORE_DEVICES=0x054c/0x09cc
```

A launch agent, `com.xenondoctor.steam-env`, puts that variable into the login session at login, so Steam started from the Dock or at login inherits it. The app installs the agent and also writes four Steam settings that stop the Home button reaching Steam and disable Steam Input for the game. The measured record is in `.claude/output/20260905-1715-xenon-doctor-change/pin.md`.

## Repairs

| Button | What it does |
|---|---|
| Turn Bluetooth on | powers the radio on and waits |
| Reconnect controller | asks each paired pad to connect; if none answers in eight seconds, cycles the radio once and asks again |
| Restart Steam | quits Steam and waits for it to exit (Steam answers "cancel" and then exits on its own, up to 75 s), makes sure the pin is in place, launches Steam from a clean environment carrying only the ignore list |
| Fix Steam settings | quits Steam, writes the four keys with a backup beside the file, installs and loads the launch agent, relaunches Steam |
| Relaunch Stardew Valley | asks the game to quit, waits, launches it again through Steam. Never a kill signal |

## The one failure no button fixes

After a crash or forced restart the Mac loses the pad's Bluetooth service record. The pad only serves that record while in pairing mode. A PS press then connects for two seconds and drops. The fix is to hold Share and PS until the light bar blinks fast. The app shows that line whenever a pad is paired but not connected.

## Updates

The app asks `https://api.github.com/repos/alcatraz627/xenon-doctor/releases/latest` once a day at 3 PM, and at launch only when the last check is more than a day old (the time is kept in the app's defaults). The rows themselves are re-read every five seconds; that is local and never touches the network. When the tag is newer than the running version (numeric compare, so 0.10 beats 0.9), the menu grows a row, "Update to vX and relaunch". That row downloads the release zip, unpacks it with `ditto`, moves the running bundle aside into the temp folder, moves the new one into its place, and starts it with `open -n` before quitting. A file the app downloads itself carries no quarantine flag, so the new copy opens with no right-click step. The swap is exercised from the terminal with `--update --force`, which reinstalls the current release over a copy of the app.

## Command modes

```
XenonDoctor --status          the four rows as text, exit 1 when any is not fine
XenonDoctor --repair K        one repair: powerOnRadio reconnectPad restartSteam relaunchGame applyPin
XenonDoctor --self-test       parser round trip, pad lookup, classifier, menu hints, version compare; exit 0 on pass
XenonDoctor --unpin           test reset: remove the four keys and the launch agent
XenonDoctor --pads            print the pad registry and where it was read from
XenonDoctor --add-pad M MAC   add a pad of the same model; --remove-pad M takes it out
XenonDoctor --check-update    print the latest release against this build
XenonDoctor --update          install the latest release over this bundle; --force reinstalls the same version
XenonDoctor --window          open the window on the Status tab
XenonDoctor --tester          open the window on the Button tester tab
XenonDoctor --guide           open the window on the Controller guide tab
XenonDoctor --menu            pop the menu two seconds after launch, for screenshots
```

Add `--light` or `--dark` after any window flag to force that appearance for the app only. `XENON_DEMO=playing` in the environment makes every row green with the game running, to see the fifth row without launching a game. Set `XENON_TRACE=1` in the environment for one-line notes on stderr about the window (`open -n XenonDoctor.app --env XENON_TRACE=1 --stderr trace.txt --args --window`). Screenshots of the window come from `tools/winshot`, which lists and captures windows by the owner's display name, "Xenon Doctor"; System Events cannot see a menu bar app's windows.

## Layout

```
Sources/XenonDoctor/
  main.swift              command modes and app start
  Model/Chain.swift       Link, Severity, LinkState, ChainSnapshot, Probe, Repair
  Model/Pads.swift        the pad registry: JSON file, lookup by address, add and remove
  Probes/                 one file per link, plus PadBattery.swift for the HID battery byte
  Steam/KeyValues.swift   Valve's config text format, parse and write
  Steam/Pin.swift         the four keys, the agent, unpin
  Repairs/Repairs.swift   the five repairs and the three go-there buttons
  UI/                     status item and menu, the tabbed window, tester pane, the SceneKit pad model, guide text
  Updater.swift           GitHub release check, download, swap, relaunch
  Trace.swift             XENON_TRACE stderr notes
  SelfTest.swift          --self-test
Resources/                Info.plist, launch agent plist, pads.json, AppIcon.icns
tools/                    gcprobe and btctl (standalone probes), makeicon, winshot
```
