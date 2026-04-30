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
- `hyperkey.lua` - Core modal logic. F19 acts as a pure modifier: modal is entered on key down, exited on key up. Exports `modal` and `bindApp()`.
- `keybinds_apps.lua` - Application launch/focus bindings using `bindApp()`
- `keybinds_window_mgmt.lua` - Native Hammerspoon tiling, vim-style window focus (hjkl), and shift+hyper+1..9 to move focused window to space N
- `keybinds_special.lua` - Config reload, paste as plain text, F13/F14 special keys
- `keybind_finder.lua` - Custom Finder handling with AppleScript (opens new window if none exist)
- `space_hud.lua` - Transient HUD that flashes the current Mission Control space index on space change

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
