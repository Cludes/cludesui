-- Mythic+ Tools options (CUI_MythicTimer_Options.lua): every page snapped
-- with its header (the Kick Tracker page too, for the shared header preview
-- kit); then on the Mythic+ Timer, Cast Bars, Target/Focus Bars and Run
-- Summary pages every visible button clicked, each on a fresh build: a
-- dropdown gets its menu snapped and a row picked, a cog gets its popup
-- snapped and every button and slider inside it used. Then every slider on
-- the page pressed on its track. The module's settings that changed are
-- written out after each step, and each page is snapped again at the end.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS and CUI._ModuleNS.CludesUIMythicTimer
if not (mod and mod._MT_Preview) then
    OUT:write("== no mythic+ tools options\n")
    return
end
local cursorX, buttonDown = 0, false
GetCursorPosition = function() return cursorX, 0 end
IsMouseButtonDown = function() return buttonDown end

local function Rebuild(page)
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    CUI:SelectModule("CludesUIMythicTimer")
    CUI:SelectPage(page)
end
local function Hosts()
    local hosts = { UIParent }
    if CUI.OverlayParent and CUI.OverlayParent() ~= UIParent then hosts[2] = CUI.OverlayParent() end
    return hosts
end
local function ShownTops()
    local set = {}
    for _, host in ipairs(Hosts()) do
        for _, c in ipairs({ host:GetChildren() }) do
            if c:IsShown() then set[c] = true end
        end
    end
    return set
