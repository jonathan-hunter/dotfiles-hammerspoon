--[[
~/.hammerspoon/keybinds_window_mgmt.lua
Window management keybindings using hyper key (Caps Lock mapped to F19)
Special keybinds: F19+key transmits as modified keystrokes
Useful for apps that don't support F19 but need a unique keybind (Rectangle Pro)
]]

-- Configuration
local WINDOW_FOCUS_DELAY = 0.1
hs.window.animationDuration = 0

bindSpecial({'shift'}, ']', {'shift', 'ctrl', 'alt', 'cmd'}, ']')
bindSpecial({'shift'}, '[', {'shift', 'ctrl', 'alt', 'cmd'}, '[')
bindSpecial({'shift'}, 'H', {'shift', 'ctrl', 'alt', 'cmd'}, 'H')
bindSpecial({'shift'}, 'G', {'shift', 'ctrl', 'alt', 'cmd'}, 'G')
bindSpecial({'shift'}, 'J', {'shift', 'ctrl', 'alt', 'cmd'}, 'J')
bindSpecial({'shift'}, 'K', {'shift', 'ctrl', 'alt', 'cmd'}, 'K')
bindSpecial({'shift'}, 'L', {'shift', 'ctrl', 'alt', 'cmd'}, 'L')
bindSpecial({'shift'}, 'Y', {'shift', 'ctrl', 'alt', 'cmd'}, 'Y')
bindSpecial({'shift'}, 'U', {'shift', 'ctrl', 'alt', 'cmd'}, 'U')
bindSpecial({'shift'}, 'I', {'shift', 'ctrl', 'alt', 'cmd'}, 'I')
bindSpecial({'shift'}, 'N', {'shift', 'ctrl', 'alt', 'cmd'}, 'N')
bindSpecial({'shift'}, 'M', {'shift', 'ctrl', 'alt', 'cmd'}, 'M')
bindSpecial({'shift'}, ',', {'ctrl', 'alt', 'cmd'}, ',')           -- special case: omits shift to avoid unknown keybind conflict (TODO: document which conflict) 
bindSpecial({'shift'}, 'space', {'shift', 'ctrl', 'alt', 'cmd'}, 'space')

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
