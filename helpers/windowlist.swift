// windowlist.swift — print "windowID<TAB>bundleID<TAB>appName" for every
// normal-layer window of every regular (Dock-visible) app, on every Mission
// Control Space. Used by space_taskbar.lua: the Accessibility API only sees
// the current Space, while CGWindowListCopyWindowInfo sees them all — and
// owner/ID/layer data needs no screen-recording permission (window *titles*
// would, so we never request them).
//
// Rebuild: swiftc -O -o helpers/windowlist helpers/windowlist.swift

import AppKit
import CoreGraphics
import Darwin

// Electron apps (Slack, Claude, …) hide their window on close instead of
// destroying it, and CGWindowList still reports it with normal bounds and
// alpha — kCGWindowIsOnscreen can't tell it apart from a visible window on
// an inactive Space. The window server's ordered-in flag can: hidden
// (ordered-out) windows read false, visible windows on any Space read true.
// SkyLight is private, so resolve it at runtime and fail open (treat every
// window as ordered in) if the symbols ever vanish.
typealias MainConnFn = @convention(c) () -> Int32
typealias OrderedInFn = @convention(c) (Int32, UInt32, UnsafeMutablePointer<Bool>) -> Int32

var connID: Int32 = 0
var orderedInFn: OrderedInFn? = nil
if let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
   let cidSym = dlsym(handle, "SLSMainConnectionID"),
   let ordSym = dlsym(handle, "SLSWindowIsOrderedIn") {
    connID = unsafeBitCast(cidSym, to: MainConnFn.self)()
    orderedInFn = unsafeBitCast(ordSym, to: OrderedInFn.self)
}

func isOrderedIn(_ windowID: Int) -> Bool {
    guard let fn = orderedInFn else { return true }
    var ordered = false
    guard fn(connID, UInt32(windowID), &ordered) == 0 else { return true }
    return ordered
}

guard let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}

var byPID: [Int: (bundle: String, name: String)?] = [:]

for info in list {
    guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
          let number = info[kCGWindowNumber as String] as? Int,
          let pid = info[kCGWindowOwnerPID as String] as? Int,
          let bounds = info[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double, width >= 100,
          let height = bounds["Height"] as? Double, height >= 50,
          isOrderedIn(number) else { continue }

    let entry: (bundle: String, name: String)?
    if let cached = byPID[pid] {
        entry = cached
    } else {
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)),
           app.activationPolicy == .regular,
           let bundle = app.bundleIdentifier {
            entry = (bundle, app.localizedName ?? bundle)
        } else {
            entry = nil
        }
        byPID[pid] = entry
    }
    if let entry {
        print("\(number)\t\(entry.bundle)\t\(entry.name)")
    }
}
