import Foundation

/// One game the household plays with the pad, and how the pad reaches it. Three games,
/// three different input paths, and the row for each has to probe its own path or a
/// green row means nothing.
///
///   Stardew Valley  reads the pad through its bundled SDL, straight off the HID device.
///                   Anything in the login session that tells SDL to ignore the pad
///                   blinds it (that was the 0.3.2 bug).
///   Factorio        reads the pad through Apple's GameController framework, the same
///                   layer the button tester uses, but only when its config says so.
///   Undertale       cannot read a pad on a Mac at all (GameMaker). Xenon Doctor turns
///                   pad presses into key presses for it while it is the front window.
struct Game {
    enum Path { case sdl, gameController, keyMapper }

    let link: Link
    let title: String
    let bundleID: String
    let steamAppID: String
    let path: Path
    let relaunch: RepairKind
    let install: RepairKind

    static let stardew = Game(link: .game, title: "Stardew Valley", bundleID: "com.concernedape.stardewvalley",
                              steamAppID: "413150", path: .sdl, relaunch: .relaunchGame, install: .installGame)
    static let factorio = Game(link: .factorio, title: "Factorio", bundleID: "com.factorio",
                               steamAppID: "427520", path: .gameController, relaunch: .relaunchFactorio, install: .installFactorio)
    static let undertale = Game(link: .undertale, title: "Undertale", bundleID: "com.tobyfox.undertale",
                                steamAppID: "391540", path: .keyMapper, relaunch: .relaunchUndertale, install: .installUndertale)

    static let all = [stardew, factorio, undertale]

    static func forLink(_ link: Link) -> Game? { all.first { $0.link == link } }
    static func forRelaunch(_ kind: RepairKind) -> Game? { all.first { $0.relaunch == kind } }
    static func forInstall(_ kind: RepairKind) -> Game? { all.first { $0.install == kind } }
}
