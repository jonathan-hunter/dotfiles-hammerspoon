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
          let height = bounds["Height"] as? Double, height >= 50 else { continue }

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
