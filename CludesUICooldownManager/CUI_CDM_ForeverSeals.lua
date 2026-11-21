if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_CDM_ForeverSeals.lua
--
--  WoW Forever Paladins: a stand-in for Blizzard's "Seals" cooldown entry
--  (SEALS), for which Blizzard's Cooldown Manager draws no frame there, with or
--  without addons (its settings row stays grey as if unlearned). An entry of
--  that spell on a cooldown or utility bar -- picked from the bar's Add menu
--  (Seals, beside Racial) or from Blizzard's own list -- is drawn by an aura
--  icon of ours (CUI_CDM_AuraIcons.lua), as a racial Blizzard does not track
--  is: the Seals icon while no seal is up, else the seal's own icon, swipe
--  and countdown. Its aura IDs: every seal the player knows (each rank is its
--  own spell, sharing its seal's name), the seeds below and the entry's own
--  linked spells.
--
--  Hand-over to Blizzard: an entry Blizzard draws is claimed by its frame, so
--  the reanchor never injects ours over it, and once a frame of Blizzard's
--  Seals entry shows on any bar (its fix landed) the stand-in stands down for
--  the session. To retire it for good, drop this file, its TOC / build list
--  lines and the Seals row in the CDM Add menu (SpellPicker_Options.lua); the
--  aura icon engine and its hooks stay for custom buffs.
-------------------------------------------------------------------------------
local _, mod = ...
if CUI.IS_FOREVER ~= true then return end
local _, playerClass = UnitClass("player")
if playerClass ~= "PALADIN" then return end
if not mod.CDM_AuraIconProvider then return end

-- Blizzard's Seals entry on WoW Forever (its spell).
local SEALS = 1323522

-- Seal spells whose names seed the rank scan (Classic ids, which Forever
-- reuses, plus Forever's Seal of Fury). Any rank the player knows joins
-- through its name; an id the client lacks only joins the set.
local SEAL_SEEDS = {
    20154,
    21084, -- Seal of Righteousness
    21082, -- Seal of the Crusader
    20375, -- Seal of Command
    20164, -- Seal of Justice
    20165, -- Seal of Light
    20166, -- Seal of Wisdom
    1311649, -- Seal of Fury (WoW Forever)
}

-- The Add menu's Seals row reads it.
mod.CDM_SEALS_SPELL = SEALS

-- cd: cooldownID -> whether it is the Seals entry; linked: the entry's linked
-- spells; known: a seal is in the spellbook; native: Blizzard draws its own
-- Seals frame, the stand-in stands down.
local S = { cd = {} }

local IsSecret = CUI.IsSecret

-- Blizzard's API copy of an entry's info is never secret.
local function IsSealsInfo(details)
    return details ~= nil
        and (
            details.spellID == SEALS
            or details.overrideSpellID == SEALS
            or details.overrideTooltipSpellID == SEALS
        )
end

local function IsSealsCd(cdID)
    if type(cdID) ~= "number" or IsSecret(cdID) then return false end
    local known = S.cd[cdID]
    if known == nil then
        local getCdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
        known = IsSealsInfo(getCdInfo and getCdInfo(cdID)) and true or false
        S.cd[cdID] = known
    end
    return known
end

-- Blizzard's Seals entry in its cooldown data, read once that has loaded: the
-- other spell IDs an entry picked from Blizzard's list may carry, and the
-- entry's linked spells (seal IDs).
local function Aliases()
    local CV = C_CooldownViewer
    local cats = Enum and Enum.CooldownViewerCategory
    if not (CV and CV.GetCooldownViewerCategorySet and CV.GetCooldownViewerCooldownInfo and cats) then
        return nil
    end
    local ids, linked = {}, {}
    for _, category in pairs(cats) do
        local success, set = pcall(CV.GetCooldownViewerCategorySet, category, true)
        if success and type(set) == "table" then
            for _, cdID in ipairs(set) do
                local details = type(cdID) == "number"
                    and not IsSecret(cdID)
                    and CV.GetCooldownViewerCooldownInfo(cdID)
                if details and IsSealsInfo(details) then
                    S.cd[cdID] = true
                    local a, b = details.spellID, details.overrideSpellID
                    if type(a) == "number" and a > 0 and a ~= SEALS then ids[#ids + 1] = a end
                    if type(b) == "number" and b > 0 and b ~= SEALS then ids[#ids + 1] = b end
                    if type(details.linkedSpellIDs) == "table" then
                        for index = 1, #details.linkedSpellIDs do
                            linked[#linked + 1] = details.linkedSpellIDs[index]
                        end
                    end
                end
            end
        end
    end
    S.linked = linked
    return ids
end

local function AddID(set, nameList, ident)
    if type(ident) ~= "number" or IsSecret(ident) or ident <= 0 then return end
    set[ident] = true
    local name = C_Spell.GetSpellName(ident)
    if name then nameList[name] = true end
end

-- Every seal id: the seeds, the entry's linked spells, and every spellbook
-- spell (each rank is its own spell on Forever) sharing their names.
local function Include()
    local set, nameList = {}, {}
    for index = 1, #SEAL_SEEDS do
        AddID(set, nameList, SEAL_SEEDS[index])
    end
    local linked = S.linked
    if linked then
        for index = 1, #linked do
            AddID(set, nameList, linked[index])
        end
    end
    local known = false
    pcall(function()
        local bank = Enum.SpellBookSpellBank.Player
        local SPELL = Enum.SpellBookItemType.Spell
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
            local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if li and li.itemIndexOffset and li.numSpellBookItems then
                for slot = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                    local it = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                    local spellRef = it and it.itemType == SPELL and it.spellID
                    if spellRef then
                        local name = C_Spell.GetSpellName(spellRef)
                        if name and nameList[name] then
                            set[spellRef] = true
                            known = true
                        end
                    end
                end
            end
        end
    end)
    S.known = known
    local ids = {}
    for ident in pairs(set) do
        ids[#ids + 1] = ident
    end
    table.sort(ids)
    return set, table.concat(ids, ",")
end

local function Icon()
    if not S.art then
        S.art = C_Spell.GetSpellTexture(SEALS)
        for index = 1, #SEAL_SEEDS do
            if S.art then break end
            S.art = C_Spell.GetSpellTexture(SEAL_SEEDS[index])
        end
    end
    return S.art
end

-- After a reanchor that placed the stand-in: Blizzard's own Seals frame on a
-- bar means its fix landed, so the stand-in stands down for the session (the
-- next reanchor drops its frames).
local function Placed()
    if S.native then return end
    local icons = mod.cdmBarIcons
    if not icons then return end
    for _, entries in pairs(icons) do
        for index = 1, #entries do
            local frame = entries[index]
            if
                frame
                and not frame._isPresetFrame
                and not frame._isPlaceholderFrame
                and IsSealsCd(frame.cooldownID)
            then
                S.native = true
                if mod.QueueReanchor then mod.QueueReanchor() end
                return
            end
        end
    end
end

mod.CDM_AuraIconProvider(SEALS, {
    key = "seals",
    tip = SEALS,
    Include = Include,
    Icon = Icon,
    -- Grey only while no seal is known; a seal that is down is the Seals icon.
    Desaturate = function() return not S.known end,
    Off = function() return S.native end,
    Aliases = Aliases,
    Placed = Placed,
})
