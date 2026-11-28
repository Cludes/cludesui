if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Scout.lua  (WoW Forever only)
--  Creature Scout: on a creature's tooltip, the spells it is known to use,
--  its armor and how much of your physical damage that takes, what it is
--  immune to and resists, and (for hunters) its pet family and whether you
--  can tame it yet. Hold the details key (Ctrl by default) to read what each
--  ability does. The data (CludesUIForeverEssentials_ScoutData.lua) unpacks
--  on first use, never in combat.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("scout", {
    enabled = false,
    abilities = true,
    armor = true,
    immunities = true,
    family = true,
    instances = true,
    hint = true,
    key = "ctrl",
})
local Get, Enabled = F.Get, F.Enabled

local UNKNOWN_LEVEL_GAP = 10
local MITIGATION_BASE, MITIGATION_PER_LEVEL, MITIGATION_CAP = 400, 85, 0.75
local SPELLS_SHOWN = 8
local ICON_LINE = "|T%d:0|t %s"
local KEY_TEST = { ctrl = IsControlKeyDown, alt = IsAltKeyDown, shift = IsShiftKeyDown }
local KEY_LABEL = { ctrl = "Ctrl", alt = "Alt", shift = "Shift" }
local KEY_CODES = { LCTRL = "ctrl", RCTRL = "ctrl", LALT = "alt", RALT = "alt", LSHIFT = "shift", RSHIFT = "shift" }
local STAT_ARMOR, STAT_SCHOOLS, STAT_EFFECTS, STAT_RESIST_FIRST = 1, 2, 3, 4
local SCHOOL_BITS = {
    { 1, "Physical" }, { 2, "Holy" }, { 4, "Fire" }, { 8, "Nature" },
    { 16, "Frost" }, { 32, "Shadow" }, { 64, "Arcane" },
}
local EFFECT_BITS = {
    { 12, "Stun" }, { 5, "Fear" }, { 7, "Root" }, { 11, "Slow" }, { 9, "Silence" }, { 10, "Sleep" },
    { 1, "Charm" }, { 17, "Polymorph" }, { 18, "Banish" }, { 2, "Disorient" }, { 26, "Interrupt" },
    { 15, "Bleed" }, { 20, "Shackle" }, { 3, "Disarm" },
}
for _, effect in ipairs(EFFECT_BITS) do
    effect[1] = bit.lshift(1, effect[1] - 1)
end
local hasBit = bit.band
local SCHOOL_PHYSICAL = 1
local RESIST_NAMES = { "Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane" }
local HEADER_RGB = { 0.6, 0.8, 1 }
local DIM_RGB = { 0.6, 0.6, 0.6 }
local VALUE_RGB = { 1, 0.82, 0 }
local YES_RGB, NO_RGB = { 0.4, 0.9, 0.5 }, { 1, 0.3, 0.3 }

local spellsByNpc, tameByNpc, statsByNpc, detailTip, events
local tipSpells
local parts, loadedIds, awaitingText = {}, {}, {}

local function Secret(value)
    return issecretvalue and issecretvalue(value)
end

local function Decoded(blob)
    local u = C_EncodingUtil
    if not (blob and u and u.DecodeBase64 and u.DecompressString and u.DeserializeCBOR) then return nil end
    local ok, spellRows = pcall(function()
        return u.DeserializeCBOR(u.DecompressString(u.DecodeBase64(blob), Enum.CompressionMethod.Deflate))
    end)
    if ok and type(spellRows) == "table" then return spellRows end
end

local function ToMap(spellRows)
    local out = {}
    for i = 1, #spellRows, 2 do
        out[spellRows[i]] = spellRows[i + 1]
    end
    return out
end

-- Unpacked once, out of combat; false until then (the tooltip adds nothing).
local function Unpacked()
    if spellsByNpc then return true end
    if InCombatLockdown() then return false end
    local spellRows, tameRows, statRows =
        Decoded(module.SCOUT_ABILITIES_PACKED), Decoded(module.SCOUT_TAMEABLE_PACKED), Decoded(module.SCOUT_STATS_PACKED)
    if not (spellRows and tameRows and statRows) then return false end
    spellsByNpc, tameByNpc, statsByNpc = ToMap(spellRows), ToMap(tameRows), ToMap(statRows)
    module.SCOUT_ABILITIES_PACKED, module.SCOUT_TAMEABLE_PACKED, module.SCOUT_STATS_PACKED = nil, nil, nil
    return true
end

local function CreatureId(guid)
    if Secret(guid) or type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, keyName = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(keyName)
end

local function DetailKeyHeld()
    local Held = KEY_TEST[Get("key")] or IsControlKeyDown
    return Held()
end

