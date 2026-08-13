# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Hammerspoon configuration for macOS automation. It implements a hyperkey system where Caps Lock (mapped to F19 via Karabiner-Elements) provides modal keybindings for app launching, window management, and special functions.

## Testing Changes

Reload the Hammerspoon config after making changes:
- Use `Hyper+Shift+R` (if config is currently working)
- Or click the Hammerspoon menu bar icon → Reload Config
- Or run in Hammerspoon console: `hs.reload()`

View the Hammerspoon console for errors: menu bar icon → Console

## Architecture

**Module loading pattern:** `init.lua` loads `hyperkey.lua` first, then exposes two globals (`f19`, `bindApp`) that all other keybind modules use directly without imports.

**File responsibilities:**
- `hyperkey.lua` - Core modal logic. F19 acts as a pure modifier: modal is entered on key down, exited on key up. Exports `modal` and `bindApp()`. When the bound app is already frontmost, `bindApp()` cycles through its windows on the current Space instead of re-launching.
- `keybinds_apps.lua` - Application launch/focus bindings using `bindApp()`
- `keybinds_window_mgmt.lua` - Native Hammerspoon tiling, hyper+opt+1..4 one-shot layouts (monocle / two columns / 1:3:1 / 2x2) for all windows on the current Space, vim-style window focus (hjkl), and shift+hyper+1..9 to move focused window to space N
- `keybinds_special.lua` - Config reload, paste as plain text, F13/F14 special keys, Hyper+Shift+Opt+Q quit-all-apps Shortcut
- `keybinds_caffeine.lua` - Hyper+Opt+C toggles a `caffeinate -s` child process, shown as a highlighted coffee cup menu bar item while active (`assets/coffee-active.png`: an SF Symbol knocked out of a filled blue pill, so the cup is a transparent hole that picks up the menu bar behind it). It is a **colour** image, so it must be set with `template=false` — `setIcon()` defaults to `true`, which would flatten the blue to a monochrome tint. Falls back to a ☕ title if the asset is missing. The task's exit callback is the only place that clears state, so an externally killed process still deactivates the indicator. Owns `hs.shutdownCallback` to avoid leaking the child across a reload. The menu bar item is created and deleted per toggle rather than parked with `removeFromMenuBar()` — detaching destroys the status item, and a title set while detached is silently lost, leaving a titleless item that still occupies the bar (an invisible indicator, not a missing one)
- `keybind_finder.lua` - Custom Finder handling with AppleScript (opens new window if none exist)
- `space_state.lua` - Shared cached Space IDs for consistent Desktop/HUD numbering
- `space_hud.lua` - Transient HUD for the current Mission Control space index; feeds current-Space updates to the taskbar
- `space_taskbar.lua` - Menu bar taskbar: app icons grouped by Desktop with the current Space highlighted. No dropdown — clicks act directly, hit-tested against the rendered strip: an app icon switches to that Desktop and focuses that app's window there, the Desktop number (or the `+n` overflow) just switches Space
- `helpers/coffee-icon.swift` - Dev-time only, never invoked at runtime. Renders an SF Symbol to a template PNG, because `hs.image.imageFromName` goes through `NSImage(named:)` and cannot resolve symbol names. Regenerate with `swift helpers/coffee-icon.swift cup.and.saucer.fill 0.00 0.48 1.00 2 assets/coffee-active.png` (args: symbol, r, g, b, scale, output)
- `helpers/windowlist.swift` - CGWindowList helper that reports windows on all Spaces (AX only sees the current one); skips ordered-out windows via SkyLight's `SLSWindowIsOrderedIn` so closed-to-background Electron windows (Slack/Claude hide on close, never destroy) don't appear; auto-compiled by `space_taskbar.lua` if the binary is missing — **recompile manually after editing** (`swiftc -O -o helpers/windowlist helpers/windowlist.swift`), auto-compile only fires when the binary is absent

## Adding Keybindings

**App launcher:** In `keybinds_apps.lua`:
```lua
bindApp({}, 'X', "App Name")           -- Hyper+X
bindApp({'shift'}, 'X', "Other App")   -- Hyper+Shift+X
```

**Custom function:** Bind directly to `f19` modal:
```lua
f19:bind({}, 'key', function()
  -- custom code
end)
```

## Key Constants

- `WINDOW_FOCUS_DELAY` in `keybinds_window_mgmt.lua` (0.1s) - delay after window close before auto-focus
- `NAVIGATION_REFRESH_DELAY` in `keybinds_window_mgmt.lua` (0.12s) - coalesces window-list updates
- `NAVIGATION_SPACE_REFRESH_DELAY` in `keybinds_window_mgmt.lua` (0.20s) - rebuilds navigation candidates after a Space transition
- `SPACE_FOCUS_DELAY` in `space_taskbar.lua` (0.30s) - lets a taskbar-click Space switch settle before AX focuses the clicked app (mirrors `CYCLE_SPACE_FOCUS_DELAY` in `hyperkey.lua`)
