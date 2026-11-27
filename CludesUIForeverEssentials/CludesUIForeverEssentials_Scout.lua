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

local UNKNOWN_GAP = 10
local ARMOR_BASE, ARMOR_PER_LEVEL, ARMOR_CAP = 400, 85, 0.75
local MAX_LISTED = 8
local ICON = "|T%d:0|t %s"
local KEYS = { ctrl = IsControlKeyDown, alt = IsAltKeyDown, shift = IsShiftKeyDown }
local KEY_NAMES = { ctrl = "Ctrl", alt = "Alt", shift = "Shift" }
local MODIFIERS = { LCTRL = "ctrl", RCTRL = "ctrl", LALT = "alt", RALT = "alt", LSHIFT = "shift", RSHIFT = "shift" }
local ARMOR, SCHOOLS_IMMUNE, MECHANICS_IMMUNE, FIRST_RESIST = 1, 2, 3, 4
local SCHOOLS = {
    { 1, "Physical" }, { 2, "Holy" }, { 4, "Fire" }, { 8, "Nature" },
    { 16, "Frost" }, { 32, "Shadow" }, { 64, "Arcane" },
}
local MECHANICS = {
    { 12, "Stun" }, { 5, "Fear" }, { 7, "Root" }, { 11, "Slow" }, { 9, "Silence" }, { 10, "Sleep" },
    { 1, "Charm" }, { 17, "Polymorph" }, { 18, "Banish" }, { 2, "Disorient" }, { 26, "Interrupt" },
    { 15, "Bleed" }, { 20, "Shackle" }, { 3, "Disarm" },
}
for _, mechanic in ipairs(MECHANICS) do
    mechanic[1] = bit.lshift(1, mechanic[1] - 1)
end
local band = bit.band
local PHYSICAL = 1
local RESISTED = { "Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane" }
local HEAD = { 0.6, 0.8, 1 }
local MUTED = { 0.6, 0.6, 0.6 }
local GOLD = { 1, 0.82, 0 }
local GOOD, BAD = { 0.4, 0.9, 0.5 }, { 1, 0.3, 0.3 }

local abilities, tameable, stats, details, events
local shown
local listed, named, requested = {}, {}, {}

local function Secret(value)
    return issecretvalue and issecretvalue(value)
end

local function Unpack(packed)
    local u = C_EncodingUtil
    if not (packed and u and u.DecodeBase64 and u.DecompressString and u.DeserializeCBOR) then return nil end
    local ok, flat = pcall(function()
        return u.DeserializeCBOR(u.DecompressString(u.DecodeBase64(packed), Enum.CompressionMethod.Deflate))
    end)
    if ok and type(flat) == "table" then return flat end
end

local function Pairs(flat)
    local out = {}
    for i = 1, #flat, 2 do
        out[flat[i]] = flat[i + 1]
    end
    return out
end

-- Unpacked once, out of combat; false until then (the tooltip adds nothing).
local function Load()
    if abilities then return true end
    if InCombatLockdown() then return false end
    local flat, tame, numbers =
        Unpack(module.SCOUT_ABILITIES_PACKED), Unpack(module.SCOUT_TAMEABLE_PACKED), Unpack(module.SCOUT_STATS_PACKED)
    if not (flat and tame and numbers) then return false end
    abilities, tameable, stats = Pairs(flat), Pairs(tame), Pairs(numbers)
    module.SCOUT_ABILITIES_PACKED, module.SCOUT_TAMEABLE_PACKED, module.SCOUT_STATS_PACKED = nil, nil, nil
    return true
end

local function NpcID(guid)
    if Secret(guid) or type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, entry = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(entry)
end

local function KeyDown()
    local IsDown = KEYS[Get("key")] or IsControlKeyDown
    return IsDown()
end

local function Meta(info)
    local cast = (info.castTime or 0) > 0 and ("%ss cast"):format(info.castTime / 1000) or "Instant"
    local range = "Melee"
    local minRange, maxRange = info.minRange or 0, info.maxRange or 0
    if maxRange > 0 then
        range = minRange > 0 and ("%d-%d yd"):format(minRange, maxRange) or ("%d yd"):format(maxRange)
    end
    return range .. ", " .. cast
