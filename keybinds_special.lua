-- ~/.hammerspoon/keybinds_special.lua

-- Reload Hammerspoon config (custom handler, not a standard app launch)
f19:bind({'alt'}, 'R', function()
  notify("Config reloaded")
  hs.timer.doAfter(0.05, hs.reload)
end)

-- Hyper+Shift+Opt+Q - run the "Quit All Apps" Shortcut. Async hs.task:
-- a synchronous run would block the Lua loop -- including
-- the F19 key-up callback -- while the hyper key is held.
f19:bind({'shift', 'alt'}, 'Q', function()
  hs.task.new("/usr/bin/shortcuts", function(exitCode)
    if exitCode ~= 0 then
      notify("Quit All Apps shortcut failed")
    end
  end, { "run", "Quit All Apps" }):start()
end)

-- Hyper+Shift+Opt+K - restart Karabiner-Elements. Kickstarts the two user
-- agents that do the remapping, not the settings UI (quitting that app leaves
-- the engine running and fixes nothing). No sudo: the privileged grabber
-- daemon survives, only the session-side agents are recycled. Same async
-- hs.task reasoning as the binding above. Note the hyperkey itself is
-- Karabiner's caps->F19 mapping, so this can only fire while it still works.
f19:bind({'shift', 'alt'}, 'K', function()
  hs.task.new("/bin/sh", function(exitCode)
    notify(exitCode == 0 and "Karabiner restarted" or "Karabiner restart failed")
  end, { "-c", "for a in Karabiner-Core-Service-rev2 karabiner_console_user_server; do " ..
                 "launchctl kickstart -k \"gui/$(id -u)/org.pqrs.service.agent.$a\" || exit 1; done" }):start()
end)

-- F13 special binding - Screenshot (Clipboard)
hs.hotkey.bind({}, "F13", function()
  hs.eventtap.keyStroke({"shift", "cmd"}, "4")
end)

-- F14 special binding - Caps Lock (Claude Voice Mode)
hs.hotkey.bind({}, "F14", function()
  hs.hid.capslock.toggle()
end)

-- Cmd+Shift+Return - open a new line above the caret (line start, Return, Up).
-- Waits for the physical cmd+shift to be released first: Firefox merges held
-- modifiers into the synthetic keys, so firing early made it flaky there.
-- ponytail: global bind, so it shadows apps with their own Cmd+Shift+Return
-- (add a frontmost-app check if so).
local function newLineAbove(tries)
  local m = hs.eventtap.checkKeyboardModifiers()
  if (m.cmd or m.shift) and tries < 50 then
    return hs.timer.doAfter(0.01, function() newLineAbove(tries + 1) end)
  end
  hs.eventtap.keyStroke({"cmd"}, "left", 20000)
  hs.timer.doAfter(0.03, function()
    hs.eventtap.keyStroke({}, "return", 20000)
    hs.timer.doAfter(0.03, function() hs.eventtap.keyStroke({}, "up", 20000) end)
  end)
end
hs.hotkey.bind({"cmd", "shift"}, "return", function() newLineAbove(0) end)

-- Cmd+Shift+V - Paste as plain text (preserves original clipboard)
hs.hotkey.bind({"cmd", "shift"}, "V", function()
  local original = hs.pasteboard.readAllData()
  local text = hs.pasteboard.getContents()
  if text and original then
    hs.pasteboard.setContents(text)
    hs.timer.doAfter(0.20, function()
      hs.eventtap.keyStroke({"cmd"}, "v")
      hs.timer.doAfter(0.10, function()
        hs.pasteboard.writeAllData(original)
      end)
    end)
  end
end)