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

local anchor = CreateFrame("Button", nil, UIParent)
anchor:SetSize(36, 36)
anchor:SetPoint("CENTER")

for _, key in ipairs({ bars[1].key, "buffs" }) do
    if mod.AddTrackedSpell then
        pcall(mod.AddTrackedSpell, key, 774)
        pcall(mod.AddTrackedSpell, key, 33763)
    end
    anchor._previewSpellID = 774
    mod.CDMO_ShowSpellPicker(anchor, key, nil, {}, function() end)
    Popups("picker " .. tostring(key))
    HoverRows("picker " .. tostring(key))
    mod.CDMO_ShowSpellPicker(anchor, key, nil, {}, function() end) -- toggles closed
    mod.CDMO_ShowSpellPicker(anchor, key, 1, {}, function() end, true)
    Popups("icon menu " .. tostring(key))
    HoverRows("icon menu " .. tostring(key))
    mod.CDMO_ShowSpellPicker(anchor, key, 1, {}, function() end, true)
end
