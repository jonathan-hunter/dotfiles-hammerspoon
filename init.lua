-- ~/.hammerspoon/init.lua
-- Version: 1.0
local hyperkey = require("hyperkey")  -- hyperkey logic

-- Make hyperkey components globally available for other modules
-- Note: These are intentionally global to allow keybind modules to use them without imports
f19 = hyperkey.modal
bindApp = hyperkey.bindApp
bindSpecial = hyperkey.bindSpecial

-- Load other keybind modules
require("keybinds_apps")          -- app keybinds
require("keybind_finder")         -- finder launch/focus logic and keybind
require("keybinds_window_mgmt")   -- window management keybinds
require("keybinds_special")       -- reload hammerspoon; screenshot; claude voice mode