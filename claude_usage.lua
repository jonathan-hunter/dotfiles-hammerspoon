-- ~/.hammerspoon/claude_usage.lua
-- Menu bar readout of Claude plan usage: "<spark> 5h% · 7d%". Click to focus Claude
-- (and refresh).
--
-- Data comes from the same endpoint Claude Code's /usage calls. It is
-- undocumented, so a shape change shows up as a failure (see fail()). The
-- OAuth token is read from the Keychain item Claude Code maintains; we never
-- refresh it ourselves, so if Claude Code hasn't run in a while the token may
-- be expired and fetches fail with HTTP 401 until Claude Code refreshes it.
-- The first Keychain read prompts -- choose "Always Allow".

local USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
local KEYCHAIN_SERVICE = "Claude Code-credentials"
local REFRESH_INTERVAL = 300   -- seconds
-- The endpoint rate-limits hard (429 with retry-after of minutes), so clicks
-- only refetch if the last fetch is at least this old.
local CLICK_REFRESH_MIN_GAP = 60   -- seconds
local TOOLTIP = "Claude usage: 5-hour · 7-day — click to open Claude"

-- The Claude desktop app's own macOS tray template: a 16pt spark in a 24pt
-- canvas, so it sits like any other status item. Referenced in place rather
-- than copied, falling back to a text spark if the app isn't installed.
local ICON_PATH = "/Applications/Claude.app/Contents/Resources/TrayIconTemplate@2x.png"
local ICON_SIZE = { w = 24, h = 24 }   -- points; the PNG is that at 2x

local menubar = hs.menubar.new(true, "claude-usage")
local icon = hs.image.imageFromPath(ICON_PATH)
local prefix = ""
if icon then
  menubar:setIcon(icon:setSize(ICON_SIZE), true)
else
  prefix = "✳ "
end

local function setTitle(text) menubar:setTitle(prefix .. text) end

local function pct(window)
  return window and window.utilization and math.floor(window.utilization + 0.5) or "–"
end

local hasReading = false   -- once true, failures keep the last numbers on show
local lastFetch = 0

-- A failed fetch leaves a good reading in place (minutes-old usage beats "?")
-- and says why in the tooltip; "?" only shows if nothing has succeeded yet.
local function fail(reason)
  if hasReading then
    menubar:setTooltip(TOOLTIP .. "\nLast update failed: " .. reason)
  else
    setTitle("?")
    menubar:setTooltip(TOOLTIP .. "\n" .. reason)
  end
end

local function refresh()
  lastFetch = hs.timer.secondsSinceEpoch()
  hs.task.new("/usr/bin/security", function(_, out)
    local ok, creds = pcall(hs.json.decode, out)
    local token = ok and creds and creds.claudeAiOauth and creds.claudeAiOauth.accessToken
    if not token then
      if not hasReading then setTitle("–") end
      menubar:setTooltip(TOOLTIP .. "\nNo Claude Code token in the Keychain")
      return
    end
    hs.http.asyncGet(USAGE_URL,
      { Authorization = "Bearer " .. token, ["anthropic-beta"] = "oauth-2025-04-20" },
      function(status, body)
        if status ~= 200 then return fail("HTTP " .. status) end
        local okBody, u = pcall(hs.json.decode, body)
        if not okBody or not u then return fail("unreadable response") end
        hasReading = true
        setTitle(string.format("%s%% · %s%%", pct(u.five_hour), pct(u.seven_day)))
        menubar:setTooltip(TOOLTIP)
      end)
  end, { "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w" }):start()
end

setTitle("…")
menubar:setTooltip(TOOLTIP)
menubar:setClickCallback(function()
  hs.application.launchOrFocus("Claude")
  require("hyperkey").settleApp("Claude")   -- hops to its Desktop if elsewhere
  if hs.timer.secondsSinceEpoch() - lastFetch >= CLICK_REFRESH_MIN_GAP then refresh() end
end)
local timer = hs.timer.doEvery(REFRESH_INTERVAL, refresh)
refresh()

-- Returned (and so held by package.loaded) to keep the timer from being collected.
return { refresh = refresh, timer = timer }
