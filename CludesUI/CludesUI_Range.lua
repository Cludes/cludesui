if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CludesUI_Range.lua
--  Shared range-check engine for the suite's range consumers:
--    - Nameplates "Distance to Target Text"  (spell-ladder lower bound)
--    - Nameplates "Out of Range Alpha"       (class/spec cutoff probes)
--    - QoL "Target Distance Text"            (item bracket or spell lower bound)
--    - QoL crosshair out-of-range recolor    (cutoff probes + item fallback)
--
--  One spellbook ladder, one harm-item table, one set of invalidation events.
--  Everything is built lazily and the events are registered only while at
--  least one consumer has declared itself active (Range_SetActive), so the
--  engine costs nothing while every range feature is disabled. When several
--  features are enabled at once they share a single ladder build and a short
--  per-tick result cache, so the same question is never answered twice in
--  the same window.
--
--  No direct distance API exists for enemies, so everything here is inferred
--  from in-range answers: the player's own harmful spellbook spells (checked
--  live, so talent range extensions are reflected automatically) and a ladder
--  of fixed-range harm items.
-------------------------------------------------------------------------------
if not CUI then return end
if CUI.Range_SetActive then return end -- already loaded

local GetTime = GetTime

-- Fixed-range harm items for the item bracket. Desired display buckets:
--   1-10: 1 yd steps -- 10-50: 5 yd -- 50-80: 10 yd -- then 80+.
-- Yards with no reliable item (1, 6, 9) are omitted; neighboring checks form
-- the bracket. Multi-id rungs: any one answering suffices (some items are
-- invalid on some clients).
local RANGE_ITEMS = {
    { range = 2, ids = { 37727, 168948, 194718 } }, -- Ruby Acorn / Dried Kelp / Salamander Feed
    { range = 3, ids = { 42732, 200469 } }, -- Everfrost Razor / Khadgar's Rod
    { range = 4, id = 129055 }, -- Shoe Shine Kit
    { range = 5, ids = { 8149, 136605, 63427 } }, -- Voodoo Charm / Solendra's / Worgsaw
    { range = 7, id = 61323 }, -- Ruby Seeds
    { range = 8, ids = { 34368, 33278 } }, -- Attuned Crystal Cores / Burning Torch
    { range = 10, ids = { 32321, 17626, 10699 } }, -- Sparrowhawk Net / Frostwolf Muzzle / Yeh'kinya's
    { range = 15, ids = { 33069, 31129 } }, -- Sturdy Rope / Blackwhelp Net
    { range = 20, ids = { 10645, 21519 } }, -- Gnomish Death Ray / Mistletoe
    { range = 25, ids = { 13289, 24268, 41509, 31463 } },
    { range = 30, ids = { 17202, 835, 7734, 34191 } },
    { range = 35, ids = { 18904, 24269 } },
    { range = 40, ids = { 28767, 18640 } }, -- Decapitator / Happy Fun Rock
    { range = 45, ids = { 32698, 23836 } }, -- Wrangling Rope / Goblin Rocket Launcher
    { range = 50, id = 116139 }, -- Haunting Memento
    { range = 60, ids = { 32825, 37887 } }, -- Soul Cannon / Seeds of Nature's Wrath
    { range = 70, id = 41265 }, -- Eyesore Blaster
    { range = 80, id = 35278 }, -- Reinforced Net
}

local RangeKit = {
    ladder = {}, -- ascending { range = yds, spells = { sid, ... } }
    ladderBuilt = false,
    dirty = false,
    active = {}, -- consumer key -> true
    activeCount = 0,
    evt = nil, -- invalidation event frame (created on first activation)
    probeCutoff = nil, -- cutoff the cached probe list below was built for
    probes = {}, -- crosshair probe spells, longest range first
}

-- Some harmful spells answer nil on IsSpellInRange (ground-target only,
-- conditionally castable), so each rung keeps a few spares to stay
-- answerable instead of deduping to a single spell per range.
local MAX_SPELLS_PER_RUNG = 3
local MAX_PROBE_SPELLS = 4

