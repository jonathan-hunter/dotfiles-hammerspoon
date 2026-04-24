-- ~/.hammerspoon/menubar_spaces.lua
-- Menu bar indicator showing the current Mission Control space index on the main screen.

local spaces = require("hs.spaces")

local FONT_SIZE = 16
local BASELINE_OFFSET = -2  -- negative = down, positive = up

local menu = hs.menubar.new()

local function currentSpaceIndex()
  local screen = hs.screen.mainScreen()
  if not screen then return nil end
  local screenSpaces = spaces.spacesForScreen(screen:getUUID())
  if not screenSpaces then return nil end
  local focused = spaces.focusedSpace()
  for i, s in ipairs(screenSpaces) do
    if s == focused then return i end
  end
  return nil
end

local function update()
  if not menu then return end
  local idx = currentSpaceIndex()
  local text = idx and ("▸ " .. idx) or "▸ ?"
  menu:setTitle(hs.styledtext.new(text, {
    font = { size = FONT_SIZE },
    baselineOffset = BASELINE_OFFSET,
  }))
end

update()

local watcher = spaces.watcher.new(update)
watcher:start()

return { menu = menu, watcher = watcher }
