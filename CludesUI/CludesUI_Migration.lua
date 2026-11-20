if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  CludesUI_Migration.lua -- loaded after CludesUI_Lite.lua, before
--  CludesUI_Profiles.lua; runs at ADDON_LOADED for "CludesUI" (before
--  child addons init). Legacy migrations removed: the beta-exit wipe (reset
--  version 5) guarantees a clean slate for every user.
--------------------------------------------------------------------------------

local floor = math.floor

--------------------------------------------------------------------------------
--  ONE-TIME MIGRATION RUNNER
--
--  RegisterMigration({id, scope, description, body}) runs a one-time migration
--  reliably across upgrades/characters/profiles/specs. scope picks ctx + flag
--  host: "global" -> ctx.db=CludesUIDB (flag on CludesUIDB); "profile" ->
--  ctx.profile/profileName (flag on profileData); "specProfile" ->
--  ctx.specProfile/specKey (flag on specProfData) -- all under ._migrations[id].
--  Runner walks ALL profiles/spec profiles each pass. Bodies run in pcall; flag
--  stamps only on success so a failed body retries next session. Only the
--  "early" phase exists (parent ADDON_LOADED, before child addons init).
--
--  RULES: (1) IDs are forever, never change one -- register a new id instead.
--  (2) Bodies must be idempotent (predicate-gated) even with the flag. (3)
--  Don't iterate profiles/specs inside a body, the runner does that. (4) No
--  live game APIs (UnitClass, GetSpecialization, C_CooldownViewer) -- unreliable
--  at "early" phase. (5) Walk raw ctx.profile/ctx.specProfile, never
--  child.db.profile: child addons haven't initialized.
--------------------------------------------------------------------------------

local _migrations = {} -- ordered registration list (1..N)
local _migrationsById = {} -- id -> spec, for dedup + lookup
local _migrationErrors = {} -- session-only error buffer for /cui migrations
CludesUI._migrationErrors = _migrationErrors

local VALID_SCOPES = { global = true, profile = true, specProfile = true }

