if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_Reconcile.lua
--
--  First login capture, reseeding, drops, the hidden-channel reader and buff
--  families.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- The main file or an earlier CDM file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ALL_RACIAL_SPELLS, ECME, _myRacialsSet = Inner.ALL_RACIAL_SPELLS, Inner.ECME, Inner._myRacialsSet
local ResolveActiveRacial = Inner.ResolveActiveRacial
local GHOST_CD_BAR_KEY, MAIN_BAR_KEYS = Inner.GHOST_CD_BAR_KEY, Inner.MAIN_BAR_KEYS
local SaveCurrentSpecProfile, barDataByKey = Inner.SaveCurrentSpecProfile, Inner.barDataByKey
local CaptureCDMPositions = Inner.CaptureCDMPositions

-------------------------------------------------------------------------------
--  CDM Bar: First Login Capture
-------------------------------------------------------------------------------
local function CDMFirstLoginCapture()
    local profile = ECME.db.profile
    local captured = CaptureCDMPositions()

    for _, barInfo in ipairs(profile.cdmBars.bars) do
        local limit = captured[barInfo.key]
        if limit then
            -- Icon size: visual size from child icon (base width * child scale).
            if limit.iconSize then
                barInfo.iconSize = limit.iconSize
            end
            -- Spacing (icon padding from Edit Mode setting)
            if limit.spacing then
                barInfo.spacing = limit.spacing
            end
            -- Rows (counted from distinct Y positions of visible icons)
            if limit.numRows then
                barInfo.numRows = limit.numRows
            end
            if limit.isHorizontal ~= nil then
                if not limit.isHorizontal then
                    barInfo.growDirection = "DOWN"
                end
                barInfo.verticalOrientation = not limit.isHorizontal
            end
            -- Position: no scale division needed (scale is always 1)
            if limit.point then
                profile.cdmBarPositions[barInfo.key] = {
                    point = limit.point,
                    relPoint = limit.relPoint,
                    x = limit.x,
                    y = limit.y,
                }
            end
        end
    end

    ECME.db.sv._capturedOnce_CDM = true
end

