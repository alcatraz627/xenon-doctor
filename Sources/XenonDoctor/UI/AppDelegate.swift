import AppKit

/// Owns the menu bar item. `openOnLaunch` lets `--guide` and `--tester` bring a window up
/// straight away, which is how the windows get screenshotted without clicking the menu.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    var openOnLaunch: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Trace.log("didFinishLaunching openOnLaunch=\(openOnLaunch ?? "nil")")
        statusItem = StatusItemController()
        Trace.log("status item built")
        if let which = openOnLaunch { statusItem?.open(which) }
    }
}
