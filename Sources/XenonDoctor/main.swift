import Foundation
import AppKit

// Xenon Doctor entry point. Three command modes for the terminal and tests, and the
// menu bar app when launched with no arguments.
//
//   XenonDoctor --status            print the four links
//   XenonDoctor --repair <kind>     run one repair: powerOnRadio reconnectPad restartSteam relaunchGame applyPin
//   XenonDoctor --self-test         exit 0 when the parser, pad lookup, and classifier pass
//   XenonDoctor --unpin             test reset: remove the Steam keys and the launch agent

let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "--status":
    let snap = Chain.standard().snapshot()
    print(snap.text)
    exit(snap.allOK ? 0 : 1)

case "--repair":
    guard args.count >= 2, let kind = RepairKind(rawValue: args[1]) else {
        print("usage: XenonDoctor --repair <\(RepairKind.allCases.map { $0.rawValue }.joined(separator: "|"))>")
        exit(2)
    }
    let state = Repairs.make(kind).run()
    print(ChainSnapshot(links: [state], takenAt: Date()).text)
    exit(state.ok ? 0 : 1)

case "--self-test":
    exit(SelfTest.run())

case "--unpin":
    // Test-only reset used by the clean-test protocol. Not in the menu.
    do {
        try Pin.unpin()
        print("unpinned: keys removed, agent unloaded, variable cleared. Missing now: \(Pin.check().joined(separator: ", "))")
        exit(0)
    } catch {
        print("unpin failed: \(error)")
        exit(1)
    }

case "--help", "-h":
    print("XenonDoctor [--status | --repair <kind> | --self-test]")
    exit(0)

default:
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    if args.first == "--guide" { delegate.openOnLaunch = "guide" }
    if args.first == "--tester" { delegate.openOnLaunch = "tester" }
    app.delegate = delegate
    app.run()
}
