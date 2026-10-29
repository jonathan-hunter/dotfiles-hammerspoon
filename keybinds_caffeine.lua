-- ~/.hammerspoon/keybinds_caffeine.lua
-- Hyper+Opt+C toggles `caffeinate -s` (keep the system awake). While it is
-- running a coffee cup sits in the menu bar; clicking that also toggles it off.
--
-- The assertion lives with the child process, so there is nothing to clean up
-- beyond terminating it: the task's exit callback is the single place that
-- clears state, whether we killed it or something else did.
--
-- The menu bar item is created on activation and deleted on deactivation
-- rather than parked with removeFromMenuBar(). Detaching destroys the
-- underlying status item, and a title set on a detached item is silently lost
-- when it returns -- an item with no title still occupies the bar, so the
-- failure looks like an invisible indicator rather than a missing one.

-- Active-state indicator: the SF Symbol cup.and.saucer.fill knocked out of a
-- filled blue pill, pre-rendered by helpers/coffee-icon.swift because hs.image
-- cannot resolve symbol names itself. The cup is a transparent hole, so it
-- picks up the menu bar behind it the way a highlighted menu bar item does.
--
-- This is a colour image, NOT a template: template images are flattened to a
-- single tint, which would throw the blue away. Hence template(false) and the
-- explicit false to setIcon(), whose template argument otherwise defaults true.
local ICON_PATH = hs.configdir .. "/assets/coffee-active.png"
local ICON_SIZE = { w = 28, h = 20 }   -- points; the PNG is that at 2x
local MENUBAR_TITLE = "☕"             -- fallback if the asset is missing
local MENUBAR_TOOLTIP = "caffeinate -s active — click to allow sleep"

local function coffeeIcon()
  local icon = hs.image.imageFromPath(ICON_PATH)
  if not icon then return nil end
  return icon:setSize(ICON_SIZE):template(false)
end

local caffeineTask = nil
local caffeineMenubar = nil
local toggleCaffeine   -- forward declaration: the click callback toggles too

local function showIndicator(active)
  if active then
    if caffeineMenubar then return end
    caffeineMenubar = hs.menubar.new(true, "caffeine")
    if not caffeineMenubar then return end
    local icon = coffeeIcon()
    if icon then
      caffeineMenubar:setIcon(icon, false)
    else
      caffeineMenubar:setTitle(MENUBAR_TITLE)
    end
    caffeineMenubar:setTooltip(MENUBAR_TOOLTIP)
    caffeineMenubar:setClickCallback(function() toggleCaffeine() end)
  elseif caffeineMenubar then
    caffeineMenubar:delete()
    caffeineMenubar = nil
  end
end

local function stopCaffeine()
  if not caffeineTask then return end
  local task = caffeineTask
  caffeineTask = nil            -- before terminate, so the exit callback no-ops
  task:terminate()
  showIndicator(false)
end

local function startCaffeine()
  local task = hs.task.new("/usr/bin/caffeinate", function()
    -- Fires on our own terminate too; caffeineTask is already nil by then.
    if caffeineTask then
      caffeineTask = nil
      showIndicator(false)
      notify("Caffeinate stopped")
    end
  end, { "-s" })

  if not task or not task:start() then
    notify("Caffeinate failed to start")
    return false
  end

  caffeineTask = task
  showIndicator(true)
  return true
end

toggleCaffeine = function()
  if caffeineTask then
    stopCaffeine()
    notify("Caffeinate off")
  elseif startCaffeine() then
    notify("Caffeinate on")
  end
end

f19:bind({'alt'}, 'C', toggleCaffeine)

-- Don't leak the child across a reload or quit.
hs.shutdownCallback = stopCaffeine

-- Exported so the toggle is reachable from the console / `hs -c`.
return {
  toggle = toggleCaffeine,
  isActive = function() return caffeineTask ~= nil end,
}
