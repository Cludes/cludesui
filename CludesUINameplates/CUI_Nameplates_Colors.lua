if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Nameplates_Colors.lua
--
--  Threat context, quest mob detection and the plate colors (class, threat,
--  reaction).
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._npInternals
-- CludesUINameplates.lua or an earlier nameplate file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local pairs, ipairs, type = pairs, ipairs, type
local UnitIsUnit, UnitCanAttack = UnitIsUnit, UnitCanAttack
local UnitIsEnemy, UnitIsTapDenied = UnitIsEnemy, UnitIsTapDenied
local UnitAffectingCombat, UnitClassification = UnitAffectingCombat, UnitClassification
local UnitReaction = UnitReaction
local UnitIsPlayer, UnitClass = UnitIsPlayer, UnitClass
local Enum = Enum

local defaultSet, GetTextSlot, IsComboHealthText = Inner.defaults, Inner.GetTextSlot, Inner.IsComboHealthText
local MaybeDarken = Inner.MaybeDarken

local p
Inner.profileSetters[#Inner.profileSetters + 1] = function(val)
    p = val
    mod._questObjectiveTypeEnabled = val and val.showQuestObjectiveTypeIcon == true or false
end

-- Cached threat-context state; updated at zone transitions and spec changes
local _inThreatContent = false
local _isTankRole = false

-- Off-tank color under identity restriction: the mob-target ROLE is secret, so
-- the question flips sides -- "is any OTHER tank tanking this mob" -- via
-- UnitDetailedThreatSituation(tankToken, mob) (plain tokens in; isTanking
-- boolean out, plain or secret; field-probed real boolean in keys) folded
-- through C_CurveUtil.EvaluateColorValueFromBoolean so no secret is ever read
-- in Lua. Returns ok plus possibly-SECRET r,g,b, and a: 1 while another tank
-- holds the mob, else 0 (the debuff colors' bad-threat alpha). The caller must
-- hand them to SETTERS ONLY -- never compare, cache, multiply or format them. Tank tokens
-- rebuild lazily off ns._otherTanksDirty (set by RefreshThreatCache's existing
-- roster/role/zone events -- zero new registrations; own-group role reads are
-- plain). On ns (file is at the 200-local cap).
function mod.ComputeOffTankFold(unitToken, br, backdrop, bb, otr, otg, otb)
    local eval = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
    if not eval then
        return false
    end
    if mod._otherTanksDirty or not mod._otherTankTokens then
        mod._otherTanksDirty = false
        local t = mod._otherTankTokens
        if t then
            wipe(t)
        else
            t = {}
            mod._otherTankTokens = t
        end
        local num = 0
        local prefixText, total
        if IsInRaid() then
            prefixText, total = "raid", GetNumGroupMembers()
        elseif IsInGroup() then
            prefixText, total = "party", GetNumGroupMembers() - 1
        end
        if prefixText then
            for idx = 1, total do
                if num >= 3 then
                    break
                end
                local tok = prefixText .. idx
                if not UnitIsUnit(tok, "player") and UnitGroupRolesAssigned(tok) == "TANK" then
                    num = num + 1
                    t[num] = tok
                end
            end
        end
    end
    local toks = mod._otherTankTokens
    if not toks[1] then
        return false
    end
    -- All colors arrive from the caller: the _C accessor is declared far BELOW
    -- this function, so resolving colors here read a nil global (field crash).
    local r, g, b, a = br, backdrop, bb, 0
    if not (r and otr) then
        return false
    end
    for idx = 1, #toks do
        local isTanking = UnitDetailedThreatSituation(toks[idx], unitToken)
        -- type() is legal on secrets and reports the underlying type, so one
        -- check admits both plain and secret booleans; a refused call (nil)
        -- skips and the accumulator keeps the safe tankNoAggro color.
        if type(isTanking) == "boolean" then
            r = eval(isTanking, otr, r)
            g = eval(isTanking, otg, g)
            b = eval(isTanking, otb, b)
            a = eval(isTanking, 1, a)
        end
    end
    return true, r, g, b, a
end

-- A damage dealer's or healer's threat colors mean something only while someone else can
-- hold the mob: in a group, or solo with a pet out (the pet tanking). Solo without one,
-- every mob that has the player on its threat table is on the player. Show Threat Colors
-- "alwaysSolo" (Always) drops the rule: threatAll, set by NP_RefreshThreatColorFlag.
local threatAll = false
local function ThreatShared()
    return threatAll or IsInGroup() or UnitExists("pet")
end

-- The pet coming or going changes that answer for a solo non-tank, so the plates repaint
-- then. Listens only while the threat colors are on (NP_RefreshThreatColorFlag).
local petFrame, petOn
local function PetSync(on)
    on = on and true or false
    if on == (petOn or false) then
        return
    end
    petOn = on
    if not petFrame then
        petFrame = CreateFrame("Frame")
        petFrame:SetScript("OnEvent", function()
            if not _isTankRole and not IsInGroup() then
                for _, backing in pairs(mod.plates) do
                    backing:UpdateHealthColor()
                end
            end
        end)
    end
    if on then
        petFrame:RegisterUnitEvent("UNIT_PET", "player")
    else
        petFrame:UnregisterAllEvents()
    end
end

-- WoW Forever has no specs, so the effective role is only the group's assigned one there:
-- the player also counts as the tank in Bear Form, Dire Bear Form or Defensive Stance
-- (CludesUI.ForeverTankForm) or with Righteous Fury up, while nobody in the group has
-- the tank role assigned (fvRoleTank; with one, the role alone decides). FV_TANK_CLASS (nil
-- off Forever and for every other class) names what a warrior, druid or paladin is watched
-- for. The watcher is armed only while the threat colors are on: the form event for the
-- shapes, the player's aura event for Righteous Fury, its payload probed for that one aura
-- (a restricted read keeps the last answer). A changed verdict repaints the plates.
local FV_TANK_CLASS = CludesUI.IS_FOREVER
        and ({ WARRIOR = "form", DRUID = "form", PALADIN = "fury" })[select(2, UnitClass("player"))]
    or nil
local FV_FURY = 25780
local fvFury, fvFuryInst = false, nil
local fvTankFrame, fvTankOn
local fvRoleTank = false

-- The group's assigned tank, read as the watcher arms and on every roster and role event
-- while it is armed (RefreshThreatCache); a restricted read that finds none keeps the last
-- answer.
local function FvReadRoleTank()
    local has, unsure = CludesUI.GroupHasTankRole()
    if has or not unsure then
        fvRoleTank = has
    end
end

-- Righteous Fury's state, read only while the aura is readable (outside an aura
-- restriction nothing is secret).
local function FvReadFury()
    local Stl = C_Secrets
    if Stl and Stl.ShouldSpellAuraBeSecret then
        local success, secret = pcall(Stl.ShouldSpellAuraBeSecret, FV_FURY)
        if not success or issecretvalue(secret) or secret ~= false then
            return
        end
    end
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(FV_FURY)
    if issecretvalue(aura) then
        return
    end
    fvFury = aura ~= nil
    local iid = aura and aura.auraInstanceID
    fvFuryInst = (not issecretvalue(iid)) and iid or nil
end

-- The player aura event: true when Righteous Fury may have come or gone (re-read on a full
-- update; an added instance of it, or the removal of the one held, otherwise).
local function FvFuryProbe(details)
    if issecretvalue(details) then
        return false
    end
    if not details then
        FvReadFury()
        return true
    end
    local full = details.isFullUpdate
    if issecretvalue(full) then
        return false
    end
    if full then
        FvReadFury()
        return true
    end
    local added = details.addedAuras
    if not issecretvalue(added) and added then
        for idx = 1, #added do
            local a = added[idx]
            if not issecretvalue(a) then
                local spellRef = a.spellId
                if not issecretvalue(spellRef) and spellRef == FV_FURY then
                    local iid = a.auraInstanceID
                    fvFury = true
                    fvFuryInst = (not issecretvalue(iid)) and iid or nil
                    return true
                end
            end
        end
    end
    local removed = details.removedAuraInstanceIDs
    if fvFuryInst and not issecretvalue(removed) and removed then
        for idx = 1, #removed do
            local iid = removed[idx]
            if not issecretvalue(iid) and iid == fvFuryInst then
                fvFury, fvFuryInst = false, nil
                return true
            end
        end
    end
    return false
end

-- The player's tank verdict: the effective role, plus the Forever shapes and Righteous Fury
-- while the group has no assigned tank.
local function PlayerTankVerdict()
    if CludesUI.UnitEffectiveRole("player") == "TANK" then
        return true
    end
    if not FV_TANK_CLASS or fvRoleTank then
        return false
    end
    return CludesUI.ForeverTankForm() or fvFury
end

local function FvTankOnEvent(_, evt, _, details)
    if evt == "UNIT_AURA" and not FvFuryProbe(details) then
        return
    end
    local was = _isTankRole
    _isTankRole = PlayerTankVerdict()
    if _isTankRole ~= was then
        for _, backing in pairs(mod.plates) do
            backing:UpdateHealthColor()
        end
    end
end

-- Arms the watcher while the threat colors are on (re-reading the verdict as it arms: the
-- shape or the aura may have changed while it slept), parks it otherwise.
local function FvTankSync(on)
    if not FV_TANK_CLASS then
        return
    end
    on = on and true or false
    if on == (fvTankOn or false) then
        return
    end
    fvTankOn = on
    if not fvTankFrame then
        fvTankFrame = CreateFrame("Frame")
        fvTankFrame:SetScript("OnEvent", FvTankOnEvent)
    end
    if on then
        if FV_TANK_CLASS == "fury" then
            fvTankFrame:RegisterUnitEvent("UNIT_AURA", "player")
            FvReadFury()
        else
            fvTankFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        end
        FvReadRoleTank()
        _isTankRole = PlayerTankVerdict()
    else
        fvTankFrame:UnregisterAllEvents()
    end
end

-- Show Threat Colors (threatColorMode): "always" (Group or Pet) colors every plate that
-- has threat data, "alwaysSolo" (Always) too and drops the group-or-pet rule for damage
-- dealers and healers (ThreatShared), "instances" colors only inside threat content (the
-- zone verdict RefreshThreatCache caches), "never" switches the whole threat-color
-- feature off (health-bar arm, Border / Name channels, Near Aggro glow, off-tank fold).
-- Materialized into ns._npThreatColorsOn (and threatAll) so the per-plate color paths pay
-- one field read; re-derived by RefreshThreatCache (zone, role, spec), RefreshAllSettings
-- (profile and override swaps), OnEnable and the options setter. An unknown saved value
-- reads as the default. Arms the Forever tank watcher with it, and the pet listener while
-- a pet can still change the answer.
mod._npThreatColorsOn = false
function mod.NP_RefreshThreatColorFlag()
    local modeName = p and p.threatColorMode
    if
        modeName ~= "never"
        and modeName ~= "instances"
        and modeName ~= "always"
        and modeName ~= "alwaysSolo"
    then
        modeName = defaultSet.threatColorMode
    end
    threatAll = modeName == "alwaysSolo"
    mod._npThreatColorsOn = (
        threatAll
        or modeName == "always"
        or (modeName == "instances" and _inThreatContent)
    )
            and true
        or false
    PetSync(mod._npThreatColorsOn and not threatAll)
    FvTankSync(mod._npThreatColorsOn)
end

local function RefreshThreatCache()
    mod._otherTanksDirty = true
    -- Zone: party/raid instances and delves (difficultyID 204) are threat-relevant
    local _, instanceType, difficultyID = GetInstanceInfo()
    difficultyID = tonumber(difficultyID) or 0
    -- Dungeon-only flag for the "Mini Enemies" trash color (instanceType "party"; excludes
    -- raids/delves/open world). Cached so the per-plate color path costs one field read.
    mod._inDungeon = (instanceType == "party")
    if difficultyID == 0 or (C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap()) then
        _inThreatContent = false
    else
        local isDelve = C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress()
        _inThreatContent = (instanceType == "party" or instanceType == "raid" or isDelve)
    end
    -- Role: cache so we don't recalculate on every nameplate update. Effective
    -- role (CludesUI.UnitEffectiveRole): the player's spec wins over a stale
    -- premade-listing role (listed as tank, playing dps), and still covers the
    -- solo "NONE" case the old spec fallback existed for; WoW Forever adds the
    -- tank shapes and Righteous Fury while the group has no assigned tank
    -- (PlayerTankVerdict).
    if FV_TANK_CLASS == "fury" then
        FvReadFury()
    end
    if fvTankOn then
        FvReadRoleTank()
    end
    _isTankRole = PlayerTankVerdict()
    mod.NP_RefreshThreatColorFlag()
end

-- Threat-content zone verdict (party/raid instances, delves). The classification icon's
-- open-world rule reads it; the threat colors read ns._npThreatColorsOn instead.
local function InRealInstancedContent()
    return _inThreatContent
end

-------------------------------------------------------------------------------
--  Quest Mob Detection: C_TooltipInfo scans unit tooltips for quest objective lines. Cached
--  per unit; invalidated on QUEST_LOG_UPDATE and NAME_PLATE_UNIT_REMOVED.
-------------------------------------------------------------------------------
local questMobCache = {}
local questObjectiveTypeCache = {}
-- Parallel cache of verified-clean "objectives remaining" strings, keyed by unit. Populated
-- only while the Quest Objective Text element is on; same invalidation lifecycle. On ns (cap).
mod._questObjText = mod._questObjText or {}
mod._questObjType = mod._questObjType or {}
local function ResolveQuestObjectiveType(questID, tooltipText, isOnQuest)
    if not issecretvalue then
        return nil
    end
    if issecretvalue(questID) or issecretvalue(isOnQuest) or issecretvalue(tooltipText) then
        return nil
    end
    if
        type(questID) ~= "number"
        or questID <= 0
        or questID % 1 ~= 0
        or isOnQuest ~= true
        or type(tooltipText) ~= "string"
        or not (C_QuestLog and C_QuestLog.GetQuestObjectives)
    then
        return nil
    end

    local objectives = questObjectiveTypeCache[questID]
    if objectives == nil then
        local result = C_QuestLog.GetQuestObjectives(questID)
        if issecretvalue(result) or type(result) ~= "table" then
            questObjectiveTypeCache[questID] = false
            return nil
        end
        objectives = {}
        for slotPos, objective in ipairs(result) do
            local textValue, objectiveType
            if not issecretvalue(objective) and objective then
                textValue, objectiveType = objective.text, objective.type
                if issecretvalue(textValue) then
                    textValue = nil
                end
                if issecretvalue(objectiveType) then
                    objectiveType = nil
                end
                if type(textValue) ~= "string" then
                    textValue = nil
                end
                if type(objectiveType) ~= "string" then
                    objectiveType = nil
                end
            end
            objectives[slotPos] = { text = textValue, type = objectiveType }
        end
        questObjectiveTypeCache[questID] = objectives
    elseif objectives == false then
        return nil
    end

    local matchCount, matchedType, unreadableText = 0, nil, false
    for _, objective in ipairs(objectives) do
        if not objective.text then
            unreadableText = true
        elseif objective.text == tooltipText then
            matchCount = matchCount + 1
            matchedType = objective.type
        end
    end
    if unreadableText or matchCount ~= 1 then
        return nil
    end
    if matchedType == "monster" or matchedType == "item" then
        return matchedType
    end
end
-- Is this unit one of the local player's active quest objectives with work remaining? Read
-- from the tooltip's structured data: a QuestObjective line carries `completed` plus
-- numFulfilled/numRequired, a QuestTitle line the quest id, so completion needs no
-- progress-string parsing. Ownership goes through the player's own quest log (only their
-- quests answer C_QuestLog.IsOnQuest), so a group member's objective is ignored. Every
-- structured value is possibly secret and issecretvalue-checked before use. Cached per unit;
-- cleared on QUEST_LOG_UPDATE, plate removal and zone changes.
local IsQuestMob
do
    -- The settings both caches were built under (ScanState); a call under other settings
    -- wipes them first, so a cache never answers for settings it was not built with.
    local built, builtType
    -- 1 while the Quest Objective Text element is on (the scan reads the objective text).
    -- In instanced content, plus 2 while a consumer may show the result there (the Quest
    -- Indicator, the quest mob health colour or the Quest Objective Text, each with its Show
    -- In Instances), else plus 4 (no scan: every unit reads as no quest mob). Open world: 0 / 1.
    local function ScanState()
        local st = (mod.NP_GetQuestTextSlot() ~= "none") and 1 or 0
        if InRealInstancedContent() then
            local success = (
                mod.NP_ShowInInstances("quest")
                and (mod.NP_QuestIconOn() or (p and p.questMobColorEnabled) == true)
            ) or (st == 1 and mod.NP_ShowInInstances("questtext"))
            st = st + (success and 2 or 4)
        end
        return st
    end
    IsQuestMob = function(unitToken)
        if not (C_TooltipInfo and Enum and Enum.TooltipDataLineType) then
            return false
        end
        local st = ScanState()
        local typeOn = p and p.showQuestObjectiveTypeIcon == true or false
        if st ~= built or typeOn ~= builtType then
            wipe(questMobCache)
            wipe(mod._questObjText)
            if typeOn then
                wipe(questObjectiveTypeCache)
                wipe(mod._questObjType)
            end
            built = st
            builtType = typeOn
        end
        local cached = questMobCache[unitToken]
        if cached ~= nil then
            return cached
        end

        -- Instanced content with no consumer that shows the result there: no scan.
        if st >= 4 then
            questMobCache[unitToken] = false
            return false
        end

        local details = C_TooltipInfo.GetUnit(unitToken)
        if not (details and details.lines) then
            questMobCache[unitToken] = false
            return false
        end

        local LT = Enum.TooltipDataLineType
        local onQuest = C_QuestLog and C_QuestLog.IsOnQuest
        local wantText = (st % 2) == 1
        local wantType = wantText and typeOn
        if wantType then
            mod._questObjType[unitToken] = nil
        end
        local questID -- id carried by the most recent QuestTitle line
        local isQuest, objText = false, nil

        for _, lineTex in ipairs(details.lines) do
            local kindOf = lineTex.type
            if kindOf == LT.QuestTitle then
                local ident = lineTex.id
                if ident and not (issecretvalue and issecretvalue(ident)) then
                    questID = ident
                else
                    questID = nil
                end
            elseif kindOf == LT.QuestObjective then
                local done = lineTex.completed
                -- An incomplete objective the player is actually on: their quest log scopes out
                -- a group member's objectives. Fail open when the id is unreadable so a real
                -- quest mob is never silently skipped.
                if not (issecretvalue and issecretvalue(done)) and done == false then
                    local onQuestResult = true
                    if questID and onQuest then
                        onQuestResult = onQuest(questID)
                    end
                    if onQuestResult then
                        isQuest = true
                        if wantText then
                            local have, need = lineTex.numFulfilled, lineTex.numRequired
                            if
                                have
                                and need
                                and not (issecretvalue and (issecretvalue(have) or issecretvalue(need)))
                            then
                                -- Percent-style objectives (area progress bars)
                                -- degenerate to 0/1 in the structured fields; the
                                -- real progress lives only in the line text. Show
                                -- the extracted percent when readable, else the
                                -- count (real 0/1 kill objectives keep their count).
                                local lt = lineTex.leftText
                                local pct
                                if
                                    lt
                                    and not (issecretvalue and issecretvalue(lt))
                                    and type(lt) == "string"
                                then
                                    pct = lt:match("(%d+)%s*%%")
                                end
                                objText = pct and (pct .. "%") or (have .. "/" .. need)
                                if
                                    wantType
                                    and objText
                                    and questID
                                    and onQuest
                                    and issecretvalue
                                    and not issecretvalue(onQuestResult)
                                    and onQuestResult == true
                                then
                                    mod._questObjType[unitToken] =
                                        ResolveQuestObjectiveType(questID, lt, onQuestResult)
                                end
                            end
                        end
                        break
                    end
                end
            end
        end

        questMobCache[unitToken] = isQuest
        if wantText then
            mod._questObjText[unitToken] = isQuest and objText or nil
        end
        return isQuest
    end