-- Micro result cache: one slot per query shape. The TTL sits under every
-- consumer tick interval (0.15s / 0.2s), so concurrent features share one
-- walk per window while successive ticks of a single feature stay live.
local CACHE_TTL = 0.1
local lbCache = { unit = nil, t = 0, has = false, v = nil }
local brCache = { unit = nil, stop = nil, t = 0, has = false, mn = nil, mx = nil }

local function ResetCaches()
    lbCache.has = false
    brCache.has = false
    RangeKit.probeCutoff = nil
end

local DRUID_MELEE_FORMS = { [1] = true, [2] = true } -- Bear, Cat

local EnsureLadder -- defined below; the WoW Forever caster cutoff reads the ladder

-- Spec-derived attack cutoff, form check NOT included (that is the one live
-- input; everything here only moves on spec/talent changes and is cached by
-- Range_GetAttackCutoff below).
local function SpecAttackCutoff(holyPaladinMelee)
    local _, class = UnitClass("player")
    local specIndex = C_SpecializationInfo.GetSpecialization()
    local specID = specIndex and C_SpecializationInfo.GetSpecializationInfo(specIndex)
    -- WoW Forever reports one class spec (1482-1491) whatever the player
    -- plays, so the spec cannot tell caster from melee there. Casters (Druid,
    -- Priest, Mage, Warlock, Shaman) take the longest harmful spellbook rung
    -- (<= 40 yd), so the cutoff lands on a real spell (Wrath, Shadow Bolt,
    -- Lightning Bolt) that Range_BeyondCutoff can probe directly, and follows
    -- talent range extensions. Druid Cat and Bear Form get 5 from the live form
    -- check in Range_GetAttackCutoff before this cached value is read.
    -- Paladin, Hunter (min-range shots are excluded from the ladder), Warrior
    -- and Rogue stay at 5.
    if CUI.IS_FOREVER == true then
        if
            class == "DRUID"
            or class == "PRIEST"
            or class == "MAGE"
            or class == "WARLOCK"
            or class == "SHAMAN"
        then
            EnsureLadder()
            local best
            for idx = 1, #RangeKit.ladder do
                local r = RangeKit.ladder[idx].range
                if r > 5 and r <= 40 then best = r end
            end
            if best then return best end
        end
        return 5
    end
    if not specID then return 5 end

    if class == "DRUID" then
        if specID == 102 or specID == 105 then
            return C_SpellBook.IsSpellKnown(197488) and 45 or 40 -- Astral Influence
        end
        return 5
    elseif class == "DEMONHUNTER" then
        return (specID == 577 or specID == 581) and 5 or 25
    elseif class == "EVOKER" then
        return specID == 1468 and 30 or 25
    elseif class == "HUNTER" then
        return (specID == 253 or specID == 254) and 40 or 5
    elseif class == "PALADIN" then
        return specID == 65 and not holyPaladinMelee and 40 or 5
    elseif class == "SHAMAN" then
        return specID == 263 and 5 or 40
    elseif class == "MONK" then
        return specID == 270 and 40 or 5
    elseif class == "PRIEST" or class == "MAGE" or class == "WARLOCK" then
        return 40
    end
    return 5
end

