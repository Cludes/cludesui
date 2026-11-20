if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_SpecOverrides_Layers.lua
--
--  Layer harvest and apply, the Buff Manager forks with their session swap
--  and the Debuff Manager forks.
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

local CurrentSpecID, DeepCopy, GetGroups = Inner.CurrentSpecID, Inner.DeepCopy, Inner.GetGroups
local GetProfileRoot, GroupById, L = Inner.GetProfileRoot, Inner.GroupById, Inner.L
local RunRefreshers, ApplyValuesFor = Inner.RunRefreshers, Inner.ApplyValuesFor
local GetUnlockStore, OwnerGid = Inner.GetUnlockStore, Inner.OwnerGid

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
local _inTransition = false
Inner.inTransitionSetters[#Inner.inTransitionSetters + 1] = function(val)
    _inTransition = val
end
local _activeSpec = nil
Inner.activeSpecSetters[#Inner.activeSpecSetters + 1] = function(val)
    _activeSpec = val
end
local ExitGroupEdit
Inner.exitGroupEditSetters[#Inner.exitGroupEditSetters + 1] = function(val)
    ExitGroupEdit = val
end
local RefreshCardsPopup
Inner.refreshCardsSetters[#Inner.refreshCardsSetters + 1] = function(val)
    RefreshCardsPopup = val
end

-------------------------------------------------------------------------------
--  Layer harvest / apply
--
--  A LAYER is the complete unlock layout, captured and applied WHOLESALE:
--    anchors / widthMatch / heightMatch   global unlock link tables, verbatim
--                                         (incl. offsets, growth-edge pins)
--    widthMatchExtra / heightMatchExtra   the matches' extra px, by child key
--    cdmPos / abPos                       raw saved-edge stores incl. the
--                                         tgt* follow baselines
--    cdmGrow / abGrow                     grow directions by bar key
--    elems[key] = {point,relPoint,x,y,w,h} generic registered elements via
--                                         their own loadPosition/getSize
--  No diffs, no per-aspect baselines, no size companions: whatever edited the live
--  layout during play (drags, sliders, value-override applies, match propagation,
--  offset upkeep, blesses), harvest-on-leave records the final live truth into the
--  owning layer and apply-on-enter reproduces it -- convergent by construction.
--  TBB_/TBBG_ keys are excluded (natively spec-scoped / globally shared).
-------------------------------------------------------------------------------

local function LiteProfileOf(folder)
    local valueA = CludesUI.Lite and CludesUI.Lite.GetAddon(folder, true)
    return valueA and valueA.db and valueA.db.profile or nil
end

local function LayerSkipsKey(elemKey)
    if type(elemKey) ~= "string" then
        return true
    end
    if elemKey:sub(1, 4) == "CDM_" or elemKey:sub(1, 4) == "TBB_" or elemKey:sub(1, 5) == "TBBG_" then
        return true
    end
    local abk = CludesUI._abBarKeys
    if abk and abk[elemKey] then
        return true
    end
    -- One spot for every spec (MakeUnlockElement's noSpecLayout).
    local elementList = CludesUI._unlockRegisteredElements
    local element = elementList and elementList[elemKey]
    return (element and element.noSpecLayout) and true or false
end

-- Tracking Bar CHILD-role link entries (key "TBB_<idx>") are per-spec data
-- owned by the CDM link buckets (SyncTBBUnlockLinks): layers never carry them
-- and never wipe them, or an apply would stamp one spec's links onto another
-- spec's bars. Entries where a TBB key is only the TARGET live under the
-- child's key and stay layer-managed like any other element.
local function IsTBBChildKey(elemKey)
    return type(elemKey) == "string" and elemKey:find("^TBB_%d+$") ~= nil
end

-- carry / base: the layer the harvest banks into and the baseline. An element
-- whose size the current look fixes (sizeFixedByLook: Blizzard Style unit
-- frames) reports that look's size, not its own setting, so its size is taken
-- from carry, else base, else its own setting (getSettingSize): every entry
-- keeps a size, since the layer apply treats an entry as owning the key.
local function HarvestLayer(carry, base)
    local layerRec = {
        anchors = DeepCopy(CludesUIDB and CludesUIDB.unlockAnchors or {}),
        widthMatch = DeepCopy(CludesUIDB and CludesUIDB.unlockWidthMatch or {}),
        heightMatch = DeepCopy(CludesUIDB and CludesUIDB.unlockHeightMatch or {}),
        cdmGrow = {},
        abGrow = {},
        elems = {},
    }
    -- Strip TBB child-role entries: per-spec data, not layer data.
    local stripSets = { layerRec.anchors, layerRec.widthMatch, layerRec.heightMatch }
    for idx = 1, 3 do
        local t, kill = stripSets[idx], nil
        for key in pairs(t) do
            if IsTBBChildKey(key) then
                kill = kill or {}
                kill[#kill + 1] = key
            end
        end
        if kill then
            for _, key in ipairs(kill) do
                t[key] = nil
            end
        end
    end
    -- Match extras ride with the links: kept only beside a link this layer
    -- carries (so the TBB child entries stripped above drop out too).
    layerRec.widthMatchExtra, layerRec.heightMatchExtra = {}, {}
    local wx = CludesUIDB and CludesUIDB.unlockWidthMatchExtra
    if wx then
        for key, val in pairs(wx) do
            if layerRec.widthMatch[key] ~= nil then
                layerRec.widthMatchExtra[key] = val
            end
        end
    end
    local hx = CludesUIDB and CludesUIDB.unlockHeightMatchExtra
    if hx then
        for key, val in pairs(hx) do
            if layerRec.heightMatch[key] ~= nil then
                layerRec.heightMatchExtra[key] = val
            end
        end
    end
    local cdmStore = LiteProfileOf("CludesUICooldownManager")
    if cdmStore then
        layerRec.cdmPos = DeepCopy(cdmStore.cdmBarPositions or {})
        if cdmStore.cdmBars and cdmStore.cdmBars.bars then
            for _, barCfg in ipairs(cdmStore.cdmBars.bars) do
                if barCfg.key and barCfg.growDirection then
                    layerRec.cdmGrow[barCfg.key] = barCfg.growDirection
                end
            end
        end
    end
    local ab = LiteProfileOf("CludesUIActionBars")
    if ab then
        layerRec.abPos = DeepCopy(ab.barPositions or {})
        if ab.bars then
            for key, conf in pairs(ab.bars) do
                if type(conf) == "table" and conf.growDirection then
                    layerRec.abGrow[key] = conf.growDirection
                end
            end
        end
    end
    local elementList = CludesUI._unlockRegisteredElements
    if elementList then
        for elemKey, element in pairs(elementList) do
            if not LayerSkipsKey(elemKey) then
                local record
                -- Elements whose STORED position is not the visual one loadPosition
                -- reports (PlayerAuraBars' rounding-shifted bars) expose
                -- loadRawPosition/saveRawPosition: bank that flat table verbatim, so
                -- a layer harvested at one resolution stays valid at another and
                -- keeps the element's own position flags.
                if element.loadRawPosition and element.saveRawPosition then
                    local success, p = pcall(element.loadRawPosition, elemKey)
                    if success and type(p) == "table" and p.point then
                        record = {}
                        for key, val in pairs(p) do
                            if type(val) ~= "table" then
                                record[key] = val
                            end
                        end
                        record.relPoint = record.relPoint or record.point
                        record.rawPos = true
                    end
                elseif element.loadPosition then
                    local success, p = pcall(element.loadPosition, elemKey)
                    if success and p and p.point then
                        record = { point = p.point, relPoint = p.relPoint or p.point, x = p.x, y = p.y }
                    end
                end
                if element.sizeFixedByLook then
                    local wid, hgt
                    for idx = 1, 2 do
                        local source = base
                        if idx == 1 then
                            source = carry
                        end
                        local ce = source and source.elems and source.elems[elemKey]
                        if ce and (ce.w or ce.h) then
                            wid, hgt = ce.w, ce.h
                            break
                        end
                    end
                    if wid == nil and hgt == nil and element.getSettingSize then
                        local success, sw, sh = pcall(element.getSettingSize, elemKey)
                        if success then
                            if type(sw) == "number" and sw > 0 then
                                wid = sw
                            end
                            if type(sh) == "number" and sh > 0 then
                                hgt = sh
                            end
                        end
                    end
                    if wid or hgt then
                        record = record or {}
                        record.w, record.h = wid, hgt
                    end
                elseif element.getSize then
                    local success, wid, hgt = pcall(element.getSize, elemKey)
                    if success then
                        if type(wid) == "number" and wid > 0 then
                            record = record or {}
                            record.w = wid
                        end
                        if type(hgt) == "number" and hgt > 0 then
                            record = record or {}
                            record.h = hgt
                        end
                    end
                end
                if record then
                    layerRec.elems[elemKey] = record
                end
            end
        end
    end
    return layerRec
end

-- Generic-element writes are deferred to the flush: their savePosition/setWidth
-- closures are only re-registered AFTER profile-switch applies, and the flush
-- carries the combat gate. Raw CDM/AB stores go through the stable Lite db
-- objects, so they are always safe to write immediately.
local _unlockDeferredElemLayout = nil
-- Baseline geometry for elements the INCOMING layer has no elems entry for
-- ("missing means baseline, never keep outgoing residue"): stashed by ApplyLayer,
-- applied by the flush after the layer's own entries, consumed per-key so live
-- drift is never re-stomped. Without it a layer missing a key (late registration,
-- fork saved before the element existed) leaves the OUTGOING layer's geometry live
-- and the next harvest bakes that residue into the incoming layer permanently.
local _unlockDeferredElemFallback = nil

-- Anchored children's positions are OWNED by the anchor system: a layer/baseline
-- elem recorded for a currently-anchored key is derived bookkeeping (whatever
-- geometry the anchor produced at harvest time) and must NEVER be painted back
-- through savePosition -- doing so stomps freshly anchor-applied windows and
-- poisons their module-saved positions. Mirrors the ApplyCenterPosition
-- anchored-skip, applied at the flush's write sites.
local function UnlockElemAnchorOwned(elemKey)
    local valueA = CludesUIDB and CludesUIDB.unlockAnchors
    local details = valueA and valueA[elemKey]
    return type(details) == "table" and details.target ~= nil
end
local _unlockSettleWanted = false
local _unlockFlushScheduled = false
local ScheduleUnlockFlush

-- Loose elem-geometry equality (position keywords exact, coordinates and
-- sizes within the flush's 0.5 write tolerance).
local function ElemNear(valueA, b)
    if not valueA or not b then
        return false
    end
    if (valueA.point or false) ~= (b.point or false) then
        return false
    end
    if (valueA.relPoint or valueA.point or false) ~= (b.relPoint or b.point or false) then
        return false
    end
    local function near(posX, posY)
        if posX == nil and posY == nil then
            return true
        end
        if type(posX) ~= "number" or type(posY) ~= "number" then
            return false
        end
        return math.abs(posX - posY) < 0.5
    end
    return near(valueA.x, b.x) and near(valueA.y, b.y) and near(valueA.w, b.w) and near(valueA.h, b.h)
end

-- Exact equality for RAW element positions (loadRawPosition): the element's own
-- stored fields, so a position flag it carries counts as a difference too. The
-- layer's own bookkeeping keys are not part of the position.
local RAW_POS_LAYER_KEYS = { w = true, h = true, rawPos = true, relPoint = true }
local function RawPosEqual(current, record)
    if not current then
        return false
    end
    if (current.relPoint or current.point) ~= (record.relPoint or record.point) then
        return false
    end
    for key, val in pairs(record) do
        if not RAW_POS_LAYER_KEYS[key] and current[key] ~= val then
            return false
        end
    end
    for key, val in pairs(current) do
        if not RAW_POS_LAYER_KEYS[key] and record[key] ~= val then
            return false
        end
    end
    return true
end

--- Writes a layer into the live stores. CRITICAL: the raw CDM/AB position tables
--- are mutated IN PLACE (wipe + refill) -- the owning addons keep mirror references
--- to these exact tables that only refresh on profile applies, so replacing the
--- table identity orphans them on same-profile spec swaps. baseline: the store's
--- baselineLayout when LAYER is a group/conditional fork (nil when applying the
--- baseline itself); every sub-store the layer is missing falls back to it
--- ("missing means baseline, never keep the outgoing layer's residue").
local function ApplyLayer(layerRec, baseLayer)
    if not layerRec then
        return
    end
    if CludesUIDB then
        local anchors = CludesUIDB.unlockAnchors
        if not anchors then
            anchors = {}
            CludesUIDB.unlockAnchors = anchors
        end
        -- Fallback links belong to the child/target pair, not the spec: carry
        -- each over when the arriving layer keeps the same target. TBB child
        -- entries (per-spec, bucket-owned) ride the wipe whole, fallback
        -- included, and layer-borne ones are skipped on refill.
        local fallbacks, tbbKept
        for key, details in pairs(anchors) do
            if IsTBBChildKey(key) then
                tbbKept = tbbKept or {}
                tbbKept[key] = details
            elseif details.fallback then
                fallbacks = fallbacks or {}
                fallbacks[key] = { tgt = details.target, fb = details.fallback }
            end
        end
        wipe(anchors)
        for key, details in pairs(layerRec.anchors or {}) do
            if not IsTBBChildKey(key) then
                anchors[key] = DeepCopy(details)
                local f = fallbacks and fallbacks[key]
                if f and f.tgt == details.target then
                    anchors[key].fallback = f.fb
                end
            end
        end
        if tbbKept then
            for key, details in pairs(tbbKept) do
                anchors[key] = details
            end
        end
        CludesUI._anchorLinksStamp = (CludesUI._anchorLinksStamp or 0) + 1
        local wm = CludesUIDB.unlockWidthMatch
        if not wm then
            wm = {}
            CludesUIDB.unlockWidthMatch = wm
        end
        local wmKept
        for key, val in pairs(wm) do
            if IsTBBChildKey(key) then
                wmKept = wmKept or {}
                wmKept[key] = val
            end
        end
        wipe(wm)
        for key, val in pairs(layerRec.widthMatch or {}) do
            if not IsTBBChildKey(key) then
                wm[key] = val
            end
        end
        if wmKept then
            for key, val in pairs(wmKept) do
                wm[key] = val
            end
        end
        local hm = CludesUIDB.unlockHeightMatch
        if not hm then
            hm = {}
            CludesUIDB.unlockHeightMatch = hm
        end
        local hmKept
        for key, val in pairs(hm) do
            if IsTBBChildKey(key) then
                hmKept = hmKept or {}
                hmKept[key] = val
            end
        end
        wipe(hm)
        for key, val in pairs(layerRec.heightMatch or {}) do
            if not IsTBBChildKey(key) then
                hm[key] = val
            end
        end
        if hmKept then
            for key, val in pairs(hmKept) do
                hm[key] = val
            end
        end
        -- Match extras follow the links above, the same way for both axes: TBB
        -- child entries stay, the rest become the layer's (none when it has none).
        for pass = 1, 2 do
            local field, source = "unlockWidthMatchExtra", layerRec.widthMatchExtra
            if pass == 2 then
                field, source = "unlockHeightMatchExtra", layerRec.heightMatchExtra
            end
            local tbl = CludesUIDB[field]
            local kept
            if tbl then
                for key, val in pairs(tbl) do
                    if IsTBBChildKey(key) then
                        kept = kept or {}
                        kept[key] = val
                    end
                end
                wipe(tbl)
            end
            if type(source) == "table" then
                for key, val in pairs(source) do
                    if not IsTBBChildKey(key) then
                        if not tbl then
                            tbl = {}
                            CludesUIDB[field] = tbl
                        end
                        tbl[key] = val
                    end
                end
            end
            if kept then
                for key, val in pairs(kept) do
                    tbl[key] = val
                end
            end
        end
    end
    local cdmStore = LiteProfileOf("CludesUICooldownManager")
    if cdmStore then
        -- A layer harvested while CDM was disabled has no cdmPos; restore the
        -- baseline's instead of leaving the outgoing layer's positions live
        -- (they would be harvested INTO this layer next).
        local place = layerRec.cdmPos or (baseLayer and baseLayer.cdmPos)
        if place then
            local tbl = cdmStore.cdmBarPositions
            if not tbl then
                tbl = {}
                cdmStore.cdmBarPositions = tbl
            end
            wipe(tbl)
            for key, val in pairs(place) do
                tbl[key] = DeepCopy(val)
            end
            -- Per-bar missing-means-baseline: a layer's cdmPos is a snapshot from its
            -- last harvest, so bars created AFTER it have no entry in older layers and
            -- fall to their DEFAULT (centered) placement at layout time ("CDM centered
            -- on this one spec"). Fill the gaps from the baseline (mirrors the grow-key
            -- rule below); the layer self-heals to full coverage at its next harvest.
            local bpos = baseLayer and baseLayer.cdmPos
            if bpos and bpos ~= place then
                for key, val in pairs(bpos) do
                    if tbl[key] == nil then
                        tbl[key] = DeepCopy(val)
                    end
                end
            end
        end
        if cdmStore.cdmBars and cdmStore.cdmBars.bars then
            -- Grow keys follow missing-means-baseline too. A grow store is AUTHORITATIVE
            -- only when its layer was harvested with CDM loaded (cdmPos present <=>
            -- the harvest's cdm block ran); a layer that never saw CDM knows nothing
            -- about grows. Per bar: layer value, else baseline, else CLEAR (module
            -- default), so one fork's grow can't stick to every other layer.
            local lg = (layerRec.cdmPos ~= nil) and layerRec.cdmGrow or nil
            local backdrop = (baseLayer and baseLayer.cdmPos ~= nil) and baseLayer.cdmGrow or nil
            if lg or backdrop then
                for _, barCfg in ipairs(cdmStore.cdmBars.bars) do
                    if barCfg.key then
                        local gd
                        if lg then
                            gd = lg[barCfg.key]
                        end
                        if gd == nil and backdrop then
                            gd = backdrop[barCfg.key]
                        end
                        barCfg.growDirection = gd
                    end
                end
            end
        end
    end
    local ab = LiteProfileOf("CludesUIActionBars")
    if ab then
        local place = layerRec.abPos or (baseLayer and baseLayer.abPos)
        if place then
            local tbl = ab.barPositions
            if not tbl then
                tbl = {}
                ab.barPositions = tbl
            end
            wipe(tbl)
            for key, val in pairs(place) do
                tbl[key] = DeepCopy(val)
            end
            -- Per-bar missing-means-baseline, same as cdmPos above.
            local bpos = baseLayer and baseLayer.abPos
            if bpos and bpos ~= place then
                for key, val in pairs(bpos) do
                    if tbl[key] == nil then
                        tbl[key] = DeepCopy(val)
                    end
                end
            end
        end
        if ab.bars then
            -- Same authority rule and per-bar fallback as cdmGrow.
            local lg = (layerRec.abPos ~= nil) and layerRec.abGrow or nil
            local backdrop = (baseLayer and baseLayer.abPos ~= nil) and baseLayer.abGrow or nil
            if lg or backdrop then
                for key, conf in pairs(ab.bars) do
                    if type(conf) == "table" then
                        local gd
                        if lg then
                            gd = lg[key]
                        end
                        if gd == nil and backdrop then
                            gd = backdrop[key]
                        end
                        conf.growDirection = gd
                    end
                end
            end
        end
    end
    -- REPLACE the pending map, never merge: it always represents the ACTIVE layer's
    -- intended element state. Anything still unapplied from the previous layer was
    -- already banked back by the transition harvest (which overlays pending intent),
    -- and flushing it under the new layer would cross-contaminate.
    _unlockDeferredElemLayout = nil
    if layerRec.elems and next(layerRec.elems) then
        _unlockDeferredElemLayout = {}
        for elemKey, record in pairs(layerRec.elems) do
            _unlockDeferredElemLayout[elemKey] = DeepCopy(record)
        end
    end
    -- Missing means baseline: elements the incoming layer has no entry for restore
    -- their BASELINE geometry at flush time instead of keeping the outgoing layer's
    -- residue. Replaced wholesale with the pending map; entries consumed as they apply.
    _unlockDeferredElemFallback = nil
    if baseLayer and baseLayer ~= layerRec and baseLayer.elems then
        local fb
        for elemKey, record in pairs(baseLayer.elems) do
            if not (layerRec.elems and layerRec.elems[elemKey] ~= nil) and not LayerSkipsKey(elemKey) then
                fb = fb or {}
                fb[elemKey] = DeepCopy(record)
            end
        end
        _unlockDeferredElemFallback = fb
    end
end

-- ---- apply engine -----------------------------------------------------------

--- Swaps the live unlock layout to the given spec's layer (its owning group's layout,
--- or the baseline). Same-layer arrivals are a no-op: live drift (offset upkeep,
--- blesses) stays live and is banked by the transition harvests. NEVER harvests here
--- -- by apply time the value system has already written the NEW spec's data into
--- module configs, so a harvest here would bank it into the OLD layer (the
--- transition harvest in OnSpecChanged/HarvestCurrent runs while live is still old).
function CludesUI.SpecOverrides_ApplyUnlock(specId, force)
    local store = GetUnlockStore()
    if not store then
        return
    end
    specId = specId or _activeSpec or CurrentSpecID()
    if not specId then
        return
    end
    -- TIER 1: the spec's own group layer. When it exists, conditional layouts
    -- are ignored ENTIRELY for this spec.
    local wanted = OwnerGid(specId)
    local goal
    if wanted then
        goal = store.layouts[wanted]
    else
        -- TIER 2: the applied conditional group's layout (namespaced pointer
        -- "cond:<gid>" -- one pointer, one harvest target, one heal path).
        local condition = CludesUI._CondOv and CludesUI._CondOv.ResolveGid and CludesUI._CondOv.ResolveGid() or nil
        if condition then
            local condStore = CludesUI._CondOv.GetUnlockStore()
            if condStore and condStore.layouts[condition] then
                wanted = "cond:" .. condition
                goal = condStore.layouts[condition]
            end
        end
    end
    if wanted == store.active and not force then
        -- Same-layer arrival: live drift stays live (never re-apply). BUT module
        -- POSITION stores can carry persisted gaps: a layer snapshot missing bars
        -- created after its last harvest leaves them entryless (default centered
        -- placement), and this early-out skips ApplyLayer every same-layer login, so
        -- the gap never heals without a layer transition. ADD-ONLY heal: fill missing
        -- bar keys from the live layer then the baseline; existing entries (live
        -- drift) are never touched, and the settle only runs if something was missing.
        local base = store.baselineLayout
        local function GapFill(profileTbl, storeKey, layerPos, basePos)
            if not profileTbl then
                return false
            end
            local tbl = profileTbl[storeKey]
            if not tbl then
                tbl = {}
                profileTbl[storeKey] = tbl
            end
            local added = false
            if layerPos then
                for key, val in pairs(layerPos) do
                    if tbl[key] == nil then
                        tbl[key] = DeepCopy(val)
                        added = true
                    end
                end
            end
            if basePos and basePos ~= layerPos then
                for key, val in pairs(basePos) do
                    if tbl[key] == nil then
                        tbl[key] = DeepCopy(val)
                        added = true
                    end
                end
            end
            return added
        end
        local cdmStore = LiteProfileOf("CludesUICooldownManager")
        local ab = LiteProfileOf("CludesUIActionBars")
        local added = GapFill(cdmStore, "cdmBarPositions", goal and goal.cdmPos, base and base.cdmPos)
        if GapFill(ab, "barPositions", goal and goal.abPos, base and base.abPos) then
            added = true
        end
        if added then
            -- Same settle ApplyLayer uses: repositions bars from the now
            -- complete store (the flush self-defers in combat).
            _unlockSettleWanted = true
            ScheduleUnlockFlush()
        end
        return
    end
    -- TIER 3: baseline.
    if not goal then
        goal = store.baselineLayout
    end
    store.active = wanted
    if goal then
        -- Forks fall back to the baseline for every sub-store they are
        -- missing (nil when the target IS the baseline).
        ApplyLayer(goal, goal ~= store.baselineLayout and store.baselineLayout or nil)
        _unlockSettleWanted = true
        ScheduleUnlockFlush()
    end
end

--- Banks the LIVE unlock layout into the layer it belongs to (the active group
--- layer, else the baseline). Runs at every transition boundary while live
--- still belongs to the outgoing state: spec change, profile
--- switch/export/logout, and unlock Save & Exit.
function CludesUI.SpecOverrides_HarvestUnlockLayout(userCommit)
    local store = GetUnlockStore()
    if not store then
        return
    end
    -- Zero-cost for non-users: nothing to bank into until a layer exists.
    local condStore = CludesUI._CondOv and CludesUI._CondOv.GetUnlockStore()
    if
        not store.active
        and not next(store.layouts)
        and not store.baselineLayout
        and not (condStore and next(condStore.layouts))
    then
        return
    end
    -- Mid-establish (a profile apply whose Conditions establish was combat-deferred):
    -- live is MIXED -- baseline links restored over the incoming profile's
    -- layer-valued module data. Banking it anywhere (especially into baselineLayout
    -- via the reset active pointer) poisons the store; skip until the pending
    -- establish converges, then banks resume on the next boundary.
    if CludesUI.Conditions_EstablishPending and CludesUI.Conditions_EstablishPending() then
        return
    end
    -- Import window (see ImportProfile): from an imported profile's activation until
    -- the first apply of a LATER session, the store holds the exporter's layers
    -- verbatim while live geometry is mid-import residue (inherited link tables,
    -- unconverged anchors). Banking any boundary in that window (import-tail
    -- Conditions recheck, the reload's PLAYER_LOGOUT, first post-login spec
    -- transition) would wholesale-replace a pristine bucket with that residue.
    -- Fail-open like the guards above: skip; banks resume once the window closes.
    do
        local profileTbl = GetProfileRoot()
        if profileTbl and profileTbl._importEstablishPending then
            if userCommit then
                -- Unlock Save & Exit: a user-committed layout is converged,
                -- live-authoritative state; close the window and bank it.
                profileTbl._importEstablishPending = nil
            else
                return
            end
        end
    end
    -- Reset-pointer window (see SpecOverrides_UnlockResetActive): a profile activation
    -- cleared a live layer pointer while module elem positions still hold that layer's
    -- geometry. Banking before the forced converge lands would file the outgoing
    -- layer's positions into baselineLayout via the nil pointer. Fail-open like the
    -- import window, user-commit bypass included: a Save & Exit layout is
    -- live-authoritative by definition.
    if CludesUI._unlockResetConvergePending then
        if userCommit then
            CludesUI._unlockResetConvergePending = nil
        else
            return
        end
    end
    -- Default Editing Mode / editing-as session: live module sizes are the VIEW's
    -- swapped values, not the active layer's state (value writes resize bars); banking
    -- that geometry poisons the layer bucket. Fail-open: skip, next clean boundary
    -- banks. (_CondOv, not the Cond local: Cond lives in CUI_SpecOverrides_Conditional.lua.)
    if _defaultView or _editGroup or (CludesUI._CondOv and CludesUI._CondOv._edit) then
        return
    end
    -- Resolve the live layer's owning bucket: group layer (numeric active),
    -- conditional layer ("cond:<gid>" active), else baseline.
    local condGroupKey = type(store.active) == "string" and tonumber(store.active:match("^cond:(%d+)$")) or nil
    local condBucket = condGroupKey and condStore and condStore.layouts[condGroupKey] or nil
    local previous
    if condGroupKey then
        previous = condBucket or store.baselineLayout
    else
        previous = store.active and store.layouts[store.active] or store.baselineLayout
    end
    local snapshot = HarvestLayer(previous, store.baselineLayout)
    -- Deferred entries still awaiting their element are the layer's INTENDED state:
    -- live (the shared module store) hasn't caught up, so bank the intent, not the
    -- stale value. Pending BASELINE fallback entries are intent too -- without them a
    -- fast double-swap bakes the OUTGOING layer's still-live residue into this layer.
    if _unlockDeferredElemFallback then
        for elemKey, record in pairs(_unlockDeferredElemFallback) do
            snapshot.elems[elemKey] = DeepCopy(record)
        end
    end
    if _unlockDeferredElemLayout then
        for elemKey, record in pairs(_unlockDeferredElemLayout) do
            snapshot.elems[elemKey] = DeepCopy(record)
        end
    end
    -- Preserve entries for elements not currently registered (conditional /
    -- late registration: party+raid containers, CDM bars mid-rebuild).
    -- Absence from the registry means "unknown right now", never "deleted".
    if previous and previous.elems then
        local elementList = CludesUI._unlockRegisteredElements
        for elemKey, record in pairs(previous.elems) do
            if snapshot.elems[elemKey] == nil and not (elementList and elementList[elemKey]) then
                snapshot.elems[elemKey] = DeepCopy(record)
            end
        end
    end
    -- Bake-in guard for GROUP/COND buckets: a key this layer never carried whose live
    -- geometry still MATCHES the baseline is baseline-FOLLOWING, not a layer edit, and
    -- banking it would freeze the baseline's value into the fork forever
    -- (late-registered elements, forks saved before an element existed). Keys that
    -- differ from the baseline are genuine edits and bank normally; the baseline
    -- bucket itself always banks everything.
    if previous and previous ~= store.baselineLayout and store.baselineLayout and store.baselineLayout.elems then
        local be = store.baselineLayout.elems
        local pe = previous.elems
        for elemKey, record in pairs(snapshot.elems) do
            if (pe == nil or pe[elemKey] == nil) and ElemNear(record, be[elemKey]) then
                snapshot.elems[elemKey] = nil
            end
        end
    end
    if condGroupKey then
        if condBucket then
            condStore.layouts[condGroupKey] = snapshot
        else
            store.baselineLayout = snapshot
            store.active = nil -- heal: the condition layout was deleted
        end
    elseif store.active and store.layouts[store.active] then
        store.layouts[store.active] = snapshot
    else
        store.baselineLayout = snapshot
        store.active = nil -- heal a dangling pointer (layout deleted elsewhere)
    end
end

--- Baseline link tables for profile unlockLayout snapshots: while a group layer
--- is LIVE the snapshot must come from the stored baseline, never the live
--- (group-valued) globals. Returns nil when live IS baseline. The 4th/5th
--- returns are the baseline's match extras (width, height), empty when none.
function CludesUI.SpecOverrides_UnlockBaselineLinks()
    local store = GetUnlockStore()
    if store and store.active and store.baselineLayout then
        return store.baselineLayout.anchors or {},
            store.baselineLayout.widthMatch or {},
            store.baselineLayout.heightMatch or {},
            store.baselineLayout.widthMatchExtra or {},
            store.baselineLayout.heightMatchExtra or {}
    end
    return nil
end

--- Resets the active pointer after a profile-level unlockLayout restore wrote
--- baseline links into the live globals (profile switch/import). The per-spec
--- overlay re-applies the correct layer right after, but only when the incoming
--- spec WANTS a layer: a baseline spec early-outs on want == active == nil while
--- module elem positions still hold the previous session's layer geometry (only
--- LINKS were restored), and the next harvest would bank that geometry into
--- baselineLayout via the freshly nil'd pointer. Clearing a LIVE pointer therefore
--- arms a runtime converge flag: layout banks stay suppressed until one forced
--- apply paints the pointer's truth (consumed in the Apply/ApplyValues tails
--- beside the import converge). Never arms for a pointer that was already nil.
function CludesUI.SpecOverrides_UnlockResetActive(profileRoot)
    local store = profileRoot and profileRoot.specUnlockOverrides
    if not store then
        return
    end
    if store.active ~= nil then
        CludesUI._unlockResetConvergePending = true
    end
    store.active = nil
end

--- Completes a pending unlock-layer apply: performs deferred generic-element
--- writes (safe now that unlock re-registration has run), then runs one settle
--- so the screen reflects the swapped stores. Called from OnSpecSwitchComplete
--- (after CDM's spec rebuild) and from a two-frame fallback timer for paths
--- where that never fires.
function CludesUI.SpecOverrides_FlushUnlock()
    -- Combat defer: both halves reposition SECURE unit frames (savePosition closures
    -- re-anchor boss chains; the settle SetPoints unit buttons), blocked in lockdown as
    -- ADDON_ACTION_BLOCKED. Hold ALL pending state untouched and re-run once at
    -- PLAYER_REGEN_ENABLED (the settle is idempotent, only measures post-rebuild geometry).
    if InCombatLockdown() then
        _unlockFlushScheduled = true -- keeps ScheduleUnlockFlush deduped
        CludesUI.CombatQueue.Defer("SpecOverridesFlushUnlock", function()
            if _unlockFlushScheduled then
                CludesUI.SpecOverrides_FlushUnlock()
            end
        end)
        return
    end
    _unlockFlushScheduled = false
    local pend = _unlockDeferredElemLayout
    _unlockDeferredElemLayout = nil
    local keep
    local wroteLayerSizes = false
    if pend then
        -- Sanctioned-write flag: several modules (Unit Frames, ABR) gate their
        -- setWidth/setHeight writes on unlock mode being active; the layer flush
        -- restores sizes OUTSIDE unlock mode and must pass those gates or the
        -- restore silently no-ops ("matched width bleeds to the default layout").
        CludesUI._unlockLayerApplying = true
        local elementList = CludesUI._unlockRegisteredElements
        for elemKey, record in pairs(pend) do
            local element = elementList and elementList[elemKey]
            if not element then
                -- Conditional/late registration (party+raid containers, CDM
                -- bars mid-rebuild): hold the entry; RegisterUnlockElements
                -- pokes a re-flush the moment the element appears.
                keep = keep or {}
                keep[elemKey] = record
            end
            -- A layer saved before its element took noSpecLayout keeps an
            -- entry nothing restores.
            if element and not element.noSpecLayout then
                -- Value-equal guards throughout: the arriving layer matches
                -- live for most elements; only real deltas write and settle.
                -- Anchor-owned keys never take elem positions (see
                -- UnlockElemAnchorOwned): the anchor is the authority.
                -- Raw-position elements take their stored table back verbatim,
                -- flags included (see the harvest).
                if record.rawPos and element.saveRawPosition and not UnlockElemAnchorOwned(elemKey) then
                    if not RawPosEqual(element.loadRawPosition and element.loadRawPosition(elemKey), record) then
                        pcall(element.saveRawPosition, elemKey, record)
                        if element.applyPosition then
                            pcall(element.applyPosition, elemKey)
                        end
                        _unlockSettleWanted = true
                    end
                elseif record.point and element.savePosition and not UnlockElemAnchorOwned(elemKey) then
                    local current = element.loadPosition and element.loadPosition(elemKey)
                    if
                        not (
                            current
                            and current.point == record.point
                            and (current.relPoint or current.point) == (record.relPoint or record.point)
                            and current.x == record.x
                            and current.y == record.y
                        )
                    then
                        pcall(element.savePosition, elemKey, record.point, record.relPoint or record.point, record.x, record.y)
                        -- Re-anchor through the element's OWN authority: noInitHook
                        -- elements (the RF raid container) are skipped by the settle's
                        -- saved-positions loop, so without this the DB gets the layer's
                        -- position but the frame stays where module init anchored it
                        -- from the PRE-flush value (login-only stale-layout visual).
                        if element.applyPosition then
                            pcall(element.applyPosition, elemKey)
                        end
                        _unlockSettleWanted = true
                    end
                end
                -- A size the current look fixes (sizeFixedByLook) is never
                -- written: its setters refuse it under that look anyway.
                local curW, curH
                if element.getSize then
                    curW, curH = element.getSize(elemKey)
                end
                if
                    record.w
                    and element.setWidth
                    and not element.sizeFixedByLook
                    and not (curW and math.abs(curW - record.w) < 0.5)
                then
                    pcall(element.setWidth, elemKey, record.w)
                    _unlockSettleWanted = true
                    wroteLayerSizes = true
                end
                if
                    record.h
                    and element.setHeight
                    and not element.sizeFixedByLook
                    and not (curH and math.abs(curH - record.h) < 0.5)
                then
                    pcall(element.setHeight, elemKey, record.h)
                    _unlockSettleWanted = true
                    wroteLayerSizes = true
                end
            end
        end
        CludesUI._unlockLayerApplying = nil
    end
    if keep then
        _unlockDeferredElemLayout = keep
    end
    -- Missing means baseline: elements the incoming layer carried no entry for
    -- restore their BASELINE geometry (stashed by ApplyLayer). The layer's own
    -- entries always win (pend/keep); each fallback entry is CONSUMED once applied
    -- so later flushes never stomp live drift, and still-unregistered elements are
    -- retained for the registration poke like kept pend entries.
    if _unlockDeferredElemFallback then
        local fb = _unlockDeferredElemFallback
        local elementList = CludesUI._unlockRegisteredElements
        CludesUI._unlockLayerApplying = true
        for elemKey, record in pairs(fb) do
            if (pend and pend[elemKey] ~= nil) or (keep and keep[elemKey] ~= nil) then
                fb[elemKey] = nil -- the layer owns this key
            elseif elementList and elementList[elemKey] and elementList[elemKey].noSpecLayout then
                fb[elemKey] = nil -- no layer restores it (see the pend path)
            elseif elementList and elementList[elemKey] then
                local element = elementList[elemKey]
                -- Same anchor-owned skip as the pend path above.
                -- Same raw-position branch as the pend path above.
                if record.rawPos and element.saveRawPosition and not UnlockElemAnchorOwned(elemKey) then
                    if not RawPosEqual(element.loadRawPosition and element.loadRawPosition(elemKey), record) then
                        pcall(element.saveRawPosition, elemKey, record)
                        if element.applyPosition then
                            pcall(element.applyPosition, elemKey)
                        end
                        _unlockSettleWanted = true
                    end
                elseif record.point and element.savePosition and not UnlockElemAnchorOwned(elemKey) then
                    local current = element.loadPosition and element.loadPosition(elemKey)
                    if
                        not (
                            current
                            and current.point == record.point
                            and (current.relPoint or current.point) == (record.relPoint or record.point)
                            and current.x == record.x
                            and current.y == record.y
                        )
                    then
                        pcall(element.savePosition, elemKey, record.point, record.relPoint or record.point, record.x, record.y)
                        -- Same authority re-anchor as the pend path above
                        -- (the settle never moves noInitHook elements).
                        if element.applyPosition then
                            pcall(element.applyPosition, elemKey)
                        end
                        _unlockSettleWanted = true
                    end
                end
                -- A size the current look fixes (sizeFixedByLook) is never
                -- written: its setters refuse it under that look anyway.
                local curW, curH
                if element.getSize then
                    curW, curH = element.getSize(elemKey)
                end
                if
                    record.w
                    and element.setWidth
                    and not element.sizeFixedByLook
                    and not (curW and math.abs(curW - record.w) < 0.5)
                then
                    pcall(element.setWidth, elemKey, record.w)
                    _unlockSettleWanted = true
                    wroteLayerSizes = true
                end
                if
                    record.h
                    and element.setHeight
                    and not element.sizeFixedByLook
                    and not (curH and math.abs(curH - record.h) < 0.5)
                then
                    pcall(element.setHeight, elemKey, record.h)
                    _unlockSettleWanted = true
                    wroteLayerSizes = true
                end
                fb[elemKey] = nil -- applied once; live drift owns it from here
            end
        end
        CludesUI._unlockLayerApplying = nil
        if not next(fb) then
            _unlockDeferredElemFallback = nil
        end
    end
    -- Element sizes live in MODULE settings (the same keys the value system
    -- captures), so a layer size stamp can overwrite a per-spec or Default view value
    -- applied before this deferred flush ran -- the flush runs last and would win,
    -- banking a value-overridden size into the shared baseline layer and stamping it
    -- onto specs that never had it. Re-run the value overlay so captured settings
    -- win (the layer's own store self-heals at its next harvest); runs BEFORE the
    -- settle so an active width/height match still owns matched sizes, and skips
    -- mid-transition (that apply is imminent).
    if wroteLayerSizes and not _inTransition then
        local touched = ApplyValuesFor(_activeSpec or CurrentSpecID())
        if CludesUI._CondOv then
            local t2 = CludesUI._CondOv.ApplyValues()
            if t2 then
                touched = touched or {}
                for key in pairs(t2) do
                    touched[key] = true
                end
            end
        end
        if touched then
            RunRefreshers(touched)
        end
    end
    if not _unlockSettleWanted then
        return
    end
    -- Never fight an open unlock session; its own save/close flows settle.
    if CludesUI._unlockModeActive then
        return
    end
    _unlockSettleWanted = false
    if CludesUI.ApplyAllWidthHeightMatches then
        pcall(CludesUI.ApplyAllWidthHeightMatches)
    end
    if CludesUI._applySavedPositions then
        pcall(CludesUI._applySavedPositions)
    end
    if CludesUI.ResyncAnchorOffsets then
        pcall(CludesUI.ResyncAnchorOffsets)
    end
    if CludesUI.ReapplyAllUnlockAnchorsForced then
        CludesUI._reapplyForceEdgePreserve = true
        pcall(CludesUI.ReapplyAllUnlockAnchorsForced)
        CludesUI._reapplyForceEdgePreserve = false
    end
end

ScheduleUnlockFlush = function()
    if _unlockFlushScheduled then
        return
    end
    _unlockFlushScheduled = true
    -- Two frames: a profile-switch RefreshAllAddons finishes its child applies
    -- and unlock re-registration first. The CDM spec-rebuild path also flushes
    -- from OnSpecSwitchComplete; whichever runs first wins, the other no-ops.
    C_Timer.After(0, function()
        C_Timer.After(0, function()
            if _unlockFlushScheduled then
                CludesUI.SpecOverrides_FlushUnlock()
            end
        end)
    end)
end

--- Re-flush poke from RegisterUnlockElements: deferred layer writes whose
--- elements were missing become applicable the moment they register. The
--- schedule is deduped, so a registration burst costs one flush.
function CludesUI.SpecOverrides_UnlockPokeFlush()
    if
        (_unlockDeferredElemLayout and next(_unlockDeferredElemLayout))
        or (_unlockDeferredElemFallback and next(_unlockDeferredElemFallback))
    then
        ScheduleUnlockFlush()
    end
end

-- ---- layer management ---------------------------------------------------------

--- Deletes a group's custom unlock layout. When it is the ACTIVE layer, the
--- baseline layout is applied back to live.
function CludesUI.SpecOverrides_RemoveUnlockLayout(groupKeyId)
    local store = GetUnlockStore()
    if not store or store.layouts[groupKeyId] == nil then
        return false
    end
    store.layouts[groupKeyId] = nil
    if store.active == groupKeyId then
        store.active = nil
        if store.baselineLayout then
            ApplyLayer(store.baselineLayout)
            _unlockSettleWanted = true
            CludesUI.SpecOverrides_FlushUnlock()
        end
    end
    return true
end

-- ---- conditional unlock layouts (engine in CludesUI_Conditions.lua) -------

--- Deletes a conditional group's custom unlock layout; when live, the
--- baseline layout is applied back. Mirrors SpecOverrides_RemoveUnlockLayout.
function CludesUI.Conditions_RemoveUnlockLayout(condGroupKey)
    local condStore = CludesUI._CondOv and CludesUI._CondOv.GetUnlockStore()
    if not condStore or condStore.layouts[condGroupKey] == nil then
        return false
    end
    condStore.layouts[condGroupKey] = nil
    local store = GetUnlockStore()
    if store and store.active == ("cond:" .. condGroupKey) then
        store.active = nil
        if store.baselineLayout then
            ApplyLayer(store.baselineLayout)
            _unlockSettleWanted = true
            CludesUI.SpecOverrides_FlushUnlock()
        end
    end
    return true
end

-------------------------------------------------------------------------------
--  Buff Manager forks (Raid Frames "Buff Manager" tab): the unlock LAYER model
--  applied to the BM settings subtree. A BM LAYER is the complete subtree,
--  captured and applied WHOLESALE as deep copies:
--    indicators (bmIndicators), simple (bmSimple),
--    displayMode (bmDisplayMode, resolved), iconZoom (bmIconZoom, resolved).
--  Opt-in per override group via the full-page overlay on the BM tab during an
--  editing session. Harvest-on-leave / apply-on-enter at the SAME boundaries as
--  unlock layers; spec groups win over conditionals; establish transitions
--  apply without harvesting. Stores are profile-root siblings of the unlock
--  stores: specBmOverrides { layouts, baselineLayout, active } and
--  condBmOverrides { layouts }.
-------------------------------------------------------------------------------

local function GetBmStore(create)
    local profileTbl = GetProfileRoot()
    if not profileTbl then
        return nil
    end
    local store = profileTbl.specBmOverrides
    if not store then
        if not create then
            return nil
        end
        store = {}
        profileTbl.specBmOverrides = store
    end
    store.layouts = store.layouts or {}
    -- WoW Forever: the one-time buff clear of the fork stores, before anything
    -- banks into or applies from them ("fvBuffWipe" is its frozen mark,
    -- CludesUI_Migration.lua). A marked store costs one field read.
    local fv = CludesUI.FvBW
    if fv and store.fvBuffWipe == nil then
        fv.BmForks(profileTbl)
    end
    return store
end

local function GetCondBmStore(create)
    local profileTbl = GetProfileRoot()
    if not profileTbl then
        return nil
    end
    local store = profileTbl.condBmOverrides
    if not store then
        if not create then
            return nil
        end
        store = {}
        profileTbl.condBmOverrides = store
    end
    store.layouts = store.layouts or {}
    -- WoW Forever: the one-time buff clear of the fork stores (see GetBmStore).
    local fv = CludesUI.FvBW
    if fv and store.fvBuffWipe == nil then
        fv.BmForks(profileTbl)
    end
    return store
end

--- Deterministic BM owner for a spec (first group in creation order with a BM
--- layer containing the spec). Independent of unlock ownership: a group can
--- fork one system without the other.
local function BmOwnerGid(specId)
    if not specId then
        return nil
    end
    local store = GetBmStore()
    if not store or not next(store.layouts) then
        return nil
    end
    for _, groupRec in ipairs(GetGroups() or {}) do
        if store.layouts[groupRec.id] then
            for _, spellRef in ipairs(groupRec.specs or {}) do
                if spellRef == specId then
                    return groupRec.id
                end
            end
        end
    end
    return nil
end

--- Builds a BM layer from the live RF profile. nil when RF's profile is absent
--- or never initialized -- never bank an empty layer over a stored one. The v2
--- payload (bm2 spec forks) rides the same layer; 12.1-born profiles may have
--- no legacy bmIndicators table at all, so either subtree qualifies the snap.
local function BmHarvestLayer()
    local rf = LiteProfileOf("CludesUIRaidFrames")
    if not rf then
        return nil
    end
    local fork = _G._CURF_BM2HarvestFork and _G._CURF_BM2HarvestFork() or nil
    if type(rf.bmIndicators) ~= "table" and not fork then
        return nil
    end
    return {
        indicators = DeepCopy(rf.bmIndicators or {}),
        simple = DeepCopy(rf.bmSimple or {}),
        displayMode = rf.bmDisplayMode or "custom",
        iconZoom = rf.bmIconZoom or 0.08,
        bm2 = fork,
    }
end

--- Writes a BM layer into the live RF profile IN PLACE (wipe + refill: RF's
--- ns.db.profile IS this table and open BM pages capture subtable references)
--- and runs the BM-only refresh. Nothing here touches secure frames, so no
--- combat deferral is needed. noPageRefresh: skip the options-page repaint
--- (callers running DURING a page build repaint themselves; a nested
--- RefreshPage would rebuild inside a rebuild). Returns true only when the
--- paint actually LANDED -- callers gate pointer moves on it.
local function BmApplyLayer(layerRec, skipPageRefresh)
    if not layerRec then
        return false
    end
    local rf = LiteProfileOf("CludesUIRaidFrames")
    if not rf then
        return false
    end
    local ind = rf.bmIndicators
    if type(ind) ~= "table" then
        ind = {}
        rf.bmIndicators = ind
    end
    wipe(ind)
    for key, val in pairs(layerRec.indicators or {}) do
        ind[key] = DeepCopy(val)
    end
    local simple = rf.bmSimple
    if type(simple) ~= "table" then
        simple = {}
        rf.bmSimple = simple
    end
    wipe(simple)
    for key, val in pairs(layerRec.simple or {}) do
        simple[key] = type(val) == "table" and DeepCopy(val) or val
    end
    rf.bmDisplayMode = layerRec.displayMode or "custom"
    rf.bmIconZoom = layerRec.iconZoom or 0.08
    -- v2 payload: applied through the BM2 bridge, which also converts
    -- legacy-only layers in place on first touch.
    if _G._CURF_BM2ApplyLayer then
        _G._CURF_BM2ApplyLayer(layerRec)
    end
    if _G._CURF_BMRefresh then
        _G._CURF_BMRefresh(skipPageRefresh)
    end
    return true
end

--- Banks the LIVE Buff Manager into the layer it belongs to (active group
--- layer, conditional layer, else baseline). Runs at every transition boundary
--- while live still belongs to the outgoing state.
function CludesUI.SpecOverrides_HarvestBmLayout()
    local store = GetBmStore()
    if not store then
        return
    end
    -- Zero-cost for non-users: nothing to bank into until a fork exists.
    local condStore = GetCondBmStore()
    if not store.active and not next(store.layouts) and not store.baselineLayout and not (condStore and next(condStore.layouts)) then
        return
    end
    -- Import window: same suppression as HarvestUnlockLayout (the BM forks
    -- arrived verbatim in the same import; live is residue).
    do
        local profileTbl = GetProfileRoot()
        if profileTbl and profileTbl._importEstablishPending then
            return
        end
    end
    local snapshot = BmHarvestLayer()
    if not snapshot then
        return
    end
    -- Editing-as-conditional session swap: while a conditional's fork is
    -- session-applied (edited OUT of its real context), live belongs to THAT
    -- fork, never the runtime pointer's layer. Covers every transition boundary
    -- funneling through here (logout, export, profile switch) without touching
    -- the runtime pointer.
    local sessGid = CludesUI._bmSessionGid
    if sessGid then
        if condStore and condStore.layouts[sessGid] then
            condStore.layouts[sessGid] = snapshot
        end
        return
    end
    local condGroupKey = type(store.active) == "string" and tonumber(store.active:match("^cond:(%d+)$")) or nil
    if condGroupKey then
        if condStore and condStore.layouts[condGroupKey] then
            condStore.layouts[condGroupKey] = snapshot
        else
            -- Dangling pointer (layout deleted elsewhere): bank to baseline
            -- and heal, mirroring the unlock harvest.
            store.baselineLayout = snapshot
            store.active = nil
        end
    elseif store.active then
        if store.layouts[store.active] then
            store.layouts[store.active] = snapshot
        else
            store.baselineLayout = snapshot
            store.active = nil
        end
    else
        store.baselineLayout = snapshot
    end
end

--- WoW Forever: records the spec a live spec fork serves, the bucket the
--- Raid Frames Buff Manager (dm false) or Debuff Manager (dm true) renders
--- and edits: specID when want is a spec group's id and specID a retail spec
--- of the player's class, else nil. Returns the previous value. Runtime
--- only; callers gate on Forever.
function CludesUI._SO_SetForkSpec(dm, wanted, specId)
    local val = nil
    if
        type(wanted) == "number"
        and specId
        and CludesUI.IsPlayerSpec(specId)
        and CludesUI.RetailSpecName(specId)
    then
        val = specId
    end
    local previous
    if dm then
        previous = CludesUI.SpecOverrides_DmForkSpecID
        CludesUI.SpecOverrides_DmForkSpecID = val
        CludesUI._SO_DmForkSeeded = true
    else
        previous = CludesUI.SpecOverrides_BmForkSpecID
        CludesUI.SpecOverrides_BmForkSpecID = val
        CludesUI._SO_BmForkSeeded = true
    end
    return previous
end

--- WoW Forever: re-drives the aura containers after a fork spec moved with
--- no paint, and rebuilds the open manager page unless noPage (the caller is
--- a page build, or rebuilds the page itself).
function CludesUI._SO_ForkReDrive(dm, noPage)
    if _G._CURF_BMRefresh then
        _G._CURF_BMRefresh(dm or noPage)
    end
    if
        dm
        and not noPage
        and CludesUI:GetActiveModule() == "CludesUIRaidFrames"
        and CludesUI:GetActivePage() == "Debuff Manager"
    then
        CludesUI:RefreshPage(true)
    end
end

--- Swaps the live Buff Manager to the given spec's layer: the owner group's
--- fork, else the applied conditional's fork, else the baseline. Mirrors
--- SpecOverrides_ApplyUnlock (incl. the force flag for establish transitions);
--- NEVER harvests here.
function CludesUI.SpecOverrides_ApplyBm(specId, force, skipPageRefresh)
    local store = GetBmStore()
    if not store then
        -- WoW Forever: no spec fork is live on a profile without the store.
        if CludesUI.IS_FOREVER then
            CludesUI._SO_SetForkSpec(false, nil)
        end
        return
    end
    -- Import window: NO apply may run between the store merge and the post-reload
    -- converge. Pre-reload the child Lite DBs still hold the OUTGOING profile's
    -- tables (the reload IS the switch), so a paint would "land" on the wrong
    -- profile while the pointer moves anyway, stranding imported fork content under
    -- the new pointer for the first harvest to bank over baselineLayout. The
    -- converge clears the flag before its forced apply, the first legal paint.
    do
        local profileTbl = GetProfileRoot()
        if profileTbl and profileTbl._importEstablishPending then
            return
        end
    end
    specId = specId or _activeSpec or CurrentSpecID()
    if not specId then
        return
    end
    local wanted = BmOwnerGid(specId)
    local goal
    if wanted then
        goal = store.layouts[wanted]
    else
        local condition = CludesUI._CondOv and CludesUI._CondOv.ResolveGid and CludesUI._CondOv.ResolveGid() or nil
        if condition then
            local condStore = GetCondBmStore()
            if condStore and condStore.layouts[condition] then
                wanted = "cond:" .. condition
                goal = condStore.layouts[condition]
            end
        end
    end
    -- WoW Forever: publish the spec the wanted layer serves before any paint
    -- (the paint's refresh reads it); with no paint, re-drive the frames and
    -- the open Buff Manager page when it moved. Put back below when the
    -- pointer does not move.
    local prevFallback
    if CludesUI.IS_FOREVER then
        CludesUI._SO_SeedForkSpec(false)
        prevFallback = CludesUI._SO_SetForkSpec(false, wanted, specId)
    end
    if wanted == store.active and not force then
        if CludesUI.IS_FOREVER and prevFallback ~= CludesUI.SpecOverrides_BmForkSpecID then
            CludesUI._SO_ForkReDrive(false, skipPageRefresh)
        end
        return
    end
    if not goal then
        goal = store.baselineLayout
    end
    if goal then
        -- The pointer advances ONLY when the paint lands. A silent no-op apply (RF
        -- store not ready, malformed layer) must never strand live content under the
        -- wrong pointer, or the next harvest banks it into the wrong layer (baseline
        -- overwritten by fork content). Failed applies retry naturally: want ~= active
        -- still holds at the next boundary.
        if BmApplyLayer(goal, skipPageRefresh) then
            store.active = wanted
        end
    elseif store.active == nil then
        -- Virgin store (no baseline banked yet): live IS the baseline, so the
        -- pointer may move without a paint.
        store.active = wanted
    else
        -- A layer is live but there is nothing to paint back (no
        -- baselineLayout): KEEP the old pointer so harvests keep banking live
        -- into the layer it actually holds.
    end
    -- WoW Forever: the pointer did not move, so the spec goes back to the
    -- one the live layer serves.
    if CludesUI.IS_FOREVER and store.active ~= wanted then
        CludesUI.SpecOverrides_BmForkSpecID = type(store.active) == "number" and prevFallback or nil
    end
end

-------------------------------------------------------------------------------
--  BM session swap: unlike unlock layouts (WYSIWYG against real frames), Buff
--  Manager settings need no real-context editing, so an editing-as-conditional
--  session may edit the group's fork ANYWHERE. The fork applies for the session via
--  a RUNTIME-ONLY flag (never persisted: a mid-session reload comes back on the
--  runtime pointer's layer, fail-safe); the session-aware branch in
--  SpecOverrides_HarvestBmLayout routes every mid-session bank into the fork. Spec
--  forks never need this: their member-spec gate guarantees the fork already IS
--  the runtime layer while editing is allowed.
-------------------------------------------------------------------------------

--- Applies the conditional's fork as the session-live BM layer. Idempotent.
local function BmSessionEngage(groupKey)
    if CludesUI._bmSessionGid == groupKey then
        return
    end
    local condStore = GetCondBmStore()
    local layerRec = condStore and condStore.layouts[groupKey]
    if not layerRec then
        return
    end
    -- Flag only on a LANDED paint: a session flag over unswapped live banks
    -- the runtime layer's content into the fork at release.
    if BmApplyLayer(layerRec, true) then -- callers run during a page build
        CludesUI._bmSessionGid = groupKey
    end
end

--- Banks the session's live edits into the fork and restores the runtime
--- layer. noApply: a transition is about to apply the runtime layer itself.
function CludesUI.SpecOverrides_BmSessionRelease(noApply)
    local groupKey = CludesUI._bmSessionGid
    if not groupKey then
        return
    end
    local condStore = GetCondBmStore()
    if condStore and condStore.layouts[groupKey] then
        local snapshot = BmHarvestLayer()
        if snapshot then
            condStore.layouts[groupKey] = snapshot
        end
    end
    CludesUI._bmSessionGid = nil
    if not noApply then
        CludesUI.SpecOverrides_ApplyBm(_activeSpec or CurrentSpecID(), true, true)
    end
end

--- Name of the override group whose Buff Manager fork is LIVE (session-applied
--- conditional first, then the runtime pointer), or nil when live is the
--- baseline. Drives the BM page's "Override Active" label.
function CludesUI.SpecOverrides_BmActiveInfo()
    local groupKey = CludesUI._bmSessionGid
    local isCond = groupKey ~= nil
    if not groupKey then
        local store = GetBmStore()
        local valueA = store and store.active
        if type(valueA) == "string" then
            groupKey = tonumber(valueA:match("^cond:(%d+)$"))
            isCond = true
        elseif type(valueA) == "number" then
            groupKey = valueA
        end
    end
    if not groupKey then
        return nil
    end
    local groupRec
    if isCond then
        groupRec = CludesUI.Conditions_GroupById and CludesUI.Conditions_GroupById(groupKey)
    else
        groupRec = GroupById(groupKey)
    end
    return groupRec and groupRec.name or nil
end

--- kind ("spec"/"cond") + gid of the fork LIVE on the Buff Manager page, or nil
--- when not on that page / live is the baseline. The page is hard-bound to the
--- live fork (the prelude force-activates it), so every consumer (card locks,
--- session-entry blocks, passive chrome) keys off this.
function CludesUI.SpecOverrides_BmPageLockInfo()
    local mod = CludesUI:GetActiveModule()
    if mod ~= "CludesUIRaidFrames" then
        return nil
    end
    local page = CludesUI:GetActivePage()
    if page ~= "Buff Manager" then
        return nil
    end
    if CludesUI._bmSessionGid then
        return "cond", CludesUI._bmSessionGid
    end
    local store = GetBmStore()
    local valueA = store and store.active
    if type(valueA) == "number" then
        return "spec", valueA
    end
    if type(valueA) == "string" then
        local cg = tonumber(valueA:match("^cond:(%d+)$"))
        if cg then
            return "cond", cg
        end
    end
    return nil
end

--- True while the Buff Manager page is bound to a live fork (any kind).
function CludesUI.SpecOverrides_BmPageLocked()
    return CludesUI.SpecOverrides_BmPageLockInfo() ~= nil
end

--- Deletes a group's custom Buff Manager; when it is the ACTIVE layer the
--- baseline is applied back to live.
function CludesUI.SpecOverrides_RemoveBmLayout(groupKeyId)
    local store = GetBmStore()
    if not store or store.layouts[groupKeyId] == nil then
        return false
    end
    store.layouts[groupKeyId] = nil
    if store.active == groupKeyId then
        -- WoW Forever: the baseline serves no fork spec; cleared before the
        -- paint (its refresh reads it), put back when the paint fails.
        local prevFallback
        if CludesUI.IS_FOREVER then
            prevFallback = CludesUI._SO_SetForkSpec(false, nil)
        end
        -- Pointer moves only with a landed paint (or nothing to restore).
        if not store.baselineLayout or BmApplyLayer(store.baselineLayout) then
            store.active = nil
            -- Nothing painted: the frames move to the class's bucket.
            if prevFallback and not store.baselineLayout then
                CludesUI._SO_ForkReDrive(false)
            end
        elseif CludesUI.IS_FOREVER then
            CludesUI.SpecOverrides_BmForkSpecID = prevFallback
        end
    end
    return true
end

--- Conditional twin of SpecOverrides_RemoveBmLayout.
function CludesUI.Conditions_RemoveBmLayout(condGroupKey)
    local condStore = GetCondBmStore()
    if not condStore or condStore.layouts[condGroupKey] == nil then
        return false
    end
    condStore.layouts[condGroupKey] = nil
    local store = GetBmStore()
    if store and store.active == ("cond:" .. condGroupKey) then
        if not store.baselineLayout or BmApplyLayer(store.baselineLayout) then
            store.active = nil
        end
    end
    -- Deleted while session-applied (cards popup is reachable mid-session):
    -- drop the flag and put the runtime layer back, discarding the orphan.
    if CludesUI._bmSessionGid == condGroupKey then
        CludesUI._bmSessionGid = nil
        CludesUI.SpecOverrides_ApplyBm(_activeSpec or CurrentSpecID(), true)
    end
    return true
end

--- Orphan-heal for a stored profile's BM pointer (import/restore path).
--- Deliberately NOT an unconditional reset: BM live data and pointer travel
--- together inside the profile blob (export harvests first), so a consistent
--- foreign pointer converges via the establish force-apply. Only a pointer at a
--- DELETED layout is healed -- nil-ing a consistent pointer makes the next
--- harvest bank fork data into the baseline.
function CludesUI.SpecOverrides_BmResetActive(profileRoot)
    local store = profileRoot and profileRoot.specBmOverrides
    if not store or store.active == nil then
        return
    end
    local valueA = store.active
    if type(valueA) == "string" then
        local groupKey = tonumber(valueA:match("^cond:(%d+)$"))
        local condStore = profileRoot.condBmOverrides
        if not (groupKey and condStore and type(condStore.layouts) == "table" and condStore.layouts[groupKey]) then
            store.active = nil
        end
    elseif not (type(store.layouts) == "table" and store.layouts[valueA]) then
        store.active = nil
    end
end

-------------------------------------------------------------------------------
--  Debuff Manager forks: the BM layer model applied to the RF dmDebuff subtree.
--  A DM LAYER is { dm = deep copy of the profile's dmDebuff table }. Same
--  boundaries and precedence (spec groups beat conditionals), independent
--  opt-in: a group can fork either manager without the other. Stores:
--  specDmOverrides { layouts, baselineLayout, active } and condDmOverrides
--  { layouts }. Live apply/harvest runs through the _CURF_DM* bridges exported
--  by the Debuff Manager file; every call is existence-guarded, so the feature
--  is inert when that file is absent.
-------------------------------------------------------------------------------

local function GetDmStore(create)
    local profileTbl = GetProfileRoot()
    if not profileTbl then
        return nil
    end
    local store = profileTbl.specDmOverrides
    if not store then
        if not create then
            return nil
        end
        store = {}
        profileTbl.specDmOverrides = store
    end
    store.layouts = store.layouts or {}
    return store
end

local function GetCondDmStore(create)
    local profileTbl = GetProfileRoot()
    if not profileTbl then
        return nil
    end
    local store = profileTbl.condDmOverrides
    if not store then
        if not create then
            return nil
        end
        store = {}
        profileTbl.condDmOverrides = store
    end
    store.layouts = store.layouts or {}
    return store
end

--- Deterministic DM owner for a spec (first group in creation order with a
--- DM layer containing the spec). Independent of BM/unlock ownership.
local function DmOwnerGid(specId)
    if not specId then
        return nil
    end
    local store = GetDmStore()
    if not store or not next(store.layouts) then
        return nil
    end
    for _, groupRec in ipairs(GetGroups() or {}) do
        if store.layouts[groupRec.id] then
            for _, spellRef in ipairs(groupRec.specs or {}) do
                if spellRef == specId then
                    return groupRec.id
                end
            end
        end
    end
    return nil
end

--- Builds a DM layer from the live profile via the bridge. nil when the Debuff
--- Manager is unavailable -- never bank an empty layer over a stored one.
local function DmHarvestLayer()
    local dm = _G._CURF_DMHarvestFork and _G._CURF_DMHarvestFork() or nil
    if not dm then
        return nil
    end
    return { dm = dm }
end

--- Writes a DM layer into the live profile through the bridge (wipe + refill in
--- place) and runs the DM-only refresh. Returns true only when the paint landed
--- (pointer moves gate on it).
local function DmApplyLayer(layerRec, skipPageRefresh)
    if not layerRec or not layerRec.dm then
        return false
    end
    if not _G._CURF_DMApplyLayer then
        return false
    end
    return _G._CURF_DMApplyLayer(layerRec.dm, skipPageRefresh) and true or false
end

--- Banks the LIVE Debuff Manager into the layer it belongs to. Runs at every
--- transition boundary while live still belongs to the outgoing state (mirror
--- of SpecOverrides_HarvestBmLayout).
function CludesUI.SpecOverrides_HarvestDmLayout()
    local store = GetDmStore()
    if not store then
        return
    end
    local condStore = GetCondDmStore()
    if not store.active and not next(store.layouts) and not store.baselineLayout and not (condStore and next(condStore.layouts)) then
        return
    end
    do
        local profileTbl = GetProfileRoot()
        if profileTbl and profileTbl._importEstablishPending then
            return
        end
    end
    local snapshot = DmHarvestLayer()
    if not snapshot then
        return
    end
    local sessGid = CludesUI._dmSessionGid
    if sessGid then
        if condStore and condStore.layouts[sessGid] then
            condStore.layouts[sessGid] = snapshot
        end
        return
    end
    local condGroupKey = type(store.active) == "string" and tonumber(store.active:match("^cond:(%d+)$")) or nil
    if condGroupKey then
        if condStore and condStore.layouts[condGroupKey] then
            condStore.layouts[condGroupKey] = snapshot
        else
            store.baselineLayout = snapshot
            store.active = nil
        end
    elseif store.active then
        if store.layouts[store.active] then
            store.layouts[store.active] = snapshot
        else
            store.baselineLayout = snapshot
            store.active = nil
        end
    else
        store.baselineLayout = snapshot
    end
end

--- WoW Forever: publishes a fork spec from the saved pointer at its first
--- read or apply, once per manager (dm true: Debuff Manager) per session.
--- The pointer's fork is already live at login, so the frames build with
--- its bucket before the deferred login apply (and through a /reload in
--- combat, which defers that apply). Latched even when nothing publishes:
--- after it the value moves only through a path that re-drives the frames.
function CludesUI._SO_SeedForkSpec(dm)
    if dm then
        if CludesUI._SO_DmForkSeeded then
            return
        end
    elseif CludesUI._SO_BmForkSeeded then
        return
    end
    local wanted, current, ownerFrame
    local profileTbl = GetProfileRoot()
    if profileTbl and not profileTbl._importEstablishPending then
        local store
        if dm then
            store = GetDmStore()
        else
            store = GetBmStore()
        end
        wanted = store and store.active
    end
    if type(wanted) == "number" then
        current = CurrentSpecID()
        if current then
            if dm then
                ownerFrame = DmOwnerGid(current)
            else
                ownerFrame = BmOwnerGid(current)
            end
        end
    end
    CludesUI._SO_SetForkSpec(dm, ownerFrame == wanted and ownerFrame or nil, current)
end

--- Swaps the live Debuff Manager to the given spec's layer (mirror of
--- SpecOverrides_ApplyBm). NEVER harvests here.
function CludesUI.SpecOverrides_ApplyDm(specId, force, skipPageRefresh)
    local store = GetDmStore()
    if not store then
        -- WoW Forever: no spec fork is live on a profile without the store.
        if CludesUI.IS_FOREVER then
            CludesUI._SO_SetForkSpec(true, nil)
        end
        return
    end
    -- Import window: same suppression as SpecOverrides_ApplyBm (pre-reload
    -- paints land on the outgoing profile's tables).
    do
        local profileTbl = GetProfileRoot()
        if profileTbl and profileTbl._importEstablishPending then
            return
        end
    end
    specId = specId or _activeSpec or CurrentSpecID()
    if not specId then
        return
    end
    local wanted = DmOwnerGid(specId)
    local goal
    if wanted then
        goal = store.layouts[wanted]
    else
        local condition = CludesUI._CondOv and CludesUI._CondOv.ResolveGid and CludesUI._CondOv.ResolveGid() or nil
        if condition then
            local condStore = GetCondDmStore()
            if condStore and condStore.layouts[condition] then
                wanted = "cond:" .. condition
                goal = condStore.layouts[condition]
            end
        end
    end
    -- WoW Forever: publish the spec the wanted layer serves (see the BM
    -- twin); with no paint, re-drive the frames and the open Debuff Manager
    -- page when it moved.
    local prevFallback
    if CludesUI.IS_FOREVER then
        CludesUI._SO_SeedForkSpec(true)
        prevFallback = CludesUI._SO_SetForkSpec(true, wanted, specId)
    end
    if wanted == store.active and not force then
        if CludesUI.IS_FOREVER and prevFallback ~= CludesUI.SpecOverrides_DmForkSpecID then
            CludesUI._SO_ForkReDrive(true, skipPageRefresh)
        end
        return
    end
    if not goal then
        goal = store.baselineLayout
    end
    if goal then
        -- Pointer advances ONLY when the paint lands (see the BM twin: a
        -- silent no-op apply must never strand live content under the wrong
        -- pointer, or the next harvest banks it into the wrong layer).
        if DmApplyLayer(goal, skipPageRefresh) then
            store.active = wanted
        end
    elseif store.active == nil then
        store.active = wanted
    end
    -- WoW Forever: the pointer did not move (see the BM twin).
    if CludesUI.IS_FOREVER and store.active ~= wanted then
        CludesUI.SpecOverrides_DmForkSpecID = type(store.active) == "number" and prevFallback or nil
    end
end

--- Applies the conditional's fork as the session-live DM layer (mirror of
--- BmSessionEngage; runtime-only flag, never persisted).
local function DmSessionEngage(groupKey)
    if CludesUI._dmSessionGid == groupKey then
        return
    end
    local condStore = GetCondDmStore()
    local layerRec = condStore and condStore.layouts[groupKey]
    if not layerRec then
        return
    end
    if DmApplyLayer(layerRec, true) then -- flag only on a landed paint
        CludesUI._dmSessionGid = groupKey
    end
end

--- Banks the session's live edits into the fork and restores the runtime
--- layer. noApply: a transition is about to apply the runtime layer itself.
function CludesUI.SpecOverrides_DmSessionRelease(noApply)
    local groupKey = CludesUI._dmSessionGid
    if not groupKey then
        return
    end
    local condStore = GetCondDmStore()
    if condStore and condStore.layouts[groupKey] then
        local snapshot = DmHarvestLayer()
        if snapshot then
            condStore.layouts[groupKey] = snapshot
        end
    end
    CludesUI._dmSessionGid = nil
    if not noApply then
        CludesUI.SpecOverrides_ApplyDm(_activeSpec or CurrentSpecID(), true, true)
    end
end

--- Name of the override group whose Debuff Manager fork is LIVE, or nil when
--- live is the baseline.
function CludesUI.SpecOverrides_DmActiveInfo()
    local groupKey = CludesUI._dmSessionGid
    local isCond = groupKey ~= nil
    if not groupKey then
        local store = GetDmStore()
        local valueA = store and store.active
        if type(valueA) == "string" then
            groupKey = tonumber(valueA:match("^cond:(%d+)$"))
            isCond = true
        elseif type(valueA) == "number" then
            groupKey = valueA
        end
    end
    if not groupKey then
        return nil
    end
    local groupRec
    if isCond then
        groupRec = CludesUI.Conditions_GroupById and CludesUI.Conditions_GroupById(groupKey)
    else
        groupRec = GroupById(groupKey)
    end
    return groupRec and groupRec.name or nil
end

--- kind + gid of the fork LIVE on the Debuff Manager page, or nil when not
--- on that page / live is the baseline (mirror of BmPageLockInfo).
function CludesUI.SpecOverrides_DmPageLockInfo()
    local mod = CludesUI:GetActiveModule()
    if mod ~= "CludesUIRaidFrames" then
        return nil
    end
    local page = CludesUI:GetActivePage()
    if page ~= "Debuff Manager" then
        return nil
    end
    if CludesUI._dmSessionGid then
        return "cond", CludesUI._dmSessionGid
    end
    local store = GetDmStore()
    local valueA = store and store.active
    if type(valueA) == "number" then
        return "spec", valueA
    end
    if type(valueA) == "string" then
        local cg = tonumber(valueA:match("^cond:(%d+)$"))
        if cg then
            return "cond", cg
        end
    end
    return nil
end

--- True while the Debuff Manager page is bound to a live fork (any kind).
function CludesUI.SpecOverrides_DmPageLocked()
    return CludesUI.SpecOverrides_DmPageLockInfo() ~= nil
end

--- Deletes a group's custom Debuff Manager; when it is the ACTIVE layer the
--- baseline is applied back to live.
function CludesUI.SpecOverrides_RemoveDmLayout(groupKeyId)
    local store = GetDmStore()
    if not store or store.layouts[groupKeyId] == nil then
        return false
    end
    store.layouts[groupKeyId] = nil
    if store.active == groupKeyId then
        -- WoW Forever: the baseline serves no fork spec (see the BM twin).
        local prevFallback
        if CludesUI.IS_FOREVER then
            prevFallback = CludesUI._SO_SetForkSpec(true, nil)
        end
        if not store.baselineLayout or DmApplyLayer(store.baselineLayout) then
            store.active = nil
            -- Nothing painted: the frames and the open Debuff Manager page
            -- move to the class's bucket.
            if prevFallback and not store.baselineLayout then
                CludesUI._SO_ForkReDrive(true)
            end
        elseif CludesUI.IS_FOREVER then
            CludesUI.SpecOverrides_DmForkSpecID = prevFallback
        end
    end
    return true
end

--- Conditional twin of SpecOverrides_RemoveDmLayout.
function CludesUI.Conditions_RemoveDmLayout(condGroupKey)
    local condStore = GetCondDmStore()
    if not condStore or condStore.layouts[condGroupKey] == nil then
        return false
    end
    condStore.layouts[condGroupKey] = nil
    local store = GetDmStore()
    if store and store.active == ("cond:" .. condGroupKey) then
        if not store.baselineLayout or DmApplyLayer(store.baselineLayout) then
            store.active = nil
        end
    end
    if CludesUI._dmSessionGid == condGroupKey then
        CludesUI._dmSessionGid = nil
        CludesUI.SpecOverrides_ApplyDm(_activeSpec or CurrentSpecID(), true)
    end
    return true
end

--- Orphan-heal for a stored profile's DM pointer (import/restore path);
--- same only-heal-dangling policy as SpecOverrides_BmResetActive.
function CludesUI.SpecOverrides_DmResetActive(profileRoot)
    local store = profileRoot and profileRoot.specDmOverrides
    if not store or store.active == nil then
        return
    end
    local valueA = store.active
    if type(valueA) == "string" then
        local groupKey = tonumber(valueA:match("^cond:(%d+)$"))
        local condStore = profileRoot.condDmOverrides
        if not (groupKey and condStore and type(condStore.layouts) == "table" and condStore.layouts[groupKey]) then
            store.active = nil
        end
    elseif not (type(store.layouts) == "table" and store.layouts[valueA]) then
        store.active = nil
    end
end

--- "Customize Unlock Mode" on a CONDITIONAL group card. Only valid while the group
--- is the ACTIVE conditional (WYSIWYG: author the dungeon layout in a dungeon --
--- mirror of "member spec required" for spec groups) and the current spec's own
--- group has NO layout (spec layers void conditionals entirely). First click forks
--- from live (= baseline, since no layer is applied) behind a confirm popup.
function CludesUI.Conditions_EnterUnlockForGroup(groupRec)
    if type(groupRec) == "number" then
        groupRec = CludesUI.Conditions_GroupById(groupRec)
    end
    if not groupRec then
        return
    end
    -- Dark Mode groups are values-only: no unlock layer may ever exist for them
    -- (the card never builds the button; this is the belt guard).
    if groupRec.conds and groupRec.conds.darkmode then
        return
    end
    if CludesUI._unlockModeActive then
        return
    end
    local current = CurrentSpecID()
    if OwnerGid(current) then
        CludesUI:ShowConfirmPopup({
            title = L("Customize Layout Mode"),
            message = L(
                "Your current spec has its own custom layout mode, so conditional layout modes never apply to it. Swap to a spec without one to customize this."
            ),
            confirmText = L("OK"),
            hideCancel = true,
        })
        return
    end
    local activeG = CludesUI.Conditions_ActiveGroup and CludesUI.Conditions_ActiveGroup()
    if not activeG or activeG.id ~= groupRec.id then
        CludesUI:ShowConfirmPopup({
            title = L("Customize Layout Mode"),
            message = L(
                "This conditional is not active right now. Meet one of its conditions first (for example, enter the dungeon) so you can arrange the layout in its real context."
            ),
            confirmText = L("OK"),
            hideCancel = true,
        })
        return
    end
    local condStore = CludesUI._CondOv.GetUnlockStore(true)
    local store = GetUnlockStore(true)
    if not condStore or not store then
        return
    end
    if condStore.layouts[groupRec.id] == nil then
        CludesUI:ShowConfirmPopup({
            title = L("Customize Layout Mode"),
            message = L(
                "This will create a fully unique layout mode for this conditional group. Changes made to your default layout mode will no longer affect it."
            ),
            confirmText = L("Create"),
            cancelText = L("Cancel"),
            onConfirm = function()
                if condStore.layouts[groupRec.id] ~= nil then
                    return
                end
                -- Bank live into its current owner (the baseline: the guards
                -- above ensure no layer is applied), fork it, activate in place
                -- (live is byte-identical to the new layer).
                CludesUI.SpecOverrides_HarvestUnlockLayout()
                -- Virgin-store baseline seed: without it there is nothing to
                -- restore when the condition ends (see the spec fork twin in
                -- SpecOverrides_EnterUnlockForGroup).
                if not store.baselineLayout and not store.active then
                    store.baselineLayout = HarvestLayer()
                end
                condStore.layouts[groupRec.id] = HarvestLayer(store.baselineLayout)
                store.active = "cond:" .. groupRec.id
                CludesUI.Conditions_EnterUnlockForGroup(groupRec)
            end,
        })
        return
    end
    -- Layout exists but is not the live layer yet (fresh login before any
    -- flip): route through the engine so the layer applies first.
    if store.active ~= ("cond:" .. groupRec.id) then
        if CludesUI.Conditions_Recheck then
            CludesUI.Conditions_Recheck()
        end
        if GetUnlockStore().active ~= ("cond:" .. groupRec.id) then
            return
        end
    end
    if _editGroup then
        ExitGroupEdit(true)
    end
    local panelFrame = CludesUI._mainFrame
    if panelFrame and panelFrame:IsShown() then
        panelFrame:Hide()
    end
    C_Timer.After(0, function()
        if CludesUI._openUnlockMode then
            CludesUI._openUnlockMode()
        end
    end)
end

-- ---- special unlock entry ------------------------------------------------------

--- "Customize Unlock Mode" on a group card. Only valid when the current spec is
--- a member (unlock always shows the current spec's layout). The FIRST click is
--- the fork moment and asks for confirmation; afterwards it just opens unlock
--- mode, which edits the group's (active) layer.
function CludesUI.SpecOverrides_EnterUnlockForGroup(groupRec)
    if type(groupRec) == "number" then
        groupRec = GroupById(groupRec)
    end
    if not groupRec then
        return
    end
    local current = CurrentSpecID()
    local member = false
    for _, spellRef in ipairs(groupRec.specs or {}) do
        if spellRef == current then
            member = true
            break
        end
    end
    if not member then
        return
    end
    if CludesUI._unlockModeActive then
        return
    end
    -- Exclusive layer ownership: when ANOTHER group's layout already provides this
    -- spec's unlock mode, refuse fork creation AND editing here. A fork born under a
    -- non-owner group can never apply to this spec; it sits dead until a group or
    -- layout deletion promotes it, replacing the spec's unlock mode with a stale layout.
    do
        local own = OwnerGid(current)
        if own and own ~= groupRec.id then
            local og = GroupById(own)
            CludesUI:ShowConfirmPopup({
                title = L("Customize Layout Mode"),
                message = string.format(
                    L(
                        "The override group '%s' already provides the custom layout mode for your current spec. Customize it there, or remove this spec from that group."
                    ),
                    (og and og.name) or "?"
                ),
                confirmText = L("OK"),
                hideCancel = true,
            })
            return
        end
    end
    local store = GetUnlockStore(true)
    if not store then
        return
    end
    if store.layouts[groupRec.id] == nil then
        CludesUI:ShowConfirmPopup({
            title = L("Customize Layout Mode"),
            message = L(
                "This will create a fully unique layout mode for this override group. Changes made to your default layout mode will no longer affect these specs."
            ),
            confirmText = L("Create"),
            cancelText = L("Cancel"),
            onConfirm = function()
                local storeB = GetUnlockStore(true)
                if not storeB or storeB.layouts[groupRec.id] ~= nil then
                    return
                end
                -- Fork from the current live layout: bank live into its owner
                -- first (keeps that layer current).
                CludesUI.SpecOverrides_HarvestUnlockLayout()
                -- First-ever layer on a virgin store: capture the shared BASELINE from
                -- the pre-fork live layout (live IS the baseline when no layer is
                -- active). Without it, a non-member spec taking over has nothing to
                -- restore to: the fork's edits stick and the next harvest adopts them
                -- AS the default layout.
                if not storeB.baselineLayout and not storeB.active then
                    storeB.baselineLayout = HarvestLayer()
                end
                -- Seed from the BASELINE whenever any OTHER layer is live (conditional
                -- or another spec group): harvesting live would seed the new fork with
                -- a layout its specs never owned. Live-harvest seeding is only correct
                -- when live IS the baseline -- a spec group voids conditionals
                -- entirely, so its layer must never be born from a dungeon/raid arrangement.
                local fromCond = type(storeB.active) == "string"
                local fromOtherGroup = type(storeB.active) == "number" and storeB.active ~= groupRec.id
                if (fromCond or fromOtherGroup) and storeB.baselineLayout then
                    storeB.layouts[groupRec.id] = DeepCopy(storeB.baselineLayout)
                else
                    storeB.layouts[groupRec.id] = HarvestLayer(storeB.baselineLayout)
                end
                if OwnerGid(current) == groupRec.id then
                    storeB.active = groupRec.id
                    -- Baseline-seeded fork while another layer was showing:
                    -- that layer ceased to apply for this spec, so switch the
                    -- screen to the new (base-identical) layer now.
                    if fromCond or fromOtherGroup then
                        ApplyLayer(storeB.layouts[groupRec.id], storeB.baselineLayout)
                        _unlockSettleWanted = true
                        CludesUI.SpecOverrides_FlushUnlock()
                    end
                end
                if RefreshCardsPopup then
                    RefreshCardsPopup()
                end
                CludesUI.SpecOverrides_EnterUnlockForGroup(groupRec)
            end,
        })
        return
    end
    -- Editing-as and unlock sessions never coexist. Banking the panel session
    -- first also restores canonical live values.
    if _editGroup then
        ExitGroupEdit(true)
    end
    local panelFrame = CludesUI._mainFrame
    if panelFrame and panelFrame:IsShown() then
        panelFrame:Hide()
    end
    C_Timer.After(0, function()
        if CludesUI._openUnlockMode then
            CludesUI._openUnlockMode()
        end
    end)
end

Inner.BmApplyLayer, Inner.BmHarvestLayer, Inner.BmOwnerGid = BmApplyLayer, BmHarvestLayer, BmOwnerGid
Inner.BmSessionEngage, Inner.DmApplyLayer = BmSessionEngage, DmApplyLayer
Inner.DmHarvestLayer, Inner.DmOwnerGid, Inner.DmSessionEngage = DmHarvestLayer, DmOwnerGid, DmSessionEngage
Inner.GetBmStore, Inner.GetCondBmStore, Inner.GetCondDmStore = GetBmStore, GetCondBmStore, GetCondDmStore
Inner.GetDmStore, Inner.IsTBBChildKey, Inner.LayerSkipsKey = GetDmStore, IsTBBChildKey, LayerSkipsKey
Inner.LiteProfile = LiteProfileOf
Inner.broken = false
