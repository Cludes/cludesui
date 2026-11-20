if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_SpecOverrides_Session.lua
--
--  The auto-capture watcher, notified writes, the exit sweep and the
--  Editing-as sessions (spec group, Default view, conditional).
--  Reads the earlier Spec Overrides files through CUI_NS._soInternals.
-------------------------------------------------------------------------------
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS -- standalone builds: the core's own table (CludesUI.lua)
local Inner = CUI_NS._soInternals
-- CludesUI_SpecOverrides.lua or an earlier Spec Overrides file failed to
-- load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local BlacklistedFKey, ConflictSpec = Inner.BlacklistedFKey, Inner.ConflictSpec
local CurrentSpecID, DBFor = Inner.CurrentSpecID, Inner.DBFor
local EDIT_B, EDIT_G, EDIT_R, EntryOwning = Inner.EDIT_B, Inner.EDIT_G, Inner.EDIT_R, Inner.EntryOwning
local FKeyLoaded, FOLDER_BLACKLIST, GetGroups = Inner.FKeyLoaded, Inner.FOLDER_BLACKLIST, Inner.GetGroups
local GetStore, HasRegisteredDefault, L = Inner.GetStore, Inner.HasRegisteredDefault, Inner.L
local LayerOwnedFKey, MatchOwnedFKey, NIL_SENT = Inner.LayerOwnedFKey, Inner.MatchOwnedFKey, Inner.NIL_SENT
local NumAllowedFKey, PS, PxCo, ReadLive = Inner.NumAllowedFKey, Inner.PS, Inner.PxCo, Inner.ReadLive
local RebuildFKeyIndex, RunRefreshers, SegKey = Inner.RebuildFKeyIndex, Inner.RunRefreshers, Inner.SegKey
local SnapValue, SplitFKey, WriteLive = Inner.SnapValue, Inner.SplitFKey, Inner.WriteLive
local HarvestDefaults, HarvestGroup = Inner.HarvestDefaults, Inner.HarvestGroup
local WriteDefaultValues, WriteGroupValues = Inner.WriteDefaultValues, Inner.WriteGroupValues
local WriteSpecValues, Cond, CurrentContext = Inner.WriteSpecValues, Inner.Cond, Inner.CurrentContext
local DiffProfiles, IsExcludedContext = Inner.DiffProfiles, Inner.IsExcludedContext
local SlotReads = Inner.SlotReads
local RequestGoldWalk, SnapshotProfiles = Inner.RequestGoldWalk, Inner.SnapshotProfiles
local UpdateEditLocks, SetEditGroup = Inner.UpdateEditLocks, Inner.SetEditGroup
local SetDefaultView, SetEnterSnap = Inner.SetDefaultView, Inner.SetEnterSnap
local SetWatchResync, SetExitGroupEdit = Inner.SetWatchResync, Inner.SetExitGroupEdit
local SetSweepUncaptured = Inner.SetSweepUncaptured
local SetTeardownEditSession, SetPanelShown = Inner.SetTeardownEditSession, Inner.SetPanelShown
local SetEnterDefaultView = Inner.SetEnterDefaultView

