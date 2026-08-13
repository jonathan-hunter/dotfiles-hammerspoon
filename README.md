# Hammerspoon Configuration

A modular Hammerspoon configuration using a custom hyperkey (Caps Lock → F19) for application launching, window management, and custom keybindings.

## Features

- **Hyperkey Modal**: Caps Lock mapped to F19 acts as a pure modifier key — hold and press another key to trigger custom keybindings
- **Application Launcher**: Quick launch/focus apps with single keystrokes; pressing again while the app is frontmost cycles through its windows
- **Window Management**: Native tiling, vim-style focus navigation, and move-window-to-space
- **Space Taskbar**: Menu bar strip of app icons grouped by Desktop number, with the current Space highlighted, a click-to-jump dropdown, and a transient on-screen HUD when switching spaces
- **Special Functions**: Config reload, screenshots, voice mode toggle

## Prerequisites

- [Hammerspoon](https://www.hammerspoon.org/) installed
- [Karabiner-Elements](https://karabiner-elements.pqrs.org/) for remapping Caps Lock → F19
  - Open Karabiner-Elements
  - Go to **Simple Modifications** → **For all devices**
  - Map: `caps_lock` → `F19`

## File Structure

```text
~/.hammerspoon/
├── init.lua                    # Main entry point, loads all modules
├── hyperkey.lua                # Core hyperkey modal logic and helper functions
├── keybinds_apps.lua           # Application launch/focus keybindings
├── keybind_finder.lua          # Custom Finder window handler
├── keybinds_window_mgmt.lua    # Tiling, focus navigation, move-to-space
├── keybinds_special.lua        # Special function keybindings
├── space_state.lua             # Shared cached Mission Control Space IDs
├── space_hud.lua               # Transient Space HUD; feeds the taskbar current-Space updates
├── space_taskbar.lua           # Menu bar taskbar: app icons grouped by Space
└── helpers/windowlist.swift    # CGWindowList helper (sees windows on all Spaces)
```

## Keybindings

### Application Launcher (Hyper + Key)

Pressing a key launches or focuses the app. Pressing it again while that app is already frontmost cycles through the app's windows on the current Space (minimized windows are skipped, like cmd+backtick).

| Key | App       | Shift+Key | App                  |
| --- | --------- | --------- | -------------------- |
| `1` | 1Password |           |                      |
| `A` | Claude    | `Shift+A` | Google Gemini        |
| `B` | Brave     | `Shift+B` | Safari               |
| `C` | Calendar  | `Shift+C` | Visual Studio Code   |
| `E` | Mail      | `Shift+E` | Microsoft Excel      |
| `F` | Finder    | `Shift+F` | FileZilla            |
| `N` | Bear      |           |                      |
| `O` | Obsidian  | `Shift+O` | Protégé              |
| `P` | Podcasts  | `Shift+P` | Microsoft PowerPoint |
| `R` | Reminders |           |                      |
| `S` | Slack     |           |                      |
| `T` | iTerm     | `Shift+T` | Music                |
| `W` | WhatsApp  | `Shift+W` | Microsoft Word       |
| `Z` | Zoom      | `Shift+Z` | Zotero               |

### Window Management

#### Focus Navigation (Hyper + hjkl)

- `Hyper+H` - Focus window to the left
- `Hyper+J` - Focus window below
- `Hyper+K` - Focus window above
- `Hyper+L` - Focus window to the right

#### Tiling (Hyper+Shift+Key)

Native Hammerspoon tiling — sets the focused window's frame to a fraction of the screen:

- `Hyper+Shift+]` / `[` - Right half / left half
- `Hyper+Shift+G/H` - Left three-quarters / left quarter (full height)
- `Hyper+Shift+J/K/L` - Center half / third quarter / right quarter (full height)
- `Hyper+Shift+Y/U/I` - Top left quarter / top half / top right quarter
- `Hyper+Shift+N/M/,` - Bottom left quarter / bottom half / bottom right quarter
- `Hyper+Shift+Space` - Full screen

#### Move Window to Space (Hyper+Shift+1..9)

Drags the focused window's titlebar while invoking macOS's ctrl+N shortcut, sending the window to Desktop N and following it. The drag uses non-blocking timers so Hammerspoon remains responsive throughout the switch.

### Special Functions

- `Hyper+Shift+R` - Reload Hammerspoon config
- `Hyper+Opt+C` - Toggle `caffeinate -s` (keep the system awake). A highlighted coffee cup appears in the menu bar while it is active — the cup is knocked out of a filled blue pill, so it reads as "on" at a glance; clicking it also switches it off. The child process is terminated on config reload and on quit. Note that `-s` is only honoured on AC power — on battery the assertion is held but has no effect.
- `Cmd+Shift+V` - Paste as plain text (preserves original clipboard)
- `F13` - Screenshot to clipboard (⌘⇧4)
- `F14` - Toggle Caps Lock (for Claude voice mode)

### Auto-Focus Behavior

When a window is closed and macOS has not selected a replacement, the next visible window is focused after a 0.1s delay. Directional navigation reuses a cached current-Space window list rather than querying every application on every keypress.

### Mission Control Settings

For numbered Space caching and consistent ctrl+N destinations:

- Enable **Displays have separate Spaces**.
- Disable **Automatically rearrange Spaces based on most recent use**.
- Enabling **Reduce motion** is recommended for faster visual transitions.

### Space Taskbar

The menu bar shows each numbered Desktop with the icons of the apps on it (capped at 4 per Space, `+n` for overflow), highlighting the current Space. Clicking it opens a dropdown listing every Desktop and its apps — select one to jump there via ctrl+N.

Window-to-app mapping for Spaces you haven't visited comes from `helpers/windowlist`, a small Swift binary using `CGWindowListCopyWindowInfo` (the Accessibility API only sees the current Space). It is compiled automatically from `helpers/windowlist.swift` on config load if missing, and runs asynchronously — placement lookups and re-renders happen only on debounced window events, never during a Space transition.

## Configuration

### Adjusting Window Focus Delay

Edit `keybinds_window_mgmt.lua`:

```lua
local WINDOW_FOCUS_DELAY = 0.1  -- Delay after window close (seconds)
```

## How It Works

### Hyperkey Modal

The hyperkey system uses Hammerspoon's modal hotkey functionality:

1. Pressing F19 enters the modal — bindings become active
2. Releasing F19 exits the modal — bindings become inactive

### Helper Functions

`bindApp(mods, key, app)` — binds `Hyper+mods+key` to launch or focus an application.

## Customization

### Adding New App Keybindings

Edit `keybinds_apps.lua`:

```lua
bindApp({}, 'X', "Your App Name")
bindApp({'shift'}, 'X', "Another App")
```

### Adding Custom Window Management

Edit `keybinds_window_mgmt.lua`:

```lua
f19:bind({}, "key", function()
  -- Your custom window management code
end)
```

## Version

Current version: 1.0

## License

MIT
