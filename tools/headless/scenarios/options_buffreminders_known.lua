-- Auras, Buffs & Consumables header preview with every spell known and every
-- reminder on: text shown and moved, a glow, a shaped icon, then each grow
-- direction (the relayout path) and the text off.
local CUI = rawget(_G, "CludesUI")
_G.C_SpellBook = _G.C_SpellBook or {}
C_SpellBook.IsSpellKnown = function() return true end
C_SpellBook.IsSpellInSpellBook = function() return true end
local db = rawget(_G, "_CUABR_AceDB")
local p = db and db.profile
local function AllOn(t, list)
    if not t then return end
    t.enabled = t.enabled or {}
    for _, e in ipairs(list or {}) do t.enabled[e.key] = true end
end
if p then
    AllOn(p.raidBuffs, rawget(_G, "_CUABR_RAID_BUFFS"))
    AllOn(p.auras, rawget(_G, "_CUABR_AURAS"))
    local co = p.consumables
    AllOn(co, rawget(_G, "_CUABR_ROGUE_POISONS"))
    AllOn(co, rawget(_G, "_CUABR_PALADIN_RITES"))
    AllOn(co, rawget(_G, "_CUABR_SHAMAN_IMBUES"))
    if co then
        for _, k in ipairs({ "weapon_enchant", "flask", "food", "augment_rune", "inky_black" }) do co.enabled[k] = true end
    end
    local d = p.display
    if d then
        d.showText = true; d.textSize = 14; d.textYOffset = -6; d.textXOffset = 3; d.textAnchor = "TOP"
        d.glowType = 1; d.iconShape = "cropped"; d.scale = 1.2; d.iconSpacing = 5; d.opacity = 0.8
        d.textColor = { r = 0.2, g = 0.8, b = 0.4 }
    end
end
CUI:SelectModule("CludesUIAuraBuffReminders")
CUI:SelectPage("Auras, Buffs & Consumables")
SNAP("known header", CUI._contentHeader or CUI._headerFrame)
if p and p.display then
    for _, dir in ipairs({ "LEFT", "RIGHT", "CENTER" }) do
        p.display.growDirection = dir
        CUI:InvalidatePageCache()
        CUI:SelectPage("Auras, Buffs & Consumables")
        SNAP("grow " .. dir, CUI._contentHeader or CUI._headerFrame)
    end
    p.display.showText = false; p.display.iconShape = "none"; p.display.glowType = 0
    CUI:InvalidatePageCache()
    CUI:SelectPage("Auras, Buffs & Consumables")
    SNAP("plain header", CUI._contentHeader or CUI._headerFrame)
end
