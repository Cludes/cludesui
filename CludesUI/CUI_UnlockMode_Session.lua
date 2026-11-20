if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnlockMode_Session.lua
--  Unlock Mode session: top banner HUD, save / revert, spec overrides,
--  open / close with their animations, the one-time how-to-use tip.
--  Loaded after CUI_UnlockMode.lua; _unlockCoreInit runs it once with UM.
-------------------------------------------------------------------------------
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS -- standalone builds: the core's own table (CludesUI.lua)
CUI_NS.unlockParts = CUI_NS.unlockParts or {}
CUI_NS.unlockParts.Session = function(LM)
    local mod, ABAR, min, max = CUI_NS, LM.EAB, LM.min, LM.max
    local sin, FONT_PATH, MOVER_ALPHA, ALL_BAR_ORDER = LM.sin, LM.FONT_PATH, LM.MOVER_ALPHA, LM.ALL_BAR_ORDER
    local registeredElements, registeredOrder, RebuildRegisteredOrder, handles =
        LM.registeredElements, LM.registeredOrder, LM.RebuildRegisteredOrder, LM.movers
    local lockAnimFrame, pendingPositions, snapshotPositions, snapshotAnchors =
        LM.lockAnimFrame, LM.pendingPositions, LM.snapshotPositions, LM.snapshotAnchors
    local snapshotSizes, snapshotWidthMatch, snapshotHeightMatch, snapshotGrowDirs =
        LM.snapshotSizes, LM.snapshotWidthMatch, LM.snapshotHeightMatch, LM.snapshotGrowDirs
    local GridHudAlpha, GridLabelText, CycleGridMode, _blizzOwnedOverlays =
        LM.GridHudAlpha, LM.GridLabelText, LM.CycleGridMode, LM._blizzOwnedOverlays
    local GetAnchorDB, MatchH, ValidateStoredLinks, FadeOverlayForSelectElement =
        LM.GetAnchorDB, LM.MatchH, LM.ValidateStoredLinks, LM.FadeOverlayForSelectElement
    local CancelPickMode, ReapplyAllAnchors, ConvertToCenterPos, ClearBarPosition =
        LM.CancelPickMode, LM.ReapplyAllAnchors, LM.ConvertToCenterPos, LM.ClearBarPosition
    local InstallAnchorGuard, GetAccent, CreateGrid, HideAllGuidesAndHighlight =
        LM.InstallAnchorGuard, LM.GetAccent, LM.CreateGrid, LM.HideAllGuidesAndHighlight
    local SelectMover, DeselectMover, ApplyDarkOverlays, SetupArrowKeyFrame =
        LM.SelectMover, LM.DeselectMover, LM.ApplyDarkOverlays, LM.SetupArrowKeyFrame
    local SortMoverFrameLevels, ShowBlizzOwnedOverlays, HideBlizzOwnedOverlays, CreateMover =
        LM.SortMoverFrameLevels, LM.ShowBlizzOwnedOverlays, LM.HideBlizzOwnedOverlays, LM.CreateMover

    -------------------------------------------------------------------------------
    --  The toolbar is CUI_UnlockMode_Bar.lua's (UM.CreateBar, built on the first
    --  open). BANNER_PX_H: how far above the screen it waits before dropping in.
    -------------------------------------------------------------------------------
    local BANNER_PX_H = 120
    local function CreateHUD(hostFrame)
        return LM.CreateBar(hostFrame)
    end

    -------------------------------------------------------------------------------
    --  Save / Revert / Close helpers
    -------------------------------------------------------------------------------

    -- Snapshot current bar positions when entering unlock mode
    local function SnapshotPositions()
        wipe(snapshotPositions)
        -- Action bars: capture from barPositions DB
        local saved = LM.GetPositionDB()
        if saved then
            for barId, place in pairs(saved) do
                snapshotPositions[barId] =
                    { point = place.point, relPoint = place.relPoint, x = place.x, y = place.y }
            end
        end
        -- Action bars: for any bar that has NO saved position, capture its live position
        for _, barId in ipairs(ALL_BAR_ORDER) do
            if not snapshotPositions[barId] then
                local barFrame = LM.GetBarFrame(barId)
                if barFrame then
                    local nPts = barFrame:GetNumPoints()
                    if nPts and nPts > 0 then
                        local anchorPoint, _, relPoint, posX, posY = barFrame:GetPoint(1)
                        if anchorPoint then
                            snapshotPositions[barId] =
                                { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                        end
                    end
                end
            end
        end
        -- Registered elements: snapshot via loadPosition or live frame position
        RebuildRegisteredOrder()
        for _, barKey in ipairs(registeredOrder) do
            if not snapshotPositions[barKey] then
                local element = registeredElements[barKey]
                if element then
                    local place = element.loadPosition and element.loadPosition(barKey)
                    if place then
                        snapshotPositions[barKey] = {
                            point = place.point,
                            relPoint = place.relPoint or place.point,
                            x = place.x,
                            y = place.y,
                        }
                    else
                        local fr = element.getFrame and element.getFrame(barKey)
                        if fr then
                            local nPts = fr:GetNumPoints()
                            if nPts and nPts > 0 then
                                local anchorPoint, _, relPoint, posX, posY = fr:GetPoint(1)
                                if anchorPoint then
                                    -- relPoint may be a frame object here (not a string) if anchored to
                                    -- a parent frame rather than UIParent; mark this snapshot so RevertPositions skips writing it to SavedVariables.
                                    snapshotPositions[barKey] = {
                                        point = anchorPoint,
                                        relPoint = relPoint,
                                        x = posX,
                                        y = posY,
                                        _fromLiveFrame = true,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Snapshot anchor data so we can revert on discard (includes the
        -- growth-edge pin fields; losing them on cancel would force a lazy
        -- recapture from whatever position the session left the bar at)
        wipe(snapshotAnchors)
        local anchorStore = GetAnchorDB()
        if anchorStore then
            for childKey, details in pairs(anchorStore) do
                snapshotAnchors[childKey] = {
                    target = details.target,
                    side = details.side,
                    mode = details.mode,
                    sourcePoint = details.sourcePoint,
                    targetPoint = details.targetPoint,
                    offsetX = details.offsetX,
                    offsetY = details.offsetY,
                    refX = details.refX,
                    refY = details.refY,
                    edgeOffX = details.edgeOffX,
                    edgeOffY = details.edgeOffY,
                    refFor = details.refFor,
                    -- COPY, not a reference: _NudgeSelectedFallbackGhost mutates
                    -- fb.offsetX/offsetY in place, so a shared table would drag the
                    -- snapshot along with the edit and make the revert a no-op. The
                    -- cross-axis edge is nudged in place too, so it copies as well.
                    fallback = details.fallback and CopyTable(details.fallback) or nil,
                    edge = details.edge and CopyTable(details.edge) or nil,
                }
            end
        end

        -- Snapshot element sizes so we can revert width/height changes on discard
        wipe(snapshotSizes)
        for _, barKey in ipairs(registeredOrder) do
            local element = registeredElements[barKey]
            if element and element.getSize then
                local wid, hgt = element.getSize(barKey)
                if wid and hgt then
                    snapshotSizes[barKey] = { w = wid, h = hgt }
                end
            end
        end

        -- Snapshot width/height match DBs so we can revert on discard
        wipe(snapshotWidthMatch)
        wipe(snapshotHeightMatch)
        local wmDB = MatchH.GetWidthMatchDB()
        if wmDB then
            for k, v in pairs(wmDB) do
                snapshotWidthMatch[k] = v
            end
        end
        local hmDB = MatchH.GetHeightMatchDB()
        if hmDB then
            for k, v in pairs(hmDB) do
                snapshotHeightMatch[k] = v
            end
        end
        -- ...and each match's Extra Width / Height, reverted with its link.
        local startX = MatchH.snapExtra
        wipe(startX.w)
        wipe(startX.h)
        local wxDB = CludesUIDB and CludesUIDB.unlockWidthMatchExtra
        if wxDB then
            for k, v in pairs(wxDB) do
                startX.w[k] = v
            end
        end
        local hxDB = CludesUIDB and CludesUIDB.unlockHeightMatchExtra
        if hxDB then
            for k, v in pairs(hxDB) do
                startX.h[k] = v
            end
        end

        -- Snapshot growth directions so we can revert on discard
        wipe(snapshotGrowDirs)
        local cdmStore = CludesUI.Lite.GetAddon("CludesUICooldownManager", true)
        local cdmBarCfg = cdmStore and cdmStore.db and cdmStore.db.profile and cdmStore.db.profile.cdmBars
        if cdmBarCfg and cdmBarCfg.bars then
            for _, barFrame in ipairs(cdmBarCfg.bars) do
                -- bar.key guard: ghost bars (keyless skeletons from stale
                -- override writes) have nothing to snapshot.
                if barFrame.key then
                    snapshotGrowDirs["CDM_" .. barFrame.key] = barFrame.growDirection or false
                end
            end
        end
        local eab = CludesUI.Lite.GetAddon("CludesUIActionBars", true)
        local abBars = eab and eab.db and eab.db.profile and eab.db.profile.bars
        if abBars then
            local abGrowKeys =
                { MainBar = 1, Bar2 = 1, Bar3 = 1, Bar4 = 1, Bar5 = 1, Bar6 = 1, Bar7 = 1, Bar8 = 1 }
            for bk, conf in pairs(abBars) do
                if abGrowKeys[bk] then
                    snapshotGrowDirs[bk] = conf.growDirection or false
                end
            end
        end

        -- Raw pre-session position entries for CDM/AB bars: verbatim saved edges
        -- including the tgt* follow baselines. The snapshotPositions entries above are
        -- center-converted and LOSSY for edge-preserving grow bars (a restored
        -- CENTER-format saved edge can't pin, so the bar stays wherever it currently
        -- sits). Spec-override baseline capture prefers these raw copies. Namespace
        -- table: this body is inside the deferred-init closure, at the 200-local cap.
        local rawSnap = {}
        CludesUI._unlockSnapRawPos = rawSnap
        local cdmPos = cdmStore and cdmStore.db and cdmStore.db.profile and cdmStore.db.profile.cdmBarPositions
        if cdmPos and cdmBarCfg and cdmBarCfg.bars then
            for _, barFrame in ipairs(cdmBarCfg.bars) do
                local e = cdmPos[barFrame.key]
                if e then
                    rawSnap["CDM_" .. barFrame.key] = CopyTable(e)
                end
            end
        end
        local abPos = LM.GetPositionDB()
        if abPos and CludesUI._abBarKeys then
            for bk in pairs(CludesUI._abBarKeys) do
                local e = abPos[bk]
                if e then
                    rawSnap[bk] = CopyTable(e)
                end
            end
        end
    end

    -------------------------------------------------------------------------------
    --  Unlock spec-overrides: session visuals + Save & Exit routing. Gold border =
    --  this element carries an unlock override for the active edit context (the
    --  special group's entry, or the current spec's owning group in a normal
    --  session). Red lock = element can't be edited in the special session (owned by a spec-sharing group, or a blocked subsystem).
    -------------------------------------------------------------------------------
    do
        local overrideBanner
        local function UpdateSpecOvBanner()
            local g = CludesUI._specialUnlockGroup
            if not g or not LM.unlockFrame then
                if overrideBanner then
                    overrideBanner:Hide()
                end
                return
            end
            if not overrideBanner then
                overrideBanner = CreateFrame("Frame", nil, LM.unlockFrame)
                overrideBanner:SetFrameLevel(LM.unlockFrame:GetFrameLevel() + 60)
                overrideBanner:SetHeight(28)
                overrideBanner:SetPoint("TOP", LM.unlockFrame, "TOP", 0, -64)
                local backdrop = overrideBanner:CreateTexture(nil, "BACKGROUND")
                backdrop:SetAllPoints()
                backdrop:SetColorTexture(0.16, 0.12, 0.04, 0.92)
                overrideBanner._brd =
                    CludesUI.MakeRoundedBorder(overrideBanner, 199 / 255, 166 / 255, 90 / 255, 0.7, backdrop)
                local fontStr = overrideBanner:CreateFontString(nil, "OVERLAY")
                fontStr:SetFont(FONT_PATH, 12, "OUTLINE, SLUG")
                fontStr:SetPoint("CENTER")
                fontStr:SetTextColor(1, 0.88, 0.55, 1)
                overrideBanner._text = fontStr
            end
            overrideBanner._text:SetText(
                string.format(
                    CludesUI.L("Customizing Layout Mode: %s (changes apply only to this group's specs)"),
                    g.name or "?"
                )
            )
            overrideBanner:SetWidth((overrideBanner._text:GetStringWidth() or 200) + 28)
            overrideBanner:Show()
            overrideBanner._brd:Fit()
        end

        -- Layer model: a custom unlock mode is a whole-layout fork, so there are no
        -- per-element gold marks or conflict locks anymore -- the gold frame variant
        -- and this banner carry the state; this refresh keeps the banner current and hides stale per-element markers on pooled movers.
        CludesUI._unlockRefreshSpecOvMarks = function()
            UpdateSpecOvBanner()
            for _, m in pairs(handles) do
                if m._specOvBrd then
                    m._specOvBrd:Hide()
                end
                if m._specOvLock then
                    m._specOvLock:Hide()
                end
            end
        end
    end

    -- Commit pending positions to SavedVariables
    local function CommitPositions()
        -- Suppress per-save rebuilds (e.g. CDM's BuildAllCDMBars) so that
        -- all positions are written first, then a single rebuild runs at the end.
        CludesUI._propagatingSave = true
        for barId, place in pairs(pendingPositions) do
            if place == "RESET" then
                ClearBarPosition(barId)
            else
                local element = registeredElements[barId]
                local pt, rpt, px, py = place.point, place.relPoint, place.x, place.y
                -- Anchor-cascade marker: ApplyAnchorPosition repositioned this bar during
                -- the session (e.g. its anchor target was dragged) but the entry carries no
                -- coords. The open-time snapshot below is STALE for it: saving that would
                -- pair a pre-move growth edge with the post-move target baselines savePos
                -- captures, and the bar snaps to the stale edge on save. Resolve from the
                -- bar's LIVE bounds instead -- ConvertToCenterPos prefers them and returns
                -- the exact CENTER/CENTER convention SaveBarPosition expects. Bars a cascade
                -- reapplied without actually moving resolve to the same snapshot position.
                if element and not pt and place._anchored then
                    local liveBar = LM.GetBarFrame(barId)
                    if
                        liveBar
                        and liveBar:GetLeft()
                        and liveBar:GetRight()
                        and liveBar:GetTop()
                        and liveBar:GetBottom()
                    then
                        pt, rpt, px, py = ConvertToCenterPos(barId, "TOPLEFT", "TOPLEFT", 0, 0)
                    end
                end
                -- If position wasn't dragged, fill from snapshot
                if element and not pt then
                    local snapshot = snapshotPositions[barId]
                    if snapshot then
                        pt, rpt, px, py = snapshot.point, snapshot.relPoint or snapshot.point, snapshot.x, snapshot.y
                    else
                        -- Fallback: read from loadPosition
                        local lp = element.loadPosition and element.loadPosition(barId)
                        if lp then
                            pt, rpt, px, py = lp.point, lp.relPoint or lp.point, lp.x, lp.y
                        end
                    end
                end
                LM.SaveBarPosition(barId, pt, rpt, px, py)
                -- Install anchor guard for action bar positions
                if not element then
                    local barFrame = LM.GetBarFrame(barId)
                    if barFrame then
                        InstallAnchorGuard(barFrame, barId)
                    end
                end
            end
        end
        CludesUI._propagatingSave = false

        -- Force edge-preservation across the save rebuild + reapply below. These run
        -- while isUnlocked is still true (DoClose clears it only AFTER CommitPositions
        -- returns), so without this flag ApplyAnchorPosition skips its absolute
        -- saved-edge branch and places anchored custom-growth CDM bars from the anchor
        -- offset + live width instead -- if the rebuild changed a bar's width, the
        -- growth edge lands off the freshly-saved edge and the bar visibly snaps back
        -- until /reload. Setting the flag makes both passes read cdmBarPositions
        -- exactly like the login/reload apply. Mirrors OpenUnlockMode's entry reapply; pcall-wrapped and reset in all cases so it can never leak.
        CludesUI._reapplyForceEdgePreserve = true

        -- Single rebuild now that all positions are committed.
        -- CDM savePos normally calls BuildAllCDMBars per save, but we
        -- suppressed that above to avoid partial-state rebuilds.
        for barId in pairs(pendingPositions) do
            if type(barId) == "string" and barId:sub(1, 4) == "CDM_" then
                local element = registeredElements[barId]
                if element and element.applyPosition then
                    pcall(element.applyPosition, barId)
                end
                break -- one rebuild is enough, it rebuilds all bars
            end
        end

        -- Reapply anchor positions for all anchored bars so they move from the stale CENTER
        -- coords (saved by CommitPositions) to their correct anchor-relative position
        -- immediately. Without this, anchored bars sit at stale coords until a deferred
        -- ScheduleAnchorBatch corrects them, causing a visible jump on the next resize.
        if CludesUI.ReapplyAllUnlockAnchorsForced then
            pcall(CludesUI.ReapplyAllUnlockAnchorsForced)
        end

        CludesUI._reapplyForceEdgePreserve = false

        -- Persist unlock layout into the active profile so it survives reloads
        -- without requiring a manual profile switch.
        if CludesUIDB and CludesUI.GetProfilesDB then
            local pdb = CludesUI.GetProfilesDB()
            local activeName = pdb.activeProfile or "Default"
            local profileData = pdb.profiles and pdb.profiles[activeName]
            if profileData then
                local snapshot = {
                    anchors = CopyTable(CludesUIDB.unlockAnchors or {}),
                    widthMatch = CopyTable(CludesUIDB.unlockWidthMatch or {}),
                    heightMatch = CopyTable(CludesUIDB.unlockHeightMatch or {}),
                    widthMatchExtra = CopyTable(CludesUIDB.unlockWidthMatchExtra or {}),
                    heightMatchExtra = CopyTable(CludesUIDB.unlockHeightMatchExtra or {}),
                    phantomBounds = CopyTable(CludesUIDB.phantomBounds or {}),
                }
                -- While a spec-override unlock LAYER is live, the profile
                -- snapshot must carry the shared BASELINE links, not the live
                -- (group-valued) globals; the stored baseline layout provides
                -- them. When the baseline itself is live, live is the source.
                if CludesUI.SpecOverrides_UnlockBaselineLinks then
                    local ba, bw, bh = CludesUI.SpecOverrides_UnlockBaselineLinks()
                    if ba then
                        snapshot.anchors = CopyTable(ba)
                        snapshot.widthMatch = CopyTable(bw)
                        snapshot.heightMatch = CopyTable(bh)
                        -- The baseline's match extras ride with its links (4th and
                        -- 5th returns); a baseline without extras carries none.
                        local _, _, _, bwx, bhx = CludesUI.SpecOverrides_UnlockBaselineLinks()
                        snapshot.widthMatchExtra = CopyTable(bwx or {})
                        snapshot.heightMatchExtra = CopyTable(bhx or {})
                    end
                end
                profileData.unlockLayout = snapshot
            end
        end
        -- The active spec's tracked buff bar links and extras into their spec bucket,
        -- so a profile restore before the next bar build cannot swap older ones in.
        if CludesUI._TBBBankUnlockLinks then
            CludesUI._TBBBankUnlockLinks()
        end

        -- Bank CAPTURED settings the session edited (cog size inputs) into
        -- values.default -- a normal unlock session edits the shared baseline, exactly
        -- like the panel's Default Editing Mode. Without this the next value apply
        -- reverts the user's unlock-mode resize (the sticky harvest deliberately never adopts foreign live diffs).
        if CludesUI.SpecOverrides_UnlockValueSnapCommit then
            pcall(CludesUI.SpecOverrides_UnlockValueSnapCommit)
        end

        -- Bank the freshly-saved live layout into its owning spec-override layer (the
        -- active group layer, else the stored baseline). Wholesale harvest -- no
        -- per-aspect routing exists. true = user commit: banks even inside the post-import suppression window (and closes it).
        if CludesUI.SpecOverrides_HarvestUnlockLayout then
            local okH, errH = pcall(CludesUI.SpecOverrides_HarvestUnlockLayout, true)
            if not okH then
                print("|cffff6060[CludesUI]|r Unlock layer harvest failed: " .. tostring(errH))
            end
        end
    end

    -- Revert bars to their snapshot positions (discard all pending changes)
    local function RevertPositions()
        if InCombatLockdown() then
            return
        end

        -- Cancel: unlock-session value edits are discarded too (the module store may
        -- keep the cog-edited size until the next value apply restores the recorded default -- correct for a discard).
        if CludesUI.SpecOverrides_UnlockValueSnapDiscard then
            CludesUI.SpecOverrides_UnlockValueSnapDiscard()
        end

        -- 1) Restore all DB state from snapshots (suppress rebuilds)
        CludesUI._propagatingSave = true

        local saved = LM.GetPositionDB()
        if saved then
            for barId, _ in pairs(pendingPositions) do
                if not registeredElements[barId] then
                    -- Prefer the verbatim pre-session entry (saved edge PLUS the tgt*
                    -- follow baselines): the coordinate-only snapshot would strip the baselines from grow bars on every cancel, costing a bless cycle before target-follow works again.
                    local rawSnap = CludesUI._unlockSnapRawPos and CludesUI._unlockSnapRawPos[barId]
                    local snapshot = snapshotPositions[barId]
                    if rawSnap then
                        saved[barId] = CopyTable(rawSnap)
                    elseif snapshot then
                        saved[barId] =
                            { point = snapshot.point, relPoint = snapshot.relPoint, x = snapshot.x, y = snapshot.y }
                    else
                        saved[barId] = nil
                    end
                end
            end
        end

        for barId, _ in pairs(pendingPositions) do
            local element = registeredElements[barId]
            if element and element.savePosition then
                local snapshot = snapshotPositions[barId]
                if snapshot and not snapshot._fromLiveFrame then
                    element.savePosition(barId, snapshot.point, snapshot.relPoint or snapshot.point, snapshot.x, snapshot.y)
                end
            end
        end

        CludesUI._propagatingSave = false

        -- 2) Restore anchor data before repositioning
        local anchorStore = GetAnchorDB()
        if anchorStore then
            -- fallback rides the snapshot (copied both ways), so pre-session
            -- fallbacks survive the revert and session edits discard with it.
            wipe(anchorStore)
            for childKey, details in pairs(snapshotAnchors) do
                anchorStore[childKey] = {
                    target = details.target,
                    side = details.side,
                    mode = details.mode,
                    sourcePoint = details.sourcePoint,
                    targetPoint = details.targetPoint,
                    offsetX = details.offsetX,
                    offsetY = details.offsetY,
                    refX = details.refX,
                    refY = details.refY,
                    edgeOffX = details.edgeOffX,
                    edgeOffY = details.edgeOffY,
                    refFor = details.refFor,
                    edge = details.edge and CopyTable(details.edge) or nil,
                    -- Restored from the snapshot, so a fallback MOVED this session
                    -- reverts like every other position. Fresh copy so the next
                    -- session's nudges cannot reach back into the snapshot.
                    fallback = details.fallback and CopyTable(details.fallback) or nil,
                }
            end
            -- The restored links may hold a pet-target fallback again.
            CludesUI._EnsureFallbackWatchers()
        end

        -- 3) Restore element sizes
        for barKey, snapshot in pairs(snapshotSizes) do
            local element = registeredElements[barKey]
            if element then
                if element.setWidth and snapshot.w then
                    pcall(element.setWidth, barKey, snapshot.w)
                end
                if element.setHeight and snapshot.h then
                    pcall(element.setHeight, barKey, snapshot.h)
                end
            end
        end

        -- 4) Restore width/height match DBs
        local wmDB = MatchH.GetWidthMatchDB()
        if wmDB then
            wipe(wmDB)
            for k, v in pairs(snapshotWidthMatch) do
                wmDB[k] = v
            end
        end
        local hmDB = MatchH.GetHeightMatchDB()
        if hmDB then
            wipe(hmDB)
            for k, v in pairs(snapshotHeightMatch) do
                hmDB[k] = v
            end
        end
        -- Each match's Extra Width / Height, in the same step as its link. A CDM bar
        -- reads both live (its setWidth only re-lays it out) and step 6 rebuilds only
        -- bars that moved, so a bar whose extra the restore changes is re-laid out here.
        if CludesUIDB then
            local startX = MatchH.snapExtra
            local relayout
            local function Note(live, snapshot)
                if live then
                    for k, v in pairs(live) do
                        if snapshot[k] ~= v and k:sub(1, 4) == "CDM_" then
                            relayout = relayout or {}
                            relayout[k] = true
                        end
                    end
                end
                for k, v in pairs(snapshot) do
                    if not (live and live[k] == v) and k:sub(1, 4) == "CDM_" then
                        relayout = relayout or {}
                        relayout[k] = true
                    end
                end
            end
            Note(CludesUIDB.unlockWidthMatchExtra, startX.w)
            Note(CludesUIDB.unlockHeightMatchExtra, startX.h)
            if CludesUIDB.unlockWidthMatchExtra then
                wipe(CludesUIDB.unlockWidthMatchExtra)
            end
            for k, v in pairs(startX.w) do
                MatchH.SetMatchExtra("w", k, v)
            end
            if CludesUIDB.unlockHeightMatchExtra then
                wipe(CludesUIDB.unlockHeightMatchExtra)
            end
            for k, v in pairs(startX.h) do
                MatchH.SetMatchExtra("h", k, v)
            end
            if relayout then
                for k in pairs(relayout) do
                    local e = registeredElements[k]
                    if e and e.setWidth then
                        pcall(e.setWidth, k)
                    end
                end
            end
        end

        -- 5) Restore growth directions
        for barKey, snapGrow in pairs(snapshotGrowDirs) do
            local val = snapGrow == false and nil or snapGrow
            if barKey:sub(1, 4) == "CDM_" then
                local rawKey = barKey:sub(5)
                local cdmA = CludesUI.Lite.GetAddon("CludesUICooldownManager", true)
                local cdmB = cdmA and cdmA.db and cdmA.db.profile and cdmA.db.profile.cdmBars
                if cdmB and cdmB.bars then
                    for _, barFrame in ipairs(cdmB.bars) do
                        if barFrame.key == rawKey then
                            barFrame.growDirection = val
                            break
                        end
                    end
                end
            else
                local eabA = CludesUI.Lite.GetAddon("CludesUIActionBars", true)
                local abB = eabA and eabA.db and eabA.db.profile and eabA.db.profile.bars
                if abB and abB[barKey] then
                    abB[barKey].growDirection = val
                end
            end
        end

        -- 6) Rebuild CDM bars so they read the restored DB and position correctly.
        -- Without this, CDM bars revert to wrong positions (CENTER vs edge mismatch).
        local didCDMRebuild = false
        for barId in pairs(pendingPositions) do
            if not didCDMRebuild and type(barId) == "string" and barId:sub(1, 4) == "CDM_" then
                local element = registeredElements[barId]
                if element and element.applyPosition then
                    pcall(element.applyPosition, barId)
                end
                didCDMRebuild = true
            end
        end

        -- 6) Reposition unanchored elements through normal path.
        -- Skip anchored elements -- step 7 handles them via ApplyAnchorPosition.
        for barId, _ in pairs(pendingPositions) do
            local ai = anchorStore and anchorStore[barId]
            if not (ai and ai.target) then
                local barFrame = LM.GetBarFrame(barId)
                if barFrame then
                    local snapshot = snapshotPositions[barId]
                    local revElem = registeredElements[barId]
                    if revElem and revElem.noInitHook then
                        -- Self-positioning: its own authority, from the restored save.
                        if revElem.applyPosition then
                            pcall(revElem.applyPosition, barId)
                        end
                    elseif snapshot and not snapshot._fromLiveFrame then
                        if not LM.ApplyCenterPosition(barId, snapshot) then
                            pcall(function()
                                CludesUI.ClearFramePoints(barFrame)
                                CludesUI.SetFramePoint(
                                    barFrame,
                                    snapshot.point,
                                    UIParent,
                                    snapshot.relPoint,
                                    snapshot.x,
                                    snapshot.y
                                )
                            end)
                        end
                    elseif barFrame.UpdateGridLayout then
                        pcall(barFrame.UpdateGridLayout, barFrame)
                    end
                end
            end
        end

        -- 7) Reapply anchor positions for anchored elements. Force edge preservation
        -- across the pass: this runs while isUnlocked is still true, and without the
        -- flag ApplyAnchorPosition skips its absolute saved-edge branch and places
        -- anchored custom-growth bars (StanceBar, CDM grow bars) from their center
        -- offsets + live width instead of the just-restored saved edge -- the bar
        -- visibly snaps off its reverted position. Mirrors the CommitPositions fix.
        if anchorStore then
            CludesUI._reapplyForceEdgePreserve = true
            for childKey, details in pairs(anchorStore) do
                if details.target and LM.GetBarFrame(childKey) and LM.GetBarFrame(details.target) then
                    pcall(LM.ApplyAnchorPosition, childKey, details.target, details.side)
                end
            end
            CludesUI._reapplyForceEdgePreserve = false
        end
    end

    local pendingAfterClose -- callback to run after DoClose completes
    local cogHoveredMover = nil -- the mover whose cog button is currently hovered

    -- Internal close (actually hides everything and returns to options)
    local function DoClose(closeAction)
        if not LM.isUnlocked then
            return
        end
        LM.isUnlocked = false
        CludesUI._unlockActive = false
        CludesUI._unlockModeActive = false
        CludesUI:_NotifyUnlockModeListeners(false, closeAction or "exit")
        if CludesUI._HideFallbackGhosts then
            CludesUI._HideFallbackGhosts()
        end
        if CludesUI._HideOverrideGhosts then
            CludesUI._HideOverrideGhosts()
        end
        -- Re-engage override anchors now that isUnlocked is false (the settle's
        -- position pass is the belt; this is deterministic and immediate).
        if CludesUI._ReapplyOverrideAnchors then
            CludesUI._ReapplyOverrideAnchors()
        end

        -- Notify action bars to restore Blizzard-owned frame anchors
        if _G._CUAB_UnlockModeClose then
            pcall(_G._CUAB_UnlockModeClose)
        end

        -- Recalculate action bar flyout directions after positions are finalized
        if _G._CUAB_RecalcFlyouts then
            pcall(_G._CUAB_RecalcFlyouts)
        end

        -- Notify beacon reminders to restore (if follow-mouse is active)
        if _G._CUABR_BeaconRefresh then
            pcall(_G._CUABR_BeaconRefresh)
        end

        -- Restore expandIfNoResource after unlock mode finishes
        if _G._CURB_RestoreExpand then
            pcall(_G._CURB_RestoreExpand)
        end
        -- Re-apply the anchor-target shifts after unlock mode finishes. Independent of
        -- expand restore (which early-returns when expand was never suppressed); runs
        -- after _unlockActive is cleared above so the providers return non-zero and
        -- PropagateAnchorChain is no longer a no-op. Each provider gates itself so
        -- None = no work.
        CludesUI.RestoreAnchorShifts()

        -- Restore unit frame buffs/debuffs
        local UF_FRAME_NAMES = {
            "CludesUIUnitFrames_Player",
            "CludesUIUnitFrames_Target",
            "CludesUIUnitFrames_Focus",
            "CludesUIUnitFrames_Pet",
            "CludesUIUnitFrames_TargetTarget",
            "CludesUIUnitFrames_FocusTarget",
        }
        for i = 1, 8 do
            UF_FRAME_NAMES[#UF_FRAME_NAMES + 1] = "CludesUIUnitFrames_Boss" .. i
        end
        for _, name in ipairs(UF_FRAME_NAMES) do
            local f = _G[name]
            if f then
                if f.Buffs and f.Buffs._unlockWasShown then
                    f.Buffs:Show()
                    f.Buffs._unlockWasShown = nil
                end
                if f.Debuffs and f.Debuffs._unlockWasShown then
                    f.Debuffs:Show()
                    f.Debuffs._unlockWasShown = nil
                end
            end
        end

        -- Restore objective tracker
        if LM.objTrackerWasVisible then
            local questTracker = _G.ObjectiveTrackerFrame
            if questTracker then
                questTracker:SetAlpha(1)
                local wasEnabled = CludesUI._GetFFD(questTracker).unlockMouseWasEnabled
                if questTracker.EnableMouse then
                    pcall(questTracker.EnableMouse, questTracker, wasEnabled and true or false)
                end
            end
            LM.objTrackerWasVisible = false
        end
        -- Restore CludesUI QT background
        local trackerBg = _G.CludesUIQTBackground
        if trackerBg then
            trackerBg:SetAlpha(1)
        end
        -- Re-apply user visibility setting (handles "never" mode for both tracker + bg)
        if _G.CludesUIQuestTracker and _G.CludesUIQuestTracker.UpdateVisibility then
            _G.CludesUIQuestTracker.UpdateVisibility()
        end

        -- Re-check Dragon Riding's real visibility (it force-shows while unlocked
        -- so it can be edited off-mount; without this it stays stuck visible
        -- after exiting Unlock Mode if the player dismounted while unlocked).
        if _G._CUDR_UpdateVisibility then
            pcall(_G._CUDR_UpdateVisibility)
        end

        if not LM.unlockFrame then
            return
        end

        LM.unlockFrame:SetScript("OnUpdate", nil)
        if LM.logoFadeFrame then
            LM.logoFadeFrame:SetScript("OnUpdate", nil)
            LM.logoFadeFrame:Hide()
        end
        if LM.openAnimFrame then
            LM.openAnimFrame:Hide()
        end
        if lockAnimFrame then
            lockAnimFrame:Hide()
        end
        if LM.gridFrame then
            LM.gridFrame:SetScript("OnUpdate", nil)
            LM.gridFrame:Hide()
        end
        if LM.hudFrame then
            LM.hudFrame:Hide()
        end
        if LM.unlockTipFrame then
            LM.unlockTipFrame:SetScript("OnUpdate", nil)
            LM.unlockTipFrame:Hide()
        end
        if LM.unlockFrame._anchorLineDriver then
            LM.unlockFrame._anchorLineDriver:Hide()
        end
        if LM.unlockFrame._anchorLineFrame then
            LM.unlockFrame._anchorLineFrame:Hide()
        end
        if LM.unlockFrame._clearAnchorLineAnim then
            LM.unlockFrame._clearAnchorLineAnim()
        end
        DeselectMover()
        -- Collapse any expanded mover so it doesn't stay stuck on re-enter
        LM.hoveredMover = nil
        cogHoveredMover = nil
        CludesUI._unlockCursorSpeed = 0
        for _, m in pairs(handles) do
            m._snapTarget = nil
            m._dragging = false
            m._shiftAxis = nil
            m._hoverPending = false
            -- Snap-collapse hover state so mover isn't stuck expanded on re-enter
            if m._forceCollapse then
                m._forceCollapse()
            end
            m:SetScript("OnUpdate", nil)
            m:Hide()
        end
        HideAllGuidesAndHighlight()
        HideBlizzOwnedOverlays()
        LM.unlockFrame:Hide()
        LM.unlockFrame:SetAlpha(1)

        -- Clean up arrow key nudge state
        LM.selectedMover = nil
        LM.selectElementPicker = nil
        if LM.arrowKeyFrame then
            LM.arrowKeyFrame:Hide()
        end

        -- Reset session state
        wipe(pendingPositions)
        wipe(snapshotPositions)
        wipe(snapshotAnchors)
        wipe(snapshotGrowDirs)
        LM.hasChanges = false

        -- End any special spec-override session and clear its mover marks (the
        -- banner is a child of unlockFrame, hidden with it above; the next
        -- session's mark refresh re-evaluates everything).
        CludesUI._specialUnlockGroup = nil
        for _, m in pairs(handles) do
            if m._specOvBrd then
                m._specOvBrd:Hide()
            end
            if m._specOvLock then
                m._specOvLock:Hide()
            end
        end

        -- Clean up pick mode / anchor dropdown state
        LM.PointPicker.Cancel()
        LM.pickMode = nil
        LM.pickModeMover = nil
        if LM.anchorDropdownFrame then
            LM.anchorDropdownFrame:Hide()
        end
        if LM.anchorDropdownCatcher then
            LM.anchorDropdownCatcher:Hide()
        end
        if LM.growDropdownFrame then
            LM.growDropdownFrame:Hide()
        end
        if LM.growDropdownCatcher then
            LM.growDropdownCatcher:Hide()
        end

        -- Restore action bar alpha from saved settings
        if ABAR and ABAR.RefreshMouseover and not InCombatLockdown() then
            ABAR:RefreshMouseover()
        end

        -- Restore CDM bar visibility (unlock forced all bars visible)
        if _G._CUCME_ApplyVisibility then
            _G._CUCME_ApplyVisibility()
        end

        -- Restore panel scale and show options
        local panelRealScale
        do
            local physW = (GetPhysicalScreenSize())
            local baseScale = GetScreenWidth() / physW
            local userScale = (CludesUIDB and CludesUIDB.panelScale) or 1.0
            panelRealScale = baseScale * userScale
        end
        local panelFrame = CludesUI and CludesUI._mainFrame
        if panelFrame then
            panelFrame:SetScale(panelRealScale)
            panelFrame:SetAlpha(1)
        end
        -- If there's a pending after-close callback, skip the default panel restore
        -- (the callback will handle opening the panel to the right page)
        if not pendingAfterClose then
            if CludesUI then
                -- Restore the module + page active before unlock mode opened (captured
                -- by SelectPage("Unlock Mode") in CludesUI.lua). Do NOT show the panel
                -- yet -- SelectModule/SelectPage cause Hide->Show cycles on the page
                -- wrapper via HideAllChildren, and showing the panel first would add
                -- extra cycles that leave EditBox text blank. Set up the page while hidden, then show once at the end.
                local restoreModule = CludesUI._unlockReturnModule
                local restorePage = CludesUI._unlockReturnPage
                CludesUI._unlockReturnPage = nil
                CludesUI._unlockReturnModule = nil
                if restoreModule then
                    CludesUI:SelectModule(restoreModule)
                    if restorePage and CludesUI.SelectPage then
                        local currentPage = CludesUI:GetActivePage()
                        if currentPage ~= restorePage then
                            CludesUI:SelectPage(restorePage)
                        end
                    end
                    -- NOW show the panel -- one clean Show, no prior cycling.
                    CludesUI:Toggle()
                end
            end
        end

        -- Fire any pending after-close callback (e.g. from slash commands)
        if pendingAfterClose then
            CludesUI._unlockReturnPage = nil
            CludesUI._unlockReturnModule = nil
            local func = pendingAfterClose
            pendingAfterClose = nil
            func()
        end
    end

    -- Public close request: save=true commits, save=false may prompt
    -- Optional afterFn runs after close completes (for slash command chaining)
    function mod.RequestClose(save, afterFn)
        if afterFn then
            pendingAfterClose = afterFn
        end
        if save then
            CommitPositions()
            DoClose("save")
            return
        end
        -- No changes -> just exit
        if not LM.hasChanges then
            DoClose("exit")
            return
        end
        -- Has unsaved changes -> show confirm popup
        CludesUI:ShowConfirmPopup({
            title = "Unsaved Changes",
            frameLevel = (LM.moverOverlayLevel or 250) + 100,
            message = "You have unsaved position changes.\nWhat would you like to do?",
            cancelText = "Exit Without Saving",
            confirmText = "Save & Exit",
            onCancel = function()
                RevertPositions()
                DoClose("exit")
            end,
            onConfirm = function()
                CommitPositions()
                DoClose("save")
            end,
            -- Dismiss (ESC / click-off) does nothing -- user stays in unlock mode,
            -- and any pending close callback is cleared since the close was abandoned
            onDismiss = function()
                pendingAfterClose = nil
                -- Controller Back: stamp the dismiss so the same press's step skips
                if LM.unlockFrame and LM.unlockFrame._padEsc then
                    LM.unlockFrame._padDismissAt = GetTime()
                end
            end,
        })
    end

    --- Force-closes unlock mode DISCARDING the session. Called by the profile system
    --- on a spec transition: movers, snapshots, and pending edits all belong to the
    --- OUTGOING spec's layout, so saving them against the incoming spec would corrupt both baseline and spec-override data.
    function CludesUI.ForceCloseUnlockDiscard()
        -- A combat-suspended session is still open (it keeps its snapshots for the
        -- resume): reopen its state so the close below ends it.
        if LM.combatSuspended then
            LM.combatSuspended = false
            LM.isUnlocked = true
        end
        if not LM.isUnlocked then
            return
        end
        CludesUI.PrintError(
            CludesUI.L("Layout changed: Layout Mode closed, unsaved layout changes discarded.")
        )
        pendingAfterClose = nil
        -- Unconditional: RevertPositions only runs below when positions changed,
        -- but the value-edit snapshot must never survive a discard-close.
        if CludesUI.SpecOverrides_UnlockValueSnapDiscard then
            CludesUI.SpecOverrides_UnlockValueSnapDiscard()
        end
        if LM.hasChanges then
            pcall(RevertPositions)
        end
        pcall(DoClose, "discard")
    end

    -------------------------------------------------------------------------------
    --  Smooth easing function (ease-in-out cubic)
    -------------------------------------------------------------------------------
    local function EaseInOutCubic(t)
        if t < 0.5 then
            return 4 * t * t * t
        else
            local f = 2 * t - 2
            return 0.5 * f * f * f + 1
        end
    end

    -------------------------------------------------------------------------------
    --  Open / Close Unlock Mode
    -------------------------------------------------------------------------------
    local function CreateUnlockFrame()
        if LM.unlockFrame then
            return LM.unlockFrame
        end

        LM.unlockFrame = CreateFrame("Frame", "CludesUnlockMode", UIParent)
        LM.unlockFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        LM.unlockFrame:SetAllPoints(UIParent)
        LM.unlockFrame:EnableMouse(false) -- let clicks pass through to game world
        LM.unlockFrame:EnableKeyboard(true)

        -- Dark overlay background -- on a dedicated sub-frame so movers render ABOVE it
        local overlayFrame = CreateFrame("Frame", nil, LM.unlockFrame)
        overlayFrame:SetFrameLevel(LM.unlockFrame:GetFrameLevel() + 1)
        overlayFrame:SetAllPoints(UIParent)
        local overlay = overlayFrame:CreateTexture(nil, "BACKGROUND")
        overlay:SetAllPoints()
        overlay:SetColorTexture(0.020, 0.025, 0.031, 0.20)
        LM.unlockFrame._overlay = overlay
        LM.unlockFrame._overlayMaxAlpha = 0.20

        -- Anchor lines connect mover centers or the explicit point pair.
        local anchorLinePool = {}
        local anchorPulsePool = {}
        local anchorLineFrame = CreateFrame("Frame", nil, UIParent)
        anchorLineFrame:SetFrameStrata("BACKGROUND")
        anchorLineFrame:SetFrameLevel(1)
        anchorLineFrame:SetAllPoints(UIParent)
        anchorLineFrame:EnableMouse(false)

        local function GetAnchorLine(position)
            if anchorLinePool[position] then
                return anchorLinePool[position]
            end
            local guide = anchorLineFrame:CreateLine(nil, "ARTWORK", nil, 1)
            guide:SetThickness(3)
            guide:SetSnapToPixelGrid(false)
            guide:SetTexelSnappingBias(0)
            guide:SetTexture("Interface\\AddOns\\CludesUI\\media\\textures\\soft-line")
            anchorLinePool[position] = guide
            return guide
        end

        local function GetAnchorPulse(position)
            if anchorPulsePool[position] then
                return anchorPulsePool[position]
            end
            local guide = anchorLineFrame:CreateLine(nil, "ARTWORK", nil, 2)
            guide:SetThickness(3)
            guide:SetSnapToPixelGrid(false)
            guide:SetTexelSnappingBias(0)
            guide:SetTexture("Interface\\AnimaChannelingDevice\\AnimaChannelingDeviceLineVerticalMask")
            anchorPulsePool[position] = guide
            return guide
        end

        -- Per-line animation state keyed by "childKey:targetKey"
        local anchorLineAnim = {}
        local ANCHOR_LINE_DUR = 0.5
        local PULSE_CYCLE = 2.5
        local PULSE_SWEEP = 0.56 -- fraction of cycle spent sweeping (rest is pause)

        local function UpdateAnchorLines()
            local saved = GetAnchorDB()
            local position = 0
            local pointLines = 0
            local nowTime = GetTime()
            if saved and LM.isUnlocked then
                for childKey, details in pairs(saved) do
                    local cm = handles[childKey]
                    local tm = handles[details.target]
                    if cm and tm and cm:IsShown() and tm:IsShown() then
                        -- Use _hoverConfirmed so lines wait for hover intent
                        local cmActive = cm._hoverConfirmed or cm._dragging
                        local tmActive = tm._hoverConfirmed or tm._dragging
                        local pairKey = childKey .. ":" .. details.target
                        if cmActive or tmActive then
                            -- Start or continue animation
                            if not anchorLineAnim[pairKey] then
                                anchorLineAnim[pairKey] = nowTime
                            end
                            local timePassed = nowTime - anchorLineAnim[pairKey]
                            local t = timePassed / ANCHOR_LINE_DUR
                            if t > 1 then
                                t = 1
                            end
                            -- Ease-out for smooth deceleration
                            local ease = 1 - (1 - t) * (1 - t)

                            position = position + 1
                            local guide = GetAnchorLine(position)
                            -- Child center (line origin)
                            local fromX = ((cm:GetLeft() or 0) + (cm:GetRight() or 0)) * 0.5
                            local fromY = ((cm:GetBottom() or 0) + (cm:GetTop() or 0)) * 0.5
                            -- Parent center (line destination)
                            local x2 = ((tm:GetLeft() or 0) + (tm:GetRight() or 0)) * 0.5
                            local y2 = ((tm:GetBottom() or 0) + (tm:GetTop() or 0)) * 0.5
                            if details.mode == "POINT" then
                                local startX, sy = LM.PointPicker.Point(cm, details.sourcePoint)
                                local tx, ty = LM.PointPicker.Point(tm, details.targetPoint)
                                if startX and tx then
                                    fromX, fromY, x2, y2 = startX, sy, tx, ty
                                    pointLines = pointLines + 1
                                    LM.PointVisuals.Connection(
                                        pointLines,
                                        cm,
                                        details.sourcePoint,
                                        tm,
                                        details.targetPoint,
                                        ease
                                    )
                                end
                            end
                            -- Partial endpoint based on animation progress
                            local ex = fromX + (x2 - fromX) * ease
                            local ey = fromY + (y2 - fromY) * ease
                            guide:SetStartPoint("BOTTOMLEFT", UIParent, fromX, fromY)
                            guide:SetEndPoint("BOTTOMLEFT", UIParent, ex, ey)
                            local pointR, pointG, pointB, pointA
                            if details.mode == "POINT" then
                                pointR, pointG, pointB, pointA = CludesUI.GetPointAnchorColor("line")
                                guide:SetVertexColor(pointR, pointG, pointB, pointA * 0.75 * ease)
                            else
                                guide:SetVertexColor(1, 0.7, 0.3, 0.75 * ease)
                            end
                            guide:Show()

                            -- Pulse overlay: streak that sweeps child->parent, loops every 3s
                            local pulse = GetAnchorPulse(position)
                            if ease >= 1 then
                                local pulseAge = nowTime - anchorLineAnim[pairKey] - 0.3
                                local cycleT = (pulseAge % PULSE_CYCLE) / PULSE_CYCLE
                                local sweepEnd = PULSE_SWEEP
                                if cycleT <= sweepEnd then
                                    local st = cycleT / sweepEnd
                                    -- Smooth ease-in-out motion, overshooting to 3x line length
                                    local smoothT = st * st * (3 - 2 * st)
                                    local headT = smoothT * 2.0
                                    local tailT = math.max(0, headT - 1.0)
                                    -- Clamp endpoints to the actual line
                                    local clampHead = math.min(1, headT)
                                    local clampTail = math.min(1, tailT)
                                    -- Fade in/out
                                    local fadeA = 1
                                    if smoothT < 0.1 then
                                        fadeA = smoothT / 0.1
                                    elseif smoothT > 0.7 then
                                        fadeA = (1 - smoothT) / 0.3
                                    end
                                    if fadeA < 0 then
                                        fadeA = 0
                                    end
                                    if clampHead <= clampTail then
                                        pulse:Hide()
                                    else
                                        local px1 = fromX + (x2 - fromX) * clampTail
                                        local py1 = fromY + (y2 - fromY) * clampTail
                                        local px2 = fromX + (x2 - fromX) * clampHead
                                        local py2 = fromY + (y2 - fromY) * clampHead
                                        pulse:SetStartPoint("BOTTOMLEFT", UIParent, px1, py1)
                                        pulse:SetEndPoint("BOTTOMLEFT", UIParent, px2, py2)
                                        if details.mode == "POINT" then
                                            pulse:SetVertexColor(
                                                pointR + (1 - pointR) * 0.5625,
                                                pointG + (1 - pointG) * 0.5625,
                                                pointB + (1 - pointB) * 0.5625,
                                                pointA * 0.5 * fadeA
                                            )
                                        else
                                            pulse:SetVertexColor(1, 0.89, 0.625, 0.5 * fadeA)
                                        end
                                        pulse:Show()
                                    end
                                else
                                    pulse:Hide()
                                end
                            else
                                pulse:Hide()
                            end
                        else
                            -- Not active, clear animation state
                            anchorLineAnim[pairKey] = nil
                        end
                    end
                end
            end
            -- Hide unused lines and clean stale anim entries
            for i = position + 1, #anchorLinePool do
                anchorLinePool[i]:Hide()
            end
            for i = position + 1, #anchorPulsePool do
                anchorPulsePool[i]:Hide()
            end
            LM.PointVisuals.TrimConnections(pointLines)
        end

        -- Drive line updates every frame while unlock mode is open
        local anchorLineDriver = CreateFrame("Frame")
        anchorLineDriver:SetScript("OnUpdate", UpdateAnchorLines)
        anchorLineDriver:Hide()
        LM.unlockFrame._anchorLineDriver = anchorLineDriver
        LM.unlockFrame._anchorLineFrame = anchorLineFrame
        LM.unlockFrame._clearAnchorLineAnim = function()
            wipe(anchorLineAnim)
            LM.PointVisuals.TrimConnections(0)
        end

        -- Click-to-deselect is handled by toggle behavior on movers themselves
        -- (clicking the selected mover again deselects it), so no full-screen catcher is needed -- world interaction (targeting, camera) stays unblocked.

        -- One Escape step: the innermost open layer closes, else Unlock Mode does
        -- (which asks first when there are unsaved changes). padAll: a controller
        -- Back that closes every window at once (nil from the keyboard).
        local function EscapeStep(padAll)
            -- If anchor dropdown is open, close it instead of closing unlock mode
            if LM.anchorDropdownFrame and LM.anchorDropdownFrame:IsShown() then
                LM.anchorDropdownFrame:Hide()
                if LM.anchorDropdownCatcher then
                    LM.anchorDropdownCatcher:Hide()
                end
                return
            end
            -- If in width/height/anchor pick mode, cancel it instead of closing
            if LM.pickModeMover and LM.pickMode then
                CancelPickMode()
                return
            end
            -- If in select-element pick mode, cancel it instead of closing
            if LM.selectElementPicker then
                local picker = LM.selectElementPicker
                picker._snapTarget = picker._preSelectTarget
                picker._preSelectTarget = nil
                if picker._updateSnapLabel then
                    picker._updateSnapLabel()
                end
                LM.selectElementPicker = nil
                FadeOverlayForSelectElement(false)
                return
            end
            -- That Back exits to the world, as Blizzard's does: a panel reopened
            -- here loses the pointer as soon as the press ends. Unsaved changes
            -- keep the way back for the prompt's Save & Exit.
            if padAll and not LM.hasChanges then
                CludesUI._unlockReturnModule = nil
                CludesUI._unlockReturnPage = nil
            end
            mod.CloseUnlockMode()
        end

        -- ESC to close (skip if confirm popup is already showing)
        LM.unlockFrame:SetScript("OnKeyDown", function(self, barKey)
            if barKey == "ESCAPE" then
                -- If the confirm popup is visible, let it handle ESC instead
                local dimmer = _G["CUIConfirmDimmer"]
                if dimmer and dimmer:IsShown() then
                    self:SetPropagateKeyboardInput(true)
                    return
                end
                self:SetPropagateKeyboardInput(false)
                EscapeStep()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        -- Controller Back (the escape proxy runs it once Unlock Mode is registered
        -- there, see OpenUnlockMode): the same step as Escape. A shown confirm
        -- popup answers Back itself, and the Back that just dismissed the
        -- unsaved-changes prompt must not raise it again in the same pass.
        LM.unlockFrame._padBack = function()
            local dimmer = _G["CUIConfirmDimmer"]
            if dimmer and dimmer:IsShown() then
                return
            end
            if LM.unlockFrame._padDismissAt == GetTime() then
                return
            end
            -- The game also closes every window by itself (the UI hidden and shown
            -- again, a loading screen, death, loss of control): not a Back press,
            -- so Unlock Mode stays open through those, as it always has. Hiding
            -- the UI marks the frame, so the close when it returns is skipped too.
            if not LM.unlockFrame:IsVisible() then
                LM.unlockFrame._padUIHidden = true
                return
            end
            if LM.unlockFrame._padUIHidden then
                LM.unlockFrame._padUIHidden = nil
                return
            end
            if
                CludesUI._zoneTransitionActive
                or UnitIsDeadOrGhost("player")
                or (not HasFullControl() and not UnitOnTaxi("player"))
            then
                return
            end
            EscapeStep(CludesUI.PadNative() and CanAutoSetGamePadCursorControl(false))
        end

        LM.unlockFrame:Hide()
        return LM.unlockFrame
    end

    -------------------------------------------------------------------------------
    --  Open animation: the options panel folds away while four corner brackets
    --  close in from its size onto the CludesUI logo at the centre of the screen
    --  and lock on; the bar drops in from the top, the logo flies up into the
    --  bar's badge with its brackets, and a scan line sweeps down the screen with
    --  the grid showing behind it. Plain textures, no art files.
    -------------------------------------------------------------------------------
    local EMBLEM_LOGO = 64 -- logo size at the centre of the screen
    local EMBLEM_HALF = 46 -- the brackets' half span round it
    local ARM, THICK = 16, 2 -- bracket arm length and line thickness
    local SCAN_GLOW = 18 -- glow above and below the scan line

    local function CreateOpenAnimFrame(hostFrame)
        if LM.openAnimFrame then
            return LM.openAnimFrame
        end
        local A = CreateFrame("Frame", nil, hostFrame)
        LM.openAnimFrame = A
        A:SetFrameLevel(50) -- above movers (~20), below confirm popup (100)
        A:SetAllPoints(UIParent)

        local emblem = CreateFrame("Frame", nil, A)
        emblem:SetSize(2 * EMBLEM_HALF, 2 * EMBLEM_HALF)
        emblem:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        A._emblem = emblem
        local logo = emblem:CreateTexture(nil, "ARTWORK")
        logo:SetSize(EMBLEM_LOGO, EMBLEM_LOGO)
        logo:SetPoint("CENTER")
        logo:SetTexture("Interface\\AddOns\\CludesUI\\media\\logo-full-thin.png")
        A._logo = logo
        -- Four corner brackets, two arms each (odd = across, even = down).
        local arms = {}
        for i = 1, 8 do
            local a = emblem:CreateTexture(nil, "OVERLAY")
            if i % 2 == 1 then
                a:SetSize(ARM, THICK)
            else
                a:SetSize(THICK, ARM)
            end
            arms[i] = a
        end
        local CORNERS =
            { { "TOPLEFT", -1, 1 }, { "TOPRIGHT", 1, 1 }, { "BOTTOMLEFT", -1, -1 }, { "BOTTOMRIGHT", 1, -1 } }
        function A.SetBrackets(half)
            for c = 1, 4 do
                local p = CORNERS[c]
                for k = 0, 1 do
                    local a = arms[2 * c - 1 + k]
                    a:ClearAllPoints()
                    a:SetPoint(p[1], emblem, "CENTER", p[2] * half, p[3] * half)
                end
            end
        end
        function A.SetBracketAlpha(v)
            for i = 1, 8 do
                arms[i]:SetAlpha(v)
            end
        end

        -- Scan line: the screen's width, a bright line with a soft glow either side.
        local scan = CreateFrame("Frame", nil, A)
        scan:SetHeight(THICK + 2 * SCAN_GLOW)
        local guide = scan:CreateTexture(nil, "OVERLAY")
        guide:SetPoint("LEFT")
        guide:SetPoint("RIGHT")
        guide:SetHeight(THICK)
        local above = scan:CreateTexture(nil, "ARTWORK")
        above:SetPoint("BOTTOMLEFT", guide, "TOPLEFT")
        above:SetPoint("BOTTOMRIGHT", guide, "TOPRIGHT")
        above:SetHeight(SCAN_GLOW)
        above:SetColorTexture(1, 1, 1, 1)
        local below = scan:CreateTexture(nil, "ARTWORK")
        below:SetPoint("TOPLEFT", guide, "BOTTOMLEFT")
        below:SetPoint("TOPRIGHT", guide, "BOTTOMRIGHT")
        below:SetHeight(SCAN_GLOW)
        below:SetColorTexture(1, 1, 1, 1)
        scan:Hide()
        A._scan = scan
        function A.SetScanY(posY)
            scan:ClearAllPoints()
            scan:SetPoint("LEFT", UIParent, "LEFT", 0, posY)
            scan:SetPoint("RIGHT", UIParent, "RIGHT", 0, posY)
        end

        -- The accent colour, or gold for a spec-override session (as the bar).
        function A.Paint(special)
            local red, green, blue = 1, 0.82, 0.30
            if not special then
                local color = CludesUI.CLUDES_GREEN
                red, green, blue = color.r, color.g, color.b
            end
            logo:SetVertexColor(red, green, blue, 1)
            for i = 1, 8 do
                arms[i]:SetColorTexture(red, green, blue, 1)
            end
            guide:SetColorTexture(red, green, blue, 0.9)
            above:SetGradient("VERTICAL", CreateColor(red, green, blue, 0.22), CreateColor(red, green, blue, 0))
            below:SetGradient("VERTICAL", CreateColor(red, green, blue, 0), CreateColor(red, green, blue, 0.22))
        end

        A:Hide()
        return A
    end

    -------------------------------------------------------------------------------
    --  One-time "How to use" tip -- shows below the banner on first ever open.
    --  Saved to CludesUIDB.unlockTipSeen so it never shows again.
    -------------------------------------------------------------------------------

    function mod.ShowUnlockTip()
        if CludesUIDB and CludesUIDB.unlockTipSeen then
            return
        end
        if LM.unlockTipFrame and LM.unlockTipFrame:IsShown() then
            return
        end

        if not LM.unlockTipFrame then
            -- The shared tip callout, its arrow pointing up at the banner
            local tipText = CludesUI.BuildTipCallout(UIParent, {
                width = 450,
                height = 175,
                pp = CludesUI.PP,
                strata = "TOOLTIP",
                level = 900,
                bgAlpha = 0.95,
                font = FONT_PATH,
                fontFlags = "OUTLINE, SLUG",
                text = CludesUI.L(
                    "This is where you can control the settings of Layout Mode.\n\nElements can be repositioned by dragging or arrow keys (+shift)\nAnchor, Height Match, or Width match any element.\nSnapping is based on closest element, but you can snap only to\n a specific element via right click or the settings icon."
                ),
                btnW = 80,
                btnH = 24,
                btnBottom = 15,
                btnFontSize = 10,
                onOkay = function()
                    if CludesUIDB then
                        CludesUIDB.unlockTipSeen = true
                    end
                end,
            })
            -- Pixel-perfect scale (match banner), 100px from the top of the screen
            local physW = (GetPhysicalScreenSize())
            local ppScale = GetScreenWidth() / physW
            tipText:SetScale(ppScale)
            tipText:SetPoint("TOP", UIParent, "TOP", 0, -100 / ppScale)
            LM.unlockTipFrame = tipText
        end

        CludesUI.ShowTipCallout(LM.unlockTipFrame)
    end

    function mod.OpenUnlockMode()
        if LM.isUnlocked then
            return
        end
        if InCombatLockdown() then
            print(CludesUI.L("|cffff6060[CludesUI]|r Cannot enter Layout Mode during combat."))
            return
        end
        -- Standardized options-panel roundtrip: entering unlock mode by ANY means
        -- (minimap, /cuiunlock, ...) while the options panel is open reopens it on exit,
        -- exactly like the sidebar Unlock Mode tab. Options-side entries capture their
        -- own return target BEFORE calling here, so only fill when unset. The game menu
        -- button never coexists with an open panel, so the IsShown gate is a natural no-op there.
        if not CludesUI._unlockReturnModule then
            local panelFrame = CludesUI._mainFrame
            if panelFrame and panelFrame:IsShown() then
                CludesUI._unlockReturnModule = CludesUI:GetActiveModule() or nil
                CludesUI._unlockReturnPage = CludesUI:GetActivePage() or nil
            end
        end
        -- Permanent gold variant: when the current spec's owning group has a custom
        -- unlock layout (the ACTIVE layer), every unlock session on this spec edits
        -- that layer -- so every session shows the special visuals (gold frame/banner,
        -- size inputs hidden). Derived here, not at the card button, so opening unlock any way gets the right identity.
        do
            local activeGid = CludesUI.SpecOverrides_UnlockActive and CludesUI.SpecOverrides_UnlockActive()
                or nil
            local g
            if type(activeGid) == "string" then
                -- Conditional layer live ("cond:<gid>"): same gold identity, the
                -- banner shows the conditional group's name.
                local cid = tonumber(activeGid:match("^cond:(%d+)$"))
                g = cid and CludesUI.Conditions_GroupById and CludesUI.Conditions_GroupById(cid) or nil
            elseif activeGid then
                g = CludesUI.SpecOverrides_GroupById and CludesUI.SpecOverrides_GroupById(activeGid) or nil
            end
            CludesUI._specialUnlockGroup = g
        end
        -- Close any panel-side editing session/view BEFORE taking the value snapshot: the
        -- options panel doesn't hide until much later in this flow, so with the Default
        -- view (or an editing-as session) still holding SWAPPED values live, the snapshot
        -- would capture the view's values while the panel's eventual OnHide restored the
        -- SPEC's values -- Save & Exit would then diff spec-vs-default and bank every
        -- difference into values.default (defaults silently flipping to a group's
        -- values). Exiting the sessions here banks them properly and restores canonical
        -- spec values, so the snapshot below is clean. No-op when the panel is closed.
        if CludesUI.SpecOverrides_CloseEditSessions then
            CludesUI.SpecOverrides_CloseEditSessions()
        end
        -- Value-edit banking baseline: captured settings edited from unlock mode (cog
        -- size inputs) are Default-baseline edits; Save & Exit diffs against this
        -- snapshot and banks into values.default (special sessions skipped inside --
        -- their size inputs are hidden). Must run AFTER the special-group derivation above.
        if CludesUI.SpecOverrides_UnlockValueSnapBegin then
            CludesUI.SpecOverrides_UnlockValueSnapBegin()
        end
        -- Disable expandIfNoResource before _unlockActive is set so the
        -- Rebuild inside runs in normal gameplay state and the power bar
        -- is at its true stored height before movers capture positions.
        if _G._CURB_SuppressExpand then
            pcall(_G._CURB_SuppressExpand)
        end

        LM.isUnlocked = true
        CludesUI._unlockActive = true
        CludesUI._unlockModeActive = true

        -- Notify action bars to flip Blizzard-owned frame anchors for drag
        if _G._CUAB_UnlockModeOpen then
            pcall(_G._CUAB_UnlockModeOpen)
        end
        -- Notify raid frames to fade out overlay previews
        if _G._CURF_UnlockModeOpen then
            pcall(_G._CURF_UnlockModeOpen)
        end

        -- Remove any stale anchor/match relationships before entering unlock mode.
        -- By this point all elements are registered, so anything not in the registry
        -- is genuinely gone (e.g. a custom CDM bar that was deleted).
        ValidateStoredLinks()

        -- Notify beacon reminders to hide (if follow-mouse is active)
        if _G._CUABR_BeaconRefresh then
            pcall(_G._CUABR_BeaconRefresh)
        end

        -- Hide unit frame buffs/debuffs so they don't clutter the movers
        local UF_FRAME_NAMES = {
            "CludesUIUnitFrames_Player",
            "CludesUIUnitFrames_Target",
            "CludesUIUnitFrames_Focus",
            "CludesUIUnitFrames_Pet",
            "CludesUIUnitFrames_TargetTarget",
            "CludesUIUnitFrames_FocusTarget",
        }
        for i = 1, 8 do
            UF_FRAME_NAMES[#UF_FRAME_NAMES + 1] = "CludesUIUnitFrames_Boss" .. i
        end
        for _, name in ipairs(UF_FRAME_NAMES) do
            local f = _G[name]
            if f then
                if f.Buffs and f.Buffs:IsShown() then
                    f.Buffs._unlockWasShown = true
                    f.Buffs:Hide()
                end
                if f.Debuffs and f.Debuffs:IsShown() then
                    f.Debuffs._unlockWasShown = true
                    f.Debuffs:Hide()
                end
            end
        end

        -- Hide objective tracker (alpha only -- no :Hide() to avoid taint).
        -- Hook SetAlpha to suppress Blizzard re-showing it during unlock
        -- (mounting, quest updates, etc. call SetAlpha(1) on their own).
        local questTracker = _G.ObjectiveTrackerFrame
        if questTracker and questTracker:IsShown() then
            LM.objTrackerWasVisible = true
            -- Our state for Blizzard's tracker lives in the frame data table,
            -- never on the frame itself.
            local otfd = CludesUI._GetFFD(questTracker)
            otfd.unlockMouseWasEnabled = questTracker:IsMouseEnabled()
            questTracker:SetAlpha(0)
            if questTracker.EnableMouse then
                pcall(questTracker.EnableMouse, questTracker, false)
            end
            if not otfd.unlockAlphaHooked then
                otfd.unlockAlphaHooked = true
                hooksecurefunc(questTracker, "SetAlpha", function(self, a)
                    if LM.isUnlocked and a > 0 then
                        self:SetAlpha(0)
                    end
                end)
            end
        else
            LM.objTrackerWasVisible = false
        end
        -- Also hide CludesUI QT background (separate UIParent child)
        local trackerBg = _G.CludesUIQTBackground
        if trackerBg then
            trackerBg:SetAlpha(0)
            if not trackerBg._eabUnlockAlphaHooked then
                trackerBg._eabUnlockAlphaHooked = true
                hooksecurefunc(trackerBg, "SetAlpha", function(self, a)
                    if LM.isUnlocked and a > 0 then
                        self:SetAlpha(0)
                    end
                end)
            end
        end

        -- Reset session state and snapshot current positions
        wipe(pendingPositions)
        LM.hasChanges = false
        LM.selectedMover = nil
        -- Clear per-session temporary overlay hides (Shift+Right Click). Every unlock
        -- session starts with all overlays visible again. Cleared before the fade-in
        -- Sync / ShowBlizzOwnedOverlays calls so last session's hides don't persist.
        -- Fallback/override anchor ghosts carry the same flag (their tables are
        -- do-block locals, hence the namespaced helpers).
        for _, m in pairs(handles) do
            m._tempHidden = nil
        end
        for _, shade in pairs(_blizzOwnedOverlays) do
            shade._tempHidden = nil
        end
        if CludesUI._ClearFallbackGhostTempHides then
            CludesUI._ClearFallbackGhostTempHides()
        end
        if CludesUI._ClearOverrideGhostTempHides then
            CludesUI._ClearOverrideGhostTempHides()
        end
        -- Strip provider-owned visual adjustments that live OUTSIDE the anchor
        -- system (CDM's Additional Bar Offset on un-anchored bars): each enter hook
        -- self-gates, so this is near-free when nothing is active.
        CludesUI.RunAnchorShiftEnters()
        -- Strip any temporary anchor-target shift (e.g. "Shift Elements if No
        -- Resource"/"...if No Bars") so movers snapshot TRUE saved positions.
        -- _unlockActive is already true above, so the shift providers return 0 and
        -- this re-apply snaps shifted children back to their real positions. Gated so
        -- non-shift profiles do no extra work on unlock entry.
        if CludesUI.AnchorShiftWantsApply() and CludesUI.ReapplyAllUnlockAnchors then
            -- Force edge-preservation for this reapply so custom-growth anchored bars
            -- snap to their fixed growth edge (their true saved position), not the
            -- center-offset position. Reset in all cases (pcall) so the flag can't leak.
            CludesUI._reapplyForceEdgePreserve = true
            pcall(CludesUI.ReapplyAllUnlockAnchors)
            CludesUI._reapplyForceEdgePreserve = false
        end
        SnapshotPositions()

        -- Setup and show arrow key frame for nudge support
        SetupArrowKeyFrame()
        LM.arrowKeyFrame:Show()

        -- Play unlock sound
        PlaySound(201528, "Master")

        -- Create frames
        CreateUnlockFrame()
        CreateGrid(LM.unlockFrame)
        CreateHUD(LM.unlockFrame)
        CludesUI:_NotifyUnlockModeListeners(true)
        CreateOpenAnimFrame(LM.unlockFrame)

        -- Special (spec-override) sessions paint the bar gold, normal sessions in
        -- the accent colour. Re-set every open: the bar is created once and reused.
        if LM.PaintBanner then
            LM.PaintBanner(CludesUI._specialUnlockGroup)
        end

        -- Capture the options panel frame for the shrink animation
        local panelFrame = CludesUI and CludesUI._mainFrame
        local panelStartW, panelStartH
        if panelFrame and panelFrame:IsShown() then
            panelStartW = panelFrame:GetWidth()
            panelStartH = panelFrame:GetHeight()
        end
        panelStartW = panelStartW or 600
        panelStartH = panelStartH or 400

        -- Controller Back steps out like Escape: registered with the escape proxy
        -- on the first open with a controller in use (padOnly: it counts only then),
        -- and never a controller-cursor root (a pointer-drag UI).
        if not LM.unlockFrame._padEsc and CludesUI.PadInUse() then
            LM.unlockFrame._padEsc = true
            CludesUI.RegisterEscapeClose(LM.unlockFrame, {
                padOnly = true,
                notOwned = true,
                onEscape = LM.unlockFrame._padBack,
            })
        end

        -- Show overlay, hide grid/toolbar/movers
        LM.unlockFrame:Show()
        LM.unlockFrame:SetAlpha(1)
        if LM.gridFrame then
            LM.gridFrame:Hide()
        end
        if LM.hudFrame then
            LM.hudFrame:Hide()
        end
        for _, m in pairs(handles) do
            m:Hide()
        end

        -- The open animation (CreateOpenAnimFrame): the emblem at the centre, its
        -- brackets starting round the panel; the bar's badge logo waits for the
        -- emblem to land in it.
        local A = LM.openAnimFrame
        local emblem = A._emblem
        A.Paint(CludesUI._specialUnlockGroup)
        local startHalf = max(EMBLEM_HALF + 20, min(panelStartW, panelStartH) * 0.5)
        emblem:SetScale(1)
        emblem:ClearAllPoints()
        emblem:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        A._logo:SetAlpha(0)
        A.SetBrackets(startHalf)
        A.SetBracketAlpha(0)
        A._scan:Hide()
        if LM.hudFrame and LM.hudFrame._badgeLogo then
            LM.hudFrame._badgeLogo:SetAlpha(0)
        end
        A:Show()
        A:SetAlpha(1)

        -- Start overlay at 0 alpha, will fade in during animation
        if LM.unlockFrame._overlay then
            LM.unlockFrame._overlay:SetColorTexture(0.020, 0.025, 0.031, 0)
        end

        -- Phase timings, in seconds from the click
        local MORPH = 0.35 -- panel folds away, brackets close in on the logo
        local LOCK = 0.15 -- brackets snap on (a small pull-in and back)
        local BAR_START, BAR_DUR = 0.42, 0.40 -- the bar drops in
        local FLY_START, FLY_DUR = 0.55, 0.40 -- the emblem flies up into the bar's badge
        local SCAN_START, SCAN_DUR = 0.45, 0.55 -- the scan line sweeps down; the grid shows behind it
        local DONE = FLY_START + FLY_DUR + 0.05

        local panelHidden = false
        local panelRealScale = panelFrame and panelFrame:GetScale() or 1
        local timePassed = 0
        local fadeInSynced = false
        local moversIn = false

        -- Auto-select a mover if requested (the cog popup link, the options rows'
        -- Move in Unlock Mode button), flashing it when the request asks: the
        -- moment the movers have faded in, so the flash answers the click, and
        -- again at the landing for a mover that was not built yet (the retry
        -- ticker spawns late registrations). The request is kept until the mover
        -- exists; the landing drops it after one more try.
        local function TryAutoSelect()
            local autoKey = CludesUI._unlockAutoSelectKey
            if not autoKey then
                return
            end
            local m = handles[autoKey]
            if not m then
                return
            end
            local autoFlash = CludesUI._unlockAutoSelectFlash
            CludesUI._unlockAutoSelectKey = nil
            CludesUI._unlockAutoSelectFlash = nil
            SelectMover(m)
            if autoFlash then
                LM.FlashSelectHighlight(m)
            end
        end

        -- Grid, movers and overlays start at once; the movers fade in over GLITCH_DUR
        local GLITCH_DUR = 0.60
        local GRID_START = 0 -- grid begins immediately
        local gridStarted = false

        -- Reset cursor speed so the first hover isn't blocked by a stale value
        CludesUI._unlockCursorSpeed = 0

        LM.unlockFrame:SetScript("OnUpdate", function(self, elapsed)
            -- Sample cursor position and compute speed for hover intent detection
            do
                local scale = UIParent:GetEffectiveScale()
                local nx, ny = GetCursorPosition()
                nx = nx / scale
                ny = ny / scale
                if elapsed > 0 then
                    local dx = nx - CludesUI._unlockCursorX
                    local dy = ny - CludesUI._unlockCursorY
                    -- Store squared speed to avoid sqrt; TryExpand compares against squared threshold
                    CludesUI._unlockCursorSpeed = (dx * dx + dy * dy) / (elapsed * elapsed)

                    -- After arrow-key nudge collapsed a mover, re-expand it
                    -- once the cursor moves and is still hovering the mover.
                    if LM.selectedMover and LM.selectedMover._nudgeCollapsed then
                        local moved = (dx ~= 0 or dy ~= 0)
                        if moved then
                            LM.selectedMover._nudgeCollapsed = nil
                            if LM.selectedMover:IsMouseOver() then
                                if LM.selectedMover._showOverlayText then
                                    LM.selectedMover._showOverlayText()
                                    LM.hoveredMover = LM.selectedMover
                                end
                            end
                        end
                    end
                end
                CludesUI._unlockCursorX = nx
                CludesUI._unlockCursorY = ny
            end

            -- Selected movers are NOT auto re-expanded: expansion is purely
            -- hover-driven. A selected element (e.g. one being width/height matched or
            -- anchored) keeps its border/level highlight via OnLeave regardless; the
            -- nudge block above re-expands only while the cursor is over the mover.

            timePassed = timePassed + elapsed

            ---------------------------------------------------------------
            --  Background overlay fade: 0 -> full alpha over 0.75 seconds
            --  (synced with grid glitch duration)
            ---------------------------------------------------------------
            local OVERLAY_FADE_DUR = 0.75
            if LM.unlockFrame._overlay then
                local oa = min(1, timePassed / OVERLAY_FADE_DUR) * (LM.unlockFrame._overlayMaxAlpha or 0.20)
                LM.unlockFrame._overlay:SetColorTexture(0.020, 0.025, 0.031, oa)
            end

            ---------------------------------------------------------------
            --  Grid glitch overlay -- runs independently of lock phases
            --  Starts at GRID_START (beginning of idle spin, 1s earlier)
            ---------------------------------------------------------------
            if timePassed >= GRID_START then
                if not gridStarted then
                    gridStarted = true
                    if LM.gridFrame then
                        LM.gridFrame:Rebuild()
                        if LM.gridMode ~= "disabled" then
                            LM.gridFrame:Show()
                        end
                        LM.gridFrame:SetAlpha(0)
                    end
                    if LM.hudFrame then
                        LM.hudFrame:Show()
                        LM.hudFrame:SetAlpha(1)
                        -- Position off-screen (will slide down during shackle)
                        LM.hudFrame:ClearAllPoints()
                        local ppS = LM.hudFrame:GetScale() or 1
                        LM.hudFrame:SetPoint("TOP", UIParent, "TOP", 0, (BANNER_PX_H + 10) * ppS)
                    end
                    for _, barId in ipairs(ALL_BAR_ORDER) do
                        -- Skip bars that have a registered element (avoids duplicates)
                        if not registeredElements[barId] then
                            local m = CreateMover(barId)
                            if m then
                                m:Sync()
                                m:SetAlpha(0)
                            end
                        end
                    end
                    -- Registered elements (unit frames, etc.)
                    RebuildRegisteredOrder()
                    for _, barKey in ipairs(registeredOrder) do
                        local m = CreateMover(barKey)
                        if m then
                            m:Sync()
                            m:SetAlpha(0)
                        end
                    end
                    -- Sort frame levels: smaller movers render on top
                    SortMoverFrameLevels()
                    -- Re-apply saved anchor positions and refresh anchored mover text
                    ReapplyAllAnchors()
                    wipe(pendingPositions)
                    for bk, _ in pairs(handles) do
                        if handles[bk].RefreshAnchoredText then
                            handles[bk]:RefreshAnchoredText()
                        end
                    end
                    -- Spec-override gold borders / special-session locks + banner
                    if CludesUI._unlockRefreshSpecOvMarks then
                        CludesUI._unlockRefreshSpecOvMarks()
                    end

                    -- Info overlays on Blizzard-owned elements (chat, micro, bags, encounter)
                    -- Start at alpha 0; the mover fade-in loop below handles them.
                    ShowBlizzOwnedOverlays(LM.unlockFrame)
                    for _, bov in pairs(_blizzOwnedOverlays) do
                        bov:SetAlpha(0)
                    end

                    -- Fallback ghost overlays for elements with a fallback link
                    -- (spawn at 0 alpha; the mover fade-in loop below ramps them)
                    if CludesUI._RefreshFallbackGhosts then
                        CludesUI._RefreshFallbackGhosts()
                        if CludesUI._SetFallbackGhostsAlpha then
                            CludesUI._SetFallbackGhostsAlpha(0)
                        end
                    end

                    -- Override anchors release to baseline for the session (movers
                    -- edit the baseline; the gold ghosts edit the overrides), then
                    -- their ghosts spawn on the same fade curve.
                    if CludesUI._ReapplyOverrideAnchors then
                        CludesUI._ReapplyOverrideAnchors()
                    end
                    if CludesUI._RefreshOverrideGhosts then
                        CludesUI._RefreshOverrideGhosts()
                        if CludesUI._SetOverrideGhostsAlpha then
                            CludesUI._SetOverrideGhostsAlpha(0)
                        end
                    end

                    -- Retry ticker: some addons (CDM) may not have their bar
                    -- frames ready yet. Poll briefly to catch late arrivals.
                    local retryAttempts = 0
                    local retryTicker
                    retryTicker = C_Timer.NewTicker(0.5, function()
                        retryAttempts = retryAttempts + 1
                        if not LM.isUnlocked then
                            retryTicker:Cancel()
                            return
                        end
                        -- Ask addons to re-register elements they may not have
                        -- registered yet (CDM bars that were still building, etc.)
                        if CludesUI._unlockRegistrationDirty or retryAttempts <= 3 then
                            if _G._CUCME_RegisterUnlock then
                                _G._CUCME_RegisterUnlock()
                            end
                            if _G._CUCME_RegisterTBBUnlock then
                                _G._CUCME_RegisterTBBUnlock()
                            end
                            -- Late-registering frames may satisfy a fallback
                            -- ghost that could not resolve at open.
                            if CludesUI._RefreshFallbackGhosts then
                                CludesUI._RefreshFallbackGhosts()
                            end
                            if CludesUI._RefreshOverrideGhosts then
                                CludesUI._RefreshOverrideGhosts()
                            end
                        end
                        RebuildRegisteredOrder()
                        local spawned = false
                        local missing = false
                        for _, rk in ipairs(registeredOrder) do
                            if not handles[rk] then
                                local removeBtn = CreateMover(rk)
                                if removeBtn then
                                    removeBtn:Sync()
                                    removeBtn:SetAlpha(LM.darkOverlaysEnabled and 1 or MOVER_ALPHA)
                                    removeBtn:Show()
                                    spawned = true
                                else
                                    missing = true
                                end
                            elseif not handles[rk]:IsShown() then
                                -- Mover exists but bar frame was not ready on
                                -- first Sync -- re-sync now that it may be available
                                local re = registeredElements[rk]
                                if not (re and re.isHidden and re.isHidden()) then
                                    local removeBtn = handles[rk]
                                    removeBtn:Sync()
                                    if removeBtn:IsShown() then
                                        removeBtn:SetAlpha(LM.darkOverlaysEnabled and 1 or MOVER_ALPHA)
                                        spawned = true
                                    else
                                        missing = true
                                    end
                                end
                            end
                        end
                        if spawned then
                            SortMoverFrameLevels()
                            ReapplyAllAnchors()
                            if CludesUI._unlockRefreshSpecOvMarks then
                                CludesUI._unlockRefreshSpecOvMarks()
                            end
                        end
                        -- Stop once every mover is visible, or after timeout
                        if not missing or retryAttempts >= 20 then
                            retryTicker:Cancel()
                        end
                    end)
                end

                local glitchT = timePassed - GRID_START

                -- Movers fade in over GLITCH_DUR, delayed by MOVER_DELAY (both
                -- end before the animation does). A mover selected meanwhile (the
                -- auto-select, a click) keeps the alpha the selection gave it.
                local MOVER_DELAY = 0.40
                local fadeTime = glitchT - MOVER_DELAY
                for _, m in pairs(handles) do
                    if m:IsShown() and not m._selected then
                        if fadeTime > 0 then
                            -- Re-sync once right as movers begin fading in so any
                            -- frames that were nil at initial sync are now ready.
                            if not fadeInSynced then
                                fadeInSynced = true
                                for _, removeBtn in pairs(handles) do
                                    removeBtn:Sync()
                                end
                            end
                            m:SetAlpha(
                                (LM.darkOverlaysEnabled and 1 or MOVER_ALPHA)
                                    * min(1, fadeTime / GLITCH_DUR)
                            )
                        else
                            m:SetAlpha(0)
                        end
                    end
                end
                -- The movers are in: the requested mover is selected and flashed now.
                if not moversIn and fadeTime >= GLITCH_DUR then
                    moversIn = true
                    TryAutoSelect()
                end
                -- Blizzard-owned overlays fade in on the same curve
                for _, bov in pairs(_blizzOwnedOverlays) do
                    if bov:IsShown() then
                        if fadeTime > 0 then
                            bov:SetAlpha(min(1, fadeTime / GLITCH_DUR))
                        else
                            bov:SetAlpha(0)
                        end
                    end
                end
                -- Fallback ghosts fade in on the same curve (75% resting alpha)
                if CludesUI._SetFallbackGhostsAlpha then
                    if fadeTime > 0 then
                        CludesUI._SetFallbackGhostsAlpha(min(1, fadeTime / GLITCH_DUR))
                    else
                        CludesUI._SetFallbackGhostsAlpha(0)
                    end
                end
                -- Override anchor ghosts ride the same curve
                if CludesUI._SetOverrideGhostsAlpha then
                    if fadeTime > 0 then
                        CludesUI._SetOverrideGhostsAlpha(min(1, fadeTime / GLITCH_DUR))
                    else
                        CludesUI._SetOverrideGhostsAlpha(0)
                    end
                end

                -- The grid shows behind the scan line as it sweeps down.
                if LM.gridFrame and LM.gridFrame:IsShown() then
                    LM.gridFrame:SetAlpha(max(0, min(1, (timePassed - SCAN_START) / SCAN_DUR)))
                end
            end

            -------------------------------------------------------------------
            --  Fold: the panel scales down and fades while the brackets close in
            --  from its size onto the logo, which grows in.
            -------------------------------------------------------------------
            if timePassed < MORPH then
                local t = EaseInOutCubic(timePassed / MORPH)
                if panelFrame and not panelHidden then
                    panelFrame:SetScale(panelRealScale * max(0.01, 1 - 0.4 * t))
                    panelFrame:SetAlpha(1 - min(1, timePassed / 0.2))
                    if t > 0.95 then
                        panelHidden = true
                        panelFrame:SetScale(panelRealScale)
                        panelFrame:SetAlpha(1)
                        CludesUI:Hide()
                    end
                end
                A.SetBrackets(startHalf + (EMBLEM_HALF - startHalf) * t)
                A.SetBracketAlpha(min(1, timePassed / 0.12))
                local ls = EMBLEM_LOGO * (1.4 - 0.4 * t)
                A._logo:SetSize(ls, ls)
                A._logo:SetAlpha(t)
                return
            end

            -- Ensure panel is hidden (one-time cleanup, no visual snap)
            if not panelHidden then
                panelHidden = true
                if panelFrame then
                    panelFrame:SetScale(panelRealScale)
                    panelFrame:SetAlpha(1)
                end
                CludesUI:Hide()
            end
            A._logo:SetSize(EMBLEM_LOGO, EMBLEM_LOGO)
            A._logo:SetAlpha(1)
            A.SetBracketAlpha(1)

            -- Lock: the brackets pull in a few pixels and spring back.
            local lt = timePassed - MORPH
            if lt < LOCK then
                A.SetBrackets(EMBLEM_HALF - 6 * sin(lt / LOCK * math.pi))
            else
                A.SetBrackets(EMBLEM_HALF)
            end

            -- The bar drops in from above, settling with a slight overshoot.
            local hud = LM.hudFrame
            if hud and hud:IsShown() then
                local u = min(1, max(0, (timePassed - BAR_START) / BAR_DUR)) - 1
                local e = 1 + 2.2 * u * u * u + 1.2 * u * u
                hud:ClearAllPoints()
                hud:SetPoint("TOP", UIParent, "TOP", 0, (BANNER_PX_H + 10) * (hud:GetScale() or 1) * (1 - e))
            end

            -- The emblem flies up into the bar's badge, shrinking to its size:
            -- the brackets land on the badge's border and the logo on its logo.
            local ft = (timePassed - FLY_START) / FLY_DUR
            local target = hud and hud._badgeLogo
            if ft > 0 and target and target:GetCenter() then
                local f = EaseInOutCubic(min(1, ft))
                local uiS = UIParent:GetEffectiveScale()
                local tR = target:GetEffectiveScale() / uiS
                local aR = A:GetEffectiveScale() / uiS
                local tScale = target:GetWidth() / EMBLEM_LOGO * tR / aR
                emblem:SetScale(1 + (tScale - 1) * f)
                -- The logo's centre, from the screen's centre, in UIParent units.
                local tx, ty = target:GetCenter()
                local cx, cy = UIParent:GetCenter()
                local posX, posY = (tx * tR - cx) * f, (ty * tR - cy) * f
                local k = uiS / emblem:GetEffectiveScale()
                emblem:ClearAllPoints()
                emblem:SetPoint("CENTER", UIParent, "CENTER", posX * k, posY * k)
            end

            -- The scan line leaves the emblem and sweeps to the bottom of the screen.
            local sp = (timePassed - SCAN_START) / SCAN_DUR
            if sp > 0 and sp < 1 then
                local e = 1 - (1 - sp) * (1 - sp) * (1 - sp)
                A._scan:Show()
                A.SetScanY(-(UIParent:GetHeight() / 2 + SCAN_GLOW) * e)
                A._scan:SetAlpha(sp < 0.15 and sp / 0.15 or (sp > 0.8 and (1 - sp) / 0.2 or 1))
            else
                A._scan:Hide()
            end

            if timePassed < DONE then
                return
            end

            -------------------------------------------------------------------
            --  Done -- logo stays at full alpha, grid fully visible,
            --  banner is at final position (flush with top of screen)
            -------------------------------------------------------------------
            -- The emblem has landed: the badge's own logo takes over.
            A._scan:Hide()
            A:Hide()
            if LM.hudFrame and LM.hudFrame._badgeLogo then
                LM.hudFrame._badgeLogo:SetAlpha(1)
            end
            if LM.gridFrame then
                LM.gridFrame:SetAlpha(1)
            end
            if LM.hudFrame then
                LM.hudFrame:ClearAllPoints()
                LM.hudFrame:SetPoint("TOP", UIParent, "TOP", 0, 0)
                LM.hudFrame._refitOutlines()
            end
            self:SetScript("OnUpdate", nil)

            -- Start anchor connector line updates now that movers are visible
            if LM.unlockFrame._anchorLineDriver then
                LM.unlockFrame._anchorLineDriver:Show()
            end
            if LM.unlockFrame._anchorLineFrame then
                LM.unlockFrame._anchorLineFrame:Show()
            end

            -- A requested mover not built when the movers faded in: one more try
            -- after the retry ticker's first pass, then the request is dropped.
            TryAutoSelect()
            if CludesUI._unlockAutoSelectKey then
                C_Timer.After(0.6, function()
                    TryAutoSelect()
                    CludesUI._unlockAutoSelectKey = nil
                    CludesUI._unlockAutoSelectFlash = nil
                end)
            end

            -- Show one-time toolbar tip (after animation settles)
            mod.ShowUnlockTip()
        end)
    end
end
