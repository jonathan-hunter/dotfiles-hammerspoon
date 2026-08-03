-- ~/.hammerspoon/space_state.lua
-- Shared, cached Mission Control Space lookups for Desktop/HUD numbering.

local spaces = require("hs.spaces")

local cacheByUUID = {}

local function screenUUID(screen)
  if type(screen) == "string" then return screen end
  return screen and screen:getUUID() or nil
end

local function buildCache(screen)
  local uuid = screenUUID(screen)
  if not uuid then return nil end

  local allIds = spaces.spacesForScreen(uuid)
  if not allIds then return nil end

  -- macOS's ctrl+N shortcuts address regular Desktop spaces, not full-screen
  -- application spaces. Keep both lists so the HUD can retain Mission Control
  -- ordering while direct window moves use the correct Desktop number.
  local userIds = {}
  for _, id in ipairs(allIds) do
    if spaces.spaceType(id) == "user" then
      userIds[#userIds + 1] = id
    end
  end

  local entry = { allIds = allIds, userIds = userIds }
  cacheByUUID[uuid] = entry
  return entry
end

local function cacheForScreen(screen, refresh)
  local uuid = screenUUID(screen)
  if not uuid then return nil end
  if refresh or not cacheByUUID[uuid] then
    return buildCache(uuid)
  end
  return cacheByUUID[uuid]
end

local function findIndex(list, target)
  if not list then return nil end
  for i, id in ipairs(list) do
    if id == target then return i end
  end
  return nil
end

local function currentSpace()
  local focusedId = spaces.focusedSpace()
  if not focusedId then return nil end

  -- mainScreen() can be stale when a full-screen app has focus, so derive the
  -- display from the focused Space itself.
  local uuid = spaces.spaceDisplay(focusedId)
  if not uuid then return nil end

  local entry = cacheForScreen(uuid)
  local allIndex = entry and findIndex(entry.allIds, focusedId) or nil
  if not allIndex then
    entry = cacheForScreen(uuid, true)
    allIndex = entry and findIndex(entry.allIds, focusedId) or nil
  end

  -- For regular Desktops, use the same numbering as macOS ctrl+N shortcuts,
  -- which excludes full-screen application spaces. Full-screen spaces retain
  -- their Mission Control position as a useful fallback indicator.
  local userIndex = entry and findIndex(entry.userIds, focusedId) or nil
  local index = userIndex or allIndex

  return {
    id = focusedId,
    index = index,
    uuid = uuid,
    allIds = entry and entry.allIds or nil,
    userIds = entry and entry.userIds or nil,
  }
end

-- Ordered user-Desktop Space IDs for a screen (defaults to the primary
-- screen), using the same cache as currentSpace().
local function userSpaces(screen, refresh)
  local entry = cacheForScreen(screen or hs.screen.primaryScreen(), refresh)
  return entry and entry.userIds or nil
end

local function invalidate(screen)
  local uuid = screenUUID(screen)
  if uuid then
    cacheByUUID[uuid] = nil
  else
    cacheByUUID = {}
  end
end

-- Connected-display changes invalidate all cached Space arrays. Manual Space
-- additions/removals are handled by cache misses in currentSpace().
local screenWatcher = hs.screen.watcher.new(function()
  invalidate()
end)
screenWatcher:start()

return {
  currentSpace = currentSpace,
  userSpaces = userSpaces,
  invalidate = invalidate,
  screenWatcher = screenWatcher,
}
