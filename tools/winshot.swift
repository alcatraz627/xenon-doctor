import Foundation
import CoreGraphics

// Lists or captures the on-screen windows of one app by owner name, without System
// Events, which cannot see the windows of a menu bar (LSUIElement) app.
//
//   winshot list <OwnerName>
//   winshot shoot <OwnerName> <out.png>      captures the frontmost window of that owner

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
    print("usage: winshot list <owner> | winshot shoot <owner> <out.png>")
    exit(2)
}
let owner = args[1]
// `all` lists windows on every Space, including hidden and off-screen ones.
let options: CGWindowListOption = args[0] == "all" ? [.optionAll] : [.optionOnScreenOnly, .excludeDesktopElements]
guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    print("no window list")
    exit(1)
}
// Owner `*` matches every app, for finding out what name a window is filed under.
let mine = list.filter { (owner == "*" || ($0[kCGWindowOwnerName as String] as? String) == owner) && (args[0] == "all" || ($0[kCGWindowLayer as String] as? Int) == 0) }
if args[0] == "list" || args[0] == "all" {
    for w in mine {
        let id = w[kCGWindowNumber as String] as? Int ?? 0
        let name = w[kCGWindowName as String] as? String ?? ""
        let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let who = w[kCGWindowOwnerName as String] as? String ?? ""
        let pid = w[kCGWindowOwnerPID as String] as? Int ?? 0
        print("\(id)\t\(who) [\(pid)]\t\(name)\t\(b["X"] ?? 0) \(b["Y"] ?? 0) \(b["Width"] ?? 0) \(b["Height"] ?? 0)")
    }
    if mine.isEmpty { print("no windows for \(owner)"); exit(1) }
    exit(0)
}
guard args.count >= 3, let first = mine.first, let id = first[kCGWindowNumber as String] as? Int else {
    print("no window to capture for \(owner)")
    exit(1)
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
p.arguments = ["-x", "-o", "-l", "\(id)", args[2]]
try? p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? args[2] : "screencapture failed")
exit(p.terminationStatus)
