# A1 in-game matrix, SQUARE pad, this MacBook Pro

<!-- sessions: pad-steam-7c@2026-09-05 -->

One row per launch of Stardew Valley from Steam. The Steam column quotes `~/Library/Application Support/Steam/logs/controller_ui.txt` for app 413150. The verdict column holds the owner's own words.

| Row | Steam Input for Stardew | Pad at launch | Steam applied | Owner verdict | Time |
|---|---|---|---|---|---|
| 1 | default, no per-app key in localconfig.vdf | connected | `Local Override Path for App ID 413150: controller_base/empty.vdf` | "controller works on stardew valley menu" | 2026-09-05 17:15 |
| 2 | same as row 1 | pad turned off and on twice while the game ran | `Controller 0 disconnected` then `connected, configuring it now` 4 to 5 s later, both times | "game auto-pairs, starts working. Did this twice, worked" | 2026-09-05 17:19 |
| 3 | same as row 1 | game quit, Steam still showed Stop, pad turned off, Stop clicked twice | game killed with exit 137 at 17:20:34, Mac froze about 17:21, power button | "went absolutely disastrously", see `crash-20260905-1721.md` | 2026-09-05 17:21 |

## Reconnect failure after the hard reset, and its fix

After the forced power off, every PS press produced the same sequence in the Bluetooth daemon log: link key found, encryption complete, then `Delaying response to incoming HID connection request ... as SDP is missing`, `SDP query has completed ... with status 1`, `HID Host ... result was 1`, and two seconds later `disconnected with reason STATUS 722` (terminated by the Mac). Six attempts between 17:33 and 17:45, including three after a Bluetooth radio power cycle from `tools/btctl cycle`. The radio cycle changed nothing.

Holding Share and PS together for about four seconds fixed it on the first try at 17:46:57: `SDP query has completed ... with status 0`, `HID Host ... result was 0`, `Writing HID Data to disk`. The pad only answers the service-discovery query while in pairing mode. The Mac caches the answer on disk. The hard reset lost the cache. The pin has nothing to do with this failure.

Repair the app teaches for "pad blinks, shows connected, then drops": hold Share and PS until the light bar blinks fast. Forgetting the device is not needed.

## Rows 4 to 7, with the four-key pin in place, 17:50 to 17:55

| Row | Case | Steam log | Owner verdict |
|---|---|---|---|
| 4 | pad off with a 10 s PS hold, then one PS press, no game running | reconnect logged, no `Guide button` line, no `chord` line | "yes worked ... stays connected, with a single press" |
| 5 | Stardew launched from Steam, pad already on | `Local Override Path for App ID 413150: empty.vdf` | "controller works" |
| 6 | pad off and on while the game ran | `Controller 0 disconnected` at 17:52:45, reconnected | "still auto-connects and works in game" |
| 7 | game quit from its own menu, pad off, game relaunched, pad on | game removed 17:53:15, relaunched 17:53:38, pad reconnected 17:54:03 | "still paired and started working fine in the game" |

Row 7 is the sequence that froze the Mac at 17:21. It passed.

Still open in Steam's log for the same window: 224 lines adding and removing `Valve Software Keyboard-1` and `Valve Software Mouse-1`. Steam still opens the pad with its PS4 driver when it connects and still rebuilds those two virtual devices around every config reload. The pin removed the guide and chord triggers but not this.

Adverse cases still queued:

1. Steam Input forced on for Stardew, to reproduce the "weird" state once, on purpose.
2. Game launched from the .app with Steam quit.
3. Mac sleep and wake with the pad connected.
4. Pad powered on in the wrong mode.
5. The four keys survive a Mac reboot.
