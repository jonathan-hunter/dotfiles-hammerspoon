--[[
~/.hammerspoon/keybinds_window_mgmt.lua
Window management keybindings using hyper key (Caps Lock mapped to F19).
Native Hammerspoon tiling layout, hyper+opt+1..4 one-shot multi-window
layouts, vim-style focus navigation, and shift+hyper+1..9 to move the
focused window to space N.
]]

-- Configuration
local WINDOW_FOCUS_DELAY = 0.1
local NAVIGATION_REFRESH_DELAY = 0.12
local NAVIGATION_SPACE_REFRESH_DELAY = 0.20
local PADDING = 1
local spaces = require("hs.spaces")
hs.window.animationDuration = 0

-- Set a window's frame to a fractional rect of a screen frame, inset by
-- PADDING px. x, y, w, h are fractions in [0, 1] of the screen's usable frame.
local function setTileFrame(win, f, x, y, w, h)
  win:setFrame({
    x = f.x + f.w * x + PADDING,
    y = f.y + f.h * y + PADDING,
    w = f.w * w - PADDING * 2,
    h = f.h * h - PADDING * 2,
  })
end

-- Tile the focused window to a fractional rect of its screen.
local function tile(x, y, w, h)
  return function()
    local win = hs.window.focusedWindow()
    if not win then return end
    setTileFrame(win, win:screen():frame(), x, y, w, h)
  end
end

-- Halves and full screen
f19:bind({'shift'}, ']',     tile(0.5,  0,    0.5,  1))    -- right half
f19:bind({'shift'}, '[',     tile(0,    0,    0.5,  1))    -- left half
f19:bind({'shift'}, 'space', tile(0,    0,    1,    1))    -- full screen

-- Vertical strips (full height)
f19:bind({'shift'}, 'H', tile(0,    0, 0.25, 1))           -- left quarter
f19:bind({'shift'}, 'G', tile(0,    0, 0.75, 1))           -- left three-quarters
f19:bind({'shift'}, 'J', tile(0.25, 0, 0.5,  1))           -- center half
f19:bind({'shift'}, 'K', tile(0.5,  0, 0.25, 1))           -- third quarter
f19:bind({'shift'}, 'L', tile(0.75, 0, 0.25, 1))           -- right quarter

-- Corner quarters and top/bottom halves
f19:bind({'shift'}, 'Y', tile(0,   0,   0.5, 0.5))         -- top left quarter
f19:bind({'shift'}, 'U', tile(0,   0,   1,   0.5))         -- top half
f19:bind({'shift'}, 'I', tile(0.5, 0,   0.5, 0.5))         -- top right quarter
f19:bind({'shift'}, 'N', tile(0,   0.5, 0.5, 0.5))         -- bottom left quarter
f19:bind({'shift'}, 'M', tile(0,   0.5, 1,   0.5))         -- bottom half
f19:bind({'shift'}, ',', tile(0.5, 0.5, 0.5, 0.5))         -- bottom right quarter

