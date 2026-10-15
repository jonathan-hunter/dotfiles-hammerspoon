-- ~/.hammerspoon/space_hud.lua
-- Feeds current-Space updates to space_taskbar (app icons grouped by Space)
-- via setCurrentIndex. No on-screen popup.

local spaces = require("hs.spaces")
local spaceState = require("space_state")
local taskbar = require("space_taskbar")

local function currentSpaceIndex()
  local current = spaceState.currentSpace()
  return current and current.index or nil
end

local function updateMenubar(idx)
  taskbar.setCurrentIndex(idx)
end

-- Event-tap callbacks run before macOS receives the event. Queue all canvas and
-- menu-bar work onto the next run-loop turn so ctrl+digit is delivered first.
local pendingMenubarIndex = nil
local renderTimer = hs.timer.delayed.new(0, function()
  if pendingMenubarIndex ~= nil then
    updateMenubar(pendingMenubarIndex)
    pendingMenubarIndex = nil
  end
end)

local function queueMenubar(menubarIndex)
  if menubarIndex ~= nil then pendingMenubarIndex = menubarIndex end
  renderTimer:start()
end

-- When the eventtap below has just handled a ctrl+digit press, the
-- spaces.watcher will fire moments later for the same switch; skip the duplicate.
local TAP_DEDUP_WINDOW = 0.4
local lastTapTime = 0
local canInformWindowFilter = spaces.screensHaveSeparateSpaces()

local function now() return hs.timer.absoluteTime() / 1e9 end

local verifyTimer = hs.timer.delayed.new(TAP_DEDUP_WINDOW + 0.05, function()
  updateMenubar(currentSpaceIndex())
end)

local watcher = spaces.watcher.new(function()
  -- For numbered switches the key tap already knows the destination. Avoid all
  -- synchronous Spaces IPC while macOS is completing that transition.
  if now() - lastTapTime < TAP_DEDUP_WINDOW then return end
  local idx = currentSpaceIndex()
  queueMenubar(idx or false)
end)
watcher:start()

-- Populate the menu bar immediately instead of waiting for the first switch.
updateMenubar(currentSpaceIndex())

-- Non-consuming keyDown tap (macOS still receives the keystroke) on ctrl+1..9,0,
-- macOS's space-switch shortcut. Also catches the synthetic ctrl+N posted by
-- the shift+hyper+N "move window to space" binding.
local digitFromKeyCode = {}
for d = 1, 10 do
  local code = hs.keycodes.map[tostring(d % 10)]
  if code then digitFromKeyCode[code] = d end
end

local hotkeyTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
  local digit = digitFromKeyCode[event:getKeyCode()]
  if not digit then return false end
  local flags = event:getFlags()

  if flags.ctrl and not flags.cmd and not flags.alt and not flags.shift then
    lastTapTime = now()
    -- This avoids repeated full window-filter discovery for already visited
    -- numbered Spaces. The user's Mission Control auto-rearrange setting is off;
    -- the API additionally requires Displays Have Separate Spaces to be on.
    if canInformWindowFilter then
      hs.window.filter.switchedToSpace(digit)
    end
    queueMenubar(digit)
    verifyTimer:start()
  end
  return false
end)
hotkeyTap:start()

return {
  watcher = watcher,
  hotkeyTap = hotkeyTap,
  renderTimer = renderTimer,
  verifyTimer = verifyTimer,
}
