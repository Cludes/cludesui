if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_SpecOverrides_Conditional.lua
--
--  The Conditional Overrides integration (engine in
--  CludesUI_Conditions.lua), the profile-import store merge and the
--  default re-baseline.
--  Reads the earlier Spec Overrides files through CUI_NS._soInternals.
-------------------------------------------------------------------------------
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS -- standalone builds: the core's own table (CludesUI.lua)
local Inner = CUI_NS._soInternals
-- CludesUI_SpecOverrides.lua or an earlier Spec Overrides file failed to
-- load.
if not Inner or Inner.broken then return end
Inner.broken = true

local BlacklistedFKey, CurrentSpecID, DBFor = Inner.BlacklistedFKey, Inner.CurrentSpecID, Inner.DBFor
local DeepCopy, EntryOwning, FKeyLoaded = Inner.DeepCopy, Inner.EntryOwning, Inner.FKeyLoaded
local GetGroups, GetProfileRoot, GetStore = Inner.GetGroups, Inner.GetProfileRoot, Inner.GetStore
local HasRegisteredDefault, L, MatchOwnedFKey = Inner.HasRegisteredDefault, Inner.L, Inner.MatchOwnedFKey
local NIL_SENT, PROFILES_MODULE, PxCo = Inner.NIL_SENT, Inner.PROFILES_MODULE, Inner.PxCo
local ReadLive, RebuildFKeyIndex = Inner.ReadLive, Inner.RebuildFKeyIndex
local RunRefreshers, SplitFKey, WriteLive = Inner.RunRefreshers, Inner.SplitFKey, Inner.WriteLive
local BmApplyLayer, BmHarvestLayer, BmOwnerGid = Inner.BmApplyLayer, Inner.BmHarvestLayer, Inner.BmOwnerGid
local BmSessionEngage, DmApplyLayer = Inner.BmSessionEngage, Inner.DmApplyLayer
local DmHarvestLayer, DmOwnerGid = Inner.DmHarvestLayer, Inner.DmOwnerGid
local DmSessionEngage, GetBmStore = Inner.DmSessionEngage, Inner.GetBmStore
local GetCondBmStore, GetCondDmStore = Inner.GetCondBmStore, Inner.GetCondDmStore
local GetDmStore, LiteProfile = Inner.GetDmStore, Inner.LiteProfile