-- This file's copies of shared names; Set<Name> keeps every copy current
-- (the lists are built at the end of CludesUI_SpecOverrides.lua).
local _editGroup = nil
Inner.editGroupSetters[#Inner.editGroupSetters + 1] = function(val)
    _editGroup = val
end
local _defaultView = false
Inner.defaultViewSetters[#Inner.defaultViewSetters + 1] = function(val)
    _defaultView = val
end
local _enterSnap = nil
Inner.enterSnapSetters[#Inner.enterSnapSetters + 1] = function(val)
    _enterSnap = val
end
local _inTransition = false
Inner.inTransitionSetters[#Inner.inTransitionSetters + 1] = function(val)
    _inTransition = val
end
local _activeSpec = nil
Inner.activeSpecSetters[#Inner.activeSpecSetters + 1] = function(val)
    _activeSpec = val
end
local UpdateIndicator
Inner.updateIndicatorSetters[#Inner.updateIndicatorSetters + 1] = function(val)
    UpdateIndicator = val
end

-- Forward declarations (assigned further down in this file)
local SweepUncaptured, EnsurePanelHideHook, SetEditStatus, ShowEditBanner
local HideEditBanner, ApplyEditOverlay, TeardownEditSession, PanelShown
local EnterDefaultView, ExitDefaultView, ExitGroupEdit, EnterGroupEdit
local _unlockRoundtrip = nil -- session to restore after an options-entered
-- unlock roundtrip: { kind = "spec"|"cond", id = groupId }

-------------------------------------------------------------------------------
--  Auto-capture watcher (runs while Editing-as is active)
-------------------------------------------------------------------------------
local _watchSnap = nil
local _watchTicker = nil
-- The slot the last edit is attributed to, as a SNAPSHOT of its region (the
-- slot's capture config, its section and its overridden tip) taken when the
-- slot was sampled or notified: a page rebuild that dresses that region for
-- another slot (the options page pool) can never re-point it. snap: the last
-- snapshot or nil; time: when it was taken; sample: the reused table the
-- mouse-focus sampler fills; Snap(region, into): fills a snapshot.
-- pend: the one snapshot the factory hands a write before its setter runs
-- (_SOAttribution) while it waits for the next frame's attribution, busy while
-- it does; held: where the attribution keeps the snapshot that won it.
local _lastAttr = {
    snap = nil,
    time = 0,
    sample = { _soSnap = true },
    pend = { _soSnap = true },
    held = { _soSnap = true },
    busy = false,
}
function _lastAttr.Snap(regionFrame, into)
    into.cfg = regionFrame._captureCfg
    local row = regionFrame._isOptionRow and regionFrame or regionFrame:GetParent()
    local heading = row and row._sectionHeader
    into.section = heading and heading._sectionName or nil
    into.tip = regionFrame._specOvTip
    return into
end
local _watchResync = false -- absorb the next tick's diff (page rebuild seeds)
Inner.watchResyncSetters[#Inner.watchResyncSetters + 1] = function(val)
    _watchResync = val
end
local _sessionIgnored = {} -- fkeys written on excluded pages this session
-- (never captured, and skipped by the exit sweep)

local function PrettyKey(fieldKey)
    local _, filePath = SplitFKey(fieldKey)
    local last = (filePath and filePath:match("([^\30]+)$")) or tostring(fieldKey)
    last = last:gsub("(%l)(%u)", "%1 %2")
    return (last:gsub("^%l", string.upper))
end

-- Tracks which options slot the user is interacting with. Popups (dropdown
-- menus, cog popups, color picker) keep the previous slot attribution;
-- anything outside the options UI clears it.
local function SampleAttribution()
    local foci = GetMouseFoci and GetMouseFoci()
    local f = foci and foci[1]
    if not f or f == WorldFrame then
        return
    end
    local inPanel, dialog, regionFrame = false, false, nil
    local count = f
    while count do
        if count._captureCfg then
            regionFrame = count
        end
        if count._cuiOptionsPopup or count == CludesUI._colorPickerPopup then
            dialog = true
        end
        if count == _G.CludesUIFrame then
            inPanel = true
        end
        count = count:GetParent()
    end
    if regionFrame then
        _lastAttr.snap, _lastAttr.time = _lastAttr.Snap(regionFrame, _lastAttr.sample), GetTime()
    elseif dialog then
        -- keep the previous attribution (edits flow through the popup)
        _lastAttr.time = GetTime()
    elseif not inPanel then
        _lastAttr.snap = nil -- interacting with the world / other UI
    end
end

-- An override entry's crumb from its fields, each localized: module title, element,
-- the page's tab label, section; nil while the module is not registered. The list
-- rebuilds it live (BuildListRow); capture stores it for when the module is missing.
local function BuildEntryCrumb(moduleName, element, page, section)
    local modTitle = moduleName and CludesUI:GetModuleTitle(moduleName)
    if not modTitle then
        return nil
    end
    local parts = { L(modTitle) }
    if element then
        parts[#parts + 1] = L(element)
    end
    if page then
        parts[#parts + 1] = L(CUI_NS.GetTabLabel(moduleName, page))
    end
    if section then
        parts[#parts + 1] = L(section)
    end
    return table.concat(parts, "  >  ")
end

-- The entry a slot with no entry under its name already has in the session's OWN
-- store (the conditional store in a conditional session, else the spec store), so a
-- row renamed or moved keeps its one entry. Proof is a key the slot's getters read
-- (cfg traced through SlotReads; a setter's write to another row's key is never
-- read by this slot, so it never counts):
--   1. the entry owning one of `owned` (the same edit's fkeys that store owned
--      already; the captured paths never are) that the slot reads;
--   2. else an entry under the slot's own label on the same page (a row moved to
--      another section) whose every key the slot reads (a size key's exact-size
--      partner counts with it), for an edit that writes only keys no entry owns.
-- Only an entry of the same module and element qualifies, and on the spec side never
-- one a conflicting group owns (its values never bank in this session). nil = none.
local function SlotOwnerEntry(conf, ownedSet, condRun, moduleName, element, page, slotLabel, sStore)
    local reads = SlotReads(conf)
    if not next(reads) then
        return nil
    end
    local owning = condRun and Cond.EntryOwning or EntryOwning
    local function Qualifies(e)
        return e
                and e.module == moduleName
                and (e.element or "") == (element or "")
                and (condRun or not ConflictSpec(e, _editGroup))
                and true
            or false
    end
    for idx = 1, (ownedSet and #ownedSet or 0) do
        if reads[ownedSet[idx]] then
            local e = owning(ownedSet[idx])
            if Qualifies(e) then
                return e
            end
        end
    end
    for _, entry in ipairs(sStore or {}) do
        local groupDef = entry.values and entry.values.default
        if
            type(groupDef) == "table"
            and entry.slotLabel == slotLabel
            and (entry.page or "") == (page or "")
            and Qualifies(entry)
        then
            local any, all = false, true
            for fieldKey in pairs(groupDef) do
                local base = type(fieldKey) == "string" and fieldKey:match("^(.*)Px$")
                if reads[fieldKey] or (base and reads[base] and PxCo.Partner(base) == fieldKey) then
                    any = true
                else
                    all = false
                end
            end
            if any and all then
                return entry
            end
        end
    end
    return nil
end

-- The slot's current name and place, on the entry it already has.
local function TakeOverEntry(record, slotLabel, moduleName, element, page, section)
    record.label, record.slotLabel = slotLabel, slotLabel
    record.crumb = BuildEntryCrumb(moduleName, element, page, section) or record.crumb
    record.page, record.section, record.element = page, section, element
end

-- An edit that writes only keys the session's store already owns captures nothing,
-- but a renamed or moved slot still takes over the entry it has (SlotOwnerEntry's
-- proof: a key the slot's getters read). Values are untouched. Same attribution,
-- context and burst guards as AutoCapture below.
local function RelabelOwnedSlot(ownedSet)
    if CludesUI._prebuilding then
        return
    end
    local snapshot = _lastAttr.snap
    if not (snapshot and snapshot.cfg and (GetTime() - _lastAttr.time) < 3) then
        return
    end
    local section = snapshot.section
    if IsExcludedContext(section) or #ownedSet > 12 then
        return
    end
    local condRun = Cond._edit
    local sStore = condRun and Cond.GetStore(true) or GetStore(true)
    if not sStore then
        return
    end
    local conf = snapshot.cfg
    local slotLabel = tostring(conf.text or "?")
    local moduleName = CludesUI:GetActiveModule()
    local page = CludesUI:GetActivePage()
    local element = CurrentContext()
    for _, entry in ipairs(sStore) do
        if
            entry.slotLabel == slotLabel
            and entry.module == moduleName
            and (entry.element or "") == (element or "")
            and (entry.page or "") == (page or "")
            and (entry.section or "") == (section or "")
        then
            return -- already under this slot's name
        end
    end
    local record = SlotOwnerEntry(conf, ownedSet, condRun, moduleName, element, page, slotLabel, sStore)
    if record then
        TakeOverEntry(record, slotLabel, moduleName, element, page, section)
    end
end

-- changes: the edit's fkeys no entry of the session's store owns (captured here);
-- owned (optional): the same edit's fkeys that store already owns (array of fkeys),
-- read only to find the entry a renamed or moved slot already has.
local function AutoCapture(changes, ownedSet)
    -- Hidden search prebuild: selector setters and lazy page seeding write
    -- db.profile from a pass the user never sees -- never capture them.
    if CludesUI._prebuilding then
        return
    end
    -- Attribution required: without a known slot, absorb silently (background
    -- bookkeeping like drag positions must never become overrides). The 3-second
    -- window bounds this mouse-focus FALLBACK (the notified-write path attributes
    -- exactly); longer lets unrelated background writes (match propagation,
    -- combat-end refreshers) land under the last slot touched.
    local snapshot = _lastAttr.snap
    if not (snapshot and snapshot.cfg and (GetTime() - _lastAttr.time) < 3) then
        return
    end
    -- Excluded contexts (whole modules, pages, or single sections) never factor into
    -- spec overrides: absorb, and shield these paths from the exit sweep. Section is
    -- derived up front so section-scoped (nested-table) entries apply.
    local section = snapshot.section
    if IsExcludedContext(section) then
        for _, change in ipairs(changes) do
            _sessionIgnored[change.fkey] = true
        end
        return
    end
    local storage = GetStore(true)
    if not storage then
        return
    end

    -- Validate + collect
    local paths, skippedNum, skippedBlack, layerOwned = {}, false, nil, nil
    for _, change in ipairs(changes) do
        -- Blacklist before the numeric guard: an array-shaped blacklisted key
        -- (bm2 indicator sets) reported as a list-position problem reads as
        -- "buff sizes can never be overridden", which is not what happened.
        local layer = LayerOwnedFKey(change.fkey)
        if layer then
            layerOwned = layer
        elseif BlacklistedFKey(change.fkey) then
            skippedBlack = change.folder
        elseif change.num and not NumAllowedFKey(change.fkey) then
            skippedNum = true
        elseif MatchOwnedFKey(change.fkey) then
            -- Match-owned size keys are the match engine's territory: apply
            -- skips them and every bank preserves, so capturing one only
            -- creates a dead slot the harvests must tiptoe around.
            _sessionIgnored[change.fkey] = true
        else
            paths[#paths + 1] = change.fkey
        end
    end
    if #paths == 0 then
        if layerOwned then
            local state, textValue
            if layerOwned == "bm" then
                state = CludesUI.SpecOverrides_BmOverlayState()
                textValue = L("Buff Manager changes on this page apply only to this override.")
            else
                state = CludesUI.SpecOverrides_DmOverlayState()
                textValue = L("Debuff Manager changes on this page apply only to this override.")
            end
            -- No overlay = the fork IS live, so the edit landed in it. An overlay
            -- means the page was blocked and the write came from elsewhere.
            if not state then
                SetEditStatus(textValue, 1, 1, 0.6)
            end
        elseif skippedBlack then
            if skippedBlack == "CludesUICooldownManager" then
                SetEditStatus(
                    L("Cooldown Manager has its own per-spec system and can't be overridden here."),
                    1,
                    0.55,
                    0.35
                )
            elseif FOLDER_BLACKLIST[skippedBlack] then
                SetEditStatus(L("This module is excluded from Spec Overrides."), 1, 0.55, 0.35)
            else
                -- Setting-level exclusion (SETTING_BLACKLIST hit).
                SetEditStatus(L("This setting can't be overridden."), 1, 0.55, 0.35)
            end
        elseif skippedNum then
            SetEditStatus(
                L("That setting is stored by list position and can't be safely overridden."),
                1,
                0.55,
                0.35
            )
        end
        return
    end
    if #paths > 12 then
        return
    end -- burst; not a slot edit

    local conf = snapshot.cfg
    local slotLabel = tostring(conf.text or "?")
    local moduleName = CludesUI:GetActiveModule()
    local page = CludesUI:GetActivePage()
    local element = CurrentContext()

    -- Session routing: a conditional session banks into the CONDITIONAL store
    -- (own fkey index, group id space, per-GROUP value maps instead of
    -- per-spec). Everything else is identical.
    local condRun = Cond._edit
    local sStore = condRun and Cond.GetStore(true) or storage
    local record
    for _, entry in ipairs(sStore or {}) do
        if
            entry.slotLabel == slotLabel
            and entry.module == moduleName
            and (entry.element or "") == (element or "")
            and (entry.page or "") == (page or "")
            and (entry.section or "") == (section or "")
        then
            record = entry
            break
        end
    end
    local isNew = false
    if not record then
        -- No entry under this slot's name: the entry the slot already has (its row
        -- was renamed or moved) takes the slot's current name and place instead of
        -- a second entry starting.
        record = SlotOwnerEntry(conf, ownedSet, condRun, moduleName, element, page, slotLabel, sStore)
        if record then
            TakeOverEntry(record, slotLabel, moduleName, element, page, section)
        end
    end
    if not record then
        isNew = true
        record = {
            label = slotLabel,
            slotLabel = slotLabel,
            crumb = BuildEntryCrumb(moduleName, element, page, section),
            module = moduleName,
            page = page,
            element = element,
            section = section,
            group = condRun and condRun.id or (_editGroup and _editGroup.id or nil),
            values = { default = {} },
        }
        sStore[#sStore + 1] = record
    end

    -- Record originals (pre-change snapshot values) as the shared default; conditional
    -- sessions also seed the group's map. Live values bank at session exit. The REAL
    -- spec's map is deliberately NOT seeded: the per-key default fallback in
    -- WriteSpecValues already restores the bystander spec at exit, and a stored copy
    -- would pin it at this old default forever once the default is later edited
    -- (permanent phantom override on an unassigned spec).
    for _, fieldKey in ipairs(paths) do
        if record.values.default[fieldKey] == nil then
            local original = SnapValue(_watchSnap, fieldKey)
            -- Spec-session capture of a cond-owned fkey: the snapshot may hold an
            -- APPLIED conditional's overlay value, not the shared baseline. Seed from
            -- the cond store's recorded default instead. (Inert in a cond session:
            -- captured fkeys there are never cond-owned.)
            local condRec = Cond.EntryOwning(fieldKey)
            if condRec then
                original = condRec.values.default[fieldKey]
                if original == NIL_SENT then
                    original = nil
                end
            end
            if type(original) == "table" then
                original = nil
            end
            record.values.default[fieldKey] = (original == nil) and NIL_SENT or original
            if condRun then
                local gm = record.values[condRun.id]
                if not gm then
                    gm = {}
                    record.values[condRun.id] = gm
                end
                gm[fieldKey] = record.values.default[fieldKey]
            end
        end
    end
    -- A border size key brings its exact-size companion along (see PxCo): a write
    -- of the legacy size alone must still own "<key>Px" from now on, unless
    -- another entry of this store already owns it. Seeded as the main loop seeds.
    for _, fieldKey in ipairs(paths) do
        local partnerKey = PxCo.Partner(fieldKey)
        local other = partnerKey and (condRun and Cond.EntryOwning(partnerKey) or EntryOwning(partnerKey))
        if partnerKey and record.values.default[partnerKey] == nil and not (other and other ~= record) then
            local original = SnapValue(_watchSnap, partnerKey)
            local condRec = Cond.EntryOwning(partnerKey)
            if condRec then
                original = condRec.values.default[partnerKey]
                if original == NIL_SENT then
                    original = nil
                end
            end
            if type(original) == "table" then
                original = nil
            end
            record.values.default[partnerKey] = (original == nil) and NIL_SENT or original
            if condRun then
                local gm = record.values[condRun.id]
                if not gm then
                    gm = {}
                    record.values[condRun.id] = gm
                end
                gm[partnerKey] = record.values.default[partnerKey]
            end
        end
    end

    if condRun then
        Cond.RebuildIndex()
    else
        RebuildFKeyIndex()
    end
    RequestGoldWalk()
    if isNew then
        local sessName = condRun and condRun.name or (_editGroup and _editGroup.name) or "?"
        SetEditStatus(string.format(L("'%s' is now customized for %s."), slotLabel, sessName), 0.35, 1, 0.35)
    end
end

-- The table an fkey's leaf lives in, plus that leaf's key, or nil when the path does
-- not resolve (module not loaded, array entry deleted). Same walk ReadLive does.
local function OwnerOf(fieldKey)
    local folder, filePath = SplitFKey(fieldKey)
    local t = folder and DBFor(folder)
    if type(t) ~= "table" or not filePath then
        return nil
    end
    local segs = { strsplit(PS, filePath) }
    for idx = 1, #segs - 1 do
        t = t[SegKey(t, segs[idx])]
        if type(t) ~= "table" then
            return nil
        end
    end
    return t, SegKey(t, segs[#segs])
end

-- do ... end: the helper below is released at `end` instead of taking a
-- top-level slot. The global it wires up stays, as always.
do
    -- Does any entry in `sStore` hold a VALUE (not just a recorded default) for `key` of
    -- `store`? Attribution by table identity, the same rule ClearStoreKey uses.
    local function StoreHoldsKey(sStore, storage, key)
        for _, entry in ipairs(sStore or {}) do
            local groupDef = entry.values and entry.values.default
            if groupDef then
                for fieldKey in pairs(groupDef) do
                    local ownerFrame, leaf = OwnerOf(fieldKey)
                    if ownerFrame == storage and leaf == key then
                        for mapKey, m in pairs(entry.values) do
                            if mapKey ~= "default" and type(m) == "table" and m[fieldKey] ~= nil then
                                return true
                            end
                        end
                    end
                end
            end
        end
        return false
    end

    --- True while SOME override -- spec or conditional -- still holds a value for `key` of
    --- `store`. A control that writes its own marker key (the Visibility row's override)
    --- asks before trusting a live one: removing an entry from the management list leaves
    --- its applied value in place on purpose, and a profile exported while an override
    --- applied carries the marker into every import that does not also take the overrides.
    --- In both cases nothing owns the key any more and the element would stay pinned on it
    --- with no path back.
    function CludesUI.SpecOverrides_KeyIsOwned(storage, key)
        if type(storage) ~= "table" or type(key) ~= "string" then
            return false
        end
        return StoreHoldsKey(GetStore(), storage, key) or StoreHoldsKey(Cond.GetStore(), storage, key)
    end
end

--- Drop what the CURRENT session captured for ONE key across the given settings TABLES
--- and put the recorded pre-override values back live. `stores` is an ARRAY so a control
--- writing one key to several tables (Resource Bars mirrors the Visibility row onto
--- health/primary/secondary) clears them in one pass: the finalization below re-snapshots
--- every module profile, far too expensive to repeat once per table. Attribution is by
--- TABLE IDENTITY: AutoCapture attributes an entry by slot label, the exit sweep mints
--- entries from the fkey alone with no slot fields, and only identity matches both
--- shapes. Returns true when something was cleared.
function CludesUI.SpecOverrides_ClearStoreKey(stores, key)
    if type(stores) ~= "table" or type(key) ~= "string" then
        return false
    end
    local condRun = Cond._edit
    if not (_editGroup or condRun) then
        return false
    end
    local sStore = condRun and Cond.GetStore() or GetStore()
    if not sStore then
        return false
    end

    -- The value maps this session owns. A conditional session keeps one map per GROUP;
    -- the spec side keeps one per SPEC and a group covers every member spec, which is
    -- also how HarvestGroup banks into all of them.
    local ownedSet = {}
    if condRun then
        ownedSet[1] = condRun.id
    else
        for _, specID in ipairs(_editGroup.specs or {}) do
            ownedSet[#ownedSet + 1] = specID
        end
    end

    local cleared = false
    for idx = #sStore, 1, -1 do
        local e = sStore[idx]
        local groupDef = e.values and e.values.default
        -- One entry can hold the key for SEVERAL of the stores (a mirrored row banks all
        -- of them into the same slot), so every hit is collected rather than the first.
        local hits
        if groupDef then
            for fieldKey in pairs(groupDef) do
                local ownerFrame, leaf = OwnerOf(fieldKey)
                if leaf == key and ownerFrame ~= nil then
                    for si = 1, #stores do
                        if ownerFrame == stores[si] then
                            hits = hits or {}
                            hits[#hits + 1] = fieldKey
                            break
                        end
                    end
                end
            end
        end
        for hgt = 1, (hits and #hits or 0) do
            local hit = hits[hgt]
            -- Only the maps the EDITED session owns are cleared. One entry is shared by
            -- every group that customized the same slot (AutoCapture looks it up by slot,
            -- not by group, and adds a per-group value map), so wiping all of them would
            -- delete other groups' overrides along with this one.
            for _, mapKey in ipairs(ownedSet) do
                local m = e.values[mapKey]
                if type(m) == "table" then
                    m[hit] = nil
                end
            end
            -- The recorded default only goes once nobody holds a value for the key any
            -- more; until then the entry stays alive for the groups that still do.
            local stillHeld = false
            for mapKey, m in pairs(e.values) do
                if mapKey ~= "default" and type(m) == "table" and m[hit] ~= nil then
                    stillHeld = true
                    break
                end
            end
            local dv = groupDef[hit]
            if dv == NIL_SENT then
                dv = nil
            end
            -- Same guard the apply sites use: a stored removal is never honored for a
            -- key the module registers a default for. Written either way: the session
            -- has to show the value it just gave up.
            if dv ~= nil or not HasRegisteredDefault(hit) then
                WriteLive(hit, dv)
            end
            if not stillHeld then
                groupDef[hit] = nil
            end
            cleared = true
        end
        -- Hoisted out of the hits loop: removing inside it would delete a DIFFERENT entry
        -- on the second pass, index i no longer being this one.
        if hits and groupDef and not next(groupDef) then
            table.remove(sStore, idx)
        end
    end

    if cleared then
        if condRun then
            Cond.RebuildIndex()
        else
            RebuildFKeyIndex()
        end
        -- The restore write is ours, not the user's: re-snapshot so neither the ticker
        -- nor the queued notified pass can diff it straight back into a capture.
        _watchSnap = SnapshotProfiles()
        SetWatchResync(true)
        RequestGoldWalk()
    end
    return cleared
end

local function WatchTick()
    if not _editGroup and not Cond._edit then
        return
    end
    SampleAttribution()
    local rootFrame = _G.CludesUIFrame
    if not (rootFrame and rootFrame:IsShown()) then
        return
    end
    -- Folded to the mini window: nothing on the panel can be edited, so skip the
    -- profile diff; the unfold re-baselines the snapshot (RegisterOnCollapse below).
    if CludesUI._panelCollapsed then
        return
    end
    -- Hidden search prebuild mid-session: its selector setters and lazy page
    -- seeding write db.profile; absorb the whole tick (resync) so those writes
    -- can never diff into captures.
    if CludesUI._prebuilding then
        _watchSnap = SnapshotProfiles()
        return
    end
    if not _watchSnap then
        _watchSnap = SnapshotProfiles()
        return
    end
    local diffs = DiffProfiles(_watchSnap)
    if #diffs == 0 then
        return
    end
    if not _watchResync then
        local newList, ownedList = nil, nil
        for _, change in ipairs(diffs) do
            -- Conditional session: spec-owned fkeys are editable here too
            -- (each store keeps its own value; the session shows
            -- conditional-over-default) but spec still wins at RUNTIME.
            -- Cond-owned fkeys bank at exit.
            local ownedSet
            if Cond._edit then
                ownedSet = Cond.EntryOwning(change.fkey)
            else
                ownedSet = EntryOwning(change.fkey)
            end
            if not ownedSet then
                newList = newList or {}
                newList[#newList + 1] = change
            else
                ownedList = ownedList or {}
                ownedList[#ownedList + 1] = change.fkey
            end
        end
        if newList then
            AutoCapture(newList, ownedList)
        elseif ownedList then
            RelabelOwnedSlot(ownedList)
        end
    end
    SetWatchResync(false)
    _watchSnap = SnapshotProfiles()
end

-- Unfolding from the mini window: absorb whatever changed the profiles while the
-- panel was folded (WatchTick skipped them), so the first widget edit after it
-- (ProcessNotifiedWrites diffs against the same snapshot) captures only itself.
CludesUI:RegisterOnCollapse(function(enabled)
    if not enabled and (_editGroup or Cond._edit) and _watchSnap then
        _watchSnap = SnapshotProfiles()
    end
end)

-- Page rebuilds lazily seed defaults into profiles; absorb those writes instead of
-- capturing them (fast-path refreshes don't rebuild rows and keep capture armed).
-- Also the panel-lifecycle bootstrap: page activity means the panel exists/opened,
-- so install the show/hide hooks and enter the Default view when idle.
local function OnPageRebuilt()
    SetWatchResync(true)
    RequestGoldWalk()
    if ApplyEditOverlay then
        ApplyEditOverlay()
    end -- chrome-page suppression
    if EnsurePanelHideHook then
        EnsurePanelHideHook()
    end
    -- The toolbar button disables on excluded pages; re-evaluate per page.
    if CludesUI._specOvBtnPageState then
        CludesUI._specOvBtnPageState()
    end
    -- BM passive chrome follows page navigation: shows on the Buff Manager page
    -- with a live fork, clears when leaving it.
    if CludesUI.SpecOverrides_UpdateBmPassiveChrome then
        CludesUI.SpecOverrides_UpdateBmPassiveChrome()
    end
    if not _editGroup and not _defaultView then
        C_Timer.After(0, function()
            -- _unlockRoundtrip: the post-unlock page restore rebuilds pages before the
            -- OnShow restore consumes the stash, so entering the Default view here
            -- would only churn (the session re-enter exits it a tick later).
            if
                not _editGroup
                and not _defaultView
                and not _unlockRoundtrip
                and _G.CludesUIFrame
                and _G.CludesUIFrame:IsShown()
                and EnterDefaultView
            then
                EnterDefaultView()
            end
        end)
    end
end

-------------------------------------------------------------------------------
--  Notified writes: the widget factory calls _NotifySettingWrite on EVERY widget
--  setValue. Primary capture path -- exact frame-based slot attribution, processed
--  next frame, immune to page-rebuild seed absorption (a forced refresh triggered
--  by the setter itself can never swallow the user's edit). The polling ticker is
--  only the fallback for writes outside the factory.
-------------------------------------------------------------------------------
local _pendingWrites, _pendingWriteQueued = nil, false

local function ProcessNotifiedWrites()
    _pendingWriteQueued = false
    local frameList = _pendingWrites
    _pendingWrites = nil
    -- the queued snapshot is read below, before anything can take it again
    _lastAttr.busy = false
    if not (_editGroup or Cond._edit) or not _watchSnap then
        return
    end
    -- Prebuild writes are never user edits: absorb via resync (see WatchTick).
    if CludesUI._prebuilding then
        _watchSnap = SnapshotProfiles()
        return
    end
    -- Exact attribution from the notified frames (first that resolves wins). An
    -- entry is either a snapshot the notifier took (CludesUI._SOAttribution)
    -- or the frame itself, resolved here as it stands now.
    for _, f in ipairs(frameList or {}) do
        if type(f) == "table" then
            if f._soSnap then
                if f.cfg then
                    local hgt = _lastAttr.held
                    hgt.cfg, hgt.section, hgt.tip = f.cfg, f.section, f.tip
                    _lastAttr.snap, _lastAttr.time = hgt, GetTime()
                    break
                end
            else
                local count, regionFrame = f, nil
                while count do
                    if count._captureCfg then
                        regionFrame = count
                        break
                    end
                    count = count:GetParent()
                end
                if regionFrame then
                    _lastAttr.snap, _lastAttr.time = _lastAttr.Snap(regionFrame, _lastAttr.held), GetTime()
                    break
                end
            end
        end
    end
    local diffs = DiffProfiles(_watchSnap)
    if #diffs == 0 then
        return
    end
    local newList, ownedList
    for _, change in ipairs(diffs) do
        -- Ownership filter mirrors WatchTick's session branch: in a cond
        -- session cond-owned fkeys bank at exit (HarvestEdit); everything else
        -- captures immediately here.
        local ownedSet
        if Cond._edit then
            ownedSet = Cond.EntryOwning(change.fkey)
        else
            ownedSet = EntryOwning(change.fkey)
        end
        if not ownedSet then
            newList = newList or {}
            newList[#newList + 1] = change
        else
            ownedList = ownedList or {}
            ownedList[#ownedList + 1] = change.fkey
        end
    end
    if newList then
        AutoCapture(newList, ownedList)
    elseif ownedList then
        RelabelOwnedSlot(ownedList)
    end
    _watchSnap = SnapshotProfiles()
end

-- One-time warning when a BASE edit (Default Editing Mode) lands on an OVERRIDDEN
-- slot: the change edits the shared default only, and a user who does not know the
-- system reads "my change didn't apply" on the specs the override covers. Same
-- video-guide popup as the glyph's first click with warning copy; FireOnce stamps
-- seen before showing (/cuivideos resets). Reached only while the Default view is
-- live (store non-empty, panel open, no session), so users without overrides pay a
-- single boolean per write.
local _warnWatch -- one-shot GLOBAL_MOUSE_UP frame: the guide never pops mid-drag
local function MaybeWarnDefaultEdit(widget, snapshot)
    local DEFAULT_EDIT_GUIDE = "override_default_edit"
    -- The warning popup is not part of CludesUI: nothing to show.
    do
        return
    end
    -- Hidden search prebuild: selector setters run on pages the user never sees.
    if CludesUI._prebuilding then
        return
    end
    if _warnWatch and _warnWatch._pending then
        return
    end
    -- Only a slot the last gold walk marked as overridden qualifies (from the
    -- notifier's snapshot when it took one, else the frame as it stands now).
    if snapshot then
        if not snapshot.tip then
            return
        end
    else
        local count = widget
        while count do
            if count._captureCfg then
                break
            end
            count = count.GetParent and count:GetParent() or nil
        end
        if not (count and count._specOvTip) then
            return
        end
    end
    if not _warnWatch then
        _warnWatch = CreateFrame("Frame")
        _warnWatch:SetScript("OnEvent", function(self)
            self:UnregisterEvent("GLOBAL_MOUSE_UP")
            -- Next frame: the release itself (slider commit, picker close) settles first.
            C_Timer.After(0, function()
                self._pending = nil
                VG.FireOnce(DEFAULT_EDIT_GUIDE)
            end)
        end)
    end
    _warnWatch._pending = true
    if IsMouseButtonDown() then
        -- Sliders and color pickers notify on every drag step; a dimmer landing
        -- under a held button would swallow the release. Fire when it comes up.
        _warnWatch:RegisterEvent("GLOBAL_MOUSE_UP")
    else
        -- Deferred: the notify runs inside the widget setter, often mid-refresh.
        C_Timer.After(0, function()
            _warnWatch._pending = nil
            VG.FireOnce(DEFAULT_EDIT_GUIDE)
        end)
    end
end

--- The slot a widget write belongs to, as a snapshot taken NOW: { cfg = the
--- slot's capture config, section = its section name, tip = its overridden tip }.
--- A setter that rebuilds the page (options page pool: the same frames dressed
--- again for other slots) must not move the attribution, so the widget factory
--- takes it BEFORE calling the user setter and hands it to _NotifySettingWrite.
--- nil when nothing would read it (no editing session; the Default view once
--- its warning was seen) or when the frame belongs to no slot. Same parent walk
--- as the notified pass. In a session it fills ONE reused table: the first write
--- of a frame wins the next frame's attribution (ProcessNotifiedWrites), so the
--- writes after it, until that pass ran, take none (their frames are queued).
--- detached (optional): a table the caller owns, filled instead, in or out of a
--- session and leaving that one-per-frame rule alone, for a widget that writes
--- later for the slot it was opened from (the color picker takes one when it
--- opens and hands it to _NotifySettingWrite with each later write: it names
--- that slot even after a rebuild dressed the widget again for another one).
--- Returns detached (marked as a snapshot), or nil when no slot holds frame.
function CludesUI._SOAttribution(widget, detached)
    if type(widget) ~= "table" then
        return nil
    end
    local into = detached
    if into == nil then
        if _editGroup or Cond._edit then
            if _lastAttr.busy then
                return nil
            end
            into = _lastAttr.pend
        elseif _defaultView then
            -- only MaybeWarnDefaultEdit read this, and it shows nothing now
            return nil
        else
            return nil
        end
    end
    local count = widget
    while count do
        if count._captureCfg then
            if detached then
                detached._soSnap = true
            elseif into then
                _lastAttr.busy = true
            end
            return _lastAttr.Snap(count, into or { _soSnap = true })
        end
        count = count.GetParent and count:GetParent() or nil
    end
    return nil
end

--- Called by the widget factory whenever any options widget writes a value.
--- snap: the slot snapshot the factory took before the setter ran (optional;
--- a detached one stands alone, with no frame).
function CludesUI._NotifySettingWrite(widget, snapshot)
    -- The written slot's inline cog takes notice (the cog notice in
    -- CludesUI_Widgets_RowAddons.lua, defined once the options load).
    local cogNotice = CludesUI._CogWriteNotice
    if cogNotice then
        cogNotice(widget)
    end
    -- Conditional sessions capture through this path too. Without them in the gate they
    -- fall back to watcher/exit-sweep capture only, losing edits whenever a setter's
    -- forced refresh raises the resync absorb before a tick can attribute them.
    if not (_editGroup or Cond._edit) then
        if _defaultView and (type(widget) == "table" or snapshot ~= nil) then
            MaybeWarnDefaultEdit(widget, snapshot)
        end
        return
    end
    _pendingWrites = _pendingWrites or {}
    _pendingWrites[#_pendingWrites + 1] = snapshot or widget or false
    if not _pendingWriteQueued then
        _pendingWriteQueued = true
        C_Timer.After(0, ProcessNotifiedWrites)
    end
end

-------------------------------------------------------------------------------
--  Exit-sweep safety net: anything that changed during the session and never
--  got captured (bespoke widgets, frame drags) must not leak into the real
--  spec. Sweeping it into the group lets the exit restore undo it live.
-------------------------------------------------------------------------------
SweepUncaptured = function(set)
    if not _enterSnap or not set then
        return
    end
    local storage = GetStore(true)
    if not storage then
        return
    end
    local added = false
    for _, change in ipairs(DiffProfiles(_enterSnap)) do
        -- MatchOwnedFKey: a match-owned size diff is the match engine's write,
        -- never a session edit; minting an entry from it hands the key to the
        -- harvest broadcast (proliferation vector).
        if
            not EntryOwning(change.fkey)
            and (not change.num or NumAllowedFKey(change.fkey))
            and not BlacklistedFKey(change.fkey)
            and not MatchOwnedFKey(change.fkey)
            and not _sessionIgnored[change.fkey]
        then
            local original = SnapValue(_enterSnap, change.fkey)
            -- Same guard as AutoCapture: a cond-owned fkey's snapshot may be
            -- an applied conditional's overlay; seed from the cond store's
            -- recorded default instead.
            local condRec = Cond.EntryOwning(change.fkey)
            if condRec then
                original = condRec.values.default[change.fkey]
                if original == NIL_SENT then
                    original = nil
                end
            end
            if type(original) == "table" then
                original = nil
            end
            local record = {
                label = PrettyKey(change.fkey),
                crumb = (CludesUI:GetModuleTitle(change.folder)) or change.folder,
                module = change.folder,
                group = set.id,
                values = { default = { [change.fkey] = (original == nil) and NIL_SENT or original } },
            }
            -- The real spec's map is deliberately not seeded (see AutoCapture).
            storage[#storage + 1] = record
            added = true
        end
    end
    if added then
        RebuildFKeyIndex()
    end
end
SetSweepUncaptured(SweepUncaptured)

-------------------------------------------------------------------------------
--  Editing-as core
-------------------------------------------------------------------------------
local banner, editBannerText, bannerStatus
local panelHideHooked = false

EnsurePanelHideHook = function()
    if panelHideHooked or not _G.CludesUIFrame then
        return
    end
    panelHideHooked = true
    _G.CludesUIFrame:HookScript("OnHide", function()
        -- Unlock-mode roundtrip: when the panel hides because Unlock Mode was opened
        -- FROM the options window, remember the active editing session so the
        -- auto-reopen restores the same override view. The session still tears down
        -- normally below (values bank safely; only the SELECTION is remembered). A
        -- hide with no session leaves any pending stash untouched -- the panel can
        -- flash shown/hidden while unlock force-closes.
        if CludesUI._unlockReturnModule ~= nil then
            if _editGroup then
                _unlockRoundtrip = { kind = "spec", id = _editGroup.id }
            elseif Cond._edit then
                _unlockRoundtrip = { kind = "cond", id = Cond._edit.id }
            end
        end
        if ExitGroupEdit then
            ExitGroupEdit()
        end
        if Cond.ExitEdit then
            Cond.ExitEdit()
        end
        if ExitDefaultView then
            ExitDefaultView()
        end
        if CludesUI._specOvCardsPopup then
            CludesUI._specOvCardsPopup:Hide()
        end
        if Cond._cardsPopup then
            Cond._cardsPopup:Hide()
        end
        -- Name/icon popups parent to UIParent and would survive the panel closing; their
        -- Create/Save buttons enter an edit session, and a session entered with the
        -- panel HIDDEN snapshots before the deferred page rebuild's lazy seeding, so the
        -- exit sweep adopts those seeds as phantom captures. Close them with the panel.
        if CludesUI._specOvNamePopup then
            CludesUI._specOvNamePopup:Hide()
        end
        if Cond._namePopup then
            Cond._namePopup:Hide()
        end
        -- The condition picker leads into the name popup and holds a key
        -- capture that must not stay up into combat: it closes too.
        if Cond._pickerPopup then
            Cond._pickerPopup:Hide()
        end
    end)
    -- Re-entering the panel returns to the Default Editing Mode view, or after
    -- an options-entered unlock roundtrip back to the session that was active
    -- when unlock hid the panel.
    _G.CludesUIFrame:HookScript("OnShow", function()
        C_Timer.After(0, function()
            if not (_G.CludesUIFrame and _G.CludesUIFrame:IsShown()) then
                return
            end
            local rt = _unlockRoundtrip
            if rt then
                -- One-shot: consumed only on a show that processes (the
                -- force-close flow can flash the panel shown->hidden).
                _unlockRoundtrip = nil
                if rt.kind == "spec" and EnterGroupEdit then
                    for _, group in ipairs(GetGroups() or {}) do
                        if group.id == rt.id then
                            EnterGroupEdit(group)
                            return
                        end
                    end
                elseif rt.kind == "cond" and Cond.EnterEdit then
                    local cgroups = CludesUI.Conditions_GetGroups and CludesUI.Conditions_GetGroups()
                    for _, group in ipairs(cgroups or {}) do
                        if group.id == rt.id then
                            Cond.EnterEdit(group)
                            return
                        end
                    end
                end
                -- Group vanished mid-roundtrip: fall through to Default view.
            end
            if EnterDefaultView then
                EnterDefaultView()
            end
        end)
    end)
end

local function EnsureEditBanner()
    if banner then
        return banner
    end
    -- The panel body, so the banner hides with the window when it collapses.
    local rootFrame = CludesUI._panelBody or UIParent
    banner = CreateFrame("Frame", nil, rootFrame)
    banner:SetSize(680, 44)
    -- Sits ON TOP of the visible panel: banner bottom flush with the window's
    -- top edge (the click area is the actual window; the outer frame includes
    -- the background art's shadow padding).
    banner:SetPoint("BOTTOM", _G.CludesUIClickArea or rootFrame, "TOP", 0, 0)
    banner:SetClampedToScreen(true)
    banner:SetFrameStrata("DIALOG")
    local backdrop = banner:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0.05, 0.05, 0.06, 0.92)
    -- Rounded gold outline, as the Unlock Mode override banner.
    CludesUI.MakeRoundedBorder(banner, EDIT_R, EDIT_G, EDIT_B, 0.7, backdrop)
    editBannerText = banner:CreateFontString(nil, "OVERLAY")
    editBannerText:SetFont(CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 13, "")
    editBannerText:SetPoint("TOPLEFT", banner, "TOPLEFT", 16, -8)
    editBannerText:SetTextColor(EDIT_R, EDIT_G, EDIT_B, 1)
    bannerStatus = banner:CreateFontString(nil, "OVERLAY")
    bannerStatus:SetFont(CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
    bannerStatus:SetPoint("BOTTOMLEFT", banner, "BOTTOMLEFT", 16, 7)
    bannerStatus:SetTextColor(1, 1, 1, 0.6)
    local finished = CreateFrame("Button", nil, banner)
    finished:SetSize(74, 24)
    finished:SetPoint("RIGHT", banner, "RIGHT", -12, 0)
    local dbg = CludesUI.SolidTex(finished, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    dbg:SetAllPoints()
    local dbrd = CludesUI.MakeRoundedBorder(finished, 1, 1, 1, 0.22, dbg)
    local dlbl = CludesUI.MakeFont(finished, 11, nil, 1, 1, 1, 0.9)
    dlbl:SetPoint("CENTER")
    dlbl:SetText(L("Done"))
    finished:SetScript("OnEnter", function()
        if dbrd and dbrd.SetColor then
            dbrd:SetColor(EDIT_R, EDIT_G, EDIT_B, 0.8)
        end
    end)
    finished:SetScript("OnLeave", function()
        if dbrd and dbrd.SetColor then
            dbrd:SetColor(1, 1, 1, 0.22)
        end
    end)
    finished:SetScript("OnClick", function()
        if _editGroup then
            ExitGroupEdit()
        end
        if Cond.ExitEdit then
            Cond.ExitEdit()
        end
    end)
    banner._done = finished -- passive chrome hides it (nothing to exit)
    return banner
end

SetEditStatus = function(textValue, r, group, b)
    if bannerStatus then
        bannerStatus:SetText(textValue or "")
        bannerStatus:SetTextColor(r or 1, group or 1, b or 0.6)
    end
end

ShowEditBanner = function(set)
    EnsureEditBanner()
    if banner._done then
        banner._done:Show()
    end -- passive mode hides it
    editBannerText:SetText(string.format(L("Editing as %s"), set.name or "?"))
    SetEditStatus(L("Any setting you change now applies only to this group's specs."), 1, 1, 0.6)
    banner:Show()
    -- Lock excluded modules on the sidebar for the session's duration.
    if CludesUI.RefreshSidebarOverrideLocks then
        CludesUI.RefreshSidebarOverrideLocks()
    end
end

HideEditBanner = function()
    if banner then
        banner:Hide()
    end
end

-- Background glow overlay shown while Editing-as. Aligned 1:1 with the options
-- panel background layers (both fill CludesUIFrame edge to edge), one frame
-- level above them and below all content frames.
local EDIT_GLOW_TEXTURE = "Interface\\AddOns\\CludesUI\\media\\backgrounds\\cui-glow-override.png"
local editOverlay
local editOverlayTexture = EDIT_GLOW_TEXTURE

-- The glow suppresses itself on excluded contexts (chrome pages + Global
-- Settings General) and returns on normal module pages.
local _overlayWanted = false

ApplyEditOverlay = function()
    if not editOverlay then
        return
    end
    editOverlay:SetShown(_overlayWanted and not IsExcludedContext())
end

local function SetEditOverlayShown(isShown)
    _overlayWanted = isShown and true or false
    if isShown and not editOverlay then
        local rootFrame = _G.CludesUIFrame
        if not rootFrame then
            return
        end
        editOverlay = CreateFrame("Frame", nil, CludesUI._panelBody)
        editOverlay:SetAllPoints(rootFrame)
        editOverlay:SetFrameLevel(rootFrame:GetFrameLevel() + 1)
        editOverlay:EnableMouse(false)
        local texture = editOverlay:CreateTexture(nil, "BACKGROUND")
        texture:SetAllPoints()
        texture:SetTexture(editOverlayTexture)
        editOverlay._tex = texture
    end
    ApplyEditOverlay()
end

TeardownEditSession = function()
    if _watchTicker then
        _watchTicker:Cancel()
        _watchTicker = nil
    end
    _watchSnap = nil
    SetEnterSnap(nil)
    _sessionIgnored = {}
    HideEditBanner()
    SetEditOverlayShown(false)
    UpdateIndicator()
    UpdateEditLocks() -- release threshold/hands-off locks
    RequestGoldWalk() -- clear conflict-red marks back to gold
    -- Unlock the sidebar (session over for either system).
    if CludesUI.RefreshSidebarOverrideLocks then
        CludesUI.RefreshSidebarOverrideLocks()
    end
end
SetTeardownEditSession(TeardownEditSession)

-- Passive override chrome: the Buff Manager page binds to the live fork even
-- WITHOUT an editing session (the prelude auto-activates it), so the session's
-- glow + banner must show there too. A real session owns the chrome outright;
-- this only fills the no-session case and cleans up after itself.
local _bmPassiveChrome = false

function CludesUI.SpecOverrides_UpdateBmPassiveChrome()
    if _editGroup or Cond._edit then
        return
    end -- real session owns chrome
    local kindName = CludesUI.SpecOverrides_BmPageLockInfo() or nil
    local status = L("Buff Manager changes on this page apply only to this override.")
    local nameFn = CludesUI.SpecOverrides_BmActiveInfo
    if not kindName then
        -- Same chrome serves the Debuff Manager page (one page is active at a
        -- time, so the two locks can never both report).
        kindName = CludesUI.SpecOverrides_DmPageLockInfo() or nil
        if kindName then
            status = L("Debuff Manager changes on this page apply only to this override.")
            nameFn = CludesUI.SpecOverrides_DmActiveInfo
        end
    end
    if kindName then
        local name = (nameFn and nameFn()) or "?"
        EnsureEditBanner()
        editBannerText:SetText(string.format(L("Override Active: %s"), name))
        SetEditStatus(status, 1, 1, 0.6)
        if banner._done then
            banner._done:Hide()
        end -- nothing to exit
        banner:Show()
        SetEditOverlayShown(true)
        _bmPassiveChrome = true
    elseif _bmPassiveChrome then
        _bmPassiveChrome = false
        HideEditBanner()
        SetEditOverlayShown(false)
        if banner and banner._done then
            banner._done:Show()
        end
    end
    -- The toolbar glyph's lock state tracks the same signal (fork created or
    -- deleted mid-page never goes through a page selection).
    if CludesUI._specOvBtnPageState then
        CludesUI._specOvBtnPageState()
    end
end

-------------------------------------------------------------------------------
--  Default Editing Mode view: while the options panel is open WITHOUT an
--  Editing-as session, the stored DEFAULT values swap into the live paths so
--  the panel always shows and edits the shared baseline, even when the current
--  spec belongs to an override group. Closing the panel (or entering
--  Editing-as) banks default edits and restores the spec's values.
-------------------------------------------------------------------------------
PanelShown = function()
    local rootFrame = _G.CludesUIFrame
    return rootFrame and rootFrame:IsShown() or false
end
SetPanelShown(PanelShown)

EnterDefaultView = function()
    if _defaultView or _editGroup or Cond._edit or _inTransition then
        return
    end
    local storage = GetStore()
    if not storage or #storage == 0 then
        return
    end
    -- Bank the real spec's live edits first, then swap the defaults in.
    CludesUI.SpecOverrides_HarvestCurrent()
    SetDefaultView(true)
    local changedSet = WriteDefaultValues()
    if changedSet then
        RunRefreshers(changedSet)
    end
    -- FORCED rebuild: default values may drive different page structure than
    -- the spec values they replaced.
    CludesUI:RefreshPage(true)
    UpdateIndicator()
end
SetEnterDefaultView(EnterDefaultView)

ExitDefaultView = function(restore)
    if not _defaultView then
        return
    end
    SetDefaultView(false)
    HarvestDefaults()
    if restore ~= false then
        local changedSet = WriteSpecValues(_activeSpec or CurrentSpecID())
        if changedSet then
            RunRefreshers(changedSet)
        end
    end
    UpdateIndicator()
end

--- Steps OUT of the Default view for the duration of a CONDITIONAL flip, and back
--- in afterwards. Returns true when the view was actually suspended (caller must
--- then resume it).
---
--- Why not just refuse the flip: the Dark Mode condition's only inputs (the Colors
--- page's Dark Mode rows, Class Resource Bar aside) live INSIDE the options panel,
--- so its flips are ALWAYS raised with the view up, and only a zone change/roster
--- update/combat end/reload re-drives a deferred flip -- it can stay pending a
--- whole session. While pending, the outgoing conditional stays APPLIED and keeps
--- reporting itself as the applied group, so later banks file plain baseline
--- edits into its map until the flip converges and repaints the untouched
--- defaults over them.
---
--- Suspending mirrors how a SPEC transition uses this view (banks edits, restores
--- canonical live on the way out via OnSpecChanged/HarvestCurrent, SpecOverrides_
--- Apply's tail re-enters). Resuming AFTER the applied pointer advances is
--- load-bearing: EnterDefaultView harvests through HarvestCurrent, which resolves
--- the applied gid, so re-entering first would bank the INCOMING conditional's
--- live values into the OUTGOING group's maps.
function CludesUI.SpecOverrides_SuspendDefaultView()
    if not _defaultView then
        return false
    end
    ExitDefaultView()
    return true
end

function CludesUI.SpecOverrides_ResumeDefaultView()
    if PanelShown() then
        EnterDefaultView()
    end
end

--- noRecheck: this exit is a PREAMBLE inside another operation (entering a
--- different session, a membership/delete rewrite, opening unlock mode, a profile
--- apply) rather than the user finishing, so it must not have a conditional
--- transition wedged into it -- most sharply the unlock and profile paths, where
--- the transition's ApplyUnlock schedules its flush TWO FRAMES out and it would
--- land inside unlock mode's snapshot window, or after a profile swap refilled
--- the live tables. Mirror of Cond.ExitEdit's noRecheck.
ExitGroupEdit = function(noRecheck)
    if not _editGroup then
        return
    end
    WatchTick() -- catch trailing edits from the last sub-tick window
    local group = _editGroup
    SetEditGroup(nil)
    SweepUncaptured(group)
    HarvestGroup(group)
    TeardownEditSession()
    local changedSet = WriteSpecValues(_activeSpec or CurrentSpecID())
    if changedSet then
        RunRefreshers(changedSet)
    end
    -- FORCED rebuild: restored values can change page STRUCTURE (sections
    -- shown/hidden by a visibility dropdown); the fast refresh only re-reads
    -- widget values and would leave stale structure on screen.
    CludesUI:RefreshPage(true)
    RequestGoldWalk()
    -- Back to Default Editing Mode: the open panel returns to the baseline.
    if PanelShown() then
        EnterDefaultView()
    end
    -- A condition flip raised mid-session was deferred (the handler bails while
    -- a session holds swapped values live); resolve it now, like ExitEdit.
    if not noRecheck and CludesUI.Conditions_Recheck then
        CludesUI.Conditions_Recheck()
    end
    -- WoW Forever: a group created or deleted while this session was open can
    -- move the spec the class acts as; the user finishing applies it (never a
    -- preamble exit).
    if CludesUI.IS_FOREVER and not noRecheck then
        CludesUI._SO_ForeverConverge()
    end
end
SetExitGroupEdit(ExitGroupEdit)

--- Force-closes every editing-as session (spec group, conditional, Default view).
--- Profile apply/import/switch call this BEFORE swapping stores: the exits bank and
--- restore against the OUTGOING profile, and the post-swap establish
--- (Conditions_MarkStale + Recheck) must never find a live session -- the
--- transition handler refuses under one, stranding the incoming profile
--- un-overlaid until the next zone change.
function CludesUI.SpecOverrides_CloseEditSessions()
    -- Unlock-open window: remember the active session so the post-unlock reopen
    -- restores it. Same stash the panel-hide hook takes, but OpenUnlockMode closes
    -- sessions BEFORE the panel hides (the value snapshot must be taken over
    -- canonical live data), so the hook finds no session and would lose the roundtrip.
    if CludesUI._unlockReturnModule ~= nil then
        if _editGroup then
            _unlockRoundtrip = { kind = "spec", id = _editGroup.id }
        elseif Cond._edit then
            _unlockRoundtrip = { kind = "cond", id = Cond._edit.id }
        end
    end
    if _editGroup and ExitGroupEdit then
        ExitGroupEdit(true)
    end
    -- noRecheck: every caller here drives its own choreography and must NOT have a
    -- conditional transition wedged into it. A deferred flip resolved from this exit
    -- would run ApplyUnlock, whose flush is scheduled TWO FRAMES out; on the profile
    -- apply/switch callers that lands AFTER the live tables are wiped and refilled,
    -- writing the OUTGOING profile's layer geometry into the INCOMING profile's
    -- module stores. Not stranding: the profile paths run Conditions_MarkStale +
    -- Recheck right after the swap, unlock open re-resolves on close, and
    -- PromoteGroupToProfile ends in a ReloadUI.
    if Cond._edit and Cond.ExitEdit then
        Cond.ExitEdit(nil, true)
    end
    if _defaultView and ExitDefaultView then
        ExitDefaultView()
    end
end

EnterGroupEdit = function(set, force)
    if _editGroup == set then
        return
    end
    if not set or not set.specs or #set.specs == 0 then
        return
    end
    -- BM page lock: while the Buff Manager page is bound to a live fork, only
    -- THAT group's session may open from the cards popup; any other context
    -- would edit settings the page is not displaying. force: the manager
    -- sidebar's override list switches directly (the page rebuild rebinds).
    do
        local lockType, lockGroup
        local lockLabel = "Buff Manager"
        if CludesUI.SpecOverrides_BmPageLockInfo then
            lockType, lockGroup = CludesUI.SpecOverrides_BmPageLockInfo()
        end
        if not lockType and CludesUI.SpecOverrides_DmPageLockInfo then
            lockType, lockGroup = CludesUI.SpecOverrides_DmPageLockInfo()
            if lockType then
                lockLabel = "Debuff Manager"
            end
        end
        if lockType and not force and not (lockType == "spec" and lockGroup == set.id) then
            CludesUI:ShowConfirmPopup({
                title = string.format(L("%s Override Active"), L(lockLabel)),
                message = string.format(
                    L(
                        "The active override's custom %s is bound to this page. Leave the %s tab to switch to another override."
                    ),
                    L(lockLabel),
                    L(lockLabel)
                ),
                confirmText = L("OK"),
                hideCancel = true,
            })
            return
        end
    end
    -- Preamble teardown, not the user finishing: no conditional recheck (a
    -- deferred flip resolves at the session end that really ends editing).
    if _editGroup then
        ExitGroupEdit(true)
    end
    if Cond.ExitEdit then
        Cond.ExitEdit(nil, true)
    end -- sessions never coexist
    -- Leave the Default view (banks default edits, restores spec values), then
    -- bank the real spec's live edits and swap the group in.
    ExitDefaultView()
    CludesUI.SpecOverrides_HarvestCurrent()
    SetEditGroup(set)
    local changedSet = WriteGroupValues(set)
    if changedSet then
        RunRefreshers(changedSet)
    end
    -- FORCED rebuild (structure may differ under the group's values); runs
    -- before the snapshot so lazy page seeding is absorbed.
    CludesUI:RefreshPage(true)
    _watchSnap = SnapshotProfiles()
    SetEnterSnap(_watchSnap) -- session baseline for the exit sweep
    _sessionIgnored = {}
    _lastAttr.snap, _lastAttr.busy = nil, false
    _watchTicker = C_Timer.NewTicker(0.4, WatchTick)
    ShowEditBanner(set)
    SetEditOverlayShown(true)
    UpdateIndicator()
    UpdateEditLocks()
    RequestGoldWalk()
    EnsurePanelHideHook()
end

-------------------------------------------------------------------------------
--  Editing-as-CONDITIONAL: the same session machinery banking into the
--  conditional store. Mutually exclusive with editing-as-spec and the
--  Default view. Spec-owned fkeys are refused at capture time (spec wins).
-------------------------------------------------------------------------------

--- Banks live values into the edited group's maps. EVERY entry is examined, not just
--- the group's own: an fkey first overridden by another conditional lives in THAT
--- group's entry, and this session's edit to it must still bank here (entry.group is
--- card bookkeeping, not harvest ownership; the spec side harvests the whole store
--- the same way). Per fkey: live equal to the recorded default clears the group's
--- override, anything else banks; empty maps drop so cards only list entries the
--- group actually customizes.
function Cond.HarvestEdit(group)
    for _, record in ipairs(Cond.GetStore() or {}) do
        if record.values and record.values.default then
            local map = record.values[group.id]
            for fieldKey, dv in pairs(record.values.default) do
                local live = ReadLive(fieldKey)
                -- Table-typed live: structure change, never bank (aliasing).
                -- FKeyLoaded: a disabled module reads nil, never bank that.
                -- MatchOwnedFKey: match-engine writes never bank (mirrors the
                -- spec-side Harvest); the held value stays as-is.
                if FKeyLoaded(fieldKey) and type(live) ~= "table" and not MatchOwnedFKey(fieldKey) then
                    local defVal = dv
                    if defVal == NIL_SENT then
                        defVal = nil
                    end
                    if live == defVal then
                        -- Equal to the default: a REVERT only if this session
                        -- moved it there. An untouched key that merely compares
                        -- equal (the default was edited onto the group's value)
                        -- keeps its held value instead of dissolving.
                        local s = _enterSnap and SnapValue(_enterSnap, fieldKey)
                        if type(s) == "table" then
                            s = nil
                        end
                        if map and _enterSnap and s ~= live then
                            map[fieldKey] = nil
                        end
                    else
                        if not map then
                            map = {}
                            record.values[group.id] = map
                        end
                        map[fieldKey] = (live == nil) and NIL_SENT or live
                    end
                end
            end
            if map and not next(map) then
                record.values[group.id] = nil
            end
        end
    end
    Cond.PruneRedundant()
end

--- Exit sweep: uncaptured session diffs become new conditional entries
--- (mirror of SweepUncaptured with conditional ownership rules).
function Cond.SweepUncapturedEdit(group)
    if not _enterSnap or not group then
        return
    end
    local storage = Cond.GetStore(true)
    if not storage then
        return
    end
    local added = false
    for _, change in ipairs(DiffProfiles(_enterSnap)) do
        -- Spec ownership does NOT block cond capture (coexistence: each store
        -- keeps its own value; spec wins only at runtime). MatchOwnedFKey:
        -- never mint from a match engine write (see SweepUncaptured).
        if
            not Cond.EntryOwning(change.fkey)
            and (not change.num or NumAllowedFKey(change.fkey))
            and not BlacklistedFKey(change.fkey)
            and not MatchOwnedFKey(change.fkey)
            and not _sessionIgnored[change.fkey]
        then
            local original = SnapValue(_enterSnap, change.fkey)
            if type(original) == "table" then
                original = nil
            end
            local record = {
                label = PrettyKey(change.fkey),
                crumb = (CludesUI:GetModuleTitle(change.folder)) or change.folder,
                module = change.folder,
                group = group.id,
                values = { default = { [change.fkey] = (original == nil) and NIL_SENT or original } },
            }
            storage[#storage + 1] = record
            added = true
        end
    end
    if added then
        Cond.RebuildIndex()
    end
end

--- noRestore: a spec transition is taking over. Even then the SPEC layer is written
--- back first -- the session swapped shared defaults over the spec-owned fkeys, and
--- the transition's Harvest(oldSpec) must bank real spec values, never the
--- session's default baseline. noRecheck: the caller drives its own choreography
--- and must not have a conditional transition interleaved (see CloseEditSessions).
Cond.ExitEdit = function(noRestore, noRecheck)
    if not Cond._edit then
        return
    end
    WatchTick() -- catch trailing edits from the last sub-tick window
    -- Release the Buff Manager session swap FIRST: banks the session's BM edits
    -- into the group's fork while live still holds them, then puts the runtime
    -- layer back (skipped on noRestore: the transition's ApplyBm does it).
    CludesUI.SpecOverrides_BmSessionRelease(noRestore and true or false)
    CludesUI.SpecOverrides_DmSessionRelease(noRestore and true or false)
    local group = Cond._edit
    Cond._edit = nil
    Cond.SweepUncapturedEdit(group)
    Cond.HarvestEdit(group)
    TeardownEditSession()
    local changedSet = WriteSpecValues(_activeSpec or CurrentSpecID())
    if not noRestore then
        -- Canonical live = spec values + the APPLIED conditional's overlay.
        local t2 =
            Cond.WriteValues(CludesUI.Conditions_AppliedGid and CludesUI.Conditions_AppliedGid() or nil)
        if t2 then
            changedSet = changedSet or {}
            for k in pairs(t2) do
                changedSet[k] = true
            end
        end
        if changedSet then
            RunRefreshers(changedSet)
        end
        -- FORCED rebuild: see ExitGroupEdit (stale structure otherwise).
        CludesUI:RefreshPage(true)
        RequestGoldWalk()
        if PanelShown() then
            EnterDefaultView()
        end
        -- A mid-session condition flip was deferred (the transition handler
        -- bails during edit sessions); resolve it now.
        if not noRecheck and CludesUI.Conditions_Recheck then
            CludesUI.Conditions_Recheck()
        end
        -- WoW Forever: a group created or deleted while this session was open
        -- can move the spec the class acts as; the user finishing applies it.
        -- Only with the panel shown: the panel-hide hook also ends this session
        -- when a Customize Unlock Mode click hides the panel, and unlock mode
        -- opens before an apply's layer flush lands.
        if CludesUI.IS_FOREVER and not noRecheck and PanelShown() then
            CludesUI._SO_ForeverConverge()
        end
    else
        -- The transition re-applies only the spec layer, and its conditional
        -- recheck is a no-op while the applied group holds: put the applied
        -- overlay back over the session's values here (spec-owned fkeys skip).
        local t2 =
            Cond.WriteValues(CludesUI.Conditions_AppliedGid and CludesUI.Conditions_AppliedGid() or nil)
        if t2 then
            RunRefreshers(t2)
        end
    end
    if Cond.RefreshCards then
        Cond.RefreshCards()
    end
end

Cond.EnterEdit = function(group, force)
    if Cond._edit == group then
        return
    end
    if not group then
        return
    end
    -- BM page lock: while the Buff Manager page is bound to a live fork, only
    -- that fork's own conditional session may open; anything else would edit
    -- settings the page is not displaying. force: as in EnterGroupEdit.
    do
        local lockType, lockGroup
        local lockLabel = "Buff Manager"
        if CludesUI.SpecOverrides_BmPageLockInfo then
            lockType, lockGroup = CludesUI.SpecOverrides_BmPageLockInfo()
        end
        if not lockType and CludesUI.SpecOverrides_DmPageLockInfo then
            lockType, lockGroup = CludesUI.SpecOverrides_DmPageLockInfo()
            if lockType then
                lockLabel = "Debuff Manager"
            end
        end
        if lockType and not force and not (lockType == "cond" and lockGroup == group.id) then
            CludesUI:ShowConfirmPopup({
                title = string.format(L("%s Override Active"), L(lockLabel)),
                message = string.format(
                    L(
                        "The active override's custom %s is bound to this page. Leave the %s tab to switch to another override."
                    ),
                    L(lockLabel),
                    L(lockLabel)
                ),
                confirmText = L("OK"),
                hideCancel = true,
            })
            return
        end
    end
    -- Preamble teardown, not the user finishing: no conditional recheck (a
    -- deferred flip resolves at the session end that really ends editing).
    if Cond._edit then
        Cond.ExitEdit(nil, true)
    end
    if _editGroup then
        ExitGroupEdit(true)
    end
    -- The session's baseline is the SHARED DEFAULT view: a conditional layers on the
    -- defaults, so a fresh one must look exactly like "no overrides", never like the
    -- current spec's override view. Spec values only win at APPLY time; while editing a
    -- conditional the panel shows conditional-over-default.
    local changedSet
    if _defaultView then
        -- Panel already shows the defaults; bank its edits and keep them live
        -- (no spec restore) -- that IS our baseline.
        ExitDefaultView(false)
    else
        CludesUI.SpecOverrides_HarvestCurrent()
        changedSet = WriteDefaultValues()
    end
    Cond._edit = group
    local t2 = Cond.WriteValues(group.id, true)
    if t2 then
        changedSet = changedSet or {}
        for k in pairs(t2) do
            changedSet[k] = true
        end
    end
    if changedSet then
        RunRefreshers(changedSet)
    end
    -- FORCED rebuild (structure may differ under the conditional's values).
    CludesUI:RefreshPage(true)
    _watchSnap = SnapshotProfiles()
    SetEnterSnap(_watchSnap)
    _sessionIgnored = {}
    _lastAttr.snap, _lastAttr.busy = nil, false
    _watchTicker = C_Timer.NewTicker(0.4, WatchTick)
    ShowEditBanner(group)
    SetEditStatus(L("Any setting you change now applies only while this conditional is active."), 1, 1, 0.6)
    SetEditOverlayShown(true)
    UpdateIndicator()
    UpdateEditLocks()
    RequestGoldWalk()
    EnsurePanelHideHook()
end

Inner.EnsurePanelHideHook, Inner.EnterGroupEdit = EnsurePanelHideHook, EnterGroupEdit
Inner.BuildEntryCrumb = BuildEntryCrumb
Inner.ExitGroupEdit, Inner.OnPageRebuilt = ExitGroupEdit, OnPageRebuilt
Inner.broken = false
