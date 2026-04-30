--[[
~/.hammerspoon/hyperkey.lua

Map caps lock to F19 using Karabiner-Elements for hyper key functionality:
Karabiner-Elements > Simple Modifications > For all devices: caps_lock -> F19

F19 is used to avoid conflicts with use of modifer combinations such as Ctrl+Alt+Cmd.
]]

-- F19 modal setup
local f19 = hs.hotkey.modal.new()
f19.isActive = false  -- tracks whether F19 is currently held

-- F19 acts as a pure modifier: modal is active while held, inactive when released
hs.hotkey.bind({}, 'F19',
  function() -- pressed
    f19.isActive = true
    f19:enter()
  end,
  function() -- released
    f19.isActive = false
    f19:exit()
  end)

-- Bind Shift+F19 to enter the modal (useful for testing or forcing modal mode)
hs.hotkey.bind({'shift'}, 'F19',
  function() f19:enter() end,
  function() f19:exit() end
)

-- Define keybinding function - bind hyper+key to launch/focus app
local function bindApp(mods, key, app)
  f19:bind(mods, key, function()
    hs.application.launchOrFocus(app)
  end)
end

-- Export module
return {
  modal = f19,
  bindApp = bindApp,
}
