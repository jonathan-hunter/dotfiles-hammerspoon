-- Vim Mode for Apple Notes (Hammerspoon)
-- Supports: normal, insert, visual modes, counts, operators, dot repeat,
--           f/F/t/T char jump, r/s, Ctrl+d/u scroll

local vim = {
  enabled = false,
  mode = "normal",    -- normal | insert | visual | operator | charjump | replace
  count = "",
  pending = nil,
  lastAction = nil,   -- { fn, count } for dot repeat
  jumpChar = nil,      -- { dir, till } for f/F/t/T and ;/,
}

local alert = require("hs.alert")
local canvas = require("hs.canvas")

-- ── Mode indicator (persistent, lower-right) ─────────────────────

local modeColors = {
  normal   = { bg = { red = 0.2, green = 0.6, blue = 1.0, alpha = 0.85 }, fg = { white = 1, alpha = 1 } },
  insert   = { bg = { red = 0.3, green = 0.7, blue = 0.3, alpha = 0.85 }, fg = { white = 1, alpha = 1 } },
  visual   = { bg = { red = 0.8, green = 0.4, blue = 0.1, alpha = 0.85 }, fg = { white = 1, alpha = 1 } },
  operator = { bg = { red = 0.7, green = 0.2, blue = 0.7, alpha = 0.85 }, fg = { white = 1, alpha = 1 } },
  charjump = { bg = { red = 0.7, green = 0.2, blue = 0.7, alpha = 0.85 }, fg = { white = 1, alpha = 1 } },
  replace  = { bg = { red = 0.8, green = 0.2, blue = 0.2, alpha = 0.85 }, fg = { white = 1, alpha = 1 } },
}

local modeCanvas = nil

local function updateIndicator(mode, extra)
  if not modeCanvas then return end
  local colors = modeColors[mode] or modeColors.normal
  local display = "-- " .. mode:upper()
  if extra then display = display .. " " .. extra end
  if #vim.count > 0 then display = display .. " " .. vim.count end
  display = display .. " --"
  modeCanvas[1].fillColor = colors.bg
  modeCanvas[2].text = hs.styledtext.new(display, {
    font = { name = "Menlo", size = 14 },
    color = colors.fg,
    paragraphStyle = { alignment = "center" },
  })
end

local function showIndicator()
  if modeCanvas then modeCanvas:delete() end
  local screen = hs.screen.mainScreen():frame()
  local w, h = 160, 28
  local x = screen.x + screen.w - w - 20
  local y = screen.y + screen.h - h - 20
  modeCanvas = canvas.new({ x = x, y = y, w = w, h = h })
  modeCanvas:level(canvas.windowLevels.overlay)
  modeCanvas:appendElements(
    { type = "rectangle", roundedRectRadii = { xRadius = 6, yRadius = 6 },
      fillColor = modeColors.normal.bg, strokeColor = { white = 0, alpha = 0.3 }, strokeWidth = 1 },
    { type = "text", frame = { x = 0, y = "3%", w = "100%", h = "100%" },
      text = "" }
  )
  modeCanvas:show()
  updateIndicator(vim.mode)
end

local function hideIndicator()
  if modeCanvas then
    modeCanvas:delete()
    modeCanvas = nil
  end
end

-- ── Helpers ──────────────────────────────────────────────────────

local function showMode(mode, extra)
  updateIndicator(mode, extra)
end

local function inNotes()
  local app = hs.application.frontmostApplication()
  return app and app:bundleID() == "com.apple.Notes"
end

local function key(mods, k)
  local app = hs.application.frontmostApplication()
  hs.eventtap.keyStroke(mods, k, 0, app)
end

local function getCount()
  local n = tonumber(vim.count) or 1
  vim.count = ""
  return math.min(n, 999)
end

local function repeatKey(mods, k, n)
  for _ = 1, n do key(mods, k) end
end

local function setMode(mode, extra)
  vim.mode = mode
  vim.count = ""
  vim.pending = nil
  showMode(mode, extra)
end

local function recordAction(fn, n)
  vim.lastAction = { fn = fn, count = n }