--- Re-seed assignedSpells from live cdmBarIcons. Appends any positive spell IDs present on the
--- live bars but missing from assignedSpells. Called after CollectAndReanchor so the preview stays in sync with what the player actually sees on their CDM bars.
function mod.ReseedAssignedSpellsFromLiveIcons(cdUtilOnly)
    local profile = ECME and ECME.db and ECME.db.profile
    if not profile or not profile.cdmBars then
        return
    end

    -- Both-state guards (mirror EnsureAssignedSpells). This appends live-icon spells back into
    -- assignedSpells; without these it could re-materialize a spell that is currently HIDDEN
    -- (ghosted) or already OWNED by another bar, recreating a both-state. The sole caller
    -- (RepopulateFromBlizzard) pre-wipes the ghost and Blizzard-sourced assignments, so these are normally no-ops -- but they keep Reseed safe regardless of caller or ordering.
    local specProfile = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
    local specKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
    local activeProfile = specProfile and specKey and specProfile[specKey]
    -- Skip entirely while an imported layout is pending its first-load ghosting: its tracked
    -- spells spill onto default bars until the migration ghosts them, and materializing those spills would defeat the import-authoritative hide.
    if activeProfile and activeProfile._importGhostMode then
        return
    end

    -- Unlike every other assignedSpells mutation site (the picker's add/remove/move calls,
    -- BuildAllCDMBars), this one never marked the cached render-order map (spellOrder,
    -- CUI_CDM_HookReanchor.lua) dirty -- so a spell this pass just materialized had no key in the
    -- STALE cache, fell through every OrderKeyFor match probe, and rendered via the raw
    -- layoutIndex spillover fallback (the same imprecise path #1211/#1420 already fixed once)
    -- instead of the position it was just given. Field-confirmed: Cobra Shot's assignedSpells
    -- entry was correct and it still rendered first. Set once, only when something actually inserted.
    local didInsert = false

    -- Spell -> owning bar (variant-aware), built once. A live icon whose stored owner is a DIFFERENT bar is a transient spillover we must not materialize.
    local ownerOf
    -- One-racial-total invariant (see NormalizeRacialAssignments): while ANY
    -- racial-family entry is placed on any bar, the racial slot is spoken for.
    -- Materializing a second racial slot here (a live racial icon transiting a
    -- default bar during the login route-not-ready window) creates the
    -- dual-state the normalize dedupe then resolves -- which historically
    -- deleted the user's custom placement.
    local anyRacialOwned = false
    if activeProfile and activeProfile.barSpells and mod.StoreVariantValue then
        for key, bsd in pairs(activeProfile.barSpells) do
            if key ~= GHOST_CD_BAR_KEY and type(bsd) == "table" and type(bsd.assignedSpells) == "table" then
                for _, csid in ipairs(bsd.assignedSpells) do
                    if type(csid) == "number" and csid > 0 then
                        ownerOf = ownerOf or {}
                        mod.StoreVariantValue(ownerOf, csid, key, false)
                        if ALL_RACIAL_SPELLS[csid] then
                            anyRacialOwned = true
                        end
                    end
                end
            end
        end
    end

    local ghostSd = mod.GetBarSpellData and mod.GetBarSpellData(GHOST_CD_BAR_KEY)
    local ghostList = ghostSd and ghostSd.assignedSpells
    local FindVar = mod.FindVariantIndexInList

    -- Cd-claimed collided-buff slots (cd-claim markers in assignedSpells, see ns.CdClaimMarker)
    -- are tracked by COOLDOWN ID, not by the shared spellID. Materializing such an icon's shared
    -- spellID here would, at the next route rebuild, drag the UNCLAIMED twin onto the claiming bar
    -- too -- defeating the claim's one-slot-only contract. Built once; stays nil (guard inert, zero cost) unless a collided claim exists anywhere.
    local claimedCd
    if activeProfile and activeProfile.barSpells then
        for _, bsd in pairs(activeProfile.barSpells) do
            local bsdClaims = type(bsd) == "table" and mod.CollectCdClaimSet(bsd)
            if bsdClaims then
                for cooldownId in pairs(bsdClaims) do
                    claimedCd = claimedCd or {}
                    claimedCd[cooldownId] = true
                end
            end
        end
    end

    for _, barInfo in ipairs(profile.cdmBars.bars) do
        -- cdUtilOnly (the automatic reseed path): buff-family bars are picker-authoritative --
        -- materializing live buff icons would reintroduce the secret-ID drift duplicate-slot bug
        -- the options materializer's skip exists to prevent. The manual Repopulate flow passes nothing and keeps its full sweep.
        if
            not barInfo.isGhostBar
            and barInfo.key ~= "buffs"
            and (
                barInfo.barType == "cooldowns"
                or barInfo.barType == "utility"
                or (barInfo.barType == "buffs" and not cdUtilOnly)
                or MAIN_BAR_KEYS[barInfo.key]
            )
        then
            local barSpells = mod.GetBarSpellData(barInfo.key)
            local icons = mod.cdmBarIcons and mod.cdmBarIcons[barInfo.key]
            -- Talent Conditions: the frames the reanchor filter dropped from this bar are
            -- present, only hidden. They walk after the live icons, so a hidden spell keeps
            -- (or regains) its slot and its conditions stay reachable from the preview.
            local tcHidden = mod._cdmAnyTalentCond and mod.TalentCondHiddenFrames(barInfo.key)
            local nLive = 0
            if icons then
                while icons[nLive + 1] do
                    nLive = nLive + 1
                end
            end
            local nWalk = nLive + (tcHidden and #tcHidden or 0)
            if barSpells and (icons or nWalk > 0) then
                if not barSpells.assignedSpells then
                    barSpells.assignedSpells = {}
                end
                -- Insert each missing spell right after its left neighbour in the live icon order
                -- (already Blizzard-layout order from CollectAndReanchor) instead of appending, so
                -- the seeded list matches what the player sees and a re-talented cooldown returns
                -- to its slot, not the tail. Presence is VARIANT-AWARE and the cursor is a
                -- POSITION, not an id: an exact-match set misses a stored entry when the live icon
                -- reports a different variant form (fc.spellID can be the talent override, e.g.
                -- Mongoose Bite 259387, while the slot holds the base Raptor Strike 186270 the
                -- options normalize pass wrote). Each reload then re-inserts the live form at
                -- Blizzard's position and the next normalize dedupes in its favor -- permanently snapping the user's saved order back to Blizzard order. A by-value cursor lookup fails the same way and dumps inserts at slot 1.
                local insertPos = nil
                for walk = 1, nWalk do
                    local iconTex
                    if walk <= nLive then
                        iconTex = icons[walk]
                    else
                        iconTex = tcHidden[walk - nLive]
                        -- A hidden frame has no on-screen neighbour, so place it beside its
                        -- live neighbours in Blizzard's layout: after the nearest same-viewer
                        -- icon below its layoutIndex, else before the nearest one above, else
                        -- after the last live slot (the cursor as it stands).
                        local L, vf = iconTex.layoutIndex, iconTex.viewerFrame
                        if L and vf and FindVar then
                            local predLI, predAt, succLI, succAt
                            for jdx = 1, nLive do
                                local ic = icons[jdx]
                                local li = ic.viewerFrame == vf and ic.layoutIndex
                                local fcJ = li and mod._ecmeFC[ic]
                                local at = fcJ and fcJ.spellID and FindVar(barSpells.assignedSpells, fcJ.spellID)
                                if at then
                                    if li < L then
                                        if not predLI or li > predLI then
                                            predLI, predAt = li, at
                                        end
                                    elseif not succLI or li < succLI then
                                        succLI, succAt = li, at
                                    end
                                end
                            end
                            if predAt then
                                insertPos = predAt
                            elseif succAt then
                                insertPos = succAt - 1
                            end
                        end
                    end
                    local fc = mod._ecmeFC and mod._ecmeFC[iconTex]
                    local spellRef = fc and fc.spellID
                    -- Skip hosted-buff frames and their placeholders: their bar membership is the
                    -- hosted MARKER entry, and their positive spellID would materialize the same
                    -- spell's COOLDOWN form. But DO advance the cursor over their marker: on a mixed
                    -- bar a spell re-inserted after a buff must land after the buff's marker, not squeezed back next to the previous CD spell.
                    local fdRS = mod._hookFrameData and mod._hookFrameData[iconTex]
                    if
                        (fc and fc.isHostedBuff)
                        or iconTex._isPlaceholderFrame
                        or (fdRS and fdRS._isBuffViewerFrame)
                    then
                        local hSid = fc and fc.spellID
                        if
                            type(hSid) == "number"
                            and hSid > 0
                            and mod.HostedBuffMarkerToSpell
                            and not (fc and fc._overflowLayoutBar)
                        then
                            for index = 1, #barSpells.assignedSpells do
                                local dec = mod.HostedBuffMarkerToSpell(barSpells.assignedSpells[index])
                                if
                                    dec
                                    and (dec == hSid or (mod.IsVariantOf and mod.IsVariantOf(dec, hSid)))
                                then
                                    -- Forward-only: never drag the cursor backward.
                                    if not insertPos or index > insertPos then
                                        insertPos = index
                                    end
                                    break
                                end
                            end
                        end
                        spellRef = nil
                    end
                    -- Skip overflow-diverted icons: they render on this bar only for the session but belong to their source bar's assignedSpells (mirrors the EnsureAssignedSpells skip).
                    if spellRef and fc and fc._overflowLayoutBar then
                        spellRef = nil
                    end
                    -- Skip cd-claimed collided-buff icons: their membership is the cooldownID claim, never a spellID slot (mirrors the hosted-buff membership rule above).
                    if spellRef and claimedCd and iconTex.cooldownID and claimedCd[iconTex.cooldownID] then
                        spellRef = nil
                    end
                    if type(spellRef) == "number" and spellRef ~= 0 then
                        -- FindVar handles negatives by exact scan internally, and variant matching is a strict superset of exact equality for stored positives -- no exact fallback needed.
                        local at = FindVar and FindVar(barSpells.assignedSpells, spellRef)
                        if at then
                            -- Already has a slot (any variant form, or a custom trinket/item marker): advance the cursor so the next NEW spell lands after it, matching on-screen order.
                            insertPos = at
                        elseif spellRef > 0 then
                            -- Never materialize a hidden (ghosted) spell, or a spell a DIFFERENT bar already owns (variant-aware).
                            local ownerFrame = ownerOf
                                and mod.ResolveVariantValue
                                and mod.ResolveVariantValue(ownerOf, spellRef)
                            local ghosted = ghostList and FindVar and FindVar(ghostList, spellRef)
                            -- Racial-family guard: never mint a second racial slot
                            -- while one is placed anywhere (anyRacialOwned above).
                            local racialBlocked = anyRacialOwned and ALL_RACIAL_SPELLS[spellRef]
                            if
                                not ghosted
                                and not racialBlocked
                                and not (ownerFrame and ownerFrame ~= barInfo.key)
                            then
                                -- Store the BASE form, matching what the options normalize pass writes -- otherwise this pass persists the talent-override form and the two writers diverge (exports could ship either).
                                -- Only trust that substitution when Blizzard's OWN cooldownInfo already
                                -- recorded a base/display split for THIS icon (fc.baseSpellID ~= fc.resolvedSid,
                                -- e.g. a Wither slot whose base is Immolate). GetBaseSpell can also tie
                                -- together spells with no override relationship at all -- field-confirmed
                                -- for Cobra Shot -> Arcane Shot, and #842 saw the same API do it to SV Kill
                                -- Command -- and substituting on that spurious tie stores an id the live
                                -- spell never actually shares a slot with, orphaning it as a permanent spillover.
                                local nsid = spellRef
                                if
                                    C_Spell
                                    and C_Spell.GetBaseSpell
                                    and fc.baseSpellID
                                    and fc.resolvedSid
                                    and fc.baseSpellID ~= fc.resolvedSid
                                then
                                    local b = C_Spell.GetBaseSpell(spellRef)
                                    if b and b > 0 then
                                        nsid = b
                                    end
                                end
                                local place = insertPos and (insertPos + 1) or 1
                                table.insert(barSpells.assignedSpells, place, nsid)
                                insertPos = place
                                didInsert = true
                            end
                        elseif mod.IsItemPresetKey(spellRef) and not iconTex._isItemPresetFrame then
                            -- Blizzard's own potion / healthstone row, rendering under
                            -- an item preset key no bar lists (CUI_CDM_HookReanchor.lua,
                            -- Phase 1): list the key where the row renders, so it gets
                            -- a slot and the per-icon menu, marked as the row's own
                            -- (sd.nativeItems: the preset's frame never stands in for
                            -- it). Never while the key is ghosted: a removed entry
                            -- stays removed.
                            local ghosted = ghostList and FindVar and FindVar(ghostList, spellRef)
                            if not ghosted then
                                local place = insertPos and (insertPos + 1) or 1
                                table.insert(barSpells.assignedSpells, place, spellRef)
                                insertPos = place
                                if not barSpells.nativeItems then
                                    barSpells.nativeItems = {}
                                end
                                barSpells.nativeItems[spellRef] = true
                                didInsert = true
                            end
                        end
                    end
                end
            end
        end
    end
    if didInsert then
        mod._spellOrderDirty = true
    end
end

-- Parent-facing bridge for the automatic/export-time reconcile: cd and utility bars only
-- (buff-family excluded -- picker-authoritative). The export path nil-checks this, so a disabled CDM child is a clean no-op.
CludesUI.CDMReconcileActiveSpecSpells = function()
    mod.ReseedAssignedSpellsFromLiveIcons(true)
    -- Export serializes immediately after this bridge: erase any item rows
    -- the reseed just mirrored so exports can never ship them.
    if mod.PruneEquipmentBuffRows then
        mod.PruneEquipmentBuffRows()
    end
end

-- Shared after-combat waiter for the automatic keep/drop pass below, via the
-- module combat queue rather than the module's big shared event handler
-- further down this file -- that frame's registration set is static and
-- must not churn. The queue holds PLAYER_REGEN_ENABLED only while something
-- is pending, so an idle session carries zero event traffic from this path.
local ArmCDMDropRegenWaiter
do
    local function DropPassAfterCombat()
        mod._cdmDropPending = false
        if mod.RequestCDMDropPass then
            mod.RequestCDMDropPass("regen")
        end
    end
    ArmCDMDropRegenWaiter = function()
        mod._cdmDropPending = true
        mod.CombatQueue.Defer("CDMDropPass", DropPassAfterCombat)
    end
end

--- ns.ReconcileAssignedSpellDrops(barKey): single resident implementation of
--- the 3-way keep/drop pass (formerly inline in the options panel's
--- EnsureAssignedSpells). Interactive options edits call this directly;
--- the automatic triggers (once-per-spec reseed, settings close) arrive
--- through ns.RequestCDMDropPass below. Every guard fails OPEN to keep-all:
--- no profile, no migration, mid-import, data not yet loaded, provider
--- unreachable, or combat all return the bar's spell data unchanged rather
--- than risk dropping a legitimately-owned entry.
function mod.ReconcileAssignedSpellDrops(barId)
    local barSpells = mod.GetBarSpellData(barId)
    if not barSpells then
        return barSpells
    end

    local specProfile = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
    local specKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
    local activeProfile = specProfile and specKey and specProfile[specKey]
    if not activeProfile or not activeProfile._barFilterModelV6 then
        return barSpells
    end
    -- aprof._importGhostMode is the options panel's "importPending" (same
    -- field, CUI_CooldownManager_Options.lua ~6367-6373): a mid-import pass
    -- would mark spilled tracked spells "assigned" and permanently defeat
    -- import-authoritative ghosting, so the whole pass no-ops instead.
    if activeProfile._importGhostMode then
        return barSpells
    end
    if not mod._cdmDataLoaded then
        return barSpells
    end

    -- GHOST BAR EXEMPTION (field 2026-08-13, hunter Scare Beast classified
    -- keep=false in a reconcile dry-run): the ghost store holds spells the user DELIBERATELY removed --
    -- not-shown by definition, often uncatalogued -- and dropping a ghost entry
    -- erases the removal decision, so the spell re-materializes onto the visible
    -- bar. The classification ladder must never see this pseudo-bar.
    if barId == GHOST_CD_BAR_KEY then
        return barSpells
    end
    local edge = barDataByKey[barId]
    if mod.IsBarBuffFamily and mod.IsBarBuffFamily(edge or barId) then
        -- Buff-family drop needs the persisted variant-alias ledger so a
        -- dual-tracked spell's currently-absent half never sinks its present
        -- half; ns.ReconcileBuffFamilyDrops (further down in this file)
        -- is the single implementation, gated on that ledger. Fails open to
        -- the unmodified sd if the ledger-gated pass isn't available.
        return (mod.ReconcileBuffFamilyDrops and mod.ReconcileBuffFamilyDrops(barId)) or barSpells
    end
    local bt = edge and edge.barType
    if not (bt == "cooldowns" or bt == "utility") then
        return barSpells
    end

    if InCombatLockdown() then
        ArmCDMDropRegenWaiter()
        return barSpells
    end

    if not barSpells.assignedSpells or #barSpells.assignedSpells == 0 then
        return barSpells
    end
    if not mod.EnumerateCDMViewerSpells then
        return barSpells
    end

    local NormalizeToBase = mod.NormalizeToBase
    local ResolveToLive = mod.ResolveToLive

    -- WoW Forever: an entry listed under another rank of a shown spell is
    -- shown too (ns.CDMRankName), as the presence check that kept it found it.
    local RankName = mod.CDMRankName
    local displayed, displayedNames
    for _, entry in ipairs(mod.EnumerateCDMViewerSpells(false)) do
        local spellRef = entry.sid
        if type(spellRef) == "number" and spellRef > 0 then
            displayed = displayed or {}
            displayed[spellRef] = true
            displayed[NormalizeToBase(spellRef)] = true
            local shade = ResolveToLive(spellRef)
            if shade then
                displayed[shade] = true
            end
            local num = RankName and RankName(spellRef)
            if num then
                displayedNames = displayedNames or {}
                displayedNames[num] = true
            end
        end
    end
    if not (displayed and next(displayed)) then
        return barSpells
    end

    -- Blizzard's tracked-cooldown catalog (talent-independent, arrangement-
    -- aware, and category-0/1/5/7-aware once the picker's category-set
    -- constants land) is the source untalented spells were materialized
    -- from; lets the keep test below also drop an untalented spell the user
    -- removed from tracking, invisible to `displayed` since untalented
    -- spells never get a live frame. nil provider -> untalented entries kept.
    local catalogKeys
    if mod.EnumerateCDMSettingsCatalog then
        local catalog = mod.EnumerateCDMSettingsCatalog(mod.CDM_ICON_CD_CATS)
        if catalog then
            catalogKeys = {}
            local getCdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
            local function AddCatalogVariant(val)
                if type(val) == "number" and not (issecretvalue and issecretvalue(val)) and val > 0 then
                    catalogKeys[val] = true
                end
            end
            -- Per-category live-set lookup for the hidden/removed check below
            -- (ns.CDMEntryHiddenOrRemoved), built once per category the first
            -- time it's seen this pass and reused for every entry in it --
            -- never refetched per id. Cats 0/1 hidden entries already read as
            -- HiddenActive/HiddenPassive and never reach this loop (excluded
            -- by EnumerateCDMSettingsCatalog's own wantSet test); self-mapping
            -- cats 5/7 keep their category when hidden/removed, so THEY need
            -- this extra check to stop a removed entry holding rank forever.
            local liveSetByCat = {}
            for _, ce in ipairs(catalog) do
                local details = getCdInfo and ce.cdID and getCdInfo(ce.cdID)
                local skip = false
                if mod.CDMEntryHiddenOrRemoved then
                    local lsl = liveSetByCat[ce.category]
                    if lsl == nil and mod.CDMBuildLiveCategorySetLookup then
                        lsl = mod.CDMBuildLiveCategorySetLookup(ce.category) or false
                        liveSetByCat[ce.category] = lsl
                    end
                    local verdict = mod.CDMEntryHiddenOrRemoved(ce.cdID, nil, details, lsl)
                    if verdict == "hidden" or verdict == "removed" then
                        skip = true
                    end
                end
                if not skip then
                    local s = ce.sid
                    if type(s) == "number" and s > 0 then
                        catalogKeys[s] = true
                        catalogKeys[NormalizeToBase(s)] = true
                        local shade = ResolveToLive(s)
                        if shade then
                            catalogKeys[shade] = true
                        end
                    end
                    -- Also index every id the entry itself links (spellID/
                    -- overrideSpellID/linkedSpellIDs): a stored BASE id only
                    -- matches the catalog through the entry's own linked set
                    -- once the override talent is dropped and the spellbook
                    -- link goes with it.
                    if details then
                        AddCatalogVariant(details.spellID)
                        AddCatalogVariant(details.overrideSpellID)
                        if details.linkedSpellIDs then
                            for _, lid in ipairs(details.linkedSpellIDs) do
                                AddCatalogVariant(lid)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Blizzard's own item rows (sd.nativeItems: entries the reseed listed for them):
    -- such an entry drops once Blizzard no longer tracks the row -- no live frame
    -- renders under its key AND the spec-agnostic category sets, populated and
    -- holding item rows, show no visible row of its category. Neither source judges
    -- alone: a frame is absent mid-rebuild, and a set can lack a viewer-bound id.
    -- Both built on first need, once per pass.
    local nativeLive, nativeCats
    local function NativeRowTracked(ident)
        if nativeLive == nil then
            nativeLive = {}
            local icons = mod.cdmBarIcons
            if icons then
                for _, entries in pairs(icons) do
                    for index = 1, #entries do
                        local ic = entries[index]
                        local fcN = ic and mod._ecmeFC[ic]
                        local k = fcN and fcN.spellID
                        if k and not ic._isItemPresetFrame and mod.IsItemPresetKey(k) then
                            nativeLive[k] = true
                        end
                    end
                end
            end
        end
        if nativeLive[ident] then
            return true
        end
        local pr = mod.ItemPresetForKey(ident)
        local catalog = pr and pr.nativeCategory
        if not catalog then
            return true
        end
        if nativeCats == nil then
            nativeCats = false
            local evicted = Enum and Enum.CooldownViewerCategory
            local getCdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
            if evicted and getCdInfo and mod.CDMBuildLiveCategorySetLookup then
                local cats = { evicted.SpecAgnosticEssential or 5, evicted.SpecAgnosticTracked or 6 }
                for ci = 1, #cats do
                    local keySet = mod.CDMBuildLiveCategorySetLookup(cats[ci])
                    if keySet and next(keySet) then
                        for cooldownId in pairs(keySet) do
                            local details = getCdInfo(cooldownId)
                            local sc = details and details.spellCategoryID
                            if type(sc) == "number" and not (issecretvalue and issecretvalue(sc)) then
                                -- An item row enumerates through this source: it may
                                -- judge. A hidden or removed row is not visible.
                                if not nativeCats then
                                    nativeCats = {}
                                end
                                local verdict = mod.CDMEntryHiddenOrRemoved
                                    and mod.CDMEntryHiddenOrRemoved(cooldownId, nil, details, keySet)
                                if verdict == nil then
                                    nativeCats[sc] = true
                                end
                            end
                        end
                    end
                end
            end
        end
        if not nativeCats then
            return true
        end -- no item row enumerates: keep
        return nativeCats[catalog] == true
    end

    local custom = barSpells.customSpellIDs
    local racials = _myRacialsSet
    local cdurs = barSpells.customSpellDurations
    local sdurs = barSpells.spellDurations
    local groups = barSpells.customSpellGroups
    local hosted = barSpells.hostedBuffSpellIDs
    -- Marker-present set: a hosted buff's PLAIN entry (its cooldown form)
    -- must not borrow the hosted exemption below once its own MARKER entry
    -- exists -- untracking the cooldown should drop it like any other
    -- cooldown while the hosted buff stays.
    local hostedMarkerFor
    if hosted then
        for _, mid in ipairs(barSpells.assignedSpells) do
            local mSid = mod.HostedBuffMarkerToSpell and mod.HostedBuffMarkerToSpell(mid)
            if mSid then
                hostedMarkerFor = hostedMarkerFor or {}
                hostedMarkerFor[mSid] = true
            end
        end
    end

    -- WoW Forever's full catalogue set and default-hidden set, built on first
    -- need (see below). A catalogue it cannot read keeps the spell (fails open).
    local foreverListed, defaultHidden
    local function DefaultHidden(ident)
        if not CludesUI.IS_FOREVER then
            return false
        end
        if defaultHidden == nil then
            defaultHidden = mod.CDMDefaultHiddenSet() or false
        end
        return not defaultHidden or mod.CDMIsDefaultHidden(defaultHidden, ident)
    end
    local writeIndex = 1
    for readIdx = 1, #barSpells.assignedSpells do
        local ident = barSpells.assignedSpells[readIdx]
        local keepSet = true
        -- A HOSTED buff is a real buff (never in the Essential/Utility
        -- viewer), so the "owned but not displayed -> drop" test below
        -- would wrongly delete it; always keep, like a custom spell ID/racial.
        if
            type(ident) == "number"
            and ident > 0
            and not (custom and custom[ident])
            and not (racials and racials[ident])
            and not (cdurs and cdurs[ident])
            and not (sdurs and sdurs[ident])
            and not (groups and groups[ident])
            and not (hosted and hosted[ident] and not (hostedMarkerFor and hostedMarkerFor[ident]))
            -- Drawn by an aura icon of ours (the WoW Forever Seals stand-in):
            -- user-added like a racial, never "owned but not displayed".
            and not (mod.CDM_AuraIconKeeps and mod.CDM_AuraIconKeeps(ident))
        then
            -- Plain Blizzard cooldown. Keep if still displayed OR if the
            -- player no longer HAS the spell (talented out): a talented-out
            -- cooldown must hold its rank so it returns to the SAME slot
            -- when re-talented. Only a spell still OWNED but removed from
            -- Blizzard's CDM tracking (gone from the catalog too) is
            -- genuinely user-cleared -> drop.
            local isShown = displayed[ident]
                or displayed[NormalizeToBase(ident)]
                or displayed[ResolveToLive(ident)]
                or (displayedNames ~= nil and displayedNames[RankName(ident) or false] == true)
            -- IsPlayerSpell is guarded (nil in some contexts): if
            -- unavailable, `have` is falsy so the spell is treated as
            -- untalented (kept unless the catalog says otherwise).
            local have = IsPlayerSpell
                and (
                    IsPlayerSpell(ident)
                    or IsPlayerSpell(NormalizeToBase(ident))
                    or IsPlayerSpell(ResolveToLive(ident))
                )
            if isShown then
                keepSet = true
            elseif
                catalogKeys
                and (
                    catalogKeys[ident]
                    or catalogKeys[NormalizeToBase(ident)]
                    or catalogKeys[ResolveToLive(ident)]
                )
            then
                -- Still tracked in Blizzard's catalog, just not displayed:
                -- untalented, conditionally pooled, or a BASE id whose
                -- tracked cooldown is a talent override the player dropped.
                -- Hold rank.
                keepSet = true
            elseif DefaultHidden(ident) then
                -- WoW Forever: in Not Displayed by Blizzard's default, not by
                -- the player: it holds its slot until displayed.
                keepSet = true
            elseif have then
                -- Owned but no longer tracked: the user cleared it from
                -- Blizzard's CDM tracking -> drop.
                keepSet = false
            elseif catalogKeys and not CludesUI.IS_FOREVER then
                -- Untalented: it only reached the preview by being
                -- materialized from the settings catalog, so it must also
                -- LEAVE when removed from tracking -> drop.
                keepSet = false
            elseif catalogKeys then
                -- WoW Forever: the same, but only for an id its catalogue
                -- lists (Not Displayed included). An id it does not list is
                -- a spell this client cannot see (a retail layout's), so it
                -- holds its place instead.
                if foreverListed == nil then
                    foreverListed = mod.CDMForeverListedSet() or false
                end
                keepSet = not (
                    foreverListed
                    and (
                        foreverListed[ident]
                        or foreverListed[NormalizeToBase(ident)]
                        or foreverListed[ResolveToLive(ident)]
                    )
                )
            else
                -- Untalented with no catalog signal (provider down): hold
                -- rank as the safe fallback so a transient gap never wipes
                -- an untalented assignment.
                keepSet = true
            end
        elseif barSpells.nativeItems and barSpells.nativeItems[ident] and mod.IsItemPresetKey(ident) then
            -- An entry the reseed listed for Blizzard's own item row: it goes
            -- once Blizzard no longer tracks the row (NativeRowTracked above).
            if not NativeRowTracked(ident) then
                keepSet = false
                barSpells.nativeItems[ident] = nil
            end
        end
        if keepSet then
            barSpells.assignedSpells[writeIndex] = ident
            writeIndex = writeIndex + 1
        end
    end
    for index = writeIndex, #barSpells.assignedSpells do
        barSpells.assignedSpells[index] = nil
    end

    -- Normalize the hosted-buff representation: a hosted buff owns a MARKER
    -- entry; a plain entry of the same id means the COOLDOWN form. Resolve
    -- each flagged id here, where displayed/catalog sets can tell the forms apart.
    if barSpells.hostedBuffSpellIDs and mod.HostedBuffMarker then
        local entries = barSpells.assignedSpells
        local ghostSd = mod.GetBarSpellData and mod.GetBarSpellData(GHOST_CD_BAR_KEY)
        local ghostList = ghostSd and ghostSd.assignedSpells
        local FindVar = mod.FindVariantIndexInList
        -- Plain entries claimed by OTHER visible bars (variant-aware): if
        -- the cooldown form lives elsewhere, a plain entry here is a
        -- resurrected artifact of the old shared-id model.
        local claimed
        do
            local bsAll = activeProfile.barSpells
            if bsAll and mod.StoreVariantValue then
                for key, bsd in pairs(bsAll) do
                    if
                        key ~= barId
                        and key ~= GHOST_CD_BAR_KEY
                        and type(bsd) == "table"
                        and type(bsd.assignedSpells) == "table"
                    then
                        for _, spellRef in ipairs(bsd.assignedSpells) do
                            if type(spellRef) == "number" and spellRef > 0 then
                                claimed = claimed or {}
                                mod.StoreVariantValue(claimed, spellRef, true, false)
                            end
                        end
                    end
                end
            end
        end
        for hostedSpellId in pairs(barSpells.hostedBuffSpellIDs) do
            if type(hostedSpellId) == "number" and hostedSpellId > 0 then
                local marker = mod.HostedBuffMarker(hostedSpellId)
                local markerIdx, plainIdx
                for index = 1, #entries do
                    local val = entries[index]
                    if val == marker then
                        markerIdx = index
                    elseif val == hostedSpellId then
                        plainIdx = index
                    end
                end
                if plainIdx then
                    local isCdForm = (
                        displayed[hostedSpellId]
                        or displayed[NormalizeToBase(hostedSpellId)]
                        or displayed[ResolveToLive(hostedSpellId)]
                        or (
                            catalogKeys
                            and (
                                catalogKeys[hostedSpellId]
                                or catalogKeys[NormalizeToBase(hostedSpellId)]
                                or catalogKeys[ResolveToLive(hostedSpellId)]
                            )
                        )
                    )
                            and true
                        or false
                    if isCdForm and ghostList and FindVar and FindVar(ghostList, hostedSpellId) then
                        isCdForm = false
                    end
                    if
                        isCdForm
                        and claimed
                        and mod.ResolveVariantValue
                        and mod.ResolveVariantValue(claimed, hostedSpellId)
                    then
                        isCdForm = false
                    end
                    if markerIdx then
                        if not isCdForm then
                            table.remove(entries, plainIdx)
                            mod._spellOrderDirty = true
                        end
                    elseif isCdForm then
                        table.insert(entries, plainIdx + 1, marker)
                        mod._spellOrderDirty = true
                    else
                        entries[plainIdx] = marker
                        mod._spellOrderDirty = true
                    end
                end
            end
        end
    end

    return barSpells
end

--- ns.RequestCDMDropPass(reason): fan-out entry point for the AUTOMATIC
--- triggers (once-per-spec reseed, settings close). Bails immediately while
--- the module/spec isn't ready to reconcile (zero cost while disabled);
--- coalesces concurrent requests behind the single pending flag; defers out
--- of combat via the shared regen waiter above. Interactive options edits
--- bypass this and call ns.ReconcileAssignedSpellDrops directly.
function mod.RequestCDMDropPass(reason)
    local profile = ECME and ECME.db and ECME.db.profile
    if not profile or not profile.cdmBars then
        return
    end

    local specProfile = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
    local specKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
    local activeProfile = specProfile and specKey and specProfile[specKey]
    if not activeProfile or not activeProfile._barFilterModelV6 then
        return
    end

    if mod._cdmDropPending then
        return
    end -- already scheduled, coalesce

    if InCombatLockdown() then
        ArmCDMDropRegenWaiter()
        return
    end

    -- Every reconcilable bar, not just the two default keys: custom CD/utility
    -- bars carry the same barTypes, and buff-family bars route internally to the
    -- ledger-gated pass (vouched-only, safe to automate). The ghost store is
    -- exempted inside the pass; skipped here too to spare the call.
    for barId, edge in pairs(barDataByKey) do
        if barId ~= GHOST_CD_BAR_KEY then
            local bt = edge and edge.barType
            if
                bt == "cooldowns"
                or bt == "utility"
                or (mod.IsBarBuffFamily and mod.IsBarBuffFamily(edge or barId))
            then
                mod.ReconcileAssignedSpellDrops(barId)
            end
        end
    end
    -- Items are preset-lane-only: whatever intake lane just ran (reseed,
    -- spillover, materializer) may have mirrored a native equipment entry
    -- into a store -- the same pass class erases it, so item rows can never
    -- persist. Tracking an item in Blizzard's CDM becomes a store no-op.
    if mod.PruneEquipmentBuffRows then
        mod.PruneEquipmentBuffRows()
    end
end

-------------------------------------------------------------------------------
--  Midnight hidden-channel reader (categories 0-8)
--  Blizzard folds both default-hide and user-hide into `category` for cats
--  0-3 (HiddenActive/HiddenPassive), but cats 5-8 self-map onto their OWN
--  category when hidden -- there is no separate isHidden field for them, so a
--  plain category read can never reveal a 5-8 hide; membership in the live
--  category set and isKnown carry that signal instead. GroupBuff (cat 4) is a
--  third, separate system: hidden spellIDs live in a flat array on the active
--  layout. Every provider read here is pcall-degraded: a down/errored read
--  always classifies as visible, so the drop pass this feeds never over-drops
--  on a bad read.
-------------------------------------------------------------------------------

-- Reject secret-tainted/non-positive numbers before they key a table or get compared.
local function _IsUsableSID(ident)
    if type(ident) ~= "number" then
        return false
    end
    if issecretvalue and issecretvalue(ident) then
        return false
    end
    return ident > 0 and ident == math.floor(ident)
end

-- Reads the ALREADY-BUILT display table, never the provider getters: those run
-- CheckBuildDisplayData, which rebuilds Blizzard's shared tables (and writes the
-- active layout) on OUR stack whenever the provider is dirty -- the HUD viewer
-- drops its OnDataChanged rebuild while hidden, so a post-match read used to
-- taint the viewer until reload. A dirty provider returns nil (not the previous
-- build): callers treat nil as "not ready" and fall back to keep-all/live-pool.
function mod.CDMGetProviderDisplayData(provider)
    if type(provider) ~= "table" or type(provider.GetDisplayData) ~= "function" then
        return nil, nil
    end
    if type(provider.IsDirty) == "function" then
        local okD, dirty = pcall(provider.IsDirty, provider)
        if not okD or dirty then
            return nil, nil
        end
    end
    local success, displayData = pcall(provider.GetDisplayData, provider)
    if not success or type(displayData) ~= "table" then
        return nil, nil
    end
    local ordered = displayData.orderedCooldownIDs
    local infoByID = displayData.cooldownInfoByID
    if type(ordered) ~= "table" or type(infoByID) ~= "table" then
        return nil, nil
    end
    return ordered, infoByID, displayData.cooldownDefaultsByID
end

-- Active BLIZZARD CDM layout id (the user's "preset"), not to be confused with
-- ns.GetActiveLayoutName (CUI's own account-wide spell-layout system). Used to
-- scope the automatic-reseed session gate by layout as well as spec: a spell
-- only tracked on a preset the user switches to LATER in the session was
-- invisible at the first reseed and must still get its own materialize pass.
function mod.GetActiveCDMLayoutID()
    if not (CooldownViewerSettings and CooldownViewerSettings.GetLayoutManager) then
        return nil
    end
    local okLM, layoutManager = pcall(CooldownViewerSettings.GetLayoutManager, CooldownViewerSettings)
    if not okLM or not layoutManager or not layoutManager.GetActiveLayoutID then
        return nil
    end
    local okID, layoutID = pcall(layoutManager.GetActiveLayoutID, layoutManager)
    if not okID then
        return nil
    end
    return layoutID
end

-- GroupBuff (category 4) hidden check: getter-only on the layout manager, never
-- WriteHiddenGroupBuffsToLayout. No active layout yet (fresh install, never
-- customized) is not "nothing hidden" evidence -- treated as unreachable and kept
-- visible, same as every other fail-open path in this file.
function mod.CDMIsGroupBuffSpellHidden(spellId)
    if not _IsUsableSID(spellId) then
        return false
    end
    if not (CooldownViewerSettings and CooldownViewerSettings.GetLayoutManager) then
        return false
    end
    local okLM, layoutManager = pcall(CooldownViewerSettings.GetLayoutManager, CooldownViewerSettings)
    if not okLM or not layoutManager then
        return false
    end
    local accessOnly = (Enum and Enum.CDMLayoutMode and Enum.CDMLayoutMode.AccessOnly) or false
    local okLayout, layout = pcall(layoutManager.GetActiveLayout, layoutManager, accessOnly)
    if not okLayout or not layout then
        return false
    end
    local okList, hiddenList = pcall(CooldownManagerLayout_GetHiddenGroupBuffs, layout)
    if not okList or type(hiddenList) ~= "table" then
        return false
    end
    for index = 1, #hiddenList do
        if hiddenList[index] == spellId then
            return true
        end
    end
    return false
end

-- Per-category "still a live member of this category" lookup for the cats-5-8 removal
-- signal below. allowUnlearned=true so this is the category's full membership universe,
-- not narrowed to currently-known spells (isKnown is a separate, independent signal in
-- CDMEntryHiddenOrRemoved). Build ONCE per category per pass and reuse for every id in
-- it -- never per id (mirrors Blizzard's own tInvert-on-GetCooldownViewerCategorySet
-- idiom). Returns nil (never an empty table) on failure so a caller checking
-- lookup[id] can tell "couldn't build" from "confirmed empty" -- collapsing the two
-- would make a dead provider read as "everything in this category is gone".
function mod.CDMBuildLiveCategorySetLookup(category)
    if type(category) ~= "number" then
        return nil
    end
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet) then
        return nil
    end
    local success, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
    if not success or type(ids) ~= "table" then
        return nil
    end
    local lookup = {}
    for index = 1, #ids do
        local ident = ids[index]
        if _IsUsableSID(ident) then
            lookup[ident] = true
        end
    end
    return lookup
end

-- Classifies one cooldownID against the hidden channel. Returns "hidden", "removed", or
-- nil (visible/keep -- also the result for any missing latch/provider/category match).
-- mergedInfo/rawInfo may be pre-fetched by the caller to batch a scan; liveSetLookup is
-- this id's category lookup from CDMBuildLiveCategorySetLookup above.
function mod.CDMEntryHiddenOrRemoved(cooldownId, combinedInfo, rawInfo, liveSetLookup)
    if not _IsUsableSID(cooldownId) then
        return nil
    end
    if not mod._cdmDataLoaded then
        return nil
    end -- pre-load reads see only static defaults

    local evicted = Enum and Enum.CooldownViewerCategory
    local hiddenActive = evicted and evicted.HiddenActive or -1
    local hiddenPassive = evicted and evicted.HiddenPassive or -2

    if combinedInfo == nil then
        local provider = CooldownViewerSettings
            and CooldownViewerSettings.GetDataProvider
            and CooldownViewerSettings:GetDataProvider()
        if provider then
            local _, infoByID = mod.CDMGetProviderDisplayData(provider)
            if infoByID then
                combinedInfo = infoByID[cooldownId]
            end
        end
    end

    -- Cats 0-3: default-hide and user-hide both fold into `category` -- complete on their
    -- own. A 5-8 entry that took the rare two-hop drag into Hidden also lands here.
    if combinedInfo and (combinedInfo.category == hiddenActive or combinedInfo.category == hiddenPassive) then
        return "hidden"
    end

    local catalog = combinedInfo and combinedInfo.category
    local groupBuff = evicted and evicted.GroupBuff or 4
    local spec5 = evicted and evicted.SpecAgnosticEssential or 5
    local spec6 = evicted and evicted.SpecAgnosticTracked or 6
    local equip7 = evicted and evicted.EquipSlotEssential or 7
    local equip8 = evicted and evicted.EquipSlotTracked or 8

    -- Only cats 4-8 need the raw (unreconciled) struct below; a mergedInfo hit already
    -- resolved to 0-3 is fully answered (visible) without another provider call.
    if catalog == nil or catalog == groupBuff or catalog == spec5 or catalog == spec6 or catalog == equip7 or catalog == equip8 then
        if rawInfo == nil and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            local success, details = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownId)
            if success then
                rawInfo = details
            end
        end
        if catalog == nil then
            catalog = rawInfo and rawInfo.category
        end
    end

    if type(catalog) ~= "number" then
        return nil
    end -- nothing to classify against: keep

    if catalog == groupBuff then
        local spellRef = (combinedInfo and combinedInfo.spellID) or (rawInfo and rawInfo.spellID)
        if mod.CDMIsGroupBuffSpellHidden(spellRef) then
            return "hidden"
        end
        return nil
    end

    if catalog ~= spec5 and catalog ~= spec6 and catalog ~= equip7 and catalog ~= equip8 then
        return nil -- cats 0-3 already resolved above; nothing further indicates hidden/removed
    end
    if rawInfo == nil then
        return nil
    end -- provider down: keep

    -- HideByDefault must NOT convict here. Blizzard's own provider proves the
    -- flag is a DEFAULT DISPOSITION, not live state: their CheckBuildDisplayData
    -- remaps HideByDefault entries into the Hidden pseudo-categories for cats
    -- 0-3, but for the self-mapping cats the remap is a deliberate no-op -- a
    -- user-tracked entry KEEPS the flag forever (the un-hide lives elsewhere in
    -- the layout). Convicting on it dropped every default-hidden-but-tracked
    -- SpecAgnostic entry on the first automatic pass (field 2026-08-13: shaman
    -- Gust of Wind). Until a proven per-entry user-hidden read exists for cats
    -- 5-8, the flag contributes nothing: keep. Worst case a genuinely hidden
    -- 5-8 entry lingers until manual removal -- the pre-fix status quo, and
    -- the correct failure direction.

    -- An EMPTY lookup must never judge: GetCooldownViewerCategorySet can return
    -- an empty table for a category it does not serve, indistinguishable from a
    -- real "no members" -- and treating that as removal dropped EVERY
    -- SpecAgnostic entry on the first automatic pass (field 2026-08-13: shaman
    -- Gust of Wind vanished from store/preview/picker while the live bar kept
    -- rendering via frames-as-truth). Same zero-values disease as
    -- GetPlayerAuraBySpellID: an API answering "nothing" for what it cannot
    -- see. Only a POPULATED live set may testify that this id fell out of it.
    if liveSetLookup and next(liveSetLookup) and liveSetLookup[cooldownId] == nil then
        return "removed" -- dropped out of the category's live set (unequipped/spec lost)
    end

    if rawInfo.isKnown == false then
        return "removed" -- cats 5-8 ONLY; 0-3 rank-holding depends on unknown-but-cataloged survival
    end

    return nil
end

-- WoW Forever: every spell id Forever's Cooldown Manager catalogue lists, in
-- any category, shown or Not Displayed, with base and live forms. A stored id
-- outside it is a spell this client cannot see (a retail-only spell a retail
-- layout carried in): the drop passes keep it and the options preview gives
-- it no slot. nil off Forever or while the catalogue is not readable (callers
-- then keep everything). Read-only, drop-pass and options time only.
function mod.CDMForeverListedSet()
    if not CludesUI.IS_FOREVER then
        return nil
    end
    local prefs = _G.CooldownViewerSettings
    if not prefs or type(prefs.GetDataProvider) ~= "function" then
        return nil
    end
    local okP, provider = pcall(prefs.GetDataProvider, prefs)
    if not okP or type(provider) ~= "table" then
        return nil
    end
    local ordered = mod.CDMGetProviderDisplayData(provider)
    local getCdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not (ordered and getCdInfo) then
        return nil
    end
    local NormalizeToBase, ResolveToLive = mod.NormalizeToBase, mod.ResolveToLive
    local keySet = {}
    local function Add(val)
        if _IsUsableSID(val) then
            keySet[val] = true
            keySet[NormalizeToBase(val)] = true
            keySet[ResolveToLive(val)] = true
        end
    end
    for _, cooldownId in ipairs(ordered) do
        local details = _IsUsableSID(cooldownId) and getCdInfo(cooldownId)
        if details then
            Add(details.spellID)
            Add(details.overrideSpellID)
            if type(details.linkedSpellIDs) == "table" then
                for _, lid in ipairs(details.linkedSpellIDs) do
                    Add(lid)
                end
            end
        end
    end
    if not next(keySet) then
        return nil
    end
    return keySet
end

-- WoW Forever: which cooldown and utility entries are in Not Displayed only by
-- Forever's catalogue default (current category hidden and equal to the
-- default), keyed by spell id, base and live forms and rank name: true for
-- those, false for every other cooldown entry, so a key two entries share never
-- reads as default-hidden. Blizzard saves no category equal to its default, so
-- an entry the player showed and hid again reads as default-hidden too. nil off
-- Forever or while the catalogue is not readable. Read with ns.CDMIsDefaultHidden.
function mod.CDMDefaultHiddenSet()
    if not CludesUI.IS_FOREVER then
        return nil
    end
    local prefs = _G.CooldownViewerSettings
    if not prefs or type(prefs.GetDataProvider) ~= "function" then
        return nil
    end
    local okP, provider = pcall(prefs.GetDataProvider, prefs)
    if not okP or type(provider) ~= "table" then
        return nil
    end
    local _, infoByID, defaultsByID = mod.CDMGetProviderDisplayData(provider)
    if not infoByID then
        return nil
    end
    local keySet = {}
    -- cooldownDefaultsByID is Blizzard's internal table, not an API: without it
    -- no entry reads as default-hidden, and an entry it lacks is left out.
    if type(defaultsByID) ~= "table" then
        return keySet
    end
    local evicted = Enum.CooldownViewerCategory
    local hidden = evicted.HiddenActive
    local NormalizeToBase, ResolveToLive, RankName = mod.NormalizeToBase, mod.ResolveToLive, mod.CDMRankName
    local function Mark(key, dh)
        if key ~= nil and keySet[key] ~= false then
            keySet[key] = dh
        end
    end
    local function Add(val, dh)
        if _IsUsableSID(val) then
            Mark(val, dh)
            Mark(NormalizeToBase(val), dh)
            Mark(ResolveToLive(val), dh)
            Mark(RankName and RankName(val), dh)
        end
    end
    for cooldownId, details in pairs(infoByID) do
        local def = defaultsByID[cooldownId]
        local defCat = def and def.category
        if defCat == evicted.Essential or defCat == evicted.Utility or defCat == hidden then
            local dh = details.category == hidden and defCat == hidden
            Add(details.spellID, dh)
            Add(details.overrideSpellID, dh)
            if type(details.linkedSpellIDs) == "table" then
                for _, lid in ipairs(details.linkedSpellIDs) do
                    Add(lid, dh)
                end
            end
        end
    end
    return keySet