-- Attack range shared by range-aware UI. An explicit cutoff wins; otherwise
-- class/spec decides -- CACHED, invalidated by the engine's activation events
-- (spec/talent/spellbook churn): consumers call this at sweep/tick cadence and
-- per-call GetSpecializationInfo re-derivation was measurable. Druid melee
-- forms are the single live check. Holy Paladins can opt into melee range.
function CUI.Range_GetAttackCutoff(customCutoff, holyPaladinMelee)
    customCutoff = tonumber(customCutoff)
    if customCutoff then
        customCutoff = math.floor((customCutoff + 2.5) / 5) * 5
        return math.max(5, math.min(50, customCutoff))
    end

    local _, class = UnitClass("player")
    if class == "DRUID" then
        -- WoW Forever orders the stance bar the vanilla way (Aquatic Form can sit
        -- between Bear and Cat), so it checks the form ID: Cat 1, Bear 5, Dire Bear 8.
        if CUI.IS_FOREVER == true then
            local fid = GetShapeshiftFormID()
            if fid == 1 or fid == 5 or fid == 8 then return 5 end
        elseif DRUID_MELEE_FORMS[GetShapeshiftForm()] then
            return 5
        end
    end

    if holyPaladinMelee then
        local val = RangeKit.cutoffHolyMelee
        if val == nil then
            val = SpecAttackCutoff(true)
            RangeKit.cutoffHolyMelee = val
        end
        return val
    end
    local val = RangeKit.cutoffBase
    if val == nil then
        val = SpecAttackCutoff(false)
        RangeKit.cutoffBase = val
    end
    return val
end