end
mod.IsQuestMob = IsQuestMob

-- The Quest Objective Text element's reader. Returns a clean "have/need" or "N%" string, or
-- nil (no readable count or percent).
function mod.GetQuestObjectiveText(unitToken)
    return mod._questObjText[unitToken]
end
function mod.GetQuestObjectiveType(unitToken)
    return mod._questObjType[unitToken]
end
function mod.InvalidateQuestObjectiveTypeCache()
    if not mod._questObjectiveTypeEnabled then
        return
    end
    wipe(questObjectiveTypeCache)
    wipe(mod._questObjType)
end

-- Live refresh for the quest options (the Rare/Quest and Quest Objective Text boxes, Show In
-- Instances, Text Size). Wiping BOTH caches is required: IsQuestMob short-circuits on
-- questMobCache[unit] ~= nil, so a unit cached without its objective text never gets it.
function mod.RefreshQuestObjective()
    wipe(questMobCache)
    wipe(mod._questObjText)
    mod._questObjectiveTypeEnabled = p and p.showQuestObjectiveTypeIcon == true or false
    mod.InvalidateQuestObjectiveTypeCache()
    for _, backing in pairs(mod.plates) do
        if backing.UpdateClassification then
            backing:UpdateClassification()
        end
    end
end

-- Invalidate quest cache on quest log changes (throttled to avoid
-- recoloring all plates on every QUEST_LOG_UPDATE burst).
local questCacheWatcher = CreateFrame("Frame")
questCacheWatcher:RegisterEvent("QUEST_LOG_UPDATE")
mod._questDirty = false
questCacheWatcher:SetScript("OnEvent", function()
    wipe(questMobCache)
    wipe(mod._questObjText)
    mod.InvalidateQuestObjectiveTypeCache()
    if not mod._questDirty then
        mod._questDirty = true
        C_Timer.After(0.5, function()
            mod._questDirty = false
            for _, backing in pairs(mod.plates) do
                backing:UpdateHealthColor()
                backing:UpdateClassification()
            end
        end)
    end
end)

