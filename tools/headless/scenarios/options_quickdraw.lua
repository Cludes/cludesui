-- Action Wheel options page (CUI_Quickdraw_Options.lua): a profile with two
-- menus (the first holding a spell, an item, a macro and a nested menu) and
-- a Select key bound, so the nest and cancel rows are built. The page and
-- header are snapped in each layout (arc, fan, grid) and with the module
-- off; then, in each layout, every visible button on the page is clicked,
-- each on a fresh build from the same saved settings, with what the click
-- opened snapped (and every button in that popup clicked in turn on its own
-- fresh build), and the module's settings written out after. Finally every
-- dropdown is opened and its first rows picked, each on a fresh build.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS and CUI._ModuleNS.CludesUIQuickdraw
if not (mod and mod.Profile) then
    OUT:write("== no quickdraw\n")
    return
end
GetCursorPosition = function() return 900, 500 end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Copy(x) end
    return out
end
local base
do
    local p = mod.Profile()
    p.enabled = true
    p.paletteCount = 2
    p.confirmKey = "BUTTON4"
    if mod.EnsurePalette then
        mod.EnsurePalette(1)
        mod.EnsurePalette(2)
    end
    p.palettes[1].slots = {
        { kind = "spell", id = 133 },
        { kind = "item", id = 6948 },
        { kind = "macro", name = "Hello", body = "/wave" },
        { kind = "palette", palette = 2 },
    }
    p.palettes[2].slots = {
        { kind = "spell", id = 116 },
    }
    base = Copy(p)
end
local function Restore(layout, enabled)
    local p = mod.Profile()
    for k in pairs(p) do p[k] = nil end
    for k, v in pairs(Copy(base)) do p[k] = v end
    p.enabled = enabled ~= false
    for _, pal in ipairs(p.palettes) do
        pal.appearance = pal.appearance or {}
        pal.appearance.layout = layout
    end
end
local function Rebuild(layout, enabled)
    Restore(layout, enabled)
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    CUI:SelectModule("CludesUIQuickdraw")
    CUI:SelectPage("Action Wheel")
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
local function DumpProfile()
    OUT:write("   profile " .. Dump(mod.Profile(), 0) .. "\n")
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
local function Click(b, label)
    local ok, err = pcall(b["\0scripts"].OnClick, b, "LeftButton")
    OUT:write("== " .. label .. (ok and "" or (" ERR " .. tostring(err))) .. "\n")
    HARNESS_ADVANCE(0.1)
end
local function HideAll(tops)
    for _, c in ipairs(tops) do c:Hide() end
end
local function PopupButtons(tops)
    local out = {}
    for _, c in ipairs(tops) do
        for _, b in ipairs(Find(c, Clickable)) do out[#out + 1] = b end
    end
    return out
end

local LAYOUTS = { "ARC", "FAN", "GRID" }
for _, layout in ipairs(LAYOUTS) do
    Rebuild(layout)
    SNAP(layout .. " page", CUI._scrollFrame)
    SNAP(layout .. " header", CUI._contentHeader or CUI._headerFrame)
end
Rebuild("ARC", false)
SNAP("disabled page", CUI._scrollFrame)

for _, layout in ipairs(LAYOUTS) do
    Rebuild(layout)
    local n = #Buttons()
    OUT:write("== " .. layout .. " buttons " .. n .. "\n")
    for i = 1, n do
        Rebuild(layout)
        local b = Buttons()[i]
        if b then
            local before = ShownTops()
            local label = layout .. " click " .. i
            Click(b, label)
            local tops = NewTops(before)
            for k, c in ipairs(tops) do SNAP(label .. " popup " .. k, c) end
            DumpProfile()
            local m = #PopupButtons(tops)
            HideAll(tops)
            if m > 0 and m <= 40 then
                for j = 1, m do
                    Rebuild(layout)
                    local b2 = Buttons()[i]
                    if b2 then
                        local before2 = ShownTops()
                        pcall(b2["\0scripts"].OnClick, b2, "LeftButton")
                        HARNESS_ADVANCE(0.1)
                        local tops2 = NewTops(before2)
                        local pb = PopupButtons(tops2)[j]
                        if pb then
                            local before3 = ShownTops()
                            Click(pb, label .. " inner " .. j)
                            local tops3 = NewTops(before3)
                            for k, c in ipairs(tops3) do SNAP(label .. " inner " .. j .. " popup " .. k, c) end
                            HideAll(tops3)
                            DumpProfile()
                        end
                        HideAll(NewTops(before2))
                    end
                end
            elseif m > 40 then
                OUT:write("== " .. label .. " popup buttons " .. m .. " (skipped)\n")
            end
        end
    end
end

-- Dropdowns: open each and pick its first three rows, each on a fresh build.
local function Dropdowns()
    return Find(CUI._scrollFrame, function(f)
        return f["\0kind"] == "Button" and rawget(f, "_invalidateMenu") ~= nil and f:IsVisible()
    end)
end
local function Rows(menu)
    return Find(menu, function(f)
        return f["\0kind"] == "Button" and rawget(f, "_key") ~= nil and f:IsVisible()
    end)
end
for _, layout in ipairs(LAYOUTS) do
    Rebuild(layout)
    local n = #Dropdowns()
    OUT:write("== " .. layout .. " dropdowns " .. n .. "\n")
    for i = 1, n do
        for r = 1, 3 do
            Rebuild(layout)
            local dd = Dropdowns()[i]
            if dd then
                local before = ShownTops()
                pcall(dd["\0scripts"].OnClick, dd, "LeftButton")
                HARNESS_ADVANCE(0.1)
                local tops = NewTops(before)
                local rows = {}
                for _, c in ipairs(tops) do
                    for _, row in ipairs(Rows(c)) do rows[#rows + 1] = row end
                end
                if r == 1 then
                    for k, c in ipairs(tops) do SNAP(layout .. " dropdown " .. i .. " menu " .. k, c) end
                end
                local row = rows[r]
                if row and row["\0scripts"].OnClick then
                    Click(row, layout .. " dropdown " .. i .. " row " .. r)
                    DumpProfile()
                end
                HideAll(NewTops(before))
            end
        end
    end
end