end

-- Shift modifier for visual mode (extends selection)
local function mov(mods)
  if vim.mode == "visual" or (vim.mode == "charjump" and vim._returnToVisual) then
    local m = {}
    for _, v in ipairs(mods) do table.insert(m, v) end
    table.insert(m, "shift")
    return m
  end
  return mods
end

-- ── f/F/t/T character jump via clipboard inspection ──────────────
-- Strategy: select from cursor to end/start of line, copy, scan for
-- char, restore cursor, then jump the right number of positions.

local function charJump(char, direction, till, n)
  -- Save clipboard
  local oldClip = hs.pasteboard.getContents() or ""

  local found = 0
  local totalOffset = 0

  if direction == "forward" then
    -- Select from cursor to end of line
    key({"cmd", "shift"}, "right")
    hs.timer.usleep(15000)
    key({"cmd"}, "c")
    hs.timer.usleep(15000)
    local text = hs.pasteboard.getContents() or ""
    -- Deselect, return cursor
    key({}, "left")

    if #text == 0 then
      hs.pasteboard.setContents(oldClip)
      return
    end

    -- Find nth occurrence (start from index 2 since index 1 is char under/after cursor)
    local pos = 0
    for i = 2, #text do
      if text:sub(i, i) == char then
        found = found + 1
        pos = i
        if found == n then break end
      end
    end

    if found < n or pos == 0 then
      hs.pasteboard.setContents(oldClip)
      return
    end

    totalOffset = pos - 1
    if till then totalOffset = totalOffset - 1 end
    if totalOffset > 0 then
      repeatKey(mov({}), "right", totalOffset)
    end

  else -- backward
    key({"cmd", "shift"}, "left")
    hs.timer.usleep(15000)
    key({"cmd"}, "c")
    hs.timer.usleep(15000)
    local text = hs.pasteboard.getContents() or ""
    key({}, "right") -- deselect, restore cursor

    if #text == 0 then
      hs.pasteboard.setContents(oldClip)
      return
    end

    local pos = 0
    for i = #text - 1, 1, -1 do
      if text:sub(i, i) == char then
        found = found + 1
        pos = i
        if found == n then break end
      end
    end

    if found < n or pos == 0 then
      hs.pasteboard.setContents(oldClip)
      return
    end

    totalOffset = #text - pos
    if till then totalOffset = totalOffset - 1 end
    if totalOffset > 0 then
      repeatKey(mov({}), "left", totalOffset)
    end
  end

  -- Restore clipboard
  hs.pasteboard.setContents(oldClip)

  -- Store for ;/, repeat
  vim.jumpChar = { char = char, dir = direction, till = till }
end

-- ── Motions (work in normal + visual) ────────────────────────────

local motions = {
  h = function(n) repeatKey(mov({}), "left", n) end,
  j = function(n) repeatKey(mov({}), "down", n) end,
  k = function(n) repeatKey(mov({}), "up", n) end,
  l = function(n) repeatKey(mov({}), "right", n) end,
  w = function(n) repeatKey(mov({"alt"}), "right", n) end,
  b = function(n) repeatKey(mov({"alt"}), "left", n) end,
  e = function(n) repeatKey(mov({"alt"}), "right", n) end,
  ["0"] = function() key(mov({"cmd"}), "left") end,
  ["^"] = function() key(mov({"cmd"}), "left") end,
  ["$"] = function() key(mov({"cmd"}), "right") end,
  G = function() key(mov({"cmd"}), "down") end,
  ["{"] = function(n)
    -- Paragraph up: jump to prev blank line (approximate: 5 lines per)
    repeatKey(mov({}), "up", n * 5)
  end,
  ["}"] = function(n)
    repeatKey(mov({}), "down", n * 5)
  end,
  -- ; and , for repeating f/F/t/T
  [";"] = function(n)
    if vim.jumpChar then
      charJump(vim.jumpChar.char, vim.jumpChar.dir, vim.jumpChar.till, n)
    end
  end,
  [","] = function(n)
    if vim.jumpChar then
      local rev = vim.jumpChar.dir == "forward" and "backward" or "forward"
      charJump(vim.jumpChar.char, rev, vim.jumpChar.till, n)
    end
  end,
}

