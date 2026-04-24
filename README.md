# Hammerspoon Configuration

A modular Hammerspoon configuration using a custom hyperkey (Caps Lock → F19) for application launching, window management, and custom keybindings.

## Features

- **Hyperkey Modal**: Caps Lock mapped to F19 acts as a pure modifier key — hold and press another key to trigger custom keybindings
- **Application Launcher**: Quick launch/focus apps with single keystrokes
- **Window Management**: Vim-style window focus navigation and Rectangle Pro integration
- **Special Functions**: Config reload, screenshots, voice mode toggle

## Prerequisites

- [Hammerspoon](https://www.hammerspoon.org/) installed
- [Karabiner-Elements](https://karabiner-elements.pqrs.org/) for remapping Caps Lock → F19
  - Open Karabiner-Elements
  - Go to **Simple Modifications** → **For all devices**
  - Map: `caps_lock` → `F19`

## File Structure

```
~/.hammerspoon/
├── init.lua                    # Main entry point, loads all modules
├── hyperkey.lua                # Core hyperkey modal logic and helper functions
├── keybinds_apps.lua           # Application launch/focus keybindings
├── keybind_finder.lua          # Custom Finder window handler
├── keybinds_window_mgmt.lua    # Window management and focus keybindings
└── keybinds_special.lua        # Special function keybindings
```

## Keybindings

### Application Launcher (Hyper + Key)

| Key | App | Shift+Key | App |
|-----|-----|-----------|-----|
| `1` | 1Password | | |
| `A` | Claude | `Shift+A` | Google Gemini |
| `B` | Safari | `Shift+B` | Firefox |
| `C` | Calendar | `Shift+C` | Visual Studio Code |
| `E` | Mail | `Shift+E` | Microsoft Excel |
| `F` | Finder | `Shift+F` | FileZilla |
| `N` | Bear | | |
| `O` | Obsidian | `Shift+O` | Protégé |
| `P` | Podcasts | `Shift+P` | Microsoft PowerPoint |
| `R` | Reminders | | |
| `S` | Slack | | |
| `T` | iTerm | `Shift+T` | Music |
| `W` | WhatsApp | `Shift+W` | Microsoft Word |
| `Z` | Zoom | `Shift+Z` | Zotero |

### Window Management

**Focus Navigation (Hyper + hjkl)**
- `Hyper+H` - Focus window to the left
- `Hyper+J` - Focus window below
- `Hyper+K` - Focus window above
- `Hyper+L` - Focus window to the right

**Rectangle Pro Integration (Hyper+Shift+Key)**

These keybindings forward to Rectangle Pro using `Ctrl+Alt+Cmd+Shift+Key`:
- `Hyper+Shift+]` - Window to right half
- `Hyper+Shift+[` - Window to left half
- `Hyper+Shift+H/J/K` - Window positioning (first fourth, center half, last fourth)
- `Hyper+Shift+Y/U/I` - Window positioning (top left, top half, top right) 
- `Hyper+Shift+N/M/,` - Window positioning (bottom left, bottom half, bottom right)
- `Hyper+Shift+Space` - Maximize

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

**`bindApp(mods, key, app)`**
- Binds `Hyper+mods+key` to launch or focus an application

**`bindSpecial(mods, key, targetMods, targetKey)`**
- Binds `Hyper+mods+key` to send a different keystroke
- Useful for forwarding to apps that don't recognize F19

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
