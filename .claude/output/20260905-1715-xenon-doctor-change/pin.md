# The pinned Steam configuration

<!-- sessions: pad-steam-7c@2026-09-05 -->

These are the exact keys Steam wrote when the owner flipped the settings in the Steam UI on 2026-09-05 at about 17:35. They were read from `~/Library/Application Support/Steam/userdata/331921170/config/localconfig.vdf` after Steam quit, by diffing against a snapshot taken before the clicks. Steam only flushes this file on quit, so any tool that writes it must do so while Steam is not running.

All four sit under the top level `UserLocalConfigStore` block.

| Key | Value | UI control it came from | What it stops |
|---|---|---|---|
| `SteamController_PSSupport` | `0` | Settings, Controller, "Enable Steam Input for PlayStation controllers" off | Steam opening the pad, building virtual keyboard and mouse devices for it, and applying any config |
| `Controller_CheckGuideButton` | `0` | Settings, Controller, "Guide Button Focuses Steam" off | the Home button raising Steam or the overlay |
| `SteamController_Enable_Chord` | `0` | written by Steam alongside the above | the Home button chord layer (`chord_ps4.vdf`) |
| `apps` / `413150` / `UseSteamControllerConfig` | `0` | Library, Stardew Valley, Properties, Controller, "Disable Steam Input" | Steam Input for this game even if the global toggle is ever turned back on |

Steam also wrote `SteamControllerRumble -1` and `SteamControllerRumbleIntensity 320` under the same app block. Those are defaults and are not part of the pin.

## What the pin did not do, measured 17:46:59

With all four keys in place and Steam relaunched, Steam still opened the pad when it connected: `Steam controller device opened for index 0`, `Type: 34`, and one pair of virtual devices `Valve Software Keyboard-1` and `Valve Software Mouse-1` created (`~/Library/Application Support/Steam/logs/console_log.txt` lines 3269 to 3299, and `hidutil list` shows both at vendor 0x28DE). So `SteamController_PSSupport 0` does not stop the Steam client from taking the pad for its own UI. It stops Steam Input in games. The two keys that address the freeze directly are `Controller_CheckGuideButton 0` and `SteamController_Enable_Chord 0`, which stop the Home button from raising Steam and stop the chord layer. Whether the virtual devices still churn on focus changes is the next measurement.

## The fifth part of the pin: Steam's environment, measured 17:58 to 18:01

Steam's controller layer is SDL. SDL honours an ignore list in the environment. Launching Steam with

```
SDL_GAMECONTROLLER_IGNORE_DEVICES=0x054c/0x09cc
```

made Steam skip the pad entirely: `console_log.txt` shows the pad enumerated with `driver = NONE (DISABLED)` and then no `Steam controller device opened`, no `Type: 34`, no `Valve Software Keyboard-1` or `Mouse-1`; `hidutil list` shows no vendor 0x28DE device; `controller_ui.txt` gained no new lines. macOS and the game still see the pad (`tools/gcprobe` reports the DualShock 4 profile). Both Stratos Xenon pads share the same vendor and product id, so one entry covers both.

A weaker variant, `SDL_JOYSTICK_HIDAPI_PS4=0`, only switched Steam to a second driver path; Steam still opened the pad and still built the virtual devices. Not the fix.

The environment has to be present when Steam starts. `open --env SDL_GAMECONTROLLER_IGNORE_DEVICES=0x054c/0x09cc -a Steam` did it for this test. Caveat measured with `ps -E`: `open --env` forwarded the whole calling shell environment to Steam, not just the one variable, so the app must launch Steam from a clean environment and add only this variable.

Owner ruled at 18:02: a launch agent. Installed at `~/Library/LaunchAgents/com.xenondoctor.steam-env.plist` (source copy in `/Users/alcatraz627/Code/Personal/controlelr/Resources/`). It runs `launchctl setenv SDL_GAMECONTROLLER_IGNORE_DEVICES 0x054c/0x09cc` once at login. Verified 18:03: `launchctl getenv` returns the value, a plain `open -a Steam` inherited it, and Steam enumerated the pad with `driver = NONE (DISABLED)` and never opened it.

Known race: Steam is itself a login item on this Mac, so at login it may start before the agent has run. The app checks Steam's environment and offers "Restart Steam" when the variable is missing. The reboot test decides whether the race is real.

## What the game sees with this pin

Stardew Valley reads the pad directly through its bundled SDL. macOS classifies the pad as a DualShock 4. Steam is not in the input path at all. This is the same path that produced the clean result in row 1 of the matrix, minus Steam's ability to swap in a keyboard-and-mouse profile or thrash virtual devices.

## How the app applies it on another Mac

1. Confirm Steam is not running.
2. Back up `localconfig.vdf` next to itself with a timestamp.
3. Set the four keys above, creating the `apps` and `413150` blocks if absent.
4. Launch Steam.
5. Confirm by reading `~/Library/Application Support/Steam/logs/controller_ui.txt`: with the pad connected, no new `Controller 0 connected, configuring it now` line appears.

The account id in the path differs per Steam login. The M5 Air uses the same Steam account, so the path is the same there.