-- ── Normal mode actions ──────────────────────────────────────────

local actions = {}

-- Insert mode entries
actions.i = function() setMode("insert") end
actions.a = function() key({}, "right"); setMode("insert") end
actions.I = function() key({"cmd"}, "left"); setMode("insert") end
actions.A = function() key({"cmd"}, "right"); setMode("insert") end
actions.o = function()
  key({"cmd"}, "right"); key({}, "return"); setMode("insert")
end
actions.O = function()
  key({"cmd"}, "left"); key({}, "return"); key({}, "up"); setMode("insert")
end

-- Editing
actions.x = function(n)
  for _ = 1, n do key({}, "forwarddelete") end
  recordAction(actions.x, n)
end
actions.X = function(n)
  for _ = 1, n do key({}, "delete") end
  recordAction(actions.X, n)
end
actions.u = function() key({"cmd"}, "z") end
actions.p = function() key({"cmd"}, "v"); recordAction(actions.p, 1) end
actions.P = function() key({}, "left"); key({"cmd"}, "v"); recordAction(actions.P, 1) end
actions.J = function()
  key({"cmd"}, "right"); key({}, "forwarddelete"); key({}, "space")
  recordAction(actions.J, 1)
end

-- s: delete char + insert mode
actions.s = function(n)
  for _ = 1, n do key({}, "forwarddelete") end
  setMode("insert")
  recordAction(actions.s, n)
end
actions.S = function()
  key({"cmd"}, "left"); key({"cmd", "shift"}, "right")
  key({}, "forwarddelete"); setMode("insert")
  recordAction(actions.S, 1)
end

-- ~ toggle case (select char, copy, check, delete, type toggled)
actions["~"] = function(n)
  local oldClip = hs.pasteboard.getContents() or ""
  for _ = 1, n do
    key({"shift"}, "right")
    hs.timer.usleep(10000)
    key({"cmd"}, "c")
    hs.timer.usleep(10000)
    local ch = hs.pasteboard.getContents() or ""
    if #ch == 1 then
      local toggled = ch:match("%l") and ch:upper() or ch:lower()
      key({}, "forwarddelete")
      hs.eventtap.keyStrokes(toggled, hs.application.frontmostApplication())
    else
      key({}, "right") -- deselect
    end
  end
  hs.pasteboard.setContents(oldClip)
  recordAction(actions["~"], n)
end

-- r{char}: replace single char (enters replace sub-mode)
-- Handled specially in the event tap

-- Visual mode entry
actions.v = function() setMode("visual") end
actions.V = function()
  key({"cmd"}, "left"); key({"cmd", "shift"}, "right"); setMode("visual")
end

-- Search
actions["/"] = function() key({"cmd"}, "f") end
actions.n = function() key({"cmd"}, "g") end
actions.N = function() key({"cmd", "shift"}, "g") end

-- Dot repeat
actions["."] = function()
  if vim.lastAction then
    vim.lastAction.fn(vim.lastAction.count)
  end
end

-- ── Multi-key actions ────────────────────────────────────────────

actions.dd = function(n)
  for _ = 1, n do
    key({"cmd"}, "left"); key({"cmd", "shift"}, "right")
    key({"cmd"}, "x"); key({}, "forwarddelete")
  end
  recordAction(actions.dd, n)
end
actions.yy = function(n)
  key({"cmd"}, "left")
  if n > 1 then for _ = 1, n - 1 do key({"shift"}, "down") end end
  key({"cmd", "shift"}, "right"); key({"cmd"}, "c"); key({}, "left")
end
actions.cc = function(n)
  for _ = 1, n do
    key({"cmd"}, "left"); key({"cmd", "shift"}, "right")
    if _ < n then key({}, "forwarddelete") end
  end
  key({}, "forwarddelete"); setMode("insert")
  recordAction(actions.cc, n)
end
actions.gg = function() key(mov({"cmd"}), "up") end

