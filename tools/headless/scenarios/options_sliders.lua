-- Slider drags (CludesUI_Widgets' slider) on the Info Bar page of a bar
-- holding every block type: for each slider, a track press dragged across
-- two cursor positions and released on the track, a thumb press dragged and
-- released by the drag's own button-up check, and a drag ended by hiding the
-- track. After each, the slider's row is snapped and the bar's settings
-- written out. The fake client puts every frame's left edge at 100, so the
-- cursor x is 100 plus the position along the track.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS and CUI._ModuleNS.CludesUIDataBars
BreakUpLargeNumbers = tostring
GetNetStats = function() return 0, 0, 42, 61 end
do
    local list = {
        { name = "Dungeon and Raid", isHeader = true, isHeaderExpanded = true },
        { name = "Valorstones", currencyID = 3008, iconFileID = 5868902, quantity = 1200 },
    }
    local ci = rawget(_G, "C_CurrencyInfo") or {}
    _G.C_CurrencyInfo = ci
    ci.GetCurrencyListSize = function() return #list end
    ci.GetCurrencyListInfo = function(i) return list[i] end
    ci.ExpandCurrencyList = function() end
    ci.GetCurrencyListLink = function(i) return list[i] and ("currency:" .. tostring(list[i].currencyID)) end
end
if not mod then
    OUT:write("== no info bar module\n")
    return
end
local cursorX, buttonDown = 0, false
GetCursorPosition = function() return cursorX, 0 end
IsMouseButtonDown = function() return buttonDown end

local bar = mod.CreateBar("empty")
for _, t in ipairs(mod.BLOCK_TYPES) do
    mod.AddBlock(bar.id, t.key)
end
local function Rebuild()
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    mod.GetProfile().selectedBarId = bar.id
    CUI:SelectModule("CludesUIDataBars")
    CUI:SelectPage("Info Bar")
end
local function Thumbs()
    local out, stack = {}, { CUI._scrollFrame }
    while #stack > 0 do
        local f = table.remove(stack, 1)
        if type(f) == "table" and rawget(f, "\0children") then
            if rawget(f, "_sliderDisabled") ~= nil and f:IsVisible() then out[#out + 1] = f end
            for _, ch in ipairs(f["\0children"]) do stack[#stack + 1] = ch end
        end
    end
    return out
end
local function Dump(v, depth)
    if type(v) ~= "table" then
        if type(v) == "number" then return string.format("%.3f", v) end
        return tostring(v)
    end
    if depth > 4 then return "{...}" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. Dump(v[k], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function Report(label, track)
    OUT:write("== " .. label .. " dragging=" .. tostring(CUI._sliderDragging) .. "\n")
    local row = track and track:GetParent()
    if row then SNAP(label, row) end
    local conf = mod.GetBar(bar.id)
    local copy = {}
    for k, v in pairs(conf) do
        if k ~= "blocks" then copy[k] = v end
    end
    OUT:write("   bar " .. Dump(copy, 0) .. "\n")
    for i, b in ipairs(conf.blocks) do
        OUT:write("   block " .. i .. " " .. Dump(b, 0) .. "\n")
    end
end
local function Press(frame, x)
    cursorX, buttonDown = 100 + x, true
    local ok, err = pcall(frame["\0scripts"].OnMouseDown, frame, "LeftButton")
    if not ok then OUT:write("   ERR down " .. tostring(err) .. "\n") end
end

Rebuild()
-- The first 30 (of ~80) keep a run to a few minutes.
local count = math.min(#Thumbs(), 30)
OUT:write("== sliders " .. count .. "\n")
for i = 1, count do
    -- 1. Track: press at 10, drag to 60 then 140, release on the track.
    Rebuild()
    local thumb = Thumbs()[i]
    if thumb then
        local track = thumb:GetParent()
        Press(track, 10)
        cursorX = 160
        HARNESS_TICK(0.02, 2)
        cursorX = 240
        HARNESS_TICK(0.02, 2)
        buttonDown = false
        local up = track["\0scripts"].OnMouseUp
        if up then
            local ok, err = pcall(up, track, "LeftButton")
            if not ok then OUT:write("   ERR up " .. tostring(err) .. "\n") end
        end
        HARNESS_ADVANCE(0.1)
        Report("slider " .. i .. " track", track)
    end
    -- 2. Thumb: press, drag to 30, let the button go and tick (OnUpdate's release check).
    Rebuild()
    thumb = Thumbs()[i]
    if thumb then
        local track = thumb:GetParent()
        Press(thumb, 80)
        cursorX = 130
        HARNESS_TICK(0.02, 2)
        buttonDown = false
        HARNESS_TICK(0.02, 2)
        HARNESS_ADVANCE(0.1)
        Report("slider " .. i .. " thumb", track)
    end
    -- 3. Hidden mid-drag: press at 50, drag to 90, hide the track.
    Rebuild()
    thumb = Thumbs()[i]
    if thumb then
        local track = thumb:GetParent()
        Press(track, 50)
        cursorX = 190
        HARNESS_TICK(0.02, 2)
        track:Hide()
        HARNESS_ADVANCE(0.1)
        HARNESS_TICK(0.02, 2)
        buttonDown = false
        Report("slider " .. i .. " hidden", track)
    end
end
GetCursorPosition = function() return 0, 0 end
