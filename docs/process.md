# Process: how this was built and tested, and how to resume

## Build and ship

```
./build.sh              compile and assemble XenonDoctor.app (ad-hoc signed)
./release.sh            build and zip; the zip is what goes to the other Mac
tools/makeicon.sh       regenerate Resources/AppIcon.icns
.build/release/XenonDoctor --self-test
```

The machine has Command Line Tools only, no Xcode, so there is no XCTest target. `--self-test` is the regression net and must pass before a release.

On the receiving Mac: unzip, drag to Applications, right-click, Open, Open once. The app is ad-hoc signed and not notarized.

Publishing, once the owner has looked at the build:

```
gh release create vX.Y.Z XenonDoctor-X.Y.Z.zip --title "Xenon Doctor X.Y.Z" --notes "..."
```

The tag must be `v` plus the version in `Resources/Info.plist`, and the zip must be the one asset ending in `.zip`, because installed copies poll `releases/latest` and pick that asset. A Mac that already runs the app updates itself from the menu; only the very first install needs the zip by hand.

## How the diagnosis was done

Everything was measured on the MacBook Pro on 2026-09-05 before any code was written. The record lives under `.claude/output/20260905-1715-xenon-doctor-change/`:

| File | What it holds |
|---|---|
| `plan.md` | the build plan: what was wrong with evidence, the parity ledger, directives with checks |
| `A1-matrix.md` | every game run, adverse case by adverse case, with the owner's verdict |
| `crash-20260905-1721.md` | the freeze, minute by minute, from the unified log |
| `pin.md` | the exact Steam keys and the environment variable, how each was found, what each does and does not do |
| `clean-test.md` | the dress rehearsal protocol run before the second Mac |
| `evidence/` | screenshots and log extracts cited above |

## The clean test

Before the app goes to a second Mac it is run on the first one as if it were new: pad forgotten, Steam keys removed, agent removed, app installed from the zip. Then a person who has not seen it brings the chain up using only the app and its guide. `clean-test.md` has the steps, checks, and evidence names. `XenonDoctor --unpin` is the reset for the Steam half.

## Resuming this work with Claude Code

The session checkpoint is `_checkpoint.claude.md` in the project root (a symlink to the dated dump). `/catchup` reads it. The task list lives in store `session-68bce29b` and renders with `/tasks`. Project memory carries the pad identities, the pin, and the owner's rule that the deliverable is a fix, not more diagnostics.

## Things learned that are easy to lose

- Steam answers a Quit event with "cancel" and then exits on its own 20 to 40 seconds later. A repair that waits less than that thinks it failed.
- `open --env` on this macOS forwards the caller's whole environment to the launched app, not just the variable given. Launch Steam from a clean environment.
- Steam writes `localconfig.vdf` when it quits. Editing it while Steam runs is overwritten.
- `/private/tmp` is emptied on reboot. Evidence goes in the project, not the scratch folder.
- The pad reports battery 0 when it has no reading. Zero means unknown, not empty.