end

local function Known(list)
    wipe(named)
    for i = 1, #list do
        if #named == MAX_LISTED then break end
        if C_Spell.GetSpellName(list[i]) then named[#named + 1] = list[i] end
    end
    return named
end

local function HideDetails()
    if details then details:Hide() end
end

local ShowDetails

-- A spell's description can need loading first; it shows on the next press.
local function Described(spell)
    local text = C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spell)
    if text and text ~= "" then return text end
    if not requested[spell] and Spell and Spell.CreateFromSpellID then
        requested[spell] = true
        Spell:CreateFromSpellID(spell):ContinueOnSpellLoad(function()
            if shown and KeyDown() then ShowDetails() end
        end)
    end
end

ShowDetails = function()
    HideDetails()
    if not (shown and GameTooltip:IsShown()) then return end
    details = details or CreateFrame("GameTooltip", "CludesUIScoutDetails", UIParent, "GameTooltipTemplate")
    details:SetClampedToScreen(true)
    details:SetOwner(UIParent, "ANCHOR_NONE")
    details:ClearAllPoints()
    local _, y = GameTooltip:GetCenter()
    if y and not Secret(y) and y * GameTooltip:GetEffectiveScale() < UIParent:GetHeight() * UIParent:GetEffectiveScale() * 0.5 then
        details:SetPoint("BOTTOMLEFT", GameTooltip, "TOPLEFT", 0, 2)
    else
        details:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -2)
    end
    for _, spell in ipairs(shown) do
        local name, icon = C_Spell.GetSpellName(spell), C_Spell.GetSpellTexture(spell)
        details:AddLine(icon and ICON:format(icon, name) or name, 1, 1, 1)
        local text = Described(spell)
        if text then details:AddLine(text, 1, 0.82, 0, true) end
    end
    details:Show()
end

local function AddAbilities(tooltip, list)
    tooltip:AddLine("Abilities", HEAD[1], HEAD[2], HEAD[3])
    for _, spell in ipairs(list) do
        local info = C_Spell.GetSpellInfo(spell)
        if info then
            local icon = C_Spell.GetSpellTexture(spell)
            tooltip:AddDoubleLine(icon and ICON:format(icon, info.name) or info.name, Meta(info), 1, 1, 1,
                MUTED[1], MUTED[2], MUTED[3])
        end
    end
    if Get("hint") then
        tooltip:AddLine(("Hold %s for ability details"):format(KEY_NAMES[Get("key")] or "Ctrl"),
            MUTED[1], MUTED[2], MUTED[3])
    end
end

local function MobLevel(unit, player)
    local maxLevel = #module.SCOUT_ARMOR
    local level = UnitLevel(unit)
    if Secret(level) then return nil end
    if level and level > 0 then return math.min(level, maxLevel) end
    local class = UnitClassification(unit)
    if not Secret(class) and class == "worldboss" then return maxLevel end
    return math.min(player + UNKNOWN_GAP, maxLevel)
end

local function AddArmor(tooltip, unit, npc)
    local hostile = UnitCanAttack("player", unit)
    if Secret(hostile) or not hostile then return end
    local player = UnitLevel("player")
    local row = stats[npc]
    if row and band(row[SCHOOLS_IMMUNE] or 0, PHYSICAL) ~= 0 then return end
    local armor, text = row and row[ARMOR], "%d"
    if not armor or armor == 0 then
        local level = MobLevel(unit, player)
        if not level then return end
        armor, text = module.SCOUT_ARMOR[level], "~%d"
    end
    local cut = math.min(ARMOR_CAP, armor / (armor + ARMOR_BASE + ARMOR_PER_LEVEL * player))
    tooltip:AddDoubleLine("Armor", text:format(armor), HEAD[1], HEAD[2], HEAD[3], GOLD[1], GOLD[2], GOLD[3])
    tooltip:AddDoubleLine("Your physical damage", ("-%.1f%%"):format(cut * 100), MUTED[1], MUTED[2], MUTED[3],
        GOLD[1], GOLD[2], GOLD[3])