end

--- True when a stored spell id is a default-hidden entry of `set`
--- (ns.CDMDefaultHiddenSet): by id, base or live form, by rank name only when
--- no cooldown entry lists the id.
function mod.CDMIsDefaultHidden(keySet, ident)
    local val = keySet[ident]
    if val == nil then
        val = keySet[mod.NormalizeToBase(ident)]
    end
    if val == nil then
        val = keySet[mod.ResolveToLive(ident)]
    end
    if val == nil and mod.CDMRankName then
        val = keySet[mod.CDMRankName(ident) or false]
    end
    return val == true
end

-------------------------------------------------------------------------------
--  Buff-family assigned-spell reconcile
--
--  Drops a stored buff-family id only once every member of its LEARNED variant-
--  alias family (ns.GetBuffVariantAliases / ns.LearnBuffVariantAlias, populated
--  from linkedSpellIDs while each form is live) is absent from the current
--  buff-category catalog AND not displayed. UN-LEARNED ids are VOUCHED-ONLY
--  exempt: the ledger must know the id before absence may convict (never-
--  learned = keep unconditionally, the June-ban tradeoff).
--  This is what makes a dual-tracked spell (one stored id, a different id on
--  every live frame) survivable once the pairing has been observed even a
--  single time on this spec -- see the ban comment on
--  ns.SyncExtraBuffBarsWithViewer (CUI_CDM_HookViewers.lua) for why a
--  presence-only prune is unsafe without it. Reuses `_IsUsableSID` from the
--  hidden-channel reader above (single file-scope copy) and the shared
--  `ArmCDMDropRegenWaiter` from ns.ReconcileAssignedSpellDrops's block
--  (single resident implementation, RS3) rather than redefining either.
-------------------------------------------------------------------------------

