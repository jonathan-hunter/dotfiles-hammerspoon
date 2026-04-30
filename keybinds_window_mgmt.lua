--[[
~/.hammerspoon/keybinds_window_mgmt.lua
Window management keybindings using hyper key (Caps Lock mapped to F19).
Native Hammerspoon tiling layout, vim-style focus navigation, and
shift+hyper+1..9 to move the focused window to space N.
]]

-- Configuration
local WINDOW_FOCUS_DELAY = 0.1
local PADDING = 1
hs.window.animationDuration = 0

-- Tile the focused window to a fractional rect of its screen, inset by PADDING px.
-- x, y, w, h are fractions in [0, 1] of the screen's usable frame.
local function tile(x, y, w, h)
  return function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local f = win:screen():frame()
    win:setFrame({
      x = f.x + f.w * x + PADDING,
      y = f.y + f.h * y + PADDING,
      w = f.w * w - PADDING * 2,
      h = f.h * h - PADDING * 2,
    })
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

-- Window focus keybinds
-- Bind F19+[h/j/k/l] to directional window focus
f19:bind({}, "h", function()
  local win = hs.window.focusedWindow()
  if win then win:focusWindowWest() end
end)
f19:bind({}, "j", function()
  local win = hs.window.focusedWindow()
  if win then win:focusWindowSouth() end
end)
f19:bind({}, "k", function()
  local win = hs.window.focusedWindow()
  if win then win:focusWindowNorth() end
end)
f19:bind({}, "l", function()
  local win = hs.window.focusedWindow()
  if win then win:focusWindowEast() end
end)

-- Auto-focus next window when current window is closed
hs.window.filter.default:subscribe(hs.window.filter.windowDestroyed, function()
    -- Small delay to ensure window list is updated
    hs.timer.doAfter(WINDOW_FOCUS_DELAY, function()
        local windows = hs.window.orderedWindows()
        -- Filter out minimized and hidden windows
        for _, win in ipairs(windows) do
            if win:isStandard() and win:isVisible() then
                win:focus()
                return
            end
        end
    end)
end)

--- Move focused window to space N (1..9)
local function moveWinToSpace(n)
  local win = hs.window.focusedWindow()
  if not win then return end
  local pt   = win:zoomButtonRect()             -- titlebar anchor
  pt.x, pt.y = pt.x + pt.w + 5, pt.y + pt.h / 2 -- free spot right of zoom
  local orig = hs.mouse.absolutePosition()

  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDown, pt):post()
  hs.timer.usleep(10000)                        -- let Dock register the drag
  hs.eventtap.keyStroke({"ctrl"}, tostring(n), 0)
  hs.timer.doAfter(0.05, function()
    hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, pt):post()
    hs.mouse.absolutePosition(orig)
  end)
end

-- Shift+Hyper+1..9 → move focused window to space N
for i = 1, 9 do
  f19:bind({'shift'}, tostring(i), function() moveWinToSpace(i) end)
end