local function SpellFacts(info)
    local castText = (info.castTime or 0) > 0 and ("%ss cast"):format(info.castTime / 1000) or "Instant"
    local rangeText = "Melee"
    local nearYards, farYards = info.minRange or 0, info.maxRange or 0
    if farYards > 0 then
        rangeText = nearYards > 0 and ("%d-%d yd"):format(nearYards, farYards) or ("%d yd"):format(farYards)
    end
    return rangeText .. ", " .. castText
end

local function LoadedSpells(spells)
    wipe(loadedIds)
    for i = 1, #spells do
        if #loadedIds == SPELLS_SHOWN then break end
        if C_Spell.GetSpellName(spells[i]) then loadedIds[#loadedIds + 1] = spells[i] end
    end
    return loadedIds
end

local function HideSpellTip()
    if detailTip then detailTip:Hide() end
end

local ShowSpellTip

-- A spell's description can need loading first; it shows on the next press.
local function SpellText(spellId)
    local text = C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellId)
    if text and text ~= "" then return text end
    if not awaitingText[spellId] and Spell and Spell.CreateFromSpellID then
        awaitingText[spellId] = true
        Spell:CreateFromSpellID(spellId):ContinueOnSpellLoad(function()
            if tipSpells and DetailKeyHeld() then ShowSpellTip() end
        end)
    end
end

ShowSpellTip = function()
    HideSpellTip()
    if not (tipSpells and GameTooltip:IsShown()) then return end
    detailTip = detailTip or CreateFrame("GameTooltip", "CludesUIScoutDetails", UIParent, "GameTooltipTemplate")
    detailTip:SetClampedToScreen(true)
    detailTip:SetOwner(UIParent, "ANCHOR_NONE")
    detailTip:ClearAllPoints()
    local _, y = GameTooltip:GetCenter()
    if y and not Secret(y) and y * GameTooltip:GetEffectiveScale() < UIParent:GetHeight() * UIParent:GetEffectiveScale() * 0.5 then
        detailTip:SetPoint("BOTTOMLEFT", GameTooltip, "TOPLEFT", 0, 2)
    else
        detailTip:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -2)
    end
    for _, spellId in ipairs(tipSpells) do
        local name, icon = C_Spell.GetSpellName(spellId), C_Spell.GetSpellTexture(spellId)
        detailTip:AddLine(icon and ICON_LINE:format(icon, name) or name, 1, 1, 1)
        local text = SpellText(spellId)
        if text then detailTip:AddLine(text, 1, 0.82, 0, true) end
    end
    detailTip:Show()
end

local function ListSpells(tip, spells)
    tip:AddLine("Abilities", HEADER_RGB[1], HEADER_RGB[2], HEADER_RGB[3])
    for _, spellId in ipairs(spells) do
        local info = C_Spell.GetSpellInfo(spellId)
        if info then
            local icon = C_Spell.GetSpellTexture(spellId)
            tip:AddDoubleLine(icon and ICON_LINE:format(icon, info.name) or info.name, SpellFacts(info), 1, 1, 1,
                DIM_RGB[1], DIM_RGB[2], DIM_RGB[3])
        end
    end
    if Get("hint") then
        tip:AddLine(("Hold %s for ability details"):format(KEY_LABEL[Get("key")] or "Ctrl"),
            DIM_RGB[1], DIM_RGB[2], DIM_RGB[3])
    end
end

local function CreatureLevel(unit, player)
    local topLevel = #module.SCOUT_ARMOR
    local level = UnitLevel(unit)
    if Secret(level) then return nil end
    if level and level > 0 then return math.min(level, topLevel) end
    local class = UnitClassification(unit)
    if not Secret(class) and class == "worldboss" then return topLevel end
    return math.min(player + UNKNOWN_LEVEL_GAP, topLevel)
end

local function ListArmor(tip, unit, creature)
    local attackable = UnitCanAttack("player", unit)
    if Secret(attackable) or not attackable then return end
    local player = UnitLevel("player")
    local stat = statsByNpc[creature]
    if stat and hasBit(stat[STAT_SCHOOLS] or 0, SCHOOL_PHYSICAL) ~= 0 then return end
    local armorValue, text = stat and stat[STAT_ARMOR], "%d"
    if not armorValue or armorValue == 0 then
        local level = CreatureLevel(unit, player)
        if not level then return end
        armorValue, text = module.SCOUT_ARMOR[level], "~%d"
    end
    local mitigation = math.min(MITIGATION_CAP, armorValue / (armorValue + MITIGATION_BASE + MITIGATION_PER_LEVEL * player))
    tip:AddDoubleLine("Armor", text:format(armorValue), HEADER_RGB[1], HEADER_RGB[2], HEADER_RGB[3], VALUE_RGB[1], VALUE_RGB[2], VALUE_RGB[3])
    tip:AddDoubleLine("Your physical damage", ("-%.1f%%"):format(mitigation * 100), DIM_RGB[1], DIM_RGB[2], DIM_RGB[3],
        VALUE_RGB[1], VALUE_RGB[2], VALUE_RGB[3])
