-- ~/.hammerspoon/keybinds_special.lua

-- Reload Hammerspoon config (custom handler, not a standard app launch)
f19:bind({'shift'}, 'R', function()
  hs.alert.show("Config reloaded")
  hs.timer.doAfter(0.05, hs.reload)
end)

-- Hyper+Shift+Opt+Q - run the "Quit All Apps" Shortcut. Async hs.task:
-- a synchronous run would block the Lua loop -- including
-- the F19 key-up callback -- while the hyper key is held.
f19:bind({'shift', 'alt'}, 'Q', function()
  hs.task.new("/usr/bin/shortcuts", function(exitCode)
    if exitCode ~= 0 then
      hs.alert.show("Quit All Apps shortcut failed")
    end
  end, { "run", "Quit All Apps" }):start()
end)

-- F13 special binding - Screenshot (Clipboard)
hs.hotkey.bind({}, "F13", function()
  hs.eventtap.keyStroke({"shift", "cmd"}, "4")
end)

-- F14 special binding - Caps Lock (Claude Voice Mode)
hs.hotkey.bind({}, "F14", function()
  hs.hid.capslock.toggle()
end)

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