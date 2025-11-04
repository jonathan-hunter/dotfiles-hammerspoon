--[[
~/.hammerspoon/hyperkey.lua

Map caps lock to F19 using Karabiner-Elements for hyper key functionality:
Karabiner-Elements > Simple Modifications > For all devices: caps_lock -> F19

F19 is used to avoid conflicts with use of modifer combinations such as Ctrl+Alt+Cmd.
]]

-- Configuration
local SPOTLIGHT_DELAY = 0.15

-- Fast keystroke function for better responsiveness
local function fastKeyStroke(modifiers, key)
  if not modifiers or not key then
    hs.logger.new('hyperkey'):e("Invalid keystroke parameters")
    return
  end
  local event = require("hs.eventtap").event
  event.newKeyEvent(modifiers, key, true):post()
  event.newKeyEvent(modifiers, key, false):post()
end

-- F19 modal setup
local f19 = hs.hotkey.modal.new()
local f19Tapped = false
local f19Timer = nil

-- Bind F19 with tap/hold detection
hs.hotkey.bind({}, 'F19',
  function() -- pressed
    f19Tapped = true
    -- Enter modal immediately for instant key combo response
    f19:enter()
    
    -- Stop existing timer if present
    if f19Timer then 
      f19Timer:stop()
    end
    
    -- Set a short timer to detect if this was a quick tap
    f19Timer = hs.timer.doAfter(SPOTLIGHT_DELAY, function()
      f19Tapped = false
    end)
  end,
  function() -- released
    -- Stop timer and clean up
    if f19Timer then
      f19Timer:stop()
      f19Timer = nil
    end
    
    if f19Tapped then
      -- Quick tap: trigger Spotlight and exit modal
      f19Tapped = false
      f19:exit()
      fastKeyStroke({'cmd'}, 'space')
    else
      -- Was held: just exit modal
      f19:exit()
    end
  end)

-- Bind Shift+F19 to enter the modal (useful for testing or forcing modal mode)
hs.hotkey.bind({'shift'}, 'F19', 
  function() f19:enter() end, 
  function() f19:exit() end
)

-- Define keybinding function - bind hyper+key to launch/focus app
local function bindApp(mods, key, app)
  f19:bind(mods, key, function()
    if app then
      hs.application.launchOrFocus(app)
    end
  end)
end

-- Define special keybinding function - bind hyper+key to send keystroke
local function bindSpecial(mods, key, targetMods, targetKey)
  f19:bind(mods, key, function()
    fastKeyStroke(targetMods, targetKey)
  end)
end

-- Export module
return {
  modal = f19,
  bindApp = bindApp,
  bindSpecial = bindSpecial
}