local function BuildLadder()
    RangeKit.ladderBuilt = true
    RangeKit.dirty = false
    ResetCaches()
    wipe(RangeKit.ladder)
    if
        not (
            C_SpellBook
            and C_SpellBook.GetNumSpellBookSkillLines
            and C_Spell
            and C_Spell.GetSpellInfo
            and Enum
            and Enum.SpellBookItemType
        )
    then
        return
    end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local byRange = {}
    for li = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(li)
        -- offSpecID is 0 (not nil) on active-spec lines.
        if
            line
            and not (line.offSpecID and line.offSpecID ~= 0)
            and not line.shouldHide
            and line.itemIndexOffset
            and line.numSpellBookItems
        then
            for si = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local itemType, actionID, spellId = C_SpellBook.GetSpellBookItemType(si, bank)
                local spellRef = spellId or actionID
                if
                    itemType == Enum.SpellBookItemType.Spell
                    and spellRef
                    and not (C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(spellRef))
                    and (not C_Spell.IsSpellHarmful or C_Spell.IsSpellHarmful(spellRef))
                then
                    local sinfo = C_Spell.GetSpellInfo(spellRef)
                    local maxR = sinfo and sinfo.maxRange
                    -- Ranges can read as float noise (23.999998 for a 24 yd spell): whole yards.
                    if type(maxR) == "number" then maxR = math.floor(maxR + 0.5) end
                    -- A charge/leap-style spell with a nonzero minRange answers
                    -- IsSpellInRange false both beyond maxRange AND inside its
                    -- own dead zone (e.g. a gap-closer unusable under ~8yd) --
                    -- the ladder walk below treats any false as "beyond this
                    -- rung," so such a spell would falsely fade a target
                    -- standing well inside melee range. Exclude it; other
                    -- spells sharing its maxRange rung are unaffected.
                    if sinfo and sinfo.minRange and sinfo.minRange > 0 then maxR = nil end
                    if maxR and maxR > 0 and maxR <= 100 then
                        local rung = byRange[maxR]
                        if not rung then
                            rung = { range = maxR, spells = {} }
                            byRange[maxR] = rung
                            RangeKit.ladder[#RangeKit.ladder + 1] = rung
                        end
                        if #rung.spells < MAX_SPELLS_PER_RUNG then
                            rung.spells[#rung.spells + 1] = spellRef
                        end
                    end
                end
            end
        end
    end
    table.sort(RangeKit.ladder, function(lhs, rhs) return lhs.range < rhs.range end)
end

EnsureLadder = function()
    if RangeKit.dirty or not RangeKit.ladderBuilt then BuildLadder() end
end

-- One rung's answer: first non-nil IsSpellInRange among its spells, checked
-- through the live override (a base id a talent replaced answers nil).
-- Secret results are skipped -- fail-open to nil, never an error.
local function RungInRange(rung, unitToken)
    local FindOvr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
    local spells = rung.spells
    for idx = 1, #spells do
        local spellRef = spells[idx]
        local live = (FindOvr and FindOvr(spellRef)) or spellRef
        local res = C_Spell.IsSpellInRange(live, unitToken)
        if not (issecretvalue and issecretvalue(res)) and res ~= nil then return res end
    end
    return nil
end

-- One item rung's answer: true if any id answers in-range, false only on an
-- explicit out-of-range answer, nil when every id is secret/inapplicable.
local function ItemEntryInRange(record, unitToken)
    local ids = record.ids
    if ids then
        local sawFalse = false
        for idx = 1, #ids do
            local res = C_Item.IsItemInRange(ids[idx], unitToken)
            if not (issecretvalue and issecretvalue(res)) then
                if res == true then return true end
                if res == false then sawFalse = true end
            end
        end
        if sawFalse then return false end
        return nil
    end
    local res = C_Item.IsItemInRange(record.id, unitToken)
    if issecretvalue and issecretvalue(res) then return nil end
    return res
end

-- In combat (and in protected instances, where protected-function restrictions persist
-- between pulls) C_Item.IsItemInRange is a PROTECTED call against units the player
-- cannot attack -- calling it there is an ADDON_ACTION_BLOCKED, not a secret result, so
-- it must be gated up front. Hostile checks stay legal. Fails toward skipping the walk:
-- a restricted query degrades to nil (no display) instead of a blocked action.
local function ItemChecksAllowed(unitToken)
    if not (InCombatLockdown() or (CUI.InProtectedInstance())) then return true end
    local can = UnitCanAttack("player", unitToken)
    if issecretvalue and issecretvalue(can) then return false end
    return can == true
end
-- Shared with any other item-range reader (Quickdraw's usability tint) so the
-- protection rule lives in one place.
CUI.ItemRangeChecksAllowed = ItemChecksAllowed

-------------------------------------------------------------------------------
--  Queries
-------------------------------------------------------------------------------

-- Largest spell-ladder rung the unit is BEYOND (0 = inside the smallest
-- rung), or nil when no rung produced a usable answer. Displayed as "N+".
function CUI.Range_LowerBound(unitToken)
    if not unitToken or not UnitExists(unitToken) then return nil end
    if not (C_Spell and C_Spell.IsSpellInRange) then return nil end
    local nowTime = GetTime()
    if lbCache.has and lbCache.unit == unitToken and (nowTime - lbCache.t) < CACHE_TTL then
        return lbCache.v
    end
    EnsureLadder()
    local ladder = RangeKit.ladder
    local lower, result, answered = 0, nil, false
    for idx = 1, #ladder do
        local res = RungInRange(ladder[idx], unitToken)
        if res == true then
            answered = true
            result = lower
            break
        elseif res == false then
            answered = true
            lower = ladder[idx].range
        end
    end
    if answered and result == nil then result = lower end
    lbCache.unit, lbCache.t, lbCache.has, lbCache.v = unitToken, nowTime, true, result
    return result
end

-- Item-ladder bracket. Ascending walk; returns minYards, maxYards where min
-- is the last rung answered out-of-range and max the first answered in-range
-- (max nil = beyond every checked rung). Returns nil when no rung answered.
-- stopRange (optional) ends the walk after the first rung at or past it when
-- nothing has answered in-range yet -- a beyond/within verdict at stopRange
-- never needs the rungs past it. A cached full walk can serve a stopped
-- query (its verdict at any cutoff is identical), never the other way.
-- Bare item walk, no cache reads or writes: the single-unit consumers cache
-- through Range_ItemBracket below; the multi-unit plate sweep calls this
-- directly so its fan-out can never evict the "target" cache slot.
local function ItemWalk(unitToken, stopRange)
    local minY, maxY = 0, nil
    local answered = false
    for idx = 1, #RANGE_ITEMS do
        local record = RANGE_ITEMS[idx]
        local res = ItemEntryInRange(record, unitToken)
        if res == true then
            answered = true
            maxY = record.range
            break
        elseif res == false then
            answered = true
            minY = record.range
            -- Only stop once THIS entry actually answered: an unowned item
            -- sitting exactly at stopRange answers nil, not false, and must
            -- not silently truncate the walk before a farther rung the
            -- player DOES own gets a chance to give a real verdict.
            if stopRange and record.range >= stopRange then break end
        end
    end
    if not answered then return nil end
    return minY, maxY
end

function CUI.Range_ItemBracket(unitToken, stopRange)
    if not unitToken or not UnitExists(unitToken) then return nil end
    if not (C_Item and C_Item.IsItemInRange) then return nil end
    if not ItemChecksAllowed(unitToken) then return nil end
    local nowTime = GetTime()
    if
        brCache.has
        and brCache.unit == unitToken
        and (nowTime - brCache.t) < CACHE_TTL
        and (brCache.stop == stopRange or brCache.stop == nil)
    then
        return brCache.mn, brCache.mx
    end
    local minY, maxY = ItemWalk(unitToken, stopRange)
    brCache.unit, brCache.stop, brCache.t, brCache.has = unitToken, stopRange, nowTime, true
    brCache.mn, brCache.mx = minY, maxY
    return minY, maxY
end

-- Crosshair support: is the unit beyond `cutoff` yards? Probes the player's
-- own harmful spells with ranges in [cutoff, cutoff+10] (the window keeps
-- outlier long-range utility spells from widening the answer), CLOSEST to
-- cutoff first, first non-nil answer wins. Closest-first matters: a spell
-- wider than cutoff answers in-range out to ITS OWN max and silently widens
-- the cutoff -- a 40yd spell in a 30yd window answers true all the way to 40.
-- Returns true/false, or nil when no probe answered -- the caller falls back
-- to the item ladder.
function CUI.Range_BeyondCutoff(unitToken, cutoff)
    if not unitToken or not UnitExists(unitToken) then return nil end
    if not (C_Spell and C_Spell.IsSpellInRange) then return nil end
    EnsureLadder()
    if RangeKit.probeCutoff ~= cutoff then
        RangeKit.probeCutoff = cutoff
        wipe(RangeKit.probes)
        local maxWindow = cutoff + 10
        local ladder = RangeKit.ladder
        for idx = 1, #ladder do -- ascending ladder walked forwards = closest-to-cutoff first
            local rung = ladder[idx]
            if rung.range >= cutoff then
                if rung.range > maxWindow then break end
                local spells = rung.spells
                for jdx = 1, #spells do
                    if #RangeKit.probes >= MAX_PROBE_SPELLS then break end
                    RangeKit.probes[#RangeKit.probes + 1] = spells[jdx]
                end
                if #RangeKit.probes >= MAX_PROBE_SPELLS then break end
            end
        end
    end
    local FindOvr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
    for idx = 1, #RangeKit.probes do
        local spellRef = RangeKit.probes[idx]
        local live = (FindOvr and FindOvr(spellRef)) or spellRef
        local res = C_Spell.IsSpellInRange(live, unitToken)
        if not (issecretvalue and issecretvalue(res)) and res ~= nil then return res == false end
    end
    return nil
end

-- True/false when the unit can be classified against the supplied (or normal
-- class/spec) attack range; nil when no spell or item probe answered.
-- Single-unit consumers only (crosshair "target"): the item fallback rides
-- the shared single-slot cache. Sweeps use Range_SweepBeyond below.
function CUI.Range_IsBeyondAttackRange(unitToken, cutoff)
    cutoff = cutoff or CUI.Range_GetAttackCutoff()
    if cutoff > 5 then
        local beyond = CUI.Range_BeyondCutoff(unitToken, cutoff)
        if beyond ~= nil then return beyond end
    end
    local minY, maxY = CUI.Range_ItemBracket(unitToken, cutoff)
    if minY == nil then return nil end
    -- A bracket that straddles the cutoff (the first in-range rung sits past
    -- it, the last out-of-range rung before it) cannot say which side the
    -- unit is on: unknown, no fade, rather than a beyond guess.
    if maxY and maxY > cutoff and minY < cutoff then return nil end
    return maxY == nil or maxY > cutoff
end

-- Sweep-facing variant for MANY-unit consumers (nameplate out-of-range fade):
-- verdicts ride a short-TTL per-unit map instead of the single-slot target
-- caches (a 40-plate fan-out through those evicted the crosshair/QoL hits
-- every tick), and the item fallback goes through the bare walk for the same
-- reason. Encoded 0/1/2 = nil/true/false so cached nil verdicts still hit.
-- NOTE the melee floor: at cutoff 5 the spell probes are skipped and the item
-- walk is protection-gated (ItemChecksAllowed) -- in instanced combat against
-- units whose attackability reads secret, melee verdicts degrade to nil (no
-- fade) by design rather than risking a blocked action.
local sweepCache = { t = 0, cutoff = nil, v = {} }
local SWEEP_TTL = 0.4
function CUI.Range_SweepBeyond(unitToken, cutoff)
    if not unitToken or not UnitExists(unitToken) then return nil end
    cutoff = cutoff or CUI.Range_GetAttackCutoff()
    local nowTime = GetTime()
    if (nowTime - sweepCache.t) > SWEEP_TTL or sweepCache.cutoff ~= cutoff then
        wipe(sweepCache.v)
        sweepCache.t = nowTime
        sweepCache.cutoff = cutoff
    end
    local hit = sweepCache.v[unitToken]
    if hit ~= nil then
        if hit == 0 then return nil end
        return hit == 1
    end
    local beyond
    if cutoff > 5 then beyond = CUI.Range_BeyondCutoff(unitToken, cutoff) end
    if beyond == nil and C_Item and C_Item.IsItemInRange and ItemChecksAllowed(unitToken) then
        local minY, maxY = ItemWalk(unitToken, cutoff)
        -- Same straddle rule as Range_IsBeyondAttackRange: unknown, not beyond.
        if minY ~= nil and not (maxY and maxY > cutoff and minY < cutoff) then
            beyond = maxY == nil or maxY > cutoff
        end
    end
    sweepCache.v[unitToken] = beyond == nil and 0 or (beyond and 1 or 2)
    return beyond
end

-------------------------------------------------------------------------------
--  Activation
-------------------------------------------------------------------------------

-- Consumers declare themselves while their feature is enabled. The engine
-- registers its invalidation events only while at least one consumer is
-- active and drops them all at zero, so nothing here ever fires for users
-- with every range feature disabled. Idempotent and cheap on repeat calls.
function CUI.Range_SetActive(key, enabled)
    enabled = enabled and true or nil
    if RangeKit.active[key] == enabled then return end
    RangeKit.active[key] = enabled
    RangeKit.activeCount = RangeKit.activeCount + (enabled and 1 or -1)
    if enabled and RangeKit.activeCount == 1 then
        if not RangeKit.evt then
            RangeKit.evt = CreateFrame("Frame")
            RangeKit.evt:SetScript("OnEvent", function()
                RangeKit.dirty = true
                RangeKit.cutoffBase, RangeKit.cutoffHolyMelee = nil, nil
            end)
        end
        RangeKit.evt:RegisterEvent("SPELLS_CHANGED")
        RangeKit.evt:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        RangeKit.evt:RegisterEvent("TRAIT_CONFIG_UPDATED")
        RangeKit.evt:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- Events were unregistered until now; anything may have changed.
        RangeKit.dirty = true
        RangeKit.cutoffBase, RangeKit.cutoffHolyMelee = nil, nil
    elseif not enabled and RangeKit.activeCount == 0 then
        if RangeKit.evt then RangeKit.evt:UnregisterAllEvents() end
    end
end