-- One-shot layouts: Hyper+Opt+1..4 arranges every standard window on the
-- current Space (focused window's screen only) into a fixed pattern. Slot 1
-- is the layout's hero position and always receives the focused window;
-- the rest follow in stable id order. With fewer windows than slots the
-- trailing slots stay empty; with more, assignment wraps around the pattern
-- and the hero is raised last so it stays on top of any stack.
local LAYOUTS = {
  { {0, 0, 1, 1} },                                        -- 1: monocle
  { {0, 0, 0.5, 1}, {0.5, 0, 0.5, 1} },                    -- 2: two columns
  { {0.2, 0, 0.6, 1},                                      -- 3: ultrawide 1:3:1,
    {0, 0, 0.2, 1}, {0.8, 0, 0.2, 1} },                    --    hero center
  { {0, 0, 0.5, 0.5}, {0.5, 0, 0.5, 0.5},                  -- 4: 2x2 corners
    {0, 0.5, 0.5, 0.5}, {0.5, 0.5, 0.5, 0.5} },
}

local function applyLayout(slots)
  local focused = hs.window.focusedWindow()
  local screen = focused and focused:screen() or hs.screen.mainScreen()
  if not screen then return end
  local screenId = screen:id()

  local wins = {}
  for _, win in ipairs(hs.window.orderedWindows()) do
    if win:isStandard() and win:isVisible() and win:screen():id() == screenId then
      wins[#wins + 1] = win
    end
  end
  if #wins == 0 then return end

  -- Hero first; without a focused standard window the lowest id leads.
  local focusedId = focused and focused:id()
  table.sort(wins, function(a, b)
    if a:id() == focusedId then return true end
    if b:id() == focusedId then return false end
    return a:id() < b:id()
  end)

  local frame = screen:frame()
  for i, win in ipairs(wins) do
    local s = slots[((i - 1) % #slots) + 1]
    setTileFrame(win, frame, s[1], s[2], s[3], s[4])
  end
  wins[1]:focus()
end

for i, slots in ipairs(LAYOUTS) do
  f19:bind({'alt'}, tostring(i), function() applyLayout(slots) end)
end

-- Directional focus is called frequently while Hyper is held. Calling
-- focusWindowWest/North/South/East without candidates makes Hammerspoon query
-- every application on every keypress, so maintain a current-Space candidate
-- list and refresh it once when the window set or active Space changes.
local navigationWindows = {}

local function refreshNavigationWindows()
  local refreshed = {}
  for _, win in ipairs(hs.window.orderedWindows()) do
    if win:isStandard() and win:isVisible() then
      refreshed[#refreshed + 1] = win
    end
  end
  navigationWindows = refreshed
end

local navigationRefreshTimer = hs.timer.delayed.new(
  NAVIGATION_REFRESH_DELAY,
  refreshNavigationWindows
)

local function focusDirection(method)
  local win = hs.window.focusedWindow()
  if not win then return end
  if #navigationWindows == 0 then refreshNavigationWindows() end
  win[method](win, navigationWindows)
end

f19:bind({}, "h", function() focusDirection("focusWindowWest") end)
f19:bind({}, "j", function() focusDirection("focusWindowSouth") end)
f19:bind({}, "k", function() focusDirection("focusWindowNorth") end)
f19:bind({}, "l", function() focusDirection("focusWindowEast") end)

local windowFilter = hs.window.filter.default
local cacheEvents = {
  hs.window.filter.windowCreated,
  hs.window.filter.windowVisible,
  hs.window.filter.windowNotVisible,
  hs.window.filter.windowMinimized,
  hs.window.filter.windowUnminimized,
  hs.window.filter.windowHidden,
  hs.window.filter.windowUnhidden,
}
windowFilter:subscribe(cacheEvents, function()
  navigationRefreshTimer:start()
end)

-- Clear stale candidates immediately on a Space change, then rebuild after the
-- reduced-motion transition has settled. The watcher itself performs no AX or
-- Spaces IPC, keeping it out of the switching hot path.
local navigationSpaceWatcher = spaces.watcher.new(function()
  navigationWindows = {}
  navigationRefreshTimer:start(NAVIGATION_SPACE_REFRESH_DELAY)
end)
navigationSpaceWatcher:start()

-- Auto-focus only when macOS has not already selected a replacement window.
-- This avoids both a full orderedWindows() query and focus stealing after every
-- background window destruction.
local closeFocusTimer = hs.timer.delayed.new(WINDOW_FOCUS_DELAY, function()
  if hs.window.focusedWindow() then return end
  refreshNavigationWindows()
  if navigationWindows[1] then navigationWindows[1]:focus() end
end)

windowFilter:subscribe(hs.window.filter.windowDestroyed, function()
  navigationRefreshTimer:start()
  closeFocusTimer:start()
end)

-- Populate the candidate cache after this config load finishes.
navigationRefreshTimer:start(0)

local function switchToSpaceNumber(n)
  hs.eventtap.keyStroke({"ctrl"}, tostring(n), 0)
end

-- Distance left of the zoom button's leading edge to the midpoint of the gap
-- separating it from the minimize button, used only when AX will not report
-- the minimize button. macOS 26 spaces the traffic lights 23px apart with 16px
-- rects, so the gap is 7px wide and its midpoint sits 3.5px left of zoom.
local ZOOM_TO_GAP_MIDPOINT = 3.5

-- The minimize (yellow) button's rect, or nil if AX does not expose it.
-- hs.window only surfaces zoomButtonRect(), so go through the AX element.
local function minimizeButtonRect(win)
  local ax = hs.axuielement.windowElement(win)
  local btn = ax and ax:attributeValue("AXMinimizeButton")
  if not btn then return nil end
  local pos, size = btn:attributeValue("AXPosition"), btn:attributeValue("AXSize")
  if not (pos and size) then return nil end
  return { x = pos.x, y = pos.y, w = size.w, h = size.h }
end

local function moveWinToSpaceByDrag(win, n)
  -- Anchor in the gap between the minimize (yellow) and zoom (green) buttons,
  -- level with their centres. Every standard macOS window has that gap, it is
  -- plain draggable titlebar, and it dodges both the app chrome crowding the
  -- area right of the zoom button (Brave's sidebar toggle, Slack's history
  -- buttons) and the window's top resize border. Anchoring a few px *above*
  -- the button row instead only clears the resize border where the titlebar is
  -- tall: Ghostty leaves 12px above the buttons and Claude 16px, but Brave with
  -- vertical tabs leaves roughly 9px, which put the press about 4px inside the
  -- frame edge -- close enough to the resize border to explain why the drag
  -- never started there and the window stayed behind on the Space switch.
  local zoom = win:zoomButtonRect()
  -- nil for windows without a zoom button (dialogs, palettes, some Electron
  -- windows); bail rather than error -- and crucially, bail before posting
  -- the mouse-down, which would otherwise leave a stuck virtual drag.
  if not zoom then return end
  local pt = { x = zoom.x - ZOOM_TO_GAP_MIDPOINT, y = zoom.y + zoom.h / 2 }
  -- Prefer the measured gap over the constant; guard against a layout that
  -- does not put minimize to the left of zoom, which would aim off into space.
  local minimize = minimizeButtonRect(win)
  if minimize and minimize.x + minimize.w <= zoom.x then
    pt.x = (minimize.x + minimize.w + zoom.x) / 2
  end
  local orig = hs.mouse.absolutePosition()

  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDown, pt):post()
  -- Async delay instead of hs.timer.usleep, which would freeze the whole event
  -- loop -- including the F19 key-up callback -- for 10ms while the hyper key
  -- is still held, and this binding fires precisely while it is held.
  hs.timer.doAfter(0.01, function()             -- let Dock register the drag
    switchToSpaceNumber(n)
    hs.timer.doAfter(0.05, function()
      hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, pt):post()
      hs.mouse.absolutePosition(orig)
    end)
  end)
end

--- Move focused window to space N (1..9)
local function moveWinToSpace(n)
  local win = hs.window.focusedWindow()
  if not win then return end
  moveWinToSpaceByDrag(win, n)
end

-- Shift+Hyper+1..9 → move focused window to space N
for i = 1, 9 do
  f19:bind({'shift'}, tostring(i), function() moveWinToSpace(i) end)
end

return {
  windowFilter = windowFilter,
  navigationSpaceWatcher = navigationSpaceWatcher,
  navigationRefreshTimer = navigationRefreshTimer,
  closeFocusTimer = closeFocusTimer,
}
