import Foundation
import AppKit

// Xenon Doctor entry point. Three command modes for the terminal and tests, and the
// menu bar app when launched with no arguments.
//
//   XenonDoctor --status            print every row
//   XenonDoctor --repair <kind>     run one repair, then print the whole chain again
//   XenonDoctor --self-test         exit 0 when the parser, pad lookup, and classifier pass
//   XenonDoctor --unpin             test reset: remove the Steam keys and the launch agent

let args = Array(CommandLine.arguments.dropFirst())

/// Runs work on a background thread while the main run loop turns, and returns its result.
func offMain<T>(_ work: @escaping () -> T) -> T {
    PadProbe.prepare()
    var out: T?
    DispatchQueue.global(qos: .userInitiated).async { out = work() }
    while out == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    return out!
}

switch args.first {
case "--status":
    // GameController and the HID listener deliver on the main run loop, so the chain
    // runs on another thread while this one keeps the loop turning, as the app does.
    let snap = offMain { Chain.standard().snapshot() }
    print(snap.text)
    exit(snap.allOK ? 0 : 1)

case "--repair":
    guard args.count >= 2, let kind = RepairKind(rawValue: args[1]) else {
        print("usage: XenonDoctor --repair <\(RepairKind.allCases.map { $0.rawValue }.joined(separator: "|"))>")
        exit(2)
    }
    // The repair's own report first, then the whole chain read again: the exit code
    // is the chain's, because a repair is judged by what it left behind.
    let (state, chain) = offMain { Repairs.runAndReread(kind) }
    print("repair: " + ChainSnapshot(links: [state], takenAt: Date()).text)
    print("chain after:")
    print(chain.text)
    exit(chain.allOK ? 0 : 1)

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

case "--check-update":
    // Prints the latest GitHub release against this build's version.
    let u = Updater()
    var done = false
    u.check(force: true) { state in
        switch state {
        case .available(let r): print("update available: \(r.tag) at \(r.zipURL) (running \(Updater.currentVersion))")
        case .upToDate: print("up to date: \(Updater.currentVersion)")
        case .failed(let why): print("check failed: \(why)")
        default: print("state: \(state)")
        }
        done = true
    }
    while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    exit(0)

case "--update":
    // Installs the latest release over the running bundle (or /Applications when run from
    // the build folder). `--update --force` reinstalls even when the version matches; that is
    // how the swap gets exercised without publishing a release first.
    let force = args.contains("--force")
    let u = Updater()
    var done = false
    var code: Int32 = 0
    u.check(force: true) { state in
        var rel: Updater.Release?
        if case .available(let r) = state { rel = r }
        if rel == nil, force, let data = try? Data(contentsOf: URL(string: "https://api.github.com/repos/\(Updater.repo)/releases/latest")!) {
            rel = Updater.parse(data)
        }
        guard let r = rel else {
            print(state == .upToDate ? "up to date: \(Updater.currentVersion); use --force to reinstall" : "no release: \(state)")
            done = true
            return
        }
        u.install(r) { result in
            switch result {
            case .success(let target): print("installed \(r.tag) at \(target.path)")
            case .failure(let e): print("update failed: \(e)"); code = 1
            }
            done = true
        }
    }
    while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    exit(code)

case "--pads":
    print(Pads.describe())
    exit(0)

case "--add-pad":
    // XenonDoctor --add-pad MARK MAC ["whose pad"]
    guard args.count >= 3 else { print("usage: XenonDoctor --add-pad MARK D0:27:96:xx:xx:xx [\"note\"]"); exit(2) }
    do {
        try Pads.add(mark: args[1], mac: args[2], note: args.count > 3 ? args[3] : nil)
        print(Pads.describe())
        exit(0)
    } catch {
        print("could not add: \(error)")
        exit(1)
    }

case "--remove-pad":
    guard args.count >= 2 else { print("usage: XenonDoctor --remove-pad MARK"); exit(2) }
    do {
        try Pads.remove(mark: args[1])
        print(Pads.describe())
        exit(0)
    } catch {
        print("could not remove: \(error)")
        exit(1)
    }

case "--help", "-h":
    print("XenonDoctor [--status | --repair <kind> | --self-test | --pads | --add-pad MARK MAC [note] | --remove-pad MARK | --check-update | --update [--force] | --window | --guide | --tester]")
    exit(0)

default:
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    // Screenshot aids: force one appearance so both themes can be checked without
    // flipping the whole Mac. Not shown in --help.
    if args.contains("--light") { app.appearance = NSAppearance(named: .aqua) }
    if args.contains("--dark") { app.appearance = NSAppearance(named: .darkAqua) }
    let delegate = AppDelegate()
    if args.first == "--guide" { delegate.openOnLaunch = "guide" }
    if args.first == "--tester" { delegate.openOnLaunch = "tester" }
    if args.first == "--window" { delegate.openOnLaunch = "status" }
    if args.first == "--menu" { delegate.openOnLaunch = "menu" }
    // --frame WxH sizes the window on launch, for checking layouts at other sizes.
    if let i = args.firstIndex(of: "--frame"), i + 1 < args.count {
        let parts = args[i + 1].split(separator: "x").compactMap { Double($0) }
        if parts.count == 2 { delegate.frameOnLaunch = NSSize(width: parts[0], height: parts[1]) }
    }
    app.delegate = delegate
    app.run()
}
