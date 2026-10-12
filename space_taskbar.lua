-- ~/.hammerspoon/space_taskbar.lua
-- Menu bar taskbar: real app icons grouped by Mission Control Desktop, with
-- the current Space highlighted. Clicking acts directly on whatever is under
-- the pointer -- an app icon switches to its Desktop and focuses that app,
-- the rest of a group just switches to the Desktop -- so there is no menu.
--
-- Two data sources drive rendering:
--   * a windowID -> app map. AX (hs.window) only sees windows on the current
--     Space, so the map is seeded and refined by helpers/windowlist -- a small
--     compiled Swift helper whose CGWindowList query sees every Space -- run
--     asynchronously via hs.task, with hs.window.filter events keeping the
--     current Space fresh in between.
--   * hs.spaces.windowsForSpace() placement lookups (SkyLight), which work
--     for all Spaces. These run only from debounced timers, never during a
--     Space transition.

local spaces = require("hs.spaces")
local spaceState = require("space_state")

local REFRESH_DEBOUNCE = 0.4      -- coalesce window-event rebuilds
local SWITCH_REBUILD_DELAY = 0.6  -- rebuild after a Space transition settles

local BAR_HEIGHT = 22
local ICON_SIZE = 22  -- full status-bar thickness; app icons' built-in
                      -- transparent margins make this read like ~18px
local ICON_GAP = 2
local NUMBER_WIDTH = 12
local NUMBER_TEXT_SIZE = 14   -- matches the menu bar clock
local NUMBER_FONT = ".AppleSystemUIFont"
local GROUP_GAP = 7
local EDGE_PAD = 3
local MAX_ICONS_PER_SPACE = 4     -- overflow renders as an unclickable "+n"
local NOTCH_WIDTH = 220              -- calibration knob: notch (~200pt) plus breathing room

local windowApps = {}   -- windowID -> bundleID
local iconCache = {}    -- bundleID -> hs.image (false = known missing)
local model = {}        -- array indexed by Desktop number: { bundles = {...} }
local currentIndex = nil

local halfCanvases = {}   -- [1] left / [2] right of the notch, built lazily

local function appIcon(bundle)
  local icon = iconCache[bundle]
  if icon == nil then
    icon = hs.image.imageFromAppBundle(bundle) or false
    iconCache[bundle] = icon
  end
  return icon or nil
end

local function rememberWindow(win)
  if not win then return end
  local okStd, standard = pcall(win.isStandard, win)
  if not okStd or not standard then return end
  local okId, id = pcall(win.id, win)
  if not okId or not id then return end
  local app = win:application()
  local bundle = app and app:bundleID()
  if not bundle then return end
  windowApps[id] = bundle
end

-- The built-in screen if it has a notch (its menu bar is 33pt tall, vs 24).
local function notchScreen()
  for _, scr in ipairs(hs.screen.allScreens()) do
    if scr:name():find("Built%-in") and scr:frame().y - scr:fullFrame().y >= 30 then
      return scr
    end
  end
end