-- Buff-family present-set: every non-hidden, non-removed spellID/overrideSpellID/
-- linkedSpellIDs member currently catalogued under TrackedBuff/TrackedBar/GroupBuff,
-- plus SpecAgnosticTracked/EquipSlotTracked as a safety superset (membership there can
-- only widen KEEP, never enable a new DROP), plus every live displayed buff-icon
-- spellID. READ-only against the settings provider; nil (provider unhealthy, caller
-- keeps all) if the provider/category APIs are unreachable or no entry is found.
local function BuildBuffFamilyPresentSet()
    local prefs = _G.CooldownViewerSettings
    if not prefs or type(prefs.GetDataProvider) ~= "function" then
        return nil
    end
    local okP, provider = pcall(prefs.GetDataProvider, prefs)
    if not okP or type(provider) ~= "table" then
        return nil
    end
    -- Read the already-built display table, never the getters that would
    -- build it (see ns.CDMGetProviderDisplayData).
    local ordered, infoByID = mod.CDMGetProviderDisplayData(provider)
    if not ordered then
        return nil
    end
    local getCdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not getCdInfo then
        return nil
    end
    local evicted = Enum and Enum.CooldownViewerCategory
    if not evicted then
        return nil
    end

    local wantCats = {
        [evicted.TrackedBuff or 2] = true,
        [evicted.TrackedBar or 3] = true,
        [evicted.GroupBuff or 4] = true,
        [evicted.SpecAgnosticTracked or 6] = true,
        [evicted.EquipSlotTracked or 8] = true,
    }

    -- Per-category live set: built once per category and reused for every id in that
    -- category, via the shared hidden-channel builder (pcall-safe, id-gated) so this
    -- present-set can never drift from the drop pass's own category reads.
    local liveSetByCat = {}
    if mod.CDMBuildLiveCategorySetLookup then
        for catalog in pairs(wantCats) do
            liveSetByCat[catalog] = mod.CDMBuildLiveCategorySetLookup(catalog)
        end
    end

    local present, sawEntry = {}, false
    for _, cooldownId in ipairs(ordered) do
        local combinedInfo = _IsUsableSID(cooldownId) and infoByID[cooldownId]
        local category = type(combinedInfo) == "table" and combinedInfo.category
        if category ~= nil and wantCats[category] then
            sawEntry = true
            local rawInfo = getCdInfo(cooldownId)
            -- "hidden"/"removed" entries contribute nothing (absent-or-hidden = absent).
            -- A nil verdict (visible, or the hidden-channel reader not yet available)
            -- means included -- this can only ever widen the present-set, never shrink it.
            local verdict = mod.CDMEntryHiddenOrRemoved
                and mod.CDMEntryHiddenOrRemoved(cooldownId, combinedInfo, rawInfo, liveSetByCat[category])
            if verdict == nil and rawInfo then
                if _IsUsableSID(rawInfo.spellID) then
                    present[rawInfo.spellID] = true
                end
                if _IsUsableSID(rawInfo.overrideSpellID) then
                    present[rawInfo.overrideSpellID] = true
                end
                if type(rawInfo.linkedSpellIDs) == "table" then
                    for _, lsid in ipairs(rawInfo.linkedSpellIDs) do
                        if _IsUsableSID(lsid) then
                            present[lsid] = true
                        end
                    end
                end
            end
        end
    end
    if not sawEntry then
        return nil
    end

    -- Union live displayed buff-icon frame ids: shown always means keep, regardless of
    -- catalog/hidden-channel state.
    if mod.EnumerateCDMViewerSpells then
        for _, entry in ipairs(mod.EnumerateCDMViewerSpells(true)) do
            if _IsUsableSID(entry.sid) then
                present[entry.sid] = true
            end
        end
    end
    return present