local function _C(key)
    return (p and p[key]) or defaultSet[key]
end
-- Neutral health-bar color: the enemy fallback's color while in combat (All Enemies while
-- Simple Coloring When Not In M+ applies outside 5-man dungeons, as step 11 picks it, else
-- Enemies), else the neutral color. Shared by every precedence step resolving to "neutral"
-- (step 5, neutral+mini carve-out 7b, dungeon 10d).
local function ResolveNeutralColor(unitToken)
    if UnitAffectingCombat(unitToken) then
        local key = "enemyInCombat"
        if not mod._inDungeon then
            local simple = p and p.owBasicColoring
            if simple == nil then
                simple = defaultSet.owBasicColoring
            end
            if simple then
                key = "owBasicColor"
            end
        end
        local c = _C(key)
        return c.r, c.g, c.b
    end
    local c = _C("neutral")
    return c.r, c.g, c.b
end
-- The Hostile or Neutral name colour (enemyNameHostileColor / enemyNameNeutralColor, shared
-- by every text slot) for an NPC in a Hostility / Class text slot, matching the unit's
-- reaction independent of the health-bar palette. Every NameplateFrame unit is an enemy
-- (HideBlizzardFrame only suppresses Blizzard's frame on UnitCanAttack units), so only
-- these two reactions are ever relevant here. Same
-- reaction/UnitCanAttack idiom as the health-bar Neutral check below (GetReactionColor step 5)
-- so a secret reaction read (identity-restricted units) falls through safely instead of erroring.
local function GetEnemyNameReactionColor(unitToken)
    local reaction = UnitReaction(unitToken, "player")
    local isNeutral = (reaction and reaction == 4)
        or (UnitCanAttack("player", unitToken) and not UnitIsEnemy(unitToken, "player"))
    local saved = p or defaultSet
    local c
    if isNeutral then
        c = saved.enemyNameNeutralColor or defaultSet.neutral
    else
        c = saved.enemyNameHostileColor or defaultSet.hostile
    end
    return c.r, c.g, c.b
end

-- Core Text Coloring (ns.NP_SlotColorMode, per slot): a slot in
-- Hostility / Class ("class") or Level Difficulty ("level") mode has whatever it shows
-- painted per unit from UpdateHealthColor; "custom" keeps the static slot colour.
-- ns._npSlotClassOn is materialized at login and by RefreshAllSettings (also the Spec
-- Overrides refresher), so UpdateHealthColor pays one boolean read while every slot is
-- custom. ns fields throughout: this file is at its local cap.
mod._npSlotClassOn = false
mod._npSlotClassName = false
mod._npSlotClassFS = {} -- plate font string keys painted in class mode
mod._npSlotLevelFS = {} -- plate font string keys painted in level mode
mod._npSlotLevelCK = {} -- parallel: the owning slot's colour key (unreadable-level fallback)
-- Materialized with the class flags: the font string key each bottom slot owns
-- (false = none, or a later slot rewrites that shared font string), whether
-- either owns one (the cast show / hide re-anchor runs only then), the same for
-- the top corner slots (their re-anchor follows the class power push with the
-- name's), and the slot showing Target of Target (false = none; its UNIT_TARGET
-- registration follows it) plus whether that slot is in class mode. _npToTUnits
-- caches "<unit>target". _npCustomTgt: a custom text reads [target] (UNIT_TARGET
-- follows it too). _npTgtTexts: either is shown, the one gate of every target-text
-- trigger.
mod._npBottomFS = { false, false }
mod._npBottomUsed = false
mod._npTopCornerFS = { false, false }
mod._npTopCornerUsed = false
mod._npToTSlot = false
mod._npToTClass = false
mod._npToTColorKey = nil
mod._npToTUnits = {}
mod._npCustomTgt = false
mod._npTgtTexts = false
do
    -- The order ApplyHealthTextAppearance lays the slots out in (the HP_BAR_SLOTS
    -- entries, then Top): the last slot writing a shared font string owns it.
    -- Indexes 4, 5 are the bottom corners, 6, 7 the top corners.
    local SLOTS = {
        "textSlotRight",
        "textSlotLeft",
        "textSlotCenter",
        "textSlotBottomLeft",
        "textSlotBottomRight",
        "textSlotTopLeft",
        "textSlotTopRight",
        "textSlotTop",
    }
    local ownerFrame, ownerSlot, lastIdx = {}, {}, {}
    local COLOR_KEY = {} -- slot -> its colour key (prebuilt for UpdateToT and the painter)
    for idx = 1, #SLOTS do
        COLOR_KEY[SLOTS[idx]] = SLOTS[idx] .. "Color"
    end
    -- The plate font string key an element renders on (nil for None). slot: the slot
    -- showing it, which picks a custom text's own font string.
    function mod.NP_ElementFSKey(el, slotIndex)
        if el == "custom" then
            return slotIndex and mod.NP_CustomFSKey[slotIndex]
        end
        if mod.IsNameElement(el) then
            return "name"
        end
        if el == "level" then
            return "levelText"
        end
        if el == "targetOfTarget" then
            return "totText"
        end
        if el == "healthNumber" then
            return "hpNumber"
        end
        if el == "healthPercent" or el == "healthPercentNoSign" or IsComboHealthText(el) then
            return "hpText"
        end
    end
    function mod.NP_RefreshSlotClassFlags()
        local L, V, VC = mod._npSlotClassFS, mod._npSlotLevelFS, mod._npSlotLevelCK
        wipe(L)
        wipe(V)
        wipe(VC)
        wipe(ownerFrame)
        wipe(ownerSlot)
        wipe(lastIdx)
        mod._npToTSlot = false
        mod._npToTClass = false
        mod._npCustomTgt = false
        local B, T = mod._npBottomFS, mod._npTopCornerFS
        -- The name is placed in FindNameSlot's slot (the first holding one), the
        -- other shared font strings by the last slot writing them.
        local nameSlot = mod.FindNameSlot()
        for idx = 1, #SLOTS do
            local s = SLOTS[idx]
            local el = GetTextSlot(s)
            local key = mod.NP_ElementFSKey(el, s)
            if el == "custom" and not mod._npCustomTgt then
                local parsed = mod.NP_CustomParse(s)
                mod._npCustomTgt = (parsed and parsed.reads.tgt) or false
            end
            if key == "totText" then
                -- Painted by UpdateToT from the target's class, never the plate unit's.
                mod._npToTSlot = s
                mod._npToTClass = mod.NP_SlotColorMode(s) == "class"
            elseif key and (key ~= "name" or s == nameSlot) then
                ownerFrame[key] = mod.NP_SlotColorMode(s)
                ownerSlot[key] = s
            end
            if key then
                lastIdx[key] = idx
            end
            if idx == 4 or idx == 5 then
                B[idx - 3] = key or false
            end
            if idx == 6 or idx == 7 then
                T[idx - 5] = key or false
            end
        end
        for b = 1, 2 do
            if B[b] == "name" then
                if nameSlot ~= SLOTS[b + 3] then
                    B[b] = false
                end
            elseif B[b] and lastIdx[B[b]] ~= b + 3 then
                B[b] = false
            end
            if T[b] == "name" then
                if nameSlot ~= SLOTS[b + 5] then
                    T[b] = false
                end
            elseif T[b] and lastIdx[T[b]] ~= b + 5 then
                T[b] = false
            end
        end
        mod._npToTColorKey = mod._npToTSlot and COLOR_KEY[mod._npToTSlot] or nil
        mod._npTgtTexts = (mod._npToTSlot or mod._npCustomTgt) and true or false
        mod._npBottomUsed = (B[1] or B[2]) and true or false
        mod._npTopCornerUsed = (T[1] or T[2]) and true or false
        for key, modeName in pairs(ownerFrame) do
            if modeName == "class" then
                L[#L + 1] = key
            elseif modeName == "level" then
                V[#V + 1] = key
                VC[#V] = COLOR_KEY[ownerSlot[key]]
            end
        end
        mod._npSlotClassName = ownerFrame.name == "class" or ownerFrame.name == "level"
        mod._npSlotClassOn = (L[1] or V[1]) and true or false
        -- The name text's combo part colours (read by SetNameElementText).
        mod.NP_RefreshSlotNameParts()
    end
end
-- Paints one plate's class- and level-mode slots. Class mode: enemy players take the CUI
-- class palette (CludesUI.GetClassColor: custom class colours count; the bar's own class
-- colour reads RAID_CLASS_COLORS, so the two differ only under a custom palette). A redacted
-- class token takes the restricted-unit palette, else Blizzard's class colour, handed
-- straight to the font strings and never memoized (the memo entry is cleared instead).
-- Tapped NPCs take the Tapped name colour (default: the plate's Tapped grey), other
-- NPCs the Hostile / Neutral name colours. The class token is read once per unit (keyed
-- on the unit token; ClearUnit resets it). Level mode: the unit's level difficulty colour
-- (NP_UnitLevelColor); while the level cannot be read the slot colour is written once
-- (memo marker false). Per font string memo on our plate (_scMemo), reset wherever the
-- slot colours are written statically. Returns true while the name's slot is in either
-- mode. An inline colour escape in the text (a Level | Name part colour) still wins over
-- it. skipName leaves the name alone (Threat Colors "Text" holds it) and drops its memo
-- entry, so the first call without it repaints the name. A custom text's font string
-- is missing until the plate's next appearance pass builds it: skipped until then.
function mod.NP_PaintSlotClassColors(backing, unitToken, skipName)
    local m = backing._scMemo
    if not m then
        m = {}
        backing._scMemo = m
    end
    local L = mod._npSlotClassFS
    if L[1] then
        if backing._scUnit ~= unitToken then
            backing._scUnit = unitToken
            local tok = false
            if UnitIsPlayer(unitToken) then
                local _, t = UnitClass(unitToken)
                if issecretvalue(t) then
                    tok = true
                elseif t then
                    tok = t
                end
            end
            backing._scTok = tok
        end
        local tok = backing._scTok
        local painted = false
        if tok == true then
            local _, t = UnitClass(unitToken)
            local success, sr, sg, scrollBar = CludesUI.GetClassColorForRestrictedUnit(unitToken, t)
            if not success then
                local c = C_ClassColor.GetClassColor(t)
                if c then
                    success = true
                    sr, sg, scrollBar = c:GetRGB()
                end
            end
            if success then
                painted = true
                for idx = 1, #L do
                    local key = L[idx]
                    local e = m[key]
                    if e then
                        e[1] = nil
                    end
                    if not (skipName and key == "name") then
                        local fontStr = backing[key]
                        if fontStr then
                            fontStr:SetTextColor(sr, sg, scrollBar, 1)
                        end
                    end
                end
            end
        end
        if not painted then
            local r, g, b
            if tok and tok ~= true then
                local c = CludesUI.GetClassColor(tok)
                r, g, b = c.r, c.g, c.b
            elseif UnitIsTapDenied(unitToken) then
                local c = (p and p.enemyNameTappedColor) or _C("tapped")
                r, g, b = c.r, c.g, c.b
            else
                r, g, b = GetEnemyNameReactionColor(unitToken)
            end
            for idx = 1, #L do
                local key = L[idx]
                local e = m[key]
                if not e then
                    e = {}
                    m[key] = e
                end
                if skipName and key == "name" then
                    e[1] = nil
                elseif e[1] ~= r or e[2] ~= g or e[3] ~= b then
                    e[1], e[2], e[3] = r, g, b
                    local fontStr = backing[key]
                    if fontStr then
                        fontStr:SetTextColor(r, g, b, 1)
                    end
                end
            end
        end
    end
    local V = mod._npSlotLevelFS
    if V[1] then
        local r, g, b = mod.NP_UnitLevelColor(unitToken)
        for idx = 1, #V do
            local key = V[idx]
            local e = m[key]
            if not e then
                e = {}
                m[key] = e
            end
            if skipName and key == "name" then
                e[1] = nil
            elseif not r then
                if e[1] ~= false then
                    e[1] = false
                    local ck = mod._npSlotLevelCK[idx]
                    local c = (p and p[ck]) or defaultSet[ck]
                    local fontStr = backing[key]
                    if fontStr then
                        fontStr:SetTextColor(c.r, c.g, c.b, 1)
                    end
                end
            elseif e[1] ~= r or e[2] ~= g or e[3] ~= b then
                e[1], e[2], e[3] = r, g, b
                local fontStr = backing[key]
                if fontStr then
                    fontStr:SetTextColor(r, g, b, 1)
                end
            end
        end
    end
    return mod._npSlotClassName
end
-- Threat Colors channels (multi-check on the Threat Colors section). All three on ns:
-- the module file is at the 200-local cap. Health Bar defaults ON so nothing changes
-- for an existing profile; Border/Text default OFF.
function mod.GetThreatColorHealth()
    local val = p and p.threatColorHealth
    if val == nil then
        return defaultSet.threatColorHealth
    end
    return val
end
function mod.GetThreatColorBorder()
    local val = p and p.threatColorBorder
    if val == nil then
        return defaultSet.threatColorBorder
    end
    return val
end
function mod.GetThreatColorName()
    local val = p and p.threatColorName
    if val == nil then
        return defaultSet.threatColorName
    end
    return val
end
-- The threat color for the SECOND channels (border / name text), resolved independently
-- of the health bar's priority chain. GetReactionColor cannot answer this: there the
-- threat colors compete with tapped/quest/target/focus/mob-type and lose (or win) by
-- priority, while a border/name channel exists precisely so the threat signal is never
-- traded against the type signal. Same role arms, same colors and same enable toggles as
-- the health arm, minus every priority interaction:
--   tank      -- no aggro / losing aggro always; off-tank color when a co-tank holds it;
--               has aggro only with Tank Has Aggro (or Classic Tank Aggro) enabled
--   non-tank  -- has aggro / near aggro always; no aggro only with DPS No Aggro enabled
-- Returns nothing when there is no signal to show (Show Threat Colors off here, no threat
-- data, a non-tank solo with no pet out, or the state's color is opt-in and switched off);
-- the caller then leaves the border/name at its normal color. The fourth return is a
-- SECRET flag: true means
-- r/g/b are secret values (an off-tank C-fold over a secret isTanking read), so the caller
-- must hand them to setters only and never cache or compare them. status: the threat
-- situation this pass already read (false = no threat data), or nil to read it here; the
-- nil test reads the type tag only, since the situation read can be secret.
-- ns._threatOkA: 1 while nothing is wrong, 0 on bad threat (a non-tank with or
-- near aggro, a tank without or losing it), or the off-tank fold's secret answer;
-- the debuff colors give way on the border and name channels by it.
function mod.ResolveThreatColor(unitToken, status)
    mod._threatOkA = 1
    if not mod._npThreatColorsOn then
        return
    end
    if type(status) == "nil" then
        status = UnitThreatSituation("player", unitToken)
    end
    if not status then
        return
    end
    local saved = p or defaultSet
    if not _isTankRole then
        -- Solo with no pet out the player always has aggro: no signal (ThreatShared).
        if not ThreatShared() then
            return
        end
        if status >= 3 then
            mod._threatOkA = 0
            local c = _C("dpsHasAggro")
            return c.r, c.g, c.b, false
        elseif status >= 2 then
            mod._threatOkA = 0
            local c = _C("dpsNearAggro")
            return c.r, c.g, c.b, false
        end
        local en = defaultSet.dpsNoAggroEnabled
        if saved.dpsNoAggroEnabled ~= nil then
            en = saved.dpsNoAggroEnabled
        end
        if en then
            local c = _C("dpsNoAggro")
            return c.r, c.g, c.b, false
        end
        return
    end
    -- Tank arm.
    if status >= 3 then
        -- Holding it: nothing is wrong, so the has-aggro color only paints when the user
        -- explicitly asked for one (either toggle). Otherwise no tint at all, which is the
        -- point of a border channel: red border = someone else's mob, plain border = mine.
        local hae = defaultSet.tankHasAggroEnabled
        if saved.tankHasAggroEnabled ~= nil then
            hae = saved.tankHasAggroEnabled
        end
        if not hae then
            hae = defaultSet.classicTankAggro
            if saved.classicTankAggro ~= nil then
                hae = saved.classicTankAggro
            end
        end
        if hae then
            local c = _C("tankHasAggro")
            return c.r, c.g, c.b, false
        end
        return
    end
    if status >= 2 then
        mod._threatOkA = 0
        local c = _C("tankLosingAggro")
        return c.r, c.g, c.b, false
    end
    -- No aggro. Another TANK holding the mob is normal off-tank positioning, not a
    -- warning -- same read as the health arm, including the secret-role fallback: an
    -- identity-restricted role read cannot be compared, so the question flips sides and
    -- ns.ComputeOffTankFold answers it C-side ("is any OTHER tank tanking this mob"),
    -- starting from the tankNoAggro color and folding toward offTankAggro.
    local otE = defaultSet.offTankAggroEnabled
    if saved.offTankAggroEnabled ~= nil then
        otE = saved.offTankAggroEnabled
    end
    local baseValue = _C("tankNoAggro")
    local targetRole, roleSecret = "NONE", false
    local unitTarget = unitToken .. "target"
    if UnitExists(unitTarget) then
        local r = UnitGroupRolesAssigned(unitTarget)
        if issecretvalue(r) then
            roleSecret = true
        elseif r then
            targetRole = r
        end
    end
    if otE and roleSecret then
        local otc = _C("offTankAggro")
        local folded, fr, fg, fb, fa =
            mod.ComputeOffTankFold(unitToken, baseValue.r, baseValue.g, baseValue.b, otc.r, otc.g, otc.b)
        -- Secret when an isTanking read was: those components reach setters only. A
        -- plain fold goes through the caller's memos like any other colour.
        if folded then
            mod._threatOkA = fa
            return fr, fg, fb, (issecretvalue(fr) or issecretvalue(fg) or issecretvalue(fb))
        end
        mod._threatOkA = 0
        return baseValue.r, baseValue.g, baseValue.b, false
    end
    if targetRole == "TANK" then
        -- Co-tank holds it. With Off-Tank Color off there is no signal to show (the health
        -- arm falls through here too) -- a red border would call normal positioning a bug.
        if not otE then
            return
        end
        local c = _C("offTankAggro")
        return c.r, c.g, c.b, false
    end
    mod._threatOkA = 0
    return baseValue.r, baseValue.g, baseValue.b, false
end
-- castSeen: the plate's Color Casting Enemies memory (plate._castSeen).
local function GetReactionColor(unitToken, castSeen)
    -- Per-call marker read SYNCHRONOUSLY by UpdateHealthColor right after this
    -- returns: true only when this resolution landed on the non-tank Near
    -- Aggro color, so the near-aggro glow rides the exact same decision.
    -- On ns (module file is at the 200-local cap).
    mod._reactionNearAggro = false
    -- Same idiom, for the enemy player class color at step 6: set when the class token
    -- came back redacted, so UpdateHealthColor paints the bar from C_ClassColor instead.
    mod._reactionMirrorClass = false
    -- Same idiom, for the off-tank color under identity restriction: set when the
    -- mob-target ROLE read came back secret with Off-Tank Color enabled, so
    -- UpdateHealthColor asks ns.ComputeOffTankFold for a C-folded color instead
    -- of the plain tankNoAggro fallback this function returns.
    mod._reactionOffTankFold = false
    -- Same idiom, for the threat situation: nil until this pass reads it, then the value
    -- (false = no threat data), which UpdateHealthColor hands to ns.ResolveThreatColor
    -- instead of a second UnitThreatSituation read.
    mod._reactionThreatStatus = nil
    -- Same idiom: true when this resolution landed on bad threat (a non-tank with or
    -- near aggro, a tank without or losing it), where the debuff colors give way.
    mod._reactionBadThreat = false
    -- Same idiom: the mob-type tier Color Casting Enemies may tint, nil when it may not.
    -- ns._reactionCastLit (plainly in combat, for Modify Out of Combat) is set with it.
    mod._reactionCastTier = nil
    local saved = p or defaultSet
    -- 1. Tapped always highest
    if UnitIsTapDenied(unitToken) then
        local c = _C("tapped")
        return c.r, c.g, c.b
    end
    -- 2. Quest mob second highest (in instanced content only while the Quest Indicator's
    -- Show In Instances is on)
    if
        saved.questMobColorEnabled
        and (not InRealInstancedContent() or mod.NP_ShowInInstances("quest"))
        and IsQuestMob(unitToken)
    then
        local qc = saved.questMobColor or defaultSet.questMobColor
        return qc.r, qc.g, qc.b
    end
    -- Threat colors that can NEVER be overwritten:
    -- Non-tank: has aggro, near aggro Tank: losing aggro, no aggro
    local isThreatUnit = false -- set true when threat data exists
    local threatStatus = 0
    -- A non-tank's threat colors apply (in a group, or solo with a pet out: ThreatShared).
    local threatShared = false
    -- Show Threat Colors (Never / Instances / Always): one cached field read.
    if mod._npThreatColorsOn then
        local status = UnitThreatSituation("player", unitToken)
        mod._reactionThreatStatus = status or false
        if status then
            isThreatUnit = true
            threatStatus = status
            threatShared = not _isTankRole and ThreatShared()
            -- Threat Colors "Health Bar" channel off: the bar carries no threat color at
            -- all. Clearing isThreatUnit here is what makes that complete -- it also
            -- switches off the LOW-priority has-aggro / no-aggro steps further down
            -- (6b, 7b, 9, 10), which read these two locals -- so the bar ends up purely
            -- mob-type/reaction colored and the Border/Text channels own the threat signal
            -- on their own. The near-aggro glow rides the STATE, not the bar color, so it
            -- is still marked here; ns._reactionOffTankFold is a health-bar mechanism and
            -- deliberately stays unset (ns.ResolveThreatColor does its own fold).
            if not mod.GetThreatColorHealth() then
                if threatShared and status >= 2 and status < 3 then
                    mod._reactionNearAggro = true
                end
                isThreatUnit, threatStatus, threatShared = false, 0, false
            elseif not _isTankRole then
                -- Non-tank: has aggro / near aggro absolute priority
                -- Only in a group or with a pet out (solo without one, the player always has aggro)
                if threatShared then
                    if status >= 3 then
                        mod._reactionBadThreat = true
                        local c = _C("dpsHasAggro")
                        return c.r, c.g, c.b
                    elseif status >= 2 then
                        mod._reactionNearAggro = true
                        mod._reactionBadThreat = true
                        local c = _C("dpsNearAggro")
                        return c.r, c.g, c.b
                    end
                end
            else
                -- Tank arm. 12.1 field facts (side-by-side dump): the situation
                -- API pins 3 on plate tokens while the DETAILED API returns
                -- SECRET booleans for plate pairings (plain only for "target"
                -- pairings) -- no Lua branch can know who holds the mob. With
                -- Off-Tank Color on, mark EVERY tank-arm paint for the C-side
                -- fold: it starts from the plain color this function returns
                -- and overrides toward offTankAggro exactly when a co-tank's
                -- isTanking folds true. One tank holds per mob, so the fold
                -- self-resolves with zero secret reads.
                local otE = saved.offTankAggroEnabled
                if otE == nil then
                    otE = defaultSet.offTankAggroEnabled
                end
                if otE then
                    mod._reactionOffTankFold = true
                end
                if status < 3 and status >= 2 then
                    mod._reactionBadThreat = true
                    local c = _C("tankLosingAggro")
                    return c.r, c.g, c.b
                elseif status < 3 then
                    -- Only show no-aggro warning if a non-tank has it.
                    -- If another tank holds aggro, this is normal offtank positioning.
                    local unitTarget = unitToken .. "target"
                    -- Role reads on identity-restricted units return SECRET values: never
                    -- truthiness-chain or compare one. Unreadable role reads as non-tank.
                    local targetRole = "NONE"
                    local roleSecret = false
                    if UnitExists(unitTarget) then
                        local r = UnitGroupRolesAssigned(unitTarget)
                        if issecretvalue(r) then
                            roleSecret = true
                        elseif r then
                            targetRole = r
                        end
                    end
                    -- Role unreadable (identity restriction): the plain path
                    -- below lands on tankNoAggro, but mark the frame so
                    -- UpdateHealthColor can answer the REAL question from the
                    -- other side -- "is any other tank tanking this mob" via
                    -- UnitDetailedThreatSituation + the C_CurveUtil color fold
                    -- (field-probed: returns a real boolean in keys).
                    if roleSecret then
                        local otE = saved.offTankAggroEnabled
                        if otE == nil then
                            otE = defaultSet.offTankAggroEnabled
                        end
                        if otE then
                            mod._reactionOffTankFold = true
                        end
                    end
                    if targetRole ~= "TANK" then
                        mod._reactionBadThreat = true
                        local c = _C("tankNoAggro")
                        return c.r, c.g, c.b
                    end
                    -- Another tank has aggro -- show off-tank color if enabled
                    local otEnabled = saved.offTankAggroEnabled
                    if otEnabled == nil then
                        otEnabled = defaultSet.offTankAggroEnabled
                    end
                    if otEnabled then
                        local c = _C("offTankAggro")
                        return c.r, c.g, c.b
                    end
                end
                -- Classic tank aggro: has-aggro overrides all mob-type colors
                if status >= 3 then
                    local classic = saved.classicTankAggro
                    if classic == nil then
                        classic = defaultSet.classicTankAggro
                    end
                    if classic then
                        local c = _C("tankHasAggro")
                        return c.r, c.g, c.b
                    end
                end
                -- Default: tank has aggro falls through to caster/miniboss colors
            end
        end
    end
    -- 4. Target color (if enabled)
    local targetC = _C("target")
    if targetC and UnitIsUnit(unitToken, "target") then
        local tEnabled = defaultSet.targetColorEnabled
        if saved.targetColorEnabled ~= nil then
            tEnabled = saved.targetColorEnabled
        end
        if tEnabled then
            return targetC.r, targetC.g, targetC.b
        end
    end
    -- 5. Focus color (if enabled)
    local focusC = _C("focus")
    if focusC and UnitIsUnit(unitToken, "focus") then
        local enabled = defaultSet.focusColorEnabled
        if saved.focusColorEnabled ~= nil then
            enabled = saved.focusColorEnabled
        end
        if enabled then
            return focusC.r, focusC.g, focusC.b
        end
    end
    -- 5. Neutral (colored as an enemy while in combat with them). OUTSIDE dungeons keeps its
    -- high priority while it carries no health-bar threat data; IN dungeons, and with that
    -- data anywhere, deferred to just above the enemy fallback (step 10d) so mob-type/threat
    -- colors win on it and neutral becomes the near-last resort.
    local reaction = UnitReaction(unitToken, "player")
    local isNeutral = (reaction and reaction == 4)
        or (UnitCanAttack("player", unitToken) and not UnitIsEnemy(unitToken, "player"))
    if isNeutral and not mod._inDungeon and not isThreatUnit then
        return ResolveNeutralColor(unitToken)
    end
    -- 6. Enemy player class colors
    if UnitIsPlayer(unitToken) and UnitCanAttack("player", unitToken) then
        -- Enemy Players Use Enemy Color (opt-in): the step 11 fallback color, skipping the
        -- mob-type steps so a mana user is not painted Spell Casters.
        if saved.enemyPlayerEnemyColor then
            local simple = saved.owBasicColoring
            if simple == nil then
                simple = defaultSet.owBasicColoring
            end
            local c = _C((simple and not mod._inDungeon) and "owBasicColor" or "enemyInCombat")
            return MaybeDarken(c.r, c.g, c.b, UnitAffectingCombat(unitToken))
        end
        local _, classFile = UnitClass(unitToken)
        -- A secret class token (identity-restricted, i.e. instanced PvP) cannot key a
        -- plain color table, but C_ClassColor accepts it and returns a color that may only
        -- reach setters. Flag the plate so UpdateHealthColor paints the bar that way. We
        -- still fall through to the reaction color so every plain-number consumer
        -- downstream (the skip-if-unchanged compare, the No Tint overlay tints) keeps
        -- plain numbers.
        if issecretvalue(classFile) then
            mod._reactionMirrorClass = true
            classFile = nil
        end
        local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if c then
            return c.r, c.g, c.b
        end
    end
    -- Classify the mob-type tier once up front so the tank has-aggro overrides can reason about
    -- boss vs mini-boss vs caster independently. Booleans only: mob-type colors still return at
    -- their own priority steps (7, 8, 10b).
    local inCombat = UnitAffectingCombat(unitToken)
    local classification = UnitClassification(unitToken)
    -- Simple Coloring When Not In M+ (inline cog on Enemy Types): outside 5-man dungeons, collapse the
    -- mob-type colors (Mini Enemies, Spell Casters, Mini-Bosses, Bosses) into flat owBasicColor
    -- at the enemy fallback (step 11). Neutral keeps its own color out of combat (it returns at
    -- step 5 outside dungeons, or at 10d, above the fallback, while it carries health-bar threat
    -- data) and takes owBasicColor in combat (ResolveNeutralColor). Same dungeon gate as Mini
    -- Coloring M+ Only (ns._inDungeon).
    local owBasic = false
    if not mod._inDungeon then
        owBasic = defaultSet.owBasicColoring
        if saved.owBasicColoring ~= nil then
            owBasic = saved.owBasicColoring
        end
    end
    -- Mini Enemies color scope: restricted to 5-man dungeons when "Mini Coloring
    -- M+ Only" is on (default), applied everywhere when it is off.
    local miniMPlusOnly = defaultSet.miniColoringMPlusOnly
    if saved.miniColoringMPlusOnly ~= nil then
        miniMPlusOnly = saved.miniColoringMPlusOnly
    end
    local miniColorScope = not owBasic and (mod._inDungeon or not miniMPlusOnly)
    local _isBossUnit = false -- deferred: boss color is applied at step 10b
    local _isMiniBoss = false
    if
        not owBasic
        and (classification == "elite" or classification == "worldboss" or classification == "rareelite")
    then
        -- Effective level (handles scaling / Chromie time), not raw level, so
        -- the tier tracks how the game ranks the mob against the player.
        local level = UnitEffectiveLevel(unitToken)
        local lvlClean = level and not (issecretvalue and issecretvalue(level))
        local isSkull = lvlClean and level == -1
        local playerLevel = UnitEffectiveLevel("player")
        local plvlClean = playerLevel and not (issecretvalue and issecretvalue(playerLevel))
        -- A skull, or an elite ranked at least one effective level above the
        -- player, gets a tier; ordinary same/lower-level elites are left alone.
        local aboveOne = plvlClean and lvlClean and level >= playerLevel + 1
        if isSkull or aboveOne then
            -- Boss when it reads as boss-ranked: a skull, a world boss, or two+ effective
            -- levels up. UnitIsLieutenant is the client's mini-boss marker, so a non-skull
            -- lieutenant is pinned to mini-boss.
            local aboveTwo = plvlClean and lvlClean and level >= playerLevel + 2
            local lieutenant = (not isSkull) and UnitIsLieutenant and UnitIsLieutenant(unitToken)
            if not lieutenant and (isSkull or aboveTwo or classification == "worldboss") then
                _isBossUnit = true
            else
                _isMiniBoss = true
            end
        end
    end
    -- Caster = the unit actually has a mana pool, rather than a class match. Second arg is
    -- typed PowerType (enum NUMBER), not the global MANA (localized "Mana" string, never
    -- matches). hasPower carries no secrecy flag, so it is safe to branch on directly.
    -- Excludes boss units: _isMiniBoss already skips this step by returning earlier (step 7,
    -- above Caster's step 8), but _isBossUnit's own color is deferred to step 10b (below the
    -- threat-color steps, intentionally) -- with no exclusion here, a mana-using boss (e.g. a
    -- caster-type raid boss) hit step 8's return before step 10b was ever reached, showing the
    -- Spell Caster color instead of Bosses. Mirrors the mutual exclusivity boss/mini-boss
    -- already have with each other.
    local _isCaster = not owBasic and not _isBossUnit and UnitHasPowerType(unitToken, Enum.PowerType.Mana)
    -- Color Casting Enemies (opt-in): a mob that has cast gets its tier here, where the
    -- mob-type steps start, so its tints cover what Spell Casters would; the threat
    -- overrides and neutral returns below clear it again. Mobs painted Spell Casters keep
    -- it (a mini-boss with mana is painted Mini-Boss, step 7, so it can be tinted).
    -- castSeen is never set for players (ns.NP_NoteCastKind).
    if castSeen and saved.castingEnemyColors and not owBasic and (_isMiniBoss or not _isCaster) then
        if _isBossUnit then
            mod._reactionCastTier = "Boss"
        elseif _isMiniBoss then
            mod._reactionCastTier = "MiniBoss"
        elseif
            classification == "elite"
            or classification == "rareelite"
            or classification == "worldboss"
        then
            mod._reactionCastTier = "Elite"
        else
            mod._reactionCastTier = "Normal"
        end
        mod._reactionCastLit = not (issecretvalue and issecretvalue(inCombat)) and inCombat == true
    end
    -- DPS/healer No Aggro override state (mirrors tank has-aggro overrides at 6b). Each
    -- override independently promotes the No Aggro color above one mob-type step (mini-boss 7,
    -- caster 8). Active only for a non-tank without aggro in a group or with a pet out
    -- (matches step 10).
    local dpsNoAggroActive = threatShared and threatStatus < 2
    if dpsNoAggroActive then
        local en = defaultSet.dpsNoAggroEnabled
        if saved.dpsNoAggroEnabled ~= nil then
            en = saved.dpsNoAggroEnabled
        end
        dpsNoAggroActive = en
    end
    -- 6b. Tank has aggro -- "Override Mini-Boss and Caster colors" option. Promotes the
    -- has-aggro color above the mini-boss/caster steps, still below target/focus/enemy-class.
    -- Boss units excluded (governed by "Override Boss colors", step 9/10b). Sits between the
    -- absolute-priority Classic Tank Aggro path above and low-priority step 9.
    if isThreatUnit and _isTankRole and threatStatus >= 3 and not _isBossUnit then
        local hae = defaultSet.tankHasAggroEnabled
        if saved.tankHasAggroEnabled ~= nil then
            hae = saved.tankHasAggroEnabled
        end
        local ovr = defaultSet.tankHasAggroOverrideMobType
        if saved.tankHasAggroOverrideMobType ~= nil then
            ovr = saved.tankHasAggroOverrideMobType
        end
        if hae and ovr then
            mod._reactionCastTier = nil
            local c = _C("tankHasAggro")
            return c.r, c.g, c.b
        end
    end
    -- 7. Mini-boss. Boss is intentionally LOWER priority than the low-priority threat colors
    -- below, so it is deferred to step 10b (see _isBossUnit); mini-boss stays here, above threat.
    if _isMiniBoss then
        -- DPS/healer No Aggro "Override Mini-Boss colors": promotes the No Aggro
        -- color above the mini-boss color when enabled.
        if dpsNoAggroActive then
            local ovr = defaultSet.dpsNoAggroOverrideMiniBoss
            if saved.dpsNoAggroOverrideMiniBoss ~= nil then
                ovr = saved.dpsNoAggroOverrideMiniBoss
            end
            if ovr then
                mod._reactionCastTier = nil
                local c = _C("dpsNoAggro")
                return c.r, c.g, c.b
            end
        end
        local c = _C("miniboss")
        return MaybeDarken(c.r, c.g, c.b, inCombat)
    end
    -- 7b. Mini Enemies promoted ABOVE Caster -- but ONLY for DPS/healers and tanks that do NOT
    -- use the special Tank Has Aggro color. Tanks WITH that option enabled skip this and keep
    -- Mini Enemies at its original low priority (step 10c), so has-aggro/caster/mob-type colors
    -- still win on trash.
    if
        miniColorScope
        and (classification == "normal" or classification == "minus" or classification == "trivial")
    then
        local thae = defaultSet.tankHasAggroEnabled
        if saved.tankHasAggroEnabled ~= nil then
            thae = saved.tankHasAggroEnabled
        end
        -- Neutral + mini-enemy: neutral coloring wins over the trash color while the unit
        -- carries no health-bar threat data (out of combat, or threat colors off). In combat
        -- with them on it falls through like a hostile unit, so the threat and Mini Enemies
        -- colors reach neutral trash too. Non-trash neutral units defer to 10d.
        if isNeutral and not isThreatUnit then
            mod._reactionCastTier = nil
            return ResolveNeutralColor(unitToken)
        end
        if not (_isTankRole and thae) then
            -- DPS "No Aggro" still wins over the promoted Mini Enemies color, so a DPS/healer
            -- without aggro sees the warning on trash. Scoped to this trash branch so Caster
            -- still outranks DPS No Aggro on non-trash casters (step 10, same condition).
            if threatShared and threatStatus < 2 then
                local dpsNA = defaultSet.dpsNoAggroEnabled
                if saved.dpsNoAggroEnabled ~= nil then
                    dpsNA = saved.dpsNoAggroEnabled
                end
                if dpsNA then
                    mod._reactionCastTier = nil
                    local c = _C("dpsNoAggro")
                    return c.r, c.g, c.b
                end
            end
            local c = (p and p.miniEnemy) or _C("enemyInCombat")
            return MaybeDarken(c.r, c.g, c.b, inCombat)
        end
    end
    -- 8. Caster
    if _isCaster then
        -- DPS/healer No Aggro "Override Caster colors": promotes No Aggro above the caster
        -- color when enabled. Kept separate from the mini-boss override for contrast.
        if dpsNoAggroActive then
            local ovr = defaultSet.dpsNoAggroOverrideCaster
            if saved.dpsNoAggroOverrideCaster ~= nil then
                ovr = saved.dpsNoAggroOverrideCaster
            end
            if ovr then
                local c = _C("dpsNoAggro")
                return c.r, c.g, c.b
            end
        end
        local c = _C("caster")
        return MaybeDarken(c.r, c.g, c.b, inCombat)
    end
    -- 9. Tank has aggro (if enabled) below focus/caster/miniboss. Normally sits above the boss
    -- color (step 10b); with "Override Boss colors" disabled it's held below boss instead (the
    -- 10b return wins for boss units, so has-aggro lands just below bosses).
    if isThreatUnit and _isTankRole and threatStatus >= 3 then
        local enabled = defaultSet.tankHasAggroEnabled
        if saved.tankHasAggroEnabled ~= nil then
            enabled = saved.tankHasAggroEnabled
        end
        if enabled then
            local ovrBoss = defaultSet.tankHasAggroOverrideBoss
            if saved.tankHasAggroOverrideBoss ~= nil then
                ovrBoss = saved.tankHasAggroOverrideBoss
            end
            if ovrBoss or not _isBossUnit then
                mod._reactionCastTier = nil
                local c = _C("tankHasAggro")
                return c.r, c.g, c.b
            end
        end
    end
    -- 10. Non-tank no aggro (if enabled) below focus/caster/miniboss. Boss units gated behind
    -- their own "Override Boss colors" toggle (default ON = the behaviour before the toggle
    -- existed, so nothing changes for users who did not touch it), mirroring tank has-aggro's
    -- ovrBoss check at step 9 above -- previously unconditional, so a DPS/healer without aggro
    -- always lost the Bosses color on engage with no way to turn that off (unlike Mini-Boss/
    -- Caster, which already had their own override toggles here, both off by default).
    if threatShared and threatStatus < 2 then
        local enabled = defaultSet.dpsNoAggroEnabled
        if saved.dpsNoAggroEnabled ~= nil then
            enabled = saved.dpsNoAggroEnabled
        end
        if enabled then
            local ovrBoss = defaultSet.dpsNoAggroOverrideBoss
            if saved.dpsNoAggroOverrideBoss ~= nil then
                ovrBoss = saved.dpsNoAggroOverrideBoss
            end
            if ovrBoss or not _isBossUnit then
                mod._reactionCastTier = nil
                local c = _C("dpsNoAggro")
                return c.r, c.g, c.b
            end
        end
    end
    -- 10b. Boss (intentionally below the low-priority threat colors above, so tank-has-aggro/
    -- dps-no-aggro takes precedence over boss -- unless "Override Boss colors" is disabled, in
    -- which case the has-aggro/no-aggro step above defers to this boss color for boss units).
    if _isBossUnit then
        local c = _C("boss")
        return MaybeDarken(c.r, c.g, c.b, inCombat)
    end
    -- 10c. Mini Enemies: non-elite trash (normal/minus), DUNGEONS ONLY -- outside dungeons
    -- these fall through to the enemy color below. Elites handled at step 7, so same-level
    -- elites still use the enemy color. Below the threat colors, so aggro still wins.
    -- DPS/healers and non-special-aggro tanks already returned at 7b; this path only serves
    -- tanks with "Has Aggro" on.
    if
        miniColorScope
        and (classification == "normal" or classification == "minus" or classification == "trivial")
    then
        -- Views "Enemies" (enemyInCombat) until the user sets a Mini Enemies color explicitly.
        local c = (p and p.miniEnemy) or _C("enemyInCombat")
        return MaybeDarken(c.r, c.g, c.b, inCombat)
    end
    -- 10d. Neutral, deferred (in dungeons, where step 5 skips it, and anywhere while it carries
    -- health-bar threat data): a neutral unit matching no mob-type/threat color lands here,
    -- just above the generic enemy fallback.
    if isNeutral then
        mod._reactionCastTier = nil
        return ResolveNeutralColor(unitToken)
    end
    -- 11. Fallback: enemy in/out of combat. With Simple Coloring When Not In M+ active, every mob-type
    -- special above was suppressed, so all hostile mobs share the flat "All Enemies" color.
    local eic = _C(owBasic and "owBasicColor" or "enemyInCombat")
    return MaybeDarken(eic.r, eic.g, eic.b, inCombat)
end

Inner._C, Inner.GetReactionColor, Inner.questMobCache = _C, GetReactionColor, questMobCache
Inner.RefreshThreatCache = RefreshThreatCache
Inner.broken = false
