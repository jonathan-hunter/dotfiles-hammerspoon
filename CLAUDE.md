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

**Module loading pattern:** `init.lua` loads `hyperkey.lua` first, then exposes three globals (`f19`, `bindApp`, `bindSpecial`) that all other keybind modules use directly without imports.

**File responsibilities:**
- `hyperkey.lua` - Core modal logic with tap/hold detection. Tap triggers Spotlight, hold enables keybindings. Exports `modal`, `bindApp()`, and `bindSpecial()`.
- `keybinds_apps.lua` - Application launch/focus bindings using `bindApp()`
- `keybinds_window_mgmt.lua` - Vim-style window focus (hjkl) and Rectangle Pro integration via `bindSpecial()`
- `keybinds_special.lua` - Config reload, paste as plain text, F13/F14 special keys
- `keybind_finder.lua` - Custom Finder handling with AppleScript (opens new window if none exist)

## Adding Keybindings

**App launcher:** In `keybinds_apps.lua`:
```lua
bindApp({}, 'X', "App Name")           -- Hyper+X
bindApp({'shift'}, 'X', "Other App")   -- Hyper+Shift+X
```

**Keystroke forwarding:** In `keybinds_window_mgmt.lua` (for apps that don't recognize F19):
```lua
bindSpecial({'shift'}, 'key', {'ctrl', 'alt', 'cmd'}, 'key')
```

**Custom function:** Bind directly to `f19` modal:
```lua
f19:bind({}, 'key', function()
  -- custom code
end)
```

## Key Constants

- `SPOTLIGHT_DELAY` in `hyperkey.lua` (0.15s) - tap detection threshold
- `WINDOW_FOCUS_DELAY` in `keybinds_window_mgmt.lua` (0.1s) - delay after window close before auto-focus
