<div align="center">
  <img src="assets/cover.svg" alt="Xenon Doctor cover" width="160">
</div>

<h1 align="center">Xenon Doctor</h1>

<p align="center">
  A macOS menu bar app that keeps two Cosmic Byte Stratos Xenon gamepads working with Steam and Stardew Valley, and repairs a broken link with one click.
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2014%2B-black">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5-F05138">
  <img alt="Version" src="https://img.shields.io/badge/version-0.3.0-blue">
  <img alt="Build" src="https://img.shields.io/badge/build-Command%20Line%20Tools%2C%20no%20Xcode-lightgrey">
</p>

---

## About

Two Stratos Xenon pads, two MacBooks, one game. The pads worked some evenings and not others. A pad would blink and drop, or Steam would show it connected while the game saw a keyboard, and every bad evening ended in restarting Bluetooth, Steam, the game, or the Mac. One evening it ended with the power button.

Xenon Doctor watches the four links a play session depends on: the Bluetooth radio, the pad, Steam, and the game. Each row in its menu is green, yellow with one button, or red with one sentence saying what to press. Its window has three tabs: the same rows with their full text and buttons, a button tester that draws the pad and ticks off each control, and the guide for this exact pad model. It writes the Steam settings that keep Steam out of the controller's way, because letting Steam handle these pads is what produced the keyboard mapping and the freeze, reads the pad's battery from the pad's own report, and updates itself from this repository's releases.

It is built for one household and two specific pads, on purpose. The pads are identified by pencil mark and Bluetooth address, and nothing in it is generic.

## Quick Start

Install from the zip on the Mac that will play:

1. Unzip `XenonDoctor-<version>.zip` and drag `XenonDoctor.app` into Applications.
2. Right-click the app, choose Open, then Open again. This is needed once because the app is signed ad hoc, not notarized.
3. Click the controller icon in the menu bar. Click any yellow row's button. Follow any red row's sentence.

Build it yourself, with Command Line Tools only:

```bash
git clone https://github.com/alcatraz627/xenon-doctor.git
cd xenon-doctor
./build.sh                                  # XenonDoctor.app, ad-hoc signed
.build/release/XenonDoctor --self-test      # exit 0 means the parser, pad lookup, and classifier pass
./release.sh                                # the zip to carry to the other Mac
```

Command modes, useful from a terminal when the menu is not enough:

```bash
XenonDoctor --status          # the four rows as text
XenonDoctor --repair K        # powerOnRadio | reconnectPad | restartSteam | relaunchGame | applyPin
XenonDoctor --check-update    # compare this build with the latest GitHub release
XenonDoctor --update          # install the latest release over this app and exit
```

Later installs never need the right-click step: the menu's update row downloads the new zip, swaps the app in place, and relaunches it.

## Documentation

| Document | Description |
| --- | --- |
| [How it works](docs/how-it-works.md) | the four-link chain, why Steam is kept out, what each repair does, source layout |
| [Process](docs/process.md) | build and ship, how the diagnosis was done, the clean test before a second Mac, how to resume |
| [Logging](docs/logging.md) | which Steam and Bluetooth logs hold the truth and the lines that matter |
| [Build plan](.claude/output/20260905-1715-xenon-doctor-change/plan.md) | evidence, parity ledger, directives with checks |
| [The pin](.claude/output/20260905-1715-xenon-doctor-change/pin.md) | the four Steam keys and the one environment variable, how each was found |
| [Game runs](.claude/output/20260905-1715-xenon-doctor-change/A1-matrix.md) | every adverse case tried, with the verdict |
| [The freeze](.claude/output/20260905-1715-xenon-doctor-change/crash-20260905-1721.md) | the 17:21 display freeze, minute by minute |
| [Clean test](.claude/output/20260905-1715-xenon-doctor-change/clean-test.md) | the dress rehearsal protocol run before the second Mac |

## The two things to remember

Pad blinks, connects, then drops: hold Share and PS together until the light bar blinks fast, then let go.

Never use Steam's Stop button on a game. Quit the game from its own menu.

## Contributing

This is a household tool. Issues and pull requests are welcome if you have the same pads and the same problem.

## License

No license file yet. Ask before reusing.
