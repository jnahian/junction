import AppKit
import CoreGraphics
// helper windows <pid>          → "id x y w h layer name" per on-screen window
// helper geturl <pid> <url>     → send kAEGetURL to that process only
let a = CommandLine.arguments
let pid = pid_t(a[2])!
switch a[1] {
case "windows":
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
    for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == pid {
        let b = w[kCGWindowBounds as String] as! [String: CGFloat]
        print(w[kCGWindowNumber as String]!, Int(b["X"]!), Int(b["Y"]!), Int(b["Width"]!), Int(b["Height"]!), w[kCGWindowLayer as String]!, w[kCGWindowName as String] ?? "")
    }
case "geturl":
    let target = NSAppleEventDescriptor(processIdentifier: pid)
    let ev = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL), targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    ev.setParam(NSAppleEventDescriptor(string: a[3]), forKeyword: keyDirectObject)
    _ = try? ev.sendEvent(options: [.noReply], timeout: 5)
default: break
}
