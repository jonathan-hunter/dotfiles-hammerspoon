-- ~/.hammerspoon/keybind_finder.lua

-- Hypr + F keybinding to launch or focus Finder window.
f19:bind({}, 'F', function()
  -- 1. Define the AppleScript
  local script = [[
    tell application "Finder"
        if (count of windows) > 0 then
            activate
        else
            make new Finder window to (POSIX file (do shell script "echo $HOME") as text)
            activate
        end if
    end tell
  ]]

  -- 2. Execute the script and capture the result
  local ok, result = hs.applescript.applescript(script)

  -- 3. Handle result
  if not ok then
    hs.alert.show("Finder error: " .. tostring(result))
  end
end)