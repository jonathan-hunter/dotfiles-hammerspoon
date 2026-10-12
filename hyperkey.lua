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
-- anywhere to react to, so the only reliable signal is elapsed time. The timer
-- measures inactivity, not total hold time: every modal binding that fires
-- restarts it (see the bind wrapper below), so a long deliberate hold -- e.g.
-- repeated hjkl focus navigation -- never trips it, while a stuck modal
-- force-exits 2s after the user stops pressing bound keys.
local AUTO_EXIT_AFTER = 2.0  -- seconds
local watchdog = hs.timer.delayed.new(AUTO_EXIT_AFTER, function()
  if f19.isActive then
    f19.isActive = false
    f19:exit()
    print("[hyperkey] watchdog force-exited a stuck modal")
  end
end)

local function clearWatchdog()
  watchdog:stop()
end

local function startWatchdog()
  watchdog:start()
end

-- A modal binding firing is proof the user is deliberately holding hyper,
-- so push the force-exit deadline back.
local function petWatchdog()
  if f19.isActive then startWatchdog() end
end

-- Double-tap hyper (caps lock) toggles the real caps lock ------------------
-- A "tap" is a press/release of F19 with no modal binding fired in between,
-- which the bind wrapper below reports via modalUsed. Two taps inside the
-- window toggle caps lock; alerting the state is not cosmetic, the physical
-- caps LED is dark because Karabiner has remapped the key away.
local DOUBLE_TAP_WINDOW = 0.35  -- seconds between releases
local modalUsed = false
local lastTapAt = 0

local function registerTap()
  local now = hs.timer.secondsSinceEpoch()
  if now - lastTapAt < DOUBLE_TAP_WINDOW then
    lastTapAt = 0  -- consume, so a third tap starts a fresh pair
    hs.alert.show(hs.hid.capslock.toggle() and "CAPS LOCK ON" or "caps lock off")
  else
    lastTapAt = now
  end
end

-- Centralised enter/exit so every F19 chord (plain, shift, alt, shift+alt)
-- shares one isActive flag and one watchdog, not just the plain binding.
local function enterModal()
  f19.isActive = true
  modalUsed = false
  f19:enter()
  startWatchdog()
end

local function exitModal()
  clearWatchdog()
  -- One key-up can reach here twice -- the event tap below beats Carbon to it,
  -- then the hotkey release callback runs anyway. Only the transition counts:
  -- without this guard the second call sees a ~0s gap and reads a single tap
  -- as a double, toggling caps lock on every bare hyper press.
  local wasActive = f19.isActive
  f19.isActive = false
  f19:exit()
  if wasActive and not modalUsed then registerTap() end
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

-- Wrap the modal's bind so every binding pets the watchdog when it fires.
-- All keybind modules bind through this modal (it loads first and is exposed
-- as a global), so they get this for free without changes.
local rawBind = f19.bind
function f19.bind(self, mods, key, pressedFn, releasedFn, repeatFn)
  local function withPet(fn)
    if not fn then return nil end
    return function(...)
      modalUsed = true
      petWatchdog()
      return fn(...)
    end
  end
  return rawBind(self, mods, key, withPet(pressedFn), withPet(releasedFn), withPet(repeatFn))
end

-- launchOrFocus() hands its argument to LaunchServices, which resolves it as a
-- filename. A name carrying a dot ("Brain.fm") is read as an already-extensioned
-- file, so the lookup never falls through to Brain.fm.app and the call silently
-- returns false. Retrying with an explicit .app suffix resolves it. Bindings keep
-- passing the display name so frontmostIfMatches() below still matches.
local function launchOrFocus(app)
  if hs.application.launchOrFocus(app) then return true end
  if app:match("%.app$") then return false end
  return hs.application.launchOrFocus(app .. ".app")
end

