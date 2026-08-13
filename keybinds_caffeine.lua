-- ~/.hammerspoon/keybinds_caffeine.lua
-- Hyper+Opt+C toggles `caffeinate -s` (keep the system awake). While it is
-- running a coffee cup sits in the menu bar; clicking that also toggles it off.
--
-- The assertion lives with the child process, so there is nothing to clean up
-- beyond terminating it: the task's exit callback is the single place that
-- clears state, whether we killed it or something else did.

local MENUBAR_TITLE = "☕"

local caffeineTask = nil
local caffeineMenubar = hs.menubar.new(true, "caffeine")

if caffeineMenubar then
  caffeineMenubar:removeFromMenuBar()
  caffeineMenubar:setTitle(MENUBAR_TITLE)
  caffeineMenubar:setTooltip("caffeinate -s active — click to allow sleep")
end

local function showIndicator(active)
  if not caffeineMenubar then return end
  if active then
    caffeineMenubar:returnToMenuBar()
  else
    caffeineMenubar:removeFromMenuBar()
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
      hs.alert.show("Caffeinate stopped")
    end
  end, { "-s" })

  if not task or not task:start() then
    hs.alert.show("Caffeinate failed to start")
    return false
  end

  caffeineTask = task
  showIndicator(true)
  return true
end

local function toggleCaffeine()
  if caffeineTask then
    stopCaffeine()
    hs.alert.show("Caffeinate off")
  elseif startCaffeine() then
    hs.alert.show("Caffeinate on")
  end
end

if caffeineMenubar then
  caffeineMenubar:setClickCallback(toggleCaffeine)
end

f19:bind({'alt'}, 'C', toggleCaffeine)

-- Don't leak the child across a reload or quit.
hs.shutdownCallback = stopCaffeine

-- Exported so the toggle is reachable from the console / `hs -c`.
return {
  toggle = toggleCaffeine,
  isActive = function() return caffeineTask ~= nil end,
}
