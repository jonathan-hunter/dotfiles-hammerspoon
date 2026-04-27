-- ~/.hammerspoon/menubar_spaces.lua
-- Transient HUD that flashes the current Mission Control space index in the
-- center of the main screen on every space change.

local spaces = require("hs.spaces")

local HUD_DURATION = 0.6
local HUD_FADE_IN = 0.08
local HUD_FADE_OUT = 0.15
local HUD_FONT = ".AppleSystemUIFontMedium"  -- macOS system font (SF Pro), medium weight
local HUD_FONT_SIZE = 96
local HUD_WIDTH = 160
local HUD_HEIGHT = 130
local HUD_BOTTOM_MARGIN = 80  -- gap between HUD bottom and screen bottom

-- Vertical position of the text within the canvas; tweak by eye if it looks off.
local HUD_TEXT_Y_OFFSET = -10

-- spaces.spacesForScreen() is an expensive IPC call. The list only changes when
-- the user adds/removes/reorders spaces, so cache it and refresh only when the
-- focused space ID isn't found (i.e. the cache is stale).
local cachedSpaceIds = nil
local cachedSpaceIdsUUID = nil

local function findIndex(list, target)
  if not list then return nil end
  for i, s in ipairs(list) do
    if s == target then return i end
  end
  return nil
end

local function currentSpaceIndex()
  local screen = hs.screen.mainScreen()
  if not screen then return nil end
  local uuid = screen:getUUID()
  local focused = spaces.focusedSpace()
  if not focused then return nil end

  if cachedSpaceIdsUUID ~= uuid or not cachedSpaceIds then
    cachedSpaceIds = spaces.spacesForScreen(uuid)
    cachedSpaceIdsUUID = uuid
  end

  local idx = findIndex(cachedSpaceIds, focused)
  if idx then return idx end

  -- Cache miss: spaces layout changed. Refresh and retry once.
  cachedSpaceIds = spaces.spacesForScreen(uuid)
  return findIndex(cachedSpaceIds, focused)
end

local hudCanvas = nil
local hudHideTimer = nil
local hudVisible = false

local function ensureHudCanvas()
  if hudCanvas then return end
  hudCanvas = hs.canvas.new({ x = 0, y = 0, w = HUD_WIDTH, h = HUD_HEIGHT })
  hudCanvas:level(hs.canvas.windowLevels.overlay)
  -- Float on every space so a space switch doesn't carry the HUD away with it
  hudCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  hudCanvas:appendElements(
    {
      type = "rectangle",
      action = "fill",
      fillColor = { red = 0, green = 0, blue = 0, alpha = 0.72 },
      roundedRectRadii = { xRadius = 22, yRadius = 22 },
    },
    {
      type = "text",
      text = "",
      textFont = HUD_FONT,
      textColor = { white = 1, alpha = 1 },
      textSize = HUD_FONT_SIZE,
      textAlignment = "center",
      frame = {
        x = 0,
        y = (HUD_HEIGHT - HUD_FONT_SIZE) / 2 + HUD_TEXT_Y_OFFSET,
        w = HUD_WIDTH,
        h = HUD_FONT_SIZE + 12,
      },
    }
  )
end

local function showHud(idx)
  local screen = hs.screen.mainScreen()
  if not screen then return end
  ensureHudCanvas()

  local frame = screen:frame()
  hudCanvas:topLeft({
    x = frame.x + (frame.w - HUD_WIDTH) / 2,
    y = frame.y + frame.h - HUD_HEIGHT - HUD_BOTTOM_MARGIN,
  })
  hudCanvas[2].text = tostring(idx or "?")

  if not hudVisible then
    hudCanvas:show(HUD_FADE_IN)
    hudVisible = true
  end

  if hudHideTimer then hudHideTimer:stop() end
  hudHideTimer = hs.timer.doAfter(HUD_DURATION, function()
    if hudCanvas then hudCanvas:hide(HUD_FADE_OUT) end
    hudVisible = false
  end)
end

-- When the eventtap below has just shown the HUD for a ctrl+digit press, the
-- spaces.watcher will fire moments later for the same switch. focusedSpace()
-- is a sync IPC call (5–200ms) and we already know what to display, so we
-- skip the watcher's lookup if a tap fired within this window.
local TAP_DEDUP_WINDOW = 0.4
local lastTapTime = 0

local function now() return hs.timer.absoluteTime() / 1e9 end

local watcher = spaces.watcher.new(function()
  if now() - lastTapTime < TAP_DEDUP_WINDOW then return end
  showHud(currentSpaceIndex())
end)
watcher:start()

-- Fire the HUD immediately on ctrl+1..9 keydown so the number appears before
-- macOS even starts the space-switch animation. Non-consuming tap (macOS still
-- receives the keystroke). Also catches the synthetic ctrl+N posted by the
-- shift+hyper+N "move window to space" binding.
local digitFromKeyCode = {}
for d = 1, 9 do
  local code = hs.keycodes.map[tostring(d)]
  if code then digitFromKeyCode[code] = d end
end

local hotkeyTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
  local flags = event:getFlags()
  if not flags.ctrl or flags.cmd or flags.alt or flags.shift then
    return false
  end
  local digit = digitFromKeyCode[event:getKeyCode()]
  if digit then
    showHud(digit)
    lastTapTime = now()
  end
  return false
end)
hotkeyTap:start()

return { watcher = watcher, hotkeyTap = hotkeyTap }