-- Operator + motion
actions.dw = function(n)
  for _ = 1, n do key({"alt", "shift"}, "right"); key({"cmd"}, "x") end
  recordAction(actions.dw, n)
end
actions.db = function(n)
  for _ = 1, n do key({"alt", "shift"}, "left"); key({"cmd"}, "x") end
  recordAction(actions.db, n)
end
actions["d$"] = function()
  key({"cmd", "shift"}, "right"); key({"cmd"}, "x")
  recordAction(actions["d$"], 1)
end
actions["d0"] = function()
  key({"cmd", "shift"}, "left"); key({"cmd"}, "x")
  recordAction(actions["d0"], 1)
end
actions.D = function()
  key({"cmd", "shift"}, "right"); key({"cmd"}, "x")
  recordAction(actions.D, 1)
end
actions.C = function()
  key({"cmd", "shift"}, "right"); key({"cmd"}, "x"); setMode("insert")
  recordAction(actions.C, 1)
end
actions.cw = function(n)
  for _ = 1, n do key({"alt", "shift"}, "right") end
  key({"cmd"}, "x"); setMode("insert")
  recordAction(actions.cw, n)
end
actions.cb = function(n)
  for _ = 1, n do key({"alt", "shift"}, "left") end
  key({"cmd"}, "x"); setMode("insert")
  recordAction(actions.cb, n)
end
actions.yw = function(n)
  for _ = 1, n do key({"alt", "shift"}, "right") end
  key({"cmd"}, "c"); key({}, "left")
end
actions.yb = function(n)
  for _ = 1, n do key({"alt", "shift"}, "left") end
  key({"cmd"}, "c"); key({}, "right")
end

-- Indent in normal mode
actions[">>"] = function(n)
  for _ = 1, n do
    key({"cmd"}, "left"); key({"cmd", "shift"}, "right")
    key({"cmd"}, "]"); key({}, "left")
  end
  recordAction(actions[">>"], n)
end
actions["<<"] = function(n)
  for _ = 1, n do
    key({"cmd"}, "left"); key({"cmd", "shift"}, "right")
    key({"cmd"}, "["); key({}, "left")
  end
  recordAction(actions["<<"], n)
end

-- Text object actions (ciw, diw, yiw, caw, daw, yaw)
actions.ciw = function(n)
  key({"alt"}, "left"); key({"alt", "shift"}, "right")
  key({"cmd"}, "x"); setMode("insert")
  recordAction(actions.ciw, n)
end
actions.diw = function(n)
  key({"alt"}, "left"); key({"alt", "shift"}, "right")
  key({"cmd"}, "x")
  recordAction(actions.diw, n)
end
actions.yiw = function()
  key({"alt"}, "left"); key({"alt", "shift"}, "right")
  key({"cmd"}, "c"); key({}, "left")
end
actions.caw = function(n)
  key({"alt"}, "left"); key({"alt", "shift"}, "right")
  key({"shift"}, "right") -- include trailing space
  key({"cmd"}, "x"); setMode("insert")
  recordAction(actions.caw, n)
end
actions.daw = function(n)
  key({"alt"}, "left"); key({"alt", "shift"}, "right")
  key({"shift"}, "right")
  key({"cmd"}, "x")
  recordAction(actions.daw, n)
end
actions.yaw = function()
  key({"alt"}, "left"); key({"alt", "shift"}, "right")
  key({"shift"}, "right")
  key({"cmd"}, "c"); key({}, "left")
end

-- Ctrl+d / Ctrl+u (handled in separate tap but defined here for dot)
local SCROLL_LINES = 15

-- ── Visual mode actions ──────────────────────────────────────────