-- Assign x/width to groups[first..last], recording which half they sit in.
-- Returns the strip's total width.
local function layout(first, last, half)
  local x = EDGE_PAD
  for i = first, last do
    local group = model[i]
    local shown = math.min(#group.bundles, MAX_ICONS_PER_SPACE)
    local extra = #group.bundles - shown
    group._shown, group._extra, group._x, group._half = shown, extra, x, half
    local w = NUMBER_WIDTH + shown * (ICON_SIZE + ICON_GAP)
    if extra > 0 then w = w + 8 + 5 * #tostring(extra) end
    group._w = w
    x = x + w + GROUP_GAP
  end
  return x - GROUP_GAP + EDGE_PAD
end

local function buildElements(first, last)
  -- Always light-on-dark: the menu bar sits over a dark wallpaper in both appearances.
  local textColor = { white = 1, alpha = 1 }
  local dimColor = { white = 1, alpha = 0.4 }

  local elements = {}
  for i = first, last do
    if i == currentIndex then
      local group = model[i]
      elements[#elements + 1] = {
        type = "rectangle", action = "fill",
        roundedRectRadii = { xRadius = 5, yRadius = 5 },
        fillColor = { red = 0.3, green = 0.55, blue = 1.0, alpha = 0.35 },
        frame = { x = group._x - 3, y = 1, w = group._w + 5, h = BAR_HEIGHT - 2 },
      }
    end
  end
  for i = first, last do
    local group = model[i]
    elements[#elements + 1] = {
      type = "text", text = tostring(i % 10),  -- Desktop 10 reads as 0, matching ctrl+0
      textSize = NUMBER_TEXT_SIZE, textFont = NUMBER_FONT,
      textColor = (group._shown > 0 or i == currentIndex) and textColor or dimColor,
      frame = { x = group._x, y = 2, w = NUMBER_WIDTH, h = 18 },
    }
    local ix = group._x + NUMBER_WIDTH
    for s = 1, group._shown do
      local icon = appIcon(group.bundles[s])
      if icon then
        elements[#elements + 1] = {
          type = "image", image = icon, imageScaling = "scaleProportionally",
          frame = { x = ix, y = (BAR_HEIGHT - ICON_SIZE) / 2, w = ICON_SIZE, h = ICON_SIZE },
        }
      end
      ix = ix + ICON_SIZE + ICON_GAP
    end
    if group._extra > 0 then
      elements[#elements + 1] = {
        type = "text", text = "+" .. group._extra, textSize = 9,
        textColor = dimColor,
        frame = { x = ix, y = 6, w = 8 + 5 * #tostring(group._extra), h = 12 },
      }
    end
  end
  return elements
end

local handleClick  -- defined with the click code below

-- Draw the Desktops into borderless canvases on the menu bar. On a notched
-- screen they split into two halves hugging either side of the notch; on any
-- other screen (external display) one strip is centred. Canvases get no
-- status-item placement, so they are positioned from the screen frame, and
-- clicks arrive in canvas-local x.
local function render()
  -- A full-screen app's Space has no menu bar to sit in, so stand aside there.
  local fullscreen = spaces.spaceType(spaces.focusedSpace()) == "fullscreen"
  local notch = notchScreen()
  local scr = notch or hs.screen.primaryScreen()
  local full = scr:fullFrame()
  local menuH = math.max(scr:frame().y - full.y, BAR_HEIGHT)  -- 0 when auto-hidden
  local mid = notch and math.ceil(#model / 2) or #model
  local ranges = notch and { { 1, mid }, { mid + 1, #model } } or { { 1, #model } }
  for half = 1, 2 do
    local r = ranges[half]
    local cv = halfCanvases[half]
    if not cv then
      cv = hs.canvas.new({ x = 0, y = 0, w = 10, h = BAR_HEIGHT })
      cv:level(hs.canvas.windowLevels.status)
      -- "transient" (not "stationary") so macOS hides it in Mission Control
      cv:behavior({ "canJoinAllSpaces", "transient" })
      cv:clickActivating(false)
      cv:mouseCallback(function(_, msg, _, x) if msg == "mouseUp" then handleClick(x, half) end end)
      halfCanvases[half] = cv
    end
    if fullscreen or not r or r[1] > r[2] then
      cv:hide()
    else
      local w = layout(r[1], r[2], half)
      local elements = buildElements(r[1], r[2])
      -- near-invisible backing so clicks in the gaps land on the canvas, not through it
      table.insert(elements, 1, {
        type = "rectangle", action = "fill", fillColor = { white = 0, alpha = 0.01 },
        frame = { x = 0, y = 0, w = w, h = BAR_HEIGHT }, trackMouseUp = true,
      })
      local cx = (full.w - w) / 2
      if notch then
        cx = half == 1 and (full.w / 2 - NOTCH_WIDTH / 2 - w) or (full.w / 2 + NOTCH_WIDTH / 2)
      end
      cv:frame({ x = full.x + cx, y = full.y + (menuH - BAR_HEIGHT) / 2, w = w, h = BAR_HEIGHT })
      cv:replaceElements(table.unpack(elements))
      cv:show()
    end
  end
end

-- Place every known window via SkyLight and re-render. Costs one
-- windowsForSpace call per Desktop, so it only runs from debounced timers.
-- A window reported on more than one Desktop is sticky -- e.g. a Meet
-- picture-in-picture pop-out, which joins all Spaces -- and says nothing
-- about where its app actually lives, so it is excluded from every group.
local function placeAndRender()
  local userIds = spaceState.userSpaces()
  local perSpace, spaceCount = {}, {}
  for i, spaceId in ipairs(userIds or {}) do
    local ok, wins = pcall(spaceState.windowsForSpace, spaceId)
    wins = (ok and type(wins) == "table") and wins or {}
    perSpace[i] = wins
    for _, wid in ipairs(wins) do
      spaceCount[wid] = (spaceCount[wid] or 0) + 1
    end
  end

  local rebuilt = {}
  for i, wins in ipairs(perSpace) do
    local bundles, seen = {}, {}
    for _, wid in ipairs(wins) do
      local bundle = spaceCount[wid] == 1 and windowApps[wid] or nil
      if bundle and not seen[bundle] then
        seen[bundle] = true
        bundles[#bundles + 1] = bundle
      end
    end
    rebuilt[i] = { bundles = bundles }
  end
  model = rebuilt
  render()
end

-- CGWindowList helper: sees windows on every Space, unlike AX. Compiled from
-- helpers/windowlist.swift at load if the binary is missing.
local HELPER_BIN = hs.configdir .. "/helpers/windowlist"
local HELPER_SRC = hs.configdir .. "/helpers/windowlist.swift"
local helperAvailable = hs.fs.attributes(HELPER_BIN, "mode") == "file"
local helperTask = nil
local compileTask = nil

-- Remember every window AX sees (the current Space). With `reported`, also
-- mark each one so the prune below keeps it.
local function sweepAX(reported)
  for _, win in ipairs(hs.window.orderedWindows()) do
    rememberWindow(win)
    if reported then
      local ok, id = pcall(win.id, win)
      if ok and id then reported[id] = true end
    end
  end
end

-- Full model rebuild from AX plus the helper's all-Spaces report. The AX
-- sweep (~20-35ms) and placement run once, in the helper's callback, rather
-- than once before it and again after; without the helper they run now.
local function rebuildModel()
  if helperAvailable and not helperTask then
    helperTask = hs.task.new(HELPER_BIN, function(exitCode, stdOut)
      helperTask = nil
      local reported = nil
      if exitCode == 0 and stdOut then
        reported = {}
        for id, bundle in stdOut:gmatch("(%d+)\t([^\t\n]+)\t[^\n]+") do
          local wid = tonumber(id)
          if wid then
            reported[wid] = true
            windowApps[wid] = bundle
          end
        end
      end
      -- Swept after the helper's snapshot, so a window created since then is
      -- still marked and doesn't flicker out in the prune.
      sweepAX(reported)
      if reported then
        -- Prune windows the helper no longer reports: Electron apps hide
        -- their window on close instead of destroying it, so windowDestroyed
        -- never fires and a stale entry would keep the app's icon alive.
        for wid in pairs(windowApps) do
          if not reported[wid] then windowApps[wid] = nil end
        end
      end
      placeAndRender()
    end)
    if helperTask:start() then return end  -- the callback sweeps and renders
    helperTask = nil
  end

  sweepAX()
  placeAndRender()
end

local refreshTimer = hs.timer.delayed.new(REFRESH_DEBOUNCE, rebuildModel)
local switchRebuildTimer = hs.timer.delayed.new(SWITCH_REBUILD_DELAY, rebuildModel)

if not helperAvailable and hs.fs.attributes(HELPER_SRC, "mode") == "file" then
  compileTask = hs.task.new("/usr/bin/swiftc", function(exitCode)
    compileTask = nil
    if exitCode == 0 then
      helperAvailable = true
      refreshTimer:start()
    else
      print("[space_taskbar] failed to compile helpers/windowlist.swift; " ..
            "taskbar will only learn Spaces as you visit them")
    end
  end, { "-O", "-o", HELPER_BIN, HELPER_SRC })
  compileTask:start()
end

-- Clicking ------------------------------------------------------------------

-- Delay before focusing a window after a ctrl+N Space switch: AX needs the
-- transition to settle before the destination Desktop's windows are reachable.
local SPACE_FOCUS_DELAY = 0.30
-- Electron apps build their accessibility tree lazily and can answer the first
-- query after an idle period with an empty list; re-ask once before giving up.
local AX_RETRY_DELAY = 0.15

-- Map an x offset within a rendered strip (`half` 1 or 2) onto a Desktop and,
-- when it landed on an icon, that icon's bundle ID. render() records where it
-- drew each group and how many icons fitted, so the offset maps straight back.
local function hitTest(x, half)
  for i, group in ipairs(model) do
    if group._half == half and group._x and x >= group._x - GROUP_GAP / 2
        and x < group._x + group._w + GROUP_GAP / 2 then
      local ix = group._x + NUMBER_WIDTH
      for s = 1, (group._shown or 0) do
        if x >= ix and x < ix + ICON_SIZE + ICON_GAP then
          return i, group.bundles[s]
        end
        ix = ix + ICON_SIZE + ICON_GAP
      end
      return i  -- the number, or the "+n" overflow: Desktop only
    end
  end
  return nil
end

-- The app's standard, non-minimized windows on Desktop `index`, frontmost
-- first. AX reports an app's windows on every Space, so it is the Desktop's
-- SkyLight window-id set that confines the result to the one clicked.
local function appWindowsOnSpace(bundle, index)
  local app = hs.application.get(bundle)
  if not app then return nil, {} end

  local userIds = spaceState.userSpaces()
  local spaceId = userIds and userIds[index]
  local onSpace = nil
  if spaceId then
    local ok, wins = pcall(spaceState.windowsForSpace, spaceId)
    if ok and type(wins) == "table" then
      onSpace = {}
      for _, wid in ipairs(wins) do onSpace[wid] = true end
    end
  end

  local found = {}
  for _, win in ipairs(app:allWindows()) do
    local ok, id = pcall(win.id, win)
    if ok and id and (not onSpace or onSpace[id])
        and win:isStandard() and not win:isMinimized() then
      found[#found + 1] = win
    end
  end
  return app, found
end

local function focusAppOnSpace(bundle, index)
  local app, wins = appWindowsOnSpace(bundle, index)
  if not app then return end
  if wins[1] then
    wins[1]:focus()
    return
  end
  hs.timer.doAfter(AX_RETRY_DELAY, function()
    local retryApp, retryWins = appWindowsOnSpace(bundle, index)
    if retryWins[1] then
      retryWins[1]:focus()
    elseif retryApp then
      retryApp:activate()  -- windows unreachable; at least raise the app
    end
  end)
end

handleClick = function(x, half)
  local index, bundle = hitTest(x, half)
  if not index then return end

  local cur = spaceState.currentSpace()
  if cur and cur.index == index then
    if bundle then focusAppOnSpace(bundle, index) end
    return
  end
  if index > 10 then return end  -- ctrl+N/ctrl+0 only address the first ten Desktops

  hs.eventtap.keyStroke({ "ctrl" }, tostring(index % 10), 0)
  if bundle then
    hs.timer.doAfter(SPACE_FOCUS_DELAY, function()
      focusAppOnSpace(bundle, index)
    end)
  end
end

-- Screens coming and going (lid close, external display) flip split vs centred.
local screenWatcher = hs.screen.watcher.new(function() refreshTimer:start() end)
screenWatcher:start()

-- Called by space_hud whenever the current Space index changes (tap fast-path,
-- watcher, or verify timer). Only moves the highlight -- no IPC -- then
-- schedules a rebuild for after the transition, since windows may have moved.
local function setCurrentIndex(idx)
  if idx == false then idx = nil end
  if idx ~= currentIndex then
    currentIndex = idx
    render()
  end
  switchRebuildTimer:start()
end

local windowFilter = hs.window.filter.default
windowFilter:subscribe({
  hs.window.filter.windowCreated,
  hs.window.filter.windowVisible,
  hs.window.filter.windowNotVisible,
  hs.window.filter.windowMinimized,
  hs.window.filter.windowUnminimized,
  hs.window.filter.windowHidden,
  hs.window.filter.windowUnhidden,
}, function(win)
  rememberWindow(win)
  refreshTimer:start()
end)

windowFilter:subscribe(hs.window.filter.windowDestroyed, function(win)
  if win then
    local ok, id = pcall(win.id, win)
    if ok and id then windowApps[id] = nil end
  end
  refreshTimer:start()
end)

-- Initial build once config load has finished.
refreshTimer:start()

return {
  setCurrentIndex = setCurrentIndex,
  refresh = rebuildModel,
  getModel = function() return model end,
  -- exported for programmatic testing of click targeting via the hs IPC CLI
  hitTest = hitTest,
  -- keeps the in-flight hs.task objects reachable so they aren't collected
  getTasks = function() return helperTask, compileTask end,
  halfCanvases = halfCanvases,
  screenWatcher = screenWatcher,
  refreshTimer = refreshTimer,
  switchRebuildTimer = switchRebuildTimer,
  windowFilter = windowFilter,
}
