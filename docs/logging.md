# Logging: where the truth is when something goes wrong

The app reads these; a person can read them too. Paths are for the logged-in user.

## The app's own view

```
/Applications/XenonDoctor.app/Contents/MacOS/XenonDoctor --status
```

Four lines, one per link, `ok` or `FIX`, with the button or the hint. Exit code 1 when any link is not fine. This is the first thing to run.

## Steam

| File | What to look for |
|---|---|
| `~/Library/Application Support/Steam/logs/controller_ui.txt` | `Controller 0 connected, configuring it now` means Steam opened a pad. With the pin in place this line must not appear after Steam started. |
| `~/Library/Application Support/Steam/logs/console_log.txt` | `Added HIDAPI device ... driver = NONE (DISABLED)` is the pad being skipped, which is correct. `Valve Software Keyboard-1` or `Mouse-1` means Steam built virtual devices, which is the state to avoid. `Guide button sent to JS` means the Home button reached Steam. |
| `~/Library/Application Support/Steam/logs/gameprocess_log.txt` | `Game process added` and `Remove 413150 from running list` bracket a Stardew session. `exit code 137` on the wrapper is routine. |
| `~/Library/Application Support/Steam/userdata/<account>/config/localconfig.vdf` | the four pin keys under `UserLocalConfigStore`. Backups written by the app sit beside it as `localconfig.vdf.xenondoctor-*.bak`. |

Steam's environment, to confirm the ignore list is present:

```
ps -E -p "$(pgrep -f MacOS/steam_osx)" -o command=
```

## Bluetooth

The daemon's log is the record of every connect and drop. `log` is a zsh builtin, so use the full path.

```
/usr/bin/log show --last 10m --predicate 'process == "bluetoothd" AND eventMessage CONTAINS "D0:27:96"' --style compact
```

Lines that matter:

| Line | Meaning |
|---|---|
| `SDP query has completed ... with status 0` | the Mac fetched the pad's service record; the connection will hold |
| `SDP query has completed ... with status 1` then `disconnected with reason STATUS 722` | the pad refused the record; hold Share and PS |
| `disconnected with reason STATUS 719` | the pad was switched off |
| `HID Latency Statistics events indicated HID lag issue` | the radio is congested; the device named by vid and pid is the one lagging |

## macOS input layer

```
tools/gcprobe 6        what GameController sees, and every button press for six seconds
tools/btctl list       paired devices and connection state
tools/btctl cycle      radio off and on
hidutil list           every HID device; vendor 0x28de entries are Steam's virtual devices
```

## The launch agent

```
launchctl print gui/501/com.xenondoctor.steam-env
launchctl getenv SDL_GAMECONTROLLER_IGNORE_DEVICES
```

The first shows the agent loaded with `last exit code = 0`; the second prints `0x054c/0x09cc`.

## After a freeze

No `.panic` file in `/Library/Logs/DiagnosticReports` means the kernel did not crash. Pull the window server and kernel errors for the minute before the freeze:

```
/usr/bin/log show --start "YYYY-MM-DD HH:MM:00" --end "YYYY-MM-DD HH:MM:00" --predicate 'messageType == 16 OR messageType == 17' --style compact
```

`Clearing datagram buffer for cid ...` from WindowServer and `IOSurface ... fClientTask = 0x0 not found` from the kernel together mean a client died with its window and surfaces still registered. That was the 2026-09-05 freeze.