-- launchOrFocus() resolves its argument against the app bundle's filename,
-- but some apps run under a different process name (Visual Studio Code.app
-- runs as "Code"; WhatsApp's name carries an invisible directional mark), so
-- check both when deciding whether the bound app is already frontmost.
local function frontmostIfMatches(appName)
  local front = hs.application.frontmostApplication()
  if not front then return nil end
  if front:name() == appName then return front end
  local path = front:path()
  if path and path:match("([^/]+)%.app$") == appName then return front end
  return nil
end

-- Delay before focusing a window after a ctrl+N Space switch: AX needs the
-- transition to settle before it can see the destination Space's windows.
local CYCLE_SPACE_FOCUS_DELAY = 0.30

-- The app's standard, non-minimized windows sorted by id (a stable ring order
-- regardless of z-order). AX also reports windows on other Spaces for some
-- apps, so when a current-Space window-id set is given, filter to it.
local function standardWindows(app, spaceWindowSet)
  local wins = {}
  for _, win in ipairs(app:allWindows()) do
    if win:isStandard() and not win:isMinimized()
        and (not spaceWindowSet or spaceWindowSet[win:id()]) then
      wins[#wins + 1] = win
    end
  end
  table.sort(wins, function(a, b) return a:id() < b:id() end)
  return wins
end

local function currentSpaceWindowSet()
  local focused = hs.spaces.focusedSpace()
  -- space_state's unwrapped windowsForSpace (~10x cheaper); required here, not
  -- at the top, because hyperkey loads before the space modules.
  local wins = focused and require("space_state").windowsForSpace(focused)
  if not wins then return nil end
  local set = {}
  for _, id in ipairs(wins) do set[id] = true end
  return set
end

-- Electron apps (VS Code, Slack) build their accessibility tree lazily: the
-- first AX window query after the app has been idle can return an empty list
-- and merely triggers tree construction. Acting on that snapshot makes the
-- binding conclude "no windows here" and hop away from -- or ignore -- a
-- window that is right on this Space. When the query comes back empty,
-- re-query once after a short delay before deciding.
local AX_RETRY_DELAY = 0.15

local function withStandardWindows(app, fn)
  local wins = standardWindows(app, currentSpaceWindowSet())
  if #wins > 0 then
    fn(wins)
    return
  end
  hs.timer.doAfter(AX_RETRY_DELAY, function()
    fn(standardWindows(app, currentSpaceWindowSet()))
  end)
end

-- Cycle the app's windows. With 2+ windows on the current Space, cycle among
-- them. Otherwise hop to the next Desktop holding this app's windows (per the
-- taskbar's model) via ctrl+N -- same mechanism as the HUD/taskbar, so the
-- indicators stay in sync -- and focus the app's window there on arrival.
-- Sync Spaces IPC only runs here, on an explicit keypress, never on a watcher.
local function cycleAppWindowsIn(app, wins)
  if #wins >= 2 then
    local focused = app:focusedWindow()
    local focusedId = focused and focused:id()
    local nextWin = wins[1]
    for i, win in ipairs(wins) do
      if win:id() == focusedId then
        nextWin = wins[(i % #wins) + 1]
        break
      end
    end
    nextWin:focus()
    return
  end

  -- 0 or 1 windows here: find Desktops with this app, lazily via the taskbar
  -- model (hyperkey loads before the space modules, so no top-level require).
  local okT, taskbar = pcall(require, "space_taskbar")
  local okS, spaceState = pcall(require, "space_state")
  if not (okT and okS) then return end
  local bundle = app:bundleID()
  local cur = spaceState.currentSpace()
  local curIdx = cur and cur.index
  local desktops = {}
  for i, group in ipairs(taskbar.getModel()) do
    if i ~= curIdx and i <= 10 then
      for _, b in ipairs(group.bundles) do
        if b == bundle then
          desktops[#desktops + 1] = i
          break
        end
      end
    end
  end
  if #desktops == 0 then return end

  local target = desktops[1]  -- wrap to the first if none after the current
  if curIdx then
    for _, d in ipairs(desktops) do
      if d > curIdx then target = d break end
    end
  end
  hs.eventtap.keyStroke({ "ctrl" }, tostring(target % 10), 0)
  hs.timer.doAfter(CYCLE_SPACE_FOCUS_DELAY, function()
    withStandardWindows(app, function(arrived)
      if arrived[1] then arrived[1]:focus() end
    end)
  end)
end

local function cycleAppWindows(app)
  withStandardWindows(app, function(wins)
    cycleAppWindowsIn(app, wins)
  end)
end

-- What still needs doing once a launch/focus has been issued:
--   * frontmost with a window here          -- nothing to do
--   * frontmost with no window on this Space -- macOS does not follow the app to
--     its Space, so hop to it
--   * running but still in the background   -- accessory apps (Brain.fm runs
--     with no dock icon) do not come forward from launchOrFocus() at all, and a
--     repeat launchOrFocus() does not either; activate() does, and also makes
--     them open their window
-- A cold Electron start can take a couple of seconds to register with the OS,
-- so poll a few times before concluding the launch went nowhere.
local LAUNCH_SETTLE_RETRIES = 8

local function settleAfterLaunch(appName, tries)
  local front = frontmostIfMatches(appName)
  if front then
    withStandardWindows(front, function(wins)
      if #wins == 0 then cycleAppWindowsIn(front, wins) end
    end)
    return
  end
  local running = hs.application.get(appName)
  if running then
    running:activate(true)
    return
  end
  if tries > 0 then
    hs.timer.doAfter(CYCLE_SPACE_FOCUS_DELAY, function()
      settleAfterLaunch(appName, tries - 1)
    end)
  end
end

-- Bring the app forward after something has launched or poked it (launchOrFocus,
-- or a URL scheme the app handles), hopping to its Desktop if it isn't here.
local function settleApp(app)
  hs.timer.doAfter(CYCLE_SPACE_FOCUS_DELAY, function()
    settleAfterLaunch(app, LAUNCH_SETTLE_RETRIES)
  end)
end

-- Define keybinding function - bind hyper+key to launch/focus app.
-- Pressing the key again while the app is already frontmost cycles/hops
-- through its windows instead of being a no-op.
local function bindApp(mods, key, app)
  f19:bind(mods, key, function()
    local front = frontmostIfMatches(app)
    if front then
      cycleAppWindows(front)
      return
    end
    launchOrFocus(app)
    settleApp(app)
  end)
end

-- Export module (releaseTap is returned so package.loaded keeps a reference to
-- it; an unreferenced event tap can be garbage-collected and silently stop).
return {
  modal = f19,
  bindApp = bindApp,
  settleApp = settleApp,
  releaseTap = releaseTap,
  watchdog = watchdog,
}
