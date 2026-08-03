-- ~/.hammerspoon/space_hud.lua
-- Space indicators:
--   * the current Mission Control space index on every space change
--   * "⌘N" on cmd+1..9 keypresses (visual confirmation of the hotkey)
-- The persistent menu bar item lives in space_taskbar (app icons grouped by
-- Space); this module feeds it current-Space updates via setCurrentIndex.

local spaces = require("hs.spaces")
local spaceState = require("space_state")
local taskbar = require("space_taskbar")

local HUD_DURATION = 0.6
local HUD_FADE_IN = 0.08
local HUD_FADE_OUT = 0.15
local HUD_FONT = ".AppleSystemUIFontMedium"  -- macOS system font (SF Pro), medium weight
local HUD_FONT_SIZE = 96
local HUD_WIDTH = 160         -- default width (single digit)
local HUD_WIDTH_CMD = 220     -- wider, for the two-glyph "⌘N" cmd+digit prompt
local HUD_HEIGHT = 130
local HUD_BOTTOM_MARGIN = 80  -- gap between HUD bottom and screen bottom

-- Vertical position of the text within the canvas; tweak by eye if it looks off.
local HUD_TEXT_Y_OFFSET = -10

local function currentSpaceIndex()
  local current = spaceState.currentSpace()
  return current and current.index or nil
end

local function updateMenubar(idx)
  taskbar.setCurrentIndex(idx)
end

local hudCanvas = nil
local hudVisible = false
local hudHideTimer = hs.timer.delayed.new(HUD_DURATION, function()
  if hudCanvas then hudCanvas:hide(HUD_FADE_OUT) end
  hudVisible = false
end)

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

local function showHud(text, width)
  local screen = hs.screen.mainScreen()
  if not screen then return end
  ensureHudCanvas()

  width = width or HUD_WIDTH
  hudCanvas:size({ w = width, h = HUD_HEIGHT })
  hudCanvas[2].frame = {
    x = 0,
    y = (HUD_HEIGHT - HUD_FONT_SIZE) / 2 + HUD_TEXT_Y_OFFSET,
    w = width,
    h = HUD_FONT_SIZE + 12,
  }

  local frame = screen:frame()
  hudCanvas:topLeft({
    x = frame.x + (frame.w - width) / 2,
    y = frame.y + frame.h - HUD_HEIGHT - HUD_BOTTOM_MARGIN,
  })
  hudCanvas[2].text = text or "?"

  if not hudVisible then
    hudCanvas:show(HUD_FADE_IN)
    hudVisible = true
  end

  hudHideTimer:start()
end

-- Event-tap callbacks run before macOS receives the event. Queue all canvas and
-- menu-bar work onto the next run-loop turn so ctrl+digit is delivered first.
local pendingHudText = nil
local pendingHudWidth = nil
local pendingMenubarIndex = nil
local renderTimer = hs.timer.delayed.new(0, function()
  if pendingMenubarIndex ~= nil then
    updateMenubar(pendingMenubarIndex)
    pendingMenubarIndex = nil
  end
  if pendingHudText ~= nil then
    local text, width = pendingHudText, pendingHudWidth
    pendingHudText, pendingHudWidth = nil, nil
    showHud(text, width)
  end
end)

local function queueHud(text, width, menubarIndex)
  pendingHudText = text
  pendingHudWidth = width
  if menubarIndex ~= nil then pendingMenubarIndex = menubarIndex end
  renderTimer:start()
end

-- When the eventtap below has just shown the HUD for a ctrl+digit press, the
-- spaces.watcher will fire moments later for the same switch. Update the menu
-- bar from the actual focused Space, but skip the duplicate HUD animation.
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
  queueHud(idx and tostring(idx) or "?", nil, idx or false)
end)
watcher:start()

-- Populate the menu bar immediately instead of waiting for the first switch.
updateMenubar(currentSpaceIndex())

-- Non-consuming keyDown tap (macOS still receives the keystroke). Fires the
-- HUD immediately on:
--   * ctrl+1..9 — macOS's space-switch shortcut, so the digit appears before
--     the space-switch animation. Also catches the synthetic ctrl+N posted by
--     the shift+hyper+N "move window to space" binding.
--   * cmd+1..9 — visual confirmation of the cmd hotkey; shown as "⌘N".
local digitFromKeyCode = {}
for d = 1, 9 do
  local code = hs.keycodes.map[tostring(d)]
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
    queueHud(tostring(digit), nil, digit)
    verifyTimer:start()
  elseif flags.cmd and not flags.ctrl and not flags.alt and not flags.shift then
    queueHud("⌘" .. digit, HUD_WIDTH_CMD)
  end
  return false
end)
hotkeyTap:start()

return {
  watcher = watcher,
  hotkeyTap = hotkeyTap,
  renderTimer = renderTimer,
  verifyTimer = verifyTimer,
  hudHideTimer = hudHideTimer,
}
