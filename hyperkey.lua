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
    notify(hs.hid.capslock.toggle() and "CAPS LOCK ON" or "caps lock off")
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
-- check both when deciding whether an app is the bound one.
local function matchesApp(app, appName)
  if app:name() == appName then return true end
  local path = app:path()
  return path ~= nil and path:match("([^/]+)%.app$") == appName
end

-- Bundle IDs learned from the frontmost check, for runningApp() below.
local bundleIDFor = {}

local function frontmostIfMatches(appName)
  local front = hs.application.frontmostApplication()
  if not (front and matchesApp(front, appName)) then return nil end
  bundleIDFor[appName] = front:bundleID()
  return front
end

-- The running app bound to this name, if any. Two obvious routes are traps:
--   * hs.application.get() matches names by substring and, when no name matches
--     (the app is not running yet, or runs under another process name), falls
--     back to searching every window title of every app -- a full AX sweep that
--     stalls the Lua thread and can hand back an unrelated app that merely has
--     the name in a window title.
--   * matchesApp() over runningApplications(): app:path() raises an Objective-C
--     exception for any process without a bundle URL (Hammerspoon 1.1.1), and
--     there is always one. It is only safe on the frontmost app.
-- So: exact process name, plus the bundle ID remembered from the last time the
-- app was seen frontmost, which covers the apps whose process name differs.
-- Until then such an app reads as not running and takes the slower `open -a`.
local function runningApp(appName)
  local id = bundleIDFor[appName]
  return id and hs.application.applicationsForBundleID(id)[1]
      or (hs.application.find(appName, true))
end

-- Launch tracking -------------------------------------------------------------
-- An app between "will launch" and "did launch" does not answer AX queries
-- until its main loop is running, and a query that waits on it blocks the
-- single Lua thread -- every other hotkey queues behind it. Record launch start
-- times by pid so the settle step can wait such an app out instead of asking it
-- anything. Entries expire after LAUNCH_TIMEOUT, so an app that hangs while
-- starting cannot keep a settle polling forever.
local LAUNCH_TIMEOUT = 30  -- seconds
local launchStartedAt = {}
local appEvents = hs.application.watcher
local launchWatcher = appEvents.new(function(_, event, app)
  local pid = app and app:pid()
  if not pid then return end
  if event == appEvents.launching then
    launchStartedAt[pid] = hs.timer.secondsSinceEpoch()
  elseif event == appEvents.launched or event == appEvents.terminated then
    launchStartedAt[pid] = nil
  end
end)
launchWatcher:start()

local function isLaunching(app)
  local startedAt = launchStartedAt[app:pid()]
  return startedAt ~= nil and hs.timer.secondsSinceEpoch() - startedAt < LAUNCH_TIMEOUT
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

-- Bumped by every app key. Nothing here blocks while an app starts, so another
-- app key can land mid-launch; the latest one wins, and a settle that finds the
-- counter moved on drops out rather than pulling focus back to its own app.
local settleGen = 0

local function settleAfterLaunch(appName, tries, gen)
  if gen ~= settleGen then return end
  local function retry(left)
    hs.timer.doAfter(CYCLE_SPACE_FOCUS_DELAY, function()
      settleAfterLaunch(appName, left, gen)
    end)
  end
  local front = frontmostIfMatches(appName)
  local running = front or runningApp(appName)
  if running and isLaunching(running) then
    retry(tries)  -- costs no try: LAUNCH_TIMEOUT bounds this wait instead
  elseif front then
    withStandardWindows(front, function(wins)
      if #wins == 0 then cycleAppWindowsIn(front, wins) end
    end)
  elseif running then
    running:activate(true)
  elseif tries > 0 then
    retry(tries - 1)
  end
end

-- Bring the app forward after something has launched or poked it, hopping to
-- its Desktop if it isn't here.
local function settleApp(app, gen)
  hs.timer.doAfter(CYCLE_SPACE_FOCUS_DELAY, function()
    settleAfterLaunch(app, LAUNCH_SETTLE_RETRIES, gen)
  end)
end

-- Cold launch off the Lua thread: launchOrFocus() is a synchronous
-- LaunchServices call, and the thread is held for as long as it takes. The
-- .app retry mirrors launchOrFocus() above, in case `open -a` trips on a
-- dotted name the same way; settling always uses the display name.
local function openAsync(appName, gen, target)
  target = target or appName
  hs.task.new("/usr/bin/open", function(exitCode)
    if exitCode == 0 then
      settleApp(appName, gen)
    elseif not target:match("%.app$") then
      openAsync(appName, gen, target .. ".app")
    end
  end, { "-a", target }):start()
end

-- Launch or focus the app, then settle it, without ever waiting on the launch.
local function launchApp(app)
  settleGen = settleGen + 1
  local gen = settleGen
  if runningApp(app) then
    launchOrFocus(app)  -- already running: returns at once, no process spawn
    settleApp(app, gen)
  else
    openAsync(app, gen)
  end
end

-- Define keybinding function - bind hyper+key to launch/focus app.
-- Pressing the key again while the app is already frontmost cycles/hops
-- through its windows instead of being a no-op.
local function bindApp(mods, key, app)
  f19:bind(mods, key, function()
    local front = frontmostIfMatches(app)
    if not front then
      launchApp(app)
    elseif not isLaunching(front) then  -- mid-launch: its settle is still pending
      settleGen = settleGen + 1
      cycleAppWindows(front)
    end
  end)
end

-- Export module (releaseTap and launchWatcher are returned so package.loaded
-- keeps a reference to them; an unreferenced event tap or watcher can be
-- garbage-collected and silently stop).
return {
  modal = f19,
  bindApp = bindApp,
  launchApp = launchApp,
  releaseTap = releaseTap,
  launchWatcher = launchWatcher,
  watchdog = watchdog,
}
