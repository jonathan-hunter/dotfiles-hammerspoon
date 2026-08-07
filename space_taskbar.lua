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

local windowApps = {}   -- windowID -> bundleID
local appNames = {}     -- bundleID -> display name (tooltip only)
local iconCache = {}    -- bundleID -> hs.image (false = known missing)
local model = {}        -- array indexed by Desktop number: { bundles = {...} }
local currentIndex = nil
local barWidth = 0      -- width of the last rendered strip, for click hit-testing

local spaceMenubar = hs.menubar.new(true, "space-taskbar")
local barCanvas = hs.canvas.new({ x = 0, y = 0, w = 10, h = BAR_HEIGHT })

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
  if not appNames[bundle] then
    appNames[bundle] = app:name() or bundle
  end
end

-- Render the strip offscreen and install it as the menu bar item's icon.
-- Pure local drawing -- no Spaces IPC -- so it is safe on the switch path.
local function render()
  if not spaceMenubar then return end
  if #model == 0 then
    barWidth = 0
    spaceMenubar:setIcon(nil)
    spaceMenubar:setTitle(currentIndex and tostring(currentIndex) or "?")
    return
  end

  local dark = hs.host.interfaceStyle() == "Dark"
  local textColor = dark and { white = 1, alpha = 1 } or { white = 0, alpha = 0.9 }
  local dimColor = dark and { white = 1, alpha = 0.4 } or { white = 0, alpha = 0.35 }

  local x = EDGE_PAD
  for _, group in ipairs(model) do
    local shown = math.min(#group.bundles, MAX_ICONS_PER_SPACE)
    local extra = #group.bundles - shown
    group._shown, group._extra, group._x = shown, extra, x
    local w = NUMBER_WIDTH + shown * (ICON_SIZE + ICON_GAP)
    if extra > 0 then w = w + 8 + 5 * #tostring(extra) end
    group._w = w
    x = x + w + GROUP_GAP
  end
  local totalWidth = x - GROUP_GAP + EDGE_PAD
  barWidth = totalWidth

  local elements = {}
  for i, group in ipairs(model) do
    if i == currentIndex then
      elements[#elements + 1] = {
        type = "rectangle", action = "fill",
        roundedRectRadii = { xRadius = 5, yRadius = 5 },
        fillColor = { red = 0.3, green = 0.55, blue = 1.0, alpha = 0.35 },
        frame = { x = group._x - 3, y = 1, w = group._w + 5, h = BAR_HEIGHT - 2 },
      }
    end
  end
  for i, group in ipairs(model) do
    elements[#elements + 1] = {
      type = "text", text = tostring(i),
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

  barCanvas:size({ w = totalWidth, h = BAR_HEIGHT })
  barCanvas:replaceElements(table.unpack(elements))
  local img = barCanvas:imageFromCanvas()
  if img then
    spaceMenubar:setTitle(nil)
    spaceMenubar:setIcon(img, false)
  end
  -- The tooltip carries the app names the removed dropdown used to spell out.
  local tooltip = "Spaces"
  if currentIndex then
    tooltip = "Current Space: " .. currentIndex
    local names = {}
    for _, bundle in ipairs(model[currentIndex] and model[currentIndex].bundles or {}) do
      names[#names + 1] = appNames[bundle] or bundle
    end
    if #names > 0 then tooltip = tooltip .. " (" .. table.concat(names, ", ") .. ")" end
  end
  spaceMenubar:setTooltip(tooltip)
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
    local ok, wins = pcall(spaces.windowsForSpace, spaceId)
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

-- Full model rebuild: render immediately from what AX and past sweeps know,
-- then refine asynchronously once the helper reports windows on other Spaces.
local function rebuildModel()
  for _, win in ipairs(hs.window.orderedWindows()) do
    rememberWindow(win)
  end

  if helperAvailable and not helperTask then
    helperTask = hs.task.new(HELPER_BIN, function(exitCode, stdOut)
      helperTask = nil
      if exitCode == 0 and stdOut then
        local reported = {}
        for id, bundle, name in stdOut:gmatch("(%d+)\t([^\t\n]+)\t([^\n]+)") do
          local wid = tonumber(id)
          if wid then
            reported[wid] = true
            windowApps[wid] = bundle
            if not appNames[bundle] then appNames[bundle] = name end
          end
        end
        -- Prune windows the helper no longer reports: Electron apps hide
        -- their window on close instead of destroying it, so windowDestroyed
        -- never fires and a stale entry would keep the app's icon alive.
        -- Keep anything AX still sees so a window created after the helper
        -- snapshot doesn't flicker out.
        for _, win in ipairs(hs.window.orderedWindows()) do
          local ok, id = pcall(win.id, win)
          if ok and id then reported[id] = true end
        end
        for wid in pairs(windowApps) do
          if not reported[wid] then windowApps[wid] = nil end
        end
        placeAndRender()
      end
    end)
    if not helperTask:start() then helperTask = nil end
  end

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

-- Map an absolute mouse x onto the rendered strip. render() records where it
-- drew each group and how many icons fitted, so the offset maps straight back
-- to a Desktop and, when the click landed on an icon, that icon's bundle ID.
-- The status item pads the image it is handed, so the left inset is measured
-- from the live frame rather than assumed.
local function hitTest(mouseX)
  if barWidth <= 0 then return nil end
  local frame = spaceMenubar and spaceMenubar:frame()
  if not frame then return nil end
  local x = mouseX - frame.x - (frame.w - barWidth) / 2

  for i, group in ipairs(model) do
    if group._x and x >= group._x - GROUP_GAP / 2
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
    local ok, wins = pcall(spaces.windowsForSpace, spaceId)
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

spaceMenubar:setClickCallback(function()
  local pos = hs.mouse.absolutePosition()
  if not pos then return end
  local index, bundle = hitTest(pos.x)
  if not index then return end

  local cur = spaceState.currentSpace()
  if cur and cur.index == index then
    if bundle then focusAppOnSpace(bundle, index) end
    return
  end
  if index > 9 then return end  -- ctrl+N only addresses the first nine Desktops

  hs.eventtap.keyStroke({ "ctrl" }, tostring(index), 0)
  if bundle then
    hs.timer.doAfter(SPACE_FOCUS_DELAY, function()
      focusAppOnSpace(bundle, index)
    end)
  end
end)

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
  menubar = spaceMenubar,
  canvas = barCanvas,
  refreshTimer = refreshTimer,
  switchRebuildTimer = switchRebuildTimer,
  windowFilter = windowFilter,
}
