--[[
~/.hammerspoon/hyperkey.lua

Map caps lock to F19 using Karabiner-Elements for hyper key functionality:
Karabiner-Elements > Simple Modifications > For all devices: caps_lock -> F19

F19 is used to avoid conflicts with use of modifer combinations such as Ctrl+Alt+Cmd.
]]

-- F19 modal setup
local f19 = hs.hotkey.modal.new()
f19.isActive = false  -- tracks whether the hyper modal is currently active

-- Recovery watchdog ---------------------------------------------------------
-- F19's key-up can occasionally be lost: Karabiner may drop it during capture,
-- or the single-threaded Lua loop may be blocked when the release callback
-- should run. Either way the modal stays active and plain keystrokes start
-- firing hyper bindings. In the dropped-key-up case there is no release event
-- anywhere to react to, so the only reliable signal is elapsed time: nobody
-- holds the hyper key this long on purpose, so force-exit if they appear to.
local AUTO_EXIT_AFTER = 2.0  -- seconds
local watchdog = nil

local function clearWatchdog()
  if watchdog then watchdog:stop(); watchdog = nil end
end

-- Centralised enter/exit so every F19 chord (plain, shift, alt, shift+alt)
-- shares one isActive flag and one watchdog, not just the plain binding.
local function enterModal()
  f19.isActive = true
  f19:enter()
  clearWatchdog()
  watchdog = hs.timer.doAfter(AUTO_EXIT_AFTER, function()
    watchdog = nil
    if f19.isActive then
      f19.isActive = false
      f19:exit()
      print("[hyperkey] watchdog force-exited a stuck modal")
    end
  end)
end

local function exitModal()
  clearWatchdog()
  f19.isActive = false
  f19:exit()
end

-- F19 acts as a pure modifier: modal active while held, inactive when released.
hs.hotkey.bind({},               'F19', enterModal, exitModal)
hs.hotkey.bind({'shift'},        'F19', enterModal, exitModal)  -- Shift+Hyper
hs.hotkey.bind({'alt'},          'F19', enterModal, exitModal)  -- Option+Hyper
hs.hotkey.bind({'shift', 'alt'}, 'F19', enterModal, exitModal)  -- Shift+Option+Hyper

-- Redundant release path: a session event tap sees F19's key-up before Carbon
-- dispatches it (and sees Karabiner's re-injected events), so if the hotkey
-- release callback is missed because the Lua loop was momentarily busy, this
-- still catches the key-up the instant the loop frees up. It cannot help if
-- Karabiner never emitted the key-up at all -- that case is the watchdog's job.
local f19KeyCode = hs.keycodes.map.f19
local releaseTap = nil
if f19KeyCode then
  releaseTap = hs.eventtap.new({ hs.eventtap.event.types.keyUp }, function(e)
    if e:getKeyCode() == f19KeyCode and f19.isActive then
      exitModal()
    end
    return false  -- non-consuming: macOS still receives the key-up
  end)
  releaseTap:start()
end

-- Define keybinding function - bind hyper+key to launch/focus app
local function bindApp(mods, key, app)
  f19:bind(mods, key, function()
    hs.application.launchOrFocus(app)
  end)
end

-- Export module (releaseTap is returned so package.loaded keeps a reference to
-- it; an unreferenced event tap can be garbage-collected and silently stop).
return {
  modal = f19,
  bindApp = bindApp,
  releaseTap = releaseTap,
}
