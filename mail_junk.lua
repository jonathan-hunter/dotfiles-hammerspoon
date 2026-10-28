-- Every 5 min, while Mail is running, mark Junk as read via an AppleScript.
local script = os.getenv("HOME") .. "/Scripts/mark_junk_read.applescript"

local function markJunkRead()
  if hs.application.get("Mail") then
    hs.task.new("/usr/bin/osascript", nil, { script }):start()
  end
end

mailJunkTimer = hs.timer.doEvery(300, markJunkRead) -- 300 s; global to avoid GC
