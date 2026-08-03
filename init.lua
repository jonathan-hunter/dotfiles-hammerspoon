-- ~/.hammerspoon/init.lua
-- Version: 1.0
require("hs.ipc")  -- IPC port for the `hs` command-line tool

local hyperkey = require("hyperkey")  -- hyperkey logic

-- Make hyperkey components globally available for other modules
-- Note: These are intentionally global to allow keybind modules to use them without imports
f19 = hyperkey.modal
bindApp = hyperkey.bindApp

-- Load other keybind modules
require("keybinds_apps")          -- app keybinds
require("keybind_finder")         -- finder launch/focus logic and keybind
require("keybinds_window_mgmt")   -- window management: tiling, focus nav, move-to-space
require("keybinds_special")       -- reload hammerspoon; screenshot; claude voice mode
require("space_hud")              -- space HUD + menu bar taskbar (via space_taskbar)