end

local function AddImmunities(tooltip, npc)
    local own = stats[npc]
    if not own then return end
    wipe(listed)
    for _, school in ipairs(SCHOOLS) do
        if band(own[SCHOOLS_IMMUNE] or 0, school[1]) ~= 0 then listed[#listed + 1] = school[2] end
    end
    for _, mechanic in ipairs(MECHANICS) do
        if band(own[MECHANICS_IMMUNE] or 0, mechanic[1]) ~= 0 then listed[#listed + 1] = mechanic[2] end
    end
    if #listed > 0 then
        tooltip:AddLine("Immune: " .. table.concat(listed, ", "), MUTED[1], MUTED[2], MUTED[3], true)
    end
    wipe(listed)
    for i, school in ipairs(RESISTED) do
        local points = own[FIRST_RESIST + i - 1]
        if points and points > 0 then listed[#listed + 1] = ("%s %d"):format(school, points) end
    end
    if #listed > 0 then
        tooltip:AddLine("Resists: " .. table.concat(listed, ", "), MUTED[1], MUTED[2], MUTED[3], true)
    end
end

local function AddFamily(tooltip, unit, npc)
    if select(2, UnitClass("player")) ~= "HUNTER" then return end
    local family, level = UnitCreatureFamily(unit), UnitLevel(unit)
    if Secret(family) or not family or Secret(level) then return end
    local text, color = "Tameable", GOOD
    if not tameable[npc] then
        text, color = "Untameable", BAD
    elseif level <= 0 then
        text, color = "Untameable at your level", BAD
    elseif level > UnitLevel("player") then
        text, color = ("Untameable until level %d"):format(level), BAD
    end
    tooltip:AddDoubleLine("Pet family", family .. ", " .. text, MUTED[1], MUTED[2], MUTED[3], color[1], color[2], color[3])
    local speed = tameable[npc]
    if speed and speed > 0 then
        tooltip:AddDoubleLine("Attack speed", ("%.2f"):format(speed / 1000), MUTED[1], MUTED[2], MUTED[3],
            GOLD[1], GOLD[2], GOLD[3])
    end
end

local function OnUnit(tooltip, data)
    if tooltip ~= GameTooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
    shown = nil
    HideDetails()
    if not Enabled() or (not Get("instances") and IsInInstance()) or not Load() then return end
    local npc = NpcID(data and data.guid)
    local _, unit = tooltip:GetUnit()
    if not npc or not unit or Secret(unit) then return end
    if Get("family") then AddFamily(tooltip, unit, npc) end
    local list = Get("abilities") and abilities[npc]
    if list then
        list = Known(list)
        if #list > 0 then
            AddAbilities(tooltip, list)
            shown = { unpack(list) }
            if KeyDown() then C_Timer.After(0, ShowDetails) end
        end
    end
    if Get("armor") then AddArmor(tooltip, unit, npc) end
    if Get("immunities") then AddImmunities(tooltip, npc) end
end

local function OnEvent(_, event, key, down)
    if event == "PLAYER_REGEN_ENABLED" then
        if Load() then events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    if not shown or MODIFIERS[key] ~= Get("key") then return end
    if down == 1 then ShowDetails() else HideDetails() end
end

local hooked
local function Apply()
    if not Enabled() then
        if events then events:UnregisterAllEvents() end
        shown = nil
        HideDetails()
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    if not hooked and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        hooked = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnit)
        GameTooltip:HookScript("OnHide", function()
            shown = nil
            HideDetails()
        end)
    end
    events:UnregisterAllEvents()
    if Get("abilities") then events:RegisterEvent("MODIFIER_STATE_CHANGED") end
    if not Load() then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
end

CUI._Scout = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Loaded = function() return abilities ~= nil end,
    Lookup = function(npc)
        if not Load() then return nil end
        return abilities[npc], tameable[npc], stats[npc]
    end,
}

F.Start(Apply)
