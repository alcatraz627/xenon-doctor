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
| Bluetooth | radio on | `IOBluetoothPreferenceGetControllerPowerState` |
| Controller | a known pad connected and readable by macOS | paired devices by Bluetooth address, `GCController` list, battery |
| Steam | running with the ignore list, pin in place, has not opened the pad | Steam's process environment, four keys in `localconfig.vdf`, `controller_ui.txt` since Steam started |
| Stardew Valley | running, or cleanly not running | the game process, and Steam's `gameprocess_log.txt` for a game Steam still lists as running |

Each row is green (fine), yellow (one button fixes it), or red (a person has to act, and the row says what to press).

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

## Command modes

```
XenonDoctor --status      the four rows as text, exit 1 when any is not fine
XenonDoctor --repair K    one repair: powerOnRadio reconnectPad restartSteam relaunchGame applyPin
XenonDoctor --self-test   parser round trip, pad lookup, classifier; exit 0 on pass
XenonDoctor --unpin       test reset: remove the four keys and the launch agent
XenonDoctor --guide       open the guide window on launch
XenonDoctor --tester      open the button tester on launch
```

## Layout

```
Sources/XenonDoctor/
  main.swift              command modes and app start
  Model/Chain.swift       Link, Severity, LinkState, ChainSnapshot, Probe, Repair
  Model/Pads.swift        the two pads by pencil mark and address
  Probes/                 one file per link
  Steam/KeyValues.swift   Valve's config text format, parse and write
  Steam/Pin.swift         the four keys, the agent, unpin
  Repairs/Repairs.swift   the five repairs
  UI/                     status item, guide, tester
  SelfTest.swift          --self-test
Resources/                Info.plist, launch agent plist, AppIcon.icns
tools/                    gcprobe and btctl (standalone probes), makeicon
```
