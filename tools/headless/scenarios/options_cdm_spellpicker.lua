-- Cooldown Manager > CDM Bars: the per-bar spell picker (add mode) and the
-- per-icon settings menu (a slot's right-click: its settings + Remove), on the
-- first bar with two tracked spells; then on the Buffs bar. Every row of both
-- is hovered, so each flyout (and the Potions & Healthstone list) shows too.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS and CUI._ModuleNS["CludesUICooldownManager"]
if not (mod and mod.CDMO_ShowSpellPicker) then
    OUT:write("== no picker\n")
    return
end
-- Bars are stored per spec: give the fake client one (Holy, 65).
local spec = rawget(_G, "C_SpecializationInfo") or {}
_G.C_SpecializationInfo = spec
spec.GetSpecialization = function() return 1 end
spec.GetSpecializationInfo = function() return 65, "Holy" end
if mod.InvalidateSpecKey then mod.InvalidateSpecKey() end

CUI:SelectModule("CludesUICooldownManager")
CUI:SelectPage("CDM Bars")
local db = rawget(_G, "_CUCME_AceDB")
local p = db and db.profile
local bars = p and p.cdmBars and p.cdmBars.bars
OUT:write("== bars " .. tostring(bars and #bars) .. "\n")
if not bars or #bars == 0 then return end

local function Popups(label)
    local n = 0
    local hosts = { UIParent }
    if CUI.OverlayParent and CUI.OverlayParent() ~= UIParent then hosts[2] = CUI.OverlayParent() end
    for _, host in ipairs(hosts) do
        for _, c in ipairs({ host:GetChildren() }) do
            if c:IsShown() and c.GetFrameStrata and c:GetFrameStrata() == "FULLSCREEN_DIALOG" and c:GetFrameLevel() >= 100 then
                n = n + 1
                SNAP(label .. " popup " .. n, c)
            end
        end
    end
    OUT:write("== " .. label .. ": " .. n .. " popups\n")
end

-- The open menu (level 300 on UIParent), each of its rows hovered in turn: a
-- row with a flyout opens it, and the flyout is snapshotted.
local function HoverRows(label)
    local menu
    for _, c in ipairs({ UIParent:GetChildren() }) do
        if c:IsShown() and c.GetFrameStrata and c:GetFrameStrata() == "FULLSCREEN_DIALOG" and c:GetFrameLevel() == 300 then
            menu = c
        end
    end
    local rows, stack = {}, { menu }
    while #stack > 0 do
        local f = table.remove(stack)
        if type(f) == "table" and rawget(f, "\0children") then
            if f["\0kind"] == "Button" and f["\0scripts"].OnEnter then rows[#rows + 1] = f end
            for _, ch in ipairs(f["\0children"]) do stack[#stack + 1] = ch end
        end
    end
    OUT:write("== " .. label .. " rows " .. #rows .. "\n")
    for i, row in ipairs(rows) do
        pcall(row["\0scripts"].OnEnter, row)
        for _, key in ipairs({ "_openSub", "_potionsSub" }) do
            local sub = menu and rawget(menu, key)
            if sub and sub:IsShown() then
                SNAP(label .. " flyout " .. i .. key, sub)
            end
        end
        if row["\0scripts"].OnLeave then pcall(row["\0scripts"].OnLeave, row) end
    end
end

-- The spell list, stubbed so every kind of row and group shows: primary and
-- secondary (unassigned and assigned), not tracked, an untalented one, an
-- extra, one of the wrong group, and one already on the bar (excludeSet).
mod.GetCDMSpellsForBar = function()
    return {
        { spellID = 1001, cdID = 1, name = "Zeta Strike", icon = 136081, cdmCat = 0 },
        { spellID = 1002, cdID = 2, name = "Alpha Ward", icon = 134206, cdmCat = 0, onCUIBar = true },
        { spellID = 1003, cdID = 3, name = "Utility Jump", icon = 136085, cdmCat = 1, isKnown = false },
        { spellID = 1004, cdID = 4, name = "Utility Rope", icon = 134914, cdmCat = 1, onCUIBar = true },
        { spellID = 1005, cdID = 5, name = "Old Spell", icon = 136107, cdmCat = 2 },
        { spellID = 1006, cdID = 6, name = "Buff Thing", icon = 136107, cdmCat = 0, cdmCatGroup = "buff" },
        { spellID = 1007, cdID = 7, name = "Extra Thing", icon = 136107, isExtra = true },
    }
end

local anchor = CreateFrame("Button", nil, UIParent)
anchor:SetSize(36, 36)
anchor:SetPoint("CENTER")

for _, key in ipairs({ bars[1].key, "buffs" }) do
    if mod.AddTrackedSpell then
        pcall(mod.AddTrackedSpell, key, 774)
        pcall(mod.AddTrackedSpell, key, 33763)
    end
    anchor._previewSpellID = 774
    mod.CDMO_ShowSpellPicker(anchor, key, nil, { [1001] = true }, function() end)
    Popups("picker " .. tostring(key))
    HoverRows("picker " .. tostring(key))
    mod.CDMO_ShowSpellPicker(anchor, key, nil, {}, function() end) -- toggles closed
    mod.CDMO_ShowSpellPicker(anchor, key, 1, {}, function() end, true)
    Popups("icon menu " .. tostring(key))
    HoverRows("icon menu " .. tostring(key))
    mod.CDMO_ShowSpellPicker(anchor, key, 1, {}, function() end, true)
end

-- Then every flyout item of each bar's icon menu clicked in turn (the menu
-- reopened whenever a pick closed it), writing out the spell's saved settings
-- after each click: the pick paths, not just the look.
local function FindMenu()
    for _, c in ipairs({ UIParent:GetChildren() }) do
        if c:IsShown() and c.GetFrameStrata and c:GetFrameStrata() == "FULLSCREEN_DIALOG" and c:GetFrameLevel() == 300 then
            return c
        end
    end
end
local function Buttons(root, pred)
    local out, stack = {}, { root }
    while #stack > 0 do
        local f = table.remove(stack, 1)
        if type(f) == "table" and rawget(f, "\0children") then
            if f["\0kind"] == "Button" and pred(f) then out[#out + 1] = f end
            for _, ch in ipairs(f["\0children"]) do stack[#stack + 1] = ch end
        end
    end
    return out
end
local function Dump(t, depth)
    if type(t) ~= "table" then return tostring(t) end
    if depth > 3 then return "{...}" end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. Dump(t[k], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function HidePopups()
    local hosts = { UIParent }
    if CUI.OverlayParent and CUI.OverlayParent() ~= UIParent then hosts[2] = CUI.OverlayParent() end
    for _, host in ipairs(hosts) do
        for _, c in ipairs({ host:GetChildren() }) do
            if c:IsShown() and c.GetFrameStrata and c:GetFrameStrata() == "FULLSCREEN_DIALOG" and c:GetFrameLevel() >= 100 and c:GetFrameLevel() ~= 300 then
                c:Hide()
            end
        end
    end
end
for _, key in ipairs({ bars[1].key, "buffs" }) do
    local function Open()
        if FindMenu() then mod.CDMO_ShowSpellPicker(anchor, key, 1, {}, function() end, true) end
        HidePopups()
        mod.CDMO_ShowSpellPicker(anchor, key, 1, {}, function() end, true)
        return FindMenu()
    end
    local function RowsOf(menu)
        return Buttons(menu, function(f) return f["\0scripts"].OnEnter ~= nil and f:IsVisible() end)
    end
    local function ItemsOf(menu, row)
        pcall(row["\0scripts"].OnEnter, row)
        local sub = rawget(menu, "_openSub")
        if not (sub and sub:IsShown()) then return {} end
        return Buttons(sub, function(f) return f["\0scripts"].OnClick ~= nil and f:IsVisible() end)
    end
    local menu = Open()
    local nRows = menu and #RowsOf(menu) or 0
    for i = 1, nRows do
        menu = FindMenu() or Open()
        local row = RowsOf(menu)[i]
        local nItems = row and #ItemsOf(menu, row) or 0
        for j = 1, nItems do
            menu = FindMenu() or Open()
            row = RowsOf(menu)[i]
            local item = row and ItemsOf(menu, row)[j]
            if item then
                local ok, err = pcall(item["\0scripts"].OnClick, item, "LeftButton")
                local store = mod.GetSpellSettingsStore and mod.GetSpellSettingsStore(key == "buffs" and "buffs" or key)
                OUT:write("== click " .. key .. " " .. i .. "." .. j .. (ok and "" or (" ERR " .. tostring(err))) .. " " .. Dump(store and store[774], 0) .. "\n")
            end
        end
    end
    if FindMenu() then mod.CDMO_ShowSpellPicker(anchor, key, 1, {}, function() end, true) end
    HidePopups()
end
