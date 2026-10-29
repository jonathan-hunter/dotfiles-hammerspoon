# Hammerspoon Configuration

A modular Hammerspoon configuration built around a hyperkey (Caps Lock → F19) for app launching, window management, and a few menu bar utilities.

## Features

- **Hyperkey Modal**: Caps Lock mapped to F19 acts as a pure modifier — hold it and press another key. Double-tap it to toggle the real Caps Lock.
- **Application Launcher**: Launch or focus apps with one keystroke; pressing again while the app is frontmost cycles through its windows
- **Window Management**: Native tiling, one-shot multi-window layouts, vim-style focus navigation, and move-window-to-Space
- **Space Taskbar**: Menu bar strip of app icons grouped by Desktop on every display; click or hover to jump
- **Focus Follows Mouse**: Focuses the window the pointer settles in, without stealing focus while sweeping across windows
- **Menu Bar Utilities**: Caffeinate toggle, Claude plan usage
- **Mail Junk**: Keeps Mail's junk folders marked as read

## Prerequisites

- [Hammerspoon](https://www.hammerspoon.org/), with Accessibility permission
- [Karabiner-Elements](https://karabiner-elements.pqrs.org/) to remap Caps Lock → F19
  - **Simple Modifications** → **For all devices** → `caps_lock` → `f19`
- Xcode Command Line Tools (`xcode-select --install`), so `helpers/windowlist.swift` can be compiled on first load

### Mission Control Settings

For consistent Desktop numbering and ctrl+N destinations:

- Enable **Displays have separate Spaces**.
- Disable **Automatically rearrange Spaces based on most recent use**.
- In **Keyboard Shortcuts → Mission Control**, enable **Switch to Desktop 1–9** (ctrl+1..9) and assign ctrl+0 to Desktop 10.
- Enabling **Reduce motion** is recommended for faster transitions.

## File Structure

```text
~/.hammerspoon/
├── init.lua                     # Entry point: loads modules, defines notify()
├── hyperkey.lua                 # Hyperkey modal, bindApp(), caps lock double tap
├── keybinds_apps.lua            # App launch/focus bindings
├── keybind_finder.lua           # Finder handler (opens a window if none exist)
├── keybinds_window_mgmt.lua     # Tiling, layouts, focus navigation, move-to-Space
├── keybinds_special.lua         # Reload, plain-text paste, F13/F14, Shortcuts, Karabiner restart
├── keybinds_caffeine.lua        # caffeinate toggle + menu bar coffee cup
├── focus_follows_mouse.lua      # Focus the window under a settled pointer
├── claude_usage.lua             # Menu bar Claude plan usage
├── mail_junk.lua                # Mark Mail junk folders as read
├── space_state.lua              # Shared cached Space IDs
├── space_hud.lua                # Watches Space changes, feeds the taskbar
├── space_taskbar.lua            # Menu bar taskbar: app icons grouped by Desktop
├── assets/                      # Menu bar images
└── helpers/
    ├── windowlist.swift         # CGWindowList helper (sees windows on all Spaces)
    ├── mark_junk_read.applescript
    └── coffee-icon.swift        # Dev-time only: renders the coffee cup asset
```

## Keybindings

`Hyper` = hold Caps Lock.

### Application Launcher

Pressing a key launches or focuses the app. Pressing it again while that app is frontmost cycles through its windows on the current Space (minimized windows are skipped, like cmd+backtick).

| Key | Hyper+Key | Hyper+Shift+Key      | Hyper+Opt+Key |
| --- | --------- | -------------------- | ------------- |
| `1` | 1Password |                      |               |
| `A` | Claude    | Google Gemini        |               |
| `B` | Firefox   | Brave Browser        | Brain.fm      |
| `C` | Calendar  | Visual Studio Code   |               |
| `E` | Mail      | Microsoft Excel      |               |
| `F` | Finder    | FileZilla            |               |
| `N` | Bear      |                      | NetNewsWire   |
| `O` |           | Protégé              |               |
| `P` | Podcasts  | Microsoft PowerPoint |               |
| `R` | Reminders |                      |               |
| `S` | Slack     | Shortcuts            |               |
| `T` | Ghostty   | Music                | Tailscale     |
| `W` | WhatsApp  | Microsoft Word       |               |
| `Z` | Zotero    | Zoom                 |               |

### Window Management

#### Focus Navigation

- `Hyper+H/J/K/L` - Focus the window to the left / below / above / right

#### Tiling (focused window)

- `Hyper+Shift+]` / `[` - Right half / left half
- `Hyper+Shift+G/H` - Left three-quarters / left quarter (full height)
- `Hyper+Shift+J/K/L` - Center half / third quarter / right quarter (full height)
- `Hyper+Shift+Y/U/I` - Top left quarter / top half / top right quarter
- `Hyper+Shift+N/M/,` - Bottom left quarter / bottom half / bottom right quarter
- `Hyper+Shift+Space` - Full screen

#### Layouts (all windows on the screen)

The focused window takes the first slot; extra windows wrap around the pattern.

- `Hyper+Opt+1` - Monocle
- `Hyper+Opt+2` - Two columns
- `Hyper+Opt+3` - 1:3:1 columns, focused window in the centre
- `Hyper+Opt+4` - 2x2 grid
- `Hyper+Shift+Opt+1..5` - N equal columns

#### Move Window to Space

- `Hyper+Shift+1..9,0` - Send the focused window to Desktop 1–10 and follow it

Drags the window's titlebar while invoking ctrl+N, using non-blocking timers so Hammerspoon stays responsive.

### Other

- `Hyper+Opt+R` - Reload config
- `Hyper+Opt+C` - Toggle `caffeinate -s` (see below)
- `Hyper+Opt+F` - Toggle focus follows mouse (on by default)
- `Hyper+Shift+Opt+Q` - Run the **Quit All Apps** Shortcut (create one with that name in Shortcuts.app)
- `Hyper+Shift+Opt+K` - Restart Karabiner-Elements' user agents (no sudo)
- Double-tap `Hyper` - Toggle Caps Lock, with a notification since the LED won't light
- `Cmd+Shift+V` - Paste as plain text (preserves the original clipboard)
- `Cmd+Shift+Return` - Open a new line above the caret
- `F13` - Screenshot a selection to the clipboard (⌘⇧4)
- `F14` - Toggle Caps Lock

## Modules

### Space Taskbar

The menu bar on each display shows that display's Desktops with the icons of the apps on them (up to 4 per Desktop, `+n` for overflow), highlighting the visible Space. Clicking an app icon switches to that Desktop and focuses the app's window there; clicking a Desktop number just switches. Hovering an icon (with focus follows mouse on) does the same as clicking it. The taskbar hides on full-screen Spaces and in Mission Control.

The Accessibility API only sees the current Space, so window placement on other Spaces comes from `helpers/windowlist`, a small Swift binary using `CGWindowListCopyWindowInfo`. It's compiled automatically on config load if the binary is missing — recompile by hand after editing the source:

```sh
swiftc -O -o helpers/windowlist helpers/windowlist.swift
```

### Focus Follows Mouse

Raises and focuses the window the pointer comes to rest in. Fast sweeps across windows don't change focus. It ignores the menu bar, Dock, panels, open context menus, held mouse buttons, and moments when the hyperkey is held.

### Caffeine

`Hyper+Opt+C` runs `caffeinate -s` and shows a highlighted coffee cup in the menu bar; clicking the cup also switches it off. The child process is terminated on reload and quit. `-s` is only honoured on AC power.

### Claude Usage

Shows Claude plan usage (`5h% · 7d%`) in the menu bar, polled every 5 minutes; clicking it focuses the Claude app. It reads the OAuth token that [Claude Code](https://claude.com/claude-code) stores in the Keychain, so Claude Code must be installed and signed in. The endpoint is undocumented and may change. Remove `require("claude_usage")` from `init.lua` if you don't want it.

### Mail Junk

Every 5 minutes while Mail is running, and whenever Mail is focused, marks every account's junk folder (`Junk`, `Junk Email` or `[Gmail]/Spam`) as read. To mark other mailboxes read too, create `helpers/mail_extra_mailboxes.txt` (gitignored) with one `Account/Mailbox` per line:

```text
# Account name as shown in Mail / mailbox path
Work/Notifications
```

## Customization

### Adding App Keybindings

In `keybinds_apps.lua`:

```lua
bindApp({}, 'X', "Your App Name")        -- Hyper+X
bindApp({'shift'}, 'X', "Another App")   -- Hyper+Shift+X
```

### Adding Custom Bindings

Bind directly to the `f19` modal:

```lua
f19:bind({}, "key", function()
  -- your code
end)
```

Modules show status with the global `notify(message)`, which posts a macOS notification that is withdrawn after a few seconds.

## License

MIT
