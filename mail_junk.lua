-- Every 5 min while Mail is running, and whenever Mail is focused, mark Junk as read via an AppleScript.
local script = hs.configdir .. "/helpers/mark_junk_read.applescript"

local function markJunkRead()
  if hs.application.get("Mail") then
    hs.task.new("/usr/bin/osascript", nil, { script }):start()
  end
end

mailJunkTimer = hs.timer.doEvery(300, markJunkRead) -- 300 s; global to avoid GC

-- Also on every switch to Mail. Global to avoid GC.
mailJunkWatcher = hs.application.watcher.new(function(name, event)
  if name == "Mail" and event == hs.application.watcher.activated then
    markJunkRead()
  end
end):start()
