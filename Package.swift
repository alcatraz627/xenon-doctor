// swift-tools-version: 5.9
import PackageDescription

// Xenon Doctor: a menu bar app that keeps two Stratos Xenon gamepads working with
// Steam and Stardew Valley on macOS, and repairs the chain with one click.
//
// SPM builds a bare binary; build.sh wraps it into XenonDoctor.app with an
// Info.plist (LSUIElement keeps it out of the Dock) and ad-hoc signs it. No XCTest
// target: the machine has Command Line Tools only, so the regression net is the
// binary's own --self-test mode.
let package = Package(
    name: "XenonDoctor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "XenonDoctor", targets: ["XenonDoctor"]),
    ],
    targets: [
        .executableTarget(
            name: "XenonDoctor",
            path: "Sources/XenonDoctor",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("IOKit"),
                .linkedFramework("GameController"),
                .linkedFramework("SceneKit"),
                .linkedFramework("AppKit"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