function CludesUI.RegisterMigration(specInfo)
    if type(specInfo) ~= "table" then
        error("RegisterMigration: spec must be a table", 2)
    end
    if type(specInfo.id) ~= "string" or specInfo.id == "" then
        error("RegisterMigration: spec.id must be a non-empty string", 2)
    end
    if type(specInfo.body) ~= "function" then
        error("RegisterMigration: spec.body must be a function", 2)
    end
    if not VALID_SCOPES[specInfo.scope] then
        error(
            "RegisterMigration: spec.scope must be 'global', 'profile', or 'specProfile' (got '"
                .. tostring(specInfo.scope)
                .. "')",
            2
        )
    end
    if _migrationsById[specInfo.id] then
        error("RegisterMigration: duplicate migration id '" .. specInfo.id .. "'", 2)
    end
    _migrations[#_migrations + 1] = specInfo
    _migrationsById[specInfo.id] = specInfo
end

-- Get (and lazily create) the per-scope flag table on the host table.
local function GetFlagTable(host)
    if not host._migrations then
        host._migrations = {}
    end
    return host._migrations
end

-- Run a single migration body, stamp the flag on success, log on error.
local function RunOne(specInfo, context, flagHost)
    local flagSet = GetFlagTable(flagHost)
    if flagSet[specInfo.id] then
        return
    end
    local success, err = pcall(specInfo.body, context)
    if success then
        flagSet[specInfo.id] = true
    else
        _migrationErrors[#_migrationErrors + 1] = {
            id = specInfo.id,
            scope = specInfo.scope,
            err = tostring(err),
            time = GetTime(),
        }
    end
end

-- Iterate one migration across the appropriate set of targets for its scope.
local function RunMigration(specInfo)
    if specInfo.scope == "global" then
        RunOne(specInfo, { db = CludesUIDB }, CludesUIDB)
    elseif specInfo.scope == "profile" then
        if CludesUIDB.profiles then
            for profileName, profileRec in pairs(CludesUIDB.profiles) do
                if type(profileRec) == "table" then
                    RunOne(specInfo, {
                        profile = profileRec,
                        profileName = profileName,
                    }, profileRec)
                end
            end
        end
    elseif specInfo.scope == "specProfile" then
        -- Per-profile store: spellAssignments.profiles[name].specProfiles, seeded
        -- from the legacy flat store by cdm_per_profile_spell_store_v1 (registered
        -- first). Flags ride on each specProfData._migrations, carried by seeding.
        local assignments = CludesUIDB.spellAssignments
        local profileSet = assignments and assignments.profiles
        if profileSet then
            for profileName, specBucket in pairs(profileSet) do
                local specList = type(specBucket) == "table" and specBucket.specProfiles
                if type(specList) == "table" then
                    for specKey, specProfile in pairs(specList) do
                        if type(specProfile) == "table" then
                            RunOne(specInfo, {
                                specProfile = specProfile,
                                specKey = specKey,
                                profileName = profileName,
                            }, specProfile)
                        end
                    end
                end
            end
        end
    end
end

-- Public: run all migrations. Called once from the parent ADDON_LOADED handler.
function CludesUI.RunRegisteredMigrations()
    if not CludesUIDB then
        CludesUIDB = {}
    end
    if not (CludesUIDB.profiles and next(CludesUIDB.profiles)) then
        -- Fresh install (no SavedVariables yet) or the Reset All wipe (a table
        -- with no profiles: a few preserved keys, nothing to migrate). Must
        -- stamp globals now, not skip -- an unstamped catalog would run the
        -- whole chain at next load against whatever exists by then (e.g. an
        -- imported profile), treating current-format data as legacy
        -- (concretely: CDM consolidate/detach would rebuild an imported spell
        -- store, pixel-rounding would floor imported positions/sizes, the
        -- colors seed would replace imported palettes) -- and, on the reset
        -- table, every "preserve the old default for veterans" migration would
        -- hand a reset user the OLD default. Profile-scoped stamps live inside
        -- each profile (and ride exports), so they need no genesis pass.
        local flagSet = GetFlagTable(CludesUIDB)
        for _, specInfo in ipairs(_migrations) do
            if specInfo.scope == "global" then
                flagSet[specInfo.id] = true
            end
        end
        return
    end
    for _, specInfo in ipairs(_migrations) do
        RunMigration(specInfo)
    end
end

--------------------------------------------------------------------------------
--  Registered migrations
--------------------------------------------------------------------------------

-- Hovercast macro bindings ignored their Friendly/Enemy toggles (filter applied
-- only to spell bindings). Now honored: creation defaults (hoverFriendly=true,
-- hoverEnemy=false) would silently break enemy macros, so seed both flags true
-- on existing bindings to stay unfiltered; toggles apply going forward.
CludesUI.RegisterMigration({
    id = "clickcast_macro_hover_reaction_v1",
    scope = "profile",
    description = "Keep existing hovercast macro bindings unfiltered now that Friendly/Enemy applies to them",
    body = function(context)
        local raidCfg = context.profile.addons and context.profile.addons.CludesUIRaidFrames
        local clickCfg = raidCfg and raidCfg.clickCast
        if type(clickCfg) ~= "table" then
            return
        end
        local function seedValue(entryList)
            if type(entryList) ~= "table" then
                return
            end
            for _, bind in ipairs(entryList) do
                if type(bind) == "table" and bind.type == "macro" and bind.hovercast then
                    bind.hoverFriendly = true
                    bind.hoverEnemy = true
                end
            end
        end
        seedValue(clickCfg.globals)
        if type(clickCfg.specs) == "table" then
            for _, entryList in pairs(clickCfg.specs) do
                seedValue(entryList)
            end
        end
    end,
})

-- The Friendly/Enemy toggles now gate every reaction binding (frame + hover
-- spells, items, hover macros) and "both off" means disabled; an UNSET pair
-- now reads as friendly-only. Legacy semantics were: frame spells/items and
-- hover items ignored the flags (unrestricted); hover spells/macros were
-- help-only iff (friendly and not enemy), harm-only iff (enemy and not
-- friendly), otherwise unrestricted -- including nil/nil and false/false.
-- Seed every reaction binding to booleans reproducing exactly that, and split
-- legacy "Frames + Hovercast" bindings so each path keeps its own behavior.
-- Marker `reactionSeeded` keeps the pass idempotent (a post-migration
-- false/false is a real user disable and must never be re-enabled).
CludesUI.RegisterMigration({
    id = "clickcast_frame_spell_reaction_v1",
    scope = "global",
    description = "Preserve legacy click-cast reaction behavior when the Friendly/Enemy toggles become active for all reaction bindings",
    body = function(context)
        local clickCfg = context.db.clickCast
        if type(clickCfg) ~= "table" then
            return
        end
        local function LegacyHover(bind)
            local friendlySpell, e = bind.hoverFriendly, bind.hoverEnemy
            if friendlySpell and not e then
                return true, false
            end
            if e and not friendlySpell then
                return false, true
            end
            return true, true
        end
        local function migrate(entryList)
            if type(entryList) ~= "table" then
                return
            end
            local total = #entryList
            for index = 1, total do
                local bind = entryList[index]
                if
                    type(bind) == "table"
                    and not bind.reactionSeeded
                    and (bind.type == "spell" or bind.type == "item" or (bind.type == "macro" and bind.hovercast))
                then
                    if bind.hovercast == "both" then
                        -- Frame copy: flags were ignored on the frame path.
                        local frameBind = {}
                        for fieldKey, value in pairs(bind) do
                            frameBind[fieldKey] = value
                        end
                        frameBind.hovercast = false
                        frameBind.hoverFriendly = true
                        frameBind.hoverEnemy = true
                        frameBind.reactionSeeded = true
                        entryList[#entryList + 1] = frameBind
                        bind.hovercast = true
                    end
                    if not bind.hovercast or bind.type == "item" then
                        -- Frame path (any type) and hover items ignored the flags.
                        bind.hoverFriendly, bind.hoverEnemy = true, true
                    else
                        -- Hover spells / macros: reproduce the old conditional.
                        bind.hoverFriendly, bind.hoverEnemy = LegacyHover(bind)
                    end
                    bind.reactionSeeded = true
                end
            end
        end
        migrate(clickCfg.globals)
        if type(clickCfg.specs) == "table" then
            for _, entryList in pairs(clickCfg.specs) do
                migrate(entryList)
            end
        end
    end,
})

--------------------------------------------------------------------------------
--  Position snap helpers
--  Used by position_snap_v3 and exposed as CludesUI.SnapProfilePositions for
--  profile import. MakeSnappers reads CludesUIDB.ppUIScale and
--  GetPhysicalScreenSize() at CALL time (once SavedVariables + screen API are up).
--------------------------------------------------------------------------------

local function MakeSnappers()
    local physH = select(2, GetPhysicalScreenSize())
    local perfect = physH and physH > 0 and (768 / physH) or 1
    local uiScale = CludesUIDB and CludesUIDB.ppUIScale or perfect
    if uiScale <= 0 then
        uiScale = perfect
    end
    local onePixel = perfect / uiScale

    local function snap(val)
        if type(val) ~= "number" or val == 0 then
            return val
        end
        -- Epsilon-guarded round (matches PP.SnapForES): values a hair off a
        -- half-pixel boundary must snap as at runtime, or frames shift 1px.
        local result = floor(val / onePixel + 0.5 + 0.001) * onePixel
        -- Clean floating point dust
        local rounded = floor(result + 0.5)
        if math.abs(result - rounded) < 0.001 then
            result = rounded
        end
        return result
    end
    local function snapPosition(entryList)
        if type(entryList) ~= "table" then
            return
        end
        if entryList.x then
            entryList.x = snap(entryList.x)
        end
        if entryList.y then
            entryList.y = snap(entryList.y)
        end
    end
    local function snapPosMap(map)
        if type(map) ~= "table" then
            return
        end
        for _, place in pairs(map) do
            snapPosition(place)
        end
    end
    local function snapAnchors(anchorMap)
        if type(anchorMap) ~= "table" then
            return
        end
        for _, details in pairs(anchorMap) do
            if type(details) == "table" then
                if details.offsetX then
                    details.offsetX = snap(details.offsetX)
                end
                if details.offsetY then
                    details.offsetY = snap(details.offsetY)
                end
            end
        end
    end
    return snapPosition, snapPosMap, snapAnchors, snap
end

-- Snap all positions in a single profile data table. Called per profile by the
-- position_snap_v3 migration, and once by profile import.
local function SnapProfilePositions(profileRec)
    if type(profileRec) ~= "table" then
        return
    end
    local snapPosition, snapPosMap, snapAnchors = MakeSnappers()

    local ul = profileRec.unlockLayout
    if ul then
        snapAnchors(ul.anchors)
    end

    local addonStores = profileRec.addons
    if type(addonStores) ~= "table" then
        return
    end

    local ufStore = addonStores.CludesUIUnitFrames
    if ufStore then
        snapPosMap(ufStore.positions)
    end

    local actionBarsCfg = addonStores.CludesUIActionBars
    if actionBarsCfg then
        snapPosMap(actionBarsCfg.barPositions)
    end

    local cdmStore = addonStores.CludesUICooldownManager
    if cdmStore then
        snapPosMap(cdmStore.cdmBarPositions)
    end

    local resBarsCfg = addonStores.CludesUIResourceBars
    if type(resBarsCfg) == "table" then
        for _, section in pairs(resBarsCfg) do
            if type(section) == "table" and section.unlockPos then
                snapPosition(section.unlockPos)
            end
        end
    end

    local reminderCfg = addonStores.CludesUIAuraBuffReminders
    if type(reminderCfg) == "table" and reminderCfg.unlockPos then
        snapPosition(reminderCfg.unlockPos)
    end

    local cursor = addonStores.CludesUICursor
    if type(cursor) == "table" then
        if cursor.gcd then
            snapPosition(cursor.gcd.pos)
        end
        if cursor.cast then
            snapPosition(cursor.cast.pos)
        end
    end
end

-- Expose for profile import
CludesUI.SnapProfilePositions = SnapProfilePositions

-- Flattens every per-profile spec-profile table into one array. After seeding
-- (cdm_per_profile_spell_store_v1), CDM data lives at profiles[name].specProfiles,
-- not the flat legacy store -- global-scope bodies call this for LIVE data.
local function CollectSpecProfiles(assignments)
    local result = {}
    if type(assignments) ~= "table" then
        return result
    end
    local profileSet = assignments.profiles
    if type(profileSet) == "table" then
        for _, specBucket in pairs(profileSet) do
            local specList = type(specBucket) == "table" and specBucket.specProfiles
            if type(specList) == "table" then
                for _, specProfile in pairs(specList) do
                    if type(specProfile) == "table" then
                        result[#result + 1] = specProfile
                    end
                end
            end
        end
    end
    return result
end

--------------------------------------------------------------------------------
--  Registered migrations -- one-time transforms gated by the runner's per-scope
--  flag; bodies must be idempotent. Legacy flag checks bridge old inline
--  migrations and can be dropped once all users have passed through.
--------------------------------------------------------------------------------

-- Registered FIRST (precedes all specProfile migrations). Forks the legacy account-wide
-- CDM store (spellAssignments.specProfiles, shared per spec) into per-profile stores
-- (profiles[name].specProfiles), DeepCopied into every profile so copies own
-- independent CDM data (else deleting a bar in one mutates the shared bucket and wipes
-- the origin). DeepCopy keeps _migrations flags, so specProfile migrations already run
-- don't re-run. Legacy flat table stays as a dormant, unread backup -- distinct from
-- CludesUIDB.specProfiles (the spec-to-profile auto-switch map).
--
-- Below: Spec Overrides fresh start wipes groups/value entries/unlock overrides
-- (backend moved to whole-layout LAYERS). RB Advanced output lives there, so an
-- already-migrated profile is RE-ARMED first (restored from
-- rb.advancedSpecsBackup, flag cleared) so RB init rebuilds cards into the clean
-- store same login. Re-running MergeThresholds converges: first-run inserts are
-- spec-only and get stripped before identical re-insertion.
do
    local function RearmRBAdvancedMigration(profileTbl)
        local resourceBars = profileTbl and profileTbl.addons and profileTbl.addons.CludesUIResourceBars
        if type(resourceBars) ~= "table" or not resourceBars._rbAdvMigrated then
            return
        end
        local backupCopy = resourceBars.advancedSpecsBackup
        if type(backupCopy) == "table" then
            resourceBars.advancedSpecs = backupCopy.advancedSpecs
            if type(backupCopy.disabledSpecs) == "table" then
                for secKey, ds in pairs(backupCopy.disabledSpecs) do
                    if type(resourceBars[secKey]) == "table" then
                        resourceBars[secKey].disabledSpecs = ds
                    end
                end
            end
            resourceBars.advancedSpecsBackup = nil
        end
        resourceBars._rbAdvMigrated = nil
    end

    CludesUI.RegisterMigration({
        id = "spec_overrides_fresh_start_v1",
        scope = "profile",
        description = "Wipe all spec override data (groups, value entries, unlock overrides) for the layer-model fresh start.",
        body = function(context)
            local profileTbl = context.profile
            if not profileTbl then
                return
            end
            RearmRBAdvancedMigration(profileTbl)
            profileTbl.specOverrideGroups = nil
            profileTbl.specOverrides = nil
            profileTbl.specUnlockOverrides = nil
        end,
    })

    -- Recovery for profiles wiped WITHOUT the re-arm above: cards are gone but the
    -- source sits in rb.advancedSpecsBackup, so re-arm once and RB's init
    -- re-creates them. Guard: only re-arm when the store holds no RB-module
    -- entries, since cards created AFTER the wipe (early runner precedes RB
    -- init) would otherwise get duplicates.
    CludesUI.RegisterMigration({
        id = "rb_adv_remigrate_after_wipe_v1",
        scope = "profile",
        description = "Re-run the RB Advanced migration for profiles whose migrated spec override cards were wiped by the fresh start.",
        body = function(context)
            local profileTbl = context.profile
            if not profileTbl then
                return
            end
            if type(profileTbl.specOverrides) == "table" then
                for _, entry in ipairs(profileTbl.specOverrides) do
                    if type(entry) == "table" and entry.module == "CludesUIResourceBars" then
                        return
                    end
                end
            end
            RearmRBAdvancedMigration(profileTbl)
        end,
    })
end

-- Captures made before numeric-segment path walkers existed banked NIL sentinels
-- (reads missed numeric bars[i] keys); applying via the FIXED walkers would null
-- live CDM settings on the next spec swap. Drop every CDM-bars capture from both stores.
CludesUI.RegisterMigration({
    id = "cdm_bars_capture_reset_v1",
    scope = "profile",
    description = "Drop corrupt CDM bar captures recorded by the pre-numeric-walker override builds.",
    body = function(context)
        local profileTbl = context.profile
        if not profileTbl then
            return
        end
        local PREFIX = "CludesUICooldownManager\31cdmBars\30bars\30"
        local function sweep(storage)
            if type(storage) ~= "table" then
                return
            end
            for index = #storage, 1, -1 do
                local e = storage[index]
                local default = type(e) == "table" and e.values and e.values.default
                if type(default) == "table" then
                    for fieldKey in pairs(default) do
                        if type(fieldKey) == "string" and fieldKey:sub(1, #PREFIX) == PREFIX then
                            table.remove(storage, index)
                            break
                        end
                    end
                end
            end
        end
        sweep(profileTbl.specOverrides)
        sweep(profileTbl.condOverrides)
    end,
})

-- The Skyriding HUD sub-DB registers its own folder (CludesUIDragonRiding),
-- dodging the BlizzardSkin capture blacklist, so a width-match write could be
-- auto-captured into an unrelated entry; applying it hits a folder with no
-- targeted refresher, so the unmapped-folder fallback escalates every apply
-- into a full RefreshAllAddons (minutes of refresh under spec-change traffic).
-- Folder is now blacklisted; strip its keys from both stores (empty default map = drop whole).
CludesUI.RegisterMigration({
    id = "specov_strip_dragonriding_fkeys_v1",
    scope = "profile",
    description = "Strip stowaway Dragon Riding fkeys from spec/conditional override stores (unmapped-folder RefreshAllAddons storm).",
    body = function(context)
        local profileTbl = context.profile
        if not profileTbl then
            return
        end
        local PREFIX = "CludesUIDragonRiding\31"
        local function strip(storage)
            if type(storage) ~= "table" then
                return
            end
            for index = #storage, 1, -1 do
                local e = storage[index]
                local valueList = type(e) == "table" and e.values
                if type(valueList) == "table" then
                    for _, m in pairs(valueList) do
                        if type(m) == "table" then
                            for fieldKey in pairs(m) do
                                if type(fieldKey) == "string" and fieldKey:sub(1, #PREFIX) == PREFIX then
                                    m[fieldKey] = nil
                                end
                            end
                        end
                    end
                    if type(valueList.default) ~= "table" or next(valueList.default) == nil then
                        table.remove(storage, index)
                    end
                end
            end
        end
        strip(profileTbl.specOverrides)
        strip(profileTbl.condOverrides)
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_per_profile_spell_store_v1",
    scope = "global",
    description = "Fork the shared per-spec CDM spell store into every profile so profile copies own independent CDM data.",
    body = function(context)
        local saved = context.db
        local assignments = saved and saved.spellAssignments
        if not assignments then
            return
        end -- fresh install: nothing stored yet
        if assignments._perProfileSeeded then
            return
        end -- already converted
        local legacy = assignments.specProfiles -- old account-wide per-spec store
        if not assignments.profiles then
            assignments.profiles = {}
        end
        local DeepCopy = CludesUI._DeepCopy or (CludesUI.Lite and CludesUI.Lite.DeepCopy)
        local function seedValue(label)
            if not label then
                return
            end
            if assignments.profiles[label] then
                return
            end -- idempotent: never clobber an existing bucket
            local specList = {}
            if legacy and DeepCopy then
                specList = DeepCopy(legacy)
            end
            assignments.profiles[label] = { specProfiles = specList }
        end
        if saved.profiles then
            for label, profileSaved in pairs(saved.profiles) do
                if type(profileSaved) == "table" then
                    seedValue(label)
                end
            end
        end
        -- Ensure the active/Default profile has a bucket even when db.profiles
        -- lacks it (very early / minimal-state installs).
        seedValue(saved.activeProfile or "Default")
        assignments._perProfileSeeded = true
    end,
})

-- Consolidates auto-seeded per-profile CDM buckets into spell LAYOUTS: collapses
-- identical duplicates into one, keeps distinct setups as their own layouts,
-- backs up originals (seeding copied one CDM setup into every profile, else
-- users would see a redundant layout each). Only auto-seeded buckets (no
-- `meta`) are touched; user-created/imported layouts are left alone.
CludesUI.RegisterMigration({
    id = "cdm_consolidate_profile_layouts_v1",
    scope = "global",
    description = "Collapse identical auto-seeded per-profile CDM buckets into single spell layouts; keep distinct ones; dormant backup at spellAssignments._preConsolidateBackup.",
    body = function(context)
        local saved = context.db
        local assignments = saved and saved.spellAssignments
        if not assignments or type(assignments.profiles) ~= "table" then
            return
        end
        local DeepCopy = CludesUI._DeepCopy or (CludesUI.Lite and CludesUI.Lite.DeepCopy)

        -- Deep value-equality IGNORING "_"-prefixed bookkeeping keys (e.g.
        -- _migrations), so copies differing only in flags count as identical.
        local function ContentEqual(lhs, rhs)
            if type(lhs) ~= type(rhs) then
                return false
            end
            if type(lhs) ~= "table" then
                return lhs == rhs
            end
            for key, val in pairs(lhs) do
                if not (type(key) == "string" and key:sub(1, 1) == "_") then
                    if not ContentEqual(val, rhs[key]) then
                        return false
                    end
                end
            end
            for key in pairs(rhs) do
                if not (type(key) == "string" and key:sub(1, 1) == "_") then
                    if lhs[key] == nil then
                        return false
                    end
                end
            end
            return true
        end

        -- Auto-seeded buckets have no `meta`; only they are consolidation candidates.
        local wasSeeded = {}
        for label, specBucket in pairs(assignments.profiles) do
            if type(specBucket) == "table" and not specBucket.meta then
                wasSeeded[#wasSeeded + 1] = label
            end
        end
        if #wasSeeded <= 1 then
            return
        end -- nothing to collapse

        -- One-time dormant backup of every bucket (safety net; recoverable).
        if DeepCopy and not assignments._preConsolidateBackup then
            assignments._preConsolidateBackup = DeepCopy(assignments.profiles)
        end

        -- Active profile first so its name is the kept representative for the live
        -- setup; the rest alphabetically for determinism.
        local activeName = saved.activeProfile or "Default"
        table.sort(wasSeeded)
        local ordered = {}
        if assignments.profiles[activeName] and not assignments.profiles[activeName].meta then
            ordered[#ordered + 1] = activeName
        end
        for _, num in ipairs(wasSeeded) do
            if num ~= activeName then
                ordered[#ordered + 1] = num
            end
        end

        local keptCount = {}
        local repOf = {} -- every processed seeded name -> its surviving layout
        for _, label in ipairs(ordered) do
            local specBucket = assignments.profiles[label]
            local rep
            for _, kn in ipairs(keptCount) do
                if ContentEqual(assignments.profiles[kn].specProfiles or {}, specBucket.specProfiles or {}) then
                    rep = kn
                    break
                end
            end
            if rep then
                assignments.profiles[label] = nil -- identical duplicate: drop it
                repOf[label] = rep
            else
                keptCount[#keptCount + 1] = label
                repOf[label] = label
            end
        end

        -- Active layout is remembered PER CUI PROFILE: point each profile at the
        -- surviving layout holding its own pre-consolidation CDM, so a profile
        -- switch loads that setup. Never clobber a user-set pointer.
        assignments.activeLayoutByProfile = assignments.activeLayoutByProfile or {}
        if saved.profiles then
            for pname in pairs(saved.profiles) do
                if not assignments.activeLayoutByProfile[pname] and repOf[pname] then
                    assignments.activeLayoutByProfile[pname] = repOf[pname]
                end
            end
        end
        local activeRep = repOf[activeName] or keptCount[1] or activeName
        if not assignments.activeLayoutByProfile[activeName] then
            assignments.activeLayoutByProfile[activeName] = activeRep
        end
        -- Global last-active = default for any profile without a pointer yet.
        if not assignments.activeLayout or not assignments.profiles[assignments.activeLayout] then
            assignments.activeLayout = activeRep
        end
    end,
})

-- Detaches CDM spell layouts from profiles: the implicit per-profile active-layout
-- map (activeLayoutByProfile) becomes OPT-IN bindings (profileBindings) plus one
-- account-wide active layout. Behavior-identical (profiles stay bound to the
-- layout they used; user detaches by removing bindings). Runs AFTER
-- cdm_consolidate_profile_layouts_v1, inheriting deduped layouts+pointers.
CludesUI.RegisterMigration({
    id = "cdm_detach_spell_layouts_v1",
    scope = "global",
    description = "Convert per-profile active CDM spell layouts (activeLayoutByProfile) into opt-in profile bindings + a single account-wide active layout. Zero behavior change.",
    body = function(context)
        local saved = context.db
        local assignments = saved and saved.spellAssignments
        if type(assignments) ~= "table" then
            return
        end
        local byProfile = assignments.activeLayoutByProfile
        assignments.profileBindings = assignments.profileBindings or {}
        if type(byProfile) == "table" then
            for profileTbl, layout in pairs(byProfile) do
                if
                    type(profileTbl) == "string"
                    and type(layout) == "string"
                    and type(assignments.profiles) == "table"
                    and type(assignments.profiles[layout]) == "table"
                then
                    -- Don't clobber a binding the user may already have set.
                    if assignments.profileBindings[profileTbl] == nil then
                        assignments.profileBindings[profileTbl] = layout
                    end
                end
            end
        end
        -- Account-wide active = current profile's layout, so the live CDM is
        -- byte-for-byte unchanged here. Fall back to the old global pointer,
        -- then any valid layout.
        local current = saved.activeProfile or "Default"
        local isActive = assignments.profileBindings[current]
        if type(isActive) ~= "string" or not (assignments.profiles and assignments.profiles[isActive]) then
            if type(assignments.activeLayout) == "string" and assignments.profiles and assignments.profiles[assignments.activeLayout] then
                isActive = assignments.activeLayout
            else
                isActive = nil
                if type(assignments.profiles) == "table" then
                    for num, val in pairs(assignments.profiles) do
                        if type(val) == "table" then
                            isActive = num
                            break
                        end
                    end
                end
            end
        end
        assignments.activeLayout = isActive
        -- Retire the old per-profile resolution table (back up first, then clear).
        if byProfile then
            assignments._preDetachBackup = byProfile
            assignments.activeLayoutByProfile = nil
        end
    end,
})

CludesUI.RegisterMigration({
    id = "quest_tracker_blizzard_skin_rebuild_v1",
    scope = "global",
    description = "Archive obsolete custom-tracker keys (width/height/alignment/bg/font/color/zone/world/prey/topLine) into _legacy so they stop polluting questTracker defaults after the rebuild to a skin+QoL layer.",
    body = function()
        local sv = _G.CludesUIQuestTrackerDB
        if type(sv) ~= "table" then
            return
        end
        local profileSet = sv.profiles
        if type(profileSet) ~= "table" then
            return
        end

        local OBSOLETE = {
            "width",
            "height",
            "alignment",
            "bgR",
            "bgG",
            "bgB",
            "bgAlpha",
            "showTopLine",
            "showZoneQuests",
            "showWorldQuests",
            "showPreyQuests",
            "showQuestItems",
            "questItemSize",
            "zoneCollapsed",
            "worldCollapsed",
            "preyCollapsed",
            "delveCollapsed",
            "questsCollapsed",
            "achievementsCollapsed",
            "titleFontSize",
            "objFontSize",
            "completedFontSize",
            "secFontSize",
            "focusedFontSize",
            "titleColor",
            "objColor",
            "completedColor",
            "secColor",
            "focusedColor",
            "secColorUseAccent",
            "focusBgOpacity",
            "hideBlizzardTracker",
        }

        for _, profileTbl in pairs(profileSet) do
            if type(profileTbl) == "table" and type(profileTbl.questTracker) == "table" then
                local trackerCfg = profileTbl.questTracker
                local legacy = trackerCfg._legacy or {}
                local moved = false
                for _, k in ipairs(OBSOLETE) do
                    if trackerCfg[k] ~= nil then
                        legacy[k] = trackerCfg[k]
                        trackerCfg[k] = nil
                        moved = true
                    end
                end
                if moved then
                    trackerCfg._legacy = legacy
                end
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "friend_notes_wipe_v1",
    scope = "global",
    description = "Wipe legacy bnetAccountID-keyed friendAssignments and friendNotes (sessions 15-17 rebuild).",
    body = function(context)
        -- DESTRUCTIVE (wipes global.friendAssignments + .friendNotes): the
        -- _friendNotesMigrated bridge is critical, a re-run destroys data since.
        if CludesUIDB and CludesUIDB.global and CludesUIDB.global._friendNotesMigrated then
            return
        end

        local g = context.db.global
        if not g then
            return
        end

        -- One-time popup flag only if the user actually had group assignments
        -- pre-wipe, so users who never used the feature see no "reset" popup.
        local hadAssignments = false
        if g.friendAssignments then
            for _ in pairs(g.friendAssignments) do
                hadAssignments = true
                break
            end
        end
        if hadAssignments then
            g._friendGroupReassignPopup = true
        end

        g.friendAssignments = {}
        g.friendNotes = {}
    end,
})

-- Pixel-perfect snapping splits global (unlock anchors, spec profiles) from
-- per-profile (positions+sizes). Per-profile half runs on every profile incl.
-- future imports; global half keeps its original flag so existing users skip it.
CludesUI.RegisterMigration({
    id = "pixel_perfect_comprehensive_v11",
    scope = "global",
    description = "Snap global unlock anchors and spec-profile TBB positions/sizes to the physical pixel grid.",
    body = function(context)
        local snapPosition, snapPosMap, snapAnchors, snapVal = MakeSnappers()
        local function roundFields(entryList, keyList)
            if not entryList then
                return
            end
            for _, fieldKey in ipairs(keyList) do
                if type(entryList[fieldKey]) == "number" then
                    entryList[fieldKey] = snapVal(entryList[fieldKey])
                end
            end
        end

        snapAnchors(context.db.unlockAnchors)

        -- Spec profiles (per-profile store): TBB positions + bar sizes
        for _, specRec in ipairs(CollectSpecProfiles(context.db.spellAssignments)) do
            local tbbPos = specRec.tbbPositions
            if tbbPos then
                for _, place in pairs(tbbPos) do
                    if type(place) == "table" then
                        snapPosition(place)
                    end
                end
            end
            local trackingBars = specRec.trackedBuffBars
            local tbbBars = trackingBars and trackingBars.bars
            if tbbBars then
                for _, barConf in ipairs(tbbBars) do
                    if type(barConf) == "table" then
                        roundFields(barConf, { "width", "height" })
                    end
                end
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "pixel_perfect_profile_v1",
    scope = "profile",
    description = "Snap all per-profile positions and sizes to the physical pixel grid. Runs on each profile individually so imported profiles are covered.",
    body = function(context)
        local snapPosition, snapPosMap, _, snapVal = MakeSnappers()
        local function roundFields(entryList, keyList)
            if not entryList then
                return
            end
            for _, fieldKey in ipairs(keyList) do
                if type(entryList[fieldKey]) == "number" then
                    entryList[fieldKey] = snapVal(entryList[fieldKey])
                end
            end
        end
        local function snapSection(section, sizeKeys)
            if not section then
                return
            end
            roundFields(section, sizeKeys)
            snapPosition(section.unlockPos)
        end

        local addonStores = context.profile.addons
        if type(addonStores) ~= "table" then
            return
        end

        local actionBarsCfg = addonStores.CludesUIActionBars
        if actionBarsCfg then
            snapPosMap(actionBarsCfg.barPositions)
            if actionBarsCfg.bars then
                for _, barConf in pairs(actionBarsCfg.bars) do
                    if type(barConf) == "table" then
                        roundFields(barConf, { "buttonWidth", "buttonHeight", "width", "height" })
                    end
                end
            end
        end

        local resBarsCfg = addonStores.CludesUIResourceBars
        if resBarsCfg then
            local erbSizeKeys = { "width", "height", "pipWidth", "pipHeight" }
            snapSection(resBarsCfg.primary, erbSizeKeys)
            snapSection(resBarsCfg.secondary, erbSizeKeys)
            snapSection(resBarsCfg.health, erbSizeKeys)
            snapSection(resBarsCfg.castBar or resBarsCfg.castbar, erbSizeKeys)
        end

        local ufStore = addonStores.CludesUIUnitFrames
        if ufStore then
            snapPosMap(ufStore.unlockPositions or ufStore.positions)
            local ufSizeKeys = {
                "frameWidth",
                "healthHeight",
                "powerHeight",
                "castbarWidth",
                "castbarHeight",
                "playerCastbarWidth",
                "playerCastbarHeight",
                "bottomTextBarHeight",
            }
            for _, unitName in ipairs({ "player", "target", "focus", "boss" }) do
                if ufStore[unitName] then
                    roundFields(ufStore[unitName], ufSizeKeys)
                end
            end
        end

        local cdmStore = addonStores.CludesUICooldownManager
        if cdmStore then
            snapPosMap(cdmStore.cdmBarPositions)
            if cdmStore.cdmBars and cdmStore.cdmBars.bars then
                for _, edge in ipairs(cdmStore.cdmBars.bars) do
                    roundFields(edge, { "iconSize", "spacing", "width", "height" })
                end
            end
        end

        local meterCfg = addonStores.CludesUIDamageMeters
        if meterCfg then
            snapPosition(meterCfg.unlockPos)
            roundFields(meterCfg, { "dmWidth", "dmHeight" })
        end

        local chatCfg = addonStores.CludesUIChat
        if chatCfg then
            snapPosition(chatCfg.unlockPos)
            roundFields(chatCfg, { "chatWidth", "chatHeight" })
        end

        local reminderCfg = addonStores.CludesUIAuraBuffReminders
        if reminderCfg and reminderCfg.display then
            snapPosition(reminderCfg.display.unlockPos)
            roundFields(reminderCfg.display, { "iconSize", "iconSpacing" })
        end
    end,
})

CludesUI.RegisterMigration({
    id = "rf_targeted_spells_bool_to_mode_v1",
    scope = "profile",
    description = "Convert RaidFrames PARTY Targeted Spells tsEnabled boolean to tsMode (false->never, true->whenHealing; nil leaves the default). Raid is NOT migrated -- it hard-defaults to never.",
    body = function(context)
        local raidCfg = context.profile.addons and context.profile.addons.CludesUIRaidFrames
        if type(raidCfg) ~= "table" then
            return
        end
        -- Self-gating on the new key: idempotent, never clobbers a user choice.
        if raidCfg.tsMode == nil then
            if raidCfg.tsEnabled == false then
                raidCfg.tsMode = "never"
            elseif raidCfg.tsEnabled == true then
                raidCfg.tsMode = "whenHealing"
            end
            -- tsEnabled == nil: leave unset so DeepMergeDefaults applies the default.
        end
        -- Raid intentionally NOT migrated: tsRaidEnabled ignored, tsRaidMode left
        -- unset so DeepMergeDefaults applies the "never" default.
    end,
})

CludesUI.RegisterMigration({
    id = "nameplates_miniboss_boss_color_split_v1",
    scope = "profile",
    description = "Split nameplate mini-boss/boss colors: seed the new 'boss' color from the user's existing 'miniboss' color so bosses keep their current color until changed.",
    body = function(context)
        -- Self-gating on boss == nil: idempotent, never clobbers a user choice.
        -- Copies only a customized miniboss; unset leaves both to default via
        -- DeepMergeDefaults. Import forward-copies in ApplyProfileData.
        local plateCfg = context.profile.addons and context.profile.addons.CludesUINameplates
        if type(plateCfg) ~= "table" then
            return
        end
        if plateCfg.boss == nil and type(plateCfg.miniboss) == "table" then
            plateCfg.boss = { r = plateCfg.miniboss.r, g = plateCfg.miniboss.g, b = plateCfg.miniboss.b }
        end
    end,
})

CludesUI.RegisterMigration({
    id = "uf_power_border_size_zero_v1",
    scope = "profile",
    description = "Zero out Unit Frames per-unit powerBorderSize. The detached power bar border size only became functional this build; older non-zero values were set while the control did nothing, so clear them so each UI stays visually identical. Users can re-enable a border afterward.",
    body = function(context)
        -- Self-gating: powerBorderSize of 0 (or absent) is skipped, so this runs
        -- once per profile and never touches a border set after the flag stamps.
        -- Scoped STRICTLY to CludesUIUnitFrames -- RaidFrames' own unrelated
        -- powerBorderSize (border already worked) must NOT be zeroed here.
        local ufStore = context.profile.addons and context.profile.addons.CludesUIUnitFrames
        if type(ufStore) ~= "table" then
            return
        end
        local UNIT_KEYS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
        for _, unitName in ipairs(UNIT_KEYS) do
            local u = ufStore[unitName]
            if type(u) == "table" and type(u.powerBorderSize) == "number" and u.powerBorderSize ~= 0 then
                u.powerBorderSize = 0
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_pandemic_glow_color_table",
    scope = "profile",
    description = "Migrate CDM bar flat pandemicR/G/B keys into a pandemicGlowColor table, plus default pandemicGlowStyle.",
    body = function(context)
        -- No legacy flag to bridge. Idempotent by predicate: fires only when the
        -- legacy flat keys exist AND pandemicGlowColor is missing.
        local cdmStore = context.profile.addons and context.profile.addons.CludesUICooldownManager
        local cdmBars = cdmStore and cdmStore.cdmBars
        local barList = cdmBars and cdmBars.bars
        if type(barList) ~= "table" then
            return
        end

        for _, barInfo in ipairs(barList) do
            if type(barInfo) == "table" and barInfo.pandemicR and not barInfo.pandemicGlowColor then
                barInfo.pandemicGlowColor = {
                    r = barInfo.pandemicR or 1,
                    g = barInfo.pandemicG or 1,
                    b = barInfo.pandemicB or 0,
                }
                barInfo.pandemicGlowStyle = barInfo.pandemicGlowStyle or 1
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_repair_bar_keys_v1",
    scope = "profile",
    description = "Repair CDM bars that lost their `key` field via Lite DB delta-strip. Assigns missing core keys (cooldowns, utility, buffs) in order.",
    body = function(context)
        -- Self-gating via `if not bd.key` -- no-op once every bar has a key. The
        -- round-trip (StripDefaults -> save -> load -> DeepMergeDefaults) restores
        -- identity fields in every normal path (profile switch, import); this pass
        -- is purely one-time recovery for already-broken data.
        local cdmStore = context.profile.addons and context.profile.addons.CludesUICooldownManager
        local cdmBars = cdmStore and cdmStore.cdmBars
        local barList = cdmBars and cdmBars.bars
        if type(barList) ~= "table" then
            return
        end

        local CORE_KEYS = { "cooldowns", "utility", "buffs" }
        local CORE_NAMES = { cooldowns = "Cooldowns", utility = "Utility", buffs = "Buffs" }

        local present = {}
        for _, edge in ipairs(barList) do
            if edge.key then
                present[edge.key] = true
            end
        end
        local missing = {}
        for _, ck in ipairs(CORE_KEYS) do
            if not present[ck] then
                missing[#missing + 1] = ck
            end
        end
        if #missing == 0 then
            return
        end

        local mi = 1
        for _, edge in ipairs(barList) do
            if not edge.key and mi <= #missing then
                edge.key = missing[mi]
                edge.name = edge.name or CORE_NAMES[missing[mi]]
                if edge.enabled == nil then
                    edge.enabled = true
                end
                mi = mi + 1
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_remove_misc_bars",
    scope = "profile",
    description = "Remove obsolete CDM bars with barType=='misc' and clear anchorTo references that pointed at them.",
    body = function(context)
        -- Self-gating via the barType check: a no-op once misc bars are gone.
        local cdmStore = context.profile.addons and context.profile.addons.CludesUICooldownManager
        local cdmBars = cdmStore and cdmStore.cdmBars
        local barList = cdmBars and cdmBars.bars
        if type(barList) ~= "table" then
            return
        end

        -- Pass 1: remove misc bars (reverse iteration keeps indices valid).
        local miscKeys = {}
        for index = #barList, 1, -1 do
            if barList[index].barType == "misc" then
                miscKeys[barList[index].key] = true
                table.remove(barList, index)
            end
        end

        -- Pass 2: clear anchorTo on bars that referenced a removed misc bar.
        if next(miscKeys) then
            for _, edge in ipairs(barList) do
                if edge.anchorTo and miscKeys[edge.anchorTo] then
                    edge.anchorTo = "none"
                end
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_active_state_anim_none_to_hideactive",
    scope = "profile",
    description = "Rename CDM bar activeStateAnim value 'none' (No Animation) to 'hideActive' (Hide Active State).",
    body = function(context)
        -- Self-gating: no-op once no bar holds 'none'. MUST register before
        -- cdm_active_state_per_bar_to_per_icon, which depends on the post-rename
        -- 'hideActive' value.
        local cdmStore = context.profile.addons and context.profile.addons.CludesUICooldownManager
        local cdmBars = cdmStore and cdmStore.cdmBars
        local barList = cdmBars and cdmBars.bars
        if type(barList) ~= "table" then
            return
        end

        for _, edge in ipairs(barList) do
            if edge.activeStateAnim == "none" then
                edge.activeStateAnim = "hideActive"
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_mouseover_visibility_to_always",
    scope = "profile",
    description = "Rewrite CDM bar barVisibility 'mouseover' to 'always' (mouseover mode was removed).",
    body = function(context)
        -- Self-gating: a no-op once no bar carries 'mouseover'.
        local cdmStore = context.profile.addons and context.profile.addons.CludesUICooldownManager
        local cdmBars = cdmStore and cdmStore.cdmBars
        local barList = cdmBars and cdmBars.bars
        if type(barList) ~= "table" then
            return
        end

        for _, edge in ipairs(barList) do
            if edge.barVisibility == "mouseover" then
                edge.barVisibility = "always"
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_strip_tbb_linked_frames",
    scope = "specProfile",
    description = "Strip stale _linkedFrame/_linkedCdID/_linkedGen fields from Tracked Buff Bar configs (legacy bloat from removed frame-tree serialization).",
    body = function(context)
        -- Idempotent: nil to nil. Pure legacy cleanup -- frame-tree serialization
        -- into TBB configs is gone, so no live code writes these fields.
        local trackingBars = context.specProfile.trackedBuffBars
        local tbbBars = trackingBars and trackingBars.bars
        if type(tbbBars) ~= "table" then
            return
        end

        for _, barConf in ipairs(tbbBars) do
            barConf._linkedFrame = nil
            barConf._linkedCdID = nil
            barConf._linkedGen = nil
        end
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_removed_spells_to_ghost_cd_bar",
    scope = "specProfile",
    description = "Move per-bar removedSpells (legacy filter mechanic) into the ghost CD bar's assignedSpells. The ghost bar replaced the per-bar removedSpells filter.",
    body = function(context)
        -- Idempotent: removedSpells wiped after run. Skips entirely when no bar has
        -- removedSpells, so cold specs get no empty ghost bar entry -- the runtime
        -- getter creates it on first real write.
        local barSpellMap = context.specProfile.barSpells
        if type(barSpellMap) ~= "table" then
            return
        end

        local GHOST_CD = "__ghost_cd"
        local GHOST_BUFF = "__ghost_buffs"

        -- First pass: is there anything to migrate?
        local hasWork = false
        for barId, barConf in pairs(barSpellMap) do
            if
                barId ~= GHOST_CD
                and barId ~= GHOST_BUFF
                and type(barConf) == "table"
                and barConf.removedSpells
                and next(barConf.removedSpells)
            then
                hasWork = true
                break
            end
        end
        if not hasWork then
            return
        end

        local ghostBS = barSpellMap[GHOST_CD]
        if not ghostBS then
            ghostBS = {}
            barSpellMap[GHOST_CD] = ghostBS
        end
        if not ghostBS.assignedSpells then
            ghostBS.assignedSpells = {}
        end

        local existing = {} -- dedupe against spells already on the ghost bar
        for _, spellRef in ipairs(ghostBS.assignedSpells) do
            existing[spellRef] = true
        end

        -- Second pass: migrate and wipe.
        for barId, barConf in pairs(barSpellMap) do
            if
                barId ~= GHOST_CD
                and barId ~= GHOST_BUFF
                and type(barConf) == "table"
                and barConf.removedSpells
                and next(barConf.removedSpells)
            then
                for spellRef in pairs(barConf.removedSpells) do
                    if not existing[spellRef] then
                        existing[spellRef] = true
                        ghostBS.assignedSpells[#ghostBS.assignedSpells + 1] = spellRef
                    end
                end
                wipe(barConf.removedSpells)
            end
        end
    end,
})

-- Inline copy of every race's racial spell IDs (mirrors RACE_RACIALS in the CDM
-- addon). Ghost CD bar cleanup needs this without depending on the CDM child
-- addon (loads after this runner) or per-character _myRacialsSet. New race =
-- update both.
local CDM_ALL_RACIAL_SPELL_IDS = {
    [7744] = true,
    [20549] = true,
    [20572] = true,
    [33697] = true,
    [33702] = true,
    [202719] = true,
    [50613] = true,
    [25046] = true,
    [69179] = true,
    [80483] = true,
    [155145] = true,
    [129597] = true,
    [232633] = true,
    [28730] = true,
    [20594] = true,
    [26297] = true,
    [28880] = true,
    [59543] = true,
    [59545] = true,
    [121093] = true,
    [59544] = true,
    [370626] = true,
    [59547] = true,
    [59548] = true,
    [59542] = true,
    [416250] = true,
    [58984] = true,
    [59752] = true,
    [265221] = true,
    [20589] = true,
    [69041] = true,
    [68992] = true,
    [69070] = true,
    [107079] = true,
    [274738] = true,
    [255647] = true,
    [256948] = true,
    [287712] = true,
    [291944] = true,
    [312411] = true,
    [312924] = true,
    [357214] = true,
    [368970] = true,
    [436344] = true,
    [1287685] = true,
}

CludesUI.RegisterMigration({
    id = "cdm_ghost_cd_bar_cleanup_v3",
    scope = "specProfile",
    description = "Strip junk entries from the ghost CD bar: negative IDs (presets/trinkets), racials, customs (best-effort), and duplicates of spells already on a real bar.",
    body = function(context)
        -- Idempotent: junk entries gone after first run. Customs detection is
        -- best-effort -- customs predating bs.customSpellIDs stamping, or tracked
        -- via the now-wiped legacy bs.customSpells, are undetectable and stay on
        -- the hidden ghost bar (cosmetic-only impact).
        local barSpellMap = context.specProfile.barSpells
        if type(barSpellMap) ~= "table" then
            return
        end

        local GHOST_CD = "__ghost_cd"
        local GHOST_BUFF = "__ghost_buffs"

        local ghostBS = barSpellMap[GHOST_CD]
        if not (ghostBS and ghostBS.assignedSpells) then
            return
        end

        -- Spells currently on real bars + currently stamped as custom.
        local realBarSpells = {}
        local customSet = {}
        for barKey, barConf in pairs(barSpellMap) do
            if barKey ~= GHOST_CD and barKey ~= GHOST_BUFF and type(barConf) == "table" then
                if barConf.assignedSpells then
                    for _, spellRef in ipairs(barConf.assignedSpells) do
                        if spellRef and spellRef > 0 then
                            realBarSpells[spellRef] = true
                        end
                    end
                end
                if barConf.customSpellIDs then
                    for spellRef in pairs(barConf.customSpellIDs) do
                        customSet[spellRef] = true
                    end
                end
            end
        end

        for index = #ghostBS.assignedSpells, 1, -1 do
            local spellRef = ghostBS.assignedSpells[index]
            if
                spellRef
                and (
                    spellRef <= 0
                    or customSet[spellRef]
                    or CDM_ALL_RACIAL_SPELL_IDS[spellRef]
                    or realBarSpells[spellRef]
                )
            then
                table.remove(ghostBS.assignedSpells, index)
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_ghost_strip_racials_v1",
    scope = "specProfile",
    description = "Remove racial spells from ghost CD bar (racials should never be ghosted)",
    body = function(context)
        local barSpellMap = context.specProfile.barSpells
        if type(barSpellMap) ~= "table" then
            return
        end
        local ghostBS = barSpellMap["__ghost_cd"]
        if not (ghostBS and ghostBS.assignedSpells) then
            return
        end
        for index = #ghostBS.assignedSpells, 1, -1 do
            local spellRef = ghostBS.assignedSpells[index]
            if spellRef and CDM_ALL_RACIAL_SPELL_IDS[spellRef] then
                table.remove(ghostBS.assignedSpells, index)
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_strip_legacy_spell_keys",
    scope = "specProfile",
    description = "Strip legacy trackedSpells/customSpells keys from CDM bar data. The current shape is bs.assignedSpells; legacy keys are no longer written by any code path.",
    body = function(context)
        -- Idempotent (nil to nil). Cold profiles with legacy data LOSE those entries
        -- rather than being auto-ported -- schema has drifted too far for porting to
        -- produce valid entries. Bar comes up with assignedSpells == nil, which
        -- new-spec auto-population fills with defaults.
        local barSpellMap = context.specProfile.barSpells
        if type(barSpellMap) ~= "table" then
            return
        end

        for _, barConf in pairs(barSpellMap) do
            if type(barConf) == "table" then
                barConf.trackedSpells = nil
                barConf.customSpells = nil
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_consolidate_buff_bars",
    scope = "global",
    description = "Remove all extra (custom) buff bars across every parent profile, nil stale assignedSpells on the main buffs bar across every spec profile, and prune orphaned spell data for the deleted bars. Replaces the old _buffBarMigrationV2Done and _buffsBarCleanupV2 inline migrations.",
    body = function(context)
        -- Idempotent: no-op once extra buff bars are gone and main-buffs
        -- assignedSpells is nil. Main "buffs" bar is Blizzard-owned/auto-populated
        -- from the CDM viewer, so it must never carry manual assignedSpells;
        -- extra/custom buff bars (custom_5_1234 etc.) are removed entirely --
        -- list entries AND spell data both go.
        local removedBuffBarKeys = {}

        -- 1. Walk every parent profile, drop extra buff bars from the
        -- bar list, and remember their keys for the spell-data prune.
        if context.db.profiles then
            for _, profileRec in pairs(context.db.profiles) do
                local cdmStore = profileRec.addons and profileRec.addons.CludesUICooldownManager
                local cdmBars = cdmStore and cdmStore.cdmBars
                local barList = cdmBars and cdmBars.bars
                if type(barList) == "table" then
                    local keptCount = {}
                    for _, edge in ipairs(barList) do
                        if edge.barType == "buffs" and edge.key ~= "buffs" then
                            removedBuffBarKeys[edge.key] = true
                        else
                            keptCount[#keptCount + 1] = edge
                        end
                    end
                    cdmBars.bars = keptCount
                end
            end
        end

        -- 2. Walk every spec profile: nil stale main-buffs assignedSpells and
        -- prune orphaned spell data for the deleted extra bars.
        for _, specProfile in ipairs(CollectSpecProfiles(context.db.spellAssignments)) do
            local barSpellMap = specProfile.barSpells
            if type(barSpellMap) == "table" then
                if barSpellMap["buffs"] then
                    barSpellMap["buffs"].assignedSpells = nil
                end
                for removedKey in pairs(removedBuffBarKeys) do
                    barSpellMap[removedKey] = nil
                end
            end
        end

        -- 3. Wipe the old manual flag bytes: the runner's flag replaces them.
        context.db._buffBarMigrationV2Done = nil
        context.db._buffsBarCleanupV2 = nil
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_wipe_legacy_glows_tbb_locations",
    scope = "global",
    description = "Wipe legacy bar glows / TBB / tbbPositions storage locations. The data was moved to per-spec storage in v5.5.7. No live code writes to these locations anymore -- they are dead bytes that the previous inline migration was still trying to copy out.",
    body = function(context)
        -- Idempotent (nil=nil). Anything remaining belongs to cold profiles/specs;
        -- active users already ported to per-spec storage. Discriminator is
        -- LOCATION not content: top-level spellAssignments.barGlows and the parent
        -- profile's CDM block are legacy by definition -- live code writes only to
        -- spellAssignments.specProfiles[specKey].X.

        local assignments = context.db.spellAssignments
        if assignments then
            assignments.barGlows = nil
        end

        if context.db.profiles then
            for _, profileRec in pairs(context.db.profiles) do
                local cdmStore = profileRec.addons and profileRec.addons.CludesUICooldownManager
                if cdmStore then
                    cdmStore.trackedBuffBars = nil
                    cdmStore.tbbPositions = nil
                end
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_strip_position_based_glow_keys",
    scope = "specProfile",
    description = "Strip old position-based CDM bar glow assignment keys (101_*, 102_*) from barGlows.assignments. These were tied to bar index + button index and broke when CDM icons reordered during reanchor. The new format keys are cdm_<cooldownID>.",
    body = function(context)
        -- Idempotent: after the first run no 10[12]_ keys remain. Action bar keys
        -- (1_* through 8_*) and the new cdm_<id> format keys are left alone.
        local backdrop = context.specProfile.barGlows
        local assignments = backdrop and backdrop.assignments
        if type(assignments) ~= "table" then
            return
        end

        for fieldKey in pairs(assignments) do
            if type(fieldKey) == "string" and fieldKey:match("^10[12]_") then
                assignments[fieldKey] = nil
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_remove_discontinued_presets",
    scope = "specProfile",
    description = "Remove preset versions of discontinued spells (Bloodlust + variants, Time Spiral, warlock pets) from CDM bars and TBB bars. These presets were removed from the picker because they can't be tracked via cooldown detection.",
    body = function(context)
        -- Idempotent: IDs/TBB bars gone after first run. customSpellDurations is the
        -- safety guard: a real class spell sharing an ID (e.g. Shaman Heroism 32182)
        -- never carries this stamp since it came from the regular picker, not the
        -- preset adder, so real spells are never collateral. presetVariants wipe is
        -- separate stale-field cleanup; nothing reads it.
        local removedPresets = {
            [2825] = true,
            [32182] = true,
            [80353] = true,
            [264667] = true,
            [390386] = true,
            [381301] = true,
            [444062] = true,
            [444257] = true, -- Bloodlust variants
            [104316] = true,
            [265187] = true,
            [264119] = true,
            [111898] = true, -- Warlock pets
        }
        local removedPopularKeys = {
            bloodlust = true,
            time_spiral = true,
            call_dreadstalkers = true,
            demonic_tyrant = true,
            summon_vilefiend = true,
            grimoire_felguard = true,
        }

        local barSpellMap = context.specProfile.barSpells
        if type(barSpellMap) == "table" then
            for _, barConf in pairs(barSpellMap) do
                if type(barConf) == "table" then
                    if barConf.assignedSpells and barConf.customSpellDurations then
                        for index = #barConf.assignedSpells, 1, -1 do
                            local spellRef = barConf.assignedSpells[index]
                            if removedPresets[spellRef] and barConf.customSpellDurations[spellRef] then
                                table.remove(barConf.assignedSpells, index)
                                barConf.customSpellDurations[spellRef] = nil
                            end
                        end
                    end
                    barConf.presetVariants = nil
                end
            end
        end

        -- Clean removed presets from TBB. Other popular presets (potions etc.) are kept.
        local trackingBars = context.specProfile.trackedBuffBars
        if trackingBars and type(trackingBars.bars) == "table" then
            for index = #trackingBars.bars, 1, -1 do
                local barConf = trackingBars.bars[index]
                if barConf.popularKey and removedPopularKeys[barConf.popularKey] then
                    table.remove(trackingBars.bars, index)
                end
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_strip_buff_bar_item_ids_v1",
    scope = "specProfile",
    description = "Remove item-ID (negative -itemID) entries from CDM buff bars. Buff bars track auras only (positive spell IDs); items can no longer be placed on them. CD/utility bars (which legitimately hold trinkets/potions) are left untouched.",
    body = function(context)
        -- Idempotent: only NEGATIVE ids are removed, so a re-run finds none.
        local specList = context.specProfile
        local barSpellMap = specList and specList.barSpells
        if type(barSpellMap) ~= "table" then
            return
        end

        -- Resolves BUFF bar keys from this profile's bar config (barType); "buffs"
        -- is always seeded even if config is absent. Only buff bars are stripped --
        -- cooldown/utility bars keep legitimate trinket/potion markers.
        local buffKeySet = { buffs = true }
        local profileTbl = CludesUIDB.profiles and CludesUIDB.profiles[context.profileName]
        local cdmStore = profileTbl and profileTbl.addons and profileTbl.addons.CludesUICooldownManager
        local barList = cdmStore and cdmStore.cdmBars and cdmStore.cdmBars.bars
        if type(barList) == "table" then
            for _, bar in ipairs(barList) do
                if type(bar) == "table" and bar.barType == "buffs" and type(bar.key) == "string" then
                    buffKeySet[bar.key] = true
                end
            end
        end

        for barId, barConf in pairs(barSpellMap) do
            if buffKeySet[barId] and type(barConf) == "table" and type(barConf.assignedSpells) == "table" then
                local as = barConf.assignedSpells
                for index = #as, 1, -1 do
                    local ident = as[index]
                    -- Negative ids are item markers (-itemID / trinket slots);
                    -- positive ids are real buff spell IDs and are kept verbatim.
                    if type(ident) == "number" and ident < 0 then
                        table.remove(as, index)
                        -- Drop any per-id side data so nothing dangles.
                        if type(barConf.spellSettings) == "table" then
                            barConf.spellSettings[ident] = nil
                        end
                        if type(barConf.spellDurations) == "table" then
                            barConf.spellDurations[ident] = nil
                        end
                        if type(barConf.customSpellDurations) == "table" then
                            barConf.customSpellDurations[ident] = nil
                        end
                    end
                end
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_unanchor_buff_bars",
    scope = "global",
    description = "Clear unlock anchors that target CDM buff/custom_buff bars or the Buff Reminders frame. Dynamic bars (resize with auras) cause cascading position shifts when used as anchor targets.",
    body = function(context)
        -- Self-gating: predicate false once targeting anchors are cleared. Buff key
        -- set unions ALL profiles, so inactive-profile buff bars count too.
        local anchorMap = context.db.unlockAnchors
        if not anchorMap then
            return
        end

        local buffKeySet = {}
        if context.db.profiles then
            for _, profileRec in pairs(context.db.profiles) do
                local cdmStore = profileRec.addons and profileRec.addons.CludesUICooldownManager
                local barList = cdmStore and cdmStore.cdmBars and cdmStore.cdmBars.bars
                if type(barList) == "table" then
                    for _, edge in ipairs(barList) do
                        if
                            edge.barType == "buffs"
                            or edge.key == "buffs"
                            or edge.barType == "custom_buff"
                        then
                            buffKeySet["CDM_" .. edge.key] = true
                        end
                    end
                end
            end
        end
        -- AuraBuff Reminders is also dynamic regardless of profile.
        buffKeySet["EABR_Reminders"] = true

        for childKey, details in pairs(anchorMap) do
            if details.target and buffKeySet[details.target] then
                anchorMap[childKey] = nil
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_active_state_per_bar_to_per_icon",
    scope = "profile",
    description = "Promote per-bar activeStateAnim='hideActive' to per-icon activeSwipeMode='none' across every spec profile, then reset the bar-level value to 'blizzard'.",
    body = function(context)
        -- Mixed scope: outer walk is per-profile (cdmBars.bars, gated by the
        -- runner's per-profile flag); inner per-spec-profile walk
        -- (barSpells/spellSettings) is done by the body itself, self-gating via
        -- bd.activeStateAnim="blizzard" after migrating. REQUIRES
        -- cdm_active_state_anim_none_to_hideactive first (renames legacy 'none' to
        -- 'hideActive', which this body matches).
        local cdmStore = context.profile.addons and context.profile.addons.CludesUICooldownManager
        local cdmBars = cdmStore and cdmStore.cdmBars
        local barList = cdmBars and cdmBars.bars
        if type(barList) ~= "table" then
            return
        end

        -- Spell store is per-profile (spellAssignments.profiles[name].specProfiles).
        -- Collect buckets directly, not via ns.GetSpecProfiles: CDM hasn't
        -- initialized at early phase, but seeding already ran so buckets exist.
        local specProfs = CollectSpecProfiles(CludesUIDB and CludesUIDB.spellAssignments)

        for _, edge in ipairs(barList) do
            if edge.activeStateAnim == "hideActive" and not edge.isGhostBar then
                for _, profileTbl in ipairs(specProfs) do
                    local barSpellMap = profileTbl and profileTbl.barSpells
                    local barConf = barSpellMap and barSpellMap[edge.key]
                    if barConf and barConf.assignedSpells then
                        if not barConf.spellSettings then
                            barConf.spellSettings = {}
                        end
                        for _, spellRef in ipairs(barConf.assignedSpells) do
                            if spellRef and spellRef > 0 then
                                if not barConf.spellSettings[spellRef] then
                                    barConf.spellSettings[spellRef] = {}
                                end
                                local ss = barConf.spellSettings[spellRef]
                                -- Skip icons with an explicit per-icon active state already set.
                                if not ss.activeSwipeMode and not ss.activeSwipeR then
                                    ss.activeSwipeMode = "none"
                                end
                            end
                        end
                    end
                end
                -- Clear the per-bar setting so re-runs find nothing.
                edge.activeStateAnim = "blizzard"
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "cdm_buff_assignedspells_reseed_v1",
    scope = "specProfile",
    description = "Clear buffs.assignedSpells so the unified model re-seeds from live icons (buff/CD unification).",
    body = function(context)
        -- Under the unified model EnsureAssignedSpells lazily seeds the buff bar
        -- from live icons, so stale stored data must be cleared to re-seed clean.
        local barConf = context.specProfile.barSpells
        if not barConf then
            return
        end
        local buffData = barConf["buffs"]
        if buffData and buffData.assignedSpells then
            buffData.assignedSpells = nil
        end
    end,
})

--------------------------------------------------------------------------------
--  Bar Texture -> global setting
--  Bar Texture dropdown writes db.profile.healthBarTexture instead of per-unit
--  keys. Promote first non-"none" texture among player/target/focus (in order)
--  to the global key, then strip per-unit overrides so none shadows it.
--------------------------------------------------------------------------------
CludesUI.RegisterMigration({
    id = "v67_bar_texture_global",
    scope = "profile",
    description = "Promote per-unit healthBarTexture to a single global profile key.",
    body = function(context)
        local ufStore = context.profile.addons and context.profile.addons.CludesUIUnitFrames
        if type(ufStore) ~= "table" then
            return
        end

        local winner -- first non-"none" override, in canonical order
        for _, unitToken in ipairs({ "player", "target", "focus" }) do
            local cfg = ufStore[unitToken]
            local val = type(cfg) == "table" and cfg.healthBarTexture
            if type(val) == "string" and val ~= "" and val ~= "none" then
                winner = val
                break
            end
        end

        if winner and (ufStore.healthBarTexture == nil or ufStore.healthBarTexture == "none") then
            ufStore.healthBarTexture = winner
        end

        -- Strip per-unit overrides so the global value is the single source.
        for _, unitToken in ipairs({ "player", "target", "focus", "pet", "totPet", "boss" }) do
            local cfg = ufStore[unitToken]
            if type(cfg) == "table" then
                cfg.healthBarTexture = nil
            end
        end
    end,
})

--------------------------------------------------------------------------------
--  Quest Tracker: reset stale enabled=false inherited from Basics.
--  v66_basics_split_data copied the whole questTracker table across; old
--  "enabled" meant "disable the custom overlay" (Blizzard's tracker still
--  showed), but new QT's EvalVisibility reads it as "completely hide the
--  tracker" -- an inherited false hid it with no way back (not exposed).
--------------------------------------------------------------------------------
CludesUI.RegisterMigration({
    id = "qt_minimap_ensure_enabled_v2",
    scope = "profile",
    description = "Ensure quest tracker / minimap have enabled=true and visibility=always when missing or false.",
    body = function(context)
        local addonStores = context.profile.addons
        if type(addonStores) ~= "table" then
            return
        end
        local trackerCfg = addonStores.CludesUIQuestTracker and addonStores.CludesUIQuestTracker.questTracker
        if type(trackerCfg) == "table" then
            if not trackerCfg.enabled then
                trackerCfg.enabled = true
            end
            if not trackerCfg.visibility then
                trackerCfg.visibility = "always"
            end
        end
        local minimapCfg = addonStores.CludesUIMinimap and addonStores.CludesUIMinimap.minimap
        if type(minimapCfg) == "table" then
            if not minimapCfg.enabled then
                minimapCfg.enabled = true
            end
            if not minimapCfg.visibility then
                minimapCfg.visibility = "always"
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "mt_bestruns_wipe_v1",
    scope = "global",
    description = "Wipe obsolete Mythic+ bestRuns data (feature removed). Clears CludesUIDB.global.bestRuns and every profile's addons.CludesUIMythicTimer.bestRuns.",
    body = function(context)
        if context.db.global then
            context.db.global.bestRuns = nil
        end

        local profileSet = context.db.profiles
        if type(profileSet) == "table" then
            for _, profileRec in pairs(profileSet) do
                local timerCfg = profileRec and profileRec.addons and profileRec.addons.CludesUIMythicTimer
                if type(timerCfg) == "table" then
                    timerCfg.bestRuns = nil
                end
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "power_color_defaults_v5",
    scope = "global",
    description = "Migrate users on old power color defaults (Mana/Rage/Focus/Energy) to new defaults",
    body = function(context)
        local clickCfg = context.db.customColors
        if not clickCfg or not clickCfg.power then
            return
        end
        -- Old defaults that shipped before this migration
        local function near(a, b)
            return math.abs(a - b) < 0.01
        end
        local function matchesOld(current, old)
            return current and near(current.r, old.r) and near(current.g, old.g) and near(current.b, old.b)
        end
        local OLD = {
            MANA = { { r = 0x33 / 255, g = 0x59 / 255, b = 0xD9 / 255 } },
            RAGE = { { r = 1.000, g = 0.000, b = 0.000 } },
            FOCUS = { { r = 1.000, g = 0.500, b = 0.250 }, { r = 0.770, g = 0.530, b = 0.240 } },
            ENERGY = { { r = 1.000, g = 1.000, b = 0.000 } },
            RUNIC_POWER = { { r = 0.000, g = 0.820, b = 1.000 } },
            LUNAR_POWER = { { r = 0.300, g = 0.520, b = 0.900 } },
            MAELSTROM = { { r = 0.000, g = 0.500, b = 1.000 } },
        }
        for fieldKey, oldList in pairs(OLD) do
            local current = clickCfg.power[fieldKey]
            for _, old in ipairs(oldList) do
                if matchesOld(current, old) then
                    clickCfg.power[fieldKey] = nil
                    break
                end
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "power_color_fury_to_classcolor_v1",
    scope = "global",
    description = "Migrate Fury (DH) power color from old purple default to DH class color (A330C9).",
    body = function(context)
        local clickCfg = context.db.customColors
        if not clickCfg or not clickCfg.power then
            return
        end
        local current = clickCfg.power.FURY
        if not current then
            return
        end
        local function near(a, b)
            return math.abs(a - b) < 0.01
        end
        if near(current.r, 0.788) and near(current.g, 0.259) and near(current.b, 0.992) then
            clickCfg.power.FURY = nil
        end
    end,
})

CludesUI.RegisterMigration({
    id = "chat_mouseover_to_always_v1",
    scope = "global",
    description = "Migrate chat visibility from 'mouseover' to 'always' (mouseover removed, idle fade replaces it).",
    body = function(context)
        local chatDB = _G.CludesUIChatDB
        if not chatDB or not chatDB.profiles then
            return
        end
        for _, profileRec in pairs(chatDB.profiles) do
            if profileRec.chat and profileRec.chat.visibility == "mouseover" then
                profileRec.chat.visibility = "always"
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "chat_bubbles_to_blizzskin_v1",
    scope = "profile",
    description = "Move Chat Bubbles settings from the Chat module profile to the profile root (Blizz UI Enhanced).",
    body = function(context)
        local chatCfg = context.profile.addons and context.profile.addons.CludesUIChat
        if not chatCfg or type(chatCfg.chatBubbles) ~= "table" then
            return
        end
        if context.profile.chatBubbles == nil then
            context.profile.chatBubbles = chatCfg.chatBubbles
        end
        chatCfg.chatBubbles = nil
    end,
})

CludesUI.RegisterMigration({
    id = "np_border_cludes_to_simple_v3",
    scope = "profile",
    description = "No-op (superseded by np_border_v5).",
    body = function() end,
})

CludesUI.RegisterMigration({
    id = "np_border_v5",
    scope = "profile",
    description = "Migrate borderStyle/simpleBorderSize to showBorder/borderSize. 'none' -> showBorder=false, everything else -> showBorder=true, borderSize=1.",
    body = function(context)
        local plateCfg = context.profile.addons and context.profile.addons.CludesUINameplates
        if not plateCfg then
            return
        end
        local oldStyle = plateCfg.borderStyle
        if oldStyle == "none" then
            plateCfg.showBorder = false
        else
            plateCfg.showBorder = true
        end
        plateCfg.borderSize = 1
        plateCfg.borderStyle = nil
        plateCfg.simpleBorderSize = nil
    end,
})

CludesUI.RegisterMigration({
    id = "uf_absorb_style_dropdown_v1",
    scope = "profile",
    description = "Migrate showPlayerAbsorb from boolean toggle to style string dropdown. true -> 'striped', false/nil -> 'none'.",
    body = function(context)
        local ufStore = context.profile.addons and context.profile.addons.CludesUIUnitFrames
        if not ufStore then
            return
        end
        for _, unitName in ipairs({ "player", "target", "playerTarget", "focus" }) do
            local unitConf = ufStore[unitName]
            if unitConf then
                local val = unitConf.showPlayerAbsorb
                if val == true then
                    unitConf.showPlayerAbsorb = "striped"
                elseif val == false or val == nil then
                    unitConf.showPlayerAbsorb = "none"
                end
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "uf_absorb_style_boolean_sweep_v1",
    scope = "profile",
    description = "Normalise any remaining boolean showPlayerAbsorb to a style string. uf_absorb_style_dropdown_v1 walked a fixed unit list and stamps per profile, so a profile that arrived AFTER it ran -- an import or a preset, both of which inherit the recipient's migration flags -- kept the legacy boolean.",
    body = function(context)
        -- Walk every table in the UF blob, not a fixed unit list: the earlier pass
        -- missed unnamed units, and any unit's bad value causes the crash.
        local ufStore = context.profile.addons and context.profile.addons.CludesUIUnitFrames
        if type(ufStore) ~= "table" then
            return
        end
        for _, unitConf in pairs(ufStore) do
            if type(unitConf) == "table" then
                local val = unitConf.showPlayerAbsorb
                if val == true then
                    unitConf.showPlayerAbsorb = "striped" -- v1's mapping for true
                elseif val ~= nil and type(val) ~= "string" then
                    unitConf.showPlayerAbsorb = "none"
                end
            end
        end
    end,
})

-- Remove the ghost buff bar (buff visibility is managed by Blizzard CDM settings): drop
-- the bar entry from all profiles and the spell data from all spec profiles.
CludesUI.RegisterMigration({
    id = "cdm_remove_ghost_buff_bar_v1",
    scope = "profile",
    description = "Remove __ghost_buffs bar entry from cdmBars.bars array (original, wrong path).",
    body = function() end,
})
CludesUI.RegisterMigration({
    id = "cdm_remove_ghost_buff_bar_v2",
    scope = "profile",
    description = "Remove __ghost_buffs bar entry from cdmBars.bars array (correct path).",
    body = function(context)
        local cdmStore = context.profile.addons and context.profile.addons.CludesUICooldownManager
        local barList = cdmStore and cdmStore.cdmBars and cdmStore.cdmBars.bars
        if not barList then
            return
        end
        for index = #barList, 1, -1 do
            if barList[index].key == "__ghost_buffs" then
                table.remove(barList, index)
            end
        end
    end,
})
CludesUI.RegisterMigration({
    id = "cdm_remove_ghost_buff_spelldata_v1",
    scope = "global",
    description = "Remove __ghost_buffs spell data from all spec profiles.",
    body = function(context)
        for _, specRec in ipairs(CollectSpecProfiles(context.db and context.db.spellAssignments)) do
            if specRec.barSpells then
                specRec.barSpells["__ghost_buffs"] = nil
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "rf_split_absorb_edge_mode_v1",
    scope = "profile",
    description = "Split the shared Raid Frames absorbFromRightEdge toggle into independent absorbEdgeMode / healAbsorbEdgeMode (overlay/right/left) per bar.",
    body = function(context)
        local raidCfg = context.profile.addons and context.profile.addons.CludesUIRaidFrames
        if type(raidCfg) ~= "table" then
            return
        end
        -- Existing users with the old toggle ON get both bars set to "right" (look
        -- unchanged); false/absent -> "overlay" default. Idempotent: unset keys only.
        local function split(oldKey, absKey, healKey)
            local old = raidCfg[oldKey]
            if old == nil then
                return
            end
            local modeName = (old == true) and "right" or "overlay"
            if raidCfg[absKey] == nil then
                raidCfg[absKey] = modeName
            end
            if raidCfg[healKey] == nil then
                raidCfg[healKey] = modeName
            end
        end
        split("absorbFromRightEdge", "absorbEdgeMode", "healAbsorbEdgeMode")
        split("party_absorbFromRightEdge", "party_absorbEdgeMode", "party_healAbsorbEdgeMode")
    end,
})

CludesUI.RegisterMigration({
    id = "uf_castbar_standalone_v1",
    scope = "profile",
    description = "Resolve castbar width=0 to real frame width and set default unlock anchors for standalone cast bars.",
    body = function(context)
        local ufStore = context.profile.addons and context.profile.addons.CludesUIUnitFrames
        if not ufStore then
            return
        end
        local positions = ufStore.positions or ufStore.unlockPositions
        local anchorMap = CludesUIDB and CludesUIDB.unlockAnchors

        local playerScale = ufStore.player
        if playerScale then
            local pw = playerScale.playerCastbarWidth or 0
            if pw == 0 then
                playerScale.playerCastbarWidth = playerScale.frameWidth or 181
            end
            local ph = playerScale.playerCastbarHeight or 0
            if ph == 0 then
                playerScale.playerCastbarHeight = playerScale.castbarHeight or 14
            end
        end

        for _, unitName in ipairs({ "target", "focus" }) do
            local cfg = ufStore[unitName]
            if cfg then
                local cw = cfg.castbarWidth or 0
                if cw == 0 then
                    cfg.castbarWidth = cfg.frameWidth or 181
                end
            end
        end

        -- Default unlock anchors only for cast bars with no position and no anchor.
        if anchorMap then
            local CASTBAR_DEFAULTS = {
                { key = "playerCastbar", target = "player" },
                { key = "targetCastbar", target = "target" },
                { key = "focusCastbar", target = "focus" },
            }
            for _, default in ipairs(CASTBAR_DEFAULTS) do
                local hasPos = positions and positions[default.key]
                local hasAnchor = anchorMap[default.key]
                if not hasPos and not hasAnchor then
                    anchorMap[default.key] = {
                        target = default.target,
                        side = "BOTTOM",
                        offsetX = 0,
                        offsetY = 0,
                    }
                end
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "mythic_timer_default_pos_to_otf_v2",
    scope = "profile",
    description = "Wipe M+ Timer position if it matches the old hardcoded default (0,0) so the new OTF-based default kicks in.",
    body = function(context)
        local emt = context.profile.addons and context.profile.addons.CludesUIMythicTimer
        if not emt then
            return
        end
        local place = emt.standalonePos
        if not place then
            return
        end
        if
            place.centerX
            and place.centerY
            and math.abs(place.centerX) < 3
            and math.abs(place.centerY) < 3
        then
            emt.standalonePos = nil
        end
    end,
})

CludesUI.RegisterMigration({
    id = "np_stacking_spacing_50_to_75_v2",
    scope = "profile",
    description = "Bump nameplate stacking spacing from old default 50 to 75 for better separation.",
    body = function(context)
        local plateCfg = context.profile.addons and context.profile.addons.CludesUINameplates
        if not plateCfg then
            plateCfg = {}
            context.profile.addons = context.profile.addons or {}
            context.profile.addons.CludesUINameplates = plateCfg
        end
        local current = plateCfg.stackSpacingScale
        if not current or current == 50 then
            plateCfg.stackSpacingScale = 90
        end
    end,
})

CludesUI.RegisterMigration({
    id = "break_blizz_owned_anchors_v1",
    scope = "global",
    description = "Remove anchor relationships involving MicroBar, BagBar, and QueueStatus (Blizzard-owned frames that cannot participate in anchor chains).",
    body = function(context)
        local anchorMap = context.db.unlockAnchors
        if not anchorMap then
            return
        end
        local BLIZZ_OWNED = { MicroBar = true, BagBar = true, QueueStatus = true }
        for childKey, details in pairs(anchorMap) do
            if BLIZZ_OWNED[childKey] or (details.target and BLIZZ_OWNED[details.target]) then
                anchorMap[childKey] = nil
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "ab_queuestatus_reset_visibility_v1",
    scope = "profile",
    description = "Reset stale QueueStatus (LFG eye) visibility/mouseover settings to neutral. CUI used to control the eye's visibility but now only controls its position; old saved values (e.g. barVisibility 'mouseover' with mouseoverAlpha 0) could leave the eye permanently invisible with no UI left to restore it.",
    body = function(context)
        local barsCfg = context.profile.addons and context.profile.addons.CludesUIActionBars
        local qs = barsCfg and barsCfg.bars and barsCfg.bars.QueueStatus
        if type(qs) ~= "table" then
            return
        end
        -- Neutral defaults (matches the EXTRA_BARS defaults): always-visible, no
        -- mouseover fade, no combat/housing/instance hiding.
        qs.barVisibility = "always"
        qs.alwaysHidden = false
        qs.mouseoverEnabled = false
        qs.mouseoverAlpha = 1
        qs._savedBarAlpha = nil
        qs.combatHideEnabled = false
        qs.combatShowEnabled = false
        qs.housingHideEnabled = false
        qs.visHideHousing = false
        qs.visOnlyInstances = false
    end,
})

CludesUI.RegisterMigration({
    id = "uf_per_unit_portrait_style_v1",
    scope = "profile",
    description = "Copy global portraitStyle into player/target/focus per-unit tables.",
    body = function(context)
        local ufStore = context.profile.addons and context.profile.addons.CludesUIUnitFrames
        if not ufStore then
            return
        end
        local global = ufStore.portraitStyle or "attached"
        for _, unitName in ipairs({ "player", "target", "focus" }) do
            local cfg = ufStore[unitName]
            if cfg and cfg.portraitStyle == nil then
                cfg.portraitStyle = global
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "uf_split_totpet_into_tot_focus_v1",
    scope = "profile",
    description = "Split shared totPet unit-frame settings into independent targettarget and focustarget tables.",
    body = function(context)
        local ufStore = context.profile.addons and context.profile.addons.CludesUIUnitFrames
        if type(ufStore) ~= "table" then
            return
        end
        local tp = ufStore.totPet
        if type(tp) ~= "table" then
            return
        end
        -- Self-contained deep copy (do not depend on an external helper).
        local function DCopy(src)
            if type(src) ~= "table" then
                return src
            end
            local copy = {}
            for k, val in pairs(src) do
                copy[k] = DCopy(val)
            end
            return copy
        end
        -- Copies old shared overrides into BOTH new tables so each mini renders
        -- identically. Overwrites unconditionally: totPet only exists pre-split, so
        -- any targettarget/focustarget present are default-merge artifacts (e.g.
        -- an import's DeepMergeDefaults), never user-authored. Deleting totPet
        -- after makes re-runs a no-op regardless of the flag.
        ufStore.targettarget = DCopy(tp)
        ufStore.focustarget = DCopy(tp)
        ufStore.totPet = nil
    end,
})

CludesUI.RegisterMigration({
    id = "uf_boss_simple_text_seed_v1",
    scope = "profile",
    description = "Seed boss simple-display cooldown-text show/size from customized regular keys so old profiles keep their text settings under the default-on Simple Display.",
    body = function(context)
        local ufStore = context.profile.addons and context.profile.addons.CludesUIUnitFrames
        local b = type(ufStore) == "table" and ufStore.boss
        if type(b) ~= "table" then
            return
        end
        -- Simple Debuff Display defaults ON ("left"); renderer reads simple* text
        -- keys, which DeepMergeDefaults fills false/14 on profiles predating them,
        -- so a customized regular size stays stored but unread. Seed simple keys
        -- from regular ones before the merge masks them -- regular defaults
        -- (10/false) are the "was it customized" sentinels, since StripDefaults
        -- nils default-equal values.
        if
            b.simpleDebuffCooldownTextSize == nil
            and type(b.debuffCooldownTextSize) == "number"
            and b.debuffCooldownTextSize ~= 10
        then
            b.simpleDebuffCooldownTextSize = b.debuffCooldownTextSize
        end
        if b.simpleDebuffShowCooldownText == nil and b.debuffShowCooldownText == true then
            b.simpleDebuffShowCooldownText = true
        end
        if
            b.simpleBuffCooldownTextSize == nil
            and type(b.buffCooldownTextSize) == "number"
            and b.buffCooldownTextSize ~= 10
        then
            b.simpleBuffCooldownTextSize = b.buffCooldownTextSize
        end
        if b.simpleBuffShowCooldownText == nil and b.buffShowCooldownText == true then
            b.simpleBuffShowCooldownText = true
        end
    end,
})

CludesUI.RegisterMigration({
    id = "charsheet_default_enabled_v1",
    scope = "global",
    description = "Preserve disabled default for existing users when flipping themedCharacterSheet to default-on.",
    body = function(context)
        -- Veterans only: a database with no profiles is a fresh install or a
        -- reset, and it must take the new default, not the preserved old one.
        if not (context.db.profiles and next(context.db.profiles)) then
            return
        end
        -- nil = never touched (old default = disabled): stamp false so the new
        -- nil-means-enabled logic can't flip them on. Explicit values are kept.
        if context.db.themedCharacterSheet == nil then
            context.db.themedCharacterSheet = false
        end
    end,
})

-------------------------------------------------------------------------------
--  Growth direction independent of anchoring
--  Anchoring no longer clears growDirection; stamp an explicit value on every
--  anchored CDM/AB bar so existing layouts stay visually identical. Anchor side
--  -> growth direction mapping is orientation-aware:
--    Horizontal: LEFT->LEFT, RIGHT->RIGHT, TOP->CENTER, BOTTOM->CENTER
--    Vertical:   TOP->UP, BOTTOM->DOWN, LEFT->CENTER, RIGHT->CENTER
-------------------------------------------------------------------------------
CludesUI.RegisterMigration({
    id = "unlock_grow_independent_v1",
    scope = "profile",
    description = "Set explicit growDirection on anchored CDM/AB bars to match their anchor side.",
    body = function(context)
        local anchorMap = CludesUIDB and CludesUIDB.unlockAnchors
        if not anchorMap then
            return
        end

        local HORIZ_MAP = { LEFT = "LEFT", RIGHT = "RIGHT", TOP = "CENTER", BOTTOM = "CENTER" }
        local VERT_MAP = { TOP = "UP", BOTTOM = "DOWN", LEFT = "CENTER", RIGHT = "CENTER" }

        -- CDM bars: always CENTER (nil meant CENTER for CDM), so the explicit stamp
        -- preserves behavior and avoids edge preservation on bars with no growEdge.
        local cdmStore = context.profile.addons and context.profile.addons.CludesUICooldownManager
        local cdmBars = cdmStore and cdmStore.cdmBars and cdmStore.cdmBars.bars
        if cdmBars then
            for _, barConf in ipairs(cdmBars) do
                local anchorKey = "CDM_" .. barConf.key
                local ai = anchorMap[anchorKey]
                if ai and ai.side and not barConf.growDirection then
                    barConf.growDirection = "CENTER"
                end
            end
        end
        -- growEdge promotion is handled by cdm_clear_stale_growedge_v1, run after.

        -- Action bars
        local barsCfg = context.profile.addons and context.profile.addons.CludesUIActionBars
        local abBars = barsCfg and barsCfg.bars
        if abBars then
            local AB_KEYS = {
                MainBar = true,
                Bar2 = true,
                Bar3 = true,
                Bar4 = true,
                Bar5 = true,
                Bar6 = true,
                Bar7 = true,
                Bar8 = true,
            }
            for barId, conf in pairs(abBars) do
                if AB_KEYS[barId] then
                    local ai = anchorMap[barId]
                    if ai and ai.side then
                        local current = conf.growDirection
                        -- Only migrate bars at default ("up" or nil)
                        if not current or current == "up" then
                            local vertical = (conf.orientation == "vertical")
                            local map = vertical and VERT_MAP or HORIZ_MAP
                            conf.growDirection = (map[ai.side] or "CENTER"):lower()
                        end
                    end
                end
            end
        end
    end,
})

-------------------------------------------------------------------------------
-- Converts CDM bar positions from CENTER+growEdge to direct edge format:
-- positions store the growth-edge anchor directly (LEFT for RIGHT-grow etc.) so
-- SetSize preserves the fixed edge with no re-anchoring; growEdge is promoted
-- into the primary fields, everything else stays as-is.
-------------------------------------------------------------------------------
CludesUI.RegisterMigration({
    id = "cdm_clear_stale_growedge_v1",
    scope = "profile",
    description = "Convert CDM bar positions to direct edge-anchor format.",
    body = function(context)
        local cdmStore = context.profile.addons and context.profile.addons.CludesUICooldownManager
        local cdmPositions = cdmStore and cdmStore.cdmBarPositions
        if not cdmPositions then
            return
        end
        for _, place in pairs(cdmPositions) do
            local growEdge = place.growEdge
            if growEdge and growEdge.anchor and growEdge.x and growEdge.y then
                place.point = growEdge.anchor
                place.x = growEdge.x
                place.y = growEdge.y
                place.growEdge = nil
            elseif growEdge then
                place.growEdge = nil -- incomplete: drop it
            end
        end
    end,
})

-------------------------------------------------------------------------------
-- Replaces the CDM "Anchor First Row" boolean with the rowGrowDirection enum.
-- anchorFirstRow pinned the leading perpendicular edge (TOP horizontal, LEFT
-- vertical), equivalent to "DOWN"/"RIGHT"; unset stays unset (centered growth default).
-------------------------------------------------------------------------------
CludesUI.RegisterMigration({
    id = "cdm_row_grow_direction_v1",
    scope = "profile",
    description = "Migrate CDM anchorFirstRow booleans to the rowGrowDirection enum.",
    body = function(context)
        local cdmStore = context.profile.addons and context.profile.addons.CludesUICooldownManager
        local barList = cdmStore and cdmStore.cdmBars and cdmStore.cdmBars.bars
        if not barList then
            return
        end
        for _, barConf in ipairs(barList) do
            if barConf.anchorFirstRow then
                if barConf.rowGrowDirection == nil then
                    barConf.rowGrowDirection = barConf.verticalOrientation and "RIGHT" or "DOWN"
                end
                barConf.anchorFirstRow = nil
            end
        end
    end,
})

-------------------------------------------------------------------------------
-- Migrates per-profile secondary threshold settings into thresholdSpecs:
-- thresholdEnabled becomes an "All Specs" entry carrying existing values; disabled leaves array empty.
-------------------------------------------------------------------------------
CludesUI.RegisterMigration({
    id = "resource_bars_threshold_specs_v1",
    scope = "profile",
    description = "Migrate secondary threshold settings into per-spec thresholdSpecs entries.",
    body = function(context)
        local resBarsCfg = context.profile.addons and context.profile.addons.CludesUIResourceBars
        local section = resBarsCfg and resBarsCfg.secondary
        if not section then
            return
        end
        if section.thresholdSpecs then
            return
        end -- already migrated
        if section.thresholdEnabled then
            section.thresholdSpecs = {
                {
                    specIDs = { 0 }, -- All Specs
                    hashValues = section.tickValues or "",
                    thresholdCount = section.thresholdCount or 3,
                    thresholdPartialOnly = section.thresholdPartialOnly or false,
                },
            }
        else
            section.thresholdSpecs = {}
        end
    end,
})

CludesUI.RegisterMigration({
    id = "resource_bars_power_threshold_specs_v1",
    scope = "profile",
    description = "Migrate power bar threshold settings into per-spec thresholdSpecs entries.",
    body = function(context)
        local resBarsCfg = context.profile.addons and context.profile.addons.CludesUIResourceBars
        local primaryCfg = resBarsCfg and resBarsCfg.primary
        if not primaryCfg then
            return
        end
        if primaryCfg.thresholdSpecs then
            return
        end
        if primaryCfg.thresholdEnabled then
            primaryCfg.thresholdSpecs = {
                {
                    specIDs = { 0 },
                    thresholdEnabled = true,
                    thresholdPct = primaryCfg.thresholdPct or 30,
                    thresholdPartialOnly = primaryCfg.thresholdPartialOnly or false,
                    thresholdR = primaryCfg.thresholdR or 1.0,
                    thresholdG = primaryCfg.thresholdG or 0.2,
                    thresholdB = primaryCfg.thresholdB or 0.2,
                    thresholdA = primaryCfg.thresholdA or 1,
                },
            }
        else
            primaryCfg.thresholdSpecs = {}
        end
    end,
})

CludesUI.RegisterMigration({
    id = "resource_bars_health_threshold_specs_v1",
    scope = "profile",
    description = "Migrate health bar threshold settings into per-spec thresholdSpecs entries.",
    body = function(context)
        local resBarsCfg = context.profile.addons and context.profile.addons.CludesUIResourceBars
        local healthCfg = resBarsCfg and resBarsCfg.health
        if not healthCfg then
            return
        end
        if healthCfg.thresholdSpecs then
            return
        end
        if healthCfg.thresholdEnabled then
            healthCfg.thresholdSpecs = {
                {
                    specIDs = { 0 },
                    thresholdEnabled = true,
                    thresholdPct = healthCfg.thresholdPct or 30,
                    thresholdR = healthCfg.thresholdR or 1.0,
                    thresholdG = healthCfg.thresholdG or 0.2,
                    thresholdB = healthCfg.thresholdB or 0.2,
                    thresholdA = healthCfg.thresholdA or 1,
                },
            }
        else
            healthCfg.thresholdSpecs = {}
        end
    end,
})

CludesUI.RegisterMigration({
    id = "ab_default_grow_to_center_v1",
    scope = "profile",
    description = "Convert AB bars with default UP growth to CENTER (UP now has real edge preservation).",
    body = function(context)
        local barsCfg = context.profile.addons and context.profile.addons.CludesUIActionBars
        local abBars = barsCfg and barsCfg.bars
        if not abBars then
            return
        end
        for barId, conf in pairs(abBars) do
            if not conf.growDirection or conf.growDirection == "up" then
                conf.growDirection = "center"
            end
        end
    end,
})

-- Action Bars Advanced Fade lost its on/off switch (advancedFadeEnabled): a bar
-- is on while one of its conditions is checked, and the conditions moved to a
-- key of their own (advancedFadeConditions) so this pass can tell old data from
-- new. A bar whose switch was on keeps its conditions; a bar whose switch was
-- off (its conditions left over from before) starts with none, off as before.
-- Both old keys go, so a second pass, or a profile born after the change (a
-- fresh install's first profile reaches this pass unstamped), finds nothing.
CludesUI.RegisterMigration({
    id = "ab_advanced_fade_conditions_v1",
    scope = "profile",
    description = "Advanced Fade is on while a condition is checked: carry the conditions of bars whose switch was on to advancedFadeConditions and drop the switch and the old conditions key.",
    body = function(context)
        local barsCfg = context.profile.addons and context.profile.addons.CludesUIActionBars
        local abBars = barsCfg and barsCfg.bars
        if type(abBars) ~= "table" then
            return
        end
        for _, conf in pairs(abBars) do
            if type(conf) == "table" and (conf.advancedFadeEnabled ~= nil or conf.fadeConditions ~= nil) then
                local old = conf.fadeConditions
                if conf.advancedFadeEnabled == true and type(old) == "table" then
                    local result
                    for k, val in pairs(old) do
                        if val then
                            result = result or {}
                            result[k] = true
                        end
                    end
                    if result then
                        conf.advancedFadeConditions = result
                    end
                end
                conf.advancedFadeEnabled = nil
                conf.fadeConditions = nil
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "enhance_five_bar_off_existing_v1",
    scope = "profile",
    description = "Existing profiles default enhanceFiveBar to false; new installs get true from defaults.",
    body = function(context)
        local resBarsCfg = context.profile.addons and context.profile.addons.CludesUIResourceBars
        local section = resBarsCfg and resBarsCfg.secondary
        if section and section.enhanceFiveBar == nil then
            section.enhanceFiveBar = false
        end
    end,
})

CludesUI.RegisterMigration({
    id = "auto_open_containers_preserve_v1",
    scope = "global",
    description = "Preserve autoOpenContainers for existing users after default changed from on to off.",
    body = function(context)
        local saved = context.db
        -- Existing users ONLY: on fresh install/factory reset no profiles exist yet
        -- at early-migration time, so nil here means NEW not "predates the flip" --
        -- without this gate a first install would get Auto Open Containers turned ON.
        if not (saved.profiles and next(saved.profiles)) then
            return
        end
        if saved.autoOpenContainers == nil then
            saved.autoOpenContainers = true
        end
    end,
})

-------------------------------------------------------------------------------
--  Bags profile migration: copy flat CludesUIDB root keys into each
--  profile's addons.CludesUIBags so the Bags module can use NewDB().
-------------------------------------------------------------------------------
CludesUI.RegisterMigration({
    id = "bags_to_profile_v1",
    scope = "global",
    description = "Migrate Bags settings from CludesUIDB root to per-profile storage.",
    body = function(context)
        local saved = context.db
        if not saved or not saved.profiles then
            return
        end

        local function DCopy(src)
            if type(src) ~= "table" then
                return src
            end
            local copy = {}
            for k, val in pairs(src) do
                copy[k] = DCopy(val)
            end
            return copy
        end

        local PROFILE_KEYS = {
            "bagScale",
            "bagColumns",
            "bagCatTitleSize",
            "bagCountFontSize",
            "itemlevelFontSize",
            "showItemlevelInBags",
            "showUpgradeIndicator",
            "bagShowTrackRank",
            "itemlevelUseCustomColor",
            "itemlevelCustomColor",
            "bagHideEmptyCategories",
            "bagSidebarCollapsed",
            "bankSidebarCollapsed",
            "bagShowPinnedItems",
            "bagShowRecentItems",
            "bagPinnedInOneBag",
            "bagRecentInOneBag",
            "bagShowPinRecentTips",
            "bagShowSortIcon",
            "bagHideRandomize",
            "bagDefaultOneBag",
            "bagNestByExpansion",
            "bagArmoryGroupBySlot",
            "bagCompactArmorySlotGroups",
            "bagHideOneBagWarning",
            "bagHideAddCategory",
            "bagMoveNoShift",
            "enableGoldTracking",
            "detachReagentBag",
            "enhancedBags",
            "bagCategoryState",
            "bagCategoryOrder",
            "bagDisabledCategories",
            "bagUserCategories",
            "bagsPosition",
            "bankPosition",
            "bagVisualOrder",
            "bagHiddenInAllItems",
            "currencyOrder",
        }

        for profileName, profileRec in pairs(saved.profiles) do
            if type(profileRec) == "table" then
                if not profileRec.addons then
                    profileRec.addons = {}
                end
                if not profileRec.addons.CludesUIBags then
                    local bagCfg = {}
                    for _, k in ipairs(PROFILE_KEYS) do
                        local val = saved[k]
                        if val ~= nil then
                            bagCfg[k] = DCopy(val)
                        end
                    end
                    if next(bagCfg) then
                        profileRec.addons.CludesUIBags = bagCfg
                    end
                end
            end
        end

        -- The Bags sync enable lives in the mirror-group reset migration below,
        -- which seeds the Bags group after wiping the old-format sync links.
    end,
})

-- The Bags "Default Open to OneBag" boolean became a three-way "Default Bag Type"
-- dropdown (all / onebag / multibag): seed the new key from the legacy boolean,
-- then drop it. Runs AFTER bags_to_profile_v1 so the legacy key already lives in
-- the per-profile bags table. Imported profiles inherit migration flags and skip
-- this, so ApplyProfileData (CludesUI_Profiles.lua) forward-copies the legacy
-- key before DeepMergeDefaults.
CludesUI.RegisterMigration({
    id = "bags_default_bag_type_v1",
    scope = "profile",
    description = "Convert legacy bagDefaultOneBag boolean into the bagDefaultBagType string (all/onebag/multibag).",
    body = function(context)
        local bagCfg = context.profile.addons and context.profile.addons.CludesUIBags
        if not bagCfg then
            return
        end -- fresh profile: defaults handle it
        if bagCfg.bagDefaultBagType ~= nil then
            return
        end -- already migrated (idempotent)
        bagCfg.bagDefaultBagType = (bagCfg.bagDefaultOneBag == true) and "onebag" or "all"
        bagCfg.bagDefaultOneBag = nil -- drop the legacy key
    end,
})

-- Close Bags on Mail Close became the Mailbox row of Auto Close Bags.
CludesUI.RegisterMigration({
    id = "bags_mail_close_to_auto_close_v1",
    scope = "global",
    description = "Move the retired Close Bags on Mail Close off state into every profile's Auto Close Bags.",
    body = function(context)
        local saved = context.db
        if saved.mailCloseBags == false and saved.profiles then
            for _, profileRec in pairs(saved.profiles) do
                if not profileRec.addons then
                    profileRec.addons = {}
                end
                local bagCfg = profileRec.addons.CludesUIBags
                if not bagCfg then
                    bagCfg = {}
                    profileRec.addons.CludesUIBags = bagCfg
                end
                if not bagCfg.bagAutoCloseWindows then
                    bagCfg.bagAutoCloseWindows = {}
                end
                bagCfg.bagAutoCloseWindows.mail = false
            end
        end
        saved.mailCloseBags = nil
    end,
})

-- Bags' Hide Items in Their Categories (pinned items) defaults on for fresh
-- installs and future profiles; every already-existing profile keeps it off
-- unless its user had turned it on. Same mechanism as the Guardian Ironfur
-- migration below.
CludesUI.RegisterMigration({
    id = "bags_hide_pinned_existing_off_v1",
    scope = "global",
    description = "Pin Bags' Hide Items in Their Categories OFF for existing users' profiles; fresh installs and future profiles inherit the new ON default.",
    body = function(context)
        local saved = context.db
        if not saved or not saved.profiles then
            return
        end
        for _, profileRec in pairs(saved.profiles) do
            -- Only profiles with real child-addon data: an empty/stub profile
            -- isn't an existing user's.
            if type(profileRec) == "table" and type(profileRec.addons) == "table" and next(profileRec.addons) then
                local bagCfg = profileRec.addons.CludesUIBags
                if type(bagCfg) ~= "table" then
                    bagCfg = {}
                    profileRec.addons.CludesUIBags = bagCfg
                end
                if bagCfg.bagHidePinnedInCategories == nil then
                    bagCfg.bagHidePinnedInCategories = false
                end
            end
        end
    end,
})

-- WoW Forever: fresh installs and future profiles open the bags to MultiBag and
-- start with Recent Items off; every already-existing profile keeps All Items and
-- Recent Items on unless its user had changed them. Registered on the Forever
-- client only, the one whose defaults changed.
if CludesUI.IS_FOREVER == true then
    CludesUI.RegisterMigration({
        id = "bags_forever_defaults_existing_v1",
        scope = "global",
        description = "Pin Bags' Default Selected Bag to All Items and Show Recent Items ON for existing WoW Forever profiles; fresh installs and future profiles inherit MultiBag and Recent Items off.",
        body = function(context)
            local saved = context.db
            if not saved or not saved.profiles then
                return
            end
            for _, profileRec in pairs(saved.profiles) do
                if
                    type(profileRec) == "table"
                    and type(profileRec.addons) == "table"
                    and next(profileRec.addons)
                then
                    local bagCfg = profileRec.addons.CludesUIBags
                    if type(bagCfg) ~= "table" then
                        bagCfg = {}
                        profileRec.addons.CludesUIBags = bagCfg
                    end
                    if bagCfg.bagShowRecentItems == nil then
                        bagCfg.bagShowRecentItems = true
                    end
                    if bagCfg.bagDefaultBagType == nil then
                        bagCfg.bagDefaultBagType = "all"
                    end
                end
            end
        end,
    })
end

-- Guardian Druid Ironfur bar ships ON (DEFAULTS.secondary.guardianIronfurBar=true)
-- for new installs; existing users expect no class resource bar, so pin every
-- already-existing profile OFF. Runs at parent ADDON_LOADED BEFORE any child NewDB
-- populates CludesUIDB.profiles, so only SavedVariables profiles (existing
-- users) are present; fresh installs have none and inherit ON (global scope runs once).
CludesUI.RegisterMigration({
    id = "resourcebars_guardian_ironfur_existing_off_v1",
    scope = "global",
    description = "Pin the Guardian Druid Ironfur bar OFF for existing users' profiles; fresh installs and future profiles inherit the new ON default.",
    body = function(context)
        local saved = context.db
        if not saved or not saved.profiles then
            return
        end
        for _, profileRec in pairs(saved.profiles) do
            -- Only profiles with real child-addon data: an empty/stub profile
            -- isn't an existing user's.
            if type(profileRec) == "table" and type(profileRec.addons) == "table" and next(profileRec.addons) then
                local resourceBars = profileRec.addons.CludesUIResourceBars
                if type(resourceBars) ~= "table" then
                    resourceBars = {}
                    profileRec.addons.CludesUIResourceBars = resourceBars
                end
                if type(resourceBars.secondary) ~= "table" then
                    resourceBars.secondary = {}
                end
                if resourceBars.secondary.guardianIronfurBar == nil then
                    resourceBars.secondary.guardianIronfurBar = false
                end
            end
        end
    end,
})

-- Prot Warrior Ignore Pain bar ships ON (DEFAULTS.secondary.protIgnorePainBar=true)
-- for new installs; existing users expect no class resource bar, so pin every
-- already-existing profile OFF. Same mechanism as the Guardian Ironfur migration above.
CludesUI.RegisterMigration({
    id = "resourcebars_protwar_ignorepain_existing_off_v1",
    scope = "global",
    description = "Pin the Prot Warrior Ignore Pain bar OFF for existing users' profiles; fresh installs and future profiles inherit the new ON default.",
    body = function(context)
        local saved = context.db
        if not saved or not saved.profiles then
            return
        end
        for _, profileRec in pairs(saved.profiles) do
            -- Only profiles with real child-addon data: an empty/stub profile
            -- isn't an existing user's.
            if type(profileRec) == "table" and type(profileRec.addons) == "table" and next(profileRec.addons) then
                local resourceBars = profileRec.addons.CludesUIResourceBars
                if type(resourceBars) ~= "table" then
                    resourceBars = {}
                    profileRec.addons.CludesUIResourceBars = resourceBars
                end
                if type(resourceBars.secondary) ~= "table" then
                    resourceBars.secondary = {}
                end
                if resourceBars.secondary.protIgnorePainBar == nil then
                    resourceBars.secondary.protIgnorePainBar = false
                end
            end
        end
    end,
})

-- Group Finder's Colored Group Names (search.nameColors) defaults off for fresh
-- installs and future profiles; every already-existing profile keeps it on unless
-- its user had turned it off. Same mechanism as the Guardian Ironfur migration.
CludesUI.RegisterMigration({
    id = "groupfinder_name_colors_existing_on_v1",
    scope = "global",
    description = "Pin Group Finder's Colored Group Names ON for existing users' profiles; fresh installs and future profiles inherit the new OFF default.",
    body = function(context)
        local saved = context.db
        if not saved or not saved.profiles then
            return
        end
        for _, profileRec in pairs(saved.profiles) do
            -- Only profiles with real child-addon data: an empty/stub profile
            -- isn't an existing user's.
            if type(profileRec) == "table" and type(profileRec.addons) == "table" and next(profileRec.addons) then
                local gf = profileRec.addons.CludesUIGroupFinder
                if type(gf) ~= "table" then
                    gf = {}
                    profileRec.addons.CludesUIGroupFinder = gf
                end
                if type(gf.search) ~= "table" then
                    gf.search = {}
                end
                if gf.search.nameColors == nil then
                    gf.search.nameColors = true
                end
            end
        end
    end,
})

-- Unit Frame cast bars count the spell icon as part of the bar's width by default
-- (*.castbarIconInWidth = true). Existing users expect the icon OUTSIDE the width
-- (to the LEFT), so pin every already-existing profile OFF, same mechanism as the
-- Guardian Ironfur migration. Nameplates have their own setting, NOT touched.
CludesUI.RegisterMigration({
    id = "uf_castbar_icon_in_width_existing_off_v1",
    scope = "global",
    description = "Pin cast-bar icon-in-width OFF for existing users' Unit Frames profiles; fresh installs and future profiles inherit the new ON default. Nameplates unaffected.",
    body = function(context)
        local saved = context.db
        if not saved or not saved.profiles then
            return
        end
        for _, profileRec in pairs(saved.profiles) do
            -- Only profiles with real child-addon data: an empty/stub profile
            -- isn't an existing user's.
            if type(profileRec) == "table" and type(profileRec.addons) == "table" and next(profileRec.addons) then
                local ufStore = profileRec.addons.CludesUIUnitFrames
                if type(ufStore) ~= "table" then
                    ufStore = {}
                    profileRec.addons.CludesUIUnitFrames = ufStore
                end
                if type(ufStore.player) ~= "table" then
                    ufStore.player = {}
                end
                if ufStore.player.playerCastbarIconInWidth == nil then
                    ufStore.player.playerCastbarIconInWidth = false
                end
                for _, unitName in ipairs({ "target", "focus", "boss" }) do
                    if type(ufStore[unitName]) ~= "table" then
                        ufStore[unitName] = {}
                    end
                    if ufStore[unitName].castbarIconInWidth == nil then
                        ufStore[unitName].castbarIconInWidth = false
                    end
                end
            end
        end
    end,
})

-- The borderless hover/target highlight draws its own outline at Border Size 0,
-- where the Hover/Target Border ticks were previously inert. Existing
-- borderless profiles overwhelmingly kept those ticks ON (they did nothing),
-- so without a pin the upgrade makes highlights appear unrequested. Pin BOTH
-- enables OFF for every existing profile whose border size is 0 --
-- UNCONDITIONALLY, not nil-guarded like the sibling migrations: an explicit
-- true stored while the setting was inert cannot represent informed intent
-- for the new behavior, and borderless veterans must see no change. The ticks
-- are the opt-in. Border'd profiles untouched (the highlight path is
-- unreachable there, so their recolor behavior is identical either way). A
-- profile with NO RaidFrames bucket never stored borderSize, defaults to 1,
-- and is skipped -- no bucket creation needed. Party frames share these keys
-- (no party_ border section exists); per-spec overrides are out of scope,
-- matching the sibling existing-off migrations.
CludesUI.RegisterMigration({
    id = "rf_borderless_highlight_existing_off_v1",
    scope = "global",
    description = "Pin Raid Frames Hover/Target Border OFF for existing profiles running Border Size 0, so the new borderless highlight stays opt-in for veterans; fresh installs and border'd profiles inherit the live defaults.",
    body = function(context)
        local saved = context.db
        if not saved or not saved.profiles then
            return
        end
        for _, profileRec in pairs(saved.profiles) do
            -- Only profiles with real child-addon data: an empty/stub profile
            -- isn't an existing user's.
            if type(profileRec) == "table" and type(profileRec.addons) == "table" and next(profileRec.addons) then
                local raidCfg = profileRec.addons.CludesUIRaidFrames
                if type(raidCfg) == "table" and (raidCfg.borderSize or 1) <= 0 then
                    raidCfg.hoverBorderEnabled = false
                    raidCfg.targetBorderEnabled = false
                end
            end
        end
    end,
})

-- The Nameplates dispel glow's Action Button Glow substitute gained real-ABG
-- anatomy (white ants, the color riding the soft halo, stock gold when no
-- color is set). A color stored under the OLD rendering was chosen to tint
-- bare ants; carrying it forward would tint the new halo instead -- a look
-- the user never picked. Clear it once for profiles running the ABG style so
-- they land on the stock gold; stored colors on every other style (and the
-- per-type color toggle) are untouched, and any color picked after this
-- migration is honored as usual.
CludesUI.RegisterMigration({
    id = "np_dispel_abg_color_gold_v1",
    scope = "global",
    description = "Reset stored Dispel Glow colors to the stock gold for profiles using the Action Button Glow style, since the color now tints the new halo rather than the old bare ants.",
    body = function(context)
        local saved = context.db
        if not saved or not saved.profiles then
            return
        end
        for _, profileRec in pairs(saved.profiles) do
            -- Only profiles with real child-addon data: an empty/stub profile
            -- isn't an existing user's.
            if type(profileRec) == "table" and type(profileRec.addons) == "table" and next(profileRec.addons) then
                local plateCfg = profileRec.addons.CludesUINameplates
                -- Style 2 = Action Button Glow; a missing key means the same
                -- via defaults. Cleared color = the engines' gold default.
                if
                    type(plateCfg) == "table"
                    and (plateCfg.dispelGlowStyle == nil or plateCfg.dispelGlowStyle == 2)
                    and plateCfg.dispelGlowColor ~= nil
                then
                    plateCfg.dispelGlowColor = nil
                end
            end
        end
    end,
})

-- Profile sync is now two-way mirror groups: a module's sync set is a membership group
-- (configuring profile is written into it) and only members push at logout/switch. Old
-- sets stored receivers only with no record of the sender, so they can't translate
-- reliably and any active profile pushed into them, silently overwriting an unrelated
-- profile. Reset every sync link (profile data untouched); users re-enable via the
-- sidebar sync icons, which write the new format. EXCEPTION: Bags keeps syncing, but
-- ONLY for profiles in the old Bags set -- they already received bags pushes every
-- logout, so mirroring exactly them adds zero new overwrite exposure, while profiles
-- outside it may hold deliberately divergent data. Registered LAST so it runs after the
-- older Bags data-move migration, landing multi-version jumps in the new shape.
CludesUI.RegisterMigration({
    id = "sync_reset_for_mirror_groups_v2",
    scope = "global",
    description = "Reset all profile sync links for the mirror-group rework (profile data untouched; sync is re-enabled via the module sync icons). The Bags group carries over its previous members only.",
    body = function(context)
        local saved = context.db
        if not saved then
            return
        end
        -- Capture old Bags membership before wiping; the legacy boolean format
        -- (pre per-profile sets) meant "all profiles".
        local oldBags = saved.syncedModules and saved.syncedModules.CludesUIBags
        local carried, total = {}, 0
        if saved.profiles then
            if oldBags == true then
                for profileName in pairs(saved.profiles) do
                    carried[profileName] = true
                    total = total + 1
                end
            elseif type(oldBags) == "table" then
                for profileName, val in pairs(oldBags) do
                    if val and saved.profiles[profileName] then
                        carried[profileName] = true
                        total = total + 1
                    end
                end
            end
        end
        saved.syncedModules = {}
        if total >= 2 then
            saved.syncedModules.CludesUIBags = carried
        end
    end,
})

-- Seeds every profile's customColors from the account-wide table so the opt-in
-- "Save Colors Per Profile" mode starts identical everywhere. Global
-- CludesUIDB.customColors stays the source of truth while the mode is off.
-- One-time overwrite: prior per-profile snapshots were inert, nothing is lost.
CludesUI.RegisterMigration({
    id = "global_colors_per_profile_seed_v1",
    scope = "global",
    description = "Seed every profile's customColors from the global table for the opt-in per-profile colours mode.",
    body = function(context)
        local saved = context.db
        if not saved or type(saved.customColors) ~= "table" or type(saved.profiles) ~= "table" then
            return
        end
        local DeepCopy = CludesUI._DeepCopy or (CludesUI.Lite and CludesUI.Lite.DeepCopy)
        if not DeepCopy then
            return
        end
        for _, profileSaved in pairs(saved.profiles) do
            if type(profileSaved) == "table" then
                profileSaved.customColors = DeepCopy(saved.customColors)
            end
        end
    end,
})

-- Secondary Stats + FPS counter moved from the account-wide CludesUIDB root
-- into the per-profile QoL blob (CludesUIQoL) so they travel with profiles,
-- export/import and module sync (see CludesUI.QoLExtrasGet/Set in
-- CludesUIQoL.lua). Seeds EVERY existing profile from the old
-- values, DeepCopy so each owns independent color/position tables. Root keys
-- stay as the read-time fallback + dormant backup; per-key nil guard = re-run safe.
CludesUI.RegisterMigration({
    id = "qol_secondary_stats_fps_per_profile_v1",
    scope = "global",
    description = "Seed every profile's QoL data with the formerly account-wide Secondary Stats + FPS settings.",
    body = function(context)
        local saved = context.db
        if not saved or type(saved.profiles) ~= "table" then
            return
        end
        local DeepCopy = CludesUI._DeepCopy or (CludesUI.Lite and CludesUI.Lite.DeepCopy)
        if not DeepCopy then
            return
        end
        local KEYS = {
            "showSecondaryStats",
            "secondaryStatsColor",
            "showTertiaryStats",
            "tertiaryStatsColor",
            "secondaryStatsPos",
            "showFPS",
            "fpsTextSize",
            "fpsColor",
            "fpsShowWorldMS",
            "fpsShowLocalMS",
            "fpsHideLabel",
            "fpsPos",
        }
        for _, profileSaved in pairs(saved.profiles) do
            if type(profileSaved) == "table" then
                if type(profileSaved.addons) ~= "table" then
                    profileSaved.addons = {}
                end
                local q = profileSaved.addons.CludesUIQoL
                if type(q) ~= "table" then
                    q = {}
                    profileSaved.addons.CludesUIQoL = q
                end
                for _, k in ipairs(KEYS) do
                    local val = saved[k]
                    if val ~= nil and q[k] == nil then
                        if type(val) == "table" then
                            q[k] = DeepCopy(val)
                        else
                            q[k] = val
                        end
                    end
                end
            end
        end
    end,
})

-- Tertiary visibility now lives entirely in the reorderable Stats to Show
-- checklist. Preserve the removed toggle's effective state for every profile:
-- checked enables all three tertiary rows; unchecked leaves all three hidden.
CludesUI.RegisterMigration({
    id = "qol_tertiary_stats_checklist_v1",
    scope = "profile",
    description = "Convert Show Tertiary Stats into the per-stat visibility checklist.",
    body = function(context)
        local profileRec = context.profile
        if type(profileRec.addons) ~= "table" then
            profileRec.addons = {}
        end
        local qolCfg = profileRec.addons.CludesUIQoL
        if type(qolCfg) ~= "table" then
            qolCfg = {}
            profileRec.addons.CludesUIQoL = qolCfg
        end

        local enabled = qolCfg.showTertiaryStats
        if enabled == nil then
            enabled = CludesUIDB and CludesUIDB.showTertiaryStats
        end
        if type(qolCfg.secondaryStatsHidden) ~= "table" then
            qolCfg.secondaryStatsHidden = {}
        end
        local hidden = enabled ~= true
        qolCfg.secondaryStatsHidden.leech = hidden
        qolCfg.secondaryStatsHidden.avoidance = hidden
        qolCfg.secondaryStatsHidden.speed = hidden
        qolCfg.showTertiaryStats = nil
    end,
})

-- "Disable Slug Outline" (neverShowSlug) and "Outline Icon Text" (outlineIconText)
-- moved from account-wide root into the per-profile fonts DB for export/import +
-- module sync. Seeds the live working fonts table (active profile) AND every
-- EXISTING profile fonts snapshot; profiles with NO snapshot are left untouched
-- (a partial one would reset global font/outline mode next switch; getter
-- fallback covers reads). Root keys stay as that fallback (getters in
-- CludesUI.lua) + dormant backup; nil guard = re-run safe.
CludesUI.RegisterMigration({
    id = "fonts_slug_iconoutline_per_profile_v1",
    scope = "global",
    description = "Seed every profile's fonts DB with the formerly account-wide Disable Slug Outline + Outline Icon Text settings.",
    body = function(context)
        local saved = context.db
        if not saved then
            return
        end
        local slug = saved.neverShowSlug
        local oit = saved.outlineIconText
        if slug == nil and type(oit) ~= "table" then
            return
        end
        local function seedValue(fontMap)
            if type(fontMap) ~= "table" then
                return
            end
            if fontMap.neverShowSlug == nil and slug ~= nil then
                fontMap.neverShowSlug = slug and true or false
            end
            if fontMap.outlineIconText == nil and type(oit) == "table" then
                local tbl = {}
                for k, val in pairs(oit) do
                    tbl[k] = val
                end
                fontMap.outlineIconText = tbl
            end
        end
        -- Live working copy = what a full export snapshots via DeepCopy(GetFontsDB()).
        seedValue(saved.fonts)
        -- Existing stored snapshots = so exporting a non-active profile carries it.
        if type(saved.profiles) == "table" then
            for _, profileSaved in pairs(saved.profiles) do
                if type(profileSaved) == "table" then
                    seedValue(profileSaved.fonts)
                end
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "blizzskin_reskin_master_split_v1",
    scope = "global",
    description = "Split the old 'Reskin Blizzard Elements' master (customTooltips) into independent Reskin Popups and Menus + per-window reskins, seeding each from the old master value once so what is reskinned stays exactly the same.",
    body = function(context)
        local saved = context.db
        if not saved then
            return
        end
        -- customTooltips is now tooltip-only, but at migration time still holds the
        -- OLD combined-master value, so seed the split-out keys from it once.
        local master = (saved.customTooltips ~= false)
        -- Old game-menu/group-finder defaults ANDed in queue-popup state (nil
        -- queue popup counted as on), matching the live default formula.
        local queueNotFalse = (saved.reskinQueuePopup ~= false)
        if saved.reskinPopupsMenus == nil then
            saved.reskinPopupsMenus = master
        end
        if saved.reskinQueuePopup == nil then
            saved.reskinQueuePopup = master
        end
        if saved.reskinGreatVault == nil then
            saved.reskinGreatVault = master
        end
        if saved.reskinGameMenu == nil then
            saved.reskinGameMenu = master and queueNotFalse
        end
        if saved.reskinLFGMenu == nil then
            saved.reskinLFGMenu = master and queueNotFalse
        end
    end,
})

CludesUI.RegisterMigration({
    id = "blizzskin_widget_bars_seed_v1",
    scope = "global",
    description = "Seed the new Reskin Widget Bars toggle from existing chrome preferences: on only when Reskin Tooltips AND Reskin Popups and Menus are both on, so accounts that turned those off do not get newly skinned HUD bars.",
    body = function(context)
        local saved = context.db
        if not saved then
            return
        end
        -- Registered AFTER the master-split migration on purpose: an account
        -- jumping many versions gets reskinPopupsMenus seeded first in the
        -- same pass, so this reads the settled value. Writes an explicit
        -- boolean both ways; the key is independent from here on (same
        -- contract as reskinPopupsMenus itself). Fresh installs never run
        -- this (genesis stamp) and keep nil = on, which matches both masters
        -- defaulting on.
        if saved.reskinWidgetBars == nil then
            saved.reskinWidgetBars = (saved.customTooltips ~= false) and (saved.reskinPopupsMenus ~= false)
        end
    end,
})

CludesUI.RegisterMigration({
    id = "texture_kringel_diamonds_to_blinkii_v1",
    scope = "profile",
    description = "Rename the saved 'kringel-diamonds' bar texture value to its replacement 'blinkii-diamonds' across Unit Frames, Raid Frames, Nameplates, Resource Bars, and Damage Meters.",
    body = function(context)
        -- Dropdown value is the texture KEY string, stored under different fields
        -- per module (healthBarTexture, general.barTexture, castBar.texture, etc).
        -- "kringel-diamonds" appears only as a texture value, so a recursive swap
        -- catches every location.
        local addonStores = context.profile.addons
        if type(addonStores) ~= "table" then
            return
        end

        local function swap(tbl, depth)
            if type(tbl) ~= "table" or depth > 8 then
                return
            end
            for k, val in pairs(tbl) do
                if val == "kringel-diamonds" then
                    tbl[k] = "blinkii-diamonds"
                elseif type(val) == "table" then
                    swap(val, depth + 1)
                end
            end
        end

        local MODULES = {
            "CludesUIUnitFrames",
            "CludesUIRaidFrames",
            "CludesUINameplates",
            "CludesUIResourceBars",
            "CludesUIDamageMeters",
        }
        for _, label in ipairs(MODULES) do
            swap(addonStores[label], 1)
        end
    end,
})

CludesUI.RegisterMigration({
    id = "purge_anchor_debug_log_v1",
    scope = "global",
    description = "Remove the temporary _anchorDebugLog table left in the central DB by the combat-reload anchor diagnostics.",
    body = function()
        if CludesUIDB then
            CludesUIDB._anchorDebugLog = nil
        end
    end,
})

CludesUI.RegisterMigration({
    id = "minimap_coords_mode_position_v1",
    scope = "profile",
    description = "Convert the minimap 'Show Coordinates Below Map' toggle into coordsMode/coordsPosition dropdown values, preserving each user's current coordinate behavior.",
    body = function(context)
        -- Only profiles that have used the Minimap module migrate; fresh installs
        -- take the new defaults (always/topLeft). The addons key survives the
        -- logout default-strip even when every setting is default, so an
        -- all-default existing user still lands on hover (old behavior). Runs
        -- AFTER v66_basics_split_data, so pre-split data already lives here.
        local emm = context.profile.addons and context.profile.addons.CludesUIMinimap
        if type(emm) ~= "table" then
            return
        end
        local minimapCfg = emm.minimap
        if type(minimapCfg) ~= "table" then
            minimapCfg = {}
            emm.minimap = minimapCfg
        end
        if minimapCfg.coordsMode ~= nil then
            return
        end -- already on the new keys
        if minimapCfg.coordsBelow then
            minimapCfg.coordsMode = "always"
            minimapCfg.coordsPosition = "belowMap"
        else
            minimapCfg.coordsMode = "hover"
            minimapCfg.coordsPosition = "topLeft"
            -- The X/Y nudge only applied in below-map mode; clear leftovers so
            -- they don't shift the newly position-aware hover coordinates.
            minimapCfg.coordsBelowOffsetX = nil
            minimapCfg.coordsBelowOffsetY = nil
        end
    end,
})

CludesUI.RegisterMigration({
    id = "minimap_clock_location_mode_v2",
    scope = "profile",
    description = "Convert the minimap Clock Inside / Zone Inside toggles into clockMode/locationMode dropdown values (none/inside/edge). Elements hidden via the removed Show Blizzard Elements Zone/Clock checkboxes become 'none'. Replaces the never-shipped _v1 (deleted).",
    body = function(context)
        -- Same gate as minimap_coords_mode_position_v1; fresh installs take the new
        -- defaults (inside/inside). Data is default-stripped, so absent keys mean
        -- old defaults: showClock ON, hideZoneText OFF, clockInside ON, zoneInside OFF.
        local emm = context.profile.addons and context.profile.addons.CludesUIMinimap
        if type(emm) ~= "table" then
            return
        end
        local minimapCfg = emm.minimap
        if type(minimapCfg) ~= "table" then
            minimapCfg = {}
            emm.minimap = minimapCfg
        end
        -- Hidden via the removed Show Blizzard Elements checkboxes wins over any
        -- already-stamped mode.
        if minimapCfg.showClock == false then
            minimapCfg.clockMode = "none"
        elseif minimapCfg.clockMode == nil then
            minimapCfg.clockMode = (minimapCfg.clockInside == false) and "edge" or "inside"
        end
        if minimapCfg.hideZoneText == true then
            minimapCfg.locationMode = "none"
        elseif minimapCfg.locationMode == nil then
            minimapCfg.locationMode = minimapCfg.zoneInside and "inside" or "edge"
        end
    end,
})

CludesUI.RegisterMigration({
    id = "minimap_omnium_folio_mode_v1",
    scope = "profile",
    description = "Convert the minimap Show Omnium Folio toggle into the omniumFolioMode dropdown (never/hover/always), preserving each user's current visibility.",
    body = function(context)
        -- Same gate as the other minimap mode migrations; fresh installs take the
        -- new default (always). Data is default-stripped, so only an explicit
        -- showOmniumFolio == false is ever present (default was ON).
        local emm = context.profile.addons and context.profile.addons.CludesUIMinimap
        if type(emm) ~= "table" then
            return
        end
        local minimapCfg = emm.minimap
        if type(minimapCfg) ~= "table" then
            minimapCfg = {}
            emm.minimap = minimapCfg
        end
        if minimapCfg.omniumFolioMode == nil then
            minimapCfg.omniumFolioMode = (minimapCfg.showOmniumFolio == false) and "never" or "always"
        end
    end,
})

-------------------------------------------------------------------------------
--  CDM per-spell settings: tiered-store shape transform
--
--  OLD: barSpells[barKey].spellSettings[sid], bar-scoped -- a spell moved to
--  another bar lost its settings and left an orphan; plus
--  barSpells[barKey]._syncIconSettings (Sync All Bar Buttons stamped one spell's
--  block onto every other spell on the bar).
--
--  NEW: specProf.spellSettingsCD[sid]/.spellSettingsBuff[sid] are per-spell,
--  family-scoped, travel with the spell across bars; barSpells[barKey].barSettings
--  is the per-spec "Apply to Bar" tier (seeded from synced bars); bd.barSpellSettings
--  (profile-level, NOT written here) is "Apply to Bar (All Specs)" and starts empty.
--
--  Faithfulness (nothing changes visually): entries move only when the spell is
--  CURRENTLY assigned to the bar the entry lives on, or not visibly assigned
--  anywhere (hidden spells keep styling for their return); orphans for spells now
--  owned by a DIFFERENT bar are dropped (that spell renders default today, so
--  adopting the orphan would change it); synced bars promote their uniform block
--  to barSettings and drop matching per-spell copies, while a divergent copy is
--  kept as an override with explicit `false` fillers for any seed key it lacks
--  (false is render-equivalent to nil) so the bar tier can't bleed through.
--
--  Shared with profile import so old-format strings transform immediately; the
--  registered migration also covers them next reload (both idempotent).
-------------------------------------------------------------------------------
local function CdmFlatSettingsEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    for k, val in pairs(a) do
        if b[k] ~= val then
            return false
        end
    end
    for k, val in pairs(b) do
        if a[k] ~= val then
            return false
        end
    end
    return true
end

-- Classifies a barSpells bucket key into its settings-family store key.
-- Mirrors the runtime rule (ns.SettingsFamilyKey): only barType "buffs" (and the
-- default "buffs" bar) are buff-family; custom_buff and the ghost bar are not.
-- Stale buckets for deleted bars fall back to a key heuristic -- a miss is inert
-- (entries are orphan candidates at most).
local function CdmBarFamilyKey(barId, barsCfg)
    if barId == "buffs" then
        return "spellSettingsBuff"
    end
    if barId == "__ghost_cd" then
        return "spellSettingsCD"
    end
    if type(barsCfg) == "table" then
        for _, b in ipairs(barsCfg) do
            if type(b) == "table" and b.key == barId then
                return (b.barType == "buffs") and "spellSettingsBuff" or "spellSettingsCD"
            end
        end
    end
    if type(barId) == "string" and barId:find("buff", 1, true) then
        return "spellSettingsBuff"
    end
    return "spellSettingsCD"
end

function CludesUI.MigrateCdmSpellSettingsShape(specProfile, barsCfg)
    if type(specProfile) ~= "table" then
        return
    end
    local barSpellMap = specProfile.barSpells
    if type(barSpellMap) ~= "table" then
        return
    end

    -- Pass 0: visible assignment map per family. Ghost-bar assignments do NOT
    -- count as visible, so a hidden spell's orphaned entry still migrates and
    -- un-hiding restores its styling on any bar.
    local visibleAssign = { spellSettingsCD = {}, spellSettingsBuff = {} }
    for barId, barConf in pairs(barSpellMap) do
        if barId ~= "__ghost_cd" and type(barConf) == "table" and type(barConf.assignedSpells) == "table" then
            local famKey = CdmBarFamilyKey(barId, barsCfg)
            for _, spellRef in ipairs(barConf.assignedSpells) do
                if type(spellRef) == "number" and spellRef ~= 0 then
                    visibleAssign[famKey][spellRef] = barId
                end
            end
        end
    end

    -- Pass 1: relocate entries whose spell is assigned to the bar the entry
    -- lives on. Pass 2: adopt entries for spells not visibly assigned anywhere.
    for pass = 1, 2 do
        for barId, barConf in pairs(barSpellMap) do
            local old = type(barConf) == "table" and barConf.spellSettings
            if type(old) == "table" then
                local famKey = CdmBarFamilyKey(barId, barsCfg)
                local assign = visibleAssign[famKey]
                for spellRef, record in pairs(old) do
                    if type(record) ~= "table" or next(record) == nil then
                        old[spellRef] = nil
                    else
                        local takeIt
                        if pass == 1 then
                            takeIt = (assign[spellRef] == barId)
                        else
                            takeIt = (assign[spellRef] == nil)
                        end
                        if takeIt then
                            local storage = specProfile[famKey]
                            if not storage then
                                storage = {}
                                specProfile[famKey] = storage
                            end
                            if storage[spellRef] == nil then
                                storage[spellRef] = record
                            end
                            old[spellRef] = nil
                        end
                    end
                end
            end
        end
    end

    -- Pass 3: promote synced bars to the bar tier, then clear the flag and
    -- drop whatever old-shape residue remains (stale different-bar orphans).
    for barId, barConf in pairs(barSpellMap) do
        if type(barConf) == "table" then
            if
                barConf._syncIconSettings == true
                and type(barConf.assignedSpells) == "table"
                and type(barConf.barSettings) ~= "table"
            then
                local famKey = CdmBarFamilyKey(barId, barsCfg)
                local storage = specProfile[famKey]
                local seedValue
                if storage then
                    for _, spellRef in ipairs(barConf.assignedSpells) do
                        local e = storage[spellRef]
                        if type(e) == "table" and next(e) ~= nil then
                            seedValue = e
                            break
                        end
                    end
                end
                if seedValue then
                    local duplicate = {}
                    for k, val in pairs(seedValue) do
                        duplicate[k] = val
                    end
                    barConf.barSettings = duplicate
                    for _, spellRef in ipairs(barConf.assignedSpells) do
                        local e = storage[spellRef]
                        if type(e) == "table" then
                            if CdmFlatSettingsEqual(e, duplicate) then
                                storage[spellRef] = nil
                            else
                                -- Divergent override: block seed keys it lacks
                                -- so the new bar tier can't bleed through.
                                for k in pairs(duplicate) do
                                    if e[k] == nil then
                                        e[k] = false
                                    end
                                end
                            end
                        end
                    end
                end
            end
            barConf._syncIconSettings = nil
            if type(barConf.spellSettings) == "table" then
                barConf.spellSettings = nil
            end
        end
    end
end

CludesUI.RegisterMigration({
    id = "cdm_spell_settings_tiers_v1",
    scope = "specProfile",
    description = "Move CDM per-spell icon settings from per-bar spellSettings into per-spec family stores (settings now travel with the spell across bars), and promote Sync All Bar Buttons bars into bar-level Apply-to-Bar settings.",
    body = function(context)
        local profileTbl = CludesUIDB.profiles and CludesUIDB.profiles[context.profileName]
        local cdmStore = profileTbl and profileTbl.addons and profileTbl.addons.CludesUICooldownManager
        local barsCfg = cdmStore and cdmStore.cdmBars and cdmStore.cdmBars.bars
        CludesUI.MigrateCdmSpellSettingsShape(context.specProfile, barsCfg)
    end,
})

-- Relocates HOSTED-buff per-spell settings from the CD family store to the BUFF family
-- store. Hosted buffs (a buff on a CD/utility bar) used to resolve settings through the
-- host bar's family key (CD); they now resolve the frame-keyed BUFF store, so the same
-- spellID's cooldown icon holds independent settings -- without the move, hosted-buff
-- settings silently stop applying. Idempotent: moves only while a CD-store entry exists
-- for a flagged id, never overwriting keys already in the BUFF entry (a cooldown twin
-- under the same id moves too: unsplittable in the old shared-entry shape).
-- assignedSpells conversion (plain id -> hosted marker) is NOT done here: it needs live
-- viewer/catalog data to tell buff and cooldown forms apart, so the options panel
-- normalizes it lazily (EnsureAssignedSpells).
function CludesUI.MigrateCdmHostedBuffSettings(specProfile)
    if type(specProfile) ~= "table" or type(specProfile.barSpells) ~= "table" then
        return
    end
    local stCD = specProfile.spellSettingsCD
    if type(stCD) ~= "table" then
        return
    end
    for _, sd in pairs(specProfile.barSpells) do
        local hosted = type(sd) == "table" and sd.hostedBuffSpellIDs
        if type(hosted) == "table" then
            for hostedSpellId in pairs(hosted) do
                local e = stCD[hostedSpellId]
                if type(e) == "table" then
                    local stBuff = specProfile.spellSettingsBuff
                    if type(stBuff) ~= "table" then
                        stBuff = {}
                        specProfile.spellSettingsBuff = stBuff
                    end
                    local tgt = stBuff[hostedSpellId]
                    if type(tgt) ~= "table" then
                        stBuff[hostedSpellId] = e
                    else
                        for k, val in pairs(e) do
                            if tgt[k] == nil then
                                tgt[k] = val
                            end
                        end
                    end
                    stCD[hostedSpellId] = nil
                end
            end
        end
    end
end

CludesUI.RegisterMigration({
    id = "cdm_hosted_buff_settings_v1",
    scope = "specProfile",
    description = "Move hosted-buff per-spell icon settings from the CD family store to the BUFF family store (hosted buffs now share the buff-family settings entry with the buffs bar, independent of the same spell's cooldown icon).",
    body = function(context)
        CludesUI.MigrateCdmHostedBuffSettings(context.specProfile)
    end,
})

-- Converts the per-bar "Custom Active State Decimals" (bd.faDecimals*) into the
-- per-spell Threshold Text settings that replaced it: old toggle drove a
-- 1-decimal countdown (+ optional color) on custom/preset icons' hardcoded
-- timers; new model stores Threshold Seconds/Decimals/Color per spell. Every
-- custom spell/item on an opted-in bar is stamped to render as before:
--  * cd/utility bars: item presets and custom/racial spells stamp the
--    profile-level customActiveStates entry (menu + Fake-Active engine read it).
--    Trinket SLOT presets key off the EQUIPPED item at runtime, stamped only
--    when the inventory API already answers (best effort).
--  * buff-family bars: custom buffs (cast-timer entries / tagged custom ids)
--    stamp the spec BUFF family store; Blizzard-tracked buffs are not stamped
--    (never covered by the old toggle).
-- Old bd.faDecimals* keys are consumed in the same pass. Shared with profile
-- import so old-format strings transform immediately.
function CludesUI.MigrateCdmThresholdText(cdmStore, specProfiles)
    local barsCfg = cdmStore and cdmStore.cdmBars and cdmStore.cdmBars.bars
    if type(barsCfg) ~= "table" then
        return
    end
    for _, edge in ipairs(barsCfg) do
        if type(edge) == "table" then
            local thr = tonumber(edge.faDecimalsThreshold) or 5
            if thr > 59 then
                thr = 59
            end
            if edge.faDecimals == true and thr > 0 and edge.key then
                local colorOn = edge.faDecimalsColorEnabled == true
                local cr = edge.faDecimalsColorR or 1
                local cg = edge.faDecimalsColorG or 0.2
                local callback = edge.faDecimalsColorB or 0.2
                local isBuffFam = (edge.barType == "buffs") or (edge.key == "buffs")
                local function Stamp(e)
                    if type(e) ~= "table" then
                        return
                    end
                    e.thresholdSeconds = thr
                    e.thresholdDecimals = true
                    if colorOn then
                        e.thresholdColorEnabled = true
                        e.thresholdColorR = cr
                        e.thresholdColorG = cg
                        e.thresholdColorB = callback
                    end
                end
                local function StampCas(fieldKey)
                    if type(cdmStore.customActiveStates) ~= "table" then
                        cdmStore.customActiveStates = {}
                    end
                    local e = cdmStore.customActiveStates[fieldKey]
                    if type(e) ~= "table" then
                        e = {}
                        cdmStore.customActiveStates[fieldKey] = e
                    end
                    Stamp(e)
                end
                if type(specProfiles) == "table" then
                    for _, specProfile in pairs(specProfiles) do
                        local barConf = type(specProfile) == "table"
                            and type(specProfile.barSpells) == "table"
                            and specProfile.barSpells[edge.key]
                        local assigned = type(barConf) == "table" and barConf.assignedSpells
                        if type(assigned) == "table" then
                            for _, spellRef in ipairs(assigned) do
                                if type(spellRef) == "number" then
                                    if isBuffFam then
                                        -- Custom buffs: cast-timer entries (stored
                                        -- duration) and tagged custom ids.
                                        if
                                            spellRef > 0
                                            and (
                                                (
                                                    type(barConf.spellDurations) == "table"
                                                    and (tonumber(barConf.spellDurations[spellRef]) or 0) > 0
                                                )
                                                or (
                                                    type(barConf.customSpellIDs) == "table"
                                                    and barConf.customSpellIDs[spellRef]
                                                )
                                            )
                                        then
                                            local settingsTbl = specProfile.spellSettingsBuff
                                            if type(settingsTbl) ~= "table" then
                                                settingsTbl = {}
                                                specProfile.spellSettingsBuff = settingsTbl
                                            end
                                            local e = settingsTbl[spellRef]
                                            if type(e) ~= "table" then
                                                e = {}
                                                settingsTbl[spellRef] = e
                                            end
                                            Stamp(e)
                                        end
                                    elseif spellRef <= -2000000000 then
                                        -- Hosted-buff marker: a real Blizzard buff,
                                        -- never covered by the old toggle.
                                    elseif spellRef == -13 or spellRef == -14 then
                                        local success, itemId = pcall(GetInventoryItemID, "player", -spellRef)
                                        if success and itemId then
                                            StampCas(-itemId)
                                        end
                                    elseif spellRef < 0 then
                                        StampCas(spellRef)
                                    elseif
                                        (type(barConf.customSpellIDs) == "table" and barConf.customSpellIDs[spellRef])
                                        or (
                                            type(cdmStore.customActiveStates) == "table"
                                            and type(cdmStore.customActiveStates[spellRef]) == "table"
                                            and (tonumber(cdmStore.customActiveStates[spellRef].duration) or 0)
                                                > 0
                                        )
                                    then
                                        -- Tagged custom ids, plus racials/injected
                                        -- spells already carrying a user-defined
                                        -- active state.
                                        StampCas(spellRef)
                                    end
                                end
                            end
                        end
                    end
                end
            end
            edge.faDecimals = nil
            edge.faDecimalsThreshold = nil
            edge.faDecimalsColorEnabled = nil
            edge.faDecimalsColorR = nil
            edge.faDecimalsColorG = nil
            edge.faDecimalsColorB = nil
        end
    end
end

CludesUI.RegisterMigration({
    id = "cdm_threshold_text_v1",
    scope = "global",
    description = "Replace the per-bar Custom Active State Decimals with per-spell Threshold Text: opted-in bars' custom spell/item members get per-spell Threshold Seconds/Decimals (+ Color) stamps, and the old bar keys are removed.",
    body = function(context)
        local saved = context.db
        if not saved or type(saved.profiles) ~= "table" then
            return
        end
        local saProfiles = saved.spellAssignments and saved.spellAssignments.profiles
        for profileName, profileRec in pairs(saved.profiles) do
            local cdmStore = type(profileRec) == "table"
                and type(profileRec.addons) == "table"
                and profileRec.addons.CludesUICooldownManager
            if type(cdmStore) == "table" then
                local specBucket = type(saProfiles) == "table" and saProfiles[profileName]
                local specList = type(specBucket) == "table" and specBucket.specProfiles or nil
                CludesUI.MigrateCdmThresholdText(cdmStore, specList)
            end
        end
    end,
})

-- ReconcileBuffDisplayOrder auto-resyncs the default buffs bar's displayed order
-- (sd.buffDisplayOrder) to Blizzard's current viewer order unless
-- sd._buffDisplayOrderUserModified is set (only options drag-reorder writes that
-- flag). Before the flag existed, buffDisplayOrder was created solely by a
-- manual drag, so every pre-existing stable-key array IS hand-arranged: stamp
-- the flag so the first live reconcile preserves it instead of Blizzard-sorting.
-- Numeric-format legacy arrays are skipped -- reconcile discards that format
-- outright, so there's no order to preserve. Shared with profile import so
-- orders exported from older builds stay protected.
function CludesUI.MigrateCdmBuffOrderUserFlag(specProfile)
    local barConf = type(specProfile) == "table" and type(specProfile.barSpells) == "table" and specProfile.barSpells.buffs
    if type(barConf) ~= "table" then
        return
    end
    if type(barConf.buffDisplayOrder) == "table" and type(barConf.buffDisplayOrder[1]) == "string" then
        barConf._buffDisplayOrderUserModified = true
    end
end

CludesUI.RegisterMigration({
    id = "cdm_buff_order_user_flag_v1",
    scope = "specProfile",
    description = "Protect pre-existing manually-arranged Tracked Buffs orders from the live-path Blizzard-order resync by stamping _buffDisplayOrderUserModified on every stable-key buffDisplayOrder.",
    body = function(context)
        CludesUI.MigrateCdmBuffOrderUserFlag(context.specProfile)
    end,
})

-- M+ Timer Enemy Forces bar shared barTexture/barBgTexture with the main timer
-- bar; it now has its own enemyBarTexture/enemyBarBgTexture. Seeds the new keys
-- from the old shared ones on every existing profile so Forces looks unchanged;
-- fresh installs inherit the "none" default. Runs once, only seeds when the new
-- key is unset, so a later reset is respected.
CludesUI.RegisterMigration({
    id = "mythictimer_split_forces_bar_texture_v1",
    scope = "global",
    description = "Give the M+ Timer Forces bar its own texture keys, seeded from the shared bar texture so existing users' Forces bar is unchanged.",
    body = function(context)
        local saved = context.db
        if not saved or not saved.profiles then
            return
        end
        for _, profileRec in pairs(saved.profiles) do
            if type(profileRec) == "table" and type(profileRec.addons) == "table" then
                local timerCfg = profileRec.addons.CludesUIMythicTimer
                if type(timerCfg) == "table" then
                    if timerCfg.enemyBarTexture == nil and timerCfg.barTexture ~= nil then
                        timerCfg.enemyBarTexture = timerCfg.barTexture
                    end
                    if timerCfg.enemyBarBgTexture == nil and timerCfg.barBgTexture ~= nil then
                        timerCfg.enemyBarBgTexture = timerCfg.barBgTexture
                    end
                end
            end
        end
    end,
})

CludesUI.RegisterMigration({
    id = "uf_clear_stale_attached_power_border_v1",
    scope = "profile",
    description = "Zero stale powerBorderSize on attached power bars so the new attached divider does not appear uninvited for users who set a border size while detached and later reattached.",
    body = function(context)
        -- Border Size slider was disabled while attached, so a stored size > 0 with
        -- an attached position is always a leftover from a detached phase, never a
        -- divider the user asked for; clear to default (0=off). Positions other
        -- than above/below are untouched (detached keeps its full border; "none"
        -- renders nothing either way).
        local ufStore = context.profile.addons and context.profile.addons.CludesUIUnitFrames
        if type(ufStore) ~= "table" then
            return
        end
        -- Units whose powerPosition DEFAULT is attached ("below"): a missing key
        -- still means attached. Mini frames default to "none" (missing = no border).
        local attachedDefault = { player = true, target = true, focus = true, boss = true }
        for unitName, s in pairs(ufStore) do
            if type(s) == "table" and type(s.powerBorderSize) == "number" and s.powerBorderSize > 0 then
                local place = s.powerPosition
                if place == nil and attachedDefault[unitName] then
                    place = "below"
                end
                if place == "above" or place == "below" then
                    s.powerBorderSize = nil
                end
            end
        end
    end,
})

-- Shared body: converts collided-buff cooldownID claims (bs.assignedBuffCdIDs, an
-- unordered side-table) into cd-claim markers inside assignedSpells. Idempotent:
-- assignedBuffCdIDs cleared after migrating. Also called at profile-import time
-- so old export strings keep their claims. Mirrors ns.CD_CLAIM_MARKER_BASE /
-- ns.CdClaimMarker in the CDM addon (-(3000000000 + cooldownID)); inlined rather
-- than called because CDM loads AFTER the login migration runs.
function CludesUI.MigrateCdmBuffCdClaims(specProfile)
    local CD_CLAIM_MARKER_BASE = 3000000000
    local barSpellMap = type(specProfile) == "table" and specProfile.barSpells
    if type(barSpellMap) ~= "table" then
        return
    end
    for _, barConf in pairs(barSpellMap) do
        if type(barConf) == "table" and type(barConf.assignedBuffCdIDs) == "table" and next(barConf.assignedBuffCdIDs) then
            if not barConf.assignedSpells then
                barConf.assignedSpells = {}
            end
            -- Dedup against any marker already present (e.g. an interrupted run).
            local present = {}
            for _, ident in ipairs(barConf.assignedSpells) do
                if type(ident) == "number" and ident <= -CD_CLAIM_MARKER_BASE then
                    present[-ident - CD_CLAIM_MARKER_BASE] = true
                end
            end
            for cdID in pairs(barConf.assignedBuffCdIDs) do
                if type(cdID) == "number" and not present[cdID] then
                    barConf.assignedSpells[#barConf.assignedSpells + 1] = -(CD_CLAIM_MARKER_BASE + cdID)
                end
            end
            barConf.assignedBuffCdIDs = nil
        end
    end
end

CludesUI.RegisterMigration({
    id = "cdm_buff_cd_claim_markers",
    scope = "specProfile",
    description = "Convert collided-buff cooldownID claims (bs.assignedBuffCdIDs, a side-table with no order) into cd-claim markers stored inside assignedSpells, so a claimed slot gets a real position and can be drag-reordered like any other tracked buff.",
    body = function(context)
        CludesUI.MigrateCdmBuffCdClaims(context.specProfile)
    end,
})

CludesUI.RegisterMigration({
    id = "qol_movement_alert_precision_normalize_v2",
    scope = "profile",
    description = 'Normalize Movement Alert precision to a clean 0 or 1. A legacy numeric-input control could leave a non-binary value -- the string "1", or a stored -0 -- that the Show Decimal toggle mishandled and that built an invalid "%.-0f" format string. Normalized unconditionally (no type guard) because -0 is a number, so the earlier number-only guard skipped it. Positive -> 1 (decimals on); zero/negative/garbage -> 0 (off).',
    body = function(context)
        local qolCfg = context.profile.addons and context.profile.addons.CludesUIQoL
        local ma = qolCfg and qolCfg.movementAlert
        if type(ma) ~= "table" or ma.precision == nil then
            return
        end
        ma.precision = (tonumber(ma.precision) or 1) > 0 and 1 or 0
    end,
})

local migrationFrame = CreateFrame("Frame")
migrationFrame:RegisterEvent("ADDON_LOADED")
migrationFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "CludesUI" then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")

    ---------------------------------------------------------------------------
    --  Boot sequence (runs at parent ADDON_LOADED, before child addons init).
    --  RunRegisteredMigrations walks every registered migration, iterating the
    --  right scope (global/profile/specProfile), pcall-wrapping each body and
    --  stamping per-scope flags on success.
    ---------------------------------------------------------------------------
    CludesUI.RunRegisteredMigrations()

    -- DM fontSize split into leftFontSize + rightFontSize. DeepMergeDefaults fills
    -- the new keys with 11 before the runtime fallback (c.leftFontSize or
    -- c.fontSize or 11) can reach the old value, losing a changed fontSize: copy
    -- it forward before the defaults merge overwrites it.
    if CludesUIDB and CludesUIDB.profiles then
        for _, profileRec in pairs(CludesUIDB.profiles) do
            local meterCfg = profileRec.addons
                and profileRec.addons.CludesUIDamageMeters
                and profileRec.addons.CludesUIDamageMeters.dm
            if meterCfg and meterCfg.fontSize and meterCfg.fontSize ~= 11 then
                if meterCfg.leftFontSize == nil then
                    meterCfg.leftFontSize = meterCfg.fontSize
                end
                if meterCfg.rightFontSize == nil then
                    meterCfg.rightFontSize = meterCfg.fontSize
                end
            end
        end
    end

    -- Unconditional ghost buff purge: catches imported profiles that
    -- bypass migration flags. Cheap scan, runs once at login.
    if CludesUIDB and CludesUIDB.profiles then
        for _, profileRec in pairs(CludesUIDB.profiles) do
            local barList = profileRec.addons
                and profileRec.addons.CludesUICooldownManager
                and profileRec.addons.CludesUICooldownManager.cdmBars
                and profileRec.addons.CludesUICooldownManager.cdmBars.bars
            if barList then
                for index = #barList, 1, -1 do
                    if barList[index].key == "__ghost_buffs" then
                        table.remove(barList, index)
                    end
                end
            end
        end
        for _, specRec in ipairs(CollectSpecProfiles(CludesUIDB.spellAssignments)) do
            if specRec.barSpells then
                specRec.barSpells["__ghost_buffs"] = nil
            end
        end
    end
end)

--------------------------------------------------------------------------------
--  RESOURCE BARS: Simple/Advanced -> Spec Overrides migration
--
--  Retires the RB Advanced per-spec mode (advancedSpecs copy-on-unsync sections)
--  and per-spec bar enables (health/primary/secondary .disabledSpecs), turning
--  them into Spec Overrides groups + entries: one card per advanced spec (spec
--  name, class icon) holding one entry per section whose copy DIFFERS from
--  Simple (only differing leaf keys become overrides), plus one card per
--  per-spec enable ("Class Resource"/"Power Bar"/"Health Bar") for specs
--  disabled via the Simple disabledSpecs picker. Threshold data (thresholdSpecs/
--  tickValues/thresholdFormMode) is NEVER diffed into overrides: differing
--  threshold entries are retargeted to the spec and merged into the Simple list
--  instead (natively per-spec via entry.specIDs), preserving resolution
--  behavior. Raw advanced data survives in rb.advancedSpecsBackup for cleanup.
--
--  CRITICAL BASIS: stored profile tables are SPARSE (Lite defaults merge at
--  NewDB time, not persisted) while unsync copies are FAT snapshots of the
--  merged runtime table, so ALL comparisons run over DEFAULTS-MERGED effective
--  values -- raw-table diffs would mis-classify real edits as drift and strip
--  runtime-injected defaults. That needs the RB DEFAULTS table, so this runs
--  from Resource Bars' OnInitialize (exports CludesUI._RBSectionDefaults,
--  then walks every stored profile) AND directly on imported profile data, both
--  self-guarded by a flag on the RB profile table (idempotent). With no
--  defaults available (RB disabled) it's a no-op WITHOUT stamping the flag, so
--  it runs when RB loads.
--------------------------------------------------------------------------------
do
    local PS, FS = "\30", "\31"
    local NIL_SENT = "__SPECOV_NIL__"
    local RB_FOLDER = "CludesUIResourceBars"
    local RB_PAGE = "Class, Power and Health Bars"

    -- Static spec map: migration bodies must not call live game APIs.
    local SPEC_INFO = {
        [62] = { "Arcane", "MAGE" },
        [63] = { "Fire", "MAGE" },
        [64] = { "Frost", "MAGE" },
        [65] = { "Holy", "PALADIN" },
        [66] = { "Protection", "PALADIN" },
        [70] = { "Retribution", "PALADIN" },
        [71] = { "Arms", "WARRIOR" },
        [72] = { "Fury", "WARRIOR" },
        [73] = { "Protection", "WARRIOR" },
        [102] = { "Balance", "DRUID" },
        [103] = { "Feral", "DRUID" },
        [104] = { "Guardian", "DRUID" },
        [105] = { "Restoration", "DRUID" },
        [250] = { "Blood", "DEATHKNIGHT" },
        [251] = { "Frost", "DEATHKNIGHT" },
        [252] = { "Unholy", "DEATHKNIGHT" },
        [253] = { "Beast Mastery", "HUNTER" },
        [254] = { "Marksmanship", "HUNTER" },
        [255] = { "Survival", "HUNTER" },
        [256] = { "Discipline", "PRIEST" },
        [257] = { "Holy", "PRIEST" },
        [258] = { "Shadow", "PRIEST" },
        [259] = { "Assassination", "ROGUE" },
        [260] = { "Outlaw", "ROGUE" },
        [261] = { "Subtlety", "ROGUE" },
        [262] = { "Elemental", "SHAMAN" },
        [263] = { "Enhancement", "SHAMAN" },
        [264] = { "Restoration", "SHAMAN" },
        [265] = { "Affliction", "WARLOCK" },
        [266] = { "Demonology", "WARLOCK" },
        [267] = { "Destruction", "WARLOCK" },
        [268] = { "Brewmaster", "MONK" },
        [269] = { "Windwalker", "MONK" },
        [270] = { "Mistweaver", "MONK" },
        [577] = { "Havoc", "DEMONHUNTER" },
        [581] = { "Vengeance", "DEMONHUNTER" },
        [1480] = { "Devourer", "DEMONHUNTER" },
        [1467] = { "Devastation", "EVOKER" },
        [1468] = { "Preservation", "EVOKER" },
        [1473] = { "Augmentation", "EVOKER" },
    }
    local CLASS_TITLE = {
        WARRIOR = "Warrior",
        PALADIN = "Paladin",
        HUNTER = "Hunter",
        ROGUE = "Rogue",
        PRIEST = "Priest",
        DEATHKNIGHT = "Death Knight",
        SHAMAN = "Shaman",
        MAGE = "Mage",
        WARLOCK = "Warlock",
        MONK = "Monk",
        DRUID = "Druid",
        DEMONHUNTER = "Demon Hunter",
        EVOKER = "Evoker",
    }

    local RB_SECTIONS = {
        { key = "secondary", label = "Class Resource", enableLabel = "Show Class Resource" },
        { key = "primary", label = "Power Bar", enableLabel = "Show Power Bar" },
        -- health is OPT-IN at runtime (`hp.enabled and ...`; nil = hidden),
        -- unlike power/secondary (`enabled ~= false`; nil = shown).
        { key = "health", label = "Health Bar", enableLabel = "Show Health Bar", optIn = true },
    }

    -- Effective "is this section's bar shown" for a config table, matching
    -- each section's runtime truthiness over the DEFAULTS-MERGED value, with
    -- the per-spec disabledSpecs filter folded in when a spec is given.
    local function SectionEff(section, tbl, defaults, specId)
        local en = tbl.enabled
        if en == nil then
            en = defaults and defaults.enabled
        end
        local effective
        if section.optIn then
            effective = en and true or false
        else
            effective = en ~= false
        end
        if effective and specId and type(tbl.disabledSpecs) == "table" and tbl.disabledSpecs[specId] then
            effective = false
        end
        return effective
    end

    -- Threshold-system keys are never diffed into overrides; disabledSpecs
    -- and enabled are folded into effective enables (SectionEff) instead.
    local RB_SKIP_KEYS = {
        thresholdSpecs = true,
        tickValues = true,
        thresholdFormMode = true,
        disabledSpecs = true,
        enabled = true,
    }

    local DeepCopyT = CludesUI.Lite.DeepCopy

    local function DeepEq(a, b)
        if a == b then
            return true
        end
        if type(a) ~= "table" or type(b) ~= "table" then
            return false
        end
        for k, val in pairs(a) do
            if not DeepEq(val, b[k]) then
                return false
            end
        end
        for k in pairs(b) do
            if a[k] == nil then
                return false
            end
        end
        return true
    end

    -- Walk a section table by a PS-joined relative path, falling back to the
    -- defaults subtree wherever the table side runs out (effective value).
    local function GetPathEff(tbl, defaults, filePath)
        for seg in string.gmatch(filePath, "[^\30]+") do
            local tv = (type(tbl) == "table") and tbl[seg] or nil
            local dv = (type(defaults) == "table") and defaults[seg] or nil
            tbl, defaults = tv, dv
            if tbl == nil and defaults == nil then
                return nil
            end
        end
        if tbl ~= nil then
            return tbl
        end
        return defaults
    end

    -- Union of differing leaf paths between a Simple section and an advanced copy,
    -- compared over DEFAULTS-MERGED effective values on both sides (stored Simple
    -- is sparse, copies are fat merged snapshots; raw comparison would mis-read
    -- defaults as edits). Skips threshold/disabledSpecs/enabled/numeric keys and
    -- table-shape mismatches; an emitted leaf involves nil only when neither side
    -- nor defaults define it (renderers already tolerate that as absent).
    local function DiffSection(simpleCfg, duplicate, defaults, prefixText, result)
        simpleCfg = type(simpleCfg) == "table" and simpleCfg or {}
        duplicate = type(duplicate) == "table" and duplicate or {}
        defaults = type(defaults) == "table" and defaults or {}
        local keyList = {}
        for k in pairs(simpleCfg) do
            keyList[k] = true
        end
        for k in pairs(duplicate) do
            keyList[k] = true
        end
        for k in pairs(defaults) do
            keyList[k] = true
        end
        for k in pairs(keyList) do
            if type(k) ~= "number" and not RB_SKIP_KEYS[k] then
                local sv, cv, dv = simpleCfg[k], duplicate[k], defaults[k]
                local effS = (sv == nil) and dv or sv
                local effC = (cv == nil) and dv or cv
                local filePath = prefixText and (prefixText .. PS .. tostring(k)) or tostring(k)
                if type(effS) == "table" and type(effC) == "table" then
                    DiffSection(
                        type(sv) == "table" and sv or nil,
                        type(cv) == "table" and cv or nil,
                        type(dv) == "table" and dv or nil,
                        filePath,
                        result
                    )
                elseif type(effS) ~= "table" and type(effC) ~= "table" and effS ~= effC then
                    result[filePath] = true
                end
            end
        end
    end

    -- Threshold merge: makes the spec resolve in the SIMPLE list exactly as it did
    -- in the advanced copy. Copy entries matching the spec (explicit or All-Specs)
    -- are retargeted to specIDs={spec} and front-inserted in resolver tier order
    -- (spec+talent, spec plain, all+talent, all plain); the spec is stripped from
    -- pre-existing Simple entries so nothing else can match it.
    local function MergeThresholds(simpleSec, copySec, specId, backupCopy)
        local cList = copySec.thresholdSpecs
        if type(cList) ~= "table" or #cList == 0 then
            return
        end
        if DeepEq(cList, simpleSec.thresholdSpecs) then
            return
        end
        if copySec.thresholdFormMode or simpleSec.thresholdFormMode then
            -- Form-mode thresholds resolve by druid form, not spec; a per-spec
            -- retarget cannot represent them. Keep them in the backup only.
            backupCopy.thresholdFormMergeSkipped = true
            return
        end
        local specTalent, specPlain, allTalent, allPlain = {}, {}, {}, {}
        for _, record in ipairs(cList) do
            if type(record) == "table" and type(record.specIDs) == "table" then
                local mSpec, mAll = false, false
                for _, spellRef in ipairs(record.specIDs) do
                    if spellRef == specId then
                        mSpec = true
                    end
                    if spellRef == 0 then
                        mAll = true
                    end
                end
                if mSpec or mAll then
                    local cp = DeepCopyT(record)
                    cp.specIDs = { specId }
                    local specBucket
                    if record.talentSpellID then
                        specBucket = mSpec and specTalent or allTalent
                    else
                        specBucket = mSpec and specPlain or allPlain
                    end
                    specBucket[#specBucket + 1] = cp
                end
            end
        end
        simpleSec.thresholdSpecs = simpleSec.thresholdSpecs or {}
        local target = simpleSec.thresholdSpecs
        -- Strip this spec from pre-existing Simple entries (dropping any that
        -- served only it).
        for index = #target, 1, -1 do
            local record = target[index]
            if type(record) == "table" and type(record.specIDs) == "table" then
                local changed = false
                for jdx = #record.specIDs, 1, -1 do
                    if record.specIDs[jdx] == specId then
                        table.remove(record.specIDs, jdx)
                        changed = true
                    end
                end
                if changed and #record.specIDs == 0 then
                    table.remove(target, index)
                end
            end
        end
        -- Front-insert retargeted entries in tier order.
        local merged = {}
        for _, specBucket in ipairs({ specTalent, specPlain, allTalent, allPlain }) do
            for _, record in ipairs(specBucket) do
                merged[#merged + 1] = record
            end
        end
        for index = #merged, 1, -1 do
            table.insert(target, 1, merged[index])
        end
    end

    --- Migrates one profile root table (CludesUIDB.profiles[name] shape:
    --- .addons.CludesUIResourceBars + spec-override tables at root).
    function CludesUI.MigrateRBAdvancedProfile(profileTbl)
        if type(profileTbl) ~= "table" then
            return
        end
        local resourceBars = profileTbl.addons and profileTbl.addons.CludesUIResourceBars
        if type(resourceBars) ~= "table" then
            return
        end
        if resourceBars._rbAdvMigrated then
            return
        end
        -- Defaults are mandatory for effective-value comparison: without them (RB
        -- not loaded) do nothing and leave the flag unset so it runs when RB inits.
        local DEFS = CludesUI._RBSectionDefaults
        if type(DEFS) ~= "table" then
            return
        end
        resourceBars._rbAdvMigrated = true

        local advancedCfg = resourceBars.advancedSpecs
        local advancedActive = {}
        if type(advancedCfg) == "table" then
            for _, entry in ipairs(advancedCfg) do
                if type(entry) == "table" and type(entry.specID) == "number" and entry.enabled ~= false then
                    advancedActive[#advancedActive + 1] = entry
                end
            end
        end
        local hasDisabled = false
        for _, section in ipairs(RB_SECTIONS) do
            local cfg = resourceBars[section.key]
            if type(cfg) == "table" and type(cfg.disabledSpecs) == "table" and next(cfg.disabledSpecs) then
                hasDisabled = true
                break
            end
        end
        if #advancedActive == 0 and not hasDisabled and not (type(advancedCfg) == "table" and #advancedCfg > 0) then
            return -- nothing to migrate
        end

        profileTbl.specOverrides = profileTbl.specOverrides or {}
        profileTbl.specOverrideGroups = profileTbl.specOverrideGroups or {}
        local storage, groups = profileTbl.specOverrides, profileTbl.specOverrideGroups
        local function nextId()
            local ident = (profileTbl.specOverrideNextId or 0) + 1
            profileTbl.specOverrideNextId = ident
            return ident
        end

        local backupCopy = { advancedSpecs = advancedCfg, disabledSpecs = {} }

        -- One card per advanced spec (created lazily).
        local specCards = {}
        local function SpecCard(specId)
            local g = specCards[specId]
            if not g then
                local details = SPEC_INFO[specId]
                local label
                if details then
                    label = details[1] .. " - " .. (CLASS_TITLE[details[2]] or details[2])
                else
                    label = "Spec " .. tostring(specId)
                end
                g = {
                    id = nextId(),
                    name = label,
                    icon = details and { kind = "class", key = details[2] } or nil,
                    specs = { specId },
                }
                specCards[specId] = g
                groups[#groups + 1] = g
            end
            return g
        end

        for _, section in ipairs(RB_SECTIONS) do
            local simpleCfg = resourceBars[section.key]
            if type(simpleCfg) == "table" then
                local defaults = type(DEFS[section.key]) == "table" and DEFS[section.key] or {}
                local enabledFkey = RB_FOLDER .. FS .. section.key .. PS .. "enabled"
                local simpleEff = SectionEff(section, simpleCfg, defaults)

                -- 1) Threshold merges + per-spec diffs (defaults-merged)
                local union = {}
                local copyBySpec = {}
                local specsWithDiffs = {}
                for _, entry in ipairs(advancedActive) do
                    local duplicate = entry[section.key]
                    if type(duplicate) == "table" then
                        MergeThresholds(simpleCfg, duplicate, entry.specID, backupCopy)
                        copyBySpec[entry.specID] = duplicate
                        local result = {}
                        DiffSection(simpleCfg, duplicate, defaults, nil, result)
                        for filePath in pairs(result) do
                            union[filePath] = true
                            specsWithDiffs[entry.specID] = true
                        end
                    end
                end

                -- 2) Effective enables: advanced copies fold their own enabled
                --    + disabledSpecs; Simple disabledSpecs cover non-copy specs.
                local effEnable = {}
                for specId, duplicate in pairs(copyBySpec) do
                    local effective = SectionEff(section, duplicate, defaults, specId)
                    if effective ~= simpleEff then
                        effEnable[specId] = effective
                        specsWithDiffs[specId] = true
                    end
                end
                local dsSpecs = {}
                local ds = simpleCfg.disabledSpecs
                backupCopy.disabledSpecs[section.key] = ds
                if type(ds) == "table" then
                    for specId, on in pairs(ds) do
                        if on and type(specId) == "number" and not copyBySpec[specId] and simpleEff then
                            effEnable[specId] = false
                            dsSpecs[#dsSpecs + 1] = specId
                        end
                    end
                end
                table.sort(dsSpecs)
                if next(effEnable) then
                    union["enabled"] = true
                end

                -- 3) Spec-card entries: full union, values for EVERY copy-
                --    holding spec (order-independent for shared keys), plus
                --    partial enabled-only maps for enable-card specs.
                if next(union) then
                    local default = {}
                    for filePath in pairs(union) do
                        local val = GetPathEff(simpleCfg, defaults, filePath)
                        local fieldKey = RB_FOLDER .. FS .. section.key .. PS .. filePath
                        default[fieldKey] = (val == nil or type(val) == "table") and NIL_SENT or val
                    end
                    local valuesBySpec = {}
                    for specId, duplicate in pairs(copyBySpec) do
                        local m = {}
                        for filePath in pairs(union) do
                            local val = GetPathEff(duplicate, defaults, filePath)
                            local fieldKey = RB_FOLDER .. FS .. section.key .. PS .. filePath
                            m[fieldKey] = (val == nil or type(val) == "table") and NIL_SENT or val
                        end
                        if union["enabled"] then
                            -- effective enable (section truthiness + the
                            -- copy's own disabledSpecs folded in)
                            m[enabledFkey] = SectionEff(section, duplicate, defaults, specId)
                        end
                        valuesBySpec[specId] = m
                    end
                    for _, specId in ipairs(dsSpecs) do
                        valuesBySpec[specId] = { [enabledFkey] = false }
                    end

                    for specId in pairs(specsWithDiffs) do
                        if copyBySpec[specId] then
                            local g = SpecCard(specId)
                            local record = {
                                label = section.label,
                                crumb = "Resource Bars  >  " .. RB_PAGE,
                                module = RB_FOLDER,
                                page = RB_PAGE,
                                group = g.id,
                                values = { default = DeepCopyT(default) },
                            }
                            for sID, m in pairs(valuesBySpec) do
                                record.values[sID] = DeepCopyT(m)
                            end
                            storage[#storage + 1] = record
                        end
                    end

                    -- 4) Enable card for Simple disabledSpecs specs.
                    if #dsSpecs > 0 then
                        local g = {
                            id = nextId(),
                            name = section.label,
                            icon = { kind = "multi" },
                            specs = dsSpecs,
                        }
                        groups[#groups + 1] = g
                        local record = {
                            label = section.enableLabel,
                            crumb = "Resource Bars  >  " .. RB_PAGE,
                            module = RB_FOLDER,
                            page = RB_PAGE,
                            group = g.id,
                            values = { default = { [enabledFkey] = default[enabledFkey] } },
                        }
                        -- every diverging spec gets its effective value so
                        -- apply order over the shared key can never clobber
                        for specId, effective in pairs(effEnable) do
                            record.values[specId] = { [enabledFkey] = effective }
                        end
                        storage[#storage + 1] = record
                    end
                end

                simpleCfg.disabledSpecs = nil
            end
        end

        -- 5) Backup + strip the retired mechanisms.
        resourceBars.advancedSpecsBackup = backupCopy
        resourceBars.advancedSpecs = nil
        resourceBars.advancedSelectedSpec = nil
        resourceBars.barDisplayMode = nil
    end
end

-- Deliberately NOT registered with the early migration runner: comparison needs
-- RB's DEFAULTS table, which exists only once the RB addon loads. RB's
-- OnInitialize exports CludesUI._RBSectionDefaults then invokes
-- MigrateRBAdvancedProfile per stored profile; import paths call it direct.

-- Per-character data leaked through shared profiles: the DataBars cross-character gold
-- ledger (addons.CludesUIDataBars.characters) and the QoL upgrade calculator's
-- per-character scan state (addons.CludesUIQoL.chars) sat at profile scope, so
-- exported profiles carried the sharer's character names, realms and gold. Both stores
-- are account-wide now (CludesUIDB.goldLedger, which absorbed .dataBarsGold, / .qolUpgradeCalcChars); module init
-- drops the keys from the ACTIVE profile, this sweep drops them from every stored
-- profile (cleanup, not the safety line -- string export paths strip them too).
-- Deliberately DROP rather than merge into the account stores: any profile may be an
-- import with no durable record of that, so merging could copy a stranger's characters
-- into permanent account-wide storage; nothing is lost since each character re-records
-- on login/next scan. Folder literals contain "CludesUI", which the standalone
-- packager renames to the build token, matching each build's stored profile keys.
CludesUI.RegisterMigration({
    id = "per_character_data_account_wide_v1",
    scope = "global",
    description = "Drop leaked per-character data (Info Bar gold ledger, QoL upgrade-calc state) from every stored profile; both are account-wide now.",
    body = function(context)
        local saved = context.db
        if not saved or type(saved.profiles) ~= "table" then
            return
        end
        for _, profileSaved in pairs(saved.profiles) do
            local addonStores = type(profileSaved) == "table" and type(profileSaved.addons) == "table" and profileSaved.addons or nil
            if addonStores then
                local dbars = addonStores["CludesUIDataBars"]
                if type(dbars) == "table" then
                    dbars.characters = nil
                end
                local qolCfg = addonStores["CludesUIQoL"]
                if type(qolCfg) == "table" then
                    qolCfg.chars = nil
                end
            end
        end
    end,
})

-- The options panel is pinned to physical pixels (baseScale =
-- GetScreenWidth()/physW), holding a constant physical size that does NOT follow
-- the UI Scale slider. Fine at 1080p, but above it the same pixel count covers
-- far less screen: the panel arrives small and the slider appears to do nothing.
-- New installs seed panelScale from display height in CludesUI_Startup.lua;
-- this brings existing displays onto the same value. 1440p is the reference: a
-- panel of H units covers H*panelScale/physH of the screen, so physH/1440
-- reproduces 1440p's screen fraction anywhere (4K seeds 1.5, reads like a 2K
-- monitor). The two halves are deliberately asymmetric:
--   ABOVE 1440p -- ONE-TIME RESET overwriting whatever is stored. The old default
--   (1.0) rendered the panel undersized there, so a raised stored value is a
--   WORKAROUND for that bug, not a preference, and would now be an oversized
--   stale compensation (popups no longer scale quadratically with it).
--   Migrations stamp done and never re-run, so this fires exactly once; anything
--   chosen afterward is kept forever.
--   AT OR BELOW 1440p -- nothing was broken, seed is 1.0 anyway, so a stored
--   value can only be a genuine preference. Left alone, except v1-seed residue
--   (physH/1080): a value matching v1's output ON a save carrying v1's stamp.
CludesUI.RegisterMigration({
    id = "panel_scale_highdpi_reset_v3",
    scope = "global",
    description = "Reset the options-panel scale on displays above 1440p to the corrected default, and seed it elsewhere.",
    body = function(context)
        local saved = context.db
        if not saved then
            return
        end
        local _, physH = GetPhysicalScreenSize()
        if type(physH) ~= "number" or physH <= 0 then
            return
        end
        -- Snap BEFORE the reset test: the Window Scale slider moves in 5% steps,
        -- so an off-step seed (1600p lands on 1.111) would read differently from
        -- what the panel renders at. Testing the SNAPPED value keeps the reset
        -- honest: a display rounding back to 1.00 has nothing to correct and must
        -- not fire the overwrite branch.
        local wasSeeded = math.max(1, math.min(physH / 1440, 2))
        if CludesUI.SnapPanelScale then
            wasSeeded = CludesUI.SnapPanelScale(wasSeeded)
        end

        if wasSeeded > 1 then
            -- Above the reference: one-time reset (see above).
            saved.panelScale = wasSeeded
            return
        end

        -- At or below the reference: only fill in an unset/default value, or
        -- clear v1 residue.
        local current = saved.panelScale
        local isDefault = (current == nil or current == 1.0)
        local v1Ran = saved._migrations and saved._migrations.panel_scale_highdpi_seed_v1
        local oldSeed = math.max(1, math.min(physH / 1080, 2))
        local isV1Residue = v1Ran and current ~= nil and math.abs(current - oldSeed) < 0.001
        if not isDefault and not isV1Residue then
            return
        end
        if wasSeeded ~= (current or 1.0) then
            saved.panelScale = wasSeeded
        end
    end,
})

--------------------------------------------------------------------------------
--  Player castbar spell target -> None. The player castbar never rendered the
--  spell target before the display fix (an "and ownerUnit ~= 'player'" guard
--  swallowed it), so any inherited or explicitly-set side would make the text
--  pop in on update. Pin existing profiles to None; the player default is now
--  false too, so only users who opt back in see it.
--------------------------------------------------------------------------------
CludesUI.RegisterMigration({
    id = "uf_player_cast_target_none_v1",
    scope = "profile",
    description = "Pin the player castbar spell target to None (it never displayed before the fix).",
    body = function(context)
        local ufStore = context.profile.addons and context.profile.addons.CludesUIUnitFrames
        local p = ufStore and ufStore.player
        if type(p) == "table" then
            p.showCastTarget = false
        end
    end,
})

--------------------------------------------------------------------------------
--  Raid Frames: dispellableDebuff* keys moved party-sync sections
--
--  Their controls are drawn under the DISPELS header but the keys were filed
--  under "debuffDisplay", so on the Party tab they were editable whenever
--  Dispels was unsynced while the write routed through Debuff Display. They now
--  file under "dispels".
--
--  Writing one required BOTH sections custom, but re-syncing DISPELS afterwards
--  only deleted keys mapped to "dispels", so these could survive as a live
--  override under a custom Debuff Display with Dispels synced. Under the new
--  mapping that value would go dormant; the mirror case (dormant under a synced
--  Debuff Display, live once Dispels is custom) would switch on.
--
--  Clear the override whenever its live/dormant state would flip. In the
--  flip-to-live case that preserves exactly what the party renders today; in
--  the flip-to-dormant case the party inherits raid either way, and clearing
--  stops the value reviving later. An override live in BOTH mappings (both
--  sections custom, the normal case) is left untouched.
--------------------------------------------------------------------------------
CludesUI.RegisterMigration({
    id = "rf_dispellable_debuff_party_section_v1",
    scope = "profile",
    description = "Clear dispellableDebuff* party overrides whose live/dormant state would flip when the keys moved to the Dispels sync section.",
    body = function(context)
        local raidCfg = context.profile.addons and context.profile.addons.CludesUIRaidFrames
        if type(raidCfg) ~= "table" then
            return
        end
        local ss = type(raidCfg.partySyncSections) == "table" and raidCfg.partySyncSections or nil
        local wasLive = (ss and ss.debuffDisplay == false) and true or false
        local willBeLive = (ss and ss.dispels == false) and true or false
        if wasLive == willBeLive then
            return
        end
        raidCfg.party_dispellableDebuffLocation = nil
        raidCfg.party_dispellableDebuffGrowDirection = nil
        raidCfg.party_dispellableDebuffOffsetX = nil
        raidCfg.party_dispellableDebuffOffsetY = nil
        raidCfg.party_dispellableDebuffSize = nil
    end,
})

--------------------------------------------------------------------------------
--  Raid Frames: threatBorderSize moved party-sync sections
--
--  The "Threat Borders" slider is drawn on the Health Bar row but the key was
--  filed under the Indicators party-sync section, so editing it on the Party
--  tab wrote the shared raid value. The key now files under "healthBar", which
--  matches where its control lives.
--
--  Writing party_threatBorderSize through the UI required both sections custom,
--  but the legacy showThreat -> slider conversion writes it directly, bypassing
--  that gate. So the override can be live under one mapping and dormant under
--  the other, in either direction. Clear it whenever that state would flip: in
--  the flip-to-live case that preserves exactly what party renders today, and
--  in the flip-to-dormant case party inherits raid either way while clearing
--  stops the value reviving later. An override live under BOTH mappings (the
--  normal both-custom case) is left untouched.
--------------------------------------------------------------------------------
CludesUI.RegisterMigration({
    id = "rf_threat_border_party_section_v2",
    scope = "profile",
    description = "Clear a party threat border override whose live/dormant state would flip when threatBorderSize moved to the Health Bar sync section.",
    body = function(context)
        local raidCfg = context.profile.addons and context.profile.addons.CludesUIRaidFrames
        if type(raidCfg) ~= "table" then
            return
        end
        -- Consume the legacy party conversion HERE. ERF:OnInitialize performs
        -- the same rewrite, but child addons initialize after the parent's
        -- ADDON_LOADED, so deferring to it would let a dormant 0 land after
        -- this body had already decided and stamped. Clearing the flag makes
        -- that later block a no-op; the raid showThreat key is untouched.
        if raidCfg.party_showThreat ~= nil then
            if raidCfg.party_showThreat == false then
                raidCfg.party_threatBorderSize = 0
            end
            raidCfg.party_showThreat = nil
        end
        if raidCfg.party_threatBorderSize == nil then
            return
        end
        local ss = type(raidCfg.partySyncSections) == "table" and raidCfg.partySyncSections or nil
        local wasLive = (ss and ss.indicators == false) and true or false
        local willBeLive = (ss and ss.healthBar == false) and true or false
        if wasLive ~= willBeLive then
            raidCfg.party_threatBorderSize = nil
        end
    end,
})

--------------------------------------------------------------------------------
--  Cyrillic locales gained real font choice: several bundled faces carry the
--  full Cyrillic block (CludesUI.FONT_CYRILLIC) and ResolveFontName now
--  honours them instead of forcing the system glyph font. That must not change
--  what anyone already sees, so existing installs are pinned to System Default
--  and the new faces stay an opt-in pick.
--
--  Detecting "untouched" is exact here: before this change the ruRU picker could
--  only ever store the __system sentinel, the __expressway sentinel, or an
--  external SharedMedia name. Plain "Expressway" was unreachable as a choice, so
--  it can only be the seeded default -- rewriting just that value leaves every
--  deliberate pick alone. Fresh installs never reach this body; GetFontsDB seeds
--  the correct default for them directly.
--------------------------------------------------------------------------------
CludesUI.RegisterMigration({
    id = "ru_cyrillic_font_optin_v1",
    scope = "global",
    description = "Pin existing Cyrillic-locale installs to the system glyph font so the newly selectable bundled Cyrillic faces stay opt-in.",
    body = function(context)
        if CludesUI.LOCALE_SCRIPT ~= "cyrillic" then
            return
        end
        local fontMap = context.db and context.db.fonts
        if not fontMap then
            return
        end -- fresh install: GetFontsDB seeds it
        if fontMap.global == "Expressway" then
            fontMap.global = CludesUI.SYSTEM_FONT_KEY
        end
    end,
})

--------------------------------------------------------------------------------
--  The CludesUI minimap button is a LibDBIcon button now (LibDBIcon10_CludesUI,
--  13 Nov 2026). A profile that placed the old CludesUIMinimapButton on the
--  minimap button row keeps that place under the new name.
--------------------------------------------------------------------------------
CludesUI.RegisterMigration({
    id = "minimap_button_libdbicon_v1",
    scope = "profile",
    description = "Move the CludesUI minimap button's button-row placement to its LibDBIcon name.",
    body = function(context)
        local mod = context.profile and context.profile.addons and context.profile.addons.CludesUIMinimap
        local minimapCfg = type(mod) == "table" and mod.minimap
        local ug = type(minimapCfg) == "table" and minimapCfg.ungroupedButtons
        if type(ug) == "table" and ug.CludesUIMinimapButton ~= nil then
            if ug.LibDBIcon10_CludesUI == nil then
                ug.LibDBIcon10_CludesUI = ug.CludesUIMinimapButton
            end
            ug.CludesUIMinimapButton = nil
        end
    end,
})

--------------------------------------------------------------------------------
--  Expressway is the default font again (Barlow Condensed was the default for
--  a short while from 11 Nov 2026). Installs and profiles left on Barlow
--  Condensed go back to Expressway once; it stays in the font list to pick.
--------------------------------------------------------------------------------
CludesUI.RegisterMigration({
    id = "default_font_back_to_expressway_v1",
    scope = "global",
    description = "Move the saved global font from Barlow Condensed back to Expressway, the default again.",
    body = function(context)
        local fontMap = context.db and context.db.fonts
        if fontMap and fontMap.global == "Barlow Condensed" then
            fontMap.global = "Expressway"
        end
    end,
})

CludesUI.RegisterMigration({
    id = "default_font_back_to_expressway_profile_v1",
    scope = "profile",
    description = "Move a profile's global font from Barlow Condensed back to Expressway, the default again.",
    body = function(context)
        local fontMap = context.profile and context.profile.fonts
        if fontMap and fontMap.global == "Barlow Condensed" then
            fontMap.global = "Expressway"
        end
    end,
})

--------------------------------------------------------------------------------
--  Power Bar's per-form threshold mode used to resolve Moonkin into the same
--  "mana" entry as Caster (both report PT.MANA from GetPrimaryPowerType()).
--  Now that Moonkin is checked by form ID and gets its own "moonkin" bucket,
--  seed it as a copy of the existing "mana" entry so upgrading users see the
--  same threshold behavior in Moonkin they had before, with a separate entry
--  to customize going forward.
--------------------------------------------------------------------------------
CludesUI.RegisterMigration({
    id = "erb_power_form_mode_moonkin_bucket_v1",
    scope = "profile",
    description = "Give the Power Bar's per-form threshold mode its own Moonkin entry instead of sharing Caster's.",
    body = function(context)
        local resBarsCfg = context.profile.addons and context.profile.addons.CludesUIResourceBars
        local primaryCfg = resBarsCfg and resBarsCfg.primary
        if not primaryCfg or not primaryCfg.thresholdFormMode then
            return
        end
        local entries = primaryCfg.thresholdSpecs
        if type(entries) ~= "table" or #entries == 0 then
            return
        end
        local manaEntry
        for _, record in ipairs(entries) do
            if type(record) == "table" then
                if record.formKey == "moonkin" then
                    return
                end -- already migrated
                if record.formKey == "mana" then
                    manaEntry = record
                end
            end
        end
        if not manaEntry then
            return
        end
        local moonkinEntry = CludesUI.Lite.DeepCopy(manaEntry)
        moonkinEntry.formKey = "moonkin"
        entries[#entries + 1] = moonkinEntry
    end,
})

-- Same split for the Health/Power "hide bar/text per form" popups: Moonkin
-- used to share the "mana"/Caster bucket, so disabling Caster there also hid
-- Moonkin. Seed moonkin=true wherever mana=true so that choice survives.
-- Class Resource is skipped: its Caster choice never applied in Moonkin Form.
CludesUI.RegisterMigration({
    id = "erb_moonkin_form_bucket_v1",
    scope = "profile",
    description = "Preserve existing Moonkin bar/text visibility now that Moonkin has its own per-form bucket separate from Caster.",
    body = function(context)
        local resBarsCfg = context.profile.addons and context.profile.addons.CludesUIResourceBars
        if not resBarsCfg then
            return
        end
        local function SeedMoonkin(sectionKey)
            local section = resBarsCfg[sectionKey]
            if not section then
                return
            end
            for _, field in ipairs({ "textDisabledForms", "barDisabledForms" }) do
                local df = section[field]
                if type(df) == "table" and df.mana and df.moonkin == nil then
                    df.moonkin = true
                end
            end
        end
        SeedMoonkin("health")
        SeedMoonkin("primary")
    end,
})

-- Merge Groups renders through one Blizzard flat SecureGroupHeader, whose column
-- axis can only run perpendicular to Unit Growth -- a same-axis pair has no valid
-- column direction, so the runtime silently substitutes one instead of honoring
-- Group Growth. The options UI now prevents new conflicting pairs; this fixes up
-- profiles that already saved one.
CludesUI.RegisterMigration({
    id = "rf_merge_groups_growth_axis_v1",
    scope = "profile",
    description = "For Raid Frames profiles with Merge Groups on, bump Unit Growth off Group Growth's axis (base and per-tier overrides) so the merged flat header has a valid column direction.",
    body = function(context)
        local raidCfg = context.profile.addons and context.profile.addons.CludesUIRaidFrames
        if type(raidCfg) ~= "table" then
            return
        end
        if not raidCfg.mergeGroups then
            return
        end
        local function vertical(g)
            return g == "UP" or g == "DOWN"
        end
        local gg, ug = raidCfg.groupGrowth or "RIGHT", raidCfg.unitGrowth or "DOWN"
        if vertical(gg) == vertical(ug) then
            ug = vertical(gg) and "RIGHT" or "DOWN"
            raidCfg.unitGrowth = ug
        end
        local overrides = raidCfg.raidSizeOverrides
        if type(overrides) ~= "table" then
            return
        end
        for _, shade in pairs(overrides) do
            if type(shade) == "table" then
                local ogg = shade.groupGrowth or gg
                local oug = shade.unitGrowth or ug
                if vertical(ogg) == vertical(oug) then
                    shade.unitGrowth = vertical(ogg) and "RIGHT" or "DOWN"
                end
            end
        end
    end,
})

-- The Important Cast Glow menu used to offer exactly two engines under an ad-hoc
-- numbering: 1 = Pixel Glow, 4 = Auto-Cast Shine. It now offers the whole
-- PANDEMIC_GLOW_STYLES list, where 3 is Auto-Cast Shine and 4 is GCD -- so a saved
-- 4 would silently become a different glow. Re-point it.
--
-- 4 is the only value that can be stale: 1 means Pixel Glow in both numberings and
-- nothing else was reachable from the old menu. Runs per profile and the flag rides
-- on the profile data, so a profile IMPORTED from an older build is fixed up on the
-- pass after it lands rather than staying wrong forever.
CludesUI.RegisterMigration({
    id = "np_important_cast_glow_style_reindex_v1",
    scope = "profile",
    description = "Re-point the saved Important Cast Glow style from the old two-entry numbering (4 = Auto-Cast Shine) onto the PANDEMIC_GLOW_STYLES index (3).",
    body = function(context)
        local plateCfg = context.profile.addons and context.profile.addons.CludesUINameplates
        if type(plateCfg) ~= "table" then
            return
        end
        if plateCfg.importantCastGlowStyle == 4 then
            plateCfg.importantCastGlowStyle = 3
        end
    end,
})

-- The target/focus/boss Debuff Filter became a single-select mode. Before it, a
-- frame with NOTHING checked (Own Only off, Important off) that carried Tracked
-- Auras rendered ONLY those spells -- the include link was the whole chain. The
-- mode model treats Tracked Auras as additional in every mode and derives such
-- a frame as Show All, so pin those frames to Only Tracked Auras once. Every
-- other combination derives its old display from the untouched legacy keys
-- (ns.UF_DebuffFilterMode in CUI_UnitFrames_AuraContainers.lua). An explicit
-- mode is never touched, so a re-run is a no-op.
CludesUI.RegisterMigration({
    id = "uf_debuff_filter_tracked_only_v1",
    scope = "profile",
    description = "Pin target/focus/boss Debuff Filters that had nothing checked but carried Tracked Auras (they rendered only those spells) to the Only Tracked Auras mode.",
    body = function(context)
        local ufStore = context.profile.addons and context.profile.addons.CludesUIUnitFrames
        if type(ufStore) ~= "table" then
            return
        end
        for _, unitName in ipairs({ "target", "focus", "boss" }) do
            local cfg = ufStore[unitName]
            if
                type(cfg) == "table"
                and cfg.debuffFilterMode == nil
                and cfg.onlyPlayerDebuffs ~= true
                and cfg.debuffPriorityAura ~= true
                and type(cfg.debuffInclude) == "table"
            then
                for _, on in pairs(cfg.debuffInclude) do
                    if on then
                        cfg.debuffFilterMode = "tracked"
                        break
                    end
                end
            end
        end
    end,
})

-- Visibility "Never" used to write enabledFrames[unit] = false, and that key decides
-- whether the frame is BUILT, once, at login -- so a Spec Override carrying it left
-- the frame uncreated for the whole session with no way back but a /reload.
-- Visibility no longer touches it and the visibility pass hides the frame at runtime
-- instead, so clear the flag the old pairing left behind. player/target/focus have no
-- Enable toggle of their own, so a stored false there can only have come from it.
CludesUI.RegisterMigration({
    id = "uf_visibility_never_keeps_frame_v1",
    scope = "profile",
    description = 'Clear the enabledFrames flag Visibility "Never" used to write for player/target/focus, so the frame is built and a Spec Override can lift the hide without a reload.',
    body = function(context)
        local UNITS = { "player", "target", "focus" }
        local ufStore = context.profile.addons and context.profile.addons.CludesUIUnitFrames
        local ef = ufStore and ufStore.enabledFrames
        if type(ef) == "table" then
            for _, unitName in ipairs(UNITS) do
                if ef[unitName] == false then
                    ef[unitName] = nil
                end
            end
        end
        -- Auto-capture banked the key alongside barVisibility while the two were
        -- written together, and nothing blacklists it -- left in place, the next
        -- spec apply writes false back and the frame goes missing again at the
        -- following login. Other units keep theirs: their Enable toggles own it.
        local stale = {}
        for _, unitName in ipairs(UNITS) do
            stale["CludesUIUnitFrames\31enabledFrames\30" .. unitName] = true
        end
        local function strip(storage)
            if type(storage) ~= "table" then
                return
            end
            for index = #storage, 1, -1 do
                local e = storage[index]
                local valueList = type(e) == "table" and e.values
                if type(valueList) == "table" then
                    for _, m in pairs(valueList) do
                        if type(m) == "table" then
                            for fieldKey in pairs(m) do
                                if stale[fieldKey] then
                                    m[fieldKey] = nil
                                end
                            end
                        end
                    end
                    if type(valueList.default) ~= "table" or next(valueList.default) == nil then
                        table.remove(storage, index)
                    end
                end
            end
        end
        strip(context.profile.specOverrides)
        strip(context.profile.condOverrides)
    end,
})

-- Damage Meters barHeight and Spell History shBarHeight/iconSize now render in UI
-- units instead of physical pixels (value * perfect / ppUIScale, UIParent-parented
-- frames). Multiply by that factor once so existing profiles keep their exact size.
-- GLOBAL on purpose: a profile stamp rides exports, so an old string would get the
-- RECIPIENT's factor frozen in; imports after this ran are read as UI units.
-- Per-profile stamps keep it idempotent when a full-account import resets flags.
CludesUI.RegisterMigration({
    id = "dm_bar_height_ui_units_v1",
    scope = "global",
    description = "Convert Damage Meters bar height and Spell History bar height/icon size from physical pixels to UI units, keeping every existing profile's rendered size.",
    body = function(context)
        local ID = "dm_bar_height_ui_units_v1"
        local saved = context.db
        if not saved or type(saved.profiles) ~= "table" then
            return
        end
        -- No stamp without the real factor: an error retries next session
        -- (Startup seeds ppUIScale at login).
        local _, physH = GetPhysicalScreenSize()
        if type(physH) ~= "number" or physH <= 0 then
            error("physical screen size not available")
        end
        local uiScale = saved.ppUIScale
        if type(uiScale) ~= "number" or uiScale <= 0 then
            error("ppUIScale not set yet")
        end
        -- Same legacy normalization CludesUI_Startup applies before SetScale.
        if uiScale == 0.53 then
            uiScale = 0.5333333333
        elseif uiScale == 0.71 then
            uiScale = 0.7111111111
        end
        local factor = (768 / physH) / uiScale
        -- Within 1% the 40px slider maximum moves by under half a pixel, so the
        -- snapped size is identical: pixel-perfect setups keep their values as-is.
        local convert = math.abs(factor - 1) > 0.01
        local function conv(val, default)
            local num = type(val) == "number" and val or default
            return floor(num * factor * 10000 + 0.5) / 10000
        end
        for _, profileRec in pairs(saved.profiles) do
            if type(profileRec) == "table" then
                local stampSet = profileRec._migrations
                if type(stampSet) ~= "table" then
                    stampSet = {}
                    profileRec._migrations = stampSet
                end
                if not stampSet[ID] then
                    -- Folder present = DM ran in this profile; dm itself is
                    -- missing when every value was a stripped default.
                    local addon = convert
                        and type(profileRec.addons) == "table"
                        and profileRec.addons.CludesUIDamageMeters
                    if type(addon) == "table" then
                        if type(addon.dm) ~= "table" then
                            addon.dm = {}
                        end
                        local meterCfg = addon.dm
                        meterCfg.barHeight = conv(meterCfg.barHeight, 18)
                        local sh = meterCfg.spellHistory
                        if type(sh) == "table" then
                            sh.shBarHeight = conv(sh.shBarHeight, 20)
                            sh.iconSize = conv(sh.iconSize, 36)
                        end
                    end
                    stampSet[ID] = true
                end
            end
        end
    end,
})

-- The Swing Timer's default visibility is In Combat (was Always). A profile left
-- on the old default stores nothing (Lite strips defaults at logout) and follows
-- the new default by itself; this moves the ones that carry an explicit plain
-- "always" (no conditions, no hide lanes) as well. GLOBAL with per-profile stamps,
-- gated on existing profiles: a fresh install stamps and never runs it, so a new
-- user's deliberate Always choice is never flipped, and a stamped profile keeps
-- its stamp through exports.
CludesUI.RegisterMigration({
    id = "swing_timer_visibility_in_combat_v1",
    scope = "global",
    description = "Move the Swing Timer's visibility from Always to In Combat, the new default.",
    body = function(context)
        local ID = "swing_timer_visibility_in_combat_v1"
        local saved = context.db
        if not (saved and type(saved.profiles) == "table" and next(saved.profiles)) then
            return
        end
        for _, profileRec in pairs(saved.profiles) do
            if type(profileRec) == "table" then
                local stampSet = profileRec._migrations
                if type(stampSet) ~= "table" then
                    stampSet = {}
                    profileRec._migrations = stampSet
                end
                if not stampSet[ID] then
                    local resBarsCfg = type(profileRec.addons) == "table" and profileRec.addons.CludesUIResourceBars
                    local settingsTbl = type(resBarsCfg) == "table" and resBarsCfg.swingTimer
                    if type(settingsTbl) == "table" and settingsTbl.visibility == "always" and settingsTbl.visibilityModes == nil then
                        settingsTbl.visibility = "in_combat"
                    end
                    stampSet[ID] = true
                end
            end
        end
    end,
})

-- The Swing Timer's indicator toggles became two settings: Attack State (Off /
-- Queued Only / Full) replaces Highlight Queued Attacks, Highlight Active Attack
-- and Show Shot Pending; Movement Guide (Off / Segments / Wind-Up Bar) replaces
-- Latency Overlay and Smooth Swing Timing. Only explicit values
-- move (defaults are stripped at logout); the colour keys keep their names, and
-- the latency zone keeps its old red where no colour was stored (GO's default
-- is white). Per profile: no current setting writes the old keys, so a profile
-- imported later from an older string migrates on its next load.
CludesUI.RegisterMigration({
    id = "swing_timer_indicators_v1",
    scope = "profile",
    description = "Move the Swing Timer's indicator toggles into Attack State and Movement Guide.",
    body = function(context)
        local profileRec = context.profile
        local resBarsCfg = type(profileRec.addons) == "table" and profileRec.addons.CludesUIResourceBars
        local settingsTbl = type(resBarsCfg) == "table" and resBarsCfg.swingTimer
        if type(settingsTbl) ~= "table" then
            return
        end
        if settingsTbl.activeHighlight or settingsTbl.pendingEnabled then
            settingsTbl.attackState = "full"
        elseif settingsTbl.queueHighlight == false then
            settingsTbl.attackState = "off"
        end
        if settingsTbl.latencyEnabled then
            settingsTbl.moveGuide = "segments"
            if settingsTbl.latencyR == nil then
                settingsTbl.latencyR, settingsTbl.latencyG, settingsTbl.latencyB, settingsTbl.latencyA = 0.835, 0.290, 0.290, 1
            end
        end
        settingsTbl.queueHighlight, settingsTbl.activeHighlight, settingsTbl.pendingEnabled = nil, nil, nil
        settingsTbl.latencyEnabled, settingsTbl.smoothTiming = nil, nil
    end,
})

-- WoW Forever: the Swing Timer follows the Resource Bars row of Global
-- Settings > Style, and its texture rides that row's style slots. Slots saved
-- before then take the texture it has now, so switching styles later brings a
-- custom texture back (also after the Classic seed's Plating, which a profile
-- already on Classic gets at its first load with this build); a slot without
-- it restores the default. Existing accounts only: a fresh install stamps it
-- without running.
if CludesUI.IS_FOREVER == true then
    CludesUI.RegisterMigration({
        id = "swing_timer_style_slots_v1",
        scope = "global",
        description = "Save the Swing Timer's texture into the Resource Bars style slots saved before it joined them.",
        body = function(context)
            local profileSet = context.db and context.db.profiles
            if type(profileSet) ~= "table" then
                return
            end
            for _, profileRec in pairs(profileSet) do
                local resBarsCfg = type(profileRec) == "table"
                    and type(profileRec.addons) == "table"
                    and profileRec.addons.CludesUIResourceBars
                local settingsTbl = type(resBarsCfg) == "table" and resBarsCfg.swingTimer
                local texture = type(settingsTbl) == "table" and settingsTbl.texture or nil
                local slots = texture ~= nil and resBarsCfg._styleSlots
                if type(slots) == "table" then
                    for _, slot in pairs(slots) do
                        if type(slot) == "table" and slot["swingTimer.texture"] == nil then
                            slot["swingTimer.texture"] = texture
                        end
                    end
                end
            end
        end,
    })
end

-- Spell ID on Tooltip became on by default (an unset showSpellID reads as on,
-- CludesUI.SpellIDOn). An account from before keeps it off: its unset value
-- is written off. Existing users ONLY: a fresh install or Reset ALL has no
-- profiles yet, is genesis-stamped, and takes the new default.
CludesUI.RegisterMigration({
    id = "spellid_default_on_v1",
    scope = "global",
    description = "Keep Spell ID on Tooltip off for existing users after its default changed from off to on.",
    body = function(context)
        local saved = context.db
        if not (saved.profiles and next(saved.profiles)) then
            return
        end
        if saved.showSpellID == nil then
            saved.showSpellID = false
        end
    end,
})

-- The Bags sidebar's one-time "categories can be dragged" tip is for new
-- users: an account that already ran Bags (it seeds its default category
-- groups at its first login) starts with it seen. A fresh install or Reset ALL
-- is genesis-stamped and sees it, and so does an account that turns Bags on
-- for the first time later.
CludesUI.RegisterMigration({
    id = "bags_category_tip_existing_seen_v1",
    scope = "global",
    description = "Mark the Bags category drag tip as seen for existing Bags users, so only new users see it.",
    body = function(context)
        local saved = context.db
        if saved.bagCategoryTipSeen == nil and saved.bagDefaultGroupsSeeded then
            saved.bagCategoryTipSeen = true
        end
    end,
})

-- WoW Forever Junk Items: Include White Items became Maximum Quality and Skip
-- Confirmation for White Items became Delete Without Confirming. An account
-- with either on keeps it as Common; both old keys go. Registered on the
-- Forever client only, where Junk Items exists.
if CludesUI.IS_FOREVER == true then
    CludesUI.RegisterMigration({
        id = "junk_items_quality_settings_v1",
        scope = "global",
        description = "Move the Junk Items white-item toggles into Maximum Quality and Delete Without Confirming.",
        body = function(context)
            local c = context.db.junkList
            if type(c) ~= "table" then
                return
            end
            local COMMON = Enum.ItemQuality.Common
            if c.includeWhite and c.maxQuality == nil then
                c.maxQuality = COMMON
            end
            if c.skipWhiteConfirm and c.oneClickQuality == nil then
                c.oneClickQuality = COMMON
            end
            c.includeWhite, c.skipWhiteConfirm = nil, nil
        end,
    })
end

-- WoW Forever CDM spell store repairs for imported and switched profiles.
if CludesUI.IS_FOREVER == true then
    local GHOST_CD = "__ghost_cd"
    local DEFAULT_BARS = {
        { key = "cooldowns", barType = "cooldowns" },
        { key = "utility", barType = "utility" },
        { key = "buffs", barType = "buffs" },
    }

    local function HoldsLayout(profileTbl)
        if type(profileTbl) ~= "table" then
            return false
        end
        if type(profileTbl.barSpells) == "table" then
            for barKey, barConf in pairs(profileTbl.barSpells) do
                if
                    barKey ~= GHOST_CD
                    and type(barConf) == "table"
                    and type(barConf.assignedSpells) == "table"
                    and #barConf.assignedSpells > 0
                then
                    return true
                end
            end
        end
        local trackingBars = profileTbl.trackedBuffBars
        return type(trackingBars) == "table" and type(trackingBars.bars) == "table" and #trackingBars.bars > 0
    end

    local function HasEntries(t)
        return type(t) == "table" and next(t) ~= nil
    end

    -- The reseed and a Repopulate write only Blizzard spell IDs on Cooldowns and
    -- Utility, plus the item rows they mark in nativeItems. Anything else in the
    -- bucket was placed or set by the player.
    local function HoldsPlayerEdits(profileTbl)
        if HasEntries(profileTbl.spellSettingsCD) or HasEntries(profileTbl.spellSettingsBuff) then
            return true
        end
        local trackingBars = profileTbl.trackedBuffBars
        if type(trackingBars) == "table" and HasEntries(trackingBars.bars) then
            return true
        end
        local glows = profileTbl.barGlows
        if type(glows) == "table" and type(glows.assignments) == "table" then
            for _, entryList in pairs(glows.assignments) do
                if HasEntries(entryList) then
                    return true
                end
            end
        end
        if type(profileTbl.barSpells) ~= "table" then
            return false
        end
        for barKey, barConf in pairs(profileTbl.barSpells) do
            if type(barConf) == "table" then
                if
                    HasEntries(barConf.customSpellIDs)
                    or HasEntries(barConf.customSpellDurations)
                    or HasEntries(barConf.spellDurations)
                    or HasEntries(barConf.spellSettings)
                    or HasEntries(barConf.barSettings)
                    or HasEntries(barConf.hostedBuffSpellIDs)
                    or barConf._buffDisplayOrderUserModified
                then
                    return true
                end
                local entryList = barConf.assignedSpells
                if type(entryList) == "table" then
                    if #entryList > 0 and barKey ~= "cooldowns" and barKey ~= "utility" then
                        return true
                    end
                    for _, spellRef in ipairs(entryList) do
                        if
                            type(spellRef) == "number"
                            and spellRef < 0
                            and not (barConf.nativeItems and barConf.nativeItems[spellRef])
                        then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end

    -- A class reads its Forever spec key before its retail keys (SpecFor), so a
    -- bucket under the Forever key hides a retail-keyed layout of the class. A
    -- profile apply created one, empty, which CUI then filled with Blizzard's
    -- default layout at the next login. Drop it only while it holds no more
    -- than that, and only when the key the class reads next holds a layout.
    -- An imported bucket stays: it is the sharer's, its Hidden CDs stripped.
    CludesUI.RegisterMigration({
        id = "cdm_forever_drop_shadowing_spec_v1",
        scope = "specProfile",
        description = "Drop a Forever spec key CDM bucket holding only Blizzard's layout that hides a retail-keyed layout of the same class.",
        body = function(context)
            local ident = tonumber(context.specKey)
            local cls = ident and CludesUI.SpecClassOf(ident)
            if not cls or CludesUI.FOREVER_CLASS_SPEC[cls] ~= ident then
                return
            end
            if context.specProfile._importGhostMode or HoldsPlayerEdits(context.specProfile) then
                return
            end
            local specList = CludesUIDB.spellAssignments.profiles[context.profileName].specProfiles
            local nextKey = CludesUI.ForeverClassSpec(cls, CludesUI.SpecHasStringEntry, specList)
            if HoldsLayout(specList[tostring(nextKey)]) then
                specList[context.specKey] = nil
            end
        end,
    })

    -- GetSpellName is nil for a spell that does not exist. One that exists but
    -- has no name this early fails the body, so the runner retries next load.
    local function SpellName(spellRef)
        local num = C_Spell.GetSpellName(spellRef)
        if not num and C_Spell.DoesSpellExist(spellRef) then
            error("no name yet for spell " .. spellRef)
        end
        return num
    end

    -- Each rank of a spell is its own spell ID, and a bar lists a spell once
    -- under any rank. Import ghosting compared IDs only, so it hid the rank a
    -- frame showed when the layout listed another rank of the spell on a
    -- visible cooldown bar.
    CludesUI.RegisterMigration({
        id = "cdm_forever_ghost_rank_aliases_v1",
        scope = "specProfile",
        description = "Unhide spells the ghost CD bar holds under another rank of a spell placed on a visible cooldown bar.",
        body = function(context)
            local barSpellMap = context.specProfile.barSpells
            local ghost = type(barSpellMap) == "table" and barSpellMap[GHOST_CD]
            local entryList = type(ghost) == "table" and ghost.assignedSpells
            if type(entryList) ~= "table" or #entryList == 0 then
                return
            end
            local profileTbl = CludesUIDB.profiles and CludesUIDB.profiles[context.profileName]
            local cdmStore = type(profileTbl) == "table" and profileTbl.addons and profileTbl.addons.CludesUICooldownManager
            local barList = cdmStore and cdmStore.cdmBars and cdmStore.cdmBars.bars
            if type(barList) ~= "table" then
                barList = DEFAULT_BARS
            end

            -- Saved bars drop fields equal to the defaults, which list the
            -- Cooldowns, Utility and Buffs bars first.
            local placedNames, placedIds = {}, {}
            for index, edge in ipairs(barList) do
                local default = DEFAULT_BARS[index]
                local fieldKey = edge.key or (default and default.key)
                local barType = edge.barType or (default and default.barType)
                local enabled = edge.enabled
                if enabled == nil and default then
                    enabled = true
                end
                local barConf = fieldKey
                    and enabled
                    and not edge.isGhostBar
                    and barType ~= "buffs"
                    and barType ~= "custom_buff"
                    and barSpellMap[fieldKey]
                if type(barConf) == "table" and type(barConf.assignedSpells) == "table" then
                    for _, spellRef in ipairs(barConf.assignedSpells) do
                        if
                            type(spellRef) == "number"
                            and spellRef > 0
                            and not (barConf.customSpellIDs and barConf.customSpellIDs[spellRef])
                        then
                            placedIds[spellRef] = true
                            local num = SpellName(spellRef)
                            if num then
                                placedNames[num] = true
                            end
                        end
                    end
                end
            end

            -- An entry hidden under the placed ID itself stays hidden.
            for index = #entryList, 1, -1 do
                local spellRef = entryList[index]
                if type(spellRef) == "number" and spellRef > 0 and not placedIds[spellRef] then
                    local num = SpellName(spellRef)
                    if num and placedNames[num] then
                        table.remove(entryList, index)
                    end
                end
            end
        end,
    })
end

-- Player Aura Bars icons with a custom Icon Shape used to zoom the spell art far
-- past their Icon Zoom (the shaped icon grew past its button and still took the
-- zoom crop), so most players with a shape dragged Icon Zoom down to 0. Shaped
-- icons now take the crop an unshaped icon takes at the same zoom, where 0 shows
-- the whole art, its dark edge included. Every bar with a custom shape still at 0
-- moves to 6 (an unset zoom reads 5.5): the profile's own bars and every Spec
-- Override or Condition value stored for one, each entry's banked default
-- included, or leaving an override would write the 0 back. Unshaped bars never
-- zoomed wrong and keep their zoom. PROFILE scope on purpose: an export string
-- from before carries no stamp and is fixed at its next load, while a profile
-- made from a fixed one inherits its stamp.
do
    local ZOOM = 0.06
    local UF = "CludesUIUnitFrames"
    local PAB_ROOT = UF .. "\31playerAuraBars"
    local PAB_PREFIX = PAB_ROOT .. "\30"
    local ZOOM_LEAF, SHAPE_LEAF = "\30iconZoom", "\30iconShape"
    local NIL_SENT = "__SPECOV_NIL__" -- a stored "key removed" override value
    local OV_STORES = { "specOverrides", "condOverrides" }

    -- Player Aura Bars' own test (PabShapeActive): any shape but "none".
    local function Shaped(shape)
        return type(shape) == "string" and shape ~= "none"
    end

    -- Every bar table under t. Only a bar carries iconShape and iconZoom, so the
    -- walk needs no map of where bars live (the default bars, the custom lists,
    -- the per-spec buckets).
    local function FixTree(tbl, depth)
        if tbl.iconZoom == 0 and Shaped(tbl.iconShape) then
            tbl.iconZoom = ZOOM
        end
        if depth < 6 then
            for _, val in pairs(tbl) do
                if type(val) == "table" then
                    FixTree(val, depth + 1)
                end
            end
        end
    end

    -- The bar table an override path names inside playerAuraBars (list indexes
    -- are stored as strings, as the override engine writes them).
    local function BarAt(pab, relative)
        local tbl = pab
        for seg in relative:gmatch("[^\30]+") do
            if type(tbl) ~= "table" then
                return nil
            end
            local val = tbl[seg]
            if val == nil then
                local num = tonumber(seg)
                if num then
                    val = tbl[num]
                end
            end
            tbl = val
        end
        return type(tbl) == "table" and tbl or nil
    end

    -- One stored override value map: a whole subtree is walked like the
    -- profile's own bars; a lone zoom of 0 takes the shape this layer gives its
    -- bar (the layer's own value, else the profile's bar).
    local function FixMap(map, pab)
        for fieldKey, val in pairs(map) do
            if type(fieldKey) == "string" and (fieldKey == PAB_ROOT or fieldKey:sub(1, #PAB_PREFIX) == PAB_PREFIX) then
                if type(val) == "table" then
                    FixTree(val, 0)
                elseif val == 0 and fieldKey:sub(-#ZOOM_LEAF) == ZOOM_LEAF then
                    local barConf = fieldKey:sub(1, -#ZOOM_LEAF - 1)
                    local shape = map[barConf .. SHAPE_LEAF]
                    if shape == nil and pab then
                        local tbl = BarAt(pab, barConf:sub(#PAB_PREFIX + 1))
                        shape = tbl and tbl.iconShape
                    end
                    if shape ~= NIL_SENT and Shaped(shape) then
                        map[fieldKey] = ZOOM
                    end
                end
            end
        end
    end

    CludesUI.RegisterMigration({
        id = "pab_shaped_icon_zoom_v1",
        scope = "profile",
        description = "Player Aura Bars: Icon Zoom 6 on bars with a custom Icon Shape left at 0 by the old shaped-icon over-zoom.",
        body = function(context)
            local profileTbl = context.profile
            local addonStores = profileTbl.addons
            local ufStore = type(addonStores) == "table" and addonStores[UF] or nil
            local pab = type(ufStore) == "table" and ufStore.playerAuraBars or nil
            if type(pab) ~= "table" then
                pab = nil
            end
            -- Overrides first: their shape test reads the profile's bars, which
            -- the pass below never changes the shape of anyway.
            for si = 1, #OV_STORES do
                local storage = profileTbl[OV_STORES[si]]
                if type(storage) == "table" then
                    for _, record in pairs(storage) do
                        local valueList = type(record) == "table" and record.values
                        if type(valueList) == "table" then
                            for _, map in pairs(valueList) do
                                if type(map) == "table" then
                                    FixMap(map, pab)
                                end
                            end
                        end
                    end
                end
            end
            if pab then
                FixTree(pab, 0)
            end
        end,
    })
end

--------------------------------------------------------------------------------
--  WOW FOREVER: ONE-TIME BUFF CLEAR
--
--  On WoW Forever only, each piece of buff data is cleared once:
--    * Raid Frames Buff Manager (live store and override forks): left with no
--      indicator groups in any bucket. Its filter library, its icon zoom, the
--      Debuff Manager and every other Raid Frames setting stay.
--    * Player Aura Bars, buff side: back to a new profile's state (the Buffs
--      bar on All Buffs, custom buff bars gone, the module re-seeds its own
--      disabled External Defensives bar). Debuff bars, both filter libraries,
--      layout and style stay.
--  Every write lives in this block and re-checks the client at the moment it
--  writes. Hook sites only call CludesUI.FvBW, which stays nil on every
--  other client (the block defines nothing there).
--
--  CONTRACT: the key "fvBuffWipe" marks data that went through the clear (or
--  was born on WoW Forever after it). It sits INSIDE the data it certifies, so
--  every path that moves the data moves the mark:
--    bm2.fvBuffWipe                   Raid Frames live store
--    specBmOverrides.fvBuffWipe and   Buff Manager fork stores (profile root):
--    condBmOverrides.fvBuffWipe       one unit, marked when either root has it
--    playerAuraBars.fvBuffWipe        Unit Frames
--  PRESENCE = cleared; the value is never compared. The name is frozen saved
--  data: a second clear must use a NEW key. It is in no defaults table (a
--  default would stamp data without clearing it).
--  Imports: fork stores that arrive in the same string as a marked live store
--  were banked from cleared data, so they take the mark as they are.
--  The account flag "forever_buff_wipe_sweep_v1" (CludesUIDB._migrations)
--  records the one login that also strips Player Aura Bars buff overrides from
--  profiles holding no Player Aura Bars table (data older than this block).
--
--  WOW FOREVER: BUFF MANAGER STARTER SEED
--
--  Retail's per-bucket starter groups never seed on WoW Forever. Instead the
--  Raid Frames Buff Manager gets two All Specs groups, once per store, when
--  the profile holds no indicator group anywhere (the live store and every
--  override fork layer, each after its clear above):
--    * "Defensives & Consumables": icons at the center growing both ways, any
--      caster, the Defensives, Externals and Consumables filters.
--    * "Core Healing Buffs": icons at the top right growing left, own casts
--      only, the Core Healing Buffs filter.
--  Both go into the base Buff Manager only: the live store while it holds the
--  base (no fork live), and the banked baseline layer whenever one exists, so
--  a repaint of the base keeps them. Fork layers are never seeded. It is
--  decided only while the live store holds the layer the spec root's pointer
--  names: never between a layer paint and the pointer's move, never during an
--  editing session.
--  CONTRACT: the key "fvBmSeed" (bm2.fvBmSeed, beside the clear's mark) marks
--  a store whose seed was decided: seeded, or passed over because a group
--  already existed. Same rules as "fvBuffWipe": presence only, frozen name, in
--  no defaults table, and it travels with the data, so a store that arrives
--  marked is never seeded.
--------------------------------------------------------------------------------
do
    local ADDON_NAME = ...

    -- The interface number, read directly: WoW Forever reports 16000-19999
    -- (the client gate's own band); retail and the PTR report 120100+.
    local function TocForever()
        local tocVersion = select(4, GetBuildInfo())
        return type(tocVersion) == "number" and tocVersion >= 16000 and tocVersion < 20000
    end
    -- Two independent client checks: the suite's flag and the raw interface
    -- number. Tested here and again inside every function that writes.
    local function ClientOK()
        return CludesUI ~= nil and CludesUI.IS_FOREVER == true and TocForever()
    end

    if ClientOK() then
        local KEY = "fvBuffWipe"
        local SWEEP_ID = "forever_buff_wipe_sweep_v1"
        local UF, RF = "CludesUIUnitFrames", "CludesUIRaidFrames"
        local PS = "\30"
        local OV_STORES = { "specOverrides", "condOverrides" }

        -- Default Buffs bar CONTENT fields (what it shows); layout and style stay.
        local BUFF_CONTENT = {
            "showAllBuffs",
            "hasDuration",
            "filters",
            "negFilters",
            "spells",
            "blacklist",
            "ownOnlySpells",
            "enabled",
        }

        -- Unit Frames setting paths the clear empties (an override entry on one,
        -- or under one, would re-apply cleared content), plus the mark's own.
        local PAB_PATH = "playerAuraBars" .. PS
        local MARK_PATH = PAB_PATH .. KEY
        local CLEARED_PATHS = {
            PAB_PATH .. "customBuffBars",
            PAB_PATH .. "defaultExternalDefensives",
            PAB_PATH .. "extDefPos",
            PAB_PATH .. "pabExtDefSeeded",
            MARK_PATH,
            "externalDefensives",
        }
        for index = 1, #BUFF_CONTENT do
            CLEARED_PATHS[#CLEARED_PATHS + 1] = PAB_PATH .. "defaultBuffs" .. PS .. BUFF_CONTENT[index]
        end

        -- Failures go to the migration error log, read at failure time; nothing
        -- is printed.
        local function Log(err)
            local t = CludesUI._migrationErrors
            if type(t) == "table" then
                t[#t + 1] = {
                    id = "forever_buff_wipe",
                    scope = "profile",
                    err = tostring(err),
                    time = GetTime(),
                }
            end
        end

        -- A blank Buff Manager payload: Raid Frames' own "empty" preset (every key
        -- that would seed content is pre-seeded EMPTY, so the data also reads
        -- blank on retail), else plain empty maps. Fresh tables on every call.
        local function BlankFork()
            local func = _G._CURF_BM2PresetFork
            if type(func) == "function" then
                local success, f = pcall(func, "empty")
                if
                    success
                    and type(f) == "table"
                    and type(f.specs) == "table"
                    and type(f.seeded) == "table"
                then
                    return f
                end
                Log(success and "blank payload without specs/seeded maps" or f)
            end
            return { specs = {}, seeded = {} }
        end

        -- Planned writes: (table, key, value) triples plus array removals (in
        -- descending index order per array), built without writing and then
        -- committed as plain assignments, so a commit cannot stop halfway.
        local function Put(plan, t, key, val)
            local num = plan.n + 1
            plan.n = num
            plan[num * 3 - 2], plan[num * 3 - 1], plan[num * 3] = t, key, val
        end
        local function Commit(plan)
            for index = 1, plan.n do
                local t, k = plan[index * 3 - 2], plan[index * 3 - 1]
                t[k] = plan[index * 3]
            end
            local rm = plan.rm
            for index = 1, #rm, 2 do
                table.remove(rm[index], rm[index + 1])
            end
        end

        -- An override fkey on a cleared Unit Frames path (markOnly: the mark's
        -- own path alone).
        local function Cleared(fieldKey, markOnly)
            if type(fieldKey) ~= "string" then
                return false
            end
            local folder, filePath = fieldKey:match("^([^\31]+)\31(.*)$")
            if folder ~= UF or not filePath then
                return false
            end
            if markOnly then
                return filePath == MARK_PATH
            end
            for index = 1, #CLEARED_PATHS do
                local base = CLEARED_PATHS[index]
                if filePath == base or filePath:sub(1, #base + 1) == base .. PS then
                    return true
                end
            end
            local _, e = filePath:find("^playerAuraBars\30pabSpecBars\30[^\30]+\30buffBars")
            return e ~= nil and (e == #filePath or filePath:sub(e + 1, e + 1) == PS)
        end

        -- Override entries (the spec and condition stores of a profile root) lose
        -- every matching path from every value map; an entry whose default map
        -- is left empty is removed, as the override engine's own prune does.
        local function PlanStrip(profileTbl, plan, markOnly)
            if type(profileTbl) ~= "table" then
                return
            end
            for si = 1, #OV_STORES do
                local storage = profileTbl[OV_STORES[si]]
                if type(storage) == "table" then
                    for index = #storage, 1, -1 do
                        local e = storage[index]
                        local valueList = type(e) == "table" and e.values
                        if type(valueList) == "table" then
                            for _, m in pairs(valueList) do
                                if type(m) == "table" then
                                    for fieldKey in pairs(m) do
                                        if Cleared(fieldKey, markOnly) then
                                            Put(plan, m, fieldKey, nil)
                                        end
                                    end
                                end
                            end
                            local default = valueList.default
                            if type(default) == "table" then
                                local hit, leftX = false, false
                                for fieldKey in pairs(default) do
                                    if Cleared(fieldKey, markOnly) then
                                        hit = true
                                    else
                                        leftX = true
                                    end
                                end
                                if hit and not leftX then
                                    plan.rm[#plan.rm + 1] = storage
                                    plan.rm[#plan.rm + 1] = index
                                end
                            end
                        end
                    end
                end
            end
        end

        local function CollectIds(entryList, set)
            if type(entryList) ~= "table" then
                return
            end
            for index = 1, #entryList do
                local barConf = entryList[index]
                if type(barConf) == "table" and barConf.id ~= nil then
                    set[barConf.id] = true
                end
            end
        end

        -- Player Aura Bars buff side (s = the playerAuraBars table). Only keys that
        -- exist are written, so a table with no buff content gets only the mark.
        -- Kept: debuff bars and their per-spec disables, both filter libraries,
        -- the bar id counter, the one-shot flags, layout and style.
        local function PlanPAB(cfg, plan)
            local buffIds, debuffIds = {}, {}
            CollectIds(cfg.customBuffBars, buffIds)
            CollectIds(cfg.customDebuffBars, debuffIds)
            local settingsTbl = cfg.pabSpecBars
            if type(settingsTbl) == "table" then
                for _, barKey in pairs(settingsTbl) do
                    if type(barKey) == "table" then
                        CollectIds(barKey.buffBars, buffIds)
                        CollectIds(barKey.debuffBars, debuffIds)
                    end
                end
                -- Every bucket (role buckets included) loses its buff bars and the
                -- per-spec disables of removed buff bars; an id a debuff bar also
                -- carries keeps its entry.
                for _, barKey in pairs(settingsTbl) do
                    if type(barKey) == "table" then
                        local bb = barKey.buffBars
                        if type(bb) == "table" and next(bb) ~= nil then
                            Put(plan, barKey, "buffBars", {})
                        end
                        local dis = barKey.inhDis
                        if type(dis) == "table" then
                            for ident in pairs(dis) do
                                if buffIds[ident] and not debuffIds[ident] then
                                    Put(plan, dis, ident, nil)
                                end
                            end
                        end
                    end
                end
            end
            -- nil content = a new profile's Buffs bar: All Buffs on, bar shown.
            local d = cfg.defaultBuffs
            if type(d) == "table" then
                for index = 1, #BUFF_CONTENT do
                    local f = BUFF_CONTENT[index]
                    if d[f] ~= nil then
                        Put(plan, d, f, nil)
                    end
                end
            end
            local callback = cfg.customBuffBars
            if type(callback) == "table" and next(callback) ~= nil then
                Put(plan, cfg, "customBuffBars", {})
            end
            -- The retired External Defensives sources and the seed flag: the module
            -- re-seeds a new profile's disabled bar at its next build.
            if cfg.defaultExternalDefensives ~= nil then
                Put(plan, cfg, "defaultExternalDefensives", nil)
            end
            if cfg.extDefPos ~= nil then
                Put(plan, cfg, "extDefPos", nil)
            end
            if cfg.pabExtDefSeeded ~= nil then
                Put(plan, cfg, "pabExtDefSeeded", nil)
            end
        end

        local function PlanUF(ufStore, s, profileTbl, strip, plan)
            if s then
                PlanPAB(s, plan)
            end
            if ufStore and ufStore.externalDefensives ~= nil then
                Put(plan, ufStore, "externalDefensives", nil)
            end
            if strip then
                PlanStrip(profileTbl, plan, strip == "mark")
            end
        end

        -- Import only (pd = the payload's profile root, before anything runs):
        -- fork stores that arrive beside a marked live Buff Manager were banked
        -- from cleared data (here, or on the other client from a profile that
        -- came from here), so they take the mark as they are and are never
        -- cleared. Decided from the payload alone, never at run time: a live
        -- store is marked before its profile's forks are first read.
        local function TrustForks(profileSaved)
            local s, c = profileSaved.specBmOverrides, profileSaved.condBmOverrides
            local swingCfg, cT = type(s) == "table", type(c) == "table"
            if not (swingCfg or cT) then
                return
            end
            if (swingCfg and s[KEY] ~= nil) or (cT and c[KEY] ~= nil) then
                return
            end
            local addonStores = profileSaved.addons
            local raidCfg = type(addonStores) == "table" and addonStores[RF] or nil
            local b = type(raidCfg) == "table" and raidCfg.bm2 or nil
            if type(b) ~= "table" or b[KEY] == nil then
                return
            end
            if not ClientOK() then
                return
            end
            if swingCfg then
                s[KEY] = 1
            end
            if cT then
                c[KEY] = 1
            end
        end

        local FvBW = { KEY = KEY, ClientOK = ClientOK }

        -- Raid Frames live store (p = the Raid Frames profile): every indicator
        -- group in every bucket goes, replaced by the blank payload, and the mark
        -- lands in the same assignment. The filter library stays (Player Aura
        -- Bars' copy buttons share it). Returns the marked store, nil when
        -- nothing was written.
        function FvBW.ClearBM(profile)
            if type(profile) ~= "table" then
                return nil
            end
            local b = profile.bm2
            if type(b) == "table" and b[KEY] ~= nil then
                return nil
            end
            if not ClientOK() then
                return nil
            end
            local f = BlankFork()
            if type(b) == "table" then
                local filters = b.filters
                if type(filters) ~= "table" then
                    filters = { nextId = 1, list = {} }
                end
                b.filters, b.specs, b.seeded, b[KEY] = filters, f.specs, f.seeded, 1
            else
                b = { filters = { nextId = 1, list = {} }, specs = f.specs, seeded = f.seeded, [KEY] = 1 }
                profile.bm2 = b
            end
            return b
        end

        -- Seed gate: retail's per-bucket starter groups never seed on WoW Forever
        -- (its own starter seed is FvBW.SeedStarter). Guarantees the bucket
        -- exists with an indicator array (so the retired editor fallback never
        -- runs) and is marked seeded. False only when the client check fails.
        function FvBW.SeedEmpty(b, fieldKey)
            if type(b) ~= "table" or fieldKey == nil then
                return false
            end
            local specs, wasSeeded = b.specs, b.seeded
            local barKey = type(specs) == "table" and specs[fieldKey] or nil
            if
                type(barKey) == "table"
                and type(barKey.inds) == "table"
                and type(barKey.nextId) == "number"
                and type(wasSeeded) == "table"
                and wasSeeded[fieldKey]
            then
                return true
            end
            if not ClientOK() then
                return false
            end
            if type(specs) ~= "table" then
                specs = {}
                b.specs = specs
            end
            if type(wasSeeded) ~= "table" then
                wasSeeded = {}
                b.seeded = wasSeeded
            end
            if type(barKey) ~= "table" then
                specs[fieldKey] = { nextId = 1000001, inds = {} }
            else
                if type(barKey.inds) ~= "table" then
                    barKey.inds = {}
                end
                if type(barKey.nextId) ~= "number" then
                    local topY = 1000000
                    for index = 1, #barKey.inds do
                        local ind = barKey.inds[index]
                        local ident = type(ind) == "table" and tonumber(ind.id) or nil
                        if ident and ident > topY then
                            topY = ident
                        end
                    end
                    barKey.nextId = topY + 1
                end
            end
            wasSeeded[fieldKey] = true
            return true
        end

        -- A fork layer with no v2 payload gets a blank one instead of being
        -- converted from its retired legacy fields. False only when the client
        -- check fails.
        function FvBW.BlankLayer(layer)
            if type(layer) ~= "table" or not ClientOK() then
                return false
            end
            layer.bm2 = BlankFork()
            return true
        end

        -- Buff Manager fork stores (prof = a profile root): one unit, cleared once.
        -- Every layer's v2 payload becomes blank (the rest of each layer, its
        -- icon zoom included, stays), then every existing root is stamped; a
        -- root created on this client is stamped at birth, and a root born
        -- beside a marked one joins its mark. Waits while Raid Frames is not
        -- loaded: nothing can bank into or apply from a store then.
        function FvBW.BmForks(profileTbl)
            if type(profileTbl) ~= "table" then
                return
            end
            local s, c = profileTbl.specBmOverrides, profileTbl.condBmOverrides
            local swingCfg, cT = type(s) == "table", type(c) == "table"
            if not (swingCfg or cT) then
                return
            end
            local sM, cM = swingCfg and s[KEY] ~= nil, cT and c[KEY] ~= nil
            if sM or cM then
                if ((swingCfg and not sM) or (cT and not cM)) and ClientOK() then
                    if swingCfg and not sM then
                        s[KEY] = 1
                    end
                    if cT and not cM then
                        c[KEY] = 1
                    end
                end
                return
            end
            if not ClientOK() then
                return
            end
            if type(_G._CURF_BM2PresetFork) ~= "function" then
                return
            end
            local layers = {}
            if swingCfg then
                if type(s.layouts) == "table" then
                    for _, l in pairs(s.layouts) do
                        if type(l) == "table" then
                            layers[#layers + 1] = l
                        end
                    end
                end
                if type(s.baselineLayout) == "table" then
                    layers[#layers + 1] = s.baselineLayout
                end
            end
            if cT and type(c.layouts) == "table" then
                for _, l in pairs(c.layouts) do
                    if type(l) == "table" then
                        layers[#layers + 1] = l
                    end
                end
            end
            local blanks = {}
            for index = 1, #layers do
                blanks[index] = BlankFork()
            end
            for index = 1, #layers do
                layers[index].bm2 = blanks[index]
            end
            if swingCfg then
                s[KEY] = 1
            end
            if cT then
                c[KEY] = 1
            end
        end

        -- Buff Manager starter seed (see the banner); "fvBmSeed" is its mark.
        local SEED_KEY = "fvBmSeed"

        -- True when any bucket of a v2 specs map holds an indicator group.
        local function HasGroups(specs)
            if type(specs) ~= "table" then
                return false
            end
            for _, barKey in pairs(specs) do
                local inds = type(barKey) == "table" and barKey.inds
                if type(inds) == "table" and next(inds) ~= nil then
                    return true
                end
            end
            return false
        end

        -- A fork layer's v2 payload holds a group. A layer with no v2 payload
        -- applies blank on this client.
        local function LayerHasGroups(l)
            local pay = type(l) == "table" and l.bm2
            return type(pay) == "table" and HasGroups(pay.specs)
        end
        -- A fork root (st) has such a layer: its layouts, or the spec root's
        -- banked baseline.
        local function ForkHasGroups(settingsTbl)
            if type(settingsTbl) ~= "table" then
                return false
            end
            if type(settingsTbl.layouts) == "table" then
                for _, l in pairs(settingsTbl.layouts) do
                    if LayerHasGroups(l) then
                        return true
                    end
                end
            end
            return LayerHasGroups(settingsTbl.baselineLayout)
        end

        -- Adds the two starter groups to the "allspecs" bucket of a v2 payload
        -- (the live store or a layer's), marked seeded. ids = preset key ->
        -- filter id in the profile's filter library. Fresh tables every call.
        local function SeedAllSpecs(pay, idList)
            local specs, wasSeeded = pay.specs, pay.seeded
            if type(specs) ~= "table" then
                specs = {}
                pay.specs = specs
            end
            if type(wasSeeded) ~= "table" then
                wasSeeded = {}
                pay.seeded = wasSeeded
            end
            local barKey = specs.allspecs
            if type(barKey) ~= "table" then
                barKey = {}
                specs.allspecs = barKey
            end
            local inds = barKey.inds
            if type(inds) ~= "table" then
                inds = {}
                barKey.inds = inds
            end
            local num = type(barKey.nextId) == "number" and barKey.nextId or 1000001
            local center = {
                id = num,
                enabled = true,
                type = "icon",
                name = "Defensives & Consumables",
                ownOnly = false,
                filters = {},
                spells = {},
                position = "CENTER",
                growDirection = "CENTER",
                size = 18,
            }
            if idList.defensives then
                center.filters[idList.defensives] = true
            end
            if idList.externals then
                center.filters[idList.externals] = true
            end
            if idList.consumables then
                center.filters[idList.consumables] = true
            end
            local corner = {
                id = num + 1,
                enabled = true,
                type = "icon",
                name = "Core Healing Buffs",
                ownOnly = true,
                filters = {},
                spells = {},
                position = "TOPRIGHT",
                growDirection = "LEFT",
                size = 18,
            }
            if idList.coreheals then
                corner.filters[idList.coreheals] = true
            end
            inds[#inds + 1] = center
            inds[#inds + 1] = corner
            barKey.nextId = num + 2
            wasSeeded.allspecs = true
        end

        -- The layer the last Buff Manager paint copied into a live store,
        -- recorded by Raid Frames at the paint. Runtime only, never saved.
        local painted = nil
        function FvBW.Painted(layer)
            painted = layer
        end

        -- The slot a layer table fills in a profile's fork roots (s = spec
        -- root, c = condition root): false = the baseline, a spec group id,
        -- "cond:<id>" = a condition's layer, nil = none of them (another
        -- profile's layer, or one a harvest has since replaced).
        local function SlotOf(l, cfg, c)
            if type(cfg) == "table" then
                if l == cfg.baselineLayout then
                    return false
                end
                if type(cfg.layouts) == "table" then
                    for k, val in pairs(cfg.layouts) do
                        if val == l then
                            return k
                        end
                    end
                end
            end
            if type(c) == "table" and type(c.layouts) == "table" then
                for k, val in pairs(c.layouts) do
                    if val == l then
                        return "cond:" .. k
                    end
                end
            end
            return nil
        end

        -- Raid Frames live store (p = the Raid Frames profile, b = its store),
        -- called once the preset filters exist: the starter seed, decided once
        -- per store and only after the store's clear. Returns true when the
        -- live store gained the groups.
        function FvBW.SeedStarter(p, b)
            if type(p) ~= "table" or type(b) ~= "table" then
                return false
            end
            if b[SEED_KEY] ~= nil or b[KEY] == nil then
                return false
            end
            -- An editing session holds a conditional fork live: decided after it.
            if CludesUI._bmSessionGid ~= nil then
                return false
            end
            local idList = {}
            local entryList = type(b.filters) == "table" and b.filters.list
            if type(entryList) == "table" then
                for index = 1, #entryList do
                    local f = entryList[index]
                    if type(f) == "table" and f.preset ~= nil and f.id ~= nil then
                        idList[f.preset] = f.id
                    end
                end
            end
            -- Waits for the filter library.
            if not (idList.defensives or idList.externals or idList.consumables or idList.coreheals) then
                return false
            end
            if not ClientOK() then
                return false
            end
            -- The profile root holding this store: the fork stores live there.
            local saved = CludesUIDB
            local profileSet = type(saved) == "table" and saved.profiles
            if type(profileSet) ~= "table" then
                return false
            end
            local profileTbl = profileSet[saved.activeProfile or "Default"]
            local addonStores = type(profileTbl) == "table" and profileTbl.addons
            if not (type(addonStores) == "table" and addonStores[RF] == p) then
                profileTbl = nil
                for _, profileSaved in pairs(profileSet) do
                    addonStores = type(profileSaved) == "table" and profileSaved.addons
                    if type(addonStores) == "table" and addonStores[RF] == p then
                        profileTbl = profileSaved
                        break
                    end
                end
                if not profileTbl then
                    return false
                end
            end
            -- The fork stores' own one-time clear comes first.
            FvBW.BmForks(profileTbl)
            local s, c = profileTbl.specBmOverrides, profileTbl.condBmOverrides
            if HasGroups(b.specs) or ForkHasGroups(s) or ForkHasGroups(c) then
                b[SEED_KEY] = 1
                return false
            end
            -- The slot the live store banks into: a fork when the spec root's
            -- pointer names an existing layer, else the base (a dangling
            -- pointer banks live into the baseline, as the harvest does).
            local a = type(s) == "table" and s.active or nil
            local live = false
            if type(a) == "number" then
                if type(s.layouts) == "table" and s.layouts[a] ~= nil then
                    live = a
                end
            elseif type(a) == "string" then
                local groupId = tonumber(a:match("^cond:(%d+)$"))
                if
                    groupId ~= nil
                    and type(c) == "table"
                    and type(c.layouts) == "table"
                    and c.layouts[groupId] ~= nil
                then
                    live = "cond:" .. groupId
                end
            end
            -- Mid-paint: the live store already holds a layer of this profile
            -- that the pointer has not moved to yet (it moves after the paint's
            -- refresh returns). Decided at the next read, once they agree.
            if painted ~= nil then
                local ps = SlotOf(painted, s, c)
                if ps ~= nil and ps ~= live then
                    return false
                end
            end
            local forkLive = live ~= false
            local bl = type(s) == "table" and s.baselineLayout or nil
            if type(bl) ~= "table" then
                bl = nil
            end
            if not forkLive then
                SeedAllSpecs(b, idList)
            end
            if bl then
                if type(bl.bm2) ~= "table" then
                    bl.bm2 = BlankFork()
                end
                SeedAllSpecs(bl.bm2, idList)
            end
            b[SEED_KEY] = 1
            return not forkLive
        end

        -- Player Aura Bars (uf = a Unit Frames profile, prof = its profile root
        -- for the override strip, mode = "first" | "login" | "import" | "live"):
        --   unmarked table: clear + mark, plus the override strip except "live";
        --   marked table: nothing, except an import drops mark-path entries;
        --   no table: the retired External Defensives source is cleared (every
        --     mode but "live"), and "import" (a payload's stores cannot vouch for
        --     data they did not arrive with) and "first" (the account's one
        --     sweep of data older than this block) strip the stores anyway.
        -- A planning error still stamps the mark (logged): never cleared twice.
        function FvBW.ProcessUF(ufStore, profileTbl, modeName)
            local ufT = type(ufStore) == "table"
            local cfg = ufT and ufStore.playerAuraBars or nil
            local swingCfg = type(cfg) == "table"
            local strip, clear
            if swingCfg and cfg[KEY] ~= nil then
                if modeName ~= "import" then
                    return
                end
                strip = "mark"
            elseif swingCfg then
                clear = true
                if modeName ~= "live" then
                    strip = "full"
                end
            elseif modeName == "live" then
                return
            elseif ufT and ufStore.externalDefensives ~= nil then
                clear = true
                strip = "full"
            elseif modeName == "import" or modeName == "first" then
                strip = "full"
            else
                return
            end
            if not ClientOK() then
                return
            end
            local plan = { n = 0, rm = {} }
            local success, err =
                pcall(PlanUF, clear and ufT and ufStore or nil, clear and swingCfg and cfg or nil, profileTbl, strip, plan)
            if success then
                Commit(plan)
            else
                Log(err)
            end
            if clear and swingCfg then
                cfg[KEY] = 1
            end
        end

        -- Profile-level entry (pd = a profile root: stored, or an import payload).
        function FvBW.ProcessProfile(profileSaved, modeName)
            if type(profileSaved) ~= "table" then
                return
            end
            local addonStores = profileSaved.addons
            FvBW.ProcessUF(type(addonStores) == "table" and addonStores[UF] or nil, profileSaved, modeName)
            if modeName == "import" then
                TrustForks(profileSaved)
            end
        end

        CludesUI.FvBW = FvBW

        -- Login sweep (Player Aura Bars): every stored profile, at this addon's
        -- own ADDON_LOADED -- in the suite before any child opens its profile --
        -- and before anything can switch, sync or copy one. The vararg name stays
        -- correct in standalone builds. The account's first pass with this block
        -- runs in "first" mode; the flag is written on every pass, so an account
        -- that starts with no profiles never runs one.
        local boot = CreateFrame("Frame")
        boot:RegisterEvent("ADDON_LOADED")
        boot:SetScript("OnEvent", function(self, _, label)
            if label ~= ADDON_NAME then
                return
            end
            self:UnregisterEvent("ADDON_LOADED")
            local saved = CludesUIDB
            if type(saved) ~= "table" or not ClientOK() then
                return
            end
            local flagSet = saved._migrations
            if type(flagSet) ~= "table" then
                flagSet = {}
                saved._migrations = flagSet
            end
            local modeName = flagSet[SWEEP_ID] and "login" or "first"
            local profileSet = saved.profiles
            if type(profileSet) == "table" then
                for _, profileSaved in pairs(profileSet) do
                    FvBW.ProcessProfile(profileSaved, modeName)
                end
            end
            flagSet[SWEEP_ID] = true
        end)
    end
end

--------------------------------------------------------------------------------
--  WoW Forever snapshot switch: accounts from the base-layout era (one-time).
--  A fresh WoW Forever install now snapshots Blizzard's layout through the same
--  module captures as retail. An account that already ran CludesUI there
--  started from the old fixed base layout, with those captures switched off, so
--  it is frozen to exactly what those builds gave it: no capture runs for it
--  (Action Bars, Cooldown Manager, the minimap and the chat genesis), on old or
--  new characters, and its positions stay as they are. Its Edit Mode layouts
--  are never read or written.
--  Detection, once per account as the saved data loads (Lite's
--  OnSavedVariablesLoaded: before any module opens its profile, merges its
--  defaults or reads a capture flag, in the suite and in every standalone):
--  any Edit Mode layout stamp of the old writer (foreverEditModeSeen) or any
--  stored profile data. The flag is written first, so an account that starts
--  empty is never mistaken for one later. Two client checks, as the buff clear
--  above: the suite's flag and the raw interface number.
--------------------------------------------------------------------------------
do
    local FLAG = "forever_snapshot_legacy_v1"
    -- The full-account import keeps the recipient's mark (CludesUI_Profiles.lua).
    CludesUI._FvSnapFlag = FLAG

    local function ClientOK()
        local tocVersion = select(4, GetBuildInfo())
        return CludesUI ~= nil
            and CludesUI.IS_FOREVER == true
            and type(tocVersion) == "number"
            and tocVersion >= 16000
            and tocVersion < 20000
    end

    local function Sub(tbl, fieldKey)
        if type(tbl[fieldKey]) ~= "table" then
            tbl[fieldKey] = {}
        end
        return tbl[fieldKey]
    end

    -- True when the account holds data from an earlier WoW Forever session.
    local function HadData(saved)
        if type(saved.foreverEditModeSeen) == "table" and next(saved.foreverEditModeSeen) then
            return true
        end
        if type(saved.profiles) == "table" then
            for _, profileTbl in pairs(saved.profiles) do
                if type(profileTbl) == "table" and type(profileTbl.addons) == "table" and next(profileTbl.addons) then
                    return true
                end
            end
        end
        return false
    end

    -- One stored profile, frozen to what the base-layout builds gave it:
    --   minimap: never captured -> the old WoW Forever size, no capture;
    --   chat: the old genesis rule (a pre-ownership position is dropped) with
    --     the old WoW Forever spot in place of a live read;
    --   the two WoW Forever defaults that changed (tabs inside the chat panel,
    --     Blizzard's XP / reputation bars) keep the old default where unset.
    local function FreezeProfile(profileTbl)
        if type(profileTbl) ~= "table" then
            return
        end
        local addonStores = Sub(profileTbl, "addons")
        local minimapCfg = Sub(Sub(addonStores, "CludesUIMinimap"), "minimap")
        if not minimapCfg._capturedOnce then
            minimapCfg._capturedOnce = true
            if minimapCfg.mapSize == nil then
                minimapCfg.mapSize = 200
            end
        end
        local chatCfg = Sub(Sub(addonStores, "CludesUIChat"), "chat")
        if chatCfg._chatPosOwnership ~= 1 then
            chatCfg._chatPosOwnership = 1
            chatCfg.chatPosition = nil
        end
        if chatCfg.chatPosition == nil then
            chatCfg.chatPosition = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 63.33, y = 108.17 }
        end
        if chatCfg.extendBgBehindTabs == nil then
            chatCfg.extendBgBehindTabs = false
        end
        local barsCfg = Sub(addonStores, "CludesUIActionBars")
        if barsCfg.useBlizzardDataBars == nil then
            barsCfg.useBlizzardDataBars = false
        end
    end

    if ClientOK() then
        CludesUI.Lite.OnSavedVariablesLoaded(function()
            if not ClientOK() then
                return
            end
            local saved = CludesUIDB
            if type(saved) ~= "table" then
                -- A brand-new account (no saved data yet): nothing to freeze. It is
                -- marked once its saved data exists, so its own first session's data
                -- never reads as the old layout's next time.
                local frame = CreateFrame("Frame")
                frame:RegisterEvent("PLAYER_LOGIN")
                frame:SetScript("OnEvent", function(self)
                    self:UnregisterAllEvents()
                    local d = CludesUIDB
                    if type(d) == "table" then
                        Sub(d, "_migrations")[FLAG] = true
                    end
                end)
                return
            end
            local flagSet = Sub(saved, "_migrations")
            if flagSet[FLAG] then
                return
            end
            flagSet[FLAG] = true
            if not HadData(saved) then
                return
            end
            saved._capturedOnce_EAB = true
            saved._capturedOnce_CDM = true
            if type(saved.profiles) == "table" then
                for _, profileTbl in pairs(saved.profiles) do
                    FreezeProfile(profileTbl)
                end
            end
        end)
    end
end

--------------------------------------------------------------------------------
--  WoW Forever: Nameplates Enemy Buff Filter to Show All (one-time).
--  Show All is the WoW Forever default (every enemy buff, unfiltered). An
--  account that already ran CludesUI there is moved to it once: the filter
--  in every stored profile's Nameplates data and every Spec Override value
--  stored for it (a stored "key not present" mark already reads the default).
--  Profiles made afterwards start on the default and keep whatever is picked.
--  Account flag, written before the pass; a brand-new account is marked once
--  its saved data exists. Two client checks, as the blocks above.
--------------------------------------------------------------------------------
do
    local FLAG = "forever_np_buff_showall_v1"
    -- Spec Override value key: the module folder, "\31", then the key path
    -- (CludesUI_SpecOverrides.lua's stored format), and its "not present"
    -- mark.
    local OVERRIDE_KEY = "CludesUINameplates\31npEnemyBuffFilter"
    local NIL_SENT = "__SPECOV_NIL__"

    local function ClientOK()
        local tocVersion = select(4, GetBuildInfo())
        return CludesUI ~= nil
            and CludesUI.IS_FOREVER == true
            and type(tocVersion) == "number"
            and tocVersion >= 16000
            and tocVersion < 20000
    end

    local function MoveProfile(profileTbl)
        if type(profileTbl) ~= "table" then
            return
        end
        local plateCfg = type(profileTbl.addons) == "table" and profileTbl.addons.CludesUINameplates
        if type(plateCfg) == "table" then
            plateCfg.npEnemyBuffFilter = "showall"
        end
        if type(profileTbl.specOverrides) ~= "table" then
            return
        end
        for _, record in pairs(profileTbl.specOverrides) do
            local valueList = type(record) == "table" and record.values
            if type(valueList) == "table" then
                for _, specBucket in pairs(valueList) do
                    if type(specBucket) == "table" then
                        local val = specBucket[OVERRIDE_KEY]
                        if val ~= nil and val ~= NIL_SENT then
                            specBucket[OVERRIDE_KEY] = "showall"
                        end
                    end
                end
            end
        end
    end

    if ClientOK() then
        CludesUI.Lite.OnSavedVariablesLoaded(function()
            if not ClientOK() then
                return
            end
            local saved = CludesUIDB
            if type(saved) ~= "table" then
                -- A brand-new account: nothing to move. Marked at login, so
                -- its own first session's choices are never overwritten.
                local frame = CreateFrame("Frame")
                frame:RegisterEvent("PLAYER_LOGIN")
                frame:SetScript("OnEvent", function(self)
                    self:UnregisterAllEvents()
                    local d = CludesUIDB
                    if type(d) == "table" then
                        if type(d._migrations) ~= "table" then
                            d._migrations = {}
                        end
                        d._migrations[FLAG] = true
                    end
                end)
                return
            end
            if type(saved._migrations) ~= "table" then
                saved._migrations = {}
            end
            if saved._migrations[FLAG] then
                return
            end
            saved._migrations[FLAG] = true
            if type(saved.profiles) == "table" then
                for _, profileTbl in pairs(saved.profiles) do
                    MoveProfile(profileTbl)
                end
            end
        end)
    end
end

--------------------------------------------------------------------------------
--  WoW Forever: Nameplates Elite/Rare Indicator off on the WoW Forever look
--  (one-time). That look drew no elite or rare marks whatever the box said;
--  it now follows the box like every other look, and its own seed starts the
--  box unchecked (NP_SeedForever). Every stored profile already on that look
--  gets the same once: the value the other looks share is banked in its
--  Forever-only style slot (it comes back on the way out), then the box is
--  unchecked and the seed's stamp set, so the seed never runs over it again.
--  Spec Override values stay as they are (an override wins over a look's
--  seed, as on the Style page). Account flag, written before the pass; a
--  brand-new account is marked once its saved data exists. Two client
--  checks, as the blocks above.
--------------------------------------------------------------------------------
do
    local FLAG = "forever_np_rare_box_v1"

    local function ClientOK()
        local tocVersion = select(4, GetBuildInfo())
        return CludesUI ~= nil
            and CludesUI.IS_FOREVER == true
            and type(tocVersion) == "number"
            and tocVersion >= 16000
            and tocVersion < 20000
    end

    local function MoveProfile(profileTbl)
        if type(profileTbl) ~= "table" then
            return
        end
        local plateCfg = type(profileTbl.addons) == "table" and profileTbl.addons.CludesUINameplates
        if type(plateCfg) ~= "table" or plateCfg.foreverRareSeeded then
            return
        end
        -- The WoW Forever look: its flag rides a set Blizzard flag, and a
        -- Classic flag wins over both.
        if plateCfg.useClassicStyle or not (plateCfg.useBlizzardStyle and plateCfg.useForeverStyle) then
            return
        end
        local cfg = plateCfg._foreverStyleSlots
        if type(cfg) ~= "table" then
            cfg = {}
            plateCfg._foreverStyleSlots = cfg
        end
        local cui = cfg.cui
        if type(cui) ~= "table" then
            cui = {}
            cfg.cui = cui
        end
        cui.classificationHideRare = plateCfg.classificationHideRare
        plateCfg.classificationHideRare = true
        plateCfg.foreverRareSeeded = true
    end

    if ClientOK() then
        CludesUI.Lite.OnSavedVariablesLoaded(function()
            if not ClientOK() then
                return
            end
            local saved = CludesUIDB
            if type(saved) ~= "table" then
                -- A brand-new account: nothing to move. Marked at login, so
                -- its own first session's choices are never overwritten.
                local frame = CreateFrame("Frame")
                frame:RegisterEvent("PLAYER_LOGIN")
                frame:SetScript("OnEvent", function(self)
                    self:UnregisterAllEvents()
                    local d = CludesUIDB
                    if type(d) == "table" then
                        if type(d._migrations) ~= "table" then
                            d._migrations = {}
                        end
                        d._migrations[FLAG] = true
                    end
                end)
                return
            end
            if type(saved._migrations) ~= "table" then
                saved._migrations = {}
            end
            if saved._migrations[FLAG] then
                return
            end
            saved._migrations[FLAG] = true
            if type(saved.profiles) == "table" then
                for _, profileTbl in pairs(saved.profiles) do
                    MoveProfile(profileTbl)
                end
            end
        end)
    end
end

--------------------------------------------------------------------------------
--  WoW Forever: power text Smart Text to Power Value (one-time). WoW Forever
--  offers no Smart Text: it chooses percent or value by spec, and Forever has
--  no specs (CludesUI.PowerTextFormat). An account that already ran
--  CludesUI there has every stored "smart" moved to the value ("curpp")
--  once: the Unit Frames Power Text and Form Power Text of every frame and the
--  Resource Bars Power Text and Mana Bar Text, in every stored profile and in
--  every Spec Override value stored for them (Conditional Overrides keep their
--  values in the same entries). A "smart" that arrives later (an import) reads
--  as the value. Account flag, written before the pass; a brand-new account is
--  marked once its saved data exists. Two client checks, as the blocks above.
--------------------------------------------------------------------------------
do
    local FLAG = "forever_power_text_value_v1"
    local SMART, VALUE = "smart", "curpp"

    local function ClientOK()
        local tocVersion = select(4, GetBuildInfo())
        return CludesUI ~= nil
            and CludesUI.IS_FOREVER == true
            and type(tocVersion) == "number"
            and tocVersion >= 16000
            and tocVersion < 20000
    end

    -- Spec Override value keys: the module folder, "\31", then the key path's
    -- segments joined by "\30" (CludesUI_SpecOverrides.lua's stored format).
    local function PowerTextKey(fieldKey)
        return fieldKey:find("^CludesUIUnitFrames\31[^\30]+\30powerTextFormat$")
            or fieldKey:find("^CludesUIUnitFrames\31[^\30]+\30foreverFormTextFormat$")
            or fieldKey == "CludesUIResourceBars\31primary\30textFormat"
            or fieldKey == "CludesUIResourceBars\31primary\30foreverDruidMana\30textFormat"
    end

    local function MoveProfile(profileTbl)
        if type(profileTbl) ~= "table" then
            return
        end
        local addonStores = type(profileTbl.addons) == "table" and profileTbl.addons
        local ufStore = addonStores and addonStores.CludesUIUnitFrames
        if type(ufStore) == "table" then
            -- Every frame's settings table (player, target, the mini frames, ...).
            for _, s in pairs(ufStore) do
                if type(s) == "table" then
                    if s.powerTextFormat == SMART then
                        s.powerTextFormat = VALUE
                    end
                    if s.foreverFormTextFormat == SMART then
                        s.foreverFormTextFormat = VALUE
                    end
                end
            end
        end
        local resourceBars = addonStores and addonStores.CludesUIResourceBars
        local pp = type(resourceBars) == "table" and resourceBars.primary
        if type(pp) == "table" then
            if pp.textFormat == SMART then
                pp.textFormat = VALUE
            end
            local fdm = pp.foreverDruidMana
            if type(fdm) == "table" and fdm.textFormat == SMART then
                fdm.textFormat = VALUE
            end
        end
        if type(profileTbl.specOverrides) ~= "table" then
            return
        end
        for _, record in pairs(profileTbl.specOverrides) do
            local valueList = type(record) == "table" and record.values
            if type(valueList) == "table" then
                for _, specBucket in pairs(valueList) do
                    if type(specBucket) == "table" then
                        for fieldKey, val in pairs(specBucket) do
                            if val == SMART and type(fieldKey) == "string" and PowerTextKey(fieldKey) then
                                specBucket[fieldKey] = VALUE
                            end
                        end
                    end
                end
            end
        end
    end

    if ClientOK() then
        CludesUI.Lite.OnSavedVariablesLoaded(function()
            if not ClientOK() then
                return
            end
            local saved = CludesUIDB
            if type(saved) ~= "table" then
                -- A brand-new account: nothing to move. Marked at login, so
                -- its own first session's choices are never overwritten.
                local frame = CreateFrame("Frame")
                frame:RegisterEvent("PLAYER_LOGIN")
                frame:SetScript("OnEvent", function(self)
                    self:UnregisterAllEvents()
                    local d = CludesUIDB
                    if type(d) == "table" then
                        if type(d._migrations) ~= "table" then
                            d._migrations = {}
                        end
                        d._migrations[FLAG] = true
                    end
                end)
                return
            end
            if type(saved._migrations) ~= "table" then
                saved._migrations = {}
            end
            if saved._migrations[FLAG] then
                return
            end
            saved._migrations[FLAG] = true
            if type(saved.profiles) == "table" then
                for _, profileTbl in pairs(saved.profiles) do
                    MoveProfile(profileTbl)
                end
            end
        end)
    end
end