end
local function NewTops(before)
    local out = {}
    for _, host in ipairs(Hosts()) do
        for _, c in ipairs({ host:GetChildren() }) do
            if c:IsShown() and not before[c] then out[#out + 1] = c end
        end
    end
    return out
end
local function Find(root, test)
    local out, stack = {}, { root }
    while #stack > 0 do
        local f = table.remove(stack, 1)
        if type(f) == "table" and rawget(f, "\0children") then
            if test(f) then out[#out + 1] = f end
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
    if depth > 5 then return "{...}" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. Dump(v[k], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local last = {}
local function Changed()
    local db = rawget(_G, "_CUMT_AceDB")
    local p = db and db.profile or {}
    local keys = {}
    for k in pairs(p) do keys[#keys + 1] = k end
    for k in pairs(last) do if p[k] == nil then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local d = Dump(p[k], 0)
        if last[k] ~= d then
            OUT:write("   " .. tostring(k) .. " " .. d .. "\n")
            last[k] = d
        end
    end
end
local function Call(f, script, ...)
    local fn = f["\0scripts"][script]
    if not fn then return false end
    local ok, err = pcall(fn, f, ...)
    if not ok then OUT:write("   ERR " .. script .. " " .. tostring(err) .. "\n") end
    return true
end
local function Clickable(f)
    return f["\0kind"] == "Button" and f:IsVisible() and f["\0scripts"].OnClick ~= nil
end
local function Buttons()
    local out = {}
    for _, root in ipairs({ CUI._scrollFrame, CUI._contentHeader or CUI._headerFrame }) do
        for _, b in ipairs(Find(root, Clickable)) do out[#out + 1] = b end
    end
    return out
end
local function Thumbs(root)
    return Find(root, function(f) return rawget(f, "_sliderDisabled") ~= nil and f:IsVisible() end)
end
local function PressTrack(thumb, x)
    local track = thumb:GetParent()
    cursorX, buttonDown = 100 + x, true
    Call(track, "OnMouseDown", "LeftButton")
    HARNESS_TICK(0.02, 2)
    buttonDown = false
    Call(track, "OnMouseUp", "LeftButton")
    HARNESS_ADVANCE(0.1)
end
-- A popup a click opened: snapped, then (a dropdown menu) its second row
-- picked, or (a cog) every button and slider in it used.
local function UsePopup(label, top, dd)
    SNAP(label, top)
    local menu = dd and rawget(dd, "_ddMenu")
    if menu == top then
        local rows = Find(menu, function(f) return f["\0kind"] == "Button" and rawget(f, "_key") ~= nil and f:IsVisible() end)
        local pick = rows[2] or rows[1]
        if pick then
            Call(pick, "OnClick", "LeftButton")
            OUT:write("== " .. label .. " picked " .. tostring(rawget(pick, "_key")) .. "\n")
        end
        HARNESS_ADVANCE(0.1)
        if top:IsShown() then top:Hide() end
        return
    end
    -- A button that closes the popup (its close button) is clicked like the
    -- rest; the popup is shown again for the next one.
    for j = 1, #Find(top, Clickable) do
        if not top:IsShown() then top:Show() end
        local b = Find(top, Clickable)[j]
        if b then
            local before = ShownTops()
            Call(b, "OnClick", "LeftButton")
            HARNESS_ADVANCE(0.1)
            for _, extra in ipairs(NewTops(before)) do
                if extra ~= top then
                    SNAP(label .. " button " .. j .. " opened", extra)
                    extra:Hide()
                end
            end
        end
    end
    if not top:IsShown() then top:Show() end
    for j = 1, #Thumbs(top) do
        local t = Thumbs(top)[j]
        if t then PressTrack(t, 30 + 20 * j) end
    end
    if top:IsShown() then SNAP(label .. " used", top) end
    top:Hide()
end

local PAGES = { "Mythic+ Timer", "Kick Tracker", "Targeted Spell Bars", "Target/Focus Bars", "Run Summary" }
for _, page in ipairs(PAGES) do
    Rebuild(page)
    SNAP(page .. " page", CUI._scrollFrame)
    SNAP(page .. " header", CUI._contentHeader or CUI._headerFrame)
end
Changed()

for _, page in ipairs(PAGES) do
    if page ~= "Kick Tracker" then
        Rebuild(page)
        local n = #Buttons()
        OUT:write("== " .. page .. " buttons " .. n .. "\n")
        for i = 1, n do
            Rebuild(page)
            local b = Buttons()[i]
            if b then
                local before = ShownTops()
                Call(b, "OnClick", "LeftButton")
                HARNESS_ADVANCE(0.1)
                OUT:write("== " .. page .. " click " .. i .. "\n")
                for k, top in ipairs(NewTops(before)) do
                    UsePopup(page .. " click " .. i .. " popup " .. k, top, b)
                end
                Changed()
            end
        end
        Rebuild(page)
        local s = #Thumbs(CUI._scrollFrame)
        OUT:write("== " .. page .. " sliders " .. s .. "\n")
        for i = 1, s do
            local t = Thumbs(CUI._scrollFrame)[i]
            if t then
                PressTrack(t, 40 + (i % 5) * 30)
                OUT:write("== " .. page .. " slider " .. i .. "\n")
                Changed()
            end
        end
        Rebuild(page)
        SNAP(page .. " page after", CUI._scrollFrame)
        SNAP(page .. " header after", CUI._contentHeader or CUI._headerFrame)
    end
end
-- The Mythic+ Timer page with a textured border style (its offset row
-- appears), every slider pressed; then everything that reacts to the mouse
-- hovered (with what the hover shows snapped), once with the timer on and
-- once with it off (the requirement tooltips).
local function Hover(label)
    local list = Find(CUI._scrollFrame, function(f)
        return f:IsVisible() and f["\0scripts"].OnEnter ~= nil
    end)
    OUT:write("== " .. label .. " hover " .. #list .. "\n")
    for i, f in ipairs(list) do
        local before = ShownTops()
        Call(f, "OnEnter")
        for k, top in ipairs(NewTops(before)) do SNAP(label .. " hover " .. i .. " shows " .. k, top) end
        Call(f, "OnLeave")
    end
end
do
    local db = rawget(_G, "_CUMT_AceDB")
    local p = db and db.profile
    if p then
        p.customBorderStyle = true
        local _, order = CUI.GetBorderTextureDropdown()
        for _, k in ipairs(order or {}) do
            if k ~= "solid" and k ~= "shadow" and k ~= "" then
                p.borderTexture = k
                break
            end
        end
        OUT:write("== textured border " .. tostring(p.borderTexture) .. "\n")
        Rebuild("Mythic+ Timer")
        SNAP("textured border page", CUI._scrollFrame)
        for i = 1, #Thumbs(CUI._scrollFrame) do
            local t = Thumbs(CUI._scrollFrame)[i]
            if t then
                PressTrack(t, 60 + (i % 4) * 25)
                Changed()
            end
        end
        Rebuild("Mythic+ Timer")
        Hover("timer on")
        p.enabled = false
        Rebuild("Mythic+ Timer")
        SNAP("timer off page", CUI._scrollFrame)
        Hover("timer off")
        p.enabled = true
    end
end
GetCursorPosition = function() return 0, 0 end