-- This file's copies of shared names; Set<Name> keeps every copy current
-- (the lists are built at the end of CludesUI_SpecOverrides.lua).
local _editGroup = nil
Inner.editGroupSetters[#Inner.editGroupSetters + 1] = function(val) _editGroup = val end
local _defaultView = false
Inner.defaultViewSetters[#Inner.defaultViewSetters + 1] = function(val) _defaultView = val end
local _inTransition = false
Inner.inTransitionSetters[#Inner.inTransitionSetters + 1] = function(val) _inTransition = val end
local RequestGoldWalk
Inner.goldWalkSetters[#Inner.goldWalkSetters + 1] = function(val) RequestGoldWalk = val end

-------------------------------------------------------------------------------
--  CONDITIONAL OVERRIDES integration (engine in CludesUI_Conditions.lua). Same
--  machine as spec overrides keyed by conditional GROUP instead of spec: entries
--  carry values = { default = {fkey=v}, [gid] = {fkey=v} }; "no condition active"
--  plays the role of a non-member spec (defaults write). PRECEDENCE: a SPEC-owned
--  fkey (EntryOwning) is off-limits, checked at every conditional write, so
--  later-created spec overrides evict conditional claims silently. Unlock layouts
--  ride the layer engine via the namespaced active pointer ("cond:"..gid); a spec
--  whose group has a layout ignores conditional layouts entirely (first branch of
--  layer resolution). Functions live in one table (file local budget).
-------------------------------------------------------------------------------
-- Contexts excluded from BOTH override systems: no glow overlay, no auto-capture,
-- no slot marks, entries pruned. true = whole module; table = specific pages;
-- nested table = specific sections of a page. (Declared here so both systems bind it.)
local EXCLUDED_CONTEXTS = {
    [PROFILES_MODULE] = true, -- Profiles & Presets (incl. list tab)
    ["_CUIPatchNotes"] = true, -- Patch Notes
    ["_CUILegends"] = true, -- CUI Legends
    ["_CUIGlobal"] = true, -- Global Settings (whole module)
    -- (Global Settings -> Colors stays eligible)
    -- Blacklisted modules (see FOLDER_BLACKLIST): their pages are fully
    -- outside the system, so the editing-as overlay/absorb covers them too.
    ["CludesUIBlizzardSkin"] = true,
    ["CludesUIDamageMeters"] = true,
    ["CludesUIMythicTimer"] = true,
    ["CludesUIQuestTracker"] = true,
    ["CludesUIFriends"] = true,
    ["CludesUIBags"] = true,
    ["CludesUIQoL"] = true, -- whole module
    ["CludesUIAuraBuffReminders"] = true,
    ["CludesUIForeverEssentials"] = true,
    ["CludesUIQuickdraw"] = true,
    ["CludesUILoadoutManager"] = true,
    ["CludesUIGroupFinder"] = true,
    ["CludesUISimpleLootCouncil"] = true,
    -- CDM: module eligible (bar settings override); these two tabs are
    -- spell/spec-coupled systems with their own per-spec storage.
    ["CludesUICooldownManager"] = {
        ["Bar Glows"] = true,
        ["Tracking Bars"] = true,
    },
    -- Raid Frames: HoverCast bindings live in the account-global clickCast
    -- store (never per-profile), so overrides can't apply to them.
    ["CludesUIRaidFrames"] = {
        ["HoverCast"] = true,
        ["Frame Bindings"] = true,
    },
    -- Unit Frames: Player Aura Bars is a bar-CRUD system (custom bar lists,
    -- shared filter registry, structural per-bar tables), not per-spec slot
    -- values; the whole tab stays outside overrides.
    ["CludesUIUnitFrames"] = {
        ["Player Aura Bars"] = true,
    },
}

local CondKit = {}
CUI._CondOv = CondKit

-- Condition icon art (media\icons\overrides). battleground uses the horde crest
-- art; the toolbar button rests on the dungeons icon.
CondKit.ICON_DIR = "Interface\\AddOns\\CludesUI\\media\\icons\\overrides\\"
CondKit.ICONS = {
    keybind = "override-keybinds.png",
    dungeon = "override-dungeons.png",
    raid = "override-raid.png",
    arena = "override-arena.png",
    battleground = "override-horde.png",
    solo = "override-solo.png",
    gamepad = "override-gamepad.png",
}

--- True while EITHER override editing session (spec or conditional) is live.
function CUI.SpecOverrides_EditSessionActive() return (_editGroup ~= nil) or (CondKit._edit ~= nil) end

--- Overlay policy for the Raid Frames Buff Manager page, evaluated at page build.
--- nil = no overlay (Default view / no session, or the edited group's fork is live
--- and editable WYSIWYG). Otherwise:
---   { mode = "activate"|"info", kind = "spec"|"cond", gid, text, sub }
--- "info" blocks the whole page: edits there would land in whatever layer is live
--- and bank to the WRONG owner at the next harvest.
function CUI.SpecOverrides_BmOverlayState()
    local group, kindName
    if _editGroup then
        group, kindName = _editGroup, "spec"
    elseif CondKit._edit then
        group, kindName = CondKit._edit, "cond"
    else
        return nil
    end
    local current = CurrentSpecID()
    local bmStore = GetBmStore()
    local liveKey, forked, allowed, textValue, sub
    if kindName == "spec" then
        liveKey = group.id
        forked = (bmStore and bmStore.layouts[group.id] ~= nil) or false
        local member = false
        for _, spellRef in ipairs(group.specs or {}) do
            if spellRef == current then
                member = true
                break
            end
        end
        local ownerFrame = BmOwnerGid(current)
        allowed = member and (ownerFrame == nil or ownerFrame == group.id)
        if not member then
            textValue = L(
                "This group's custom Buff Manager can only be activated or edited while playing one of its specs."
            )
        elseif not allowed then
            textValue =
                L("Another override group already provides the custom Buff Manager for your current spec.")
        end
    else
        liveKey = "cond:" .. group.id
        local condStore = GetCondBmStore()
        forked = (condStore and condStore.layouts[group.id] ~= nil) or false
        -- No real-context requirement: unlike unlock layouts these are plain
        -- settings and the session swap (BmSessionEngage) makes the fork live
        -- anywhere. Only the spec-wins precedence gate remains.
        local specOwner = BmOwnerGid(current) ~= nil
        allowed = not specOwner
        if specOwner then
            textValue = L(
                "Your current spec has its own custom Buff Manager, so conditional Buff Managers never apply to it."
            )
        end
    end
    if forked and allowed then
        -- PURE query: report a stale live pointer (fresh login ordering) via the second
        -- return; BmPagePrelude performs the heal/session engage. A session-applied
        -- fork IS the live layer even though the runtime pointer does not say so.
        local liveNow = CUI._bmSessionGid and ("cond:" .. CUI._bmSessionGid)
            or (bmStore and bmStore.active)
        return nil, liveNow ~= liveKey
    end
    if not allowed then
        return { mode = "info", kind = kindName, gid = group.id, text = textValue, sub = sub }
    end
    return {
        mode = "activate",
        kind = kindName,
        gid = group.id,
        text = kindName == "spec"
                and L(
                    "This will create a fully unique Buff Manager for this override group. Changes made to your default Buff Manager will no longer affect these specs."
                )
            or L(
                "This will create a fully unique Buff Manager for this conditional group. Changes made to your default Buff Manager will no longer affect it."
            ),
    }
end

--- Starting points offered by the create popup, in menu order: the main
--- (baseline) Buff Manager, every other override that already has its own
--- Buff Manager, then the two presets. Returns values, order for a dropdown.
--- Keys: "main" | "spec:<gid>" | "cond:<gid>" | "default" | "empty".
function CUI.SpecOverrides_BmSeedSources(kindName, groupId)
    local values, sequence = {}, {}
    local function Add(key, labelText)
        values[key] = labelText
        sequence[#sequence + 1] = key
    end
    Add("main", L("Copy from main Buff Manager"))
    local bmStore = GetBmStore()
    if bmStore and bmStore.layouts then
        for _, group in ipairs(GetGroups() or {}) do
            if bmStore.layouts[group.id] ~= nil and not (kindName == "spec" and group.id == groupId) then
                Add("spec:" .. group.id, CUI.Lf("Copy from %1$s Buff Manager", group.name or "?"))
            end
        end
    end
    local condStore = GetCondBmStore()
    if condStore and condStore.layouts and CUI.Conditions_GetGroups then
        for _, group in ipairs(CUI.Conditions_GetGroups() or {}) do
            if condStore.layouts[group.id] ~= nil and not (kindName == "cond" and group.id == groupId) then
                Add("cond:" .. group.id, CUI.Lf("Copy from %1$s Buff Manager", group.name or "?"))
            end
        end
    end
    Add("default", L("Default Preset"))
    Add("empty", L("Empty Preset"))
    return values, sequence
end

--- READ-ONLY: the override groups with their own Buff Manager (kind "bm") or
--- Debuff Manager ("dm"): spec group ids, then condition group ids, each list
--- in creation order.
function CUI.SpecOverrides_ManagerForkOwners(kindName)
    local bmStore, condStore
    if kindName == "dm" then
        bmStore, condStore = GetDmStore(), GetCondDmStore()
    else
        bmStore, condStore = GetBmStore(), GetCondBmStore()
    end
    local specInfo, cond = {}, {}
    if bmStore and bmStore.layouts then
        for _, group in ipairs(GetGroups() or {}) do
            if bmStore.layouts[group.id] ~= nil then specInfo[#specInfo + 1] = group.id end
        end
    end
    if condStore and condStore.layouts then
        for _, group in ipairs(CUI.Conditions_GetGroups() or {}) do
            if condStore.layouts[group.id] ~= nil then cond[#cond + 1] = group.id end
        end
    end
    return specInfo, cond
end

--- Page-build entry point for the RF Buff Manager page: call FIRST, before any
--- content builds. Heals a stale live layer (so the page renders the edited
--- group's fork; the heal skips the page repaint because THIS build is the
--- repaint) and returns the overlay state (nil = no overlay).
function CUI.SpecOverrides_BmPagePrelude()
    -- Outside any session: ensure the runtime layer the page is about to edit is
    -- actually LIVE. A spec owning a BM fork gets it auto-activated here; a stale
    -- pointer (login ordering, interrupted session) heals instead of letting the
    -- page edit an off-screen layer ("changing settings does nothing" with no error).
    if not _editGroup and not CondKit._edit then
        CUI.SpecOverrides_ApplyBm(CurrentSpecID(), false, true)
    end
    -- Editing-as-conditional with an existing fork that is not the runtime layer
    -- (condition not met right now): engage the session swap so the page and
    -- on-screen frames show the fork being edited. Spec-wins gate still blocks
    -- when a spec owner exists.
    if CondKit._edit then
        local condStore = GetCondBmStore()
        if
            condStore
            and condStore.layouts[CondKit._edit.id]
            and CUI._bmSessionGid ~= CondKit._edit.id
            and not BmOwnerGid(CurrentSpecID())
        then
            local bmStore = GetBmStore()
            if not (bmStore and bmStore.active == ("cond:" .. CondKit._edit.id)) then
                BmSessionEngage(CondKit._edit.id)
            end
        end
    end
    local status, needHeal = CUI.SpecOverrides_BmOverlayState()
    if needHeal then CUI.SpecOverrides_ApplyBm(CurrentSpecID(), true, true) end
    -- Re-evaluate passive chrome on EVERY BM page build: fork deletion,
    -- activation, and heals all rebuild this page without a SelectPage.
    if CUI.SpecOverrides_UpdateBmPassiveChrome then CUI.SpecOverrides_UpdateBmPassiveChrome() end
    return status
end

--- Creates the edited group's BM fork (the overlay's create popup). Re-validates
--- every gate (race guard), banks live into its current owner, then seeds from
--- `source` (SpecOverrides_BmSeedSources key; nil/"main" = the main Buff
--- Manager): spec forks born while a conditional BM layer is live seed from the
--- BASELINE (spec layers void conditionals -- never fork a dungeon state);
--- otherwise from live. Other overrides and the two presets seed a fresh layer,
--- which must then be PAINTED when the new fork becomes the live one (the main
--- copy is already what is on screen).
function CUI.SpecOverrides_ActivateBm(kindName, groupId, source)
    local status = CUI.SpecOverrides_BmOverlayState()
    if not status or status.mode ~= "activate" or status.kind ~= kindName or status.gid ~= groupId then
        return
    end
    -- Source key -> fresh layer table; nil = "main" (seeded below as before).
    local function SeedLayerFor(src)
        if not src or src == "main" then return nil end
        if src == "default" or src == "empty" then
            local rf = LiteProfile("CludesUIRaidFrames")
            return {
                indicators = {},
                simple = {},
                displayMode = "custom",
                iconZoom = (rf and rf.bmIconZoom) or 0.08,
                bm2 = _G._CURF_BM2PresetFork and _G._CURF_BM2PresetFork(src) or { specs = {}, seeded = {} },
            }
        end
        local sgid = tonumber(src:match("^spec:(%d+)$"))
        if sgid then
            local bmStore = GetBmStore()
            local layer = bmStore and bmStore.layouts and bmStore.layouts[sgid]
            return layer and DeepCopy(layer) or nil
        end
        local cgid = tonumber(src:match("^cond:(%d+)$"))
        if cgid then
            local condStore = GetCondBmStore()
            local layer = condStore and condStore.layouts and condStore.layouts[cgid]
            return layer and DeepCopy(layer) or nil
        end
        return nil
    end
    local seeded = SeedLayerFor(source)
    local current = CurrentSpecID()
    CUI.SpecOverrides_HarvestBmLayout()
    -- Virgin-store baseline seed: the first-ever BM layer must capture the
    -- shared baseline from the pre-fork live state (live IS the baseline when
    -- no layer is active), or leaving the fork later has nothing to restore and
    -- the next harvest adopts the fork's edits as the default Buff Manager.
    do
        local bmStore = GetBmStore(true)
        if bmStore and not bmStore.baselineLayout and not bmStore.active then
            bmStore.baselineLayout = BmHarvestLayer()
        end
    end
    if kindName == "spec" then
        local bmStore = GetBmStore(true)
        if not bmStore or bmStore.layouts[groupId] ~= nil then return end
        local fromCond = type(bmStore.active) == "string"
        -- Live differs from the new layer when it was seeded from anything but
        -- the main copy of what is on screen -> paint on activation.
        local needPaint = seeded ~= nil or fromCond
        if seeded then
            bmStore.layouts[groupId] = seeded
        elseif fromCond and bmStore.baselineLayout then
            bmStore.layouts[groupId] = DeepCopy(bmStore.baselineLayout)
        else
            local snapshot = BmHarvestLayer()
            if not snapshot then return end
            bmStore.layouts[groupId] = snapshot
        end
        if BmOwnerGid(current) == groupId then
            bmStore.active = groupId
            -- WoW Forever: the new fork serves the current spec's bucket;
            -- published before the paint below, or re-driven with no paint
            -- (RefreshPage below rebuilds the page).
            if CUI.IS_FOREVER then
                local fvPrev = CUI._SO_SetForkSpec(false, groupId, current)
                if not needPaint and fvPrev ~= CUI.SpecOverrides_BmForkSpecID then
                    CUI._SO_ForkReDrive(false, true)
                end
            end
            -- Baseline-seeded fork while a conditional was live (the
            -- conditional ceased to exist for this spec), or a preset/other-
            -- override seed: swap the screen to the new layer. RefreshPage
            -- below is the repaint.
            if needPaint then BmApplyLayer(bmStore.layouts[groupId], true) end
        end
    else
        local condStore = GetCondBmStore(true)
        if not condStore or condStore.layouts[groupId] ~= nil then return end
        local bmStore = GetBmStore(true)
        -- Seed from the BASELINE when any layer is live (another conditional
        -- applied right now); live IS the baseline only when nothing is.
        local snapshot = seeded
        if not snapshot then
            if bmStore and bmStore.active and bmStore.baselineLayout then
                snapshot = DeepCopy(bmStore.baselineLayout)
            else
                snapshot = BmHarvestLayer()
                if not snapshot then return end
            end
        end
        condStore.layouts[groupId] = snapshot
        local ag = CUI.Conditions_ActiveGroup and CUI.Conditions_ActiveGroup()
        if ag and ag.id == groupId then
            -- In-context creation: the fork is the runtime layer from here. A
            -- non-main seed differs from what is on screen -> paint it.
            if bmStore then bmStore.active = "cond:" .. groupId end
            if seeded then BmApplyLayer(snapshot, true) end
        else
            -- Out-of-context creation: session-scoped apply only. The runtime
            -- pointer must never point at a layer whose condition is not met.
            BmSessionEngage(groupId)
        end
    end
    CUI:RefreshPage(true)
end

--- Overlay policy for the Debuff Manager page (mirror of BmOverlayState;
--- same eligibility rules and returns).
function CUI.SpecOverrides_DmOverlayState()
    local group, kindName
    if _editGroup then
        group, kindName = _editGroup, "spec"
    elseif CondKit._edit then
        group, kindName = CondKit._edit, "cond"
    else
        return nil
    end
    local current = CurrentSpecID()
    local bmStore = GetDmStore()
    local liveKey, forked, allowed, textValue, sub
    if kindName == "spec" then
        liveKey = group.id
        forked = (bmStore and bmStore.layouts[group.id] ~= nil) or false
        local member = false
        for _, spellRef in ipairs(group.specs or {}) do
            if spellRef == current then
                member = true
                break
            end
        end
        local ownerFrame = DmOwnerGid(current)
        allowed = member and (ownerFrame == nil or ownerFrame == group.id)
        if not member then
            textValue = L(
                "This group's custom Debuff Manager can only be activated or edited while playing one of its specs."
            )
        elseif not allowed then
            textValue =
                L("Another override group already provides the custom Debuff Manager for your current spec.")
        end
    else
        liveKey = "cond:" .. group.id
        local condStore = GetCondDmStore()
        forked = (condStore and condStore.layouts[group.id] ~= nil) or false
        local specOwner = DmOwnerGid(current) ~= nil
        allowed = not specOwner
        if specOwner then
            textValue = L(
                "Your current spec has its own custom Debuff Manager, so conditional Debuff Managers never apply to it."
            )
        end
    end
    if forked and allowed then
        local liveNow = CUI._dmSessionGid and ("cond:" .. CUI._dmSessionGid)
            or (bmStore and bmStore.active)
        return nil, liveNow ~= liveKey
    end
    if not allowed then
        return { mode = "info", kind = kindName, gid = group.id, text = textValue, sub = sub }
    end
    return {
        mode = "activate",
        kind = kindName,
        gid = group.id,
        text = kindName == "spec"
                and L(
                    "This will create a fully unique Debuff Manager for this override group. Your current Debuff Manager settings are copied as its starting point, and changes made to your default Debuff Manager will no longer affect these specs."
                )
            or L(
                "This will create a fully unique Debuff Manager for this conditional group. Your current Debuff Manager settings are copied as its starting point, and changes made to your default Debuff Manager will no longer affect it."
            ),
    }
end

--- Page-build entry point for the Debuff Manager page (mirror of
--- BmPagePrelude): call FIRST, before any content builds.
function CUI.SpecOverrides_DmPagePrelude()
    if not _editGroup and not CondKit._edit then
        CUI.SpecOverrides_ApplyDm(CurrentSpecID(), false, true)
    end
    if CondKit._edit then
        local condStore = GetCondDmStore()
        if
            condStore
            and condStore.layouts[CondKit._edit.id]
            and CUI._dmSessionGid ~= CondKit._edit.id
            and not DmOwnerGid(CurrentSpecID())
        then
            local bmStore = GetDmStore()
            if not (bmStore and bmStore.active == ("cond:" .. CondKit._edit.id)) then
                DmSessionEngage(CondKit._edit.id)
            end
        end
    end
    local status, needHeal = CUI.SpecOverrides_DmOverlayState()
    if needHeal then CUI.SpecOverrides_ApplyDm(CurrentSpecID(), true, true) end
    if CUI.SpecOverrides_UpdateBmPassiveChrome then CUI.SpecOverrides_UpdateBmPassiveChrome() end
    return status
end

--- Creates the edited group's DM fork (mirror of SpecOverrides_ActivateBm,
--- including the virgin-store baseline seed and conditional seeding rules).
function CUI.SpecOverrides_ActivateDm(kindName, groupId)
    local status = CUI.SpecOverrides_DmOverlayState()
    if not status or status.mode ~= "activate" or status.kind ~= kindName or status.gid ~= groupId then
        return
    end
    local current = CurrentSpecID()
    CUI.SpecOverrides_HarvestDmLayout()
    do
        local bmStore = GetDmStore(true)
        if bmStore and not bmStore.baselineLayout and not bmStore.active then
            bmStore.baselineLayout = DmHarvestLayer()
        end
    end
    if kindName == "spec" then
        local bmStore = GetDmStore(true)
        if not bmStore or bmStore.layouts[groupId] ~= nil then return end
        local fromCond = type(bmStore.active) == "string"
        if fromCond and bmStore.baselineLayout then
            bmStore.layouts[groupId] = DeepCopy(bmStore.baselineLayout)
        else
            local snapshot = DmHarvestLayer()
            if not snapshot then return end
            bmStore.layouts[groupId] = snapshot
        end
        if DmOwnerGid(current) == groupId then
            bmStore.active = groupId
            -- WoW Forever: the new fork serves the current spec's bucket
            -- (see SpecOverrides_ActivateBm).
            if CUI.IS_FOREVER then
                local fvPrev = CUI._SO_SetForkSpec(true, groupId, current)
                if not fromCond and fvPrev ~= CUI.SpecOverrides_DmForkSpecID then
                    CUI._SO_ForkReDrive(true, true)
                end
            end
            if fromCond then DmApplyLayer(bmStore.layouts[groupId], true) end
        end
    else
        local condStore = GetCondDmStore(true)
        if not condStore or condStore.layouts[groupId] ~= nil then return end
        local bmStore = GetDmStore(true)
        local snapshot
        if bmStore and bmStore.active and bmStore.baselineLayout then
            snapshot = DeepCopy(bmStore.baselineLayout)
        else
            snapshot = DmHarvestLayer()
            if not snapshot then return end
        end
        condStore.layouts[groupId] = snapshot
        local ag = CUI.Conditions_ActiveGroup and CUI.Conditions_ActiveGroup()
        if ag and ag.id == groupId then
            if bmStore then bmStore.active = "cond:" .. groupId end
        else
            DmSessionEngage(groupId)
        end
    end
    CUI:RefreshPage(true)
end

--- True for module folders excluded wholesale from the override systems (drives
--- the sidebar lock during an editing session). Includes the management
--- surfaces (Profiles & Presets, Patch Notes, Global Settings): they lock like
--- every other excluded module. Plugin pages ("plugin:" keys) are never part of
--- the override systems, so they are always excluded.
-- Block-scoped: keeps ns out of the main chunk's locals (Lua 5.1 allows ~200).
do
    local _, mod = ...
    mod = mod.__cuiCoreNS or mod -- standalone builds: the core's own table (CludesUI.lua)

    function CUI.SpecOverrides_ModuleExcluded(moduleFolder)
        return (type(moduleFolder) == "string" and EXCLUDED_CONTEXTS[moduleFolder] == true)
            or mod.IsPluginKey(moduleFolder)
    end

    --- True when a module page is excluded (page-scoped entry, or the whole
    --- module). Drives the page-tab lock while a session is active.
    function CUI.SpecOverrides_PageExcluded(module, page)
        if mod.IsPluginKey(module) then return true end
        local ex = module and EXCLUDED_CONTEXTS[module]
        if ex == true then return true end
        if type(ex) == "table" and page then return ex[page] == true end
        return false
    end
end

function CondKit.GetStore(create)
    local profileTbl = GetProfileRoot()
    if not profileTbl then return nil end
    if not profileTbl.condOverrides then
        if not create then return nil end
        profileTbl.condOverrides = {}
    end
    return profileTbl.condOverrides
end

function CondKit.GetUnlockStore(create)
    local profileTbl = GetProfileRoot()
    if not profileTbl then return nil end
    local bmStore = profileTbl.condUnlockOverrides
    if not bmStore then
        if not create then return nil end
        bmStore = {}
        profileTbl.condUnlockOverrides = bmStore
    end
    bmStore.layouts = bmStore.layouts or {}
    return bmStore
end

-- fkey -> entry index over the conditional store (parallel to _fkeyIndex,
-- never merged into it: EntryOwning stays spec-only by definition).
CondKit._fkeyIndex = nil
function CondKit.RebuildIndex()
    CondKit._fkeyIndex = {}
    for _, record in ipairs(CondKit.GetStore() or {}) do
        if record.values and record.values.default then
            for fieldKey in pairs(record.values.default) do
                CondKit._fkeyIndex[fieldKey] = record
            end
        end
    end
end
function CondKit.EntryOwning(fieldKey)
    if not CondKit._fkeyIndex then CondKit.RebuildIndex() end
    return CondKit._fkeyIndex[fieldKey]
end

--- Writes the effective conditional values for the given active group (nil = no
--- condition: defaults). Mirrors WriteSpecValues plus the spec-wins gate.
--- forSession: painting an EDITING session's view (conditional-over-default),
--- where the conditional's own values must show even for fkeys the SPEC store
--- also tracks. Runtime applies (transitions, overlays, restores) omit it --
--- spec overrides always win at apply time.
function CondKit.WriteValues(groupId, forSession)
    local storage = CondKit.GetStore()
    if not storage or #storage == 0 then return nil end
    PxCo.Pair(storage, true)
    local touched = nil
    for _, record in ipairs(storage) do
        local map = groupId and record.values[groupId] or nil
        for fieldKey, groupDef in pairs(record.values.default) do
            if
                not BlacklistedFKey(fieldKey)
                and not MatchOwnedFKey(fieldKey)
                and (forSession or not EntryOwning(fieldKey))
            then
                local val = groupDef
                if map and map[fieldKey] ~= nil then val = map[fieldKey] end
                if val == NIL_SENT then val = nil end
                -- Same defaults-backed nil-poison skip as WriteSpecValues.
                local nilPoison = (val == nil) and HasRegisteredDefault(fieldKey)
                local current = ReadLive(fieldKey)
                -- Table values are never written or compared: a stored table
                -- reference NEVER equals live, so it would register a "write"
                -- and force a full module refresh on EVERY transition.
                if not nilPoison and type(val) ~= "table" and type(current) ~= "table" and current ~= val then
                    if WriteLive(fieldKey, val) then
                        local moduleFolder = SplitFKey(fieldKey)
                        if moduleFolder then
                            touched = touched or {}
                            touched[moduleFolder] = true
                        end
                    end
                end
            end
        end
    end
    return touched
end

--- Writes an entry's recorded DEFAULT values back to live. Called right BEFORE a
--- conditional entry is removed: a conditional's values sit in live for as long as
--- its condition holds, including while the options panel is open (the Default
--- Editing Mode swap covers the SPEC store only), so dropping the entry without
--- this would silently turn the override's values into the profile's own
--- settings. The spec delete flow needs no equivalent (live already holds the
--- shared defaults there); its one path that CAN hit this, the orphan drop in
--- PruneOrphanEntries, carries the same restore. Guards mirror Cond.WriteValues
--- exactly, so this only writes keys the conditional overlay could have written
--- (blacklisted/match-owned/SPEC-owned/unloaded-module skipped; NIL_SENT on a
--- defaults-backed key is harvest residue, not a real removal).
--- touched: folder-set accumulator; the caller refreshes once.
function CondKit.RestoreEntryDefaults(record, touched)
    local groupDef = record.values and record.values.default
    if not groupDef then return end
    for fieldKey, dv in pairs(groupDef) do
        if
            not BlacklistedFKey(fieldKey)
            and not MatchOwnedFKey(fieldKey)
            and not EntryOwning(fieldKey)
            and FKeyLoaded(fieldKey)
        then
            local val = dv
            if val == NIL_SENT then val = nil end
            local nilPoison = (val == nil) and HasRegisteredDefault(fieldKey)
            local current = ReadLive(fieldKey)
            if not nilPoison and type(val) ~= "table" and type(current) ~= "table" and current ~= val then
                if WriteLive(fieldKey, val) then
                    local moduleFolder = SplitFKey(fieldKey)
                    if moduleFolder then touched[moduleFolder] = true end
                end
            end
        end
    end
end

--- Garbage-collects conditional fkeys no group map holds a value for (the
--- diff-semantics harvests clear reverts at bank time), and entries left empty.
--- NEVER judges by equality against the default: the default is movable, and
--- equality-pruning against a moved/poisoned default silently deletes
--- intentional override values.
function CondKit.PruneRedundant()
    local storage = CondKit.GetStore()
    if not storage then return end
    local changed = false
    for idx = #storage, 1, -1 do
        local record = storage[idx]
        local groupDef = record.values and record.values.default
        if groupDef then
            for fieldKey in pairs(groupDef) do
                local held = false
                for key, m in pairs(record.values) do
                    if key ~= "default" and type(m) == "table" and m[fieldKey] ~= nil then
                        held = true
                        break
                    end
                end
                if not held then
                    -- An exact-size companion stays while its size key does (PxCo).
                    local base = fieldKey:sub(-2) == "Px" and fieldKey:sub(1, -3) or nil
                    if base and groupDef[base] ~= nil and PxCo.Partner(base) == fieldKey then held = true end
                end
                if not held then
                    groupDef[fieldKey] = nil
                    changed = true
                end
            end
            if not next(groupDef) then
                table.remove(storage, idx)
                changed = true
            end
        end
    end
    if changed then
        CondKit.RebuildIndex()
        RequestGoldWalk()
    end
end

--- Banks live values into the given group's maps (nil = the default maps) for
--- every fkey the conditional store tracks. Mirrors the spec Harvest. Group
--- maps use diff semantics (bank when live differs from the recorded default,
--- clear when it matches) so a transition harvest never seeds default-equal
--- junk maps onto entries the group never customized; the default maps
--- themselves always track live verbatim.
function CondKit.Harvest(groupId)
    local storage = CondKit.GetStore()
    if not storage or #storage == 0 then return end
    -- Defaults may only rebank over CANONICAL live data: while any editing session or
    -- the Default view holds swapped values, banking poisons the recorded defaults.
    -- (HarvestCurrent orders its call after the canonical restore; this is the belt
    -- for any other caller.)
    local sessionLive = _defaultView or _editGroup or CondKit._edit
    -- SPEC-OWNED fkeys are never harvested in either direction: while the spec store
    -- tracks an fkey, live reflects SPEC values (runtime applies skip it), so banking
    -- live here would poison the conditional's default/group maps with spec-scoped
    -- values; Cond values stay dormant until the spec override is removed. TABLE-typed
    -- live values are never banked either (structure change; mirror of HarvestMap --
    -- would alias store to profile).
    for _, record in ipairs(storage) do
        if groupId then
            local map = record.values[groupId]
            for fieldKey, dv in pairs(record.values.default) do
                -- FKeyLoaded: a disabled module reads nil for every path, which would
                -- poison the maps with deletion markers. MatchOwnedFKey: match-engine
                -- writes never bank (mirrors spec-side Harvest; Cond.WriteValues skips
                -- these at apply time).
                if not EntryOwning(fieldKey) and FKeyLoaded(fieldKey) and not MatchOwnedFKey(fieldKey) then
                    local liveValue = ReadLive(fieldKey)
                    if type(liveValue) ~= "table" then
                        local defVal = dv
                        if defVal == NIL_SENT then defVal = nil end
                        if liveValue == defVal then
                            -- Equality is NOT proof of a revert outside an edit session
                            -- (the default may have been edited onto the group's
                            -- value): retain the held value. Real reverts clear in
                            -- Cond.HarvestEdit, which has the session snapshot to prove them.
                        else
                            if not map then
                                map = {}
                                record.values[groupId] = map
                            end
                            map[fieldKey] = (liveValue == nil) and NIL_SENT or liveValue
                        end
                    end
                end
            end
            if map and not next(map) then record.values[groupId] = nil end
        elseif not sessionLive then
            local map = record.values.default
            for fieldKey in pairs(map) do
                if not EntryOwning(fieldKey) and FKeyLoaded(fieldKey) and not MatchOwnedFKey(fieldKey) then
                    local liveValue = ReadLive(fieldKey)
                    if type(liveValue) ~= "table" then
                        map[fieldKey] = liveValue == nil and NIL_SENT or liveValue
                    end
                end
            end
        end
    end
    CondKit.PruneRedundant()
end

--- Values-only overlay for profile-apply paths (RefreshAllAddons): re-paints
--- the applied conditional group's values after spec values. While an
--- editing-as-conditional session holds swapped values live, generic re-applies
--- must preserve the session's view instead.
function CondKit.ApplyValues()
    local groupId
    if CondKit._edit then
        groupId = CondKit._edit.id
    else
        groupId = CUI.Conditions_AppliedGid and CUI.Conditions_AppliedGid()
    end
    -- forSession while a session is open: without it the spec-wins gate skips
    -- spec-owned fkeys and the session view is never repainted over whatever a
    -- generic re-apply just wrote there. Returns the touched folder set so
    -- callers outside RefreshAllAddons (the FlushUnlock value overlay) can
    -- refresh what actually changed.
    return CondKit.WriteValues(groupId, CondKit._edit ~= nil)
end

-------------------------------------------------------------------------------
--  Profile-import store merge + default re-baseline
-------------------------------------------------------------------------------

--- RETIRED, no callers: ImportProfile uses ALL-OR-NOTHING override semantics (take
--- the exporter's complete override system or keep the recipient's; see the Include
--- Overrides controls). Reference only -- do NOT re-wire: the partition/union/remap
--- machinery here is the bug surface that redesign deliberately eliminated.
--- Merged PER-MODULE into a deep copy of the CURRENT profile: overrides ride with
--- their addon and fully replace every imported module; non-imported modules keep
--- the recipient's untouched.
---   * value entries (spec + cond): partitioned by each fkey's addon FOLDER. Imported
---     folders: recipient entries shed those fkeys (entry dropped when emptied),
---     incoming entries come in verbatim. Non-imported: recipient survives, incoming
---     discarded. Defaults are consistent by construction (one exporter); the
---     ApplyProfileData re-bank (SpecOverrides_RebaselineDefaults) covers strings
---     exported while an override was applied.
---   * groups: recipient groups untouched; incoming groups come along ONLY when
---     something surviving the partition references them, so a subset import can't
---     fill the dropdown with do-nothing groups. Ids re-number on collision with
---     every reference remapped (entry group fields, per-gid value maps, fork
---     layout keys, active pointers).
---   * unlock layout forks: whole-layout snapshots spanning ALL modules, so they
---     can't ride per-module. Full import: recipient's dropped, incoming's taken
---     when carried. Partial/subset (incoming.partialImport, stamped by the import
---     dialog on deselection AND by ExportProfile on subset exports) and
---     incoming.layoutExcluded ("Include layout" OFF at either end): recipient's
---     KEPT, incoming's never taken -- stripped-nil must never read as "exporter
---     had none, wipe yours".
---   * Buff Manager forks: Raid Frames data, so per-module -- replaced (or cleared)
---     when RF is imported, kept when it is not.
function CUI.SpecOverrides_MergeImportedStores(combined, pulled)
    local function maxNumericId(groups)
        local m = 0
        for _, group in ipairs(groups or {}) do
            if type(group.id) == "number" and group.id > m then m = group.id end
        end
        return m
    end

    -- Equivalence comparators: importing your OWN export must collapse each incoming
    -- group onto the recipient's original instead of appending a re-numbered twin
    -- (else the original survives as a dead card while the twin holds the values).
    local function sameSpecGroup(a, b)
        if (a.name or "") ~= (b.name or "") then return false end
        local as, bs = a.specs or {}, b.specs or {}
        if #as ~= #bs then return false end
        local set = {}
        for _, ident in ipairs(as) do
            set[ident] = true
        end
        for _, ident in ipairs(bs) do
            if not set[ident] then return false end
        end
        return true
    end
    local function sameCondGroup(a, b)
        if (a.name or "") ~= (b.name or "") then return false end
        if (a.key or "") ~= (b.key or "") then return false end
        local ac, bc = a.conds or {}, b.conds or {}
        for key in pairs(ac) do
            if not bc[key] then return false end
        end
        for key in pairs(bc) do
            if not ac[key] then return false end
        end
        return true
    end

    -- Union group lists; returns (unioned, remap oldIncomingId -> newId). An
    -- incoming group EQUIVALENT to an existing one (per `same`) adopts the
    -- existing group's id (remapped) and pushes its icon (incoming priority);
    -- only genuinely new groups append, re-numbered on id collision.
    local function unionGroups(existing, incomingGroups, same)
        local keyMap = {}
        if type(incomingGroups) ~= "table" then return existing, keyMap end
        local result, used = {}, {}
        for _, group in ipairs(existing or {}) do
            result[#result + 1] = group
            if type(group.id) == "number" then used[group.id] = true end
        end
        local nextId = maxNumericId(existing)
        local incMax = maxNumericId(incomingGroups)
        if incMax > nextId then nextId = incMax end
        -- Each existing group may be matched by ONE incoming group per union: users can
        -- hold two groups with identical name+specs/conds, and both twins matching the
        -- same target would collide their remapped gid references (pairs-order data
        -- loss in cond value maps / fork keys). Claimed-once collapses twin pairs onto
        -- their own originals; an unmatched extra falls through to the append path.
        local claimed = {}
        for _, group in ipairs(incomingGroups) do
            local match
            if same then
                for _, eg in ipairs(existing or {}) do
                    if not claimed[eg] and same(eg, group) then
                        match = eg
                        break
                    end
                end
            end
            if match then
                claimed[match] = true
                if group.id ~= match.id then keyMap[group.id] = match.id end
                -- Type guard: a corrupt/hand-edited string with a non-table
                -- icon must not abort the whole import inside DeepCopy.
                if type(group.icon) == "table" then match.icon = DeepCopy(group.icon) end
            else
                local ng = DeepCopy(group)
                if type(ng.id) == "number" and used[ng.id] then
                    nextId = nextId + 1
                    keyMap[group.id] = nextId
                    ng.id = nextId
                end
                if type(ng.id) == "number" then used[ng.id] = true end
                result[#result + 1] = ng
            end
        end
        return result, keyMap, nextId
    end

    -- Imported-folder set: the per-module partition key for value entries.
    local importedFolders = {}
    if type(pulled.addons) == "table" then
        for moduleFolder in pairs(pulled.addons) do
            importedFolders[moduleFolder] = true
        end
    end
    -- Stamped by the import dialog when any module checkbox was deselected.
    local partial = pulled.partialImport == true

    -- Per-module entry partition: strip fkeys of the given polarity from an entry
    -- list. keepImported=false keeps only NON-imported-folder fkeys (recipient side,
    -- filtered in place -- merged is already a deep copy); true keeps only
    -- imported-folder fkeys (incoming side, deep-copied). Entries emptied by the
    -- strip are dropped. Partition is per-FKEY (via SplitFKey), not per
    -- entry.module: the fkey's folder decides which addon a setting rides with.
    local function partitionEntries(entries, keepImported)
        local result = {}
        for _, record in ipairs(entries or {}) do
            local ne = keepImported and DeepCopy(record) or record
            local groupDef = ne.values and ne.values.default
            if groupDef then
                for fieldKey in pairs(groupDef) do
                    local moduleFolder = SplitFKey(fieldKey)
                    local isImported = moduleFolder and importedFolders[moduleFolder] or false
                    if isImported ~= keepImported then
                        groupDef[fieldKey] = nil
                        for key, m in pairs(ne.values) do
                            if key ~= "default" and type(m) == "table" then m[fieldKey] = nil end
                        end
                    end
                end
                if next(groupDef) ~= nil then result[#result + 1] = ne end
            end
        end
        return result
    end

    -- Re-keys a cond entry's per-gid value maps after the group union.
    local function remapEntryValues(record, keyMap)
        if not next(keyMap) or type(record.values) ~= "table" then return end
        local nv = {}
        for key, m in pairs(record.values) do
            if key ~= "default" and keyMap[key] then
                nv[keyMap[key]] = m
            else
                nv[key] = m
            end
        end
        record.values = nv
    end

    local function remapKeys(map, keyMap)
        if type(map) ~= "table" or not next(keyMap) then return map end
        local result = {}
        for key, val in pairs(map) do
            result[keyMap[key] or key] = val
        end
        return result
    end

    local function remapActive(isActive, sRemap, cRemap)
        if type(isActive) == "number" then return sRemap[isActive] or isActive end
        if type(isActive) == "string" then
            local cg = tonumber(isActive:match("^cond:(%d+)$"))
            if cg and cRemap[cg] then return "cond:" .. cRemap[cg] end
        end
        return isActive
    end

    -- Partition both stores' entries per module: recipient keeps only
    -- non-imported folders, incoming contributes only imported folders. Runs
    -- even when the string carries no entries (an imported module with no
    -- incoming overrides clears the recipient's for it -- replaced wholesale).
    local keptSpec = partitionEntries(combined.specOverrides, false)
    local incSpec = partitionEntries(pulled.specOverrides, true)
    local keptCond = partitionEntries(combined.condOverrides, false)
    local incCond = partitionEntries(pulled.condOverrides, true)

    -- Only incoming GROUPS that still carry something come along: taken when a
    -- SURVIVING incoming entry references it, or an incoming fork passing its gate
    -- below does -- a subset import of one module must not populate the dropdown with
    -- the exporter's unrelated groups as dead cards. Recipient groups are never touched.
    local rfImported = importedFolders["CludesUIRaidFrames"] and true or false
    -- layoutExcluded (stamped by ExportProfile / the import dialog when
    -- "Include layout" is OFF): layout was deliberately excluded, so the fork
    -- stores must be KEPT from the base copy -- taking the branch below with
    -- nil incoming tables would wipe the recipient's group layouts.
    local takeUnlockForks = not partial and pulled.layoutExcluded ~= true
    local specNeeded, needsCond = {}, {}
    for _, record in ipairs(incSpec) do
        if record.group ~= nil then specNeeded[record.group] = true end
    end
    for _, record in ipairs(incCond) do
        if record.group ~= nil then needsCond[record.group] = true end
        if type(record.values) == "table" then
            for key in pairs(record.values) do
                if key ~= "default" then needsCond[key] = true end
            end
        end
    end
    -- Forks reference groups via layout keys and active pointers (a spec
    -- store's active can point at a COND group via "cond:N").
    local function noteForkGids(storage, needed, condNeededToo)
        if type(storage) ~= "table" then return end
        for groupId in pairs(storage.layouts or {}) do
            needed[groupId] = true
        end
        for groupId in pairs(storage.groups or {}) do
            needed[groupId] = true
        end -- legacy shape
        local a = storage.active
        if type(a) == "number" then needed[a] = true end
        if condNeededToo and type(a) == "string" then
            local cg = tonumber(a:match("^cond:(%d+)$"))
            if cg then condNeededToo[cg] = true end
        end
    end
    if takeUnlockForks then
        noteForkGids(pulled.specUnlockOverrides, specNeeded, needsCond)
        noteForkGids(pulled.condUnlockOverrides, needsCond)
    end
    if rfImported then
        noteForkGids(pulled.specBmOverrides, specNeeded, needsCond)
        noteForkGids(pulled.condBmOverrides, needsCond)
        noteForkGids(pulled.specDmOverrides, specNeeded, needsCond)
        noteForkGids(pulled.condDmOverrides, needsCond)
    end

    local function filterGroups(groups, needed)
        local result = {}
        for _, group in ipairs(groups or {}) do
            if group.id ~= nil and needed[group.id] then result[#result + 1] = group end
        end
        return result
    end

    -- Group unions (referenced incoming groups only) + id remaps.
    local specMap, condMap = {}, {}
    if pulled.specOverrideGroups then
        local wanted = filterGroups(pulled.specOverrideGroups, specNeeded)
        if #wanted > 0 then
            local unioned, keyMap, nextId = unionGroups(combined.specOverrideGroups, wanted, sameSpecGroup)
            combined.specOverrideGroups = unioned
            specMap = keyMap
            combined.specOverrideNextId =
                math.max(combined.specOverrideNextId or 0, pulled.specOverrideNextId or 0, nextId or 0)
        end
    end
    if pulled.condOverrideGroups then
        local wanted = filterGroups(pulled.condOverrideGroups, needsCond)
        if #wanted > 0 then
            local unioned, keyMap = unionGroups(combined.condOverrideGroups, wanted, sameCondGroup)
            combined.condOverrideGroups = unioned
            condMap = keyMap
        end
    end

    -- Apply the remaps to the surviving incoming entries, then concatenate
    -- with the recipient's kept entries.
    for _, record in ipairs(incSpec) do
        if record.group and specMap[record.group] then record.group = specMap[record.group] end
        keptSpec[#keptSpec + 1] = record
    end
    for _, record in ipairs(incCond) do
        if record.group and condMap[record.group] then record.group = condMap[record.group] end
        remapEntryValues(record, condMap)
        keptCond[#keptCond + 1] = record
    end
    combined.specOverrides = keptSpec
    combined.condOverrides = keptCond

    -- Unlock layout forks: cross-module whole-layout snapshots. Full import:
    -- drop kept, take incoming (remapped; old-format strings may carry the
    -- legacy {groups, baseline, applied} shape, remapped too). Partial import:
    -- keep the recipient's, never take incoming.
    if takeUnlockForks then
        if pulled.specUnlockOverrides then
            local tbl = DeepCopy(pulled.specUnlockOverrides)
            tbl.layouts = remapKeys(tbl.layouts, specMap)
            tbl.groups = remapKeys(tbl.groups, specMap)
            if type(tbl.applied) == "table" and next(specMap) then
                for el, groupId in pairs(tbl.applied) do
                    tbl.applied[el] = specMap[groupId] or groupId
                end
            end
            tbl.active = remapActive(tbl.active, specMap, condMap)
            combined.specUnlockOverrides = tbl
        else
            combined.specUnlockOverrides = nil
        end
        if pulled.condUnlockOverrides then
            local tbl = DeepCopy(pulled.condUnlockOverrides)
            tbl.layouts = remapKeys(tbl.layouts, condMap)
            combined.condUnlockOverrides = tbl
        else
            combined.condUnlockOverrides = nil
        end
    end

    -- Buff Manager forks: Raid Frames data, so per-module rule -- full
    -- replacement when RF is imported, untouched when not.
    if importedFolders["CludesUIRaidFrames"] then
        if pulled.specBmOverrides then
            local tbl = DeepCopy(pulled.specBmOverrides)
            tbl.layouts = remapKeys(tbl.layouts, specMap)
            tbl.active = remapActive(tbl.active, specMap, condMap)
            combined.specBmOverrides = tbl
        else
            combined.specBmOverrides = nil
        end
        if pulled.condBmOverrides then
            local tbl = DeepCopy(pulled.condBmOverrides)
            tbl.layouts = remapKeys(tbl.layouts, condMap)
            combined.condBmOverrides = tbl
        else
            combined.condBmOverrides = nil
        end
        if pulled.specDmOverrides then
            local tbl = DeepCopy(pulled.specDmOverrides)
            tbl.layouts = remapKeys(tbl.layouts, specMap)
            tbl.active = remapActive(tbl.active, specMap, condMap)
            combined.specDmOverrides = tbl
        else
            combined.specDmOverrides = nil
        end
        if pulled.condDmOverrides then
            local tbl = DeepCopy(pulled.condDmOverrides)
            tbl.layouts = remapKeys(tbl.layouts, condMap)
            combined.condDmOverrides = tbl
        else
            combined.condDmOverrides = nil
        end
    end

    -- NO post-import default re-bank. Imported entries carry the exporter's recorded
    -- values.default, consistent with the imported addon blobs by construction
    -- (per-folder partition above). A RebaselineDefaults follow-up here would
    -- overwrite those defaults with the imported LIVE blob -- the exporter's CURRENT
    -- SPEC's override values, not defaults -- destroying the true defaults and
    -- bleeding one spec's values into every unassigned spec. RebaselineDefaults stays
    -- defined but must NEVER be wired back into the import flow.
end

--- Rewrites override entry DEFAULT maps (both stores) from the live profile, then
--- rebuilds both fkey indexes. Runs once right after a profile import lands: kept
--- entries' defaults were captured against the PREVIOUS profile, and restoring
--- those stale values when an override deactivates would permanently overwrite the
--- imported profile's own settings. Per-spec/per-group values are absolute and
--- untouched. MUST run before the overlays re-apply (SpecOverrides_ApplyValues),
--- while live still holds the pure imported values. folderSet limits the re-bank
--- to the given addon folders (partial imports: kept folders' profile tables can
--- hold ACTIVE override values, which must never be banked as defaults); nil = all.
function CUI.SpecOverrides_RebaselineDefaults(folderSet)
    -- Never re-bank while an editing view holds swapped values live (the import
    -- flow closes sessions first; this guards any other caller).
    if _editGroup or _defaultView or CondKit._edit then return end
    local function Rebank(storage)
        for _, record in ipairs(storage or {}) do
            local groupDef = record.values and record.values.default
            if groupDef then
                for fieldKey in pairs(groupDef) do
                    local moduleFolder = SplitFKey(fieldKey)
                    -- Folder filter + loaded-module guard: an unloaded child
                    -- addon has no Lite DB, so ReadLive returns nil for EVERY
                    -- fkey and nil-poisons the whole default map.
                    if
                        moduleFolder
                        and (not folderSet or folderSet[moduleFolder])
                        and DBFor(moduleFolder)
                    then
                        local liveValue = ReadLive(fieldKey)
                        -- Table values are never banked (aliasing/reference-
                        -- compare policy); keep the stored default.
                        if type(liveValue) ~= "table" then
                            groupDef[fieldKey] = (liveValue == nil) and NIL_SENT or liveValue
                        end
                    end
                end
            end
        end
    end
    Rebank(GetStore())
    Rebank(CondKit.GetStore())
    RebuildFKeyIndex()
    CondKit.RebuildIndex()
end

--- Prune: strip blacklisted folders, spec-owned fkeys (spec-wins eviction),
--- excluded-context entries, and maps for deleted groups; drop empty entries.
function CondKit.PruneEntries()
    local storage = CondKit.GetStore()
    if not storage then return end
    local removed = false
    for idx = #storage, 1, -1 do
        local record = storage[idx]
        local dropKey = false
        if record.module then
            local ex = EXCLUDED_CONTEXTS[record.module]
            if ex == true then
                dropKey = true
            elseif type(ex) == "table" and record.page then
                local pex = ex[record.page]
                if pex == true then
                    dropKey = true
                elseif type(pex) == "table" and record.section and pex[record.section] then
                    dropKey = true
                end
            end
        end
        if
            not dropKey
            and record.group ~= nil
            and not (CUI.Conditions_GroupById and CUI.Conditions_GroupById(record.group))
        then
            dropKey = true
        end
        if not dropKey and record.values and record.values.default then
            -- Blacklisted paths strip; SPEC-OWNED fkeys are deliberately KEPT (dormant):
            -- spec wins at runtime, but the conditional's value must survive so it
            -- resumes if the spec override is removed -- stripping here would
            -- permanently destroy it the moment the setting gains a spec override.
            for fieldKey in pairs(record.values.default) do
                if BlacklistedFKey(fieldKey) then
                    for _, m in pairs(record.values) do
                        if type(m) == "table" then m[fieldKey] = nil end
                    end
                    removed = true
                end
            end
            if not next(record.values.default) then dropKey = true end
        end
        if dropKey then
            table.remove(storage, idx)
            removed = true
        end
    end
    if removed then CondKit.RebuildIndex() end
end

local _condBusy = false -- re-entrancy latch (see SpecOverrides_CondTransition)

local function CondTransitionBody(oldGid, newGid, setUp)
    -- Values: bank the outgoing state, write the incoming one. An ESTABLISH transition
    -- (post profile-apply) has no outgoing owner: live is the incoming store's raw data
    -- (possibly the EXPORTER's overlaid state), so banking it corrupts the new
    -- profile's default maps and baseline layer. Apply only; never harvest.
    if not setUp then CondKit.Harvest(oldGid) end
    -- Unlock/BM layout: bank live into whichever layer is live now, BEFORE the
    -- incoming conditional's values are written -- value writes mutate module
    -- settings (sizes) that a later harvest would bank into the OUTGOING layer's
    -- elems. Re-resolution uses the NEW applied gid, passed explicitly (the engine
    -- updates its pointer only after this handler succeeds).
    if not setUp and CUI.SpecOverrides_HarvestUnlockLayout then
        CUI.SpecOverrides_HarvestUnlockLayout()
    end
    if not setUp and CUI.SpecOverrides_HarvestBmLayout then CUI.SpecOverrides_HarvestBmLayout() end
    if not setUp and CUI.SpecOverrides_HarvestDmLayout then CUI.SpecOverrides_HarvestDmLayout() end
    local touched = CondKit.WriteValues(newGid)
    if CUI.SpecOverrides_ApplyUnlock then
        CondKit._resolveOverride = newGid or false -- false = explicit none
        -- Forced on establish: the incoming raw stores may hold the layer that
        -- was live at export/save time while the imported active pointer was
        -- reset, and a nil==nil early-out would strand them.
        CUI.SpecOverrides_ApplyUnlock(CurrentSpecID(), setUp)
        CUI.SpecOverrides_ApplyBm(CurrentSpecID(), setUp)
        CUI.SpecOverrides_ApplyDm(CurrentSpecID(), setUp)
        CondKit._resolveOverride = nil
    end
    if touched then RunRefreshers(touched) end
    -- Condition applied/removed with the panel open: the labeled "Override
    -- Active" slot overlays must follow immediately.
    RequestGoldWalk()
end

--- The engine's transition handler: harvest the outgoing group, overlay the
--- incoming one, swap unlock layers, refresh (CondTransitionBody). Returns false
--- when the value system is mid-swap (spec transition / edit sessions); the engine
--- retries on its next signal (the spec Apply tail calls Conditions_Recheck).
--- Returns false, true on an error (reported, latch released, engine marked stale).
-- _defaultView is deliberately NOT a refusal reason: the engine steps OUT of the
-- Default view for the duration of a real flip (Conditions_Recheck ->
-- SpecOverrides_SuspendDefaultView) and back in once the applied pointer has
-- advanced, so live is canonical here as on every other boundary. Refusing instead
-- would strand the flip whenever the panel is open -- for the Dark Mode condition
-- that is ALWAYS (its only inputs are options widgets).
function CUI.SpecOverrides_CondTransition(oldGid, newGid, setUp)
    if _inTransition or _editGroup or CondKit._edit then return false end
    -- NON-RE-ENTRANT: the refresh fan-out in CondTransitionBody can reach RefreshAllAddons
    -- (unmapped-folder fallback, module internals), whose tail calls
    -- Conditions_MarkStale + Recheck; re-entering mid-flight rewrites values
    -- against a stale applied pointer and recurses until the client watchdog kills
    -- the frame. Refuse; the engine flags the flip pending and the next signal (or
    -- the establish flag) converges it.
    if _condBusy then return false end
    _condBusy = true
    -- An error must not leave the latch set (every later flip refused until a
    -- reload): report it, release, and leave the flip pending for a retry. Live
    -- may already hold the incoming values, so the retry establishes (applies
    -- without banking them into the outgoing group).
    local success = xpcall(CondTransitionBody, geterrorhandler(), oldGid, newGid, setUp)
    CondKit._resolveOverride = nil
    _condBusy = false
    if not success and CUI.Conditions_MarkStale then CUI.Conditions_MarkStale() end
    return success, not success
end

--- The conditional gid unlock layer resolution should use: during a condition
--- transition the engine's applied pointer is still the OLD one, so the handler
--- passes the target explicitly via _resolveOverride.
function CondKit.ResolveGid()
    local shade = CondKit._resolveOverride
    if shade ~= nil then return shade or nil end
    return CUI.Conditions_AppliedGid and CUI.Conditions_AppliedGid() or nil
end

Inner.Cond, Inner.EXCLUDED_CONTEXTS = CondKit, EXCLUDED_CONTEXTS
Inner.broken = false
