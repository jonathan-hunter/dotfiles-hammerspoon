-- ~/.hammerspoon/hotcorner.lua
-- Lower-right hot corner: new Bear note. Fires once on entry; re-arms when the mouse leaves.
-- bear://x-callback-url/create with no params is silently ignored, so instead
-- bring Bear forward (hopping Spaces like Hyper+C) and send it cmd+N.

local NEW_NOTE_TIMEOUT = 3  -- seconds to wait for Bear to come forward

local inCorner = false

local function newBearNote()
  hs.application.launchOrFocus("Bear")
  require("hyperkey").settleApp("Bear")
  local deadline = hs.timer.secondsSinceEpoch() + NEW_NOTE_TIMEOUT
  hs.timer.waitUntil(function()
    local front = hs.application.frontmostApplication()
    return (front and front:name() == "Bear" and front:focusedWindow() ~= nil)
      or hs.timer.secondsSinceEpoch() > deadline
  end, function()
    local front = hs.application.frontmostApplication()
    if front and front:name() == "Bear" then
      hs.eventtap.keyStroke({ "cmd" }, "n", 0, front)
    end
  end, 0.1)
end

local tap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function()
  local p = hs.mouse.absolutePosition()
  local f = hs.mouse.getCurrentScreen():fullFrame()
  local now = p.x >= f.x + f.w - 1 and p.y >= f.y + f.h - 1
  if now and not inCorner then newBearNote() end
  inCorner = now
  return false
end)
tap:start()

return tap  -- held in package.loaded so the tap isn't garbage collected