end

-- Entry point for the buff-family branch of the assigned-spell reconcile. Self-contained
-- (own guards, own health gate) so it stays correct regardless of caller. Reached today via
-- ns.ReconcileAssignedSpellDrops's buff-family branch (RS3, above), which any caller passing
-- a buff-family barKey exercises -- including the interactive options call sites. Extending
-- the automatic scheduler (ns.RequestCDMDropPass) to also iterate buff-family bar keys on
-- the reseed/settings-close/regen edges is a natural follow-up, not required for this
-- function to be reachable.
function mod.ReconcileBuffFamilyDrops(barId)
    local profile = ECME and ECME.db and ECME.db.profile
    if not profile or not profile.cdmBars then
        return nil
    end
    if not (mod.IsBarBuffFamily and mod.IsBarBuffFamily(barId)) then
        return nil
    end
    local barSpells = mod.GetBarSpellData and mod.GetBarSpellData(barId)
    if not barSpells or not barSpells.assignedSpells or #barSpells.assignedSpells == 0 then
        return barSpells
    end

    local specProfile = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
    local specKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
    local prof = specProfile and specKey and specProfile[specKey]
    if not prof or not prof._barFilterModelV6 or prof._importGhostMode then
        return barSpells
    end
    -- Data-loaded latch: unset until VARIABLES_LOADED + PLAYER_ENTERING_WORLD +
    -- COOLDOWN_VIEWER_DATA_LOADED have all fired, so this never drops against static
    -- defaults before persisted hide/recategorize overrides are merged in.
    if not mod._cdmDataLoaded then
        return barSpells
    end
    if InCombatLockdown() then
        -- Shared regen waiter (defined with ns.ReconcileAssignedSpellDrops /
        -- ns.RequestCDMDropPass, RS3/RS4 above): queues the after-combat entry
        -- that clears ns._cdmDropPending and re-requests a pass. Bare-setting
        -- the flag without arming the waiter would permanently disable every future
        -- automatic pass this session (cd/utility included) since nothing would ever clear it.
        ArmCDMDropRegenWaiter()
        return barSpells
    end

    local present = BuildBuffFamilyPresentSet()
    if not present then
        return barSpells
    end -- provider unhealthy: fail open, keep everything

    local ledger = prof.buffVariantAliases
    local custom = barSpells.customSpellIDs
    local racials = mod._myRacialsSet
    local cdurs = barSpells.customSpellDurations
    local sdurs = barSpells.spellDurations
    local groups = barSpells.customSpellGroups
    local hosted = barSpells.hostedBuffSpellIDs

    local dropped = false
    -- WoW Forever's full catalogue set, built on first need (see below).
    local foreverListed
    local writeIndex = 1
    for readIdx = 1, #barSpells.assignedSpells do
        local ident = barSpells.assignedSpells[readIdx]
        local keepSet = true
        if
            type(ident) == "number"
            and ident > 0
            and not (custom and custom[ident])
            and not (racials and racials[ident])
            and not (cdurs and cdurs[ident])
            and not (sdurs and sdurs[ident])
            and not (groups and groups[ident])
            and not (hosted and hosted[ident])
        then
            -- Ledger closure: BFS over the persisted adjacency sets, seeded with the
            -- stored id AND its base/override forms (a stored base id whose live form
            -- was the one observed must still find its family).
            local seedBase = mod.NormalizeToBase and mod.NormalizeToBase(ident) or ident
            local seedLive = mod.ResolveToLive and mod.ResolveToLive(ident) or ident
            local ledgerClosure = { [ident] = true, [seedBase] = true, [seedLive] = true }
            -- VOUCHED-ONLY (the June dual-tracked ban, reaffirmed 2026-08-13): the
            -- ledger must be able to TESTIFY about this id before absence may convict.
            -- A never-learned id (single-form buffs never enter the ledger; dual-
            -- tracked families before their first live observation) is KEPT
            -- unconditionally -- it lingers as a removable preview entry, the
            -- accepted June tradeoff. Family-of-one drop semantics silently
            -- resurrected the Vengeance Meta data-loss class and are FORBIDDEN.
            local vouched = false
            if ledger and (ledger[ident] or ledger[seedBase] or ledger[seedLive]) then
                vouched = true
            end
            if ledger then
                local frontier, num = {}, 0
                for s0 in pairs(ledgerClosure) do
                    num = num + 1
                    frontier[num] = s0
                end
                while num > 0 do
                    local nf, nn = nil, 0
                    for index = 1, num do
                        local partners = ledger[frontier[index]]
                        if partners then
                            for partner in pairs(partners) do
                                if _IsUsableSID(partner) and not ledgerClosure[partner] then
                                    ledgerClosure[partner] = true
                                    nn = nn + 1
                                    nf = nf or {}
                                    nf[nn] = partner
                                end
                            end
                        end
                    end
                    frontier, num = nf, nn
                end
            end
            -- Union every closure member's base/override variants (StoreVariantValue-
            -- style expansion) so a talent swap on any family member still resolves.
            local family = {}
            for member in pairs(ledgerClosure) do
                if mod.StoreVariantValue then
                    mod.StoreVariantValue(family, member, true, false)
                else
                    family[member] = true
                end
            end
            local anyPresent = false
            for member in pairs(family) do
                if present[member] then
                    anyPresent = true
                    break
                end
            end
            -- WoW Forever: a family its catalogue does not list at all (Not
            -- Displayed included) is a buff this client cannot see (a retail
            -- layout's): it holds its place instead.
            local unseen = false
            if vouched and not anyPresent and CludesUI.IS_FOREVER then
                if foreverListed == nil then
                    foreverListed = mod.CDMForeverListedSet() or false
                end
                unseen = true
                if foreverListed then
                    for member in pairs(family) do
                        if foreverListed[member] then
                            unseen = false
                            break
                        end
                    end
                end
            end
            if vouched and not anyPresent and not unseen then
                keepSet = false
                dropped = true
            end
        end
        if keepSet then
            barSpells.assignedSpells[writeIndex] = ident
            writeIndex = writeIndex + 1
        end
    end
    for index = writeIndex, #barSpells.assignedSpells do
        barSpells.assignedSpells[index] = nil
    end
    if dropped then
        mod._spellOrderDirty = true
    end
    return barSpells
end

--- Repopulate all main bars from Blizzard CDM for the current spec.
--- Wipes ONLY Blizzard-sourced entries (positive spell IDs that the CDM
--- viewer owns) from assignedSpells/removedSpells, then rebuilds route
--- maps and reanchors. Preserves user-added entries:
---   * Negative IDs (trinket slots -13/-14, item presets <= -100)
---   * Custom spell IDs (entries in sd.customSpellIDs)
---   * Racial spells (entries in _myRacialsSet), except on a repopulate another
---     addon requested (fromRequest, CludesUI.RequestCDMRepopulate) while the
---     racial has a place: the bar ns.RACIAL_REPOP_BAR lists for it, else where
---     Blizzard's viewers show it.
function mod.RepopulateFromBlizzard(fromRequest)
    local profile = ECME.db and ECME.db.profile
    if not profile or not profile.cdmBars then
        return
    end
    local specKey = mod.GetActiveSpecKey()
    if not specKey or specKey == "0" then
        return
    end

    -- Requested repopulate: the racial slot's place. A listed racial goes to the
    -- end of its bar (below); an unlisted one shown by Blizzard's viewers is
    -- placed by the reseed like any spell; with neither the slot stays as it is.
    local racialSid, racialBar, racialMoves
    if fromRequest then
        racialSid = ResolveActiveRacial()
        racialBar = racialSid and mod.RACIAL_REPOP_BAR[racialSid]
        racialMoves = racialBar ~= nil
        if racialSid and not racialMoves then
            for _, entry in ipairs(mod.EnumerateCDMViewerSpells(false)) do
                if _myRacialsSet[entry.sid] then
                    racialMoves = true
                    break
                end
            end
        end
    end

    -- A spell ID is "user-added" (preserved across repopulate) if it's a negative preset marker, a custom spell ID added via the picker, or a racial belonging to this character.
    local function IsUserAdded(barSpells, ident)
        if type(ident) ~= "number" or ident == 0 then
            return false
        end
        if ident < 0 then
            return true
        end
        if barSpells.customSpellIDs and barSpells.customSpellIDs[ident] then
            return true
        end
        if _myRacialsSet and _myRacialsSet[ident] and not racialMoves then
            return true
        end
        -- Drawn by an aura icon of ours (the WoW Forever Seals stand-in): no
        -- Blizzard frame would bring it back.
        if mod.CDM_AuraIconKeeps and mod.CDM_AuraIconKeeps(ident) then
            return true
        end
        -- A positive id carrying a stored duration is one of OUR injected preset/custom buffs
        -- (Bloodlust/Heroism, potions, Time Spiral, custom buff IDs). Blizzard-tracked buffs are
        -- never written into assignedSpells with a duration, so this can only be a user-added entry -- preserve it. Presets predate the customSpellIDs flag, so the flag alone is not enough.
        if barSpells.spellDurations and (barSpells.spellDurations[ident] or 0) > 0 then
            return true
        end
        return false
    end

    -- Filter a list in place: keep only entries IsUserAdded returns true for.
    local function FilterListPreservingUserAdded(barSpells, entries)
        if type(entries) ~= "table" then
            return
        end
        local writeIndex = 1
        for readIdx = 1, #entries do
            local ident = entries[readIdx]
            if IsUserAdded(barSpells, ident) then
                entries[writeIndex] = ident
                writeIndex = writeIndex + 1
            end
        end
        for index = writeIndex, #entries do
            entries[index] = nil
        end
    end

    -- Filter a set in place (keys = spell IDs): drop keys that aren't user-added.
    local function FilterSetPreservingUserAdded(barSpells, keySet)
        if type(keySet) ~= "table" then
            return
        end
        for ident in pairs(keySet) do
            if not IsUserAdded(barSpells, ident) then
                keySet[ident] = nil
            end
        end
    end

    -- Filter Blizzard entries off all CD/utility bars (main + custom). Skip ghost, custom_buff,
    -- and default buff bar. The default buff bar (key == "buffs") has no assignedSpells to filter -- Blizzard's viewer is the authority. Extra buff bars ARE filtered for user assignments.
    for _, barInfo in ipairs(profile.cdmBars.bars) do
        if
            not barInfo.isGhostBar
            and barInfo.key ~= "buffs"
            and (
                barInfo.barType == "cooldowns"
                or barInfo.barType == "utility"
                or barInfo.barType == "buffs"
                or MAIN_BAR_KEYS[barInfo.key]
            )
        then
            local barSpells = mod.GetBarSpellData(barInfo.key)
            if barSpells then
                FilterListPreservingUserAdded(barSpells, barSpells.assignedSpells)
                FilterSetPreservingUserAdded(barSpells, barSpells.removedSpells)
                -- spellSettings is per-spell config (font color, etc.) -- preserve entirely so user-added customs keep their styling.
            end
        end
    end

    -- Ghost bars hold Blizzard-owned spells the user explicitly hid. Filter the same way so user-added presets that may have been routed here (rare edge case) are preserved.
    local ghostSD = mod.GetBarSpellData(GHOST_CD_BAR_KEY)
    if ghostSD then
        FilterListPreservingUserAdded(ghostSD, ghostSD.assignedSpells)
        FilterSetPreservingUserAdded(ghostSD, ghostSD.removedSpells)
    end
    -- Ghost buff bar removed: buff visibility managed by Blizzard CDM.

    local buffSD = mod.GetBarSpellData("buffs")
    if buffSD then
        buffSD.buffDisplayOrder = nil
        buffSD._buffDisplayOrderUserModified = nil
    end
    mod._spellOrderDirty = true
    mod._cdmBuffOrderDirty = true -- re-seed from Blizzard order on next reanchor

    -- Under the diversion-set model, "repopulate from Blizzard" is just "wipe diversions and let the route map's spillover show everything from the viewer" -- the wipes above are all that is needed.

    mod.FullCDMRebuild("repopulate")
    if mod.CollectAndReanchor then
        mod.CollectAndReanchor()
    end

    mod.ReseedAssignedSpellsFromLiveIcons()

    -- A listed racial: its one slot at the end of its bar, wherever the reseed
    -- put Blizzard's copy. Buff bars keep their entries (a racial's buff can
    -- share its spell ID).
    local racialSD = racialBar and mod.GetBarSpellData(racialBar)
    if racialSD then
        for _, bar in ipairs(profile.cdmBars.bars) do
            local isBuff = bar.barType == "custom_buff" or mod.IsBarBuffFamily(bar)
            local barSpells = not isBuff and bar.key and mod.GetBarSpellData(bar.key)
            local entries = barSpells and barSpells.assignedSpells
            if entries then
                for index = #entries, 1, -1 do
                    if ALL_RACIAL_SPELLS[entries[index]] then
                        table.remove(entries, index)
                    end
                end
            end
        end
        if not racialSD.assignedSpells then
            racialSD.assignedSpells = {}
        end
        racialSD.assignedSpells[#racialSD.assignedSpells + 1] = racialSid
        mod._spellOrderDirty = true
        if mod.RebuildSpellRouteMap then
            mod.RebuildSpellRouteMap()
        end
        if mod.QueueReanchor then
            mod.QueueReanchor()
        end
    end

    C_Timer.After(1, function()
        local specKey = mod.GetActiveSpecKey()
        if specKey and specKey ~= "0" then
            SaveCurrentSpecProfile()
        end
    end)
    return true
end

-------------------------------------------------------------------------------
--  Queued repopulate (public API, PLUGINS_API.md)
--  CludesUI.RequestCDMRepopulate([specIDs]) queues the Repopulate from
--  Blizzard CDM button's work for this character: each requested spec is
--  repopulated the next time it is active and settled, at the final layout
--  pass of a login, reload or spec swap (Blizzard's viewer pools hold that
--  spec's icons by then) once Blizzard has loaded its saved layouts, never
--  during combat. A profile installer that writes
--  Blizzard CDM layouts calls it before its ReloadUI. Requests are kept per
--  character, by the game's own spec IDs, in CludesUIDB.cdmRepopulatePending.
--  CludesUI.GetCDMRepopulateStatus([specID]) tells the installer how a
--  request went: "pending" while queued, then "done" with the time and the
--  Blizzard layout ID the run read (CludesUIDB.cdmRepopulateDone, cleared by
--  a new request for that spec), or nil when no run finished.
-------------------------------------------------------------------------------
local function LiveSpecID()
    local index = C_SpecializationInfo.GetSpecialization()
    if not index or index == 0 then
        return nil
    end
    local ident = C_SpecializationInfo.GetSpecializationInfo(index)
    if not ident or ident == 0 then
        return nil
    end
    return ident
end

local function IsSpecID(ident)
    return type(ident) == "number" and ident > 0 and ident == math.floor(ident)
end

-- specIDs: nil = every spec of the player's class, or one spec ID, or a list of them.
-- Returns true once queued, false when nothing valid was given.
function CludesUI.RequestCDMRepopulate(specIDs)
    if not CludesUIDB then
        return false
    end
    local ids = {}
    if specIDs == nil then
        local _, _, classID = UnitClass("player")
        local total = classID and C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
        for index = 1, total do
            local ident = GetSpecializationInfoForClassID(classID, index)
            if IsSpecID(ident) then
                ids[#ids + 1] = ident
            end
        end
    elseif IsSpecID(specIDs) then
        ids[1] = specIDs
    elseif type(specIDs) == "table" then
        for _, ident in ipairs(specIDs) do
            if IsSpecID(ident) then
                ids[#ids + 1] = ident
            end
        end
    end
    if #ids == 0 then
        return false
    end
    local waiting = CludesUIDB.cdmRepopulatePending or {}
    CludesUIDB.cdmRepopulatePending = waiting
    local characterKey = mod.GetCharKey()
    local mine = waiting[characterKey] or {}
    waiting[characterKey] = mine
    -- A new request's status starts over: an older run's record never stands
    -- in for this one.
    local finished = CludesUIDB.cdmRepopulateDone
    local runs = finished and finished[characterKey]
    for _, ident in ipairs(ids) do
        mine[ident] = true
        if runs then
            runs[ident] = nil
        end
    end
    if runs and not next(runs) then
        finished[characterKey] = nil
    end
    if finished and not next(finished) then
        CludesUIDB.cdmRepopulateDone = nil
    end
    return true
end

-- "pending" while the spec (default: the live one) is queued for this
-- character; "done", time(), layoutID once its queued run finished (layoutID
-- nil when no saved Blizzard layout was active); nil otherwise.
function CludesUI.GetCDMRepopulateStatus(specID)
    if not CludesUIDB then
        return nil
    end
    if specID == nil then
        specID = LiveSpecID()
    end
    if not IsSpecID(specID) then
        return nil
    end
    local characterKey = mod.GetCharKey()
    local waiting = CludesUIDB.cdmRepopulatePending
    if waiting and waiting[characterKey] and waiting[characterKey][specID] then
        return "pending"
    end
    local finished = CludesUIDB.cdmRepopulateDone
    local run = finished and finished[characterKey] and finished[characterKey][specID]
    if run then
        return "done", run.time, run.layoutID
    end
    return nil
end

-- Runs the live spec's queued repopulate, if any. Called a frame after the
-- final layout pass; in combat it waits for combat to end and checks again.
-- Until Blizzard has loaded its saved layouts its viewers show the class
-- defaults (a new character's first login can reach the final pass first),
-- so the request waits for the data-loaded wake in CUI_CDM_Lifecycle.lua.
function mod.RunQueuedRepopulate()
    local waiting = CludesUIDB and CludesUIDB.cdmRepopulatePending
    if not waiting then
        return
    end
    local characterKey = mod.GetCharKey()
    local mine = waiting[characterKey]
    if not mine then
        return
    end
    local ident = LiveSpecID()
    if not ident or not mine[ident] then
        return
    end
    if not mod._cdmDataLoaded then
        mod._repopAwaitsLayouts = true
        return
    end
    if InCombatLockdown() then
        mod.CombatQueue.Defer("CDMQueuedRepopulate", mod.RunQueuedRepopulate)
        return
    end
    -- Taken off the queue before it runs, so a failure can never repeat it.
    mine[ident] = nil
    if not next(mine) then
        waiting[characterKey] = nil
    end
    if not next(waiting) then
        CludesUIDB.cdmRepopulatePending = nil
    end
    -- Recorded only once the run finished (GetCDMRepopulateStatus).
    if mod.RepopulateFromBlizzard(true) then
        local finished = CludesUIDB.cdmRepopulateDone or {}
        CludesUIDB.cdmRepopulateDone = finished
        local runs = finished[characterKey] or {}
        finished[characterKey] = runs
        runs[ident] = { time = time(), layoutID = mod.GetActiveCDMLayoutID() }
    end
end

Inner.CDMFirstLoginCapture = CDMFirstLoginCapture
Inner.broken = false
