if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_CDM_BuffBarStore.lua
--
--  Per-spec unlock-link views and the bar list: add, remove, reorder within a
--  group and broadcast a tracking bar across specs.
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._buffBarInternals
-- CludesUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local max = math.max

local TBB_DEFAULT_BAR = Inner.TBB_DEFAULT_BAR

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._buffBarInternals, which hands the value to every copy.
local ECME
Inner.ecmeSetters[#Inner.ecmeSetters + 1] = function(val) ECME = val end

-------------------------------------------------------------------------------
--  Per-spec unlock-link views (anchor / width-match / height-match entries)
--
--  Unlock links are stored account-globally by element key, but TBB keys by
--  BAR INDEX ("TBB_1") while bar lists are per-spec -- a raw global entry
--  would glue bar 1 of every spec to one link. Fix: each (profile, spec)
--  keeps its own copy of the TBB child-role entries in a bucket next to
--  tbbPositions. The global stores hold exactly ONE spec's entries -- the
--  "owner", stamped in CludesUIDB._tbbLinkOwner -- maintained by
--  SyncTBBUnlockLinks: owner==active banks live->bucket (live stores are
--  that spec's working truth); owner~=active banks the old owner then swaps
--  the active spec's bucket in; force (profile restore replaced the stores
--  wholesale) swaps in only, NEVER banks -- live entries no longer belong to
--  the stamped owner. A spec's first-ever view seeds from live entries,
--  keeping only slots with a bar on that spec.
--
--  Entries where a TBB bar is the TARGET stay under the child's key
--  untouched ("follow whatever bar 1 is on this spec"); the fallback-anchor
--  system covers an empty slot.
-------------------------------------------------------------------------------
do
    local CopyEntry = CUI.Lite.DeepCopy

    local function LiveStores(create)
        local saved = CludesUIDB
        if not saved then return nil end
        if create then
            saved.unlockAnchors = saved.unlockAnchors or {}
            saved.unlockWidthMatch = saved.unlockWidthMatch or {}
            saved.unlockHeightMatch = saved.unlockHeightMatch or {}
        end
        return saved.unlockAnchors, saved.unlockWidthMatch, saved.unlockHeightMatch
    end

    local function BucketFor(profileName, specKey, create)
        if not profileName or not specKey then return nil end
        local sp = mod.GetSpecProfilesForProfile and mod.GetSpecProfilesForProfile(profileName)
        if not sp then return nil end
        local prof = sp[specKey]
        if not prof then
            if not create then return nil end
            prof = { barSpells = {} }
            sp[specKey] = prof
        end
        if not prof.tbbUnlockLinks and create then
            prof.tbbUnlockLinks = { anchors = {}, wm = {}, hm = {} }
        end
        return prof.tbbUnlockLinks
    end

    -- Copy a live store's TBB child entries into a bucket table (slot-keyed).
    local function CopyOne(storage, dest)
        wipe(dest)
        if not storage then return end
        for key, val in pairs(storage) do
            if type(key) == "string" then
                local slot = key:match("^TBB_(%d+)$")
                if slot then dest[slot] = CopyEntry(val) end
            end
        end
    end

    -- A TBB child's Extra Width / Height rides its bucket beside its link (wmx /
    -- hmx; liveField = the account store). The live stores can exist empty
    -- (profile restores write them), so a missing bucket table is created only
    -- once the store holds a TBB entry.
    local function CopyExtra(b, field, liveField)
        local saved = CludesUIDB
        local storage = saved and saved[liveField]
        local dest = b[field]
        if not dest then
            if not storage then return end
            local any
            for key in pairs(storage) do
                if type(key) == "string" and key:find("^TBB_%d+$") then
                    any = true
                    break
                end
            end
            if not any then return end
            dest = {}
            b[field] = dest
        end
        CopyOne(storage, dest)
    end

    local function Bank(profileName, specKey)
        -- WoW Forever: never recreate a missing bucket here. The saved owner
        -- can name a key the class no longer resolves to, and a recreated
        -- bucket would steer which key the next session reads; a missing
        -- bucket has nothing live to bank.
        if CUI.IS_FOREVER then
            local sp = profileName
                and specKey
                and mod.GetSpecProfilesForProfile
                and mod.GetSpecProfilesForProfile(profileName)
            if not (sp and sp[specKey]) then return end
        end
        local b = BucketFor(profileName, specKey, true)
        if not b then return end
        local an, wm, hm = LiveStores(false)
        CopyOne(an, b.anchors)
        CopyOne(wm, b.wm)
        CopyOne(hm, b.hm)
        CopyExtra(b, "wmx", "unlockWidthMatchExtra")
        CopyExtra(b, "hmx", "unlockHeightMatchExtra")
    end

    -- Replace a live store's TBB child entries with a bucket table's.
    local function SwapOne(storage, source)
        local kill
        for key in pairs(storage) do
            if type(key) == "string" and key:match("^TBB_%d+$") then
                kill = kill or {}
                kill[#kill + 1] = key
            end
        end
        if kill then
            for _, key in ipairs(kill) do
                storage[key] = nil
            end
        end
        for slot, val in pairs(source) do
            storage["TBB_" .. slot] = CopyEntry(val)
        end
    end

    -- Swap a bucket's extras into the account store: a spec without extras (no
    -- wmx / hmx, or empty) clears every live TBB extra, and a missing store is
    -- created only to hold one. NO_EXTRA is read-only (SwapOne never writes src).
    local NO_EXTRA = {}
    local function SwapExtra(liveField, source)
        local saved = CludesUIDB
        local storage = saved[liveField]
        if not storage then
            if not source or next(source) == nil then return end
            storage = {}
            saved[liveField] = storage
        end
        SwapOne(storage, source or NO_EXTRA)
    end

    local function SwapIn(profileName, specKey)
        local an, wm, hm = LiveStores(true)
        if not an then return end
        local b = BucketFor(profileName, specKey, false)
        if not b then
            b = BucketFor(profileName, specKey, true)
            if not b then return end
            -- First view for this spec: seed from live entries, keeping only slots that have a bar here.
            CopyOne(an, b.anchors)
            CopyOne(wm, b.wm)
            CopyOne(hm, b.hm)
            local tbl = mod.GetTrackedBuffBars and mod.GetTrackedBuffBars()
            local barList = (tbl and tbl.bars) or {}
            local sets = { b.anchors, b.wm, b.hm }
            for i = 1, 3 do
                local set, drop = sets[i], nil
                for slot in pairs(set) do
                    if not barList[tonumber(slot)] then
                        drop = drop or {}
                        drop[#drop + 1] = slot
                    end
                end
                if drop then
                    for _, slot in ipairs(drop) do
                        set[slot] = nil
                    end
                end
            end
            -- Extras seed and prune like their links.
            CopyExtra(b, "wmx", "unlockWidthMatchExtra")
            CopyExtra(b, "hmx", "unlockHeightMatchExtra")
            local xsets = { b.wmx, b.hmx }
            for i = 1, 2 do
                local set = xsets[i]
                if set then
                    for slot in pairs(set) do
                        if not barList[tonumber(slot)] then set[slot] = nil end
                    end
                end
            end
        end
        SwapOne(an, b.anchors)
        SwapOne(wm, b.wm)
        SwapOne(hm, b.hm)
        SwapExtra("unlockWidthMatchExtra", b.wmx)
        SwapExtra("unlockHeightMatchExtra", b.hmx)
        -- Modules memoize views over the anchor DB (extent watch etc.).
        CUI._anchorLinksStamp = (CUI._anchorLinksStamp or 0) + 1
    end

    function mod.SyncTBBUnlockLinks(force)
        if not CludesUIDB then return end
        local profName = mod.GetActiveProfileName and mod.GetActiveProfileName()
        local specKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
        if not profName or not specKey then return end
        local own = CludesUIDB._tbbLinkOwner
        local same = own and own.profile == profName and own.spec == specKey
        if force then
            SwapIn(profName, specKey)
        elseif same then
            Bank(profName, specKey)
            return
        else
            if own then Bank(own.profile, own.spec) end
            SwapIn(profName, specKey)
        end
        CludesUIDB._tbbLinkOwner = { profile = profName, spec = specKey }
    end

    -- Called by profile-restore choke points right after they replace the live unlock
    -- stores wholesale from an unlockLayout snapshot: the snapshot's TBB entries are stale
    -- copies of whichever spec last saved unlock mode, so the active spec's own entries are re-asserted here.
    CUI._TBBRestoreUnlockLinks = function()
        -- Mid-apply, the active-store cache still holds the outgoing profile's
        -- store, and on WoW Forever the spec key resolves against that store.
        mod._cachedSpecProfiles = nil
        mod.SyncTBBUnlockLinks(true)
    end

    -- Unlock Save & Exit: bank the active spec's live TBB links and extras into its
    -- bucket (only while live belongs to it), so a profile restore before the next
    -- bar build cannot swap an older bucket over them.
    CUI._TBBBankUnlockLinks = function()
        if not CludesUIDB then return end
        local own = CludesUIDB._tbbLinkOwner
        local profName = mod.GetActiveProfileName and mod.GetActiveProfileName()
        local specKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
        if own and own.profile == profName and own.spec == specKey then Bank(profName, specKey) end
    end
end

-- Create a new bar config (no rebuild). `targetGid`: nil = follow the last
-- bar's group (quick-add default), 0 = independent, N = that group. Style
-- comes from the group's style source so the bar lands looking like its
-- group; independent bars copy the last bar. Spell identity and stack fields
-- always start fresh.
local function AddTrackedBuffBarCore(tbb, targetGid)
    local barList = tbb.bars
    local groupId
    if targetGid ~= nil then
        groupId = targetGid
    elseif #barList > 0 then
        groupId = mod.TBBBarGroupID(barList[#barList])
    else
        groupId = 1
    end

    -- Style priority: 1) preset on a bar already in the target group, 2) the target
    -- group's current look (style source bar), 3) a preset on any bar of this spec
    -- else any saved preset, 4) the last bar's look (legacy inherit), 5) defaults.
    local preset, styleSrc
    if groupId ~= 0 and mod.ResolveTBBGroupPreset then preset = mod.ResolveTBBGroupPreset(tbb, groupId) end
    if not preset and groupId ~= 0 and mod.TBBGroupStyleSource then
        styleSrc = mod.TBBGroupStyleSource(groupId)
    end
    if not preset and not styleSrc and mod.ResolveTBBFallbackPreset then
        preset = mod.ResolveTBBFallbackPreset(tbb)
    end
    if not preset and not styleSrc and #barList > 0 then styleSrc = barList[#barList] end

    -- Base from pure defaults (spell identity, enable state and stack-threshold numbers
    -- start fresh), then dress it: the style key set is the authoritative visual copy.
    local newBar = {}
    for key, val in pairs(TBB_DEFAULT_BAR) do
        newBar[key] = val
    end
    if preset then
        mod.ApplyTBBStylePresetToCfg(preset, newBar)
    elseif styleSrc then
        mod.CopyTBBStyle(styleSrc, newBar)
    end
    newBar.spellID = 0
    newBar.name = "Bar " .. (#barList + 1)
    newBar.popularKey = nil
    newBar.spellIDs = nil
    newBar.baseSpellID = nil
    newBar.customDuration = nil
    newBar.glowBased = nil
    newBar.trackType = nil
    newBar.enabled = true
    mod.TBBSetBarGroup(newBar, groupId)
    barList[#barList + 1] = newBar
    tbb.selectedBar = #barList

    -- Vertical bars read better side by side: when a vertical bar FOUNDS a group whose grow direction was never chosen, default it to RIGHT rather than the global DOWN.
    if groupId ~= 0 and newBar.verticalOrientation and mod.TBBGroupedCount(groupId) <= 1 then
        local g = tbb.groups and tbb.groups[tostring(groupId)]
        local hasStored = (g and g.grow) or (groupId == 1 and tbb.groupGrowDirection)
        if not hasStored then mod.TBBSetGroupGrow(groupId, "RIGHT") end
    end

    -- Auto-position adjacent to the previous bar; matters only for independent bars (grouped bars chain off their group anchor).
    local profile = ECME and ECME.db and ECME.db.profile
    if profile then
        local _tbbPos = mod.GetTBBPositions()
        local prevIdx = #barList - 1
        if prevIdx >= 1 then
            local prevPos = _tbbPos[tostring(prevIdx)]
            local prevCfg = barList[prevIdx]
            if prevPos and prevPos.point then
                local px, py = prevPos.x or 0, prevPos.y or 0
                if newBar.verticalOrientation then
                    -- Step sideways by the previous bar's on-screen width (width/height are always VISUAL dimensions).
                    local barW = (prevCfg and prevCfg.width or 24) + 4
                    _tbbPos[tostring(#barList)] = {
                        point = prevPos.point,
                        relPoint = prevPos.relPoint or prevPos.point,
                        x = px + barW,
                        y = py,
                    }
                else
                    local barH = (prevCfg and prevCfg.height or 24) + 4
                    _tbbPos[tostring(#barList)] = {
                        point = prevPos.point,
                        relPoint = prevPos.relPoint or prevPos.point,
                        x = px,
                        y = py + barH,
                    }
                end
            end
        end
    end

    return #barList
end

function mod.AddTrackedBuffBar(targetGid)
    local tbb = mod.GetTrackedBuffBars()
    local position = AddTrackedBuffBarCore(tbb, targetGid)
    mod.BuildTrackedBuffBars()
    return position
end

function mod.RemoveTrackedBuffBar(position)
    local tbb = mod.GetTrackedBuffBars()
    if position < 1 or position > #tbb.bars then return end
    local oldCount = #tbb.bars
    table.remove(tbb.bars, position)
    -- Positions are keyed by bar index: re-key so bars after the removed index keep their coordinates.
    local place = mod.GetTBBPositions()
    for jdx = position, oldCount - 1 do
        place[tostring(jdx)] = place[tostring(jdx + 1)]
    end
    place[tostring(oldCount)] = nil
    -- Re-key element-anchor / size-match links the same way (TBB_3 -> TBB_2) so anchors
    -- keep tracking the same visual bar; links pointing AT the deleted bar are severed.
    if CUI and CUI.ShiftIndexedAnchorKeys then
        CUI.ShiftIndexedAnchorKeys("TBB_", position, oldCount)
    end
    if tbb.selectedBar > #tbb.bars then tbb.selectedBar = max(1, #tbb.bars) end
    mod.BuildTrackedBuffBars()
end

-- Move a grouped bar to place `pos` among its group's members (1 = first). The
-- members trade the slots they already hold, so bars outside the group keep
-- their indices and positions / unlock links stay with their slot: the group
-- stays put and whatever is anchored to it stays anchored. Style is untouched.
-- Returns the bar's new index.
function mod.MoveTrackedBuffBarInGroup(position, place)
    local tbb = mod.GetTrackedBuffBars()
    local barList = tbb.bars
    local conf = barList[position]
    local groupId = mod.TBBBarGroupID(conf)
    if groupId == 0 then return position end
    local slots, members, from = {}, {}, nil
    for jdx, c in ipairs(barList) do
        if mod.TBBBarGroupID(c) == groupId then
            slots[#slots + 1] = jdx
            members[#members + 1] = c
            if jdx == position then from = #slots end
        end
    end
    place = max(1, math.min(place, #slots))
    if place == from then return position end
    local oldAnchor = mod.TBBGroupAnchorIndex(groupId)
    table.remove(members, from)
    table.insert(members, place, conf)
    for key, jdx in ipairs(slots) do
        barList[jdx] = members[key]
    end
    -- A disabled member can hand the anchor role to another slot: carry the
    -- group origin there, as the group mover's save does for every member.
    local newAnchor = mod.TBBGroupAnchorIndex(groupId)
    local posDB = mod.GetTBBPositions()
    local origin = oldAnchor and posDB[tostring(oldAnchor)]
    if newAnchor and newAnchor ~= oldAnchor and origin then
        posDB[tostring(newAnchor)] =
            { point = origin.point, relPoint = origin.relPoint, x = origin.x, y = origin.y }
    end
    mod.BuildTrackedBuffBars()
    return slots[place]
end

-- Stable identity for the broadcast toggle and the single source of truth for whether a
-- bar can broadcast across specs: only when it targets a spec-agnostic buff -- a preset
-- (popularKey, keyed "p:<key>") or a custom buff ID (keyed "s:<spellID>"). A Blizzard
-- CDM tracked spell is spec/class- specific and must NEVER be broadcastable; it's told
-- apart from a custom buff by having NO customDuration (custom-buff popup always sets
-- one, CDM picker clears it). Freshly-added empty bars return nil.
function mod.TBBBroadcastKey(conf)
    if type(conf) ~= "table" then return nil end
    if conf.popularKey and conf.popularKey ~= "" then return "p:" .. conf.popularKey end
    if
        conf.spellID
        and conf.spellID > 0
        and type(conf.customDuration) == "number"
        and conf.customDuration > 0
    then
        return "s:" .. tostring(conf.spellID)
    end
    return nil
end

-- Broadcastable only when TBBBroadcastKey yields an identity (preset or custom buff); Blizzard CDM spells and empty bars are excluded.
function mod.IsTrackedBuffBarBroadcastable(conf) return mod.TBBBroadcastKey(conf) ~= nil end

-- True when the bar's buff is marked broadcast to all specs (button reads "Remove Bar from All Specs"). Read from the persistent per-profile set.
function mod.IsTrackedBuffBarBroadcast(conf)
    local key = mod.TBBBroadcastKey(conf)
    if not key then return false end
    local set = mod.GetActiveTBBBroadcastSet and mod.GetActiveTBBBroadcastSet()
    return set ~= nil and set[key] == true
end

-- Copy a configured bar (preset or custom buff) into every OTHER spec of the player's
-- class; config and position are deep-copied so it appears identically everywhere.
-- Specs already holding it are skipped, so repeated clicks never pile up duplicates.
-- Returns the number of specs added to.
function mod.AddBarToAllSpecs(srcIdx)
    local DeepCopy = CUI.Lite and CUI.Lite.DeepCopy
    if not DeepCopy then return 0 end
    local activeKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
    if not activeKey then return 0 end

    local srcTbb = mod.GetTrackedBuffBars()
    local srcBar = srcTbb and srcTbb.bars and srcTbb.bars[srcIdx]
    if not mod.IsTrackedBuffBarBroadcastable(srcBar) then return 0 end

    local srcPos = mod.GetTBBPositions()[tostring(srcIdx)]

    local specProfiles = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
    if not specProfiles then return 0 end

    local function HasSameBar(barList)
        for _, bar in ipairs(barList) do
            -- A cooldown-tracking bar is never the same bar as a buff bar for the same spell: track types must match first.
            if (bar.trackType or "buff") == (srcBar.trackType or "buff") then
                if srcBar.popularKey and srcBar.popularKey ~= "" then
                    if bar.popularKey == srcBar.popularKey then return true end
                elseif
                    (not bar.popularKey or bar.popularKey == "")
                    and bar.spellID
                    and bar.spellID == srcBar.spellID
                then
                    return true
                end
            end
        end
        return false
    end

    local added = 0
    -- WoW Forever: the class has no other spec to copy into (the store key it
    -- runs on is the only one it reads).
    local numSpecs = (not CUI.IS_FOREVER) and GetNumSpecializations and GetNumSpecializations() or 0
    for i = 1, numSpecs do
        local specID = C_SpecializationInfo.GetSpecializationInfo(i)
        if specID then
            local key = tostring(specID)
            if key ~= activeKey then
                if not specProfiles[key] then specProfiles[key] = { barSpells = {} } end
                local prof = specProfiles[key]
                if not prof.trackedBuffBars then prof.trackedBuffBars = { selectedBar = 1, bars = {} } end
                local tbb = prof.trackedBuffBars
                if not HasSameBar(tbb.bars) then
                    local newBar = DeepCopy(srcBar)
                    -- Join the target spec's group only when its bars all live in ONE
                    -- group (mirrors quick-add); otherwise start independent so its layout
                    -- stays undisturbed. Empty spec starts the bar in group 1.
                    local groupId
                    if #tbb.bars == 0 then
                        groupId = 1
                    else
                        groupId = mod.TBBBarGroupID(tbb.bars[1])
                        for jdx = 2, #tbb.bars do
                            if mod.TBBBarGroupID(tbb.bars[jdx]) ~= groupId then
                                groupId = 0
                                break
                            end
                        end
                    end
                    mod.TBBSetBarGroup(newBar, groupId)
                    local newIdx = #tbb.bars + 1
                    tbb.bars[newIdx] = newBar
                    if srcPos then
                        if not prof.tbbPositions then prof.tbbPositions = {} end
                        prof.tbbPositions[tostring(newIdx)] = DeepCopy(srcPos)
                    end
                    added = added + 1
                end
            end
        end
    end

    -- Mark broadcast so the button flips to "Remove..." in every spec; set even when added == 0 (all specs already held it).
    -- WoW Forever copies nowhere (see above), so nothing is marked there.
    local set = not CUI.IS_FOREVER and mod.GetActiveTBBBroadcastSet and mod.GetActiveTBBBroadcastSet()
    if set then
        local key = mod.TBBBroadcastKey(srcBar)
        if key then set[key] = true end
    end

    return added
end

-- Inverse of AddBarToAllSpecs: remove the bar's buff from every OTHER spec and clear the
-- broadcast flag. The CURRENT spec's bar is left untouched. Returns specs removed from.
function mod.RemoveBarFromAllSpecs(srcIdx)
    local activeKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
    if not activeKey then return 0 end

    local srcTbb = mod.GetTrackedBuffBars()
    local srcBar = srcTbb and srcTbb.bars and srcTbb.bars[srcIdx]
    local broadcastKey = mod.TBBBroadcastKey(srcBar)
    if not broadcastKey then return 0 end

    local specProfiles = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
    if not specProfiles then return 0 end

    local function Matches(b)
        -- Track types must match: a broadcast buff bar for spell X must NEVER delete a cooldown-tracking bar for the same spell.
        if (b.trackType or "buff") ~= (srcBar.trackType or "buff") then return false end
        if srcBar.popularKey and srcBar.popularKey ~= "" then
            return b.popularKey == srcBar.popularKey
        else
            return (not b.popularKey or b.popularKey == "") and b.spellID and b.spellID == srcBar.spellID
        end
    end

    local removed = 0
    local numSpecs = (not CUI.IS_FOREVER) and GetNumSpecializations and GetNumSpecializations() or 0
    for i = 1, numSpecs do
        local specID = C_SpecializationInfo.GetSpecializationInfo(i)
        if specID then
            local specKey = tostring(specID)
            if specKey ~= activeKey then
                local prof = specProfiles[specKey]
                local tbb = prof and prof.trackedBuffBars
                if tbb and tbb.bars and #tbb.bars > 0 then
                    -- Rebuild excluding matches, re-keying positions so compacted indices and
                    -- tbbPositions stay aligned (plain table.remove would strand stale indices).
                    local oldPos = prof.tbbPositions or {}
                    local newBars, newPos = {}, {}
                    local didRemove = false
                    for jdx, bar in ipairs(tbb.bars) do
                        if Matches(bar) then
                            didRemove = true
                        else
                            newBars[#newBars + 1] = bar
                            local p = oldPos[tostring(jdx)]
                            if p then newPos[tostring(#newBars)] = p end
                        end
                    end
                    if didRemove then
                        tbb.bars = newBars
                        prof.tbbPositions = newPos
                        if tbb.selectedBar and tbb.selectedBar > #newBars then
                            tbb.selectedBar = math.max(1, #newBars)
                        end
                        removed = removed + 1
                    end
                end
            end
        end
    end

    -- Clear the broadcast flag so the button flips back to "Add...".
    local set = mod.GetActiveTBBBroadcastSet and mod.GetActiveTBBBroadcastSet()
    if set then set[broadcastKey] = nil end

    return removed
end

Inner.AddTrackedBuffBarCore = AddTrackedBuffBarCore
Inner.broken = false
