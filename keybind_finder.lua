-- ~/.hammerspoon/keybind_finder.lua

-- Hyper + F: focus Finder, opening a new window at $HOME if none are open.
f19:bind({}, 'F', function()
  local finder = hs.application.get("com.apple.finder")

  -- Fast path: Finder already has a real window open, so just focus it. This is
  -- the common case and avoids a synchronous Apple Event that would block the
  -- single-threaded Lua loop while Finder responds. isStandard() excludes the
  -- desktop, which is itself a (non-standard) Finder window.
  if finder then
    for _, w in ipairs(finder:allWindows()) do
      if w:isStandard() and w:isVisible() then
        finder:activate()
        return
      end
    end
  end

  -- Slow path: no Finder window open, so create one at $HOME. Building the path
  -- with os.getenv avoids the old embedded `do shell script "echo $HOME"`, which
  -- spawned a subprocess from inside the (already blocking) Apple Event.
  local home = os.getenv("HOME")
  local script = ([[
    tell application "Finder"
        if (count of windows) > 0 then
            activate
        else
            make new Finder window to (POSIX file "%s" as text)
            activate
        end if
    end tell
  ]]):format(home)

  local ok, result = hs.applescript.applescript(script)
  if not ok then
    hs.alert.show("Finder error: " .. tostring(result))
  end
end)