end

local function ListImmunities(tip, creature)
    local statRow = statsByNpc[creature]
    if not statRow then return end
    wipe(parts)
    for _, sch in ipairs(SCHOOL_BITS) do
        if hasBit(statRow[STAT_SCHOOLS] or 0, sch[1]) ~= 0 then parts[#parts + 1] = sch[2] end
    end
    for _, effect in ipairs(EFFECT_BITS) do
        if hasBit(statRow[STAT_EFFECTS] or 0, effect[1]) ~= 0 then parts[#parts + 1] = effect[2] end
    end
    if #parts > 0 then
        tip:AddLine("Immune: " .. table.concat(parts, ", "), DIM_RGB[1], DIM_RGB[2], DIM_RGB[3], true)
    end
    wipe(parts)
    for i, sch in ipairs(RESIST_NAMES) do
        local resistValue = statRow[STAT_RESIST_FIRST + i - 1]
        if resistValue and resistValue > 0 then parts[#parts + 1] = ("%s %d"):format(sch, resistValue) end
    end
    if #parts > 0 then
        tip:AddLine("Resists: " .. table.concat(parts, ", "), DIM_RGB[1], DIM_RGB[2], DIM_RGB[3], true)
    end
end

local function ListPetFamily(tip, unit, creature)
    if select(2, UnitClass("player")) ~= "HUNTER" then return end
    local petFamily, level = UnitCreatureFamily(unit), UnitLevel(unit)
    if Secret(petFamily) or not petFamily or Secret(level) then return end
    local text, rgb = "Tameable", YES_RGB
    if not tameByNpc[creature] then
        text, rgb = "Untameable", NO_RGB
    elseif level <= 0 then
        text, rgb = "Untameable at your level", NO_RGB
    elseif level > UnitLevel("player") then
        text, rgb = ("Untameable until level %d"):format(level), NO_RGB
    end
    tip:AddDoubleLine("Pet family", petFamily .. ", " .. text, DIM_RGB[1], DIM_RGB[2], DIM_RGB[3], rgb[1], rgb[2], rgb[3])
    local swing = tameByNpc[creature]
    if swing and swing > 0 then
        tip:AddDoubleLine("Attack speed", ("%.2f"):format(swing / 1000), DIM_RGB[1], DIM_RGB[2], DIM_RGB[3],
            VALUE_RGB[1], VALUE_RGB[2], VALUE_RGB[3])
    end
end

local function OnCreatureTip(tip, data)
    if tip ~= GameTooltip or (tip.IsForbidden and tip:IsForbidden()) then return end
    tipSpells = nil
    HideSpellTip()
    if not Enabled() or (not Get("instances") and IsInInstance()) or not Unpacked() then return end
    local creature = CreatureId(data and data.guid)
    local _, unit = tip:GetUnit()
    if not creature or not unit or Secret(unit) then return end
    if Get("family") then ListPetFamily(tip, unit, creature) end
    local spells = Get("abilities") and spellsByNpc[creature]
    if spells then
        spells = LoadedSpells(spells)
        if #spells > 0 then
            ListSpells(tip, spells)
            tipSpells = { unpack(spells) }
            if DetailKeyHeld() then C_Timer.After(0, ShowSpellTip) end
        end
    end
    if Get("armor") then ListArmor(tip, unit, creature) end
    if Get("immunities") then ListImmunities(tip, creature) end
end

local function OnKeyOrCombat(_, event, key, pressed)
    if event == "PLAYER_REGEN_ENABLED" then
        if Unpacked() then events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    if not tipSpells or KEY_CODES[key] ~= Get("key") then return end
    if pressed == 1 then ShowSpellTip() else HideSpellTip() end
end

local tipHooked
local function Apply()
    if not Enabled() then
        if events then events:UnregisterAllEvents() end
        tipSpells = nil
        HideSpellTip()
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnKeyOrCombat)
    end
    if not tipHooked and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        tipHooked = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnCreatureTip)
        GameTooltip:HookScript("OnHide", function()
            tipSpells = nil
            HideSpellTip()
        end)
    end
    events:UnregisterAllEvents()
    if Get("abilities") then events:RegisterEvent("MODIFIER_STATE_CHANGED") end
    if not Unpacked() then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
end

CUI._Scout = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Loaded = function() return spellsByNpc ~= nil end,
    Lookup = function(creature)
        if not Unpacked() then return nil end
        return spellsByNpc[creature], tameByNpc[creature], statsByNpc[creature]
    end,
}

F.Start(Apply)
