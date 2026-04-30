# Hammerspoon Configuration

A modular Hammerspoon configuration using a custom hyperkey (Caps Lock → F19) for application launching, window management, and custom keybindings.

## Features

- **Hyperkey Modal**: Caps Lock mapped to F19 acts as a pure modifier key — hold and press another key to trigger custom keybindings
- **Application Launcher**: Quick launch/focus apps with single keystrokes
- **Window Management**: Native tiling, vim-style focus navigation, and move-window-to-space
- **Space HUD**: Transient on-screen indicator of the current Mission Control space
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
└── space_hud.lua               # Transient HUD on Mission Control space change
```

## Keybindings

### Application Launcher (Hyper + Key)

| Key | App       | Shift+Key | App                  |
| --- | --------- | --------- | -------------------- |
| `1` | 1Password |           |                      |
| `A` | Claude    | `Shift+A` | Google Gemini        |
| `B` | Safari    | `Shift+B` | Firefox              |
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

Drags the focused window's titlebar to invoke macOS's ctrl+N space switch, sending the window to space N.

### Special Functions

- `Hyper+Shift+R` - Reload Hammerspoon config
- `Cmd+Shift+V` - Paste as plain text (preserves original clipboard)
- `F13` - Screenshot to clipboard (⌘⇧4)
- `F14` - Toggle Caps Lock (for Claude voice mode)

### Auto-Focus Behavior

When a window is closed, the next visible window is automatically focused (with a 0.1s delay to ensure window list updates).

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
