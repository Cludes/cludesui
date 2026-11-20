if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- CUI_UnitFrames_AuraContainers.lua
-- 12.1 aura displays for unit frames: AuraKit containers replace the oUF aura
-- element for migrated units. This file is a pure VIEW over the existing
-- per-unit settings keys -- zero migration, every current option keeps working.
--
-- Classification model: the old element fetched with a broad base filter and
-- union-OR'd the class toggles per aura. Containers cannot OR filters, so each
-- class is its own group, made mutually exclusive with '!' negation, declared
-- once up-front (groups are add-only) and enabled by flipping maxFrameCount.
-- Known behavior deltas vs the old element (documented for patch notes):
--   * icon caps apply per enabled class, not as one total across the union
--   * sorting applies within each class group, not across all shown icons
--   * on assistable units the spellID excludes (always-hidden, Hide
--     Exhaustion) work only for never-secret spells (the engine's identity
--     gate exempts them; Exhaustion/Sated are); enemy units filter exactly as
--     before

local _, mod = ...

local AK -- CludesUI.AuraKit, resolved at first use (parent loads first)
-- Born in this module's main chunk, so the aura containers it builds bill this
-- module (AuraKit's shared build scheduler).
local AKWorker = CludesUI.AuraKit.NewBuildWorker()

local AURA_CROP_HEIGHT = 0.80
local AURA_ZOOM = 0.07
local FALLBACK_FONT = "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"

-- The Bloodlust lockouts: hidden while the unit's Hide Exhaustion (its Debuff
-- Filter, s.debuffHideExhaustion, nil = on) is on. Player Aura Bars' own Hide
-- Exhaustion reads the same set.
local SATED_DEBUFFS = {
    [57723] = true,
    [57724] = true,
    [80354] = true,
    [95809] = true,
    [160455] = true,
    [264689] = true,
    [390435] = true,
}
mod.UF_SatedDebuffs = SATED_DEBUFFS
local ALWAYS_HIDE_DEBUFFS = {
    [1254550] = true, -- Arcane Empowerment
    [308312] = true, -- Time Trial Practice
}

-- Filter classes (verified 12.1 vocabulary = AuraUtil.AuraFilters; IMPORTANT
-- does not exist as a token). Token classes become groups made mutually
-- exclusive by negating the ENABLED classes before them in priority order --
-- negating disabled classes would eat auras that belong to an enabled class
-- (union semantics, not chain semantics). Candidate classes are engine
-- selectors that cannot be token-negated; they sit after the token chain and
-- partition by carrying complements between links (booleans, dispel-type
-- excludes, or a shrunk include map), so an aura matching several shown
-- classes renders once, in the highest class of one linear owner order -- see
-- BuildChain. Groups are additive and the container is never swapped: the
-- config pass re-sets each active group's filter string and candidates from
-- the current chain (ApplyGroupConfig).
local TOKEN_CLASSES = {
    { key = "raid", token = "RAID", skey = "Raid" },
    { key = "raidcombat", token = "RAID_IN_COMBAT", skey = "RaidInCombat" },
    { key = "dispellable", token = "RAID_PLAYER_DISPELLABLE", skey = "Dispellable" },
    { key = "cc", token = "CROWD_CONTROL", skey = "CrowdControl" },
    { key = "bigdef", token = "BIG_DEFENSIVE", skey = "BigDefensive" },
    { key = "extdef", token = "EXTERNAL_DEFENSIVE", skey = "ExternalDefensive" },
    { key = "cancel", token = "CANCELABLE", skey = "Cancelable", buffOnly = true },
    -- Less common (debuffs): your own casts. LAST so every existing chain
    -- shape is byte-identical while it is unselected.
    { key = "castbyme", token = "PLAYER", skey = "CastByMe", debuffOnly = true },
}
local CANDIDATE_CLASSES = {
    -- Player-frame only: debuffs not caused by ANY player or player pet (engine
    -- boolean, evaluated secret-safe engine-side). The legacy !PLAYER token this
    -- replaced only excluded YOUR casts; the boolean also drops other players' noise
    -- (Sated, Forbearance, gateway debuffs). Sits FIRST so the classes below take the
    -- complementary boolean and own the player-caused leftovers (mirrors the old
    -- PLAYER-token handoff; see BuildChain).
    {
        key = "nonplayer",
        cand = { isFromPlayerOrPlayerPet = false },
        skey = "NonPlayer",
        debuffOnly = true,
        playerUnitOnly = true,
    },
    -- The complement of nonplayer on the SAME engine field; the options setters
    -- keep the two mutually exclusive across both lanes (BuildChain carries the
    -- complementary FALSE forward once this one is in the chain).
    {
        key = "anyplayer",
        cand = { isFromPlayerOrPlayerPet = true },
        skey = "AnyPlayer",
        debuffOnly = true,
        playerUnitOnly = true,
    },
    { key = "bossaura", cand = { isBossAura = true }, skey = "BossAura", debuffOnly = true },
    { key = "roleaura", cand = { isRoleAura = true }, skey = "RoleAura", debuffOnly = true },
    -- Debuffs the player's own class can apply (engine boolean).
    { key = "canapply", cand = { canApplyAura = true }, skey = "CanApply", debuffOnly = true },
    -- Per-type dispels: BEFORE dispeltyped so a shown type forwards its exclude
    -- onto the typed record (which then shows the remaining types).
    {
        key = "magic",
        cand = { includeDispelTypes = { Magic = true } },
        skey = "DispelMagic",
        debuffOnly = true,
    },
    {
        key = "curse",
        cand = { includeDispelTypes = { Curse = true } },
        skey = "DispelCurse",
        debuffOnly = true,
    },
    {
        key = "poison",
        cand = { includeDispelTypes = { Poison = true } },
        skey = "DispelPoison",
        debuffOnly = true,
    },
    {
        key = "disease",
        cand = { includeDispelTypes = { Disease = true } },
        skey = "DispelDisease",
        debuffOnly = true,
    },
    {
        key = "bleed",
        cand = { includeDispelTypes = { Bleed = true } },
        skey = "DispelBleed",
        debuffOnly = true,
    },
    -- Important: two Blizzard importance concepts, combined per unit in BuildChain. The
    -- class default (isPriorityAura) is the raid-frame priority curation -- the concept
    -- for debuffs on FRIENDLY units (the player frame and Player Aura Bars use it
    -- alone; Raid Frames' DebuffManager uses the same flag). Non-player frames
    -- (target/focus/boss -- dynamically friendly OR hostile) render BOTH: this group
    -- plus a second one for nameplateShowPersonal (the flag default nameplates display
    -- by, covering enemies), partitioned so a doubly-flagged aura renders once
    -- (PRIORITY_NONPLAYER_CAND). The IMPORTANT filter TOKEN is NOT usable for any of
    -- this: per AuraUtil.lua it flags HELPFUL auras (enemy-nameplate buff
    -- importance), so HARMFUL|IMPORTANT is an empty set.
    { key = "priority", cand = { isPriorityAura = true }, skey = "PriorityAura", debuffOnly = true },
    { key = "steal", cand = { isStealable = true }, skey = "Stealable", buffOnly = true },
    -- Any debuff carrying a dispel type (Magic/Curse/Disease/Poison/Bleed),
    -- regardless of whether the PLAYER can remove it -- distinct from the
    -- "dispellable" token above (RAID_PLAYER_DISPELLABLE, dispellable-by-you
    -- only). Same native set Raid Frames' DebuffManager verifies against
    -- Blizzard's source (CUI_RaidFrames_DebuffManager.lua's TYPED_DEBUFFS) --
    -- kept as this module's own copy rather than a cross-addon reference.
    -- Set-valued candidate (includeDispelTypes takes a SET table, not a
    -- boolean); rides the same cand-table merge as every class above.
    -- Offered by Player Aura Bars and the player frame (both dropdowns list it
    -- through ns.PAB_ClassItems as "Dispels"); target/focus/boss never read it.
    {
        key = "dispeltyped",
        cand = {
            includeDispelTypes = { Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true },
        },
        skey = "DispelTyped",
        debuffOnly = true,
    },
}

-- Shared with CludesUIUnitFrames_PlayerAuraBars.lua: same class vocabulary, same
-- mutual-exclusion semantics (token classes negate every enabled class before them;
-- candidate classes are engine-side selectors carried as candidate-filter tables, incl.
-- the nonplayer complementary handoff). One source of truth so a class addition/removal
-- here cannot silently drift from what Player Aura Bars offers.
mod.UF_TokenClasses = TOKEN_CLASSES
mod.UF_CandidateClasses = CANDIDATE_CLASSES

-- Purgeable Buff Glow (target/focus buffs, s.buffPurgeGlow = a shared glow
-- style index). Which SPECIFIC buff is purgeable is unreadable on enemy data
-- in instanced PvP (a candidate compare on isStealable matches nothing
-- there), so the GROUP answers it: the buffs render as two groups split by
-- the engine-evaluated Dispellable token, and only the purgeable group wears
-- the glow style (see BuildChain / PurgeGlow.Register). Off, or on a
-- character with no offensive dispel, every chain stays byte-identical.
-- friendly[unit] = last assistable answer, watch[unit] = glow on for that unit
-- (both read by the friendly gate beside IncGate, below).
local PurgeGlow = { TOKEN = "RAID_PLAYER_DISPELLABLE", friendly = {}, watch = {} }

function PurgeGlow.On(unitToken, cfg)
    if unitToken == "player" then
        return false
    end
    local g = cfg and cfg.buffPurgeGlow
    if type(g) ~= "number" or g < 1 then
        return false
    end
    -- Nothing to glow while the buff row is hidden (Buff Display None and not
    -- riding the debuff stack): no split, no friendly watch. Showing it again
    -- is a settings change, so the reload re-reads this.
    if
        cfg.showBuffs == false and not (cfg.debuffAnchorBuffs == true and (cfg.debuffAnchor or "none") ~= "none")
    then
        return false
    end
    AK = AK or CludesUI.AuraKit
    if not (AK and AK.OffensiveDispelTypes) then
        return false
    end
    if not PurgeGlow.watching then
        PurgeGlow.watching = true
        -- A capability flip (talents, spec, pet) moves units between the split
        -- and the plain row; the reload is signature/fingerprint gated.
        AK.OnOffensiveDispelChange(function()
            if mod.UF_ReloadAllAuraContainers then
                mod.UF_ReloadAllAuraContainers()
            end
        end)
    end
    local magic, enrage = AK.OffensiveDispelTypes()
    return magic or enrage
end

-- Important's SECOND group payload for NON-player frames (see the
-- priority class comment above): the nameplate-importance flag,
-- partitioned by isPriorityAura = false so an aura carrying BOTH flags
-- renders exactly once (the primary isPriorityAura group owns it). False-valued
-- candidate booleans are field-proven (Raid Frames DM subtract, the nonplayer handoff).
-- Static table: BuildChain runs per settings apply.
local PRIORITY_NONPLAYER_CAND = { nameplateShowPersonal = true, isPriorityAura = false }

