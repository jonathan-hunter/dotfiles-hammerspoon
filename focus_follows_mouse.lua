-- ~/.hammerspoon/focus_follows_mouse.lua
-- Focus follows mouse: the window under the pointer is raised and focused once
-- the pointer settles in it. Fast sweeps across a window never fire, so cutting
-- across B on the way to somewhere else leaves focus alone. Hyper+Opt+F toggles;
-- on at load.
--
-- Settling: a slow move checks almost at once (you decelerate into a target); a
-- fast move pushes the check out until the pointer has been still SETTLE_DELAY.
-- Nothing is done inside the tap callback itself -- AX work there would stall
-- every mouse event system-wide.

local SETTLE_DELAY   = 0.04  -- seconds the pointer must rest after a fast move
local CHECK_INTERVAL = 0.02  -- seconds between checks while moving slowly
local SLOW_SPEED     = 400   -- px/s; slower than this counts as aiming, not transit
local AX_TIMEOUT     = 0.1   -- seconds; a hung app can't freeze the check

local taskbar = require("space_taskbar")

local enabled = true
local timer           -- the settle timer, created below check()
local lastX, lastY, lastT  -- pointer position and time at the last mouseMoved
local systemWide = hs.axuielement.systemWideElement()
systemWide:setTimeout(AX_TIMEOUT)

-- A context menu or dropdown shows up as an AXMenu child of its app; focusing
-- another window would dismiss it. (A menu under the pointer needs no check:
-- menu items have no AXWindow, so windowUnderPointer already returns nil.)
local function menuOpen(app)
  local axApp = hs.axuielement.applicationElement(app)
  for _, child in ipairs((axApp and axApp.AXChildren) or {}) do
    if child.AXRole == "AXMenu" then return true end
  end
  return false
end

local function windowUnderPointer(p)
  local el = systemWide:elementAtPosition(p)
  if not el then return nil end
  local axWin = el.AXRole == "AXWindow" and el or el.AXWindow
  return axWin and axWin:asHSWindow()
end

local function check()
  if not enabled or f19.isActive then return end
  if next(hs.eventtap.checkMouseButtons()) then return end  -- dragging / selecting

  -- Inside the display but outside its usable frame = menu bar or a visible
  -- Dock: no window focus there. The taskbar strip switches on hover, but only
  -- at full rest -- a Space switch is too heavy to fire for every icon a slow
  -- glide along the bar passes over.
  local p = hs.mouse.absolutePosition()
  local screen = hs.mouse.getCurrentScreen()
  if not screen then return end
  if not hs.geometry.point(p):inside(screen:frame()) then
    -- 0.75: slack for timer jitter, so a true rest isn't made to wait twice
    if lastT and hs.timer.absoluteTime() - lastT < SETTLE_DELAY * 0.75 * 1e9 then
      timer:start(SETTLE_DELAY)  -- still moving; look again once it rests
    else
      taskbar.hoverAt(p)
    end
    return
  end

  local win = windowUnderPointer(p)
  -- Non-standard covers the desktop, auto-hidden Dock, Mission Control,
  -- popovers and floating panels (Spotlight, Raycast, 1Password).
  if not win or not win:isStandard() then return end

  local focused = hs.window.focusedWindow()
  if focused and focused:id() == win:id() then return end
  if focused and menuOpen(focused:application()) then return end

  win:focus()
end

timer = hs.timer.delayed.new(SETTLE_DELAY, check)

local tap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function()
  if not enabled then return false end
  local p, t = hs.mouse.absolutePosition(), hs.timer.absoluteTime()
  if lastT then
    local dt = (t - lastT) / 1e9
    local dist = math.sqrt((p.x - lastX) ^ 2 + (p.y - lastY) ^ 2)
    if dt > 0 and dist / dt < SLOW_SPEED then
      if not timer:running() then timer:start(CHECK_INTERVAL) end
    else
      timer:start(SETTLE_DELAY)
    end
  end
  lastX, lastY, lastT = p.x, p.y, t
  return false
end)
tap:start()

-- macOS silently disables a tap after a slow callback or a secure-input spell;
-- re-arm it rather than have the feature quietly die until the next reload.
local tapWatchdog = hs.timer.doEvery(5, function()
  if enabled and not tap:isEnabled() then tap:start() end
end)

f19:bind({ 'alt' }, 'F', function()
  enabled = not enabled
  if enabled then tap:start() else tap:stop(); timer:stop() end
  notify("Focus follows mouse: " .. (enabled and "on" or "off"))
end)

return { tap = tap, timer = timer, watchdog = tapWatchdog }  -- held in package.loaded so nothing is GC'd