local visualActions = {
  d = function() key({"cmd"}, "x"); setMode("normal") end,
  x = function() key({"cmd"}, "x"); setMode("normal") end,
  y = function() key({"cmd"}, "c"); key({}, "left"); setMode("normal") end,
  c = function() key({"cmd"}, "x"); setMode("insert") end,
  [">"] = function() key({"cmd"}, "]"); setMode("normal") end,
  ["<"] = function() key({"cmd"}, "["); setMode("normal") end,
  ["~"] = function()
    -- Toggle case of selection: copy, toggle, paste back
    local oldClip = hs.pasteboard.getContents() or ""
    key({"cmd"}, "c")
    hs.timer.usleep(15000)
    local sel = hs.pasteboard.getContents() or ""
    local toggled = sel:gsub(".", function(ch)
      return ch:match("%l") and ch:upper() or ch:lower()
    end)
    hs.pasteboard.setContents(toggled)
    key({"cmd"}, "v")
    hs.timer.usleep(10000)
    hs.pasteboard.setContents(oldClip)
    setMode("normal")
  end,
  u = function()
    local oldClip = hs.pasteboard.getContents() or ""
    key({"cmd"}, "c"); hs.timer.usleep(15000)
    local sel = hs.pasteboard.getContents() or ""
    hs.pasteboard.setContents(sel:lower())
    key({"cmd"}, "v"); hs.timer.usleep(10000)
    hs.pasteboard.setContents(oldClip); setMode("normal")
  end,
  U = function()
    local oldClip = hs.pasteboard.getContents() or ""
    key({"cmd"}, "c"); hs.timer.usleep(15000)
    local sel = hs.pasteboard.getContents() or ""
    hs.pasteboard.setContents(sel:upper())
    key({"cmd"}, "v"); hs.timer.usleep(10000)
    hs.pasteboard.setContents(oldClip); setMode("normal")
  end,
}

-- ── Multi-key sequence starters ──────────────────────────────────

local multiKeyStarters = { d = true, y = true, c = true, g = true, [">"] = true, ["<"] = true }

-- ── Char-jump sub-mode starters ──────────────────────────────────

local charJumpStarters = {
  f = { dir = "forward",  till = false },
  F = { dir = "backward", till = false },
  t = { dir = "forward",  till = true  },
  T = { dir = "backward", till = true  },
}

-- Forward declaration for toggle (defined after taps)
local toggleVim

-- ── Main event tap (normal + visual) ─────────────────────────────