-- Order-independent fingerprint of a candidate-filter table. The config pass re-sets
-- candidates on live groups (SetAuraGroupCandidateFilters clears the group and
-- re-parses). Lane-shaped and carried links embed their payload in the group KEY
-- (LaneKey), so each such payload is its own declared variant; plain keys whose
-- payload follows the enabled set (the Non-Player handoff and the flip-case links
-- that skip it) rely on that live retake (ApplyGroupConfig). Number-keyed sets
-- (spell ids) fingerprint as count:sum; string-keyed sets join outright.
local function CandFP(castFrame)
    if not castFrame then
        return "-"
    end
    local keyList = {}
    for k in pairs(castFrame) do
        keyList[#keyList + 1] = k
    end
    table.sort(keyList)
    local parts = {}
    for index = 1, #keyList do
        local k = keyList[index]
        local val = castFrame[k]
        if type(val) == "table" then
            local first = next(val)
            if type(first) == "number" then
                local n, sum = 0, 0
                for ident in pairs(val) do
                    n = n + 1
                    sum = (sum + ident) % 2147483647
                end
                parts[#parts + 1] = k .. "=" .. n .. ":" .. sum
            else
                local nameList = {}
                for name in pairs(val) do
                    nameList[#nameList + 1] = tostring(name)
                end
                table.sort(nameList)
                parts[#parts + 1] = k .. "=" .. table.concat(nameList, "+")
            end
        else
            parts[#parts + 1] = k .. "=" .. tostring(val)
        end
    end
    return table.concat(parts, ",")
end

-- The "priority" candidate payload (isPriorityAura), shared by the
-- non-player debuff modes below and the class vocabulary above; its class
-- entry drives the player frame's Important ownership in BuildChain.
local PRIORITY_CAND, PRIORITY_CLASS
for index = 1, #CANDIDATE_CLASSES do
    if CANDIDATE_CLASSES[index].key == "priority" then
        PRIORITY_CLASS = CANDIDATE_CLASSES[index]
        PRIORITY_CAND = PRIORITY_CLASS.cand
    end
end

-- Non-player DEBUFF filter (target/focus/boss): ONE single-select mode,
-- a pure VIEW over the legacy keys -- nothing is rewritten on update.
--   s.debuffFilterMode      explicit pick from the Debuff Filter dropdown
--   else derived:  Important + Own Only checked -> "importantOwn"
--                  Important checked            -> "important"
--                  Own Only checked             -> "own" (the boss default)
--                  nothing                      -> "all"
-- Tracked Auras never enter the derivation: they are ADDITIONAL tracking in
-- every mode (caster scope = the per-entry MINE tag, never the filter), and
-- only the explicit "tracked" mode makes them the whole display.
local MODE_VALID = {
    all = true,
    tracked = true,
    own = true,
    important = true,
    importantOwn = true,
    importantOrOwn = true,
}
local function HasActiveIncludes(cfg)
    local included = cfg.debuffInclude
    if not included then
        return false
    end
    for _, val in pairs(included) do
        if val then
            return true
        end
    end
    return false
end
local function DebuffFilterMode(cfg)
    local m = cfg.debuffFilterMode
    if m and MODE_VALID[m] then
        return m
    end
    local own = cfg.onlyPlayerDebuffs == true
    if cfg.debuffPriorityAura == true then
        if own then
            return "importantOwn"
        end
        return "important"
    end
    if own then
        return "own"
    end
    return "all"
end
mod.UF_DebuffFilterMode = DebuffFilterMode
mod.UF_DebuffHasIncludes = HasActiveIncludes

-- Tracked Auras include links (target/focus/boss): the unit's explicit
-- always-show spells, additive in every mode. Caster scope lives in the
-- filter STRING, so the two scopes are two links: "inc" any caster,
-- "incmine" your casts (PLAYER). Boss entries default to your casts with an
-- any-caster OPT-OUT map (s.debuffIncludeAnyCaster); target/focus entries
-- default to any caster with a MINE OPT-IN map (s.debuffIncludeMine). Each
-- key embeds its id-set fingerprint so list/tag edits declare a fresh
-- variant (stale ones park at 0); the cand overrides BOTH spell-ID sets in
-- the config sweep -- includeSpellIDs = the actives, excludeSpellIDs = {}
-- so the shared excludes (which hide the actives from every OTHER group,
-- see ApplyGroupConfig) never blank these.
local function AppendIncludeLinks(filterChain, cfg, unitToken)
    local included = cfg.debuffInclude
    if not included then
        return
    end
    local isBoss = unitToken:match("^boss") ~= nil
    local anym = isBoss and cfg.debuffIncludeAnyCaster or nil
    local minem = (not isBoss) and cfg.debuffIncludeMine or nil
    local m, mm
    for ident, val in pairs(included) do
        if val then
            local mine
            if isBoss then
                mine = not (anym and anym[ident])
            else
                mine = minem ~= nil and minem[ident] == true
            end
            if mine then
                mm = mm or {}
                mm[ident] = true
            else
                m = m or {}
                m[ident] = true
            end
        end
    end
    if m then
        filterChain[#filterChain + 1] = {
            key = "inc|" .. CandFP({ includeSpellIDs = m }),
            tokens = { "HARMFUL" },
            cand = { includeSpellIDs = m, excludeSpellIDs = {} },
            inc = true,
        }
    end
    if mm then
        filterChain[#filterChain + 1] = {
            key = "incmine|" .. CandFP({ includeSpellIDs = mm }),
            tokens = { "HARMFUL", "PLAYER" },
            cand = { includeSpellIDs = mm, excludeSpellIDs = {} },
            inc = true,
            mine = true,
        }
    end
end

-- Non-player DEBUFF chain: a fixed, mutually exclusive group set per mode.
-- Own Only is the PLAYER filter token (the isFromPlayerOrPlayerPet candidate
-- matches ANY player's casts, not only yours), and
-- "Important or Own" partitions with !PLAYER so an aura renders once.
-- Important covers both importance concepts (see PRIORITY_NONPLAYER_CAND).
-- Every group is capped on its own (the engine has no shared cap, and a
-- group's contents are secret in combat), so Important or Own caps each of
-- its two important-from-others links (important = true) with Max Important
-- (s.maxImportantDebuffs, unset = Max Count; the two together can show twice
-- that) and your own with Max Count.
-- Show All emits no include links: the catch-all already shows the tracked
-- spells, and ApplyGroupConfig leaves them un-excluded when no link renders
-- them. Only Tracked Auras with an empty list = an empty chain = nothing.
local function NonPlayerDebuffChain(cfg, unitToken)
    local modeName = DebuffFilterMode(cfg)
    local filterChain = {}
    if modeName == "all" then
        filterChain[1] = { key = "all", tokens = { "HARMFUL" } }
        return filterChain
    end
    if modeName == "own" then
        filterChain[1] = { key = "own", tokens = { "HARMFUL", "PLAYER" } }
    elseif modeName == "important" then
        filterChain[1] = { key = "priority", tokens = { "HARMFUL" }, cand = PRIORITY_CAND }
        filterChain[2] = { key = "prioritynp", tokens = { "HARMFUL" }, cand = PRIORITY_NONPLAYER_CAND }
    elseif modeName == "importantOwn" then
        filterChain[1] = { key = "priorityown", tokens = { "HARMFUL", "PLAYER" }, cand = PRIORITY_CAND }
        filterChain[2] = { key = "prioritynpown", tokens = { "HARMFUL", "PLAYER" }, cand = PRIORITY_NONPLAYER_CAND }
    elseif modeName == "importantOrOwn" then
        filterChain[1] = { key = "own", tokens = { "HARMFUL", "PLAYER" } }
        filterChain[2] = {
            key = "priorityoth",
            tokens = { "HARMFUL", "!PLAYER" },
            cand = PRIORITY_CAND,
            important = true,
        }
        filterChain[3] = {
            key = "prioritynpoth",
            tokens = { "HARMFUL", "!PLAYER" },
            cand = PRIORITY_NONPLAYER_CAND,
            important = true,
        }
    end
    AppendIncludeLinks(filterChain, cfg, unitToken)
    return filterChain
end

local function ClassEnabled(classFile, buffSide, cfg, unitToken)
    if classFile.buffOnly and not buffSide then
        return false
    end
    if classFile.debuffOnly and buffSide then
        return false
    end
    -- Player-frame-only classes: offered nowhere else in the UI, and a
    -- stale key on another unit's settings must have no effect.
    if classFile.playerUnitOnly and unitToken ~= "player" then
        return false
    end
    -- Non-player BUFF vocabulary is Stealable / Big Defensive / Dispellable only
    -- (zero-migration rule: retired checkbox keys go unread). Non-player DEBUFFS
    -- never reach the class system -- NonPlayerDebuffChain owns them.
    if
        buffSide
        and unitToken ~= "player"
        and classFile.key ~= "steal"
        and classFile.key ~= "bigdef"
        and classFile.key ~= "dispellable"
    then
        return false
    end
    local prefixText = "debuff"
    if buffSide then
        prefixText = "buff"
    end
    return cfg[prefixText .. classFile.skey] == true
end

-- Hide-lane test (two-lane filter dropdowns): mirrors ClassEnabled's per-unit
-- vocabulary limits, reading the negative sets (s.buffNegClasses /
-- s.debuffNegClasses, keyed by class.skey). The options setters keep the two
-- lanes mutually exclusive; if stale data ever disagrees, show wins (the hidden
-- pass skips enabled classes).
local function ClassNegated(classFile, buffSide, cfg, unitToken)
    if classFile.buffOnly and not buffSide then
        return false
    end
    if classFile.debuffOnly and buffSide then
        return false
    end
    if classFile.playerUnitOnly and unitToken ~= "player" then
        return false
    end
    if
        buffSide
        and unitToken ~= "player"
        and classFile.key ~= "steal"
        and classFile.key ~= "bigdef"
        and classFile.key ~= "dispellable"
    then
        return false
    end
    local negs
    if buffSide then
        negs = cfg.buffNegClasses
    else
        negs = cfg.debuffNegClasses
    end
    return negs ~= nil and negs[classFile.skey] == true
end

-- Union of two dispel-type sets as a NEW table (vocabulary tables are shared
-- and never mutated); nil-safe on the accumulator.
local function MergeDispelTypes(acc, add)
    local result = {}
    if acc then
        for k, val in pairs(acc) do
            result[k] = val
        end
    end
    for k, val in pairs(add) do
        result[k] = val
    end
    return result
end
mod.UF_MergeDispelTypes = MergeDispelTypes

local function BuildChain(baseSet, buffSide, cfg, unitToken)
    -- Non-player DEBUFFS run the mode model (one dropdown value, see
    -- NonPlayerDebuffChain). The class chain below serves the non-player BUFF
    -- elements and the player frame's debuff legacy path (PlayerDebuffChain
    -- delegates here for the class-checkbox model).
    if not buffSide and unitToken ~= "player" then
        return NonPlayerDebuffChain(cfg, unitToken)
    end
    local glowOn = buffSide and PurgeGlow.Active(unitToken, cfg)
    local filterChain, negList = {}, {}
    local subPick, negDispelTypes, npNegOwned, anyNegOwned

    -- HIDDEN PASS -- hide-lane classes join FIRST as parked links so their
    -- negations / forward excludes / inverted booleans reach every positive link
    -- (and the show-all catch-all below, when one is emitted). These link keys
    -- self-describe (tokens embedded, PlayerDebuffChain's convention) because
    -- their shapes change with the lane selection; with an empty hide lane this
    -- pass emits nothing and every legacy key below stays byte-identical.
    for index = 1, #TOKEN_CLASSES do
        local classFile = TOKEN_CLASSES[index]
        if ClassNegated(classFile, buffSide, cfg, unitToken) and not ClassEnabled(classFile, buffSide, cfg, unitToken) then
            local tokenList = { baseSet, classFile.token }
            for n = 1, #negList do
                tokenList[#tokenList + 1] = negList[n]
            end
            filterChain[#filterChain + 1] = {
                key = classFile.key .. "|" .. table.concat(tokenList, ""),
                tokens = tokenList,
                hidden = true,
            }
            negList[#negList + 1] = classFile.neg or ("!" .. classFile.token)
        end
    end
    for index = 1, #CANDIDATE_CLASSES do
        local classFile = CANDIDATE_CLASSES[index]
        local classColor = classFile.cand
        if
            classColor
            and ClassNegated(classFile, buffSide, cfg, unitToken)
            and not ClassEnabled(classFile, buffSide, cfg, unitToken)
        then
            -- Forward-capable candidate classes (dispeltyped's include map,
            -- nonplayer's complementary boolean) subtract through the hidden-link
            -- + forward-exclude route; pure boolean classes invert onto subCand
            -- (false-valued candidate booleans, field-proven).
            local forward = classColor.includeDispelTypes ~= nil or classColor.isFromPlayerOrPlayerPet ~= nil
            if forward then
                local tokenList = { baseSet }
                for n = 1, #negList do
                    tokenList[#tokenList + 1] = negList[n]
                end
                filterChain[#filterChain + 1] = {
                    key = classFile.key .. "|" .. table.concat(tokenList, ""),
                    tokens = tokenList,
                    cand = classColor,
                    hidden = true,
                }
                if classColor.includeDispelTypes then
                    negDispelTypes = MergeDispelTypes(negDispelTypes, classColor.includeDispelTypes)
                end
                if classColor.isFromPlayerOrPlayerPet == false then
                    npNegOwned = true
                elseif classColor.isFromPlayerOrPlayerPet == true then
                    anyNegOwned = true
                end
            else
                subPick = subPick or {}
                for k, val in pairs(classColor) do
                    if type(val) == "boolean" then
                        subPick[k] = not val
                    end
                end
                -- Non-player "Important" renders through TWO groups (priority +
                -- prioritynp below); hiding it must exclude both faces.
                if classFile.key == "priority" and unitToken ~= "player" then
                    subPick.nameplateShowPersonal = false
                end
            end
        end
    end

    local lanesActive = #filterChain > 0 or subPick ~= nil
    -- Merge the hide lane's candidate-side exclusions over a positive/catch-all
    -- group's own cand (copy-on-write: the vocabulary tables are shared and must
    -- never be mutated). Identity-preserving no-op while the hide lane is empty.
    local function NegCand(baseCand)
        if not lanesActive then
            return baseCand
        end
        local result
        if baseCand then
            result = {}
            for k, val in pairs(baseCand) do
                result[k] = val
            end
        end
        if subPick then
            result = result or {}
            for k, val in pairs(subPick) do
                if result[k] == nil then
                    result[k] = val
                end
            end
        end
        if negDispelTypes then
            result = result or {}
            local included = result.includeDispelTypes
            if included then
                -- A positive include map (typed dispels) shrinks by the hidden
                -- types; a per-type map never holds a hidden type (lanes are
                -- exclusive per class), so the copy is a no-op there.
                local m
                for T in pairs(negDispelTypes) do
                    if included[T] then
                        m = m or MergeDispelTypes(nil, included)
                        m[T] = nil
                    end
                end
                if m then
                    result.includeDispelTypes = m
                end
            elseif result.excludeDispelTypes then
                -- A link already carrying shown types forward (see the positive
                -- pass) keeps them: the hidden types join the same exclude.
                result.excludeDispelTypes = MergeDispelTypes(result.excludeDispelTypes, negDispelTypes)
            else
                result.excludeDispelTypes = negDispelTypes
            end
        end
        if npNegOwned then
            result = result or {}
            if result.isFromPlayerOrPlayerPet == nil then
                result.isFromPlayerOrPlayerPet = true
            end
        elseif anyNegOwned then
            result = result or {}
            if result.isFromPlayerOrPlayerPet == nil then
                result.isFromPlayerOrPlayerPet = false
            end
        end
        return result
    end
    -- Lane-shaped links (and links carrying a partition from the positive pass,
    -- `carried`) get self-describing keys, so each payload is its own declared
    -- variant; legacy plain keys survive untouched configs byte-identically.
    local function LaneKey(auraKey, tokenList, candidate, wasCarried)
        if not (lanesActive or wasCarried) then
            return auraKey
        end
        return auraKey .. "|" .. table.concat(tokenList, "") .. "|" .. CandFP(candidate)
    end

    -- POSITIVE PASS -- the legacy chain verbatim when the hide lane is empty
    -- (negations arrive pre-seeded with the hidden pass).
    for index = 1, #TOKEN_CLASSES do
        local classFile = TOKEN_CLASSES[index]
        if ClassEnabled(classFile, buffSide, cfg, unitToken) then
            local tokenList = { baseSet, classFile.token }
            for n = 1, #negList do
                tokenList[#tokenList + 1] = negList[n]
            end
            local candidate = NegCand(nil)
            local auraKey = LaneKey(classFile.key, tokenList, candidate)
            -- Purgeable Buff Glow (own keys: a group's style is fixed). The
            -- Dispellable class IS the purgeable set, so its link wears the glow;
            -- any other shown token class (Big Defensive) splits into its
            -- purgeable part, glowing, and the rest -- unless Dispellable,
            -- shown before it or hidden, already took the purgeable buffs.
            local notPurge = "!" .. PurgeGlow.TOKEN
            local purgeTaken = false
            if glowOn and classFile.key ~= "dispellable" then
                for n = 1, #negList do
                    if negList[n] == notPurge then
                        purgeTaken = true
                        break
                    end
                end
            end
            if glowOn and classFile.key == "dispellable" then
                filterChain[#filterChain + 1] = { key = auraKey .. ":glow", tokens = tokenList, cand = candidate, glow = true }
            elseif glowOn and not purgeTaken then
                local gT = { baseSet, classFile.token, PurgeGlow.TOKEN }
                local rT = { baseSet, classFile.token, notPurge }
                for n = 1, #negList do
                    gT[#gT + 1] = negList[n]
                    rT[#rT + 1] = negList[n]
                end
                filterChain[#filterChain + 1] = {
                    key = LaneKey(classFile.key .. ":glow", gT, candidate),
                    tokens = gT,
                    cand = candidate,
                    glow = true,
                }
                filterChain[#filterChain + 1] =
                    { key = LaneKey(classFile.key .. ":rest", rT, candidate), tokens = rT, cand = candidate }
            else
                filterChain[#filterChain + 1] = { key = auraKey, tokens = tokenList, cand = candidate }
            end
            negList[#negList + 1] = classFile.neg or ("!" .. classFile.token)
        end
    end
    -- Non-Player exclusivity handoff: once the nonplayer class (boolean
    -- isFromPlayerOrPlayerPet = false) is in the chain, every later
    -- candidate class carries the complementary TRUE so the two sides
    -- partition instead of double-displaying (an aura is shown by exactly
    -- one group; candidate booleans cannot be token-negated).
    -- EXCEPT Important, which OWNS its overlap with Non-Player (the owner Raid
    -- Frames and Player Aura Bars use): the Important link takes no handoff and
    -- the Non-Player link carries isPriorityAura = false instead, while
    -- Important is shown (the classes ranked above Important follow it; see
    -- the pre-scan below). Only the player frame offers Non-Player, so this
    -- never reaches another unit.
    local npOwned, anyOwned = false, false
    local prioShown = PRIORITY_CLASS ~= nil and ClassEnabled(PRIORITY_CLASS, buffSide, cfg, unitToken)
    -- A shown Important carries isPriorityAura = false onto every later link
    -- (the typed dispel class), so an Important typed debuff renders once.
    local prioOwned = false
    -- Shown Boss / Role / Can Apply rows carry their false boolean (isBossAura /
    -- isRoleAura / canApplyAura = false) onto every later link, so the owner
    -- order below Non-Player / From Any Player is Boss > Role > Can Apply >
    -- per-type > Important > Dispels.
    local boolCarry
    -- Shown per-type dispel maps forward an exclude onto later candidate links:
    -- the typed dispel class drops the shown types from its include map, and a
    -- later link with no include map (Important) carries them as
    -- excludeDispelTypes, so a type shown on its own renders once.
    local shownTypes
    -- Non-Player + Important: Important ranks ABOVE Non-Player, so every class
    -- ranked above Important (Boss, Role, Can Apply, the per-type dispel rows)
    -- must rank above Non-Player too, or the order cycles and an NPC Important
    -- debuff of a shown type (or an NPC Important Boss debuff) matches no link
    -- at all. Non-Player sits FIRST, so the pair is pre-scanned: those links skip
    -- the Non-Player handoff, and the Non-Player link excludes their types and
    -- carries their false booleans. Owner order then: Boss > Role > Can Apply >
    -- per-type > Important > Non-Player > Dispels (as Raid Frames and Player
    -- Aura Bars rank Important over Non-Player). Nothing changes unless
    -- Non-Player, Important and one of those rows are all shown.
    local flipTypes, flipBools, npFlip
    if prioShown then
        local npShown
        for index = 1, #CANDIDATE_CLASSES do
            local classFile = CANDIDATE_CLASSES[index]
            if classFile == PRIORITY_CLASS then
                break
            end
            if ClassEnabled(classFile, buffSide, cfg, unitToken) then
                if classFile.key == "nonplayer" then
                    npShown = true
                elseif classFile.cand.includeDispelTypes then
                    flipTypes = MergeDispelTypes(flipTypes, classFile.cand.includeDispelTypes)
                elseif classFile.cand.isBossAura or classFile.cand.isRoleAura or classFile.cand.canApplyAura then
                    flipBools = flipBools or {}
                    for k, val in pairs(classFile.cand) do
                        flipBools[k] = not val
                    end
                end
            end
        end
        if npShown then
            npFlip = true
        else
            flipTypes, flipBools = nil, nil
        end
    end
    for index = 1, #CANDIDATE_CLASSES do
        local classFile = CANDIDATE_CLASSES[index]
        if ClassEnabled(classFile, buffSide, cfg, unitToken) then
            local tokenList = { baseSet }
            for n = 1, #negList do
                tokenList[#tokenList + 1] = negList[n]
            end
            local candidate = classFile.cand
            -- Set when one of the partitions below lands on this link: its
            -- payload then joins the key (see LaneKey), so a setup none of
            -- them touches keeps its legacy plain keys.
            local wasCarried = false
            local isOwned = false -- cand is already this link's own copy
            local boolOwner = classFile.cand.isBossAura or classFile.cand.isRoleAura or classFile.cand.canApplyAura
            local skipNp = npOwned
                and (
                    classFile.key == "priority"
                    or (npFlip and boolOwner)
                    or (
                        flipTypes ~= nil
                        and classFile.cand.includeDispelTypes ~= nil
                        and classFile.key ~= "dispeltyped"
                    )
                )
            if (npOwned or anyOwned) and not skipNp then
                local src = candidate
                candidate = {}
                for k, val in pairs(src) do
                    candidate[k] = val
                end
                isOwned = true
                if candidate.isFromPlayerOrPlayerPet == nil then
                    candidate.isFromPlayerOrPlayerPet = npOwned
                end
            end
            if (prioOwned or (prioShown and classFile.key == "nonplayer")) and candidate.isPriorityAura == nil then
                if not isOwned then
                    local src = candidate
                    candidate = {}
                    for k, val in pairs(src) do
                        candidate[k] = val
                    end
                    isOwned = true
                end
                candidate.isPriorityAura = false
                wasCarried = true
            end
            -- Boss / Role / Can Apply ownership: the false booleans of the shown
            -- rows before this link, or on the Non-Player link (always first, so
            -- nothing reaches it that way) the flip set pre-scanned above.
            local bools = boolCarry
            if classFile.key == "nonplayer" then
                bools = flipBools
            end
            -- A dispel-type link the Hide lane empties matches nothing, so it
            -- takes no carry and keeps its key.
            if bools and candidate.includeDispelTypes and negDispelTypes then
                local live = false
                for T in pairs(candidate.includeDispelTypes) do
                    if not negDispelTypes[T] then
                        live = true
                        break
                    end
                end
                if not live then
                    bools = nil
                end
            end
            if bools then
                for k, val in pairs(bools) do
                    if candidate[k] == nil then
                        if not isOwned then
                            local src = candidate
                            candidate = {}
                            for sk, savedVars in pairs(src) do
                                candidate[sk] = savedVars
                            end
                            isOwned = true
                        end
                        candidate[k] = val
                        wasCarried = true
                    end
                end
            end
            if classFile.key == "nonplayer" and flipTypes then
                if not isOwned then
                    local src = candidate
                    candidate = {}
                    for k, val in pairs(src) do
                        candidate[k] = val
                    end
                    isOwned = true
                end
                candidate.excludeDispelTypes = flipTypes
                wasCarried = true
            end
            if shownTypes and not candidate.includeDispelTypes and candidate.excludeDispelTypes == nil then
                if not isOwned then
                    local src = candidate
                    candidate = {}
                    for k, val in pairs(src) do
                        candidate[k] = val
                    end
                    isOwned = true
                end
                -- Never mutated after this (MergeDispelTypes builds new sets),
                -- so later links may share it.
                candidate.excludeDispelTypes = shownTypes
                wasCarried = true
            end
            if shownTypes and candidate.includeDispelTypes then
                local included = candidate.includeDispelTypes
                local m
                for T in pairs(shownTypes) do
                    if included[T] then
                        m = m or MergeDispelTypes(nil, included)
                        m[T] = nil
                    end
                end
                if m then
                    local src = candidate
                    candidate = {}
                    for k, val in pairs(src) do
                        candidate[k] = val
                    end
                    candidate.includeDispelTypes = m
                end
            end
            candidate = NegCand(candidate)
            local itemLink = { key = LaneKey(classFile.key, tokenList, candidate, wasCarried), tokens = tokenList, cand = candidate }
            -- Stealable buffs are the player's own steal/purge targets: glow too.
            if glowOn and classFile.key == "steal" then
                itemLink.key = itemLink.key .. ":glow"
                itemLink.glow = true
            end
            filterChain[#filterChain + 1] = itemLink
            -- Important on non-player frames covers BOTH importance concepts (the
            -- unit's hostility is dynamic -- a target can be an ally or an enemy): a
            -- second group adds the nameplate-importance flag, partitioned against the
            -- primary isPriorityAura group (see PRIORITY_NONPLAYER_CAND). The nonplayer
            -- handoff never applies here (that class is player-frame only, so npOwned
            -- is always false off-player).
            if classFile.key == "priority" and unitToken ~= "player" then
                local pnp = NegCand(PRIORITY_NONPLAYER_CAND)
                filterChain[#filterChain + 1] = { key = LaneKey("prioritynp", tokenList, pnp), tokens = tokenList, cand = pnp }
            end
            if classFile.key == "nonplayer" then
                npOwned = true
            end
            if classFile.key == "anyplayer" then
                anyOwned = true
            end
            if classFile.key == "priority" then
                prioOwned = true
            end
            if boolOwner then
                boolCarry = boolCarry or {}
                for k, val in pairs(classFile.cand) do
                    boolCarry[k] = not val
                end
            end
            if classFile.cand.includeDispelTypes and classFile.key ~= "dispeltyped" then
                shownTypes = MergeDispelTypes(shownTypes, classFile.cand.includeDispelTypes)
            end
        end
    end

    -- Hide lane with NOTHING positive on a non-player unit: the legacy show-all
    -- fallback (plain "all" group, ApplyGroupConfig) cannot carry the negations,
    -- so an explicit catch-all link takes its place -- everything minus the hide
    -- lane. Player frames keep PAB semantics: nothing positive = show nothing.
    -- Purgeable Buff Glow splits that show-all set (the "all" fallback or the
    -- catch-all) into the purgeable group, which wears the glow, and the rest;
    -- not while the Hide lane removes the Dispellable class (nothing to glow).
    if (lanesActive or glowOn) and unitToken ~= "player" then
        local hasPositive = false
        for index = 1, #filterChain do
            if not filterChain[index].hidden then
                hasPositive = true
                break
            end
        end
        if not hasPositive then
            local notPurge = "!" .. PurgeGlow.TOKEN
            local split = glowOn
            for n = 1, #negList do
                if negList[n] == notPurge then
                    split = false
                end
            end
            local candidate = NegCand(nil)
            if split then
                local gT, rT = { baseSet, PurgeGlow.TOKEN }, { baseSet, notPurge }
                for n = 1, #negList do
                    gT[#gT + 1] = negList[n]
                    rT[#rT + 1] = negList[n]
                end
                filterChain[#filterChain + 1] =
                    { key = LaneKey("pglow", gT, candidate), tokens = gT, cand = candidate, glow = true }
                filterChain[#filterChain + 1] = { key = LaneKey("prest", rT, candidate), tokens = rT, cand = candidate }
            elseif lanesActive then
                local allTokens = { baseSet }
                for n = 1, #negList do
                    allTokens[#allTokens + 1] = negList[n]
                end
                filterChain[#filterChain + 1] =
                    { key = LaneKey("nall", allTokens, candidate), tokens = allTokens, cand = candidate }
            end
        end
    end
    return filterChain
end

-- One-shot lane split for the player frame's two-lane filter dropdowns (stamp on
-- the player unit's settings table; an imported older profile lacks the stamp and
-- re-splits). Broad-mode selections were SUBTRACTING under the old one-lane model --
-- move them to the hide lane (s.buffNegFilters / s.debuffNegClasses) so rendering
-- is bit-identical; add-mode selections already mean SHOW and stay put.
local function EnsurePlayerAuraLanes(cfg)
    if cfg.auraFilterLanesV1 then
        return
    end
    cfg.auraFilterLanesV1 = true
    if (cfg.buffShowAll ~= false or cfg.buffHasDuration == true) and cfg.buffFilters and next(cfg.buffFilters) then
        cfg.buffNegFilters = cfg.buffFilters
        cfg.buffFilters = nil
    end
    if cfg.debuffShowAll ~= false then
        local negated
        local function Move(entries)
            for index = 1, #entries do
                local classFile = entries[index]
                if not classFile.buffOnly and cfg["debuff" .. classFile.skey] == true then
                    negated = negated or {}
                    negated[classFile.skey] = true
                    cfg["debuff" .. classFile.skey] = nil
                end
            end
        end
        Move(TOKEN_CLASSES)
        Move(CANDIDATE_CLASSES)
        if negated then
            cfg.debuffNegClasses = negated
        end
    end
end
mod.UF_EnsurePlayerAuraLanes = EnsurePlayerAuraLanes

-- Player-frame buffs run the Player Aura Bars content model (the shared
-- PAB_Filters registry + All Buffs / Has Duration / Own Only, two-lane
-- semantics -- identical dropdown, identical engine behavior; see the
-- player branch in CUI_UnitFrames_Options.lua's Buff Filter slot). Keys:
--   buffShowAll     (nil = on) -- All Buffs
--   buffFilters     ([filterId] = true, SHOW lane, shared ns.PAB_Filters registry)
--   buffNegFilters  ([filterId] = true, HIDE lane)
--   buffSpells      ({ spellID, ... } -- reserved for Extra Spells parity)
--   buffHasDuration (true = hide permanent buffs, candidate maxDuration)
-- Chain keys embed each link's candidate fingerprint: payload changes
-- declare fresh variants through the existing sig/declare machinery and
-- stale variants park at 0. Hide-lane filters SUBTRACT their resolved
-- spells via the catch-all's excludeSpellIDs in the broad modes and drop
-- out of the include group's union in add mode (Extra Spells win over the
-- hide lane). The legacy buff class checkboxes no longer apply to the
-- player frame (stale class keys stay inert); an empty chain = add mode
-- with nothing selected = show nothing, exactly like an empty Player Aura
-- Bar.
local pbImportEnsured
local function PlayerBuffChain(cfg)
    EnsurePlayerAuraLanes(cfg)
    if
        not pbImportEnsured
        and ((cfg.buffFilters and next(cfg.buffFilters)) or (cfg.buffNegFilters and next(cfg.buffNegFilters)))
    then
        -- Selected registry filters (either lane) need the curated presets
        -- materialized (idempotent; normally PAB/options do this, but PAB can
        -- be disabled while the player frame still uses the registry).
        pbImportEnsured = true
        if mod.PAB_ImportBM2Filters then
            mod.PAB_ImportBM2Filters()
        end
    end
    -- Curated spell families (a primary plus its alts: rank/talent ids and
    -- multi-state buffs whose aura swaps spell ID as it advances) expand at
    -- resolution, exactly as PAB_ResolveSpells does for this same shared filter
    -- registry, so the player frame and Player Aura Bars agree on what a filter
    -- tracks. An explicit false in the owning filter wins.
    local function ExpandBuffFamily(set, ident, blocked)
        local fam = mod.PAB_SPELL_FAMILY and mod.PAB_SPELL_FAMILY[ident]
        if not fam then
            return
        end
        for index = 1, #fam do
            local m = fam[index]
            if not (blocked and blocked[m] == false) then
                set[m] = true
            end
        end
    end
    local filterChain = {}
    local dur = cfg.buffHasDuration == true
    -- All Buffs and Has Duration are mutually exclusive broad-content modes (the
    -- options setters enforce it): either one builds the catch-all -- Has Duration's is
    -- narrowed to duration-carrying buffs by maxDuration below -- and checked filters
    -- SUBTRACT from it. With neither on, filters ADD through the spells group.
    local broad = cfg.buffShowAll ~= false or dur
    -- Blacklist (Edit Blacklist in the Filters dropdown): applied exactly while the
    -- dropdown offers it -- All Buffs or Has Duration on -- and excluded from every
    -- content group below, so a blacklisted spell never displays.
    local bl
    if cfg.buffBlacklist and next(cfg.buffBlacklist) and broad then
        bl = cfg.buffBlacklist
    end
    if broad then
        local candidate
        local ex
        if cfg.buffNegFilters then
            for filterId in pairs(cfg.buffNegFilters) do
                local frame = mod.PAB_GetFilter and mod.PAB_GetFilter(filterId)
                if frame and frame.spells then
                    -- Ids a preset keeps only for the other client never count
                    -- here (ns.PAB_OtherClientSpell), same as on Player Aura Bars.
                    for ident, enabled in pairs(frame.spells) do
                        if enabled and not mod.PAB_OtherClientSpell(frame, ident) then
                            ex = ex or {}
                            ex[ident] = true
                            ExpandBuffFamily(ex, ident, frame.spells)
                        end
                    end
                end
            end
        end
        if bl then
            ex = ex or {}
            for ident in pairs(bl) do
                ex[ident] = true
            end
        end
        if ex then
            candidate = { excludeSpellIDs = ex }
        end
        if dur then
            candidate = candidate or {}
            candidate.maxDuration = math.huge
        end
        filterChain[#filterChain + 1] = { key = "pball|" .. CandFP(candidate), tokens = { "HELPFUL" }, cand = candidate }
    end
    local included, n
    if cfg.buffSpells then
        for index = 1, #cfg.buffSpells do
            local ident = cfg.buffSpells[index]
            included = included or {}
            if not included[ident] then
                included[ident] = true
                n = (n or 0) + 1
            end
            ExpandBuffFamily(included, ident)
        end
    end
    if not broad and cfg.buffFilters then
        for filterId in pairs(cfg.buffFilters) do
            local frame = mod.PAB_GetFilter and mod.PAB_GetFilter(filterId)
            if frame and frame.spells then
                for ident, enabled in pairs(frame.spells) do
                    if enabled and not mod.PAB_OtherClientSpell(frame, ident) then
                        included = included or {}
                        if not included[ident] then
                            included[ident] = true
                            n = (n or 0) + 1
                        end
                        ExpandBuffFamily(included, ident, frame.spells)
                    end
                end
            end
        end
    end
    -- Add-mode hide lane: drop hidden filters' spells from the union. Direct
    -- Extra Spells (s.buffSpells) win over the hide lane.
    if not broad and included and cfg.buffNegFilters then
        local direct
        if cfg.buffSpells then
            direct = {}
            for index = 1, #cfg.buffSpells do
                direct[cfg.buffSpells[index]] = true
                ExpandBuffFamily(direct, cfg.buffSpells[index])
            end
        end
        -- Hidden filters expand as families too, or one hidden id of a family
        -- would leak its siblings; direct Extra Spells still win.
        local hide = {}
        for filterId in pairs(cfg.buffNegFilters) do
            local frame = mod.PAB_GetFilter and mod.PAB_GetFilter(filterId)
            if frame and frame.spells then
                for ident, enabled in pairs(frame.spells) do
                    if enabled and not mod.PAB_OtherClientSpell(frame, ident) then
                        hide[ident] = true
                        ExpandBuffFamily(hide, ident, frame.spells)
                    end
                end
            end
        end
        for ident in pairs(hide) do
            if not (direct and direct[ident]) then
                included[ident] = nil
            end
        end
        if next(included) == nil then
            included = nil
        end
    end
    if included then
        local candidate = { includeSpellIDs = included }
        if dur then
            candidate.maxDuration = math.huge
        end
        if bl then
            local m = {}
            for ident in pairs(bl) do
                m[ident] = true
            end
            candidate.excludeSpellIDs = m
        end
        filterChain[#filterChain + 1] = { key = "pbsp|" .. CandFP(candidate), tokens = { "HELPFUL" }, cand = candidate }
    end
    return filterChain
end

-- Show-lane rows the player frame's Debuff Filter dropdown offers ([skey] = true,
-- from the same ns.PAB_ClassItems list the dropdown builds from). Match All combines
-- only these: a retired row's stale key would otherwise silently empty the display.
-- Static list, resolved once.
local matchVocab
local function MatchVocab()
    if matchVocab then
        return matchVocab
    end
    local itemList = mod.PAB_ClassItems and mod.PAB_ClassItems(false)
    if not itemList then
        return nil
    end
    local val = {}
    for index = 1, #itemList do
        if itemList[index].key then
            val[itemList[index].key] = true
        end
    end
    matchVocab = val
    return val
end

-- Match All for the player frame's debuffs (s.debuffFilterMatch == "all"; nil =
-- Match Any = the union BuildChain renders). Every Show pick ANDs into ONE group:
-- HARMFUL + every shown token + every shown candidate field, so a debuff renders at
-- most once and one group replaces N. The dispel types stay one OR'd axis (one
-- includeDispelTypes set; Dispels ANDed onto it changes nothing), and the Hide lane
-- is a plain veto on the same group (!TOKEN, false booleans, the Non-Player
-- opposite, excludeDispelTypes). Runs only with All Debuffs off and at least two
-- Show picks; otherwise returns nil and the caller builds today's chain unchanged.
-- Returns true plus the link, or true plus nil for picks that can never match
-- together (Non-Player with Cast By You, Cast By You with Hide From Any Player, a
-- dispel type with Hide Dispels): the chain is then empty and the options page
-- warns through ns.UF_DebuffMatchEmpty. Settings-apply time only.
local function PlayerDebuffMatch(cfg)
    if cfg.debuffFilterMatch ~= "all" or cfg.debuffShowAll ~= false then
        return nil
    end
    local vocab = MatchVocab()
    if not vocab then
        return nil
    end
    local negated = cfg.debuffNegClasses
    local pickCount = 0
    local tokenList = { "HARMFUL" }
    local candidate, hideBool = {}, nil
    local included, exc, typedShown, playerTok, clash, dispTok
    for index = 1, #TOKEN_CLASSES do
        local classFile = TOKEN_CLASSES[index]
        if not classFile.buffOnly then
            if vocab[classFile.skey] and cfg["debuff" .. classFile.skey] == true then
                pickCount = pickCount + 1
                tokenList[#tokenList + 1] = classFile.token
                if classFile.key == "castbyme" then
                    playerTok = true
                end
                if classFile.key == "dispellable" then
                    dispTok = true
                end
            elseif negated and negated[classFile.skey] == true then
                tokenList[#tokenList + 1] = classFile.neg or ("!" .. classFile.token)
            end
        end
    end
    for index = 1, #CANDIDATE_CLASSES do
        local classFile = CANDIDATE_CLASSES[index]
        local classColor = classFile.cand
        if classColor and not classFile.buffOnly then
            if vocab[classFile.skey] and cfg["debuff" .. classFile.skey] == true then
                pickCount = pickCount + 1
                if classFile.key == "dispeltyped" then
                    typedShown = classColor.includeDispelTypes
                elseif classColor.includeDispelTypes then
                    included = MergeDispelTypes(included, classColor.includeDispelTypes)
                else
                    for k, val in pairs(classColor) do
                        -- Two picks on one field (stale data only: the setters keep
                        -- Non-Player and From Any Player exclusive) never match.
                        if candidate[k] ~= nil and candidate[k] ~= val then
                            clash = true
                        end
                        candidate[k] = val
                    end
                end
            elseif negated and negated[classFile.skey] == true then
                if classColor.includeDispelTypes then
                    exc = MergeDispelTypes(exc, classColor.includeDispelTypes)
                else
                    hideBool = hideBool or {}
                    for k, val in pairs(classColor) do
                        if type(val) == "boolean" then
                            hideBool[k] = not val
                        end
                    end
                end
            end
        end
    end
    if pickCount < 2 then
        return nil
    end
    if hideBool then
        for k, val in pairs(hideBool) do
            if candidate[k] == nil then
                candidate[k] = val
            end
        end
    end
    -- Dispels alone = every type; ANDed onto shown types it changes nothing.
    if typedShown and not included then
        included = MergeDispelTypes(nil, typedShown)
    end
    if included then
        if exc then
            for T in pairs(exc) do
                included[T] = nil
            end
        end
        if next(included) == nil then
            clash = true
        end
        candidate.includeDispelTypes = included
    elseif exc then
        candidate.excludeDispelTypes = exc
        -- Dispellable By You passes only debuffs of a dispellable type, so
        -- hiding all five leaves it nothing.
        if dispTok and exc.Magic and exc.Curse and exc.Disease and exc.Poison and exc.Bleed then
            clash = true
        end
    end
    -- PLAYER (Cast By You: you or your pet) inside isFromPlayerOrPlayerPet = false
    -- (a shown Non-Player, or a hidden From Any Player) is always empty.
    if playerTok and candidate.isFromPlayerOrPlayerPet == false then
        clash = true
    end
    if clash then
        return true, nil
    end
    if next(candidate) == nil then
        candidate = nil
    end
    return true,
        {
            key = "pdand|" .. table.concat(tokenList, "") .. "|" .. CandFP(candidate),
            tokens = tokenList,
            cand = candidate,
        }
end

-- Options-page empty warning: true when Match All is active and its picks can never
-- match together (the same test the chain builder uses, so the two never disagree).
function mod.UF_DebuffMatchEmpty(cfg)
    if not cfg then
        return false
    end
    local enabled, itemLink = PlayerDebuffMatch(cfg)
    return enabled == true and itemLink == nil
end

-- Player-frame debuffs run the Player Aura Bars debuff model (identical
-- dropdown, identical engine behavior; see the player branch of the
-- Debuff Filter slot in CUI_UnitFrames_Options.lua). Two-lane keys:
-- s.debuff<SKey> booleans = the SHOW lane (add mode via the legacy
-- class-chain model, which now also honors the hide lane through
-- BuildChain); s.debuffNegClasses = the HIDE lane, subtracting in both
-- modes -- under All Debuffs (s.debuffShowAll, nil = on) hidden classes
-- become parked links whose negations / forward excludes remove them from
-- the catch-all, and pure boolean classes invert onto the catch-all's
-- candidates (the shared complementary-boolean mechanism).
-- Link keys embed their token sets plus the catch-all's candidate fingerprint, so
-- every payload shape declares its own variant through the existing sig/declare
-- machinery and stale variants park at 0. The sated/ always-hide excludes ride the
-- catch-all's DECLARED candidates and its fingerprint. Match All (add mode only)
-- replaces the class chain with its one "pdand|" link (PlayerDebuffMatch), or with
-- nothing when its picks can never match.
local function PlayerDebuffChain(cfg)
    EnsurePlayerAuraLanes(cfg)
    -- Has Duration checked with no Show pick is the timed catch-all (Player Aura
    -- Bars parity): the All Debuffs path below, narrowed by ChainFor.
    local durAlone = false
    if cfg.debuffShowAll == false and cfg.debuffHasDuration == true then
        durAlone = true
        for index = 1, #TOKEN_CLASSES do
            if ClassEnabled(TOKEN_CLASSES[index], false, cfg, "player") then
                durAlone = false
                break
            end
        end
        if durAlone then
            for index = 1, #CANDIDATE_CLASSES do
                if ClassEnabled(CANDIDATE_CLASSES[index], false, cfg, "player") then
                    durAlone = false
                    break
                end
            end
        end
    end
    if cfg.debuffShowAll == false and not durAlone then
        local matchOn, itemLink = PlayerDebuffMatch(cfg)
        if matchOn then
            return { itemLink }
        end
        return BuildChain("HARMFUL", false, cfg, "player")
    end
    local filterChain, negList = {}, {}
    local subPick, excludeDispelTypes, npOwned
    local function Checked(classFile)
        if classFile.buffOnly then
            return false
        end
        local negated = cfg.debuffNegClasses
        return negated ~= nil and negated[classFile.skey] == true
    end
    for index = 1, #TOKEN_CLASSES do
        local classFile = TOKEN_CLASSES[index]
        if Checked(classFile) then
            local tokenList = { "HARMFUL", classFile.token }
            for n = 1, #negList do
                tokenList[#tokenList + 1] = negList[n]
            end
            filterChain[#filterChain + 1] = {
                key = classFile.key .. "|" .. table.concat(tokenList, ""),
                tokens = tokenList,
                hidden = true,
            }
            negList[#negList + 1] = classFile.neg or ("!" .. classFile.token)
        end
    end
    for index = 1, #CANDIDATE_CLASSES do
        local classFile = CANDIDATE_CLASSES[index]
        local classColor = classFile.cand
        if Checked(classFile) and classColor then
            local forward = classColor.includeDispelTypes ~= nil or classColor.isFromPlayerOrPlayerPet ~= nil
            if forward then
                local tokenList = { "HARMFUL" }
                for n = 1, #negList do
                    tokenList[#tokenList + 1] = negList[n]
                end
                filterChain[#filterChain + 1] = {
                    key = classFile.key .. "|" .. table.concat(tokenList, ""),
                    tokens = tokenList,
                    cand = classColor,
                    hidden = true,
                }
                if classColor.includeDispelTypes then
                    excludeDispelTypes = classColor.includeDispelTypes
                end
                if classColor.isFromPlayerOrPlayerPet == false then
                    npOwned = true
                end
            else
                subPick = subPick or {}
                for k, val in pairs(classColor) do
                    if type(val) == "boolean" then
                        subPick[k] = not val
                    end
                end
            end
        end
    end
    local ex = {}
    for ident in pairs(ALWAYS_HIDE_DEBUFFS) do
        ex[ident] = true
    end
    if cfg.debuffHideExhaustion ~= false then
        for ident in pairs(SATED_DEBUFFS) do
            ex[ident] = true
        end
    end
    local candidate = { excludeSpellIDs = ex }
    if subPick then
        for k, val in pairs(subPick) do
            candidate[k] = val
        end
    end
    if excludeDispelTypes then
        candidate.excludeDispelTypes = excludeDispelTypes
    end
    if npOwned then
        candidate.isFromPlayerOrPlayerPet = true
    end
    local allTokens = { "HARMFUL" }
    for n = 1, #negList do
        allTokens[#allTokens + 1] = negList[n]
    end
    filterChain[#filterChain + 1] = {
        key = "pdall|" .. table.concat(allTokens, "") .. "|" .. CandFP(candidate),
        tokens = allTokens,
        cand = candidate,
    }
    return filterChain
end

-- An element's chain. Has Duration (s.debuffHasDuration on every unit,
-- s.buffDurOnly on target/focus/boss -- its own key: the player's broad-mode
-- s.buffHasDuration, run inside PlayerBuffChain, can already sit copied on
-- those units) is an AND-modifier on every link that shows content:
-- Blizzard's candidate maxDuration check, which drops an aura when
-- `duration > maxDuration or duration == 0`, so math.huge drops only the
-- permanent ones. The container evaluates it and it is not identity-gated,
-- so it holds on any unit, friendly or hostile, secret or not. Hide-lane links
-- (they render nothing) and Tracked Auras include links (explicit always-show
-- spells) keep their payload. A narrowed link's key gains "|dur", so the
-- variant declares fresh and the plain one parks at 0.
local function ChainFor(unitToken, baseSet, cfg)
    local buffSide = baseSet == "HELPFUL"
    local filterChain
    if unitToken == "player" and buffSide then
        return PlayerBuffChain(cfg)
    elseif unitToken == "player" then
        filterChain = PlayerDebuffChain(cfg)
    else
        filterChain = BuildChain(baseSet, buffSide, cfg, unitToken)
    end
    local dur
    if buffSide then
        dur = cfg.buffDurOnly == true
    else
        dur = cfg.debuffHasDuration == true
    end
    if not dur then
        return filterChain
    end
    -- Non-player buffs with nothing shown or hidden run the plain show-all
    -- group (ApplyGroupConfig); narrowed, it becomes an explicit link.
    if buffSide and #filterChain == 0 then
        filterChain[1] = { key = "all", tokens = { baseSet } }
    end
    -- Show All's catch-all is what shows the Tracked Auras there (no include
    -- links); narrowed, they get one include link of their own, from any
    -- caster as the catch-all showed them, at any duration.
    if not buffSide and unitToken ~= "player" and DebuffFilterMode(cfg) == "all" and HasActiveIncludes(cfg) then
        local m = {}
        for ident, val in pairs(cfg.debuffInclude) do
            if val then
                m[ident] = true
            end
        end
        filterChain[#filterChain + 1] = {
            key = "incall|" .. CandFP({ includeSpellIDs = m }),
            tokens = { "HARMFUL" },
            cand = { includeSpellIDs = m, excludeSpellIDs = {} },
            inc = true,
        }
    end
    for index = 1, #filterChain do
        local c = filterChain[index]
        if not (c.hidden or c.inc) then
            local candidate = { maxDuration = math.huge }
            if c.cand then
                for k, val in pairs(c.cand) do
                    candidate[k] = val
                end
                if candidate.maxDuration == nil then
                    candidate.maxDuration = math.huge
                end
            end
            filterChain[index] = {
                key = c.key .. "|dur",
                tokens = c.tokens,
                cand = candidate,
                glow = c.glow,
                mine = c.mine,
                important = c.important,
            }
        end
    end
    return filterChain
end

local function ChainSignature(filterChain)
    local sig = {}
    for index = 1, #filterChain do
        sig[index] = filterChain[index].key
    end
    return table.concat(sig, ",")
end

-- [unitKey] = { frame, buffs, debuffs, dispel, sig = {buffs=,debuffs=} }.
-- Entries carry `building = true` while the deferred stepper is still
-- constructing them; every reload/refresh path skips building entries (the
-- stepper's final stage clears the flag and runs the first real reload).
local registry = {}

-- Units whose build job is queued but has not run its first atom (the entry is
-- born there): a repeat request in between queues nothing more (the pet's lazy
-- build is asked on every reload pass).
local buildQueued = {}

-- The pet swap watcher (UNIT_PET), held by the pet's reload; its Sync is
-- defined below RefreshUnit.
local PetSwap = {}

-- The PLAYER_LOGIN shell stash lived here until 68914 made container
-- creation combat-legal (/cuit3 field PASS): builds now birth their own
-- shells inline wherever the job runs, combat included.

-- The pet's aura settings: a read-only VIEW over two live tables, nothing is
-- copied into the profile. Placement, size (Cropped Icons included: it sets
-- the icon height) and the Location switches are the pet's own; the aura look
-- comes from the frame its Copy Auras From names (ns.UF_MiniAuraTables); every
-- other key reads nil, so the pet keeps the runtime defaults for content
-- (every buff and debuff, Sated hidden, no Tracked Auras, no Purgeable Buff
-- Glow, no merge with the debuffs, no cast bar reserve) whatever either table
-- holds. Values per key:
--   1 = the pet's own key, 2 = the source frame's key, 3 = the source frame's
--   key unless that frame is the player (the player frame never shows it),
--   4 = the source frame's key only when that frame is the player (only the
--   player frame shows it).
-- A key the aura code newly reads for every unit lands here too, or the pet
-- reads nil for it.
local PET_AURA_KEYS = {
    showBuffs = 1,
    buffAnchor = 1,
    debuffAnchor = 1,
    buffSize = 1,
    debuffSize = 1,
    buffGrowth = 1,
    debuffGrowth = 1,
    maxBuffs = 1,
    maxDebuffs = 1,
    buffMaxPerRow = 1,
    debuffMaxPerRow = 1,
    buffOffsetX = 1,
    buffOffsetY = 1,
    debuffOffsetX = 1,
    debuffOffsetY = 1,
    buffSpacingX = 1,
    buffSpacingY = 1,
    debuffSpacingX = 1,
    debuffSpacingY = 1,
    buffCropIcons = 1,
    debuffCropIcons = 1,
    -- Show Tooltip For > Main Frames Auras writes it on the pet too.
    showAuraTooltips = 1,
    buffIconZoom = 2,
    debuffIconZoom = 2,
    auraBorderR = 2,
    auraBorderG = 2,
    auraBorderB = 2,
    auraBorderA = 2,
    auraBorderSize = 2,
    auraBorderSizePx = 2,
    auraBorderTexture = 2,
    auraBorderTextureOffset = 2,
    auraBorderTextureOffsetY = 2,
    auraBorderTextureShiftX = 2,
    auraBorderTextureShiftY = 2,
    auraBorderBehind = 2,
    auraBorderBehindUnitFrame = 2,
    auraBorderDispelTextured = 2,
    debuffDispelBorder = 2,
    buffDispelBorder = 3,
    buffShowCooldownText = 2,
    buffCooldownTextSize = 2,
    buffCooldownTextPrecision = 2,
    buffCooldownTextColor = 2,
    buffCooldownTextOffsetX = 2,
    buffCooldownTextOffsetY = 2,
    buffStackTextSize = 2,
    buffStackTextColor = 2,
    buffStackTextPosition = 2,
    buffStackTextOffsetX = 2,
    buffStackTextOffsetY = 2,
    debuffShowCooldownText = 2,
    debuffCooldownTextSize = 2,
    debuffCooldownTextPrecision = 2,
    debuffCooldownTextColor = 2,
    debuffCooldownTextOffsetX = 2,
    debuffCooldownTextOffsetY = 2,
    debuffStackTextSize = 2,
    debuffStackTextColor = 2,
    debuffStackTextPosition = 2,
    debuffStackTextOffsetX = 2,
    debuffStackTextOffsetY = 2,
    debuffDispelUsePalette = 4,
}
local petView = { own = nil, src = nil, player = false }
local PET_VIEW = setmetatable({}, {
    __index = function(_, key)
        local c = PET_AURA_KEYS[key]
        if c == 1 then
            return petView.own[key]
        end
        if c == 2 or (c == 3 and not petView.player) or (c == 4 and petView.player) then
            return petView.src[key]
        end
        return nil
    end,
    -- Read-only: the runtime writes only the player's table (EnsurePlayerAuraLanes).
    __newindex = function() end,
})
-- Points the view at the current tables (a profile switch, import or layer
-- paint can replace either one) and returns it.
local function PetAuraSettings()
    local own, src, srcKey = mod.UF_MiniAuraTables("pet")
    if not (own and src) then
        return nil
    end
    petView.own, petView.src, petView.player = own, src, srcKey == "player"
    return PET_VIEW
end

local function SettingsFor(unitToken)
    if unitToken == "pet" then
        return PetAuraSettings()
    end
    if mod.UF_GetSettings then
        return mod.UF_GetSettings(unitToken)
    end
    local saved = mod.db
    if not saved then
        return nil
    end
    local auraKey = unitToken:match("^boss%d+$") and "boss" or unitToken
    return saved.profile[auraKey]
end
-- What the containers read for a unit (the pet's view, another unit's own
-- table): the pet's lazy build and the options preview read the same.
mod.UF_AuraSettings = SettingsFor

-- Anchor/growth tables: initial anchor, frame point + offset direction, and
-- the growth pair per anchor position.
local ANCHOR_IA = {
    topleft = "BOTTOMLEFT",
    topright = "BOTTOMRIGHT",
    bottomleft = "TOPLEFT",
    bottomright = "TOPRIGHT",
    left = "RIGHT",
    right = "LEFT",
}
local ANCHOR_FP = {
    topleft = { "TOPLEFT", 0, 1 },
    topright = { "TOPRIGHT", 0, 1 },
    bottomleft = { "BOTTOMLEFT", 0, -1 },
    bottomright = { "BOTTOMRIGHT", 0, -1 },
    left = { "LEFT", -1, 0 },
    right = { "RIGHT", 1, 0 },
}
local AUTO_GROWTH = {
    topleft = { "RIGHT", "UP" },
    topright = { "LEFT", "UP" },
    bottomleft = { "RIGHT", "DOWN" },
    bottomright = { "LEFT", "DOWN" },
    left = { "LEFT", "DOWN" },
    right = { "RIGHT", "DOWN" },
}
local EXPLICIT_GROWTH = {
    right = { "RIGHT", "UP" },
    left = { "LEFT", "UP" },
    up = { "RIGHT", "UP" },
    down = { "RIGHT", "DOWN" },
}

local function ResolveLayout(anchorFrame, growth)
    anchorFrame = anchorFrame or "topleft"
    local ia = ANCHOR_IA[anchorFrame] or "BOTTOMLEFT"
    local filterPass = ANCHOR_FP[anchorFrame] or ANCHOR_FP.topleft
    local g
    if growth and growth ~= "auto" then
        g = EXPLICIT_GROWTH[growth]
    end
    g = g or AUTO_GROWTH[anchorFrame] or AUTO_GROWTH.topleft
    return ia, filterPass[1], filterPass[2], filterPass[3], g[1], g[2]
end

-- Column cap from the growth SETTING string: a per-row cap below maxCount
-- wins; explicit vertical growth = one column; anything else = Max Per Row,
-- or maxCount while it is unset (what its slider shows). Never unlimited:
-- Max Count caps each group, not the container, so several active groups
-- (filters, the Purgeable Glow split, Max Important) would otherwise
-- stretch one row past it.
-- rowMax = Max Count; maxCount may be Max Important instead (ApplyGroupConfig).
-- Second return: true when the cap is a single row (not a grid or a column).
local function ResolveColumns(growth, maxCount, perRow, rowMax)
    if perRow and perRow >= 1 and perRow < maxCount then
        return perRow, false
    end
    if growth == "up" or growth == "down" then
        return 1, false
    end
    if perRow and perRow >= 1 then
        return perRow, true
    end
    return rowMax, true
end

local FLOWDIR = { RIGHT = nil, LEFT = nil, UP = nil, DOWN = nil } -- filled on first use
local function FlowDir(token)
    if FLOWDIR.RIGHT == nil then
        FLOWDIR.RIGHT = AnchorUtil.FlowDirection.Right
        FLOWDIR.LEFT = AnchorUtil.FlowDirection.Left
        FLOWDIR.UP = AnchorUtil.FlowDirection.Up
        FLOWDIR.DOWN = AnchorUtil.FlowDirection.Down
    end
    return FLOWDIR[token]
end

-- zoom (optional) overrides the default AURA_ZOOM crop; per-unit/per-category
-- Icon Zoom values flow in here, defaulting to AURA_ZOOM so unset = unchanged.
local function CropCoords(cropped, wid, hgt, zoom)
    local zoomVal = zoom or AURA_ZOOM
    if cropped and wid and hgt and wid > 0 then
        local uSpan = 1 - 2 * zoomVal
        local vSpan = uSpan * (hgt / wid)
        local v0 = 0.5 - vSpan / 2
        return { zoomVal, 1 - zoomVal, v0, 1 - v0 }
    end
    return { zoomVal, 1 - zoomVal, zoomVal, 1 - zoomVal }
end

local STACK_POINTS = {
    bottomright = { "BOTTOMRIGHT", -1 },
    bottomleft = { "BOTTOMLEFT", 1 },
    topright = { "TOPRIGHT", -1 },
    topleft = { "TOPLEFT", 1 },
    center = { "CENTER", 0 },
}

local function CK(color)
    if not color then
        return "-"
    end
    return string.format("%.3f,%.3f,%.3f", color.r or color[1] or 0, color.g or color[2] or 0, color.b or color[3] or 0)
end

-- Module text pass: fonts through the shared icon-text pipeline (outline slug
-- rules live there), duration text centered like cooldown countdown text.
-- Restyles hit every registered button, so SetFont is change-guarded (it
-- costs real time even with identical values; font key = path|size, so an
-- outline-only module font change slips until a size touch -- accepted,
-- same as the RF pass). The duration string is ALWAYS fonted, hidden or
-- not: the engine SetText()s every registered duration string on display
-- updates, and an unfonted FontString hard-errors inside that engine call
-- (visibility is handled by AuraKit via SetShown). Text color is likewise
-- change-guarded via CK() fingerprints (d.ufDurColor/d.ufStackColor) --
-- SetTextColor costs real time too, same reasoning as the font guard above.
local function ApplyUFText(btnFrame, skinData, look)
    if look.auraBorderAboveEffects or skinData.ufBorderAboveEffects then
        -- Only owned art/text hosts move; the restricted button is untouched.
        -- Stock styles hide the border instead of restoring its level.
        local level = skinData.borderHost:GetFrameLevel()
        if look.auraBorderAboveEffects then
            skinData.ufBorderBaseLevel = level
            level = math.max(level, (skinData.buttonFrameLevel or 1) + 20)
            skinData.borderHost:SetFrameLevel(level)
        else
            if not look.border and skinData.ufBorderBaseLevel then
                level = skinData.ufBorderBaseLevel
                skinData.borderHost:SetFrameLevel(level)
            end
            skinData.ufBorderBaseLevel = nil
        end
        skinData.dispelHolder:SetFrameLevel(level + 4)
        skinData.stackCarrier:SetFrameLevel(level + 5)
        skinData.akDispelLvl = level
        skinData.ufBorderAboveEffects = look.auraBorderAboveEffects or nil
    end
    local filePath = look.fontPath or FALLBACK_FONT
    if skinData.duration then
        local fontKey = filePath .. "|" .. (look.cdTextSize or 10)
        if skinData.ufDurFont ~= fontKey then
            skinData.ufDurFont = fontKey
            CludesUI.ApplyIconTextFont(skinData.duration, filePath, look.cdTextSize or 10, "unitFrames")
        end
        local color = look.cdTextColor
        local cKey = CK(color)
        if skinData.ufDurColor ~= cKey then
            skinData.ufDurColor = cKey
            skinData.duration:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
        end
        -- Anchor change-guarded (stamp AFTER the calls): SetPoint with the
        -- button as the relative frame is policed by the 12.1 button access
        -- restriction while auras are secret; unchanged offsets must make
        -- zero button-involving calls so restyles stay live in-instance.
        local aKey = (look.cdOffX or 0) .. "|" .. (look.cdOffY or 0)
        if skinData.ufDurAnchor ~= aKey then
            skinData.duration:ClearAllPoints()
            skinData.duration:SetPoint("CENTER", btnFrame, "CENTER", look.cdOffX or 0, look.cdOffY or 0)
            skinData.ufDurAnchor = aKey
        end
        -- Duration formatter options are registered once when an AuraKit button
        -- is created. Re-register when the user changes the precision threshold;
        -- a normal style restyle alone does not change the engine binding.
        -- SAME stamp key + shape as MakeInitializer's creation write ("b" --
        -- UF styles never set durationShowSeconds -- plus the threshold), so
        -- untouched configs compare equal to the creation stamp and never
        -- rebind: zero cost while the feature is off.
        local wantFmt = "b" .. tostring(look.durationPrecisionThreshold or 0)
        if skinData.durationFmtS ~= wantFmt then
            local AK = CludesUI.AuraKit
            local options =
                AK.BuildDurationTextOpts(AK.GetDurationFormatter(nil, look.durationPrecisionThreshold))
            local success = AK.SetDurationTextSafe(btnFrame, skinData.duration, options)
            if success then
                skinData.durationFmtS = wantFmt
            end
        end
    end
    if skinData.stack then
        local fontKey = filePath .. "|" .. (look.stackSize or 14)
        if skinData.ufStackFont ~= fontKey then
            skinData.ufStackFont = fontKey
            CludesUI.ApplyIconTextFont(skinData.stack, filePath, look.stackSize or 14, "unitFrames")
        end
        local color = look.stackColor
        local cKey = CK(color)
        if skinData.ufStackColor ~= cKey then
            skinData.ufStackColor = cKey
            skinData.stack:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
        end
        local sp = STACK_POINTS[look.stackPos or "bottomright"] or STACK_POINTS.bottomright
        local sKey = sp[1] .. "|" .. (sp[2] + (look.stackOffX or 0)) .. "|" .. (look.stackOffY or 0)
        if skinData.ufStackAnchor ~= sKey then
            skinData.stack:ClearAllPoints()
            skinData.stack:SetPoint(sp[1], btnFrame, sp[1], sp[2] + (look.stackOffX or 0), look.stackOffY or 0)
            skinData.ufStackAnchor = sKey
        end
    end
end

local function StyleKey(unitToken, baseSet)
    return "uf:" .. unitToken .. ":" .. baseSet
end

-- Settings fingerprints (same discipline as the RF containers file): every
-- engine setter is a dirty mark that costs real engine work even when the
-- value is unchanged, and a restyle touches every pre-created button of the
-- style (10-button engine batches per group add up fast). Reload paths
-- fingerprint what each pass reads and skip the work whose inputs did not
-- change. Numbers round to 2 decimals: scaled values carry float noise.
local ufFP = {}

local function FP(...)
    local n = select("#", ...)
    local t = {}
    for index = 1, n do
        local val = select(index, ...)
        if type(val) == "number" then
            t[index] = string.format("%.2f", val)
        else
            t[index] = tostring(val)
        end
    end
    return table.concat(t, "|")
end

-- Fingerprint of a BUILT style table (BuildStyle is a pure function of the settings, so
-- hashing its scalar output covers every input, including the boss-simple sizing and
-- scale). Constant cooldown/cancel fields are omitted; every user-configurable border
-- scalar must participate so layer-only edits schedule an immediate AuraKit restyle.
local function StyleTableFP(state, font)
    local tc = state.texCoord
    local b = state.border
    return FP(
        font,
        state.width,
        state.height,
        tc[1],
        tc[2],
        tc[3],
        tc[4],
        state.hideDurationText,
        state.durationPrecisionThreshold,
        state.cdTextSize,
        CK(state.cdTextColor),
        state.cdOffX,
        state.cdOffY,
        state.stackSize,
        CK(state.stackColor),
        state.stackPos,
        state.stackOffX,
        state.stackOffY,
        b and b.texture,
        b and b.size,
        b and b.edgePx,
        b and b[1],
        b and b[2],
        b and b[3],
        b and b[4],
        b and b.offsetX,
        b and b.offsetY,
        b and b.shiftX,
        b and b.shiftY,
        b and b.behind,
        b and b.behindUnitFrame,
        b and b.unitFrameLevel,
        state.auraBorderAboveEffects,
        state.noTooltips,
        state.blizzBorder,
        state.dispelBorder,
        -- Textured Dispel Ring (the ring's art key) and Use Dispel Colors (the
        -- palette fingerprint the colour map was built from).
        state.dispelBorderTexture,
        state.dispelColorFP
    )
end

-- Declares one chain group and records it in the element's declared-set
-- registry (one group per chain key; containers are never swapped -- the
-- ever-used set accumulates, inactive groups sit at count 0, and the config
-- pass re-sets each active group's filter string). Used at creation and by
-- the additive reload path (AddAuraGroup on an existing container is
-- combat-legal -- probe T1/T1b).
local function DeclareElementGroup(boxHolder, declared, styleKey, auraKey, tokenList, candidate)
    -- A declaration cut short after the engine registered the group (the
    -- client watchdog) left it unrecorded here: record it rather than add it
    -- again (a duplicate key asserts). The cut can also skip storing its
    -- layout, which the config pass sets on every active group.
    if boxHolder:HasAuraGroup(auraKey) then
        declared[auraKey] = { cand = candidate or false }
        return
    end
    AK.AddGroupToContainer(boxHolder, {
        key = auraKey,
        filter = tokenList,
        maxFrameCount = 0,
        style = styleKey,
        -- Candidates ride the declaration too: chain keys that embed a candidate
        -- fingerprint bring a changed payload here as a fresh variant, and the
        -- config pass live-sets candidates on top (the shared debuff excludes).
        candidateFilters = candidate or nil,
    })
    declared[auraKey] = { cand = candidate or false }
end

-- Explicit either/or (never `cond and a or b`: a falsy setting must not fall
-- through to the other element's key).
local function Pick(buffSide, a, b)
    if buffSide then
        return a
    end
    return b
end

-- Boss "simple" side display: returns whether it is on and which side.
local function BossSimple(unitToken, baseSet, cfg)
    if not unitToken:match("^boss") then
        return false, "none"
    end
    local modeName
    if baseSet == "HELPFUL" then
        modeName = mod.GetBossSimpleBuffMode and mod.GetBossSimpleBuffMode(cfg) or "none"
    else
        modeName = mod.GetBossSimpleDebuffMode and mod.GetBossSimpleDebuffMode(cfg) or "none"
    end
    return modeName ~= "none", modeName
end

-- Whether one element of a unit shows: buffs unless Buff Display is None,
-- or while a boss Simple Buff Display or Anchor Buffs with Debuffs renders
-- them; debuffs while Debuff Display is not None or a boss Simple Debuff
-- Display renders them. The one test the build stepper, the reload's group
-- declaration and the config pass share: an element that is off declares no
-- groups (each is an eager engine batch) until a reload sees it on.
local function SideOn(unitToken, baseSet, cfg)
    if baseSet == "HELPFUL" then
        if cfg.showBuffs ~= false or BossSimple(unitToken, baseSet, cfg) then
            return true
        end
        return cfg.debuffAnchorBuffs == true
            and not unitToken:match("^boss")
            and (cfg.debuffAnchor or "none") ~= "none"
    end
    return (cfg.debuffAnchor or "none") ~= "none" or (BossSimple(unitToken, baseSet, cfg))
end
mod.UF_AuraSideOn = SideOn

-- Player weapon enchant cells (AnchorContainer declares them): they flow
-- ahead of the buffs in the same row, so a capped row widens by the cells
-- showing (only duration-bearing ones, hidePermanent). Equipment state, not
-- aura data: no secret values, in restricted combat either.
local WeaponCells = {}

-- On = the buff row is in a broad mode, which declares the cells.
function WeaponCells.On(unitToken, baseSet, cfg)
    return unitToken == "player"
        and baseSet == "HELPFUL"
        and SideOn(unitToken, baseSet, cfg)
        and (cfg.buffShowAll ~= false or cfg.buffHasDuration == true)
end

-- Shown = the cells render on the player buff row: the engine cannot
-- undeclare them, so once declared (AnchorContainer stamps the container)
-- they stay after a switch out of the broad modes until the next /reload.
function WeaponCells.Shown(unitToken, baseSet, cfg)
    if WeaponCells.On(unitToken, baseSet, cfg) then
        return true
    end
    local record = registry.player
    return unitToken == "player"
        and baseSet == "HELPFUL"
        and WeaponCells.declared ~= nil
        and record ~= nil
        and record.buffs == WeaponCells.declared
        and SideOn(unitToken, baseSet, cfg)
end

-- Player Aura Bars' count (all three slots: AK declares them all here).
function WeaponCells.Count()
    return mod.PAB_ActiveEnchantCount and mod.PAB_ActiveEnchantCount(3) or 0
end

-- Registered only while the cells are on; the count is change-guarded
-- (WEAPON_ENCHANT_CHANGED also fires for charge ticks). The count rides the
-- player buff fingerprint, so the reload re-runs only that config pass.
-- n = the current count when the caller already has it.
function WeaponCells.Sync(wanted, n)
    local frame = WeaponCells.frame
    if wanted then
        if not frame then
            frame = CreateFrame("Frame")
            frame:SetScript("OnEvent", function()
                local record = registry.player
                -- Player frame no longer ours (source switched away without a
                -- /reload): nothing to widen, stop listening.
                if
                    not (record and record.frame)
                    or (mod.GetUnitFrameSource and mod.GetUnitFrameSource("player") ~= "cui")
                then
                    WeaponCells.Sync(false)
                    return
                end
                local n = WeaponCells.Count()
                if n == WeaponCells.last then
                    return
                end
                WeaponCells.last = n
                if mod.UF_ReloadAuraContainers then
                    mod.UF_ReloadAuraContainers(record.frame, "player")
                end
            end)
            WeaponCells.frame = frame
        end
        WeaponCells.last = n or WeaponCells.Count()
        frame:RegisterEvent("WEAPON_ENCHANT_CHANGED")
        frame:RegisterEvent("WEAPON_SLOT_CHANGED")
    elseif frame then
        frame:UnregisterAllEvents()
        WeaponCells.last = nil
    end
end

-- Element pixel size; boss simple mode matches the frame's bar-stack height.
local function ElementSize(unitToken, baseSet, cfg)
    local buffSide = (baseSet == "HELPFUL")
    local size = Pick(buffSide, cfg.buffSize, cfg.debuffSize) or 22
    local isSimple = BossSimple(unitToken, baseSet, cfg)
    local Pix = CludesUI.PP
    local m = Pix.mult or 1
    if isSimple then
        local powerPos = cfg.powerPosition or "below"
        local powerH = 0
        if powerPos == "below" or powerPos == "above" then
            powerH = cfg.powerHeight or 0
        end
        size = Pix.Scale((cfg.healthHeight or 0) + powerH)
    elseif m ~= 1 then
        -- Whole physical pixels (nearest, as Player Aura Bars): AuraKit's border
        -- strips skip pixel snapping while the icon texture snaps, so a
        -- fractional far edge leaves the border off the icon at a
        -- non-pixel-perfect scale.
        size = Pix.FromPixels(Pix.ToPixels(size))
    end
    local cropped = Pick(buffSide, cfg.buffCropIcons, cfg.debuffCropIcons)
    local hgt = size
    if cropped then
        hgt = math.floor(size / m * AURA_CROP_HEIGHT + 0.5) * m
    end
    return size, hgt, cropped
end

-- Use Dispel Colors (player debuffs): the Dispel Colors palette as the engine's
-- customDispelColorMap plus its fingerprint. Assigned below the dispel slot table
-- it reads.
local PlayerDispelPalette

local function BuildStyle(unitToken, baseSet, cfg, unitFrame)
    local buffSide = (baseSet == "HELPFUL")
    local size, hgt, cropped = ElementSize(unitToken, baseSet, cfg)
    local p = Pick(buffSide, "buff", "debuff")

    -- Boss simple side displays read their own cooldown-text keys.
    local isSimple = BossSimple(unitToken, baseSet, cfg)
    local showCdKey, cdSizeKey = p .. "ShowCooldownText", p .. "CooldownTextSize"
    local cdSizeDefault = 10
    if isSimple then
        showCdKey = "simple" .. p:gsub("^%l", string.upper) .. "ShowCooldownText"
        cdSizeKey = "simple" .. p:gsub("^%l", string.upper) .. "CooldownTextSize"
        cdSizeDefault = 14
    end

    -- Blizzard Style: buffs borderless like the stock frames, debuffs on the
    -- engine-stamped stock dispel border (AuraKit blizzBorder); no CUI ring.
    local blizz = mod.UF_Blizz and mod.UF_Blizz() or false
    local border, dispel, blizzBorder, dispelTex, dcMap, dcFP
    if blizz then
        if not buffSide then
            dispel = true
            blizzBorder = true
        end
    else
        border = {
            cfg.auraBorderR or 0,
            cfg.auraBorderG or 0,
            cfg.auraBorderB or 0,
            cfg.auraBorderA or 1,
            size = cfg.auraBorderSize or 1,
            texture = cfg.auraBorderTexture or "solid",
            -- Exact size (nil = the legacy step path); a pure function of the three
            -- keys, so the built-style fingerprint above covers it.
            edgePx = CludesUI.BorderPx(
                cfg.auraBorderSizePx,
                cfg.auraBorderSize or 1,
                cfg.auraBorderTexture or "solid"
            ),
            offsetX = cfg.auraBorderTextureOffset,
            offsetY = cfg.auraBorderTextureOffsetY,
            shiftX = cfg.auraBorderTextureShiftX,
            shiftY = cfg.auraBorderTextureShiftY,
            behind = cfg.auraBorderBehind,
            behindUnitFrame = cfg.auraBorderBehindUnitFrame,
            unitFrameLevel = unitFrame and unitFrame:GetFrameLevel() or 1,
        }
        -- Dispel-type border recolor (per-unit debuffDispelBorder): the engine
        -- shows the ring only on typed (dispellable) debuffs and tints it per
        -- dispel type, in its own colours or, with the player's Use Dispel
        -- Colors, in the Dispel Colors palette handed over as
        -- customDispelColorMap (below). No aura data is read either way.
        dispel = (not buffSide and cfg.debuffDispelBorder) and true or nil
        -- Buffs on target/focus/boss (opt-in): the same engine ring, tinted by
        -- the buff's dispel type (Magic blue). Untyped buffs get no ring.
        if buffSide and unitToken ~= "player" and cfg.buffDispelBorder == true then
            dispel = true
        end
        -- Textured Dispel Ring (per-unit, player/target/focus): AuraKit draws the ring
        -- in the aura border's own art on the aura border's geometry (style.border)
        -- instead of flat strips, and keeps the strips by itself for a size-0 border.
        if
            dispel
            and cfg.auraBorderDispelTextured == true
            and border.texture ~= "solid"
            and border.texture ~= ""
        then
            dispelTex = border.texture
        end
        -- Use Dispel Colors: the player's rings, and the pet's while it copies
        -- the player frame's aura look (its view hands the key on only then).
        if
            dispel
            and not buffSide
            and (unitToken == "player" or unitToken == "pet")
            and cfg.debuffDispelUsePalette == true
        then
            dcMap, dcFP = PlayerDispelPalette()
        end
    end

    return {
        width = size,
        height = hgt,
        -- Blizzard Style: zoom 0 -- the stock frames draw the whole icon, and
        -- the icon art's own dark edge is the border a stock buff shows.
        texCoord = CropCoords(
            cropped,
            size,
            hgt,
            blizz and 0 or Pick(buffSide, cfg.buffIconZoom, cfg.debuffIconZoom)
        ),
        border = border,
        blizzBorder = blizzBorder,
        -- Weapon enchant buttons mirror this style: the stock purple ring.
        blizzEnchant = blizz or nil,
        cooldownReverse = true,
        cooldownDrawEdge = false,
        noDefaultFonts = true,
        hideDurationText = not cfg[showCdKey],
        durationPrecisionThreshold = tonumber(cfg[p .. "CooldownTextPrecision"]),
        cdTextSize = cfg[cdSizeKey] or cdSizeDefault,
        cdTextColor = cfg[p .. "CooldownTextColor"],
        cdOffX = cfg[p .. "CooldownTextOffsetX"] or 0,
        cdOffY = cfg[p .. "CooldownTextOffsetY"] or 0,
        stackSize = cfg[p .. "StackTextSize"] or 14,
        stackColor = cfg[p .. "StackTextColor"],
        stackPos = cfg[p .. "StackTextPosition"],
        stackOffX = cfg[p .. "StackTextOffsetX"] or 0,
        stackOffY = cfg[p .. "StackTextOffsetY"] or 0,
        cancelButtons = (unitToken == "player" and buffSide) and "RightButtonUp" or nil,
        -- Show Tooltip For -> Buffs & Debuffs (per-unit, default on). Motion
        -- goes off with the tooltips; clicks (player buff cancel) unaffected.
        noTooltips = (cfg.showAuraTooltips == false) or nil,
        dispelBorder = dispel,
        dispelHelpful = (buffSide and dispel) or nil,
        dispelBorderTexture = dispelTex,
        dispelColorMap = dcMap,
        dispelColorFP = dcFP,
        -- Resolved once per (fingerprint-gated) style rebuild instead of on
        -- every ApplyUFText call -- GetFontPath's result only changes when
        -- font settings change, which already forces a fresh style table.
        fontPath = (CludesUI.GetFontPath("unitFrames")) or FALLBACK_FONT,
        auraBorderAboveEffects = cfg.auraBorderAboveEffects == true
                and unitToken:match("^boss")
                and mod.UF_BossAuraBorderAboveEffects(cfg)
            or nil,
        applyExtra = ApplyUFText,
    }
end

-- Purgeable Buff Glow style: the buff element's style plus the glow, on its
-- own key so only the purgeable groups wear it. Every button of those groups
-- is purgeable by construction, so the glow rides the button's own
-- visibility -- no per-aura read, identical in and out of restricted content.
function PurgeGlow.StyleKey(unitToken)
    return StyleKey(unitToken, "HELPFUL") .. ":glow"
end

-- The glow families the menu offers: Pixel, the flipbooks and Blizzard Border.
PurgeGlow.NEED = { ants = true, flip = true, stealable = true }

function PurgeGlow.Extra(btnFrame, skinData, look)
    ApplyUFText(btnFrame, skinData, look)
    if not look.purgeSpec then
        return
    end
    local Glows = CludesUI.Glows
    local owner = skinData.ufPurgeGlow
    if not owner then
        -- The first call runs inside initializeFrame, the button's one legal
        -- window for parenting a new frame to it. Just below the text carrier.
        owner = CreateFrame("Frame", nil, btnFrame)
        owner:SetAllPoints(btnFrame)
        if look.auraBorderAboveEffects then
            owner:SetFrameLevel(skinData.cooldown:GetFrameLevel() + 5)
        elseif skinData.stackCarrier then
            owner:SetFrameLevel(skinData.stackCarrier:GetFrameLevel() - 1)
        else
            owner:SetFrameLevel(btnFrame:GetFrameLevel() + 1)
        end
        owner:EnableMouse(false)
        skinData.ufPurgeGlow = owner
        Glows.PrewarmEngineHost(owner, look.width, look.height, PurgeGlow.NEED)
    end
    -- Bound once: the button runs the glow's animations itself (12.1.5),
    -- Blizzard playing them while it shows a buff and stopping them when it
    -- has none. false where the button cannot (no API).
    if skinData.ufPurgeBound == nil then
        skinData.ufPurgeBound = Glows.BindEngineHost(owner, btnFrame, skinData)
    end
    -- C-side animations only (engine-button subtree); Blizzard Border
    -- (static stealable art) renders through the same call. Bound, every
    -- button carries the glow. Unbound (no API), the animations play while
    -- hidden too, so only buttons the group can ever show run one.
    if skinData.ufPurgeBound or CludesUI.AuraKit.ButtonCanShow(btnFrame) then
        Glows.StartSpecGlow(owner, look.purgeSpec, look.width, look.height, "engine")
    elseif owner._cuiGlowActive then
        Glows.StopGlow(owner)
    end
end

-- Unset color = "default" mode: the suite's default look (gold).
function PurgeGlow.Spec(cfg)
    local color = cfg.buffPurgeGlowColor
    local modeName = cfg.buffPurgeGlowColorMode or (color and "custom" or "default")
    local bgc = cfg.buffPurgeGlowBackgroundColor
    local specInfo = {
        style = cfg.buffPurgeGlow,
        lines = cfg.buffPurgeGlowLines,
        thickness = cfg.buffPurgeGlowThickness,
        speed = cfg.buffPurgeGlowSpeed,
        bg = cfg.buffPurgeGlowBackground == true or nil,
        bgR = bgc and bgc.r,
        bgG = bgc and bgc.g,
        bgB = bgc and bgc.b,
    }
    specInfo.r, specInfo.g, specInfo.b = CludesUI.Glows.ResolveColor(modeName, color and color.r, color and color.g, color and color.b)
    -- Class mode: the palette colour this spec (and Register's print) holds,
    -- for the colours-changed hook below the reload.
    if modeName == "class" then
        PurgeGlow.ccR, PurgeGlow.ccG, PurgeGlow.ccB = specInfo.r, specInfo.g, specInfo.b
    end
    return specInfo
end
mod.UF_PurgeGlowSpec = PurgeGlow.Spec

-- Registers (and restyles on a fingerprint change) the glow style while the
-- glow is on. Runs before any glow group is declared: initializeFrame
-- consumes the style for the pre-created button batch.
function PurgeGlow.Register(unitToken, cfg, widget, font)
    if not PurgeGlow.On(unitToken, cfg) then
        return
    end
    local auraKey = PurgeGlow.StyleKey(unitToken)
    local look = BuildStyle(unitToken, "HELPFUL", cfg, widget)
    local sp = PurgeGlow.Spec(cfg)
    look.purgeSpec = sp
    look.applyExtra = PurgeGlow.Extra
    local val = StyleTableFP(look, font)
        .. "|"
        .. FP(sp.style, sp.r, sp.g, sp.b, sp.lines, sp.thickness, sp.speed, sp.bg, sp.bgR, sp.bgG, sp.bgB)
    local state = ufFP[auraKey]
    if not state then
        state = {}
        ufFP[auraKey] = state
    end
    if state.style ~= val then
        state.style = val
        AK.styles[auraKey] = look
        AK.RestyleSoon(auraKey)
    end
end

-- Does the unit's cast bar occupy the strip directly below the frame -- the
-- space a bottom-anchored aura stack would otherwise take? Answered from LIVE
-- GEOMETRY, not from "has the user ever moved it": a bar that was free-moved in
-- unlock mode but still parks under its frame (the common case) keeps the
-- reserve, and only a bar genuinely somewhere else drops it.
--
-- The previous rule read ns.db, which is assigned one frame LATER than every
-- other input here (SetupOptionsPanel runs off C_Timer.After(0), while the
-- settings come from ns.UF_GetSettings, live since frame creation). Whether the
-- deferred container build landed before or after that frame decided the answer,
-- so the reserve differed between a cold login and a /reload with identical
-- saved data.
--
-- Fails toward KEEPING the reserve: no frame, no bounds yet (pre-layout) or a
-- unit with no movable cast bar of its own (boss) all answer true, which is what
-- the bottom-anchor path did before. The saved cast bar position lands on the
-- unlock system's deferred pass, so the settle timers further down re-run this
-- once the bar is actually where the user put it.
local CB_STRIP_SLACK = 8 -- physical pixels of tolerance on the strip's edges
local CB_FRAME_NAMES = {
    player = "CludesUIUnitFrames_Player",
    target = "CludesUIUnitFrames_Target",
    focus = "CludesUIUnitFrames_Focus",
}
local function CastbarBelowFrame(unitToken, widget)
    if not CB_FRAME_NAMES[unitToken] then
        return true
    end
    widget = widget or _G[CB_FRAME_NAMES[unitToken]]
    local vb = 0
    if mod.UF_Blizz and mod.UF_Blizz() then
        -- Blizzard Style: the bar hangs off the frame's aura block (an engine
        -- anchor whose edges are secret values under aura restriction, so no
        -- Lua compare may touch them) and the bottom stacks reserve nothing
        -- for it, so the strip test is moot: report it below the frame without
        -- reading it. Without the layout aspect (ns.UF_LayoutAspectOK) the bar
        -- rests on the visible art's bottom instead, so the strip is measured
        -- from there.
        if mod.UF_LayoutAspectOK and mod.UF_LayoutAspectOK() then
            return true
        end
        local _, _, _, b = mod.UF_BlizzVis(widget)
        vb = b or 0
    end
    -- frame.Castbar is the status bar; its PARENT is the holder the unlock
    -- system moves (see CreateCastBar in CUI_UnitFrames_Castbar.lua).
    local callback = widget and widget.Castbar and widget.Castbar:GetParent()
    if not callback then
        return true
    end
    local fl, fr, fb = widget:GetLeft(), widget:GetRight(), widget:GetBottom()
    local cl, cr, ct, cbot = callback:GetLeft(), callback:GetRight(), callback:GetTop(), callback:GetBottom()
    if not (fl and fr and fb and cl and cr and ct and cbot) then
        return true
    end
    -- Physical pixels: the holder is positioned independently of the frame and
    -- can carry its own effective scale, so raw coordinates are not comparable.
    local fontStr, cs = widget:GetEffectiveScale(), callback:GetEffectiveScale()
    fl, fr, fb = fl * fontStr, fr * fontStr, (fb + vb) * fontStr
    cl, cr, ct, cbot = cl * cs, cr * cs, ct * cs, cbot * cs
    -- Beside the frame rather than under it: nothing to reserve.
    if cl >= fr or cr <= fl then
        return false
    end
    -- How far the bar's top edge hangs below the frame's bottom: 0 is flush, a
    -- hand-aligned bar is a few pixels either way. The reserve itself is a fixed
    -- -castbarHeight, so it only ever clears a bar sitting AT the frame's edge;
    -- once the drop reaches a full bar height the reserve would park the icons
    -- on top of the bar rather than above it, so the stack docks to the frame
    -- instead. Overlap into the frame stays allowed within the tolerance.
    local hgt = ct - cbot
    if hgt <= 0 then
        hgt = 14
    end
    local drop = fb - ct
    return drop < hgt and drop >= -CB_STRIP_SLACK
end
mod.UF_CastbarBelowFrame = CastbarBelowFrame
-- Cross-addon: the options preview mirrors this decision so its layout matches
-- the live frames (CludesUIOptions/CUI_UnitFrames_Options.lua).
CludesUI.UF_CastbarBelowFrame = CastbarBelowFrame

-- A frame edge read as a plain number, or nil when it is unset or secret, so the
-- reserve below degrades to 0 instead of erroring on arithmetic.
local function secretNum(val)
    if val == nil or issecretvalue(val) then
        return nil
    end
    return val
end

-- How far the Resource Bars stack hangs below the PLAYER frame, in the frame's LOCAL
-- units (so it composes with the cast bar's -cbH). Resource Bars hands over the
-- stack's per-bar rects (CludesUI.ERB_PlayerStackBars: physical pixels, steady
-- through the combat/target/group visibility modes); this reserves the span down to
-- the lowest bar actually DOCKED under the frame, walking the chain so a bar sitting
-- elsewhere is never reserved. On WoW Forever the frame's own form power bar (a
-- druid's Power Type Mana + Form Power, CUI_UnitFrames_ForeverFormBar.lua) joins the
-- chain while it shows: it hangs under the power bar, outside the frame box.
local function ResourceStackBelowFrame(unitToken, widget)
    if unitToken ~= "player" then
        return 0
    end
    widget = widget or _G[CB_FRAME_NAMES.player]
    local getBars = CludesUI.ERB_PlayerStackBars
    local formBar = mod.UF_ForeverFormBarShown and mod.UF_ForeverFormBarShown()
    if not (widget and (getBars or formBar)) then
        return 0
    end
    local barList = getBars and getBars()
    if formBar then
        local l, region = secretNum(formBar:GetLeft()), secretNum(formBar:GetRight())
        local t, b = secretNum(formBar:GetTop()), secretNum(formBar:GetBottom())
        if l and region and t and b then
            local cfg = formBar:GetEffectiveScale() or 1
            barList = barList or {}
            barList[#barList + 1] = { l = l * cfg, r = region * cfg, t = t * cfg, b = b * cfg }
        end
    end
    if not barList then
        return 0
    end
    local fl = secretNum(widget:GetLeft())
    local fr = secretNum(widget:GetRight())
    local fb = secretNum(widget:GetBottom())
    if not (fl and fr and fb) then
        return 0
    end
    local fontStr = widget:GetEffectiveScale() or 1
    if fontStr == 0 then
        fontStr = 1
    end
    fl, fr, fb = fl * fontStr, fr * fontStr, fb * fontStr -- physical, matching the bar rects
    -- Walk the chain of bars actually DOCKED under the frame. Each must overlap the
    -- frame horizontally and dock to the boundary above it (the frame bottom first,
    -- then each docked bar's bottom). "Docked" mirrors CastbarBelowFrame: the gap from
    -- the boundary down to the bar's top is less than the bar's own height, and overlap
    -- up into the boundary is allowed within CB_STRIP_SLACK. A bar placed elsewhere
    -- (e.g. a bottom-center class resource while the power bar is docked) never joins
    -- the chain, so it is not reserved and the auras do not chase it down.
    local boundary, lowest, used = fb, nil, {}
    while true do
        local best, bestT, bestI
        for index = 1, #barList do
            local b = barList[index]
            if b and not used[index] and b.l < fr and b.r > fl then
                local hgt = b.t - b.b
                local drop = boundary - b.t
                if hgt > 0 and drop < hgt and drop >= -CB_STRIP_SLACK then
                    if not bestT or b.t > bestT then
                        best, bestT, bestI = b, b.t, index
                    end
                end
            end
        end
        if not best then
            break
        end
        used[bestI] = true
        if not lowest or best.b < lowest then
            lowest = best.b
        end
        boundary = best.b
    end
    if not lowest then
        return 0
    end
    local gap = fb - lowest
    if gap <= 0 then
        return 0
    end
    return gap / fontStr
end

-- Blizzard Style: point the frame's aura block (ns.UF_BlizzAuraBlock, the
-- edge a cast bar linked under the frame follows) at the lowest
-- bottom-anchored stack. `container` nil = this display is off; `ia` is its
-- anchor point and `xOff` its x offset from the frame's corner (the fixed
-- edge under `ia`), so the block's corner lands on the frame's own edge.
-- Merged buffs ride the debuff anchor with the debuff container below them
-- (above for upward growth); otherwise a bottom-anchored debuff stack wins
-- over a bottom-anchored buff stack. Nothing below: the visible art's bottom.
local function PointBlizzAuraBlock(widget, unitToken, cfg, buffSide, boxHolder, ia, xOff, merged, gY)
    if not (CB_FRAME_NAMES[unitToken] and mod.UF_BlizzAuraBlock and mod.UF_BlizzAuraBlock(widget)) then
        return
    end
    local dA, bA = cfg.debuffAnchor or "none", cfg.buffAnchor or "topleft"
    local dBottom = (dA == "bottomleft" or dA == "bottomright")
    local bBottom = (bA == "bottomleft" or bA == "bottomright") and cfg.showBuffs ~= false
    local lowestIsBuff
    if merged then
        if dBottom then
            lowestIsBuff = (gY == "UP")
        end
    elseif dBottom then
        lowestIsBuff = false
    elseif bBottom then
        lowestIsBuff = true
    end
    if lowestIsBuff == nil then
        mod.UF_BlizzAuraBlockBottom(widget, nil)
    elseif boxHolder and lowestIsBuff == buffSide then
        local corner = (ia and ia:find("RIGHT", 1, true)) and "BOTTOMRIGHT" or "BOTTOMLEFT"
        mod.UF_BlizzAuraBlockBottom(widget, boxHolder, corner, -(xOff or 0))
    end
end

-- Container anchoring: mirrors the legacy element's SetPoint(ia, frame, fp,
-- ox + userX, oy + castbarPush + userY) with gap = 1.
-- buffContainer (HARMFUL calls only): the unit's buff container, needed by
-- the Anchor Buffs with Debuffs mode below.
-- reanchorOnly (the footprint-watcher re-anchor path): re-run ONLY the geometry --
-- SetPoint + aura-block point -- and skip the one-time weapon-enchant declaration
-- below, which must not be re-issued every settle frame (the engine has no unregister).
local function AnchorContainer(boxHolder, widget, unitToken, baseSet, cfg, buffContainer, reanchorOnly)
    local buffSide = (baseSet == "HELPFUL")

    -- Boss simple side display: forced side anchoring flush with the frame
    -- top, growing away from the chosen edge, own offsets, no castbar push.
    local isSimple, simpleMode = BossSimple(unitToken, baseSet, cfg)
    if isSimple then
        local ia, filterPass
        if simpleMode == "right" then
            ia, filterPass = "TOPLEFT", "TOPRIGHT"
        else
            ia, filterPass = "TOPRIGHT", "TOPLEFT"
        end
        local offX, offY
        if buffSide then
            offX, offY = mod.GetBossSimpleBuffOffset(cfg)
        else
            offX, offY = mod.GetBossSimpleDebuffOffset(cfg)
        end
        boxHolder:ClearAllPoints()
        boxHolder:SetPoint(ia, widget, filterPass, offX or 0, offY or 0)
        AK.SetContainerAnchor(boxHolder, ia)
        local gX = "LEFT"
        if simpleMode == "right" then
            gX = "RIGHT"
        end
        AK.SetContainerGrowth(boxHolder, FlowDir(gX), FlowDir("DOWN"))
        return simpleMode
    end

    local anchorFrame = Pick(buffSide, cfg.buffAnchor, cfg.debuffAnchor)
    if anchorFrame == nil then
        anchorFrame = Pick(buffSide, "topleft", "none")
    end

    -- Anchor Buffs with Debuffs (per-unit debuffAnchorBuffs, non-boss):
    -- buffs adopt the debuff anchor/growth/offsets and become the stack's first rows;
    -- the debuff container then rides the BUFF CONTAINER's leading edge. The engine
    -- re-sizes that container to its rows every layout pass, so the push is
    -- engine-driven -- full rows only, and no aura reads (secret-safe in combat). The
    -- merge OWNS buff visibility: it renders buffs even with Buff Display at None
    -- (showBuffs false), which is the state the options auto-select on enable.
    local merged = cfg.debuffAnchorBuffs == true
        and not unitToken:match("^boss")
        and (cfg.debuffAnchor or "none") ~= "none"
    local mergedBuff = merged and buffSide
    if mergedBuff then
        anchorFrame = cfg.debuffAnchor
    end
    if anchorFrame == "none" then
        -- Player buffs hidden: the weapon enchants ride this container (see
        -- the declaration below), so ApplyGroupConfig's SetShown(false) takes
        -- them down with it -- nothing to retire here.
        PointBlizzAuraBlock(widget, unitToken, cfg, buffSide, nil, nil, nil, merged, nil)
        return anchorFrame
    end

    local growth = Pick(buffSide, cfg.buffGrowth, cfg.debuffGrowth)
    if mergedBuff then
        growth = cfg.debuffGrowth
    end
    local ia, filterPass, ox, oy, gX, gY = ResolveLayout(anchorFrame, growth)

    -- Blizzard Style: the frame is the stock box with transparent padding round
    -- the art, so the anchors move in to the visible art's edges; and on the
    -- frames with a movable cast bar the bottom stacks no longer reserve the
    -- bar's strip -- the bar hangs below them instead, off the frame's aura
    -- block (ns.UF_BlizzAuraBlock), as the stock spell bar does.
    local vl, vr, vt, vb
    if mod.UF_BlizzVis then
        vl, vr, vt, vb = mod.UF_BlizzVis(widget)
    end
    if vl then
        if anchorFrame == "topleft" or anchorFrame == "bottomleft" or anchorFrame == "left" then
            ox = ox + vl
        elseif anchorFrame == "topright" or anchorFrame == "bottomright" or anchorFrame == "right" then
            ox = ox - vr
        end
        if anchorFrame == "topleft" or anchorFrame == "topright" then
            oy = oy - vt
        elseif anchorFrame == "bottomleft" or anchorFrame == "bottomright" then
            oy = oy + vb
        end
    end

    local cbOff = 0
    local castBarShown, castBarH
    if unitToken == "player" then
        castBarShown, castBarH = cfg.showPlayerCastbar, cfg.playerCastbarHeight
    else
        castBarShown, castBarH = cfg.showCastbar, cfg.castbarHeight
    end
    -- Bottom anchors ONLY: they stack below the frame, where an attached cast
    -- bar hangs, so they reserve its height. Side anchors (left/right) are
    -- vertically CENTERED on the frame and clear the bar by construction --
    -- including them here pushed centered icons DOWN by the full bar height
    -- (field case: boss left-anchored debuffs sat ~castbarHeight low). The
    -- oUF-element anchor path has always been bottom-only; this matches it.
    if
        castBarShown
        and (anchorFrame == "bottomleft" or anchorFrame == "bottomright")
        and not (vl and CB_FRAME_NAMES[unitToken] and mod.UF_LayoutAspectOK and mod.UF_LayoutAspectOK())
        and CastbarBelowFrame(unitToken, widget)
    then
        if not castBarH or castBarH <= 0 then
            castBarH = 14
        end
        cbOff = -castBarH
    end
    -- Resource Bars stack (power bar / class resource / Forever shapeshift mana), and
    -- the frame's own Forever form power bar,
    -- below the player frame: reserve down to its bottom edge the same way, and keep
    -- whichever reserve reaches LOWER (the cast bar may sit above or below it). Same
    -- bottom-anchor + non-Blizzard-aspect gate as the cast bar; player-only inside
    -- ResourceStackBelowFrame. CfgFP leaves this value out: a stack footprint change
    -- re-runs this anchor through the re-anchor Resource Bars arms (further down).
    if
        (anchorFrame == "bottomleft" or anchorFrame == "bottomright")
        and not (vl and CB_FRAME_NAMES[unitToken] and mod.UF_LayoutAspectOK and mod.UF_LayoutAspectOK())
    then
        local resReserve = ResourceStackBelowFrame(unitToken, widget)
        if resReserve > 0 and -resReserve < cbOff then
            cbOff = -resReserve
        end
    end

    local offX = Pick(buffSide, cfg.buffOffsetX, cfg.debuffOffsetX) or 0
    local offY = Pick(buffSide, cfg.buffOffsetY, cfg.debuffOffsetY) or 0
    if mergedBuff then
        offX = cfg.debuffOffsetX or 0
        offY = cfg.debuffOffsetY or 0
    end

    boxHolder:ClearAllPoints()
    if merged and not buffSide and buffContainer then
        -- Ride the buff container: horizontal side from the layout anchor,
        -- vertical side from the wrap direction, one debuff line-gap
        -- between the blocks. Debuffs never share a row with buffs.
        local Pix = CludesUI.PP
        local horiz = ""
        if ia:find("LEFT") then
            horiz = "LEFT"
        elseif ia:find("RIGHT") then
            horiz = "RIGHT"
        end
        local vert, relVert, gapSign
        if gY == "UP" then
            vert, relVert, gapSign = "BOTTOM", "TOP", 1
        else
            vert, relVert, gapSign = "TOP", "BOTTOM", -1
        end
        local gap = Pix.FromPixels(cfg.debuffSpacingY or 1)
        boxHolder:SetPoint(vert .. horiz, buffContainer, relVert .. horiz, 0, gap * gapSign)
        AK.SetContainerAnchor(boxHolder, vert .. horiz)
        PointBlizzAuraBlock(widget, unitToken, cfg, buffSide, boxHolder, ia, ox + offX, merged, gY)
    else
        -- Side anchors ("left"/"right") pin the container's vertical CENTER to
        -- the frame's LEFT/RIGHT point -- a center-class axis. An odd-physical-
        -- pixel frame height parks that center on a half pixel, so every icon
        -- edge lands on X.5: the icon texture (default pixel snapping) rounds
        -- to whole pixel rows while the snap-disabled 1px border strips
        -- straddle two rows at the true fractional edges -- the icon visibly
        -- bleeds past the border. Standing parity rule (see the pixel-perfect
        -- half-pixel conventions): the perpendicular axis of an edge anchor
        -- snaps via SnapCenterForDim against the ELEMENT dimension. Correct
        -- offY so the row's center sits on the parity grid for the icon size.
        -- Reading our own frame's live geometry is legal under aura
        -- restriction; nil (pre-layout window) keeps the raw offset and a
        -- later anchor pass corrects it.
        if anchorFrame == "left" or anchorFrame == "right" then
            local Pix = CludesUI.PP
            if Pix and Pix.SnapCenterForDim and Pix.SnapForES then
                local es = boxHolder:GetEffectiveScale()
                local _, fcY = widget:GetCenter()
                if fcY then
                    local _, iconH = ElementSize(unitToken, baseSet, cfg)
                    local rawY = fcY + oy + cbOff + offY
                    offY = offY + (Pix.SnapCenterForDim(rawY, iconH, es) - rawY)
                end
                -- Growth (horizontal) axis is EDGE-class: the container's edge
                -- pins to the frame's edge, so the absolute X snaps to a whole
                -- physical pixel (SnapForES). A fractional frame edge otherwise
                -- lands every icon's vertical edges on partial pixels -- same
                -- bleed as the parity case, on the left/right borders. Integer
                -- icon widths keep the far edge whole once this edge is.
                local fx = (anchorFrame == "left") and widget:GetLeft() or widget:GetRight()
                if fx then
                    local rawX = fx + ox + offX
                    offX = offX + (Pix.SnapForES(rawX, es) - rawX)
                end
            end
        end
        boxHolder:SetPoint(ia, widget, filterPass, ox + offX, oy + cbOff + offY)
        AK.SetContainerAnchor(boxHolder, ia)
        PointBlizzAuraBlock(widget, unitToken, cfg, buffSide, boxHolder, ia, ox + offX, merged, gY)
        -- Weapon enchants are not auras: the engine's own item-enchantment
        -- source renders them as a layout group flowed AHEAD of the aura
        -- groups on this container (see AK.AddItemEnchantmentsToContainer),
        -- so nothing is anchored and no cells are reserved. They ride the
        -- broad-content modes (All Buffs or Has Duration), like every other
        -- generic buff: declared the first time the buff row shows in a broad
        -- mode (this pass re-runs on a chain change and when the row turns
        -- on), and -- the engine has no addon-facing unregister -- kept until
        -- the next /reload should the row or the mode turn off again.
        if not reanchorOnly and WeaponCells.On(unitToken, baseSet, cfg) then
            local Pix = CludesUI.PP
            local wid, hgt = ElementSize(unitToken, baseSet, cfg)
            local gap = Pix.FromPixels(cfg.buffSpacingX or 1)
            local lineGap = Pix.FromPixels(cfg.buffSpacingY or 1)
            local placement = CustomAuraContainerItemEnchantmentPlacement
            local sortMethods = AuraContainerItemEnchantmentSortMethod
            local sortDirs = AuraContainerSortDirection
            AK.AddItemEnchantmentsToContainer(boxHolder, {
                style = StyleKey("player", "HELPFUL"),
                -- Marks the cell as a weapon enchant for the style pass
                -- (Blizzard Style draws the stock temp-enchant ring on those only).
                extraInit = AK.EnchantCellInit,
                hidePermanent = true,
                -- REVERSE keeps main hand adjacent to the aura run: the
                -- engine puts the group's first element at the leading edge,
                -- and Slot order is main hand, off hand, ranged.
                sortMethod = sortMethods and sortMethods.Slot,
                sortDirection = sortDirs and sortDirs.Reverse,
                layout = {
                    elementWidth = wid,
                    elementHeight = hgt,
                    elementSpacing = gap,
                    lineSpacing = lineGap,
                    -- No groupSpacing, see the aura groups' layout below.
                    groupLineSpacing = lineGap,
                    placement = placement and placement.BeforeAuraGroups,
                },
            })
            -- Only where AK could declare them (it no-ops without the API).
            if boxHolder.AddItemEnchantment and AuraContainerItemEnchantmentSlot then
                WeaponCells.declared = boxHolder
            end
        end
    end
    AK.SetContainerGrowth(boxHolder, FlowDir(gX), FlowDir(gY))

    return anchorFrame
end

------------------------------------------------------------------------------
-- Tracked Auras on a FRIENDLY target / focus
--
-- The include links ("inc" / "incmine") filter by spell ID alone, and the engine
-- skips spell-ID candidates for debuffs on a unit the player can assist (unless
-- the spell is never-secret) -- so on a friendly target or focus those groups
-- would accept every other debuff (and the other groups' tracked-spell excludes
-- are skipped too, doubling every debuff the mode shows). While the unit can be
-- assisted the include groups park at 0; everything else on the frame is
-- unchanged. Only Tracked Auras is the exception: the include links are its
-- whole display, so parking would blank the frame. There the links NARROW
-- instead (ApplyGroupConfig): player-cast only, which keeps the never-secret
-- lockouts people track and drops the NPC/boss debuffs; if both links exist
-- the any-caster one also drops your casts and "incmine" lists every tracked
-- spell, so no debuff renders twice. What narrowing cannot drop: other
-- players' debuffs that are not never-secret pass the spell check unfiltered
-- (in PvP, enemy players' debuffs on that friendly unit), and NPC-cast tracked
-- spells are lost there. The check matches the engine's (immune and
-- uninteractable units count as assistable). An unreadable answer (pcall
-- failure or a secret value) leaves the groups live, as before. A missing
-- unit (no target, focus out of range) keeps the last real answer, and the
-- frame's own show (unit watch, the unit existing again -- a focus back in
-- range fires no change event) re-checks it. Also re-checked on target/focus
-- changes (unitWatcher, below), on the unit's UNIT_FACTION (registered only
-- while that unit has an active include group), and on the player's own
-- faction flips (the player recovery watcher). Boss frames are left as they are.
--   state[unit] = { keys = { [groupKey] = true }, num = liveCount, parked = bool }
------------------------------------------------------------------------------
local IncGate = { state = {}, hooked = setmetatable({}, { __mode = "k" }) }

function IncGate.Assistable(unitToken)
    local success, can = pcall(UnitCanAssist, "player", unitToken, true, true)
    if success and not (issecretvalue and issecretvalue(can)) and can == true then
        return true
    end
    return false
end

-- The gate's answer for config passes: live while the unit exists, else the
-- last real answer (false before there was one).
function IncGate.Answer(unitToken)
    if UnitExists(unitToken) then
        return IncGate.Assistable(unitToken)
    end
    local g = IncGate.state[unitToken]
    return g ~= nil and g.parked == true
end

-- UNIT_FACTION follows the live state: registered per unit only while it holds
-- keys or wears the Purgeable Buff Glow (PurgeGlow.watch, the same friendly
-- flip). The unit change events ride the always-on unitWatcher instead, so a
-- target swap runs the gate before its one aura re-parse.
function IncGate.Sync()
    local state, pw = IncGate.state, PurgeGlow.watch
    local wantT, wantF = state.target or pw.target, state.focus or pw.focus
    local sig = (wantT and 1 or 0) + (wantF and 2 or 0)
    if IncGate.sig == sig then
        return
    end
    IncGate.sig = sig
    local frame = IncGate.frame
    if sig == 0 then
        if frame then
            frame:UnregisterAllEvents()
        end
        return
    end
    if not frame then
        frame = CreateFrame("Frame")
        IncGate.frame = frame
        frame:SetScript("OnEvent", IncGate.OnEvent)
    end
    frame:UnregisterEvent("UNIT_FACTION")
    if wantT and wantF then
        frame:RegisterUnitEvent("UNIT_FACTION", "target", "focus")
    elseif wantT then
        frame:RegisterUnitEvent("UNIT_FACTION", "target")
    else
        frame:RegisterUnitEvent("UNIT_FACTION", "focus")
    end
end

-- ApplyGroupConfig (debuff element): record the unit's active include keys and
-- their live count; returns whether they park right now.
function IncGate.Store(unitToken, keyList, num)
    if unitToken ~= "target" and unitToken ~= "focus" then
        return false
    end
    local state = IncGate.state
    local g
    if keyList then
        g = state[unitToken]
        local parked = IncGate.Answer(unitToken)
        if not g then
            g = {}
            state[unitToken] = g
        end
        g.keys, g.num = keyList, num
        g.parked = parked
    else
        state[unitToken] = nil
    end
    IncGate.Sync()
    return g ~= nil and g.parked
end

-- Re-check one unit; work runs only when the answer flips. The other groups'
-- tracked-spell excludes follow the park state too (ApplyGroupConfig), so a flip
-- forces the element's config pass (which re-stores the counts) and then
-- re-parses: membership was decided under the old answer, and re-setting
-- candidates is what makes the engine re-decide it. noParse: the caller
-- re-parses right after (unitWatcher's RefreshUnit), so only one parse runs.
function IncGate.Apply(unitToken, noParse)
    local g = IncGate.state[unitToken]
    local record = registry[unitToken]
    if not (g and record and record.debuffs) or record.building then
        return
    end
    -- No unit: keep the last answer (nothing is shown; the next unit re-checks).
    if not UnitExists(unitToken) then
        return
    end
    local park = IncGate.Assistable(unitToken)
    if park == g.parked then
        return
    end
    g.parked = park
    record.cfgDirty = true
    if record.frame and mod.UF_ReloadAuraContainers then
        mod.UF_ReloadAuraContainers(record.frame, unitToken)
    end
    if not noParse then
        record.debuffs:UpdateAllAuras()
    end
end

-- UNIT_FACTION can fire in bursts: one coalesced check a frame later.
function IncGate.Flush()
    local t, frame = IncGate.pendT, IncGate.pendF
    IncGate.pendT, IncGate.pendF = nil, nil
    if t then
        IncGate.Apply("target")
        PurgeGlow.Check("target")
    end
    if frame then
        IncGate.Apply("focus")
        PurgeGlow.Check("focus")
    end
end

function IncGate.OnEvent(_, _, unitToken)
    if unitToken == "target" or unitToken == "focus" then
        if not (IncGate.pendT or IncGate.pendF) then
            C_Timer.After(0, IncGate.Flush)
        end
        if unitToken == "target" then
            IncGate.pendT = true
        else
            IncGate.pendF = true
        end
    end
end

------------------------------------------------------------------------------
-- Purgeable Buff Glow on a FRIENDLY target / focus: a friend's buffs are not
-- the player's to purge, and the Dispellable token also matches a friend's
-- helpful Magic, so an assistable unit keeps the plain show-all row
-- (BuildChain reads PurgeGlow.Active). Same check as the Tracked Auras gate
-- above: live while the unit exists, else the last answer (a focus out of
-- range keeps its state). A flip re-runs the unit's reload; only the buff
-- element's chain signature moves, so only its config pass is forced (and
-- after the first flip each way every group is already declared).
-- Re-checked on target/focus changes (unitWatcher), the frame's own show,
-- the player's faction flips (the player recovery watcher) and the unit's
-- UNIT_FACTION (IncGate.Sync holds it while PurgeGlow.watch[unit] is set, i.e.
-- only while the glow is on for that unit).
------------------------------------------------------------------------------
function PurgeGlow.Friendly(unitToken)
    if UnitExists(unitToken) then
        PurgeGlow.friendly[unitToken] = IncGate.Assistable(unitToken)
    end
    return PurgeGlow.friendly[unitToken] == true
end

function PurgeGlow.Active(unitToken, cfg)
    return PurgeGlow.On(unitToken, cfg) and not PurgeGlow.Friendly(unitToken)
end

-- noParse: the caller re-parses right after (unitWatcher's RefreshUnit).
function PurgeGlow.Check(unitToken, noParse)
    if not PurgeGlow.watch[unitToken] then
        return
    end
    local record = registry[unitToken]
    if not (record and record.buffs) or record.building then
        return
    end
    if not UnitExists(unitToken) then
        return
    end
    if IncGate.Assistable(unitToken) == (PurgeGlow.friendly[unitToken] == true) then
        return
    end
    if record.frame and mod.UF_ReloadAuraContainers then
        mod.UF_ReloadAuraContainers(record.frame, unitToken)
    end
    if not noParse then
        record.buffs:UpdateAllAuras()
    end
end

-- Held by the unit's reload: set while the glow is on for target / focus.
function PurgeGlow.SetWatch(unitToken, enabled)
    if unitToken ~= "target" and unitToken ~= "focus" then
        return
    end
    if enabled then
        enabled = true
    else
        enabled = nil
    end
    if PurgeGlow.watch[unitToken] == enabled then
        return
    end
    PurgeGlow.watch[unitToken] = enabled
    IncGate.Sync()
end

local function ApplyGroupConfig(boxHolder, unitToken, baseSet, cfg, filterChain, declared)
    local Pix = CludesUI.PP
    local buffSide = (baseSet == "HELPFUL")
    local anyClass = #filterChain > 0

    local isSimple = BossSimple(unitToken, baseSet, cfg)

    -- Anchor Buffs with Debuffs: the merge owns buff visibility (Buff
    -- Display reads None while the stack renders the buffs), and the buff
    -- groups wrap like the debuff stack they join.
    local mergedAB = cfg.debuffAnchorBuffs == true
        and not unitToken:match("^boss")
        and (cfg.debuffAnchor or "none") ~= "none"

    local isShown = SideOn(unitToken, baseSet, cfg)

    local num = 0
    if isShown then
        num = Pick(buffSide, cfg.maxBuffs or 4, cfg.maxDebuffs or 28)
    end

    local size, hgt = ElementSize(unitToken, baseSet, cfg)
    local spX, spY
    if unitToken:match("^boss") then
        -- Boss uses a single spacing value (its simple-display key when the
        -- simple mode is active).
        local sp
        if buffSide then
            sp = mod.GetBossBuffSpacing(cfg, isSimple)
        else
            sp = mod.GetBossDebuffSpacing(cfg, isSimple)
        end
        spX = Pix.FromPixels(sp or 1)
        spY = spX
    else
        spX = Pix.FromPixels(Pick(buffSide, cfg.buffSpacingX, cfg.debuffSpacingX) or 1)
        spY = Pix.FromPixels(Pick(buffSide, cfg.buffSpacingY, cfg.debuffSpacingY) or 1)
    end

    local growth = Pick(buffSide, cfg.buffGrowth, cfg.debuffGrowth)
    if isSimple then
        growth = "auto"
    end
    if mergedAB and buffSide then
        growth = cfg.debuffGrowth
    end
    local perRow = Pick(buffSide, cfg.buffMaxPerRow, cfg.debuffMaxPerRow)
    -- Max Important lets the important links grow past Max Count, so a Max
    -- Per Row between the two caps sizes the row from Max Important (an
    -- unset Per Row, one equal to Max Count or one at or above Max
    -- Important keeps the Max Count rule).
    local capMax = num
    local mi = (not buffSide) and cfg.maxImportantDebuffs or nil
    if num > 0 and mi and perRow and perRow > num and mi > perRow then
        for index = 1, #filterChain do
            if filterChain[index].important then
                capMax = mi
                break
            end
        end
    end
    local cols, oneRow = ResolveColumns(growth, capMax > 0 and capMax or 1, perRow, num > 0 and num or 1)
    -- Weapon enchant cells share the first row. The engine applies one line
    -- size to every row, so only a single-row cap over at most one shown
    -- group (which never overflows it) widens by the cells showing; a grid
    -- or several groups keep the cells in their rows.
    local cellsOn = WeaponCells.Shown(unitToken, baseSet, cfg)
    local cellN = cellsOn and WeaponCells.Count() or 0
    if unitToken == "player" and buffSide then
        WeaponCells.Sync(cellsOn, cellN)
    end
    if cellN > 0 and oneRow then
        local groups = 0
        for index = 1, #filterChain do
            if not filterChain[index].hidden then
                groups = groups + 1
            end
        end
        if groups <= 1 then
            cols = cols + cellN
        end
    end
    AK.SetContainerRowWidth(boxHolder, cols * size + (cols - 1) * spX + 0.4)

    -- Candidate filters: (debuffs) the always-hide and Hide Exhaustion
    -- excludes. Caster scope rides the chain links' own PLAYER tokens, never
    -- this table.
    local candidate = nil
    if not buffSide then
        local ex = {}
        for ident in pairs(ALWAYS_HIDE_DEBUFFS) do
            ex[ident] = true
        end
        if cfg.debuffHideExhaustion ~= false then
            for ident in pairs(SATED_DEBUFFS) do
                ex[ident] = true
            end
        end
        -- Tracked Auras (target/focus/boss): user excludes hide everywhere; active
        -- INCLUDES are excluded from every OTHER group while an include link renders
        -- them (its own cand overrides both spell-ID sets). Show All carries no
        -- include link, so its catch-all keeps them. Player units carry neither key.
        local uex = cfg.debuffExclude
        if uex then
            for ident, val in pairs(uex) do
                if val then
                    ex[ident] = true
                end
            end
        end
        local uinc = cfg.debuffInclude
        if uinc then
            local incLink = false
            for index = 1, #filterChain do
                if filterChain[index].inc then
                    incLink = true
                    break
                end
            end
            -- Not while IncGate parks the include links (a friendly target or
            -- focus): a never-secret tracked spell still honours the excludes
            -- there and would show nowhere.
            if
                incLink
                and not ((unitToken == "target" or unitToken == "focus") and IncGate.Answer(unitToken))
            then
                for ident, val in pairs(uinc) do
                    if val then
                        ex[ident] = true
                    end
                end
            end
        end
        candidate = candidate or {}
        candidate.excludeSpellIDs = ex
    end

    -- No groupSpacing: the engine trails every element with elementSpacing,
    -- the last one of a group included, so a group boundary -- the seam
    -- between the weapon-enchant cells and the first aura -- already sits one
    -- spX away, and groupSpacing would double it.
    local layout = { elementWidth = size, elementHeight = hgt, elementSpacing = spX, lineSpacing = spY }

    -- Active set = "all" (a non-player BUFF element with no classes enabled)
    -- or each chain link. Every other declared group -- disabled classes and
    -- retired variants -- parks at count 0 (declared sets only ever grow;
    -- setters run per declared key only).
    local isActive, hiddenKeys, tokensOf, incKeys, impKeys = {}, nil, {}, nil, nil
    -- Purgeable Buff Glow groups lay out FIRST whatever their declaration
    -- order (layoutIndex beats every other group's registration index).
    local glowKeySet, glowLayout
    if num > 0 then
        if anyClass then
            for index = 1, #filterChain do
                local c = filterChain[index]
                isActive[c.key] = c.cand or false
                tokensOf[c.key] = c.tokens
                if c.glow then
                    glowKeySet = glowKeySet or {}
                    glowKeySet[c.key] = true
                end
                -- Subtracted classes (the player PAB model) stay declared
                -- so their negations keep them out of the catch-all, but
                -- render nothing themselves.
                if c.hidden then
                    hiddenKeys = hiddenKeys or {}
                    hiddenKeys[c.key] = true
                end
                if c.inc then
                    incKeys = incKeys or {}
                    incKeys[c.key] = true
                end
                if c.important then
                    impKeys = impKeys or {}
                    impKeys[c.key] = true
                end
            end
        elseif buffSide and unitToken ~= "player" then
            -- Non-player buffs keep the legacy show-all fallback (no classes =
            -- everything). Player elements run the PAB content model (an empty
            -- chain = add mode with nothing selected = show nothing), and
            -- non-player debuff chains carry their catch-all explicitly (Show
            -- All) or mean nothing at all (Only Tracked Auras, empty list).
            isActive.all = false
        end
    end
    -- Tracked Auras include groups park while a target/focus can be assisted
    -- (IncGate above); the debuff element owns the unit's gate state.
    local incPark = false
    if not buffSide then
        incPark = IncGate.Store(unitToken, incKeys, num)
    end
    -- Only Tracked Auras (the chain is nothing but include links) narrows
    -- instead of parking, see IncGate above: per-pass overrides of the links'
    -- own tokens and candidates, which the next pass after the unit turns
    -- hostile restores from the chain.
    if incPark then
        local anyC, mineC, onlyInc = nil, nil, true
        for index = 1, #filterChain do
            local c = filterChain[index]
            if not c.inc then
                onlyInc = false
                break
            end
            if c.mine then
                mineC = c
            else
                anyC = c
            end
        end
        if onlyInc then
            incPark = false
            if anyC then
                local cd = { isFromPlayerOrPlayerPet = true }
                for k, val in pairs(anyC.cand) do
                    cd[k] = val
                end
                isActive[anyC.key] = cd
                if mineC then
                    tokensOf[anyC.key] = { "HARMFUL", "!PLAYER" }
                end
            end
            if anyC and mineC then
                local ids = {}
                for ident in pairs(anyC.cand.includeSpellIDs) do
                    ids[ident] = true
                end
                for ident in pairs(mineC.cand.includeSpellIDs) do
                    ids[ident] = true
                end
                isActive[mineC.key] = { includeSpellIDs = ids, excludeSpellIDs = {} }
            end
        end
    end
    for eff, details in pairs(declared) do
        if isActive[eff] ~= nil then
            local n = num
            if impKeys and impKeys[eff] then
                n = cfg.maxImportantDebuffs or num
            end
            if (hiddenKeys and hiddenKeys[eff]) or (incPark and incKeys[eff]) then
                n = 0
            end
            CludesUI.AuraKit.SetGroupCap(boxHolder, eff, n)
            -- Filter strings follow the CURRENT chain too: a plain key's tokens
            -- depend on which earlier token classes are enabled, so a group first
            -- declared under another set would keep a stale string (a debuff shown
            -- twice, or not at all) until /reload. The setter no-ops on an
            -- unchanged string, so untouched groups cost nothing.
            local toks = tokensOf[eff]
            if toks and boxHolder.SetAuraGroupFilterString then
                boxHolder:SetAuraGroupFilterString(eff, AK.Filter(unpack(toks)))
            end
            local groupCand = candidate
            -- Candidate-class groups carry their defining booleans on top of the shared
            -- candidates (fresh table: setter securecopies). Read from the CURRENT
            -- chain (active), not the declared registry: the Non-Player handoff changes
            -- a class's boolean set when the enabled set changes, and groups persist
            -- across those toggles (declared sets only ever grow).
            local ac = isActive[eff]
            if ac then
                groupCand = {}
                if candidate then
                    for k, val in pairs(candidate) do
                        groupCand[k] = val
                    end
                end
                for k, val in pairs(ac) do
                    groupCand[k] = val
                end
            end
            boxHolder:SetAuraGroupCandidateFilters(eff, groupCand)
            if glowKeySet and glowKeySet[eff] then
                if not glowLayout then
                    glowLayout = { layoutIndex = 0 }
                    for k, val in pairs(layout) do
                        glowLayout[k] = val
                    end
                end
                boxHolder:SetAuraGroupLayout(eff, glowLayout)
            else
                boxHolder:SetAuraGroupLayout(eff, layout)
            end
        else
            CludesUI.AuraKit.SetGroupCap(boxHolder, eff, 0)
        end
    end

    boxHolder:SetShown(isShown)
    return isShown
end

-- Sorted value-sensitive fingerprint of a tri-state spell list
-- ({ [id] = true|false }): disabled entries prefix "-", so an enable
-- flip moves the print (CandFP's count:sum ignores values).
local function TriListFP(entries)
    if not entries or next(entries) == nil then
        return "-"
    end
    local o = {}
    for ident, val in pairs(entries) do
        o[#o + 1] = (val and "" or "-") .. ident
    end
    table.sort(o)
    return table.concat(o, ",")
end

-- Fingerprint over every input AnchorContainer + ApplyGroupConfig read
-- (computed values like ElementSize and the pixel-scaled spacings capture
-- scale changes implicitly). The chain composition is covered separately by
-- entry.sig; a sig change swaps the container and forces this pass anyway.
local function CfgFP(unitToken, baseSet, cfg, widget)
    local Pix = CludesUI.PP
    local buffSide = (baseSet == "HELPFUL")
    local size, hgt = ElementSize(unitToken, baseSet, cfg)
    local isSimple, simpleMode = BossSimple(unitToken, baseSet, cfg)
    local spX, spY
    if unitToken:match("^boss") then
        local sp
        if buffSide then
            sp = mod.GetBossBuffSpacing(cfg, isSimple)
        else
            sp = mod.GetBossDebuffSpacing(cfg, isSimple)
        end
        spX = Pix.FromPixels(sp or 1)
        spY = spX
    else
        spX = Pix.FromPixels(Pick(buffSide, cfg.buffSpacingX, cfg.debuffSpacingX) or 1)
        spY = Pix.FromPixels(Pick(buffSide, cfg.buffSpacingY, cfg.debuffSpacingY) or 1)
    end
    local sOffX, sOffY = 0, 0
    if isSimple then
        if buffSide then
            sOffX, sOffY = mod.GetBossSimpleBuffOffset(cfg)
        else
            sOffX, sOffY = mod.GetBossSimpleDebuffOffset(cfg)
        end
    end
    local castBarShown, castBarH
    if unitToken == "player" then
        castBarShown, castBarH = cfg.showPlayerCastbar, cfg.playerCastbarHeight
    else
        castBarShown, castBarH = cfg.showCastbar, cfg.castbarHeight
    end
    -- Anchor Buffs with Debuffs inputs ride BOTH elements' fingerprints,
    -- but ONLY while the toggle is on: the buff element reads the debuff
    -- anchor set while merged, and the debuff element re-anchors when the
    -- merge flag or buff visibility flips. Off (the default), the extra
    -- slots are constant nils so no existing fingerprint ever moves.
    local mAB = cfg.debuffAnchorBuffs == true
    local filterPass = FP(
        size,
        hgt,
        spX,
        spY,
        isSimple,
        simpleMode,
        sOffX,
        sOffY,
        Pick(buffSide, cfg.buffAnchor, cfg.debuffAnchor),
        Pick(buffSide, cfg.buffGrowth, cfg.debuffGrowth),
        Pick(buffSide, cfg.buffOffsetX, cfg.debuffOffsetX),
        Pick(buffSide, cfg.buffOffsetY, cfg.debuffOffsetY),
        castBarShown,
        castBarH,
        Pick(buffSide, cfg.maxBuffs, cfg.maxDebuffs),
        Pick(buffSide, cfg.buffMaxPerRow, cfg.debuffMaxPerRow),
        cfg.showBuffs,
        mAB,
        mAB and cfg.debuffAnchor or nil,
        mAB and cfg.debuffGrowth or nil,
        mAB and cfg.debuffOffsetX or nil,
        mAB and cfg.debuffOffsetY or nil,
        mAB and cfg.debuffSpacingY or nil,
        CastbarBelowFrame(unitToken, widget),
        -- (The Resource Bars stack reserve is deliberately NOT in this fingerprint:
        -- AnchorContainer reads it live whenever it runs, and a footprint change is
        -- re-anchored by the Resource-Bars-armed throttle below -- not by forcing a full
        -- restyle here on every geometry shift.)
        -- Tracked Auras lists: ApplyGroupConfig reads both (the shared
        -- excludes), and TRI-STATE flips don't move the chain sig -- an
        -- entry's enable checkbox must re-drive this pass. The caster-scope
        -- maps (boss any-caster opt-out, target/focus MINE opt-in) move an
        -- include between the two scope links.
        TriListFP(cfg.debuffExclude),
        TriListFP(cfg.debuffInclude),
        TriListFP(cfg.debuffIncludeAnyCaster),
        TriListFP(cfg.debuffIncludeMine)
    )
    -- Hide Exhaustion (debuffs; nil = on) feeds ApplyGroupConfig's excludes.
    -- Marked only while off, so a default fingerprint stays as it was.
    if not buffSide and cfg.debuffHideExhaustion == false then
        filterPass = filterPass .. "|lx0"
    end
    -- Max Important (Important or Own) caps the important-from-others links in
    -- ApplyGroupConfig. Marked only while set, so a default fingerprint stays.
    if not buffSide and cfg.maxImportantDebuffs then
        filterPass = filterPass .. "|mi" .. cfg.maxImportantDebuffs
    end
    -- Weapon enchant cells widen the player buff row (ApplyGroupConfig).
    -- Marked only while some show, so a default fingerprint stays.
    if WeaponCells.Shown(unitToken, baseSet, cfg) then
        local n = WeaponCells.Count()
        if n > 0 then
            filterPass = filterPass .. "|we" .. n
        end
    end
    return filterPass
end

------------------------------------------------------------------------------
-- Player dispel overlay -> dispel slots
--
-- One bare slot per dispel type, filtered engine-side; each renders our overlay texture
-- pre-colored from the user palette, so the display works while auras are secret
-- without the addon ever reading dispel data. The engine shows/hides the slot button;
-- the overlay is its child. Priority when multiple debuff types are present: fixed
-- layer order (Magic on top), replacing the old first-by-scan-index behavior.
--
-- Two slot sets, one per container. The health bar and its absorb bars sit
-- inside the frame's bar clip (_barClip, SetClipsChildren), which draws its
-- whole subtree as one group at its own level: anything outside it covers every
-- bar inside it, whatever the levels. The overlay set therefore lives under the
-- health bar, where it sorts below the absorbs. The decoration set (Color
-- Custom Borders copies, Type Icon) reaches past the health bar and would be
-- clipped there, so it stays on the unit frame. Each set is built the first
-- time its feature is on: with the overlay, Color Custom Borders and the Type
-- Icon all off (the defaults), neither is.
------------------------------------------------------------------------------

local DISPEL_SLOTS = {
    {
        key = "magic",
        colorKey = "dispelColorMagic",
        fallback = { 0.349, 0.475, 1.0 },
        level = 5,
        atlas = "RaidFrame-Icon-DebuffMagic",
    },
    {
        key = "curse",
        colorKey = "dispelColorCurse",
        fallback = { 0.636, 0.0, 0.64 },
        level = 4,
        atlas = "RaidFrame-Icon-DebuffCurse",
    },
    {
        key = "disease",
        colorKey = "dispelColorDisease",
        fallback = { 0.671, 0.384, 0.098 },
        level = 3,
        atlas = "RaidFrame-Icon-DebuffDisease",
    },
    {
        key = "poison",
        colorKey = "dispelColorPoison",
        fallback = { 0.0, 0.706, 0.286 },
        level = 2,
        atlas = "RaidFrame-Icon-DebuffPoison",
    },
    {
        key = "bleed",
        colorKey = "dispelColorBleed",
        fallback = { 0.75, 0.15, 0.15 },
        level = 1,
        atlas = "RaidFrame-Icon-DebuffBleed",
    },
}
local DISPEL_TYPE_TOKENS =
    { magic = "Magic", curse = "Curse", disease = "Disease", poison = "Poison", bleed = "Bleed" }

-- Type Icon Position: the stacked icons (ApplyDispelSlotStyle) and the Growth
-- Direction row (TypeIcons.CreateRow) both draw at health+LIFT+level, over the
-- border and the texts.
local TypeIcons = { LIFT = 18, GROW = { up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT" } }

-- Use Dispel Colors: the player's Dispel Colors (profile root, the palette the
-- dispel overlay uses) as a customDispelColorMap (dispel type -> Color) for the
-- player's debuff rings, plus its fingerprint, which BuildStyle hands on as
-- style.dispelColorFP (AuraKit re-registers the ring options when it moves).
-- Memoised on the five resolved colours, its only inputs: an unchanged palette
-- hands back the same map.
do
    local memoFP, memoMap
    PlayerDispelPalette = function()
        local p = mod.UF_GetProfile and mod.UF_GetProfile()
        if not p then
            return nil, nil
        end
        local filterPass = ""
        for index = 1, #DISPEL_SLOTS do
            local slotIndex = DISPEL_SLOTS[index]
            local color = p[slotIndex.colorKey]
            filterPass = filterPass
                .. string.format(
                    "%.3f,%.3f,%.3f;",
                    (color and color.r) or slotIndex.fallback[1],
                    (color and color.g) or slotIndex.fallback[2],
                    (color and color.b) or slotIndex.fallback[3]
                )
        end
        if memoFP ~= filterPass then
            local map = {}
            for index = 1, #DISPEL_SLOTS do
                local slotIndex = DISPEL_SLOTS[index]
                local color = p[slotIndex.colorKey]
                map[DISPEL_TYPE_TOKENS[slotIndex.key]] = CreateColor(
                    (color and color.r) or slotIndex.fallback[1],
                    (color and color.g) or slotIndex.fallback[2],
                    (color and color.b) or slotIndex.fallback[3],
                    1
                )
            end
            memoFP, memoMap = filterPass, map
        end
        return memoMap, memoFP
    end
end

-- A dispel type RAID_PLAYER_DISPELLABLE can never match (bleeds via the dwarf
-- racial, poison on a shaman via Poison Cleansing Totem -- the token knows class
-- and spec dispels only) is handled here by keeping the PLAIN slot lit for such
-- a type rather than giving the by-me twin a filter that would match it: two
-- slots declaring one filter string share a single engine parse batch (see
-- AK.Filter) and both are not guaranteed to receive the aura. The rule itself
-- lives with the legacy overlay in CUI_UnitFrames_Lifecycle.lua, which needs the
-- same answer.
local function TokenBlindDispelSlot(slotKey)
    return mod.UF_TokenBlindDispel ~= nil and mod.UF_TokenBlindDispel(slotKey)
end
local GRADIENT_TEXTURE = "Interface\\AddOns\\CludesUI\\media\\textures\\gradient-tb.tga"
local GRADIENT_SHARP_TEXTURE = "Interface\\AddOns\\CludesUI\\media\\textures\\gradient-sharp.tga"

-- Copy the separator's actual texture rect, so width, pixel snapping and future
-- layout changes stay owned by the separator. Copies belong to the aura slot
-- (engine visibility); the options preview tints its separators in place.
-- Keep state outside the slot button, as with the border and outer ring copies.
local function ApplyDispelSeparatorCopy(hostFrame, status, auraKey, seam, color)
    local duplicate = status[auraKey]
    local source = seam and seam._tex
    if not (source and seam:IsShown() and source:IsShown()) then
        if duplicate then
            duplicate.host:Hide()
        end
        return
    end
    if not duplicate then
        local owner = CreateFrame("Frame", nil, hostFrame)
        local texture = owner:CreateTexture(nil, "OVERLAY", nil, 7)
        texture:SetAllPoints(owner)
        owner:SetAllPoints(source)
        duplicate = { host = owner, tex = texture, source = source }
        status[auraKey] = duplicate
    end
    if duplicate.source ~= source then
        duplicate.host:ClearAllPoints()
        duplicate.host:SetAllPoints(source)
        duplicate.source = source
    end
    duplicate.host:SetFrameStrata(seam:GetFrameStrata())
    duplicate.host:SetFrameLevel(seam:GetFrameLevel() + 1)
    duplicate.tex:SetTexture(source:GetTexture())
    duplicate.tex:SetTexCoord(source:GetTexCoord())
    duplicate.tex:SetVertexColor(color.r, color.g, color.b, 1)
    duplicate.host:Show()
end

-- applyExtra for dispel slots: builds/updates the overlay texture from the
-- style (mode, color, opacity, health refs). Runs at init and every Restyle.
local function ApplyDispelSlotStyle(btnFrame, skinData, look)
    local health = look.healthFrame
    if not health then
        return
    end

    -- Overlay set only: the decoration set never draws one. Still created on
    -- the first run (the creation window) even under Overlay None.
    if not skinData.overlay and look.fillSet then
        -- Sublevel 2+level (3..7): higher-priority types get the higher
        -- sublevel, since every slot shares one frame level (see below).
        skinData.overlay = btnFrame:CreateTexture(nil, "ARTWORK", nil, 2 + (look.level or 1))
    end
    local texture = skinData.overlay
    local color = look.color
    local alpha = (look.opacity or 100) / 100

    -- Change-guarded, stamped AFTER the call: SetFrameLevel on the slot
    -- button is denied while auras are secret (12.1 access restriction).
    -- At creation this runs inside the initializeFrame window (always
    -- legal); on later restyles the level rarely changes, and a denied
    -- attempt throws so the worker defers this key to the lift re-queue.
    -- The health bar's own level, where the legacy overlay texture lived:
    -- over the fill and below the shield and heal-absorb bars at
    -- hpBar+1, so fill/full overlays never cover them. That order only holds
    -- for the overlay set, which shares the bar clip with them (see the section
    -- header). All slots share this level; the Magic > Curse > ... priority is
    -- encoded in the overlay's ARTWORK sublevel above.
    local lvl = health:GetFrameLevel()
    if skinData.lvl ~= lvl then
        btnFrame:SetFrameLevel(lvl)
        skinData.lvl = lvl
    end

    if not texture then
        -- Decoration set: no overlay texture.
    elseif look.mode == "none" then
        -- Overlay None; the overlay set's container is hidden then anyway.
        texture:ClearAllPoints()
        texture:Hide()
    elseif look.mode == "gradient" or look.mode == "gradient_sharp" or look.mode == "gradient_reverse" then
        texture:ClearAllPoints()
        texture:Show()
        texture:SetAllPoints(health)
        texture:SetTexture(look.mode == "gradient" and GRADIENT_TEXTURE or GRADIENT_SHARP_TEXTURE)
        -- Gradient Sharp Reverse: the sharp texture flipped vertically (bottom-up).
        if look.mode == "gradient_reverse" then
            texture:SetTexCoord(0, 1, 1, 0)
        else
            texture:SetTexCoord(0, 1, 0, 1)
        end
        texture:SetVertexColor(color.r, color.g, color.b, alpha)
    elseif look.mode == "fill" then
        texture:ClearAllPoints()
        texture:Show()
        local fillTex = health.GetStatusBarTexture and health:GetStatusBarTexture()
        -- Both corners come off the fill texture so the overlay follows vertical and
        -- reverse fills; anchoring TOPLEFT to the bar only tracks left-to-right.
        if fillTex then
            texture:SetAllPoints(fillTex)
        else
            texture:SetAllPoints(health)
        end
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetColorTexture(color.r, color.g, color.b, alpha)
        texture:SetVertexColor(1, 1, 1, 1)
    else -- "full"
        texture:ClearAllPoints()
        texture:Show()
        texture:SetAllPoints(health)
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetColorTexture(color.r, color.g, color.b, alpha)
        texture:SetVertexColor(1, 1, 1, 1)
    end

    -- Color Custom Borders: a copy of the player frame's own border (same style,
    -- size, exact pixels, offsets and shifts) in this type's Dispel Color at full
    -- opacity. It rides the slot's engine visibility, so it covers the normal
    -- border only while the type is present; only the active "by me" twin carries
    -- style.customBorder. One level over the unified border's current level
    -- (frame+10, frame+20 over an inside 3D portrait, frame-1 under Show Behind).
    -- Every type's copy shares that level, so two types present at once stack in
    -- no fixed order, as on Raid Frames. The secret-safe renderer needs no size
    -- reads and no scripts (scripts never run under a slot button). State lives
    -- in d, never on the button.
    local callback = look.customBorder
    local uf = look.unitFrame
    local ub = callback and uf and uf.unifiedBorder
    if ub then
        if not skinData.ufCbHost then
            -- Published only once anchored: a denied write leaves no half-built
            -- host, and the next restyle simply tries again.
            local owner = CreateFrame("Frame", nil, btnFrame)
            owner:SetAllPoints(ub)
            skinData.ufCbState = {}
            skinData.ufCbHost = owner
        end
        -- Armed before the first write on the host: a draw that throws partway
        -- still leaves the off branch able to clear whatever it drew.
        skinData.ufCbOn = true
        skinData.ufCbHost:SetFrameLevel(ub:GetFrameLevel() + 1)
        CludesUI.ApplySecretSafeBorderStyle(
            skinData.ufCbHost,
            skinData.ufCbState,
            callback.size,
            color.r,
            color.g,
            color.b,
            1,
            callback.tex,
            callback.offX,
            callback.offY,
            callback.shX,
            callback.shY,
            "unitframes",
            callback.size,
            nil,
            callback.px
        )
        skinData.ufCbHost:Show()
    elseif skinData.ufCbOn then
        -- Size 0 hides every piece and drops the UI-scale re-apply registration.
        CludesUI.ApplySecretSafeBorderStyle(skinData.ufCbHost, skinData.ufCbState, 0, 0, 0, 0, 0, "solid")
        skinData.ufCbHost:Hide()
        -- Disarmed only once the hide landed: a denied call re-runs this at the lift.
        skinData.ufCbOn = nil
    end

    -- The portrait's Outer Ring (its texture on the backdrop, backdrop._outerRing)
    -- gets the same copy while it shows: the ring's own art laid on the ring's own
    -- rect (anchor-derived, so size and position follow it), on a holder over the
    -- portrait backdrop (a detached backdrop sits at frame+15, over the unified
    -- border and its copy): one level up, or four with Show Icon on Portrait,
    -- whose cast icon lifts the ring to the backdrop's +3 while it shows
    -- (CUI_UnitFrames_Castbar.lua). Set here once per restyle, never per cast:
    -- a slot child's level cannot be written while auras are secret.
    local edge = ub and uf.Portrait and uf.Portrait.backdrop
    local ring = edge and edge._outerRing
    if ring and ring:IsShown() and edge:IsShown() then
        if not skinData.ufRingHost then
            local owner = CreateFrame("Frame", nil, btnFrame)
            local rt = owner:CreateTexture(nil, "OVERLAY", nil, 7)
            rt:SetAllPoints(owner)
            skinData.ufRingTex = rt
            skinData.ufRingHost = owner
        end
        local owner = skinData.ufRingHost
        if skinData.ufRingAnchor ~= ring then
            owner:ClearAllPoints()
            owner:SetAllPoints(ring)
            skinData.ufRingAnchor = ring
        end
        skinData.ufRingOn = true
        owner:SetFrameLevel(edge:GetFrameLevel() + (look.ringLift or 1))
        local art = ring:GetTexture()
        if skinData.ufRingArt ~= art then
            skinData.ufRingTex:SetTexture(art)
            skinData.ufRingArt = art
        end
        skinData.ufRingTex:SetVertexColor(color.r, color.g, color.b, 1)
        owner:Show()
    elseif skinData.ufRingOn then
        skinData.ufRingHost:Hide()
        skinData.ufRingOn = nil
    end

    -- Only enabled, displayed separators get copies. The inactive by-me twin
    -- and disabled custom-border mode clear any copies they previously drew.
    if ub or skinData.ufPowerSeam or skinData.ufPortraitSeam then
        ApplyDispelSeparatorCopy(btnFrame, skinData, "ufPowerSeam", ub and uf.Power and uf.Power._pbSeam, color)
        ApplyDispelSeparatorCopy(btnFrame, skinData, "ufPortraitSeam", ub and uf._portraitSeparator, color)
    end

    -- Type Icon Position: the type's icon on a corner of the health bar (Raid
    -- Frames parity). Only the live twin carries style.icon. health+LIFT+level
    -- (frame+21..+25) draws it over the border and the texts (frame+20), in
    -- the Magic > ... > Bleed order, at most level with the raid marker.
    local ic = look.icon
    if ic then
        if not skinData.ufIconHost then
            local owner = CreateFrame("Frame", nil, btnFrame)
            local texture = owner:CreateTexture(nil, "ARTWORK")
            texture:SetAllPoints(owner)
            skinData.ufIconTex = texture
            skinData.ufIconHost = owner
        end
        local owner = skinData.ufIconHost
        owner:SetFrameLevel(health:GetFrameLevel() + TypeIcons.LIFT + (look.level or 1))
        skinData.ufIconTex:SetAtlas(ic.atlas)
        owner:SetSize(ic.size, ic.size)
        owner:ClearAllPoints()
        owner:SetPoint(ic.corner, health, ic.corner, ic.offX, ic.offY)
        owner:Show()
    elseif skinData.ufIconHost then
        skinData.ufIconHost:Hide()
    end
end

-- Type Icon Position Growth Direction ("none" keeps the stacked slot icons):
-- the icons move to a row of their own, one engine group per type in DISPEL_SLOTS
-- order (Magic first), each capped at one icon, so every type present shows once
-- and the engine packs the shown ones from the Type Icon Position point. A cell
-- draws its type's atlas, as the stacked icons do; no aura data is read. "Only
-- Dispellable by You" picks each type's plain or by-me group, as the slot twins.
function TypeIcons.StyleKey(slotKey)
    return "uf:player:dispelicon:" .. slotKey
end

-- applyExtra: the cell's icon host, made on the first run (the creation window,
-- the only one that may anchor to the cell), with its type's art at the stacked
-- icons' level.
function TypeIcons.ApplyCell(btnFrame, skinData, look)
    local owner = skinData.ufRowIconHost
    if not owner then
        owner = CreateFrame("Frame", nil, btnFrame)
        owner:SetAllPoints(btnFrame)
        owner:EnableMouse(false)
        skinData.ufRowIconTex = owner:CreateTexture(nil, "ARTWORK")
        skinData.ufRowIconTex:SetAllPoints(owner)
        skinData.ufRowIconHost = owner
    end
    skinData.ufRowIconTex:SetAtlas(look.atlas)
    local health = look.healthFrame
    if health then
        owner:SetFrameLevel(health:GetFrameLevel() + TypeIcons.LIFT + (look.level or 1))
    end
end

-- Declared at cap 0, so no cell exists until a debuff of its type shows.
function TypeIcons.CreateRow(widget, record)
    if record.dispelIconsBuilt then
        return
    end
    local boxHolder = record.dispelIcons
    if not boxHolder then
        boxHolder = AK.CreateContainerShell(widget, { point = { "CENTER", widget, "CENTER" } })
        record.dispelIcons = boxHolder
    end
    for index = 1, #DISPEL_SLOTS do
        local slotIndex = DISPEL_SLOTS[index]
        local candidate = { includeDispelTypes = { [DISPEL_TYPE_TOKENS[slotIndex.key]] = true } }
        for t = 1, 2 do
            local auraKey = (t == 1) and slotIndex.key or (slotIndex.key .. "_byme")
            if not boxHolder:HasAuraGroup(auraKey) then
                AK.AddGroupToContainer(boxHolder, {
                    key = auraKey,
                    maxFrameCount = 0,
                    candidateFilters = candidate,
                    filter = (t == 1) and { "HARMFUL" } or { "HARMFUL", "RAID_PLAYER_DISPELLABLE" },
                    style = TypeIcons.StyleKey(slotIndex.key),
                })
            end
        end
    end
    AK.FinishContainer(boxHolder, "player")
    record.dispelIconsBuilt = true
end

-- Anchors the row on the Type Icon Position point, grows it, and lights each
-- type's live group at one icon.
function TypeIcons.LayoutRow(widget, record, profile)
    local boxHolder, health = record.dispelIcons, widget.Health
    if not (boxHolder and health) then
        return
    end
    local anchorPoint = (profile.dispelIconPosition or "right"):upper()
    local grow = TypeIcons.GROW[profile.dispelIconGrowth or "none"] or "LEFT"
    local size = profile.dispelIconSize or 16
    local gap = CludesUI.PP.FromPixels(1)
    boxHolder:ClearAllPoints()
    boxHolder:SetPoint(anchorPoint, health, anchorPoint, profile.dispelIconOffsetX or 0, profile.dispelIconOffsetY or 0)
    AK.SetContainerAnchor(boxHolder, anchorPoint)
    local vertical = grow == "UP" or grow == "DOWN"
    local gX = vertical and (anchorPoint:find("LEFT") and "RIGHT" or "LEFT") or grow
    local gY = vertical and grow or (anchorPoint:find("BOTTOM") and "UP" or "DOWN")
    AK.SetContainerRowWidth(boxHolder, vertical and (size + 0.4) or nil)
    AK.SetContainerGrowth(boxHolder, FlowDir(gX), FlowDir(gY))
    local layout = { elementWidth = size, elementHeight = size, elementSpacing = gap, lineSpacing = gap }
    local byMe = profile.dispelOverlayByMe == true
    for index = 1, #DISPEL_SLOTS do
        local auraKey = DISPEL_SLOTS[index].key
        local byMeLive = byMe and not TokenBlindDispelSlot(auraKey)
        boxHolder:SetAuraGroupLayout(auraKey, layout)
        boxHolder:SetAuraGroupLayout(auraKey .. "_byme", layout)
        AK.SetGroupCap(boxHolder, auraKey, byMeLive and 0 or 1)
        AK.SetGroupCap(boxHolder, auraKey .. "_byme", byMeLive and 1 or 0)
    end
end

-- `fill` picks the overlay set's key, otherwise the decoration set's.
local function DispelStyleKey(slotKey, fillTex)
    return (fillTex and "uf:player:dispelfill:" or "uf:player:dispel:") .. slotKey
end

-- Color Custom Borders is live: the toggle, over a custom border (runtime twin
-- of the options gate; a saved true stands down under a stock style, a Solid
-- Border Style or Border Size 0).
local function DispelCustomBorderOn(profile)
    return profile.dispelCustomBorder == true and mod.UF_CustomBorderOn(profile.player)
end

-- Returns decoration shown, overlay shown. The decoration set shows while
-- Color Custom Borders or the type icon needs it, the overlay set while an
-- overlay mode is picked; off (the default), a container stays hidden and
-- parses nothing.
local function DispelSlotsShown(profile)
    local icons = profile.showDispelIcons == true
    local grow = icons and (profile.dispelIconGrowth or "none") ~= "none"
    return DispelCustomBorderOn(profile) or (icons and not grow), (profile.dispelOverlay or "none") ~= "none", grow
end

local function BuildDispelStyles(widget)
    local p = mod.UF_GetProfile and mod.UF_GetProfile()
    if not p then
        return false
    end
    local modeName = p.dispelOverlay or "none"
    -- "Only Dispellable by You": slot filters are fixed at declaration and
    -- containers are never swapped (engine buttons leak), so BOTH filter
    -- variants exist as slots from creation and the INACTIVE variant is
    -- styled to opacity 0. Toggling the option only restyles.
    local byMe = p.dispelOverlayByMe == true
    local op = p.dispelOverlayOpacity or 100
    -- Color Custom Borders: the player frame border's own ApplyBorderStyle
    -- inputs, so each type's copy matches it (read-only, shared by the slots).
    local customBorder
    if DispelCustomBorderOn(p) then
        local cfg = p.player
        local bs = cfg.borderSize or 1
        local btex = cfg.borderTexture
        customBorder = {
            size = bs,
            tex = btex,
            offX = cfg.borderTextureOffset,
            offY = cfg.borderTextureOffsetY,
            shX = cfg.borderTextureShiftX,
            shY = cfg.borderTextureShiftY,
            px = CludesUI.BorderPx(cfg.borderSizePx, bs, btex),
        }
    end
    -- The Outer Ring copy's lift over the portrait backdrop (ApplyDispelSlotStyle).
    local ringLift = (customBorder and mod.UF_CastIconOnPortrait("player", p.player)) and 4 or 1
    -- Type Icon Position: one geometry for every type's icon (its art per slot).
    -- A Growth Direction moves the icons to their own row (TypeIcons.CreateRow).
    local iconCorner = p.showDispelIcons == true
            and (p.dispelIconGrowth or "none") == "none"
            and (p.dispelIconPosition or "right"):upper()
        or nil
    local rowSize = p.dispelIconSize or 16
    for index = 1, #DISPEL_SLOTS do
        local slotIndex = DISPEL_SLOTS[index]
        -- A type the engine token can never match keeps using the PLAIN slot in
        -- "by me" mode: its by-me twin stays dark and would swallow the setting
        -- entirely.
        local tokenBlind = TokenBlindDispelSlot(slotIndex.key)
        local byMeLive = byMe and not tokenBlind
        local colour = p[slotIndex.colorKey]
        local color = {
            r = colour and colour.r or slotIndex.fallback[1],
            g = colour and colour.g or slotIndex.fallback[2],
            b = colour and colour.b or slotIndex.fallback[3],
        }
        local iconTex = iconCorner
                and {
                    atlas = slotIndex.atlas,
                    corner = iconCorner,
                    size = p.dispelIconSize or 16,
                    offX = p.dispelIconOffsetX or 0,
                    offY = p.dispelIconOffsetY or 0,
                }
            or nil
        -- Plain twin, then the by-me twin. The overlay, the border copy and the
        -- type icon ride the live twin only; the inactive one draws nothing.
        for t = 1, 2 do
            local auraKey = (t == 1) and slotIndex.key or (slotIndex.key .. "_byme")
            local live = (t == 2) == byMeLive
            AK.styles[DispelStyleKey(auraKey)] = {
                width = 1,
                height = 1,
                noRegions = true,
                mode = "none",
                color = color,
                level = slotIndex.level,
                healthFrame = widget.Health,
                unitFrame = widget,
                customBorder = live and customBorder or nil,
                ringLift = ringLift,
                icon = live and iconTex or nil,
                applyExtra = ApplyDispelSlotStyle,
            }
            AK.styles[DispelStyleKey(auraKey, true)] = {
                width = 1,
                height = 1,
                noRegions = true,
                fillSet = true,
                mode = modeName,
                color = color,
                opacity = live and op or 0,
                level = slotIndex.level,
                healthFrame = widget.Health,
                applyExtra = ApplyDispelSlotStyle,
            }
        end
        -- The Growth Direction row's cells for this type (both twins).
        AK.styles[TypeIcons.StyleKey(slotIndex.key)] = {
            width = rowSize,
            height = rowSize,
            noRegions = true,
            noTooltips = true,
            atlas = slotIndex.atlas,
            level = slotIndex.level,
            healthFrame = widget.Health,
            applyExtra = TypeIcons.ApplyCell,
        }
    end
    return DispelSlotsShown(p)
end

-- One set: the decoration set (fill false) on the unit frame, or the overlay
-- set (fill true) under the health bar, inside the bar clip with the absorbs
-- (section header). Built once and kept; `<field>Adds` counts the set's
-- completed slot declarations, so a resumed build skips what already landed
-- instead of re-declaring existing slot keys.
local function CreateDispelSet(widget, record, fillTex)
    local field = fillTex and "dispelFill" or "dispel"
    if record[field .. "Built"] then
        return
    end
    local addsField = field .. "Adds"
    local boxHolder = record[field]
    if not boxHolder then
        boxHolder = AK.CreateContainerShell(fillTex and widget.Health or widget, {
            point = { "CENTER", widget, "CENTER" },
        })
        -- Stashed BEFORE the slot adds so a watchdog-killed build resumes on
        -- the same container instead of birthing a second one.
        record[field] = boxHolder
    end

    local n = 0
    for index = 1, #DISPEL_SLOTS do
        local slotIndex = DISPEL_SLOTS[index]
        local function ParkSlot(slotButton)
            -- Park the slot button on the health bar center (the overlay textures
            -- anchor to the health bar independently). Anchored HERE, inside the
            -- creation window: SetPoint on the returned button is denied while
            -- auras are secret (12.1 button access restriction), and this build
            -- path runs on in-instance reloads.
            slotButton:SetPoint("CENTER", widget.Health or widget, "CENTER")
        end
        n = n + 1
        if n > (record[addsField] or 0) then
            AK.AddSlotToContainer(boxHolder, {
                key = slotIndex.key,
                filter = { "HARMFUL" },
                candidateFilters = { includeDispelTypes = { [DISPEL_TYPE_TOKENS[slotIndex.key]] = true } },
                style = DispelStyleKey(slotIndex.key, fillTex),
                extraInit = ParkSlot,
            })
            record[addsField] = n
        end
        -- "Only Dispellable by You" variant: identical slot with the engine
        -- by-me filter token added. Declared upfront -- slot filters cannot
        -- change after declaration -- and mutually exclusive with the plain
        -- slot via its style (BuildDispelStyles blanks the inactive one).
        n = n + 1
        if n > (record[addsField] or 0) then
            AK.AddSlotToContainer(boxHolder, {
                key = slotIndex.key .. "_byme",
                filter = { "HARMFUL", "RAID_PLAYER_DISPELLABLE" },
                candidateFilters = { includeDispelTypes = { [DISPEL_TYPE_TOKENS[slotIndex.key]] = true } },
                style = DispelStyleKey(slotIndex.key .. "_byme", fillTex),
                extraInit = ParkSlot,
            })
            record[addsField] = n
        end
    end
    AK.FinishContainer(boxHolder, "player")
    record[field .. "Built"] = true
end

-- Builds a set the first time its feature is on (decorated from the current
-- styles: callers run BuildDispelStyles first), then shows each built set
-- only while its feature is on; a hidden container parses nothing.
local function SyncDispelSets(widget, record, decorShown, fillShown, iconsShown)
    if decorShown then
        CreateDispelSet(widget, record, false)
    end
    if fillShown then
        CreateDispelSet(widget, record, true)
    end
    if iconsShown and not record.dispelIconsBuilt then
        TypeIcons.CreateRow(widget, record)
        local p = mod.UF_GetProfile and mod.UF_GetProfile()
        if p then
            TypeIcons.LayoutRow(widget, record, p)
        end
    end
    if record.dispel then
        record.dispel:SetShown(decorShown and true or false)
    end
    if record.dispelFill then
        record.dispelFill:SetShown(fillShown and true or false)
    end
    if record.dispelIcons then
        record.dispelIcons:SetShown(iconsShown and true or false)
    end
end

local function DispelFP(profile, widget)
    -- The poison capability is a talent (Poison Cleansing Totem), so it rides
    -- the fingerprint; race can't change mid-session.
    -- Color Custom Borders copies the frame border, so while it is on every input
    -- the copy reads counts too: the border keys; the strata (a strata change
    -- re-stacks child levels); the portrait mode and side (an inside 3D portrait
    -- lifts the unified border to frame+20); the portrait and Outer Ring keys
    -- that decide whether the ring copy shows and which art it takes; and Show
    -- Icon on Portrait, which lifts the ring copy over the cast icon's overlay.
    -- Separator
    -- visibility and orientation changes must restyle their copies too; their
    -- dimensions follow the source texture anchors without a restyle.
    local cfg = profile.player
    local callback = profile.dispelCustomBorder == true and cfg ~= nil
    local filterPass = FP(
        profile.dispelOverlay,
        profile.dispelOverlayOpacity,
        profile.dispelOverlayByMe == true,
        TokenBlindDispelSlot("poison") and 1 or 0,
        CK(profile.dispelColorMagic),
        CK(profile.dispelColorCurse),
        CK(profile.dispelColorDisease),
        CK(profile.dispelColorPoison),
        CK(profile.dispelColorBleed),
        callback,
        callback
                and FP(
                    cfg.borderSize,
                    cfg.borderTexture,
                    cfg.borderSizePx,
                    cfg.borderTextureOffset,
                    cfg.borderTextureOffsetY,
                    cfg.borderTextureShiftX,
                    cfg.borderTextureShiftY,
                    cfg.borderBehind,
                    profile.frameStrata,
                    cfg.frameStrata,
                    cfg.portraitMode,
                    cfg.portraitSide,
                    profile.portraitStyle,
                    cfg.portraitStyle,
                    cfg.showPortrait,
                    cfg.portraitSize,
                    cfg.detachedPortraitShape,
                    cfg.detachedPortraitOuterRing,
                    cfg.detachedPortraitOuterRingScale,
                    cfg.borderPowerSeam,
                    cfg.powerPosition,
                    cfg.powerHeight,
                    cfg.portraitSeparator,
                    mod.UF_CastIconOnPortrait("player", cfg)
                )
            or false
    )
    -- Type Icon Position: marked only while on, so an off print stays as it was.
    if profile.showDispelIcons == true then
        filterPass = filterPass
            .. "|ti|"
            .. FP(
                profile.dispelIconPosition,
                profile.dispelIconSize,
                profile.dispelIconOffsetX,
                profile.dispelIconOffsetY,
                profile.dispelIconGrowth
            )
    end
    -- The health bar's level: the slot buttons copy it only on a restyle, and
    -- the overlay must stay under the absorbs at hpBar+1.
    local health = widget and widget.Health
    if health then
        filterPass = filterPass .. "|hl|" .. health:GetFrameLevel()
    end
    return filterPass
end

local function ReloadDispelSlots(widget, record)
    -- The build's dispel stage makes the styles; nothing to reload before it.
    if not record.dispelDone then
        return
    end
    local p = mod.UF_GetProfile and mod.UF_GetProfile()
    if not p then
        return
    end
    local val = DispelFP(p, widget)
    if ufFP.dispel ~= val then
        ufFP.dispel = val
        BuildDispelStyles(widget)
        for index = 1, #DISPEL_SLOTS do
            local auraKey = DISPEL_SLOTS[index].key
            AK.RestyleSoon(DispelStyleKey(auraKey))
            AK.RestyleSoon(DispelStyleKey(auraKey .. "_byme"))
            AK.RestyleSoon(DispelStyleKey(auraKey, true))
            AK.RestyleSoon(DispelStyleKey(auraKey .. "_byme", true))
            AK.RestyleSoon(TypeIcons.StyleKey(auraKey))
        end
        if record.dispelIconsBuilt then
            TypeIcons.LayoutRow(widget, record, p)
        end
    end
    -- A set turned on for the first time is built here, from the styles just
    -- made current.
    SyncDispelSets(widget, record, DispelSlotsShown(p))
end

-- Options-panel poke (via ns.UpdatePlayerDispelOverlay): re-run the
-- fingerprinted dispel reload for the live player frame so dropdown/cog
-- edits apply without waiting for a full container pass.
function mod.UF_ReloadPlayerDispelSlots()
    local record = registry.player
    if record and record.frame and not record.building then
        ReloadDispelSlots(record.frame, record)
    end
end

-- The poison capability behind UF_TokenBlindDispel is a talent (Poison
-- Cleansing Totem). Talent edits fire no spec event, and IsPlayerSpell can lag
-- the trait event itself (the spellbook grant lands with SPELLS_CHANGED), so
-- shamans re-check on both; the reload runs only when the cached capability
-- actually flips. No combat gate: the restyle routes through AK.RestyleSoon,
-- whose worker defers secrecy-denied writes to the restriction-lift re-queue.
do
    local _, classFile = UnitClass("player")
    if classFile == "SHAMAN" then
        local eventFrame = CreateFrame("Frame")
        eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
        eventFrame:RegisterEvent("SPELLS_CHANGED")
        eventFrame:SetScript("OnEvent", function()
            if mod.UF_RefreshPoisonTotem and mod.UF_RefreshPoisonTotem() then
                mod.UF_ReloadPlayerDispelSlots()
            end
        end)
    end
end

-- Boss preview (fake auras) suppresses the real containers; ReloadFrames
-- restores them when the preview ends.
function mod.UF_HideAuraContainers(widget)
    for _unitKey, record in pairs(registry) do
        if record.frame == widget then
            if record.buffs then
                record.buffs:Hide()
            end
            if record.debuffs then
                record.debuffs:Hide()
            end
            -- Hidden outside the fingerprinted flow: the next reload must
            -- re-drive visibility even if no setting changed.
            record.previewHid = true
            return
        end
    end
end

function mod.UF_ReloadAuraContainers(widget, unitToken)
    local cfg = SettingsFor(unitToken)
    local record = registry[unitToken]
    if not cfg or not record then
        return
    end
    -- Still under construction by the deferred stepper: its final stage
    -- runs this reload once the containers are complete.
    if record.building then
        return
    end

    if unitToken:match("^boss") and mod._bossPreviewActive then
        if record.buffs then
            record.buffs:Hide()
        end
        if record.debuffs then
            record.debuffs:Hide()
        end
        record.previewHid = true
        return
    end

    local font = (CludesUI.GetFontPath("unitFrames")) or ""
    -- Containers hidden outside the fingerprinted flow (boss preview) must
    -- re-drive anchor/config/visibility even with matching fingerprints.
    -- cfgDirty: the degradation-recovery lane below (cinematic/faction/
    -- vehicle) needs the same force -- re-setting candidates is what makes
    -- the engine re-honor spell-ID filters after an assistability flip, and
    -- the fingerprints never change across one.
    local forceCfg = (record.previewHid or record.cfgDirty) and true or false
    record.previewHid = nil
    record.cfgDirty = nil

    local anyOn = false
    for baseSet, field in pairs({ HELPFUL = "buffs", HARMFUL = "debuffs" }) do
        local auraKey = StyleKey(unitToken, baseSet)
        local state = ufFP[auraKey]
        if not state then
            state = {}
            ufFP[auraKey] = state
        end

        -- Restyle only when the built style actually differs; the deferred
        -- time-sliced restyler spreads the button decoration work out.
        local look = BuildStyle(unitToken, baseSet, cfg, record.frame)
        local styleV = StyleTableFP(look, font)
        if state.style ~= styleV then
            state.style = styleV
            AK.styles[auraKey] = look
            AK.RestyleSoon(auraKey)
        end
        if baseSet == "HELPFUL" and unitToken ~= "player" then
            PurgeGlow.Register(unitToken, cfg, record.frame, font)
            PurgeGlow.SetWatch(unitToken, PurgeGlow.On(unitToken, cfg))
        end

        -- Groups are ADDITIVE and the container is NEVER swapped: a changed chain
        -- declares any missing groups on the existing container (combat-legal --
        -- probe T1/T1b), and the config pass zeroes whatever fell out of the active
        -- set. The old swap path permanently leaked a 10-button batch per group per
        -- toggle (engine frames are never freed).
        local filterChain = ChainFor(unitToken, baseSet, cfg)
        local sig = ChainSignature(filterChain)
        local force = forceCfg
        local boxHolder = record[field]
        local declared = (record.groups and record.groups[field]) or {}
        -- An element that is off declares nothing and leaves its signature
        -- unstamped, so the first pass that sees it on declares what its chain
        -- needs (then the config pass below shows it, which registers its
        -- UNIT_AURA). Additive declaration requires the REAL registry:
        -- declaring into a fallback table would lose track and double-declare
        -- next change.
        local enabled = SideOn(unitToken, baseSet, cfg)
        if enabled then
            anyOn = true
        end
        if enabled and record.sig[field] ~= sig and boxHolder and record.groups then
            -- The plain catch-all only for an empty chain: there it is the
            -- group that shows (a non-player buff element, see
            -- ApplyGroupConfig), or, showing nothing, it still gives the
            -- container the layout aspect the engine requires before a debuff
            -- container may ride the buff container (Anchor Buffs with
            -- Debuffs). A chain with links never shows it (Show All's own
            -- "all" link is declared with the chain). Purgeable Buff Glow
            -- splits a hostile unit's buffs into links, so that row declares
            -- its catch-all on the first friendly unit (once per session).
            if not declared.all and #filterChain == 0 then
                DeclareElementGroup(boxHolder, declared, auraKey, "all", { baseSet }, nil)
            end
            for index = 1, #filterChain do
                local c = filterChain[index]
                if not declared[c.key] then
                    local sk = auraKey
                    if c.glow then
                        sk = PurgeGlow.StyleKey(unitToken)
                    end
                    DeclareElementGroup(boxHolder, declared, sk, c.key, c.tokens, c.cand)
                end
            end
            -- Stamped once every group the chain needs is declared: a pass an
            -- error cut short declares the rest on the next one.
            record.sig[field] = sig
            force = true
        end

        if boxHolder then
            local cfgV = CfgFP(unitToken, baseSet, cfg, widget)
            if force or state.cfg ~= cfgV then
                state.cfg = cfgV
                AnchorContainer(boxHolder, widget, unitToken, baseSet, cfg, record.buffs) -- self-skips on anchor "none"
                ApplyGroupConfig(boxHolder, unitToken, baseSet, cfg, filterChain, declared)
            end
        end
    end

    if unitToken == "player" then
        ReloadDispelSlots(widget, record)
    elseif unitToken == "pet" then
        -- Re-parse on pet swaps only while the pet's CludesUI frame shows
        -- buffs or debuffs.
        PetSwap.Sync(anyOn and mod.GetUnitFrameSource("pet") == "cui")
    end
end

-- Resource-stack re-anchor (event-free). Bottom-anchored player auras reserve the
-- Resource Bars stack hanging below the frame (power / class resource / shapeshift
-- mana). Its footprint only changes on build / spec / form / expand / shift / options
-- -- all of which converge on Resource Bars' BuildBars(). Rather than have UnitFrames
-- watch a pile of game events, Resource Bars ARMS this one-shot throttle at the end of
-- BuildBars via CludesUI.UF_RequestResourceReanchor(). Arming reads no geometry; the
-- throttle's OnUpdate re-anchors once on the next frame, after the build has settled,
-- then disarms. Mirrors the reloadThrottle pattern in CUI_UnitFrames_OptionsSetup.lua. Zero cost when idle:
-- no registered events, and non-bottom-anchored players never arm anything. Per-bar
-- VISIBILITY modes (combat/target/group alpha) are intentionally NOT handled -- the
-- footprint (ERB_PlayerStackBars) is predicate-based, so alpha toggles do not move it.
-- The WoW Forever form power bar (CUI_UnitFrames_ForeverFormBar.lua) arms it too, when
-- it shows, hides or is laid out again.
do
    local function BottomAnchored(a)
        return a == "bottomleft" or a == "bottomright"
    end
    local function PlayerWantsStackReserve()
        if not (CludesUI.ERB_PlayerStackBars or mod.UF_ForeverFormBarShown) then
            return false
        end
        local cfg = SettingsFor("player")
        return cfg ~= nil and (BottomAnchored(cfg.debuffAnchor) or BottomAnchored(cfg.buffAnchor))
    end
    -- Cheap re-anchor: only the two player containers' SetPoint offsets change when the
    -- footprint moves, so re-run just AnchorContainer (reanchorOnly -- folds in
    -- ResourceStackBelowFrame, skips style/chain/group), never a full reload. Buffs first
    -- so a merged debuff rides a positioned buff container. Self-skips non-bottom anchors.
    local function reanchorPlayer()
        local record = registry.player
        local widget = record and record.frame
        if not widget or record.building then
            return
        end
        local cfg = SettingsFor("player")
        if not cfg then
            return
        end
        if record.buffs then
            AnchorContainer(record.buffs, widget, "player", "HELPFUL", cfg, record.buffs, true)
        end
        if record.debuffs then
            AnchorContainer(record.debuffs, widget, "player", "HARMFUL", cfg, record.buffs, true)
        end
    end
    local queued = false
    local throttle = CreateFrame("Frame")
    throttle:Hide()
    throttle:SetScript("OnUpdate", function(self)
        self:Hide() -- disarm FIRST so we fire exactly once per arm (an error
        queued = false -- below then cannot latch it)
        reanchorPlayer()
    end)
    -- Armed (by Resource Bars' BuildBars, or anyone) when the footprint may have changed.
    -- Coalesces many arms in one frame into a single re-anchor; gated so idle/irrelevant
    -- configs do nothing and register nothing.
    function CludesUI.UF_RequestResourceReanchor()
        if queued or not PlayerWantsStackReserve() then
            return
        end
        queued = true
        throttle:Show()
    end
end

-- Dynamic unit tokens ("target", "focus", "bossN") re-resolve silently: the
-- engine only re-parses on UNIT_AURA or show/hide, so a target swap while the
-- frame stays shown would display the previous unit's auras. Blizzard's own
-- container exposes UpdateAllAuras for exactly this; poke it on unit changes.
local function RefreshUnit(unitKey)
    local record = registry[unitKey]
    if not record or record.building then
        return
    end
    if record.buffs then
        record.buffs:UpdateAllAuras()
    end
    if record.debuffs then
        record.debuffs:UpdateAllAuras()
    end
    if record.dispel then
        record.dispel:UpdateAllAuras()
    end
    if record.dispelFill then
        record.dispelFill:UpdateAllAuras()
    end
    if record.dispelIcons then
        record.dispelIcons:UpdateAllAuras()
    end
end

-- Pet swap (a different pet summoned while one is out): the frame stays shown
-- and the token stays "pet", so the containers see no show/hide and keep the
-- old pet's auras until a full re-parse (Blizzard's own pet frame re-reads its
-- auras on every UNIT_PET). UpdateAllAuras is a dirty mark the container
-- drains once on its next visible frame, so a burst costs one parse.
-- Registered only while the pet's reload holds it on.
function PetSwap.Sync(enabled)
    enabled = enabled and true or false
    if PetSwap.on == enabled then
        return
    end
    PetSwap.on = enabled
    local frame = PetSwap.frame
    if enabled then
        if not frame then
            frame = CreateFrame("Frame")
            frame:SetScript("OnEvent", function()
                RefreshUnit("pet")
            end)
            PetSwap.frame = frame
        end
        frame:RegisterUnitEvent("UNIT_PET", "player")
    elseif frame then
        frame:UnregisterEvent("UNIT_PET")
    end
end

-- Degradation recovery for the PLAYER frame's containers: cinematics
-- (UNIT_FACTION fires for every unit at start+end while assistability
-- briefly drops; UNIT_FLAGS does NOT fire -- authors-channel etrace,
-- 2026-08-13), addon-cancelled cinematics (CINEMATIC_STOP's hide/re-show
-- can parse mid-degradation), and vehicles (assistability stays down for
-- the whole ride) all silently disable spell-ID candidate filters
-- engine-side -- the player buff chain's Extra Spells / filter includes
-- degrade to the FULL buff set, and no aura edge is guaranteed to follow
-- the restore. Same trigger set as the PAB lane and the RF assist gate.
-- Recovery = BOTH levers, coalesced one tick after each edge: a forced
-- config pass (cfgDirty -- re-setting candidates is what makes the engine
-- re-honor them) plus a reparse. Cost while idle: a handful of registered
-- events that fire only on cinematics/faction flips/vehicle transitions.
do
    local queued = false
    local wid = CreateFrame("Frame")
    wid:RegisterUnitEvent("UNIT_FACTION", "player")
    wid:RegisterEvent("CINEMATIC_STOP")
    wid:RegisterUnitEvent("UNIT_ENTERING_VEHICLE", "player")
    wid:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    wid:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    wid:SetScript("OnEvent", function(_, evt)
        if queued then
            return
        end
        queued = true
        C_Timer.After(0, function()
            queued = false
            -- The player's own faction/PvP flip changes whether the target and
            -- focus can be assisted: re-check the Tracked Auras gate (a no-op
            -- unless that unit holds include groups and the answer flipped).
            IncGate.Apply("target")
            IncGate.Apply("focus")
            PurgeGlow.Check("target")
            PurgeGlow.Check("focus")
            local record = registry.player
            if not record or record.building then
                return
            end
            record.cfgDirty = true
            if record.frame and mod.UF_ReloadAuraContainers then
                mod.UF_ReloadAuraContainers(record.frame, "player")
            end
            RefreshUnit("player")
        end)
    end)
end

-- The 12.1 ping-receiver strip workaround lived here until build 68914
-- fixed SendUnitPing upstream (PingManager securecopys the receiver info at
-- the secure boundary); contextual pings on our frames are legal again.

local unitWatcher = CreateFrame("Frame")
unitWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
unitWatcher:RegisterEvent("PLAYER_FOCUS_CHANGED")
unitWatcher:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
unitWatcher:SetScript("OnEvent", function(_, evt)
    -- The Tracked Auras gate first (a friendly/hostile flip re-configures the
    -- debuff groups), then the one re-parse.
    if evt == "PLAYER_TARGET_CHANGED" then
        IncGate.Apply("target", true)
        PurgeGlow.Check("target", true)
        RefreshUnit("target")
    elseif evt == "PLAYER_FOCUS_CHANGED" then
        IncGate.Apply("focus", true)
        PurgeGlow.Check("focus", true)
        RefreshUnit("focus")
    else
        for index = 1, 5 do
            RefreshUnit("boss" .. index)
        end
    end
end)

-- Called by the main file at the end of every real (throttled) reload pass.
-- A direct call, not a wrap: ns.ReloadFrames is a throttle-arming stub that
-- gets (re)assigned during login setup, which makes wrap timing unreliable.
function mod.UF_ReloadAllAuraContainers()
    for unitKey, record in pairs(registry) do
        if record.frame then
            mod.UF_ReloadAuraContainers(record.frame, unitKey)
        end
    end
end

-- Colors page edits (swatches, darken, resets, profile switches) all end in
-- ApplyColorsToOUF. Once a Class-mode purge glow was built, a changed class
-- colour re-runs the reload; the purge print carries the colour, so only
-- that glow style restyles. Calls in one frame (a profile switch can make
-- two) collapse into one check on the next frame: the flush frame stays
-- hidden until a call and hides itself before working.
do
    local flush = CreateFrame("Frame")
    flush:Hide()
    flush:SetScript("OnUpdate", function(self)
        self:Hide()
        local r0 = PurgeGlow.ccR
        if r0 == nil then
            return
        end
        local red, green, blue = CludesUI.Glows.ResolveColor("class")
        if red ~= r0 or green ~= PurgeGlow.ccG or blue ~= PurgeGlow.ccB then
            mod.UF_ReloadAllAuraContainers()
        end
    end)
    hooksecurefunc(CludesUI, "ApplyColorsToOUF", function()
        if PurgeGlow.ccR ~= nil then
            flush:Show()
        end
    end)
end

-- Cast bar settle: the bar's saved position is applied by the unlock system's
-- deferred login pass (CUI_UnlockMode.lua fires it ~1.5s after
-- PLAYER_ENTERING_WORLD, or CDM owns it), which lands AFTER these containers
-- anchored -- so the bottom-anchor reserve was decided against the bar's
-- provisional position. Re-run the pass once the positions are in, and again
-- whenever unlock mode closes (the bar may have been dragged into or out of the
-- strip below the frame). Both are no-ops unless the reserve actually changed:
-- UF_ReloadAuraContainers only re-anchors on a config fingerprint change.
-- A profile swap needs no trigger of its own: it runs through RefreshAllAddons
-- -> ReloadFrames, which ends in UF_ReloadAllAuraContainers already.
-- Cost: two login timers, one unlock listener. No per-frame work, no allocation
-- on any chatty event.
--
-- Deliberately NOT a hook on CludesUI._applySavedPositions: that field is
-- passed by reference into C_Timer.After by the action bars module
-- (CUI_ActionBars_Setup.lua), and replacing it there made that call raise.
do
    local queued = false
    local function Settle()
        queued = false
        mod.UF_ReloadAllAuraContainers()
    end
    local function Queue()
        if queued then
            return
        end
        queued = true
        C_Timer.After(0, Settle)
    end
    local settleWatcher = CreateFrame("Frame")
    settleWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    settleWatcher:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        -- Two passes: the first clears the unlock system's own deferred pass
        -- (~1.5s after this event), the second covers a CDM-owned run of it,
        -- which waits for async icon population and can land later. Whichever
        -- lands second is a no-op unless the reserve actually changed.
        C_Timer.After(2, Queue)
        C_Timer.After(5, Queue)
    end)
    CludesUI:RegisterUnlockModeListener("EUF_AuraContainers", function(unlockActive)
        if not unlockActive then
            Queue()
        end
    end)
end

-- One element shell, born directly on our frame (combat-legal since 68914).
local function AdoptShell(widget, unitToken, field)
    return AK.CreateContainerShell(widget, {
        point = { "CENTER", widget, "CENTER" }, -- provisional; reload anchors properly
    })
end

local ELEMENT_ORDER = { { "HELPFUL", "buffs" }, { "HARMFUL", "debuffs" } }

-- Builds one unit's containers as a RESUMABLE STEPPER: each invocation does one bounded
-- atom of work and returns "again" until done. The expensive atom is a single group
-- declaration (an eager 10-button engine batch through AuraKit's full region
-- initializer); running them one per invocation lets the shared worker's per-frame
-- budget apply between atoms, where the old whole-unit job could balloon past the
-- client watchdog under login contention ("script ran too long" -- and the killed job
-- left the unit half-built). Every stage is existence-guarded, so a watchdog-killed
-- invocation resumes cleanly: an aborted engine declare never stamps its
-- declared/progress mark, so it re-runs, or, when the engine had already
-- registered the group, DeclareElementGroup records it.
local function BuildUnitContainers(widget, unitToken)
    local cfg = SettingsFor(unitToken)
    if not (AK and cfg) then
        return
    end
    local record = registry[unitToken]
    if record and not record.building then
        return
    end

    -- Stage 1: entry + both element shells (cheap; no engine batches;
    -- combat-legal since 68914).
    if not record then
        -- Styles must exist before group declaration: initializeFrame
        -- consumes them for the pre-created button batches. Prime their
        -- fingerprints too: the final-stage reload would otherwise queue a
        -- restyle of buttons that were decorated from these exact tables.
        local font = (CludesUI.GetFontPath("unitFrames")) or ""
        for _, baseSet in ipairs({ "HELPFUL", "HARMFUL" }) do
            local auraKey = StyleKey(unitToken, baseSet)
            local look = BuildStyle(unitToken, baseSet, cfg, widget)
            AK.styles[auraKey] = look
            ufFP[auraKey] = { style = StyleTableFP(look, font) }
            if baseSet == "HELPFUL" and unitToken ~= "player" then
                PurgeGlow.Register(unitToken, cfg, widget, font)
            end
        end

        record = { frame = widget, building = true, sig = {}, groups = { buffs = {}, debuffs = {} } }
        record.buffs = AdoptShell(widget, unitToken, "buffs")
        record.debuffs = AdoptShell(widget, unitToken, "debuffs")
        registry[unitToken] = record
        -- Tracked Auras gate: a focus coming back into range (or any unit
        -- appearing without a change event) shows the frame through unit
        -- watch, so re-check there; the container parses on its next update,
        -- after this. A no-op unless the unit holds include groups.
        if (unitToken == "target" or unitToken == "focus") and not IncGate.hooked[widget] then
            IncGate.hooked[widget] = true
            widget:HookScript("OnShow", function()
                IncGate.Apply(unitToken)
                PurgeGlow.Check(unitToken)
            end)
        end
        return "again"
    end

    -- Stage 2: one missing group declaration per invocation (the expensive
    -- atom), for the elements that are on (SideOn, re-read every atom): an
    -- element that is off declares nothing until a reload sees it on.
    for e = 1, 2 do
        local baseSet, field = ELEMENT_ORDER[e][1], ELEMENT_ORDER[e][2]
        if SideOn(unitToken, baseSet, cfg) then
            local filterChain = ChainFor(unitToken, baseSet, cfg)
            local declared = record.groups[field]
            local styleKey = StyleKey(unitToken, baseSet)
            -- The plain catch-all only for an empty chain, where it is the
            -- group that shows or, showing nothing, still gives the container
            -- its layout aspect (see the reload's declaration).
            if not declared.all and #filterChain == 0 then
                DeclareElementGroup(record[field], declared, styleKey, "all", { baseSet }, nil)
                return "again"
            end
            for index = 1, #filterChain do
                local c = filterChain[index]
                if not declared[c.key] then
                    local sk = styleKey
                    if c.glow then
                        sk = PurgeGlow.StyleKey(unitToken)
                        -- The capability can arrive between stages (spellbook
                        -- ready after stage 1): never declare against a missing style.
                        if not AK.styles[sk] then
                            PurgeGlow.Register(
                                unitToken,
                                cfg,
                                widget,
                                (CludesUI.GetFontPath and CludesUI.GetFontPath("unitFrames")) or ""
                            )
                        end
                    end
                    DeclareElementGroup(record[field], declared, sk, c.key, c.tokens, c.cand)
                    return "again"
                end
            end
        end
    end

    -- Stage 3: finish both containers (SetUnit + full refresh). Stamped
    -- after the calls; re-finishing on a resumed run is harmless.
    if not record.finished then
        AK.FinishContainer(record.buffs, unitToken)
        AK.FinishContainer(record.debuffs, unitToken)
        record.finished = true
        return "again"
    end

    -- Stage 4: player dispel styles, and the slot sets whose feature is on
    -- (batch-1 slot adds; each set resumable via its container and add
    -- count). A set that is off is built by the reload that first sees it on.
    if unitToken == "player" and not record.dispelDone then
        local decorShown, fillShown, iconsShown = BuildDispelStyles(widget)
        SyncDispelSets(widget, record, decorShown, fillShown, iconsShown)
        record.dispelDone = true
        -- Prime the dispel fingerprint: creation just applied these exact
        -- settings, so the final-stage reload must not queue a redundant
        -- restyle (harmless noise OOC, but denied button writes when built
        -- under restriction -- the in-instance /reload case).
        local p = mod.UF_GetProfile and mod.UF_GetProfile()
        if p then
            ufFP.dispel = DispelFP(p, widget)
        end
        return "again"
    end

    -- Final stage: the first real reload stamps the signatures of the elements
    -- that are on (their additive path walks the declared sets as no-ops,
    -- unless one turned on mid-build) and force-applies anchor/config/
    -- visibility; an element that is off stays unstamped until a reload sees
    -- it on.
    record.building = nil
    mod.UF_ReloadAuraContainers(widget, unitToken)
end

-- Deferred through the shared AuraKit build scheduler (budgeted per frame, never ticks
-- during loading screens; combat-runnable via the stash shells). One QUEUED job per
-- unit, but the job is a stepper: it returns "again" after each bounded atom (one
-- engine group batch) so the worker's budget check runs between atoms -- the return
-- propagates BuildUnitContainers' verdict.
function mod.UF_CreateAuraContainers(widget, unitToken)
    AK = AK or CludesUI.AuraKit
    if not (AK and AK.QueueBuildJob) then
        return
    end
    if registry[unitToken] or buildQueued[unitToken] then
        return
    end
    buildQueued[unitToken] = true
    AKWorker:Queue(function()
        buildQueued[unitToken] = nil
        return BuildUnitContainers(widget, unitToken)
    end, "uf:unit")
end
