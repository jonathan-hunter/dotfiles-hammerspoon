-- Every 5 min while Mail is running, and whenever Mail is focused, mark Junk as read via an AppleScript.
local script = hs.configdir .. "/helpers/mark_junk_read.applescript"
-- Non-junk mailboxes to also mark read, one "Account/Mailbox" per line. Gitignored
-- so account names stay out of the repo; missing file = junk folders only.
local extrasFile = hs.configdir .. "/helpers/mail_extra_mailboxes.txt"

local function extraMailboxes()
  local extras = {}
  local f = io.open(extrasFile)
  if not f then return extras end
  for raw in f:lines() do
    local line = raw:match("^%s*(.-)%s*$")
    if line ~= "" and not line:match("^#") then table.insert(extras, line) end
  end
  f:close()
  return extras
end

local function markJunkRead()
  if hs.application.get("Mail") then
    local args = { script }
    for _, mb in ipairs(extraMailboxes()) do table.insert(args, mb) end
    hs.task.new("/usr/bin/osascript", function(code, _, err)
      if code ~= 0 then print("mail_junk: " .. err) end -- e.g. a typo in the extras file
    end, args):start()
  end
end

mailJunkTimer = hs.timer.doEvery(300, markJunkRead) -- 300 s; global to avoid GC

-- Also on every switch to Mail. Global to avoid GC.
mailJunkWatcher = hs.application.watcher.new(function(name, event)
  if name == "Mail" and event == hs.application.watcher.activated then
    markJunkRead()
  end
end):start()