local mainTap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
  if not inNotes() then return false end
  if vim.mode == "insert" then return false end

  local char = event:getCharacters()
  local code = event:getKeyCode()
  local flags = event:getFlags()

  -- Pass through Cmd combos always
  if flags.cmd then return false end

  -- Pass through F19 so the hyperkey handler can set f19.isActive
  if code == 80 then return false end

  -- F19+; toggles vim mode off
  if char == ";" and f19.isActive then
    toggleVim()
    return true
  end

  -- ── Replace sub-mode: next char replaces ──
  if vim.mode == "replace" then
    if code == 53 then -- Escape
      setMode("normal")
      return true
    end
    if not flags.ctrl then
      local n = vim._replaceCount or 1
      for _ = 1, n do
        key({}, "forwarddelete")
        hs.eventtap.keyStrokes(char, hs.application.frontmostApplication())
      end
      recordAction(function(nn)
        for _ = 1, nn do
          key({}, "forwarddelete")
          hs.eventtap.keyStrokes(char, hs.application.frontmostApplication())
        end
      end, n)
      setMode("normal")
      return true
    end
    return true
  end

  -- ── Char-jump sub-mode: waiting for target char ──
  if vim.mode == "charjump" then
    if code == 53 then
      setMode("normal")
      return true
    end
    if not flags.ctrl then
      local info = vim._charJumpInfo
      local returnToVisual = vim._returnToVisual
      charJump(char, info.dir, info.till, vim._charJumpCount or 1)
      if returnToVisual then
        setMode("visual")
      else
        setMode("normal")
      end
      return true
    end
    return true
  end

  -- ── Text object sub-mode: waiting for object key (w, W) ──
  if vim.mode == "textobj" then
    if code == 53 then
      if vim._returnToVisual then setMode("visual") else setMode("normal") end
      return true
    end
    if not flags.ctrl and (char == "w" or char == "W") then
      local objType = vim._textObjType -- "i" or "a"
      key({"alt"}, "left")
      key({"alt", "shift"}, "right")
      if objType == "a" then key({"shift"}, "right") end
      if vim._returnToVisual then setMode("visual") else setMode("normal") end
      return true
    end
    if vim._returnToVisual then setMode("visual") else setMode("normal") end
    return true
  end

  -- ── Ctrl+d / Ctrl+u ──
  if flags.ctrl then
    if char == "d" then
      repeatKey(mov({}), "down", SCROLL_LINES)
      return true
    elseif char == "u" then
      repeatKey(mov({}), "up", SCROLL_LINES)
      return true
    elseif char == "r" and vim.mode ~= "visual" then
      key({"cmd", "shift"}, "z") -- redo
      return true
    end
    return false
  end

  -- Escape → normal mode
  if code == 53 then
    if vim.mode == "visual" then key({}, "left") end
    setMode("normal")
    return true
  end

  -- ── Count accumulation ──
  if char:match("^%d$") and not (char == "0" and #vim.count == 0) then
    vim.count = vim.count .. char
    showMode(vim.mode)
    return true
  end

  local n = getCount()

  -- ── Visual mode ──
  if vim.mode == "visual" then
    -- Text objects in visual (iw, aw)
    if char == "i" or char == "a" then
      vim._textObjType = char
      vim._returnToVisual = true
      vim.mode = "textobj"
      showMode("textobj", char .. "?")
      return true
    end
    -- Char jump in visual
    if charJumpStarters[char] then
      vim._charJumpInfo = charJumpStarters[char]
      vim._charJumpCount = n
      vim.mode = "charjump"
      -- Stay aware we came from visual — charJump uses mov() which checks vim.mode
      -- We need a flag to restore visual after
      vim._returnToVisual = true
      showMode("charjump", char .. "?")
      return true
    end
    if motions[char] then
      motions[char](n)
      return true
    end
    if visualActions[char] then
      visualActions[char]()
      return true
    end
    return true
  end

  -- ── Normal mode: pending multi-key ──
  if vim.pending then
    local pendingChar = vim.pending.char
    local savedN = vim.pending.count or n

    -- Chain operator + i/a for text objects (ci→w, di→w, yi→w)
    if (char == "i" or char == "a") and #pendingChar == 1 then
      vim.pending = { char = pendingChar .. char, count = savedN }
      return true
    end

    local seq = pendingChar .. char
    vim.pending = nil
    if actions[seq] then
      actions[seq](savedN)
      return true
    end
    return true
  end

  -- ── r: enter replace sub-mode ──
  if char == "r" then
    vim._replaceCount = n
    vim.mode = "replace"
    showMode("replace", "?")
    return true
  end

  -- ── f/F/t/T: enter char-jump sub-mode ──
  if charJumpStarters[char] then
    vim._charJumpInfo = charJumpStarters[char]
    vim._charJumpCount = n
    vim._returnToVisual = false
    vim.mode = "charjump"
    showMode("charjump", char .. "?")
    return true
  end

  -- ── Multi-key starter ──
  if multiKeyStarters[char] and not actions[char] then
    vim.pending = { char = char, count = n }
    return true
  end

  -- ── Single-char action ──
  if actions[char] then
    actions[char](n)
    return true
  end

  -- ── Motion ──
  if motions[char] then
    motions[char](n)
    return true
  end

  return true -- swallow unmapped
end)

-- ── Escape tap (insert → normal) ─────────────────────────────────

local escapeTap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
  if not inNotes() then return false end
  if event:getKeyCode() == 53 and vim.mode == "insert" then
    setMode("normal")
    return true
  end
  return false
end)

-- ── Toggle: F19+; ───────────────────────────────────────────────
-- On: f19:bind fires toggleVim. Off: mainTap detects F19+; and calls toggleVim.

toggleVim = function()
  if vim.enabled then
    vim.enabled = false
    mainTap:stop()
    escapeTap:stop()
    hideIndicator()
    alert.show("Vim Mode OFF", 1)
  else
    vim.enabled = true
    showIndicator()
    setMode("normal")
    mainTap:start()
    escapeTap:start()
  end
end

f19:bind({}, ";", toggleVim)