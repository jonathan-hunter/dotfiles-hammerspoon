-- markdown_notes.lua
-- Simulates markdown formatting in Apple Notes
-- 
-- Features:
--   1. Auto-convert line prefixes on Space (Notion-style)
--      # → Title, ## → Heading, ### → Subheading
--      - [ ] → Checklist, - → Bulleted list, 1. → Numbered list
--   2. Paste markdown as rich text (⌃⌥⌘V)
--      Requires: pandoc (`brew install pandoc`)
--
-- Usage: require("markdown_notes") in your init.lua

local M = {}

-------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------

local PASTE_MD_HOTKEY = { mods = {"ctrl", "alt", "cmd"}, key = "v" }

-- Apple Notes format shortcuts (macOS 15+)
local FMT = {
    title       = { mods = {"shift", "cmd"}, key = "t" },
    heading     = { mods = {"shift", "cmd"}, key = "h" },
    subheading  = { mods = {"shift", "cmd"}, key = "j" },
    body        = { mods = {"shift", "cmd"}, key = "b" },
    checklist   = { mods = {"shift", "cmd"}, key = "l" },
    bullet      = { mods = {"shift", "cmd"}, key = "7" },
    dashed      = { mods = {"shift", "cmd"}, key = "8" },
    numbered    = { mods = {"shift", "cmd"}, key = "9" },
    bold        = { mods = {"cmd"},          key = "b" },
    italic      = { mods = {"cmd"},          key = "i" },
    mono        = { mods = {"shift", "cmd"}, key = "m" },
    quote       = { mods = {"cmd"},           key = 39  },  -- Cmd+' (apostrophe)
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function inNotes()
    local app = hs.application.frontmostApplication()
    return app and app:bundleID() == "com.apple.Notes"
end

local function notesApp()
    return hs.application.frontmostApplication()
end

local function applyFormat(name, app)
    local f = FMT[name]
    if f then
        app = app or notesApp()
        hs.eventtap.keyStroke(f.mods, f.key, 0, app)
    end
end

local function deleteBackward(n, app)
    app = app or notesApp()
    for i = 1, n do
        hs.eventtap.keyStroke({}, "delete", 0, app)
        if i < n then hs.timer.usleep(5000) end
    end
end

-------------------------------------------------------------------------------
-- Feature 1: Auto-convert line prefixes
-- When Space is pressed, reads the text before the cursor via clipboard
-- inspection. If it matches a markdown prefix, deletes the prefix and
-- applies the corresponding Apple Notes format.
-------------------------------------------------------------------------------

local PREFIX_MAP = {
    { prefix = "###",   fmt = "subheading" },
    { prefix = "##",    fmt = "heading"    },
    { prefix = "#",     fmt = "title"      },
    { prefix = "- [x]", fmt = "checklist"  },
    { prefix = "- [ ]", fmt = "checklist"  },
    { prefix = "- []",  fmt = "checklist"  },
    { prefix = "-",     fmt = "bullet"     },
    { prefix = "*",     fmt = "bullet"     },
    { prefix = "1.",    fmt = "numbered"   },
    { prefix = "```",   fmt = "mono"      },
    { prefix = ">",     fmt = "quote"     },
}

local inMonoBlock = false
local lineBuffer = ""

M._eventtap = hs.eventtap.new({
    hs.eventtap.event.types.keyDown,
    hs.eventtap.event.types.leftMouseDown,
}, function(event)
    -- Mouse click → reset buffer (cursor moved)
    if event:getType() == hs.eventtap.event.types.leftMouseDown then
        lineBuffer = ""
        return false
    end

    if not inNotes() then
        lineBuffer = ""
        return false
    end

    local keyCode = event:getKeyCode()
    local flags = event:getFlags()

    -- Pass through modified keys (except shift).
    -- Allow alt when it produces a prefix char (e.g. Alt+3 → '#' on some layouts).
    if flags.cmd or flags.ctrl then return false end
    if flags.alt then
        local char = event:getCharacters()
        if not char or not char:match("[#>%*%-%[%]`1-9]") then
            return false
        end
    end

    -- Return / Enter → reset buffer (new line)
    if keyCode == 36 or keyCode == 76 then
        lineBuffer = ""
        return false
    end

    -- Backspace → trim buffer
    if keyCode == 51 then
        if #lineBuffer > 0 then
            lineBuffer = lineBuffer:sub(1, -2)
        end
        return false
    end

    -- Escape → reset buffer
    if keyCode == 53 then
        lineBuffer = ""
        return false
    end

    local char = event:getCharacters()

    -- Space → check for prefix match
    if char == " " then
        for _, entry in ipairs(PREFIX_MAP) do
            if lineBuffer == entry.prefix then
                local prefixLen = #entry.prefix
                local fmt = entry.fmt
                local app = notesApp()
                hs.timer.doAfter(0.01, function()
                    hs.eventtap.keyStroke({}, "escape", 0, app)
                    hs.timer.doAfter(0.05, function()
                        deleteBackward(prefixLen, app)
                        hs.timer.doAfter(0.1, function()
                            if fmt == "mono" and inMonoBlock then
                                applyFormat("body", app)
                                inMonoBlock = false
                            else
                                applyFormat(fmt, app)
                                if fmt == "mono" then inMonoBlock = true end
                            end
                        end)
                    end)
                end)
                lineBuffer = ""
                return true  -- consume the space
            end
        end
        lineBuffer = ""
        return false
    end

    -- Accumulate buffer (only first ~6 chars matter for prefix matching)
    if char and #char == 1 and #lineBuffer < 8 then
        lineBuffer = lineBuffer .. char
    end

    return false
end)

M._eventtap:start()

-------------------------------------------------------------------------------
-- Feature 2: Paste markdown as rich text
-- Reads plain text from clipboard, converts via pandoc → HTML,
-- writes HTML to clipboard as rich text, then pastes.
-------------------------------------------------------------------------------

local function pasteMarkdownAsRichText()
    if not inNotes() then return end

    local md = hs.pasteboard.getContents()
    if not md or md == "" then
        hs.alert.show("Clipboard empty")
        return
    end

    -- Convert markdown → HTML via pandoc
    local tmpIn  = os.tmpname()
    local tmpOut = os.tmpname() .. ".html"

    local f = io.open(tmpIn, "w")
    f:write(md)
    f:close()

    -- Try homebrew ARM path first, then Intel
    local cmd = string.format(
        '/opt/homebrew/bin/pandoc "%s" -f markdown -t html --wrap=none -o "%s" 2>&1',
        tmpIn, tmpOut
    )
    local output, status = hs.execute(cmd)
    if not status then
        cmd = cmd:gsub("/opt/homebrew/bin/pandoc", "/usr/local/bin/pandoc")
        output, status = hs.execute(cmd)
    end

    if not status then
        hs.alert.show("pandoc not found — brew install pandoc")
        os.remove(tmpIn)
        os.remove(tmpOut)
        return
    end

    local htmlFile = io.open(tmpOut, "r")
    if not htmlFile then
        hs.alert.show("Conversion failed")
        os.remove(tmpIn)
        os.remove(tmpOut)
        return
    end
    local html = htmlFile:read("*a")
    htmlFile:close()

    -- Convert HTML → RTF via textutil, write to pasteboard
    local saved = hs.pasteboard.readAllData()

    hs.pasteboard.setContents("")
    hs.execute(string.format(
        'echo %q | /usr/bin/textutil -stdin -format html -convert rtf -stdout | pbcopy -Prefer rtf',
        html
    ))

    hs.eventtap.keyStroke({"cmd"}, "v", 0)

    -- Restore clipboard after short delay
    hs.timer.doAfter(0.5, function()
        if saved then
            hs.pasteboard.writeAllData(saved)
        end
    end)

    os.remove(tmpIn)
    os.remove(tmpOut)
end

M._pasteHotkey = hs.hotkey.bind(
    PASTE_MD_HOTKEY.mods, PASTE_MD_HOTKEY.key,
    pasteMarkdownAsRichText
)

-------------------------------------------------------------------------------
-- Feature 3: Quick format hotkeys (active only in Notes)
-- These supplement the auto-prefix detection for cases where you want to
-- apply formatting to existing text or toggle mid-line.
-------------------------------------------------------------------------------

-- ⌃1/2/3 for Title/Heading/Subheading (easier than ⇧⌘T/H/J)
local quickFormats = {
    { mods = {"cmd"}, key = "1", fmt = "title"      },
    { mods = {"cmd"}, key = "2", fmt = "heading"    },
    { mods = {"cmd"}, key = "3", fmt = "subheading" },
    { mods = {"cmd"}, key = "0", fmt = "body"       },
}

M._quickHotkeys = {}
for _, qf in ipairs(quickFormats) do
    local hk = hs.hotkey.new(qf.mods, qf.key, function()
        if inNotes() then applyFormat(qf.fmt) end
    end)
    table.insert(M._quickHotkeys, hk)
end

-- Enable/disable quick hotkeys based on active app
M._appWatcher = hs.application.watcher.new(function(appName, eventType, app)
    if eventType == hs.application.watcher.activated then
        local isNotes = app and app:bundleID() == "com.apple.Notes"
        for _, hk in ipairs(M._quickHotkeys) do
            if isNotes then hk:enable() else hk:disable() end
        end
    end
end)
M._appWatcher:start()

-- Initialize hotkey state
local frontApp = hs.application.frontmostApplication()
if frontApp and frontApp:bundleID() == "com.apple.Notes" then
    for _, hk in ipairs(M._quickHotkeys) do hk:enable() end
end

-------------------------------------------------------------------------------
-- Cleanup
-------------------------------------------------------------------------------

function M.stop()
    M._eventtap:stop()
    M._pasteHotkey:delete()
    M._appWatcher:stop()
    for _, hk in ipairs(M._quickHotkeys) do hk:delete() end
end

return M