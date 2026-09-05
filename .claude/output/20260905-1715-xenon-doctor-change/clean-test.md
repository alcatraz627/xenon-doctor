# Clean test on this Mac before the Air

<!-- sessions: pad-steam-7c@2026-09-05 -->

A dress rehearsal. This Mac is put back to the state the M5 Air is in today: pad not paired, Steam on its defaults, no launch agent, no ignore list in Steam's environment, Xenon Doctor not installed. Then the chain is brought up using only the app and its guide, with the owner acting as the person who has never seen any of this. Every step names who acts, what proves it, and where the proof is kept.

Passing here is the bar for taking the zip to the Air. Anything that needs me typing in a terminal during the run is a defect in the app, not a step in the test.

## What gets reset, and how

| # | State today | Reset to | How | Reversible |
|---|---|---|---|---|
| R1 | SQUARE pad paired as "Aakarsh Controller" | not paired | owner: System Settings, Bluetooth, the pad's info button, Forget This Device | yes, re-pair with Share + PS |
| R2 | four pin keys in `localconfig.vdf` | Steam defaults (keys removed) | me: `XenonDoctor --unpin` while Steam is quit; it removes the four keys and keeps a timestamped backup | yes, backup beside the file |
| R3 | launch agent loaded, variable in the login session | absent | same `--unpin`: `launchctl bootout`, `launchctl unsetenv`, plist removed | yes, the app reinstalls it |
| R4 | Steam running with the ignore list | Steam running without it, owning the pad again | owner: quit Steam from its menu, start it from the Dock | yes |
| R5 | XenonDoctor running from the project folder | not installed | me: quit it; owner installs from the zip like on the Air | yes |

Not reset: Stardew Valley stays installed (the Air has it installed), the Steam login stays, every other Bluetooth pairing stays.

## The run

Each row: who acts, the step, the check that flips, the evidence file kept under `evidence/clean-test/`.

| Step | Who | Action | Check | Evidence |
|---|---|---|---|---|
| 1 | owner | Unzip `XenonDoctor-0.1.0.zip`, drag the app to Applications, right-click, Open, Open | the triangle appears in the menu bar | `01-menubar.png` |
| 2 | owner | Click the triangle, read the four rows aloud | rows read: Bluetooth on; Controller no pad paired with the pairing hint; Steam wrong settings with one button; Stardew not running | `02-menu-fresh.png` |
| 3 | owner | Click "Fix Steam settings" | Steam quits and comes back on its own; the Steam row turns green within 40 s | `03-menu-after-fix.png`, `03-status.txt` from `--status`, `launchctl getenv` output, `console_log.txt` tail |
| 4 | owner | Open the guide from the menu and follow "Pairing a pad to a new Mac" with the SQUARE pad | Controller row green with battery; Steam row stays green | `04-menu-paired.png`, `controller_ui.txt` gains no "configuring" line |
| 5 | owner | Open the button tester, press each face button and move both sticks | each pressed button lights, sticks move | `05-tester.png` |
| 6 | owner | Launch Stardew from Steam, play a minute, press Home once | game row "running"; Home does nothing to Steam | `06-menu-ingame.png`, `console_log.txt` has no Guide line |
| 7 | owner | Turn the pad off with a 10 s PS hold, then one PS press, still in game | game picks the pad back up | owner's word, Steam log shows disconnect and reconnect |
| 8 | owner | Quit the game from its menu | game row back to "not running" within 10 s | `08-status.txt` |
| 9 | owner | Reboot the Mac, log in, wait one minute, open the app | Steam row: green means the agent beat the login item; "started without the controller ignore list" with a Restart Steam button means the race is real and one click fixes it | `09-menu-after-reboot.png`, `ps -E` of Steam |
| 10 | owner | If step 9 showed the button, click it | Steam row green | `10-status.txt` |
| 11 | owner | Pair the CIRCLE pad the same way and repeat steps 5 to 8 with it | same checks, Steam log names serial D02796D0116D nowhere as configured | `11-*.png` |

A step that fails stops the run. The failure is fixed in the app and the run restarts from the reset, because the Air will see the same sequence from the same starting point.

## What the app must have before the run starts

These are built now, in order, before any reset:

1. `--unpin`, the reset command for R2 and R3. Not shown in the menu.
2. The reconnect and restart-Steam repairs exercised once each here, with the pad off, so the run is not their first execution.
3. `release.sh` produces the zip.

## Owner gates

One approval covers the five resets, since each is reversible and the owner asked for the clean test. The reboot in step 9 is the owner's time and happens when he chooses.

## Not part of this test

The "blinks, connects, drops" failure cannot be induced on demand; it needs the Mac's cached service record for the pad to be lost, which only a crash has done so far. The guide covers it in words. Factorio is not run. The Bluetooth congestion indicator is not built yet and not tested here.
