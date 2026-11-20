if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnlockMode_Anchors.lua
--  Anchor / match engine: anchor and size-match DB helpers, match status
--  API, link pruning and re-keying, NotifyElementResized, OnSizeChanged
--  hooks, combat-parked positioning, fallback anchors.
--  Loaded after CUI_UnlockMode.lua; _unlockCoreInit runs it once with UM.
-------------------------------------------------------------------------------
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS -- standalone builds: the core's own table (CludesUI.lua)
CUI_NS.unlockParts = CUI_NS.unlockParts or {}
CUI_NS.unlockParts.Anchors = function(LM)
    local mod, floor, Pix, registeredElements = CUI_NS, LM.floor, LM.PP, LM.registeredElements
    local movers, pendingPositions, SELECT_ELEMENT_ALPHA, SELECT_ELEMENT_FADE =
        LM.movers, LM.pendingPositions, LM.SELECT_ELEMENT_ALPHA, LM.SELECT_ELEMENT_FADE

    -------------------------------------------------------------------------------
    --  Anchor / Match DB helpers  -- cui-style: allow comment-budget
    --  CludesUIDB.unlockAnchors = { [childKey] = { target=key, side="LEFT"|"RIGHT"|"TOP"|"BOTTOM" } }
    --  Width/height matches apply immediately into the element's own settings.
    -------------------------------------------------------------------------------

    -- Blizzard's quest tracker grows down; a tracker of our own under the same
    -- key answers for itself.
    local function QuestTrackerGrowDir()
        local get = CludesUI.GetQuestTrackerGrowDir
        return get and get() or "DOWN"
    end

    -------------------------------------------------------------------------------
    --  Actual grow direction -- never nil; used by position math that needs the
    --  true anchor edge.
    -------------------------------------------------------------------------------
    local function GetBarGrowDirActual(barId)
        if barId == "EQT_Tracker" then
            return QuestTrackerGrowDir()
        end
        -- Via the owning module's resolver so menu/layout never disagree (clamps to orientation on read, not save).
        if barId == "ERB_TotemBar" then
            if CludesUI.GetTotemGrowDir then
                return (CludesUI.GetTotemGrowDir())
            end
            return "RIGHT"
        end
        if barId == "EABR_Reminders" then
            if CludesUI.GetAuraBuffGrowDir then
                return CludesUI.GetAuraBuffGrowDir()
            end
            return "CENTER"
        end
        if barId:sub(1, 4) == "CDM_" then
            local rawKey = barId:sub(5)
            local cdm = CludesUI.Lite.GetAddon("CludesUICooldownManager", true)
            local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
            if cdmBars and cdmBars.bars then
                for _, barCfg in ipairs(cdmBars.bars) do
                    if barCfg.key == rawKey then
                        return barCfg.growDirection or "CENTER"
                    end
                end
            end
            return "CENTER"
        else
            local eab = CludesUI.Lite.GetAddon("CludesUIActionBars", true)
            local cfg = eab and eab.db and eab.db.profile and eab.db.profile.bars and eab.db.profile.bars[barId]
            if cfg then
                return (cfg.growDirection or "up"):upper()
            end
            return "CENTER"
        end
    end

    -------------------------------------------------------------------------------
    --  Grow direction from the bar's per-profile settings: uppercase string, or nil
    --  if default/unset. Action bar default "UP", CDM default nil (centered).
    -------------------------------------------------------------------------------
    local function GetBarGrowDir(barId)
        if barId == "EQT_Tracker" then
            return QuestTrackerGrowDir()
        end
        if barId == "ERB_TotemBar" then
            if not CludesUI.GetTotemGrowDir then
                return "RIGHT"
            end
            local g = CludesUI.GetTotemGrowDir()
            if g == "CENTER" then
                return nil
            end -- centered = no direction indicator
            return g
        end
        if barId == "EABR_Reminders" then
            if not CludesUI.GetAuraBuffGrowDir then
                return nil
            end
            local g = CludesUI.GetAuraBuffGrowDir()
            if g and g ~= "CENTER" then
                return g
            end
            return nil
        end
        if barId:sub(1, 4) == "CDM_" then
            local rawKey = barId:sub(5)
            local cdm = CludesUI.Lite.GetAddon("CludesUICooldownManager", true)
            local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
            if cdmBars and cdmBars.bars then
                for _, barCfg in ipairs(cdmBars.bars) do
                    if barCfg.key == rawKey then
                        local g = barCfg.growDirection
                        if g and g ~= "CENTER" then
                            return g
                        end
                        return nil
                    end
                end
            end
            return nil
        else
            local eab = CludesUI.Lite.GetAddon("CludesUIActionBars", true)
            local cfg = eab and eab.db and eab.db.profile and eab.db.profile.bars and eab.db.profile.bars[barId]
            if cfg then
                local g = (cfg.growDirection or "up"):upper()
                if g == "CENTER" then
                    return nil
                end
                -- UP is default for horizontal bars (no indicator) but meaningful for vertical (show indicator)
                if g == "UP" and (cfg.orientation or "horizontal") ~= "vertical" then
                    return nil
                end
                return g
            end
            return nil
        end
    end

    local function GetAnchorDB()
        if not CludesUIDB then
            return nil
        end
        if not CludesUIDB.unlockAnchors then
            CludesUIDB.unlockAnchors = {}
        end
        return CludesUIDB.unlockAnchors
    end

    -- A link saved on an element that places itself (ownsPosition: main chat) is
    -- inert, so it reads as none: no anchor rows in its cog, and no false circle
    -- when another element links to it. ValidateStoredLinks deletes it when
    -- Unlock Mode opens.
    local function GetAnchorInfo(barId)
        local saved = GetAnchorDB()
        if not saved then
            return nil
        end
        local element = registeredElements[barId]
        if element and element.ownsPosition then
            return nil
        end
        return saved[barId]
    end

    -- Re-applies the grow-direction-aware anchor after a resize so the fixed edge stays
    -- put. Must be synchronous (no C_Timer.After) to avoid a visible flicker frame.
    -- Defined here, after its dependencies, so the closure captures the right upvalues.
    function CludesUI.RecenterBarAnchor(barId)
        if not LM.isUnlocked then
            return
        end
        if mod.PointAnchors.Recenter(barId, LM) then
            return
        end
        local element = registeredElements[barId]
        if element and element.isAnchored and element.isAnchored() then
            return
        end
        local widget = LM.GetBarFrame(barId)
        if not widget then
            return
        end

        local s = widget:GetEffectiveScale()
        local uiScale = UIParent:GetEffectiveScale()
        local elemScale = s / uiScale

        local bL = widget:GetLeft()
        local bT = widget:GetTop()
        if not bL or not bT then
            return
        end

        local wid = (widget:GetWidth() or 0) * elemScale
        local hgt = (widget:GetHeight() or 0) * elemScale
        if wid < 1 or hgt < 1 then
            return
        end

        -- Center in UIParent-BOTTOMLEFT space
        local uiCX = bL * elemScale + wid * 0.5
        local uiCY = bT * elemScale - hgt * 0.5

        local growDir = GetBarGrowDirActual(barId)
        local anchor, aX, aY
        if growDir == "RIGHT" then
            anchor = "LEFT"
            aX = bL * elemScale
            aY = uiCY
        elseif growDir == "LEFT" then
            anchor = "RIGHT"
            aX = (bL * elemScale) + wid
            aY = uiCY
        elseif growDir == "DOWN" then
            anchor = "TOP"
            aX = uiCX
            aY = bT * elemScale
        elseif growDir == "UP" then
            anchor = "BOTTOM"
            aX = uiCX
            aY = bT * elemScale - hgt
        else
            anchor = "CENTER"
            aX = uiCX
            aY = uiCY
        end

        -- Convert to CENTER-relative (the unlock mode system's standard format)
        local uiW, uiH = UIParent:GetSize()
        local cRelX = aX - uiW / 2
        local cRelY = aY - uiH / 2

        -- Snap to the physical pixel grid so subpixel coords never persist into pendingPositions -> CommitPositions -> SavedVariables.
        local PPr = Pix or (CludesUI and CludesUI.PP)
        if PPr then
            if anchor == "CENTER" then
                cRelX = PPr.SnapCenterForDim(cRelX, wid, uiScale)
                cRelY = PPr.SnapCenterForDim(cRelY, hgt, uiScale)
            else
                cRelX = PPr.SnapForES(cRelX, uiScale)
                cRelY = PPr.SnapForES(cRelY, uiScale)
            end
        end

        -- cRelX/cRelY are UIParent units; SetPoint offsets read in the frame's own space
        -- (identical unless the element self-scales, see ApplyCenterPosition) -- divide is a no-op for anything unscaled.
        local setX, setY = cRelX, cRelY
        if elemScale ~= 1 and elemScale > 0 then
            setX = cRelX / elemScale
            setY = cRelY / elemScale
        end

        pcall(function()
            CludesUI.ClearFramePoints(widget)
            CludesUI.SetFramePoint(widget, anchor, UIParent, "CENTER", setX, setY)
        end)

        -- Keep mover's stored center in sync so drag/snap logic stays consistent
        local handle = movers[barId]
        if handle and handle._setCenterXY then
            handle._setCenterXY(uiCX, uiCY - uiH)
        end
    end

    local function SetAnchorInfo(childBarKey, targetBarKey, edgeSide, offsetX, offsetY)
        local saved = GetAnchorDB()
        if not saved then
            return
        end
        -- Keep an existing fallback only when re-anchoring to the SAME target; a new target invalidates it (fallback belongs to the link, not the child).
        local previous = saved[childBarKey]
        local fb = previous and previous.target == targetBarKey and previous.fallback or nil
        -- The cross-axis screen edge belongs to the CHILD, not to this link, so it
        -- survives a re-anchor -- unless the new target claims its axis (edge target),
        -- in which case the two would fight over the same coordinate.
        local edge = previous and previous.edge or nil
        if
            edge
            and edge.key
            and CludesUI._ScreenEdgeAxis
            and CludesUI._ScreenEdgeAxis(edge.key) == CludesUI._ScreenEdgeAxis(targetBarKey)
        then
            edge = nil
        end
        saved[childBarKey] = {
            target = targetBarKey,
            side = edgeSide,
            offsetX = offsetX,
            offsetY = offsetY,
            fallback = fb,
            edge = edge,
        }
        -- Link-change stamp: modules with memoized views over the anchor DB (e.g.
        -- the tracking bar growth-edge extent watch) re-derive lazily.
        CludesUI._anchorLinksStamp = (CludesUI._anchorLinksStamp or 0) + 1
        CludesUI._EnsureFallbackWatchers()
    end

    local function ClearAnchorInfo(childBarKey)
        local saved = GetAnchorDB()
        if not saved then
            return
        end
        saved[childBarKey] = nil
        CludesUI._anchorLinksStamp = (CludesUI._anchorLinksStamp or 0) + 1
        CludesUI._EnsureFallbackWatchers()
    end

    local function IsAnchored(barId)
        local details = GetAnchorInfo(barId)
        if details ~= nil then
            return true
        end
        local element = registeredElements[barId]
        return element and element.isAnchored and element.isAnchored() or false
    end

    -- Element anchored via a module option (e.g. ERB "Anchor To") with keepMoverWhenAnchored:
    -- mover exists but is position-locked (module's anchor owns position) -- drag/nudge/
    -- anchor-link disabled, resize and width/height match stay. On ns: deferred body is at the 200-local cap.
    function mod.IsMoverPosLocked(barId)
        local element = registeredElements[barId]
        if not (element and element.keepMoverWhenAnchored) then
            return false
        end
        return element.isAnchored and element.isAnchored() or false
    end

    -- Width/Height match persistent links
    local MatchH = {}

    function MatchH.GetWidthMatchDB()
        if not CludesUIDB then
            return nil
        end
        if not CludesUIDB.unlockWidthMatch then
            CludesUIDB.unlockWidthMatch = {}
        end
        return CludesUIDB.unlockWidthMatch
    end

    function MatchH.GetHeightMatchDB()
        if not CludesUIDB then
            return nil
        end
        if not CludesUIDB.unlockHeightMatch then
            CludesUIDB.unlockHeightMatch = {}
        end
        return CludesUIDB.unlockHeightMatch
    end

    -- Extra width / height on a match (the unlock cog's Extra Width / Extra Height
    -- rows): whole physical pixels at the child's scale, added to the matched size
    -- after the target's pad and before the child's own pad comes off. Keyed by the
    -- child element like its link ("w" / "h" axis); stored only while non-zero and
    -- read only while the child's link exists, so a leftover entry does nothing.
    function CludesUI.GetMatchExtra(dim, barKey)
        if not CludesUIDB or not barKey then
            return nil
        end
        local t
        if dim == "h" then
            t = CludesUIDB.unlockHeightMatchExtra
        else
            t = CludesUIDB.unlockWidthMatchExtra
        end
        local val = t and t[barKey]
        if val and val ~= 0 then
            return val
        end
        return nil
    end

    function MatchH.SetMatchExtra(dim, barKey, px)
        if not CludesUIDB or not barKey then
            return
        end
        local field = "unlockWidthMatchExtra"
        if dim == "h" then
            field = "unlockHeightMatchExtra"
        end
        px = tonumber(px)
        if px then
            px = math.floor(px + 0.5)
        end
        local tbl = CludesUIDB[field]
        if not px or px == 0 then
            if tbl then
                tbl[barKey] = nil
            end
            return
        end
        if not tbl then
            tbl = {}
            CludesUIDB[field] = tbl
        end
        tbl[barKey] = px
    end

    function MatchH.GetWidthMatchInfo(barId)
        local saved = MatchH.GetWidthMatchDB()
        return saved and saved[barId] or nil
    end

    function MatchH.GetHeightMatchInfo(barId)
        local saved = MatchH.GetHeightMatchDB()
        return saved and saved[barId] or nil
    end

    -- Cycle detect: walk the chain from targetKey; reaching childKey would loop forever.
    function MatchH.WouldCreateCycle(saved, childBarKey, targetBarKey)
        local seen = {}
        local current = targetBarKey
        while current do
            if current == childBarKey then
                return true
            end
            if seen[current] then
                return false
            end
            seen[current] = true
            current = saved[current]
        end
        return false
    end

    -- True when barKey's width/height is driven, via an unbroken chain of match links,
    -- by a content-sized bar: a CDM_ bar, or an action bar reached through at least one
    -- link (0-hop start mirrors call-site direct-target tests, so a bar matched
    -- DIRECTLY to a plain action bar never qualifies). Match DBs key on literal element
    -- keys (no alias resolution), as the anchor cascade reads them; visited guards malformed cycles.
    function MatchH.ChainDrivenToBar(barId, dim)
        if not barId then
            return false
        end
        local saved
        if dim == "width" then
            saved = MatchH.GetWidthMatchDB()
        elseif dim == "height" then
            saved = MatchH.GetHeightMatchDB()
        else
            return false
        end
        local abKeys = CludesUI._abBarKeys
        local seen = {}
        local current = barId
        while current do
            if current:sub(1, 4) == "CDM_" then
                return true
            end
            if abKeys and abKeys[current] and current ~= barId then
                return true
            end
            if not saved or seen[current] then
                return false
            end
            seen[current] = true
            current = saved[current]
        end
        return false
    end

    function MatchH.SetWidthMatch(childBarKey, targetBarKey)
        local saved = MatchH.GetWidthMatchDB()
        if not saved then
            return
        end
        if MatchH.WouldCreateCycle(saved, childBarKey, targetBarKey) then
            -- Break the cycle: clear the link that targetKey has, then set ours
            saved[targetBarKey] = nil
            MatchH.SetMatchExtra("w", targetBarKey, nil)
        end
        -- A new match starts at +0.
        if saved[childBarKey] ~= targetBarKey then
            MatchH.SetMatchExtra("w", childBarKey, nil)
        end
        saved[childBarKey] = targetBarKey
    end

    function MatchH.SetHeightMatch(childBarKey, targetBarKey)
        local saved = MatchH.GetHeightMatchDB()
        if not saved then
            return
        end
        if MatchH.WouldCreateCycle(saved, childBarKey, targetBarKey) then
            saved[targetBarKey] = nil
            MatchH.SetMatchExtra("h", targetBarKey, nil)
        end
        if saved[childBarKey] ~= targetBarKey then
            MatchH.SetMatchExtra("h", childBarKey, nil)
        end
        saved[childBarKey] = targetBarKey
    end

    function MatchH.ClearWidthMatch(childBarKey)
        local saved = MatchH.GetWidthMatchDB()
        if not saved then
            return
        end
        -- Persist current width so "0 = match parent" defaults don't revert on reload
        -- (elem.setWidth saves to its own DB); pixel-snapped like every match apply, else an off-grid raw GetWidth propagates through setters/harvests.
        local element = registeredElements[childBarKey]
        if element and element.setWidth then
            local widget = LM.GetBarFrame(childBarKey)
            if widget then
                local curW = widget:GetWidth()
                if curW and curW > 0 then
                    local PPm = CludesUI and CludesUI.PP
                    if PPm and PPm.SnapForES then
                        curW = PPm.SnapForES(curW, widget:GetEffectiveScale())
                    end
                    pcall(element.setWidth, childBarKey, curW)
                end
            end
        end
        saved[childBarKey] = nil
        MatchH.SetMatchExtra("w", childBarKey, nil)
    end

    function MatchH.ClearHeightMatch(childBarKey)
        local saved = MatchH.GetHeightMatchDB()
        if not saved then
            return
        end
        local element = registeredElements[childBarKey]
        if element and element.setHeight then
            local widget = LM.GetBarFrame(childBarKey)
            if widget then
                local curH = widget:GetHeight()
                if curH and curH > 0 then
                    local PPm = CludesUI and CludesUI.PP
                    if PPm and PPm.SnapForES then
                        curH = PPm.SnapForES(curH, widget:GetEffectiveScale())
                    end
                    pcall(element.setHeight, childBarKey, curH)
                end
            end
        end
        saved[childBarKey] = nil
        MatchH.SetMatchExtra("h", childBarKey, nil)
    end

    -------------------------------------------------------------------------------
    --  Public API: query width/height match state from any addon
    -------------------------------------------------------------------------------
    function CludesUI.GetWidthMatchTarget(barId)
        local saved = MatchH.GetWidthMatchDB()
        return saved and saved[barId] or nil
    end

    function CludesUI.GetHeightMatchTarget(barId)
        local saved = MatchH.GetHeightMatchDB()
        return saved and saved[barId] or nil
    end

    -- Returns (disabled_fn, tooltip_fn, rawTooltip) for width/height sliders, composing
    -- with an optional existing disabled/tooltip so both conditions work.
    -- rawTooltip=true tells the widget system to skip DisabledTooltip wrapping.
    function CludesUI.MatchGuard(barId, dim, existingDisabled, existingTooltip)
        local isWidth = (dim == "Width" or dim == "width")
        local getFn = isWidth and CludesUI.GetWidthMatchTarget or CludesUI.GetHeightMatchTarget
        local disabled = function()
            if getFn(barId) then
                return true
            end
            if existingDisabled then
                return existingDisabled()
            end
            return false
        end
        local tooltip = function()
            local target = getFn(barId)
            if target then
                local name = (CludesUI.GetBarLabel and CludesUI.GetBarLabel(target)) or target
                return isWidth
                        and CludesUI.Lf(
                            "Width matched to %1$s. Unmatch in Layout Mode to edit.",
                            CludesUI.L(name)
                        )
                    or CludesUI.Lf(
                        "Height matched to %1$s. Unmatch in Layout Mode to edit.",
                        CludesUI.L(name)
                    )
            end
            if existingTooltip then
                return type(existingTooltip) == "function" and existingTooltip() or existingTooltip
            end
            return ""
        end
        local rawTooltip = function()
            return getFn(barId) ~= nil
        end
        return disabled, tooltip, rawTooltip
    end

    -------------------------------------------------------------------------------
    --  PruneStaleLinks -- removes all anchor/match links for a key, as child AND
    --  as target. Call on unregister so nothing points to a ghost key.
    -------------------------------------------------------------------------------
    local function PruneStaleLinks(barKey)
        if not CludesUIDB then
            return
        end

        -- Anchors: key as child
        local anchorMap = CludesUIDB.unlockAnchors
        if anchorMap then
            anchorMap[barKey] = nil
            -- key as target -- scan all children
            for childBarKey, details in pairs(anchorMap) do
                if details and details.target == barKey then
                    anchorMap[childBarKey] = nil
                end
            end
        end

        -- Match extras go with the links dropped below: the key's own, and those of
        -- the children matched to it (read before those links are gone).
        local wx = CludesUIDB.unlockWidthMatchExtra
        if wx then
            local wmL = CludesUIDB.unlockWidthMatch
            wx[barKey] = nil
            for childBarKey in pairs(wx) do
                if wmL and wmL[childBarKey] == barKey then
                    wx[childBarKey] = nil
                end
            end
        end
        local hx = CludesUIDB.unlockHeightMatchExtra
        if hx then
            local hmL = CludesUIDB.unlockHeightMatch
            hx[barKey] = nil
            for childBarKey in pairs(hx) do
                if hmL and hmL[childBarKey] == barKey then
                    hx[childBarKey] = nil
                end
            end
        end

        -- Width matches: key as child or target
        local wm = CludesUIDB.unlockWidthMatch
        if wm then
            wm[barKey] = nil
            for childBarKey, targetBarKey in pairs(wm) do
                if targetBarKey == barKey then
                    wm[childBarKey] = nil
                end
            end
        end

        -- Height matches: key as child or target
        local hm = CludesUIDB.unlockHeightMatch
        if hm then
            hm[barKey] = nil
            for childBarKey, targetBarKey in pairs(hm) do
                if targetBarKey == barKey then
                    hm[childBarKey] = nil
                end
            end
        end
    end
    CludesUI.PruneStaleLinks = PruneStaleLinks

    -- Override UnregisterUnlockElement so cleanup runs on removal (e.g. a deleted CDM bar).
    function CludesUI:UnregisterUnlockElement(barKey)
        self._unlockRegisteredElements[barKey] = nil
        self._unlockRegistrationDirty = true
        PruneStaleLinks(barKey)
    end

    -------------------------------------------------------------------------------
    --  ShiftIndexedAnchorKeys -- re-keys anchor/size-match links for an index-keyed
    --  element family after a slot is removed (deleting Tracking Bar 2 of 4 shifts
    --  TBB_3->TBB_2, TBB_4->TBB_3, mirroring the addon's own re-keyed position
    --  store). Links pointing AT the removed key are severed (child keeps its
    --  stored position); the removed key's own links go with it.
    -------------------------------------------------------------------------------
    function CludesUI.ShiftIndexedAnchorKeys(prefixText, removedIdx, oldCount)
        if not CludesUIDB then
            return
        end
        local removedKey = prefixText .. removedIdx
        local plen = #prefixText

        -- Returns the shifted key for keys above the removed index, else nil.
        local function ShiftedKey(barKey)
            if type(barKey) ~= "string" or barKey:sub(1, plen) ~= prefixText then
                return nil
            end
            local idx = tonumber(barKey:sub(plen + 1))
            if not idx or idx <= removedIdx or idx > oldCount then
                return nil
            end
            return prefixText .. (idx - 1)
        end

        local anchorMap = CludesUIDB.unlockAnchors
        if anchorMap then
            -- Sever children anchored to the removed key; retarget higher indexes.
            for childBarKey, details in pairs(anchorMap) do
                if details and details.target == removedKey then
                    anchorMap[childBarKey] = nil
                elseif details then
                    local nt = ShiftedKey(details.target)
                    if nt then
                        details.target = nt
                    end
                end
            end
            -- Shift child-role keys down one slot.
            anchorMap[removedKey] = nil
            for idx = removedIdx + 1, oldCount do
                local oldK, newK = prefixText .. idx, prefixText .. (idx - 1)
                anchorMap[newK] = anchorMap[oldK]
                anchorMap[oldK] = nil
            end
        end

        local function ShiftMatchStore(storage)
            if not storage then
                return
            end
            for childBarKey, targetBarKey in pairs(storage) do
                if targetBarKey == removedKey then
                    storage[childBarKey] = nil
                else
                    local nt = ShiftedKey(targetBarKey)
                    if nt then
                        storage[childBarKey] = nt
                    end
                end
            end
            storage[removedKey] = nil
            for idx = removedIdx + 1, oldCount do
                local oldK, newK = prefixText .. idx, prefixText .. (idx - 1)
                storage[newK] = storage[oldK]
                storage[oldK] = nil
            end
        end
        -- Match extras (child key -> px) follow their links: a child whose link is
        -- severed (it pointed at the removed key) loses its extra, read before the
        -- link stores shift below; the rest re-key like the links (ShiftedKey never
        -- retargets a number, so only the child-role keys move).
        local function DropSeveredExtras(links, extras)
            if not (links and extras) then
                return
            end
            for childBarKey, targetBarKey in pairs(links) do
                if targetBarKey == removedKey then
                    extras[childBarKey] = nil
                end
            end
        end
        DropSeveredExtras(CludesUIDB.unlockWidthMatch, CludesUIDB.unlockWidthMatchExtra)
        DropSeveredExtras(CludesUIDB.unlockHeightMatch, CludesUIDB.unlockHeightMatchExtra)
        ShiftMatchStore(CludesUIDB.unlockWidthMatchExtra)
        ShiftMatchStore(CludesUIDB.unlockHeightMatchExtra)
        ShiftMatchStore(CludesUIDB.unlockWidthMatch)
        ShiftMatchStore(CludesUIDB.unlockHeightMatch)
    end

    -- Validate stored relationships against registered elements. Runs on every
    -- unlock-mode open: drops links whose endpoint is gone for good, and size
    -- matches a noResize endpoint cannot use (see MatchUnusable).
    local function ValidateStoredLinks()
        if not CludesUIDB then
            return
        end
        local elems = CludesUI._unlockRegisteredElements

        -- While a spec-override unlock LAYER is live, never prune a missing endpoint:
        -- elements may exist for only some specs, and the transition harvest would bank
        -- the prune into the layer, destroying data other specs expect.
        local activeFn = CludesUI.SpecOverrides_UnlockActive
        local function OverrideProtected()
            return (activeFn and activeFn() ~= nil) and true or false
        end

        -- Tracking Bar keys are spec-scoped (registry holds only the current spec's
        -- bars), so a missing TBB_ key may exist for another spec; never prune over one
        -- (bar deletion re-keys/severs via ShiftIndexedAnchorKeys). Global tracking bar
        -- groups (TBBG_) live in a per-profile registry too and may come back.
        local function MissingForGood(barKey)
            if barKey ~= nil and elems[barKey] then
                return false
            end
            if type(barKey) == "string" and barKey:find("^TBB_%d+$") then
                return false
            end
            if type(barKey) == "string" and barKey:find("^TBBG_") then
                return false
            end
            return true
        end

        -- A unit frame key missing from the registry is switched off by a unit
        -- setting (Frame Source, Enable) or the module being off, never deleted. A
        -- link whose CHILD is one stays for when it comes back (nothing places a
        -- missing child) as long as its other end is live or another such key (a
        -- cast bar and its frame). A live child anchored or matched to one is still
        -- freed, so it is never left following a frame that is not there.
        local resolveFolder = CludesUI.ResolveKeyToFolder
        local function ufKey(barKey)
            return resolveFolder ~= nil and resolveFolder(barKey) == "CludesUIUnitFrames"
        end
        -- WoW Forever never builds the House Favor bar or the Battle Res and
        -- Bloodlust icons: a link whose CHILD is one of them stays for the other
        -- client on the same terms (its other end live, a unit frame key, or
        -- another such key).
        local function clientAbsent(barKey)
            return CludesUI.IS_FOREVER == true
                and (barKey == "FavorBar" or barKey == "CUI_BattleRes" or barKey == "CUI_Bloodlust")
        end
        local function LinkGone(childBarKey, targetBarKey)
            local childGone, targetGone = MissingForGood(childBarKey), MissingForGood(targetBarKey)
            if not (childGone or targetGone) then
                return false
            end
            if
                childGone
                and (ufKey(childBarKey) or clientAbsent(childBarKey))
                and (not targetGone or ufKey(targetBarKey) or clientAbsent(targetBarKey))
            then
                return false
            end
            return true
        end

        local anchorMap = CludesUIDB.unlockAnchors
        if anchorMap then
            for childBarKey, details in pairs(anchorMap) do
                local cElem = elems[childBarKey]
                if cElem and cElem.ownsPosition then
                    -- A link on an element that places itself (main chat) never
                    -- takes effect, yet the passes that walk the whole store still
                    -- see it: a line to its old target, and a loop that pulls back
                    -- an element linked to it. Dropped on every spec.
                    anchorMap[childBarKey] = nil
                elseif LinkGone(childBarKey, details and details.target) and not OverrideProtected(childBarKey) then
                    anchorMap[childBarKey] = nil
                elseif
                    details
                    and details.edge
                    and details.edge.key
                    and LinkGone(childBarKey, details.edge.key)
                    and not OverrideProtected(childBarKey)
                then
                    -- Unknown cross-axis edge (a string from a build without this
                    -- feature): drop the extra, keep the link itself.
                    details.edge = nil
                end
            end
        end

        -- A size match a noResize endpoint cannot use: a child that cannot be sized
        -- (unless it may match as a source) or a target with no size to follow.
        -- sizeFixedByLook endpoints are only size-locked by the current look
        -- (Blizzard Style unit frames), so their links stay for the other look.
        local function MatchUnusable(childBarKey, targetBarKey)
            local c, t = elems[childBarKey], elems[targetBarKey]
            if not (c and t) then
                return false
            end
            if c.noResize and not c.allowMatchSource and not c.sizeFixedByLook then
                return true
            end
            if t.noResize and not t.sizeFixedByLook then
                return true
            end
            return false
        end

        local wm = CludesUIDB.unlockWidthMatch
        if wm then
            for childBarKey, targetBarKey in pairs(wm) do
                if LinkGone(childBarKey, targetBarKey) and not OverrideProtected(childBarKey) then
                    wm[childBarKey] = nil
                elseif MatchUnusable(childBarKey, targetBarKey) then
                    wm[childBarKey] = nil
                end
            end
        end

        local hm = CludesUIDB.unlockHeightMatch
        if hm then
            for childBarKey, targetBarKey in pairs(hm) do
                if LinkGone(childBarKey, targetBarKey) and not OverrideProtected(childBarKey) then
                    hm[childBarKey] = nil
                elseif MatchUnusable(childBarKey, targetBarKey) then
                    hm[childBarKey] = nil
                end
            end
        end

        -- A match extra is read only while its link exists: drop every extra whose
        -- link is gone, so orphans never ride into snapshots and profiles.
        local wx = CludesUIDB.unlockWidthMatchExtra
        if wx then
            for childBarKey in pairs(wx) do
                if not (wm and wm[childBarKey]) then
                    wx[childBarKey] = nil
                end
            end
        end
        local hx = CludesUIDB.unlockHeightMatchExtra
        if hx then
            for childBarKey in pairs(hx) do
                if not (hm and hm[childBarKey]) then
                    hx[childBarKey] = nil
                end
            end
        end
    end

    -- Apply width/height match: sync source size from target. _propagatingMatch
    -- prevents re-entrant loops (setWidth -> OnSizeChanged -> NotifyElementResized ->
    -- PropagateWidthMatch); exposed so child addons' setWidth can detect it.
    local _propagatingMatch = false
    CludesUI._propagatingMatch = false

    function MatchH.ApplyWidthMatch(sourceBarKey, targetBarKey)
        local targetElement = registeredElements[targetBarKey]
        local targetFrame = LM.GetBarFrame(targetBarKey)
        local targetWidth
        if targetElement and targetElement.getSize then
            targetWidth = targetElement.getSize(targetBarKey)
        elseif targetFrame then
            targetWidth = targetFrame:GetWidth()
        end
        -- Chrome drawn outside the target's own rect (getMatchPad, e.g. a classic
        -- resource bar's frame): the match lines up with what is on screen.
        if targetWidth and targetElement and targetElement.getMatchPad then
            local padW = targetElement.getMatchPad(targetBarKey)
            if padW and padW > 0 then
                targetWidth = targetWidth + padW
            end
        end
        -- A width that is not a real number (a frame not laid out yet can read NaN)
        -- skips the match: WoW Forever errors on dividing one.
        if targetWidth and CludesUI.PP.IsNum(targetWidth) and targetWidth > 0 then
            local rawW, conv = targetWidth, 1
            -- Snap to the physical pixel grid with round-to-nearest: PP.Scale
            -- truncates and drops a pixel on float boundary values; SnapForES uses
            -- floor(x/px + 0.5), which is safe.
            local PPm = CludesUI and CludesUI.PP
            if PPm and PPm.SnapForES and targetFrame then
                targetWidth = PPm.SnapForES(targetWidth, targetFrame:GetEffectiveScale())
            else
                targetWidth = floor(targetWidth + 0.5)
            end
            -- Convert target width to source's coordinate space if scales differ
            local sourceBar = LM.GetBarFrame(sourceBarKey)
            if targetFrame and sourceBar then
                local tES = targetFrame:GetEffectiveScale()
                local sES = sourceBar:GetEffectiveScale()
                if math.abs(tES - sES) > 0.001 then
                    targetWidth = targetWidth * tES / sES
                    conv = tES / sES
                end
            end
            local sourceElement = registeredElements[sourceBarKey]
            if sourceElement and sourceElement.setWidth then
                -- The source's own outside chrome comes off the width it is set
                -- to, so what it draws is what matches. Taken off the unsnapped
                -- width and snapped once: snapping before the subtraction rounds a
                -- half-pixel pad twice, leaving two bars with the same pad a pixel
                -- apart.
                if sourceElement.getMatchPad then
                    local padW = sourceElement.getMatchPad(sourceBarKey)
                    if padW and padW > 0 then
                        targetWidth = rawW * conv - padW
                        if PPm and PPm.SnapForES and sourceBar then
                            targetWidth = PPm.SnapForES(targetWidth, sourceBar:GetEffectiveScale())
                        else
                            targetWidth = floor(targetWidth + 0.5)
                        end
                        targetWidth = math.max(1, targetWidth)
                    end
                end
                -- The match's Extra Width (whole pixels at the source's scale). targetW
                -- sits on the source's pixel grid here, so whole pixels keep it there
                -- with no second rounding. nil = no extra: nothing changes.
                local ex = CludesUI.GetMatchExtra("w", sourceBarKey)
                if ex then
                    local es = sourceBar and sourceBar:GetEffectiveScale()
                    local one = (PPm and PPm.perfect and es and es > 0) and (PPm.perfect / es) or 1
                    targetWidth = math.max(1, targetWidth + ex * one)
                end
                if LM.isUnlocked then
                    local scrollBar = LM.GetBarFrame(sourceBarKey)
                    local savedAlpha = scrollBar and CludesUI._GetFFD(scrollBar).restoreAlpha
                    if scrollBar and not savedAlpha then
                        CludesUI._UnlockSetBarAlpha(scrollBar, 0)
                    end
                    _propagatingMatch = true
                    CludesUI._propagatingMatch = true
                    pcall(sourceElement.setWidth, sourceBarKey, targetWidth)
                    _propagatingMatch = false
                    CludesUI._propagatingMatch = false
                    CludesUI.RecenterBarAnchor(sourceBarKey)
                    if scrollBar and not savedAlpha then
                        C_Timer.After(0, function()
                            CludesUI._UnlockSetBarAlpha(scrollBar, 1)
                        end)
                    end
                    local handle = movers[sourceBarKey]
                    if handle then
                        handle:SyncSize()
                    end
                else
                    _propagatingMatch = true
                    CludesUI._propagatingMatch = true
                    pcall(sourceElement.setWidth, sourceBarKey, targetWidth)
                    _propagatingMatch = false
                    CludesUI._propagatingMatch = false
                    if sourceElement.noInitHook then
                        -- Self-positioning: its own authority, never the stored CENTER.
                        if sourceElement.applyPosition and not CludesUI.IsUnlockAnchored(sourceBarKey) then
                            pcall(sourceElement.applyPosition, sourceBarKey)
                        end
                    elseif sourceElement.loadPosition then
                        local place = sourceElement.loadPosition(sourceBarKey)
                        if place and place.point == "CENTER" and place.relPoint == "CENTER" then
                            LM.ApplyCenterPosition(sourceBarKey, place)
                        end
                    end
                end
            end
        end
    end

    function MatchH.ApplyHeightMatch(sourceBarKey, targetBarKey)
        local targetElement = registeredElements[targetBarKey]
        local targetFrame = LM.GetBarFrame(targetBarKey)
        local _, targetHeight
        if targetElement and targetElement.getSize then
            _, targetHeight = targetElement.getSize(targetBarKey)
        elseif targetFrame then
            targetHeight = targetFrame:GetHeight()
        end
        -- Outside chrome on the target (getMatchPad), as in ApplyWidthMatch.
        if targetHeight and targetElement and targetElement.getMatchPad then
            local _, ph = targetElement.getMatchPad(targetBarKey)
            if ph and ph > 0 then
                targetHeight = targetHeight + ph
            end
        end
        if targetHeight and CludesUI.PP.IsNum(targetHeight) and targetHeight > 0 then
            local rawH, conv = targetHeight, 1
            local PPm = CludesUI and CludesUI.PP
            if PPm and PPm.SnapForES and targetFrame then
                targetHeight = PPm.SnapForES(targetHeight, targetFrame:GetEffectiveScale())
            else
                targetHeight = floor(targetHeight + 0.5)
            end
            -- Cross-scale conversion, mirroring ApplyWidthMatch: matched height is a
            -- coordinate in the TARGET's effective scale; a source at another scale
            -- would persist a physically wrong height into its module config.
            local sourceBar = LM.GetBarFrame(sourceBarKey)
            if targetFrame and sourceBar then
                local tES = targetFrame:GetEffectiveScale()
                local sES = sourceBar:GetEffectiveScale()
                if math.abs(tES - sES) > 0.001 then
                    targetHeight = targetHeight * tES / sES
                    conv = tES / sES
                end
            end
            local sourceElement = registeredElements[sourceBarKey]
            if sourceElement and sourceElement.setHeight then
                -- The source's own outside chrome comes off the unsnapped height,
                -- snapped once, as in ApplyWidthMatch.
                if sourceElement.getMatchPad then
                    local _, ph = sourceElement.getMatchPad(sourceBarKey)
                    if ph and ph > 0 then
                        targetHeight = rawH * conv - ph
                        if PPm and PPm.SnapForES and sourceBar then
                            targetHeight = PPm.SnapForES(targetHeight, sourceBar:GetEffectiveScale())
                        else
                            targetHeight = floor(targetHeight + 0.5)
                        end
                        targetHeight = math.max(1, targetHeight)
                    end
                end
                -- The match's Extra Height, as the Extra Width in ApplyWidthMatch.
                local ex = CludesUI.GetMatchExtra("h", sourceBarKey)
                if ex then
                    local es = sourceBar and sourceBar:GetEffectiveScale()
                    local one = (PPm and PPm.perfect and es and es > 0) and (PPm.perfect / es) or 1
                    targetHeight = math.max(1, targetHeight + ex * one)
                end
                if LM.isUnlocked then
                    local scrollBar = LM.GetBarFrame(sourceBarKey)
                    local savedAlpha = scrollBar and CludesUI._GetFFD(scrollBar).restoreAlpha
                    if scrollBar and not savedAlpha then
                        CludesUI._UnlockSetBarAlpha(scrollBar, 0)
                    end
                    _propagatingMatch = true
                    CludesUI._propagatingMatch = true
                    pcall(sourceElement.setHeight, sourceBarKey, targetHeight)
                    _propagatingMatch = false
                    CludesUI._propagatingMatch = false
                    CludesUI.RecenterBarAnchor(sourceBarKey)
                    if scrollBar and not savedAlpha then
                        C_Timer.After(0, function()
                            CludesUI._UnlockSetBarAlpha(scrollBar, 1)
                        end)
                    end
                    local handle = movers[sourceBarKey]
                    if handle then
                        handle:SyncSize()
                    end
                else
                    _propagatingMatch = true
                    CludesUI._propagatingMatch = true
                    pcall(sourceElement.setHeight, sourceBarKey, targetHeight)
                    _propagatingMatch = false
                    CludesUI._propagatingMatch = false
                    if sourceElement.noInitHook then
                        -- Self-positioning: its own authority, never the stored CENTER.
                        if sourceElement.applyPosition and not CludesUI.IsUnlockAnchored(sourceBarKey) then
                            pcall(sourceElement.applyPosition, sourceBarKey)
                        end
                    elseif sourceElement.loadPosition then
                        local place = sourceElement.loadPosition(sourceBarKey)
                        if place and place.point == "CENTER" and place.relPoint == "CENTER" then
                            LM.ApplyCenterPosition(sourceBarKey, place)
                        end
                    end
                end
            end
        end
    end

    -- Pending anchor propagation keys -- batched into a single deferred frame
    LM._pendingAnchorKeys = {}
    local _anchorBatchScheduled = false

    local function ScheduleAnchorBatch()
        if _anchorBatchScheduled then
            return
        end
        _anchorBatchScheduled = true
        C_Timer.After(0, function()
            _anchorBatchScheduled = false
            if LM.isUnlocked then
                return
            end -- unlock mode handles its own saves
            -- Runs only outside a session or while combat hides one, so its
            -- re-placements never mark the session (noMark below).
            local keyList = LM._pendingAnchorKeys
            LM._pendingAnchorKeys = {}
            -- Profile swap: skip AB bars entirely (LayoutBar already positioned them from
            -- the new profile; stale resize events would move them wrong). CDM bars pass through (need post-settle).
            local abSkip = CludesUI._abAnchorSuppressed and CludesUI._abBarKeys
            for key, dim in pairs(keyList) do
                if abSkip and abSkip[key] then
                -- skip: AB bar during profile swap
                else
                    -- If this element is itself anchored, re-apply its own position
                    -- first: it resized and must reposition relative to its target.
                    local anchorDB = GetAnchorDB()
                    if anchorDB then
                        local ownInfo = anchorDB[key]
                        if ownInfo and ownInfo.target then
                            -- Skip AB growth bars: LayoutBar/applyPos owns their position;
                            -- reapplying from a stale offset yields the wrong edge and visible drift.
                            local isAB = CludesUI._abBarKeys and CludesUI._abBarKeys[key]
                            if not isAB or ownInfo.mode == "POINT" then
                                LM.ApplyAnchorPosition(key, ownInfo.target, ownInfo.side, true)
                            end
                        end
                        -- An alias key (global tracking bar group riding this bar's hooks) may itself be anchored: re-apply on a shared resize.
                        local aliasK = CludesUI._unlockKeyAliases and CludesUI._unlockKeyAliases[key]
                        local aliasInfo = aliasK and anchorDB[aliasK]
                        if aliasInfo and aliasInfo.target then
                            LM.ApplyAnchorPosition(aliasK, aliasInfo.target, aliasInfo.side, true)
                        end
                    end
                    -- Propagate with axis filter (nil = all axes)
                    local propagateAxis = (dim == "all") and nil or dim
                    LM.PropagateAnchorChain(key, nil, propagateAxis)
                end -- abSkip else
            end
            -- No persistence here: only Save & Exit (CommitPositions) writes the DB; the chain just repositioned in-place.
            wipe(pendingPositions)
        end)
    end

    -------------------------------------------------------------------------------
    --  One-time follow-baseline migration ("bless the pin"): anchored grow-direction  -- cui-style: allow comment-budget
    --  bars saved before follow-baseline capture have a savedEdge but no tgt*
    --  baseline, so their follow delta stays 0 and they can't track a resizing
    --  target. The baseline can't be reconstructed from ai.offsetX/Y (those drift
    --  from layout maintenance and are non-authoritative for grow bars -- why
    --  savedEdge is the authority). Instead, once per bar (tgt* presence = the
    --  migrated flag) at a quiescent settle, pair the UNTOUCHED savedEdge with the
    --  target's live settled geometry: delta is 0 at that instant by construction,
    --  so the bar doesn't move, and every future resize/login follows from the
    --  blessed pair. Skipped in combat/unlock mode (retries next settle).
    -------------------------------------------------------------------------------
    do
        local function MigrateOne(childBarKey, details)
            local savedEdge
            if childBarKey:sub(1, 4) == "CDM_" then
                local tbl = CludesUI._cdmBarPositions
                savedEdge = tbl and tbl[childBarKey:sub(5)]
            elseif CludesUI._abBarKeys and CludesUI._abBarKeys[childBarKey] then
                local tbl = CludesUI._abBarPositions
                savedEdge = tbl and tbl[childBarKey]
            end
            if not savedEdge then
                return
            end
            -- Presence of a baseline is the migrated flag -- never touch again.
            if savedEdge.tgtx ~= nil or savedEdge.tgty ~= nil then
                return
            end
            local growDir = GetBarGrowDirActual(childBarKey)
            if not growDir or growDir == "CENTER" then
                return
            end
            local targetFrame = LM.GetBarFrame(details.target)
            if not targetFrame or not targetFrame:GetLeft() then
                return
            end
            -- A clamp-held target is not at its saved spot: pairing it would make the
            -- child jump once the target is released. Retries next settle.
            if CludesUI._RectHeldByClamp(details.target, targetFrame) then
                return
            end
            -- UIParent-space target geometry, computed like ApplyAnchorPosition's tL/tR/tT/tB so the baseline is comparable.
            local uiScale = UIParent:GetEffectiveScale()
            local tS = targetFrame:GetEffectiveScale()
            local tL = (targetFrame:GetLeft() or 0) * tS / uiScale
            local tR = (targetFrame:GetRight() or 0) * tS / uiScale
            local tT = (targetFrame:GetTop() or 0) * tS / uiScale
            local tB = (targetFrame:GetBottom() or 0) * tS / uiScale
            savedEdge.tgtx = (tL + tR) / 2
            savedEdge.tgty = (tT + tB) / 2
            savedEdge.tgtL = tL
            savedEdge.tgtR = tR
            savedEdge.tgtT = tT
            savedEdge.tgtB = tB
            -- Blessed baselines need no override write-back: layer harvest banks the live stores wholesale at every spec/profile transition.
        end

        function CludesUI._MigrateAnchorFollowBaselines()
            if LM.isUnlocked or InCombatLockdown() then
                return
            end
            local anchorDB = GetAnchorDB()
            if not anchorDB then
                return
            end
            for childBarKey, details in pairs(anchorDB) do
                if
                    details.target
                    and details.mode ~= "POINT"
                    and (
                        childBarKey:sub(1, 4) == "CDM_"
                        or (CludesUI._abBarKeys and CludesUI._abBarKeys[childBarKey])
                    )
                then
                    pcall(MigrateOne, childBarKey, details)
                end
            end
        end
    end

    -- Settle re-apply debounce: anchored CDM bars and their targets resize several times
    -- on login (icon population, 1/3/6s refresh ladder, trinket retries) with no
    -- reliable "done" signal. Rather than guess a delay, watch for QUIESCENCE: every
    -- real resize (NotifyElementResized) restarts this cancelable timer, and only a
    -- full quiet window forces ONE full anchor re-apply against the final chain. The
    -- 0.25s window must exceed the 0.2s resize throttle so a burst of throttled reanchors keeps the timer alive instead of mis-firing between them.
    function CludesUI.ScheduleSettleReapply()
        if LM.isUnlocked then
            return
        end -- unlock owns positioning
        if CludesUI._settleReapplyInProgress then
            return
        end -- never re-arm from our own pass
        -- The in-progress flag only covers the SYNCHRONOUS pass; everything it spawns
        -- (anchor batches, SetPoint move checks) is After(0) deferred and lands after the
        -- flag clears. If the forced re-apply isn't pixel-stable (1 physical px snap
        -- deltas exceed the 0.5 UI-unit epsilon at low UI scale), that tail re-arms the
        -- timer forever -- a permanent ~5Hz re-apply burning the client in combat.
        -- Suppress re-arms long enough to swallow the deferred tail; a real disturbance
        -- inside the window only loses this belt-and-braces pass, already handled by notify/batch.
        local su = CludesUI._settleSuppressUntil
        if su and GetTime() < su then
            return
        end
        if CludesUI._settleTimer then
            CludesUI._settleTimer:Cancel()
        end
        CludesUI._settleTimer = C_Timer.NewTimer(0.25, function()
            CludesUI._settleTimer = nil
            if LM.isUnlocked then
                return
            end
            -- Chain settled: absolute pin may now pick up the target-follow delta.
            -- Flipping only after true quiescence guarantees the target is at its
            -- settled position, so the first follow-aware pass computes a ~0 delta on a
            -- same-spec login and the pin->follow handoff shows no jump.
            CludesUI._anchorFollowReady = true
            -- One-shot follow-baseline migration for anchored grow bars; no-op once every candidate has its tgt* baseline.
            if CludesUI._MigrateAnchorFollowBaselines then
                pcall(CludesUI._MigrateAnchorFollowBaselines)
            end
            -- Re-pull every width/height MATCH before the anchor pass. A match child  -- cui-style: allow comment-budget
            -- is corrected only by a full pass or by its target's own resize notify,
            -- and a spec swap ends with resizes that reach neither: the authoritative
            -- passes (OnSpecSwitchComplete, CDM's reanchor pass) run before the CDM
            -- retry ladder re-lays out the bar, and a size change landing inside the
            -- 50ms notify throttle is dropped outright with nothing to re-run it. The
            -- child then stays pinned to the size its target held mid-rebuild until a
            -- reload -- the power bar <- Essential Cooldowns mismatch. Quiescence
            -- means every target is at its final size, so this is the same correction
            -- a reload performs. Gated on a non-empty store: no matches, no work.
            local wdb = CludesUIDB and CludesUIDB.unlockWidthMatch
            local hdb = CludesUIDB and CludesUIDB.unlockHeightMatch
            if ((wdb and next(wdb)) or (hdb and next(hdb))) and CludesUI.ApplyAllWidthHeightMatches then
                CludesUI._settleReapplyInProgress = true
                CludesUI._settleSuppressUntil = GetTime() + 0.75
                pcall(CludesUI.ApplyAllWidthHeightMatches)
                CludesUI._settleReapplyInProgress = false
            end
            if CludesUI.ReapplyAllUnlockAnchorsForced then
                CludesUI._settleReapplyInProgress = true
                CludesUI._settleSuppressUntil = GetTime() + 0.75
                pcall(CludesUI.ReapplyAllUnlockAnchorsForced)
                CludesUI._settleReapplyInProgress = false
            end
        end)
    end

    function CludesUI.PropagateWidthMatch(barKey)
        local saved = MatchH.GetWidthMatchDB()
        if not saved then
            return
        end
        -- Push width to elements matching this key, then recurse so chained
        -- matches (A -> B -> C) propagate fully.
        local seen = { [barKey] = true }
        local function pushChildren(parentKey)
            for childBarKey, tKey in pairs(saved) do
                if tKey == parentKey and not seen[childBarKey] then
                    seen[childBarKey] = true
                    MatchH.ApplyWidthMatch(childBarKey, parentKey)
                    LM._pendingAnchorKeys[childBarKey] = "width"
                    pushChildren(childBarKey)
                end
            end
        end
        pushChildren(barKey)
        ScheduleAnchorBatch()
    end

    function CludesUI.PropagateHeightMatch(barKey)
        local saved = MatchH.GetHeightMatchDB()
        if not saved then
            return
        end
        local seen = { [barKey] = true }
        local function pushChildren(parentKey)
            for childBarKey, tKey in pairs(saved) do
                if tKey == parentKey and not seen[childBarKey] then
                    seen[childBarKey] = true
                    MatchH.ApplyHeightMatch(childBarKey, parentKey)
                    LM._pendingAnchorKeys[childBarKey] = "height"
                    pushChildren(childBarKey)
                end
            end
        end
        pushChildren(barKey)
        ScheduleAnchorBatch()
    end

    -------------------------------------------------------------------------------
    --  Centralized resize notification: CludesUI.NotifyElementResized(key), called
    --  after changing a frame's size, propagates width/height matches and anchor
    --  chains. OnSizeChanged hooks on registered elements call it automatically.
    -------------------------------------------------------------------------------
    local _resizeNotifyThrottle = {} -- [key] = GetTime() of last notify
    local _resizeLastSize = {} -- [key] = { w = ..., h = ... }
    local RESIZE_THROTTLE_SEC = 0.05 -- ignore rapid-fire size changes within 50ms
    -- Trailing re-run bookkeeping (this file is at the 200-local cap, so it lives on
    -- CludesUI rather than in locals). pending[key] = a re-run is queued;
    -- at[key] = when the last one ran, floored to one per 0.5s. That floor is the
    -- hard spin guard: an element whose re-apply is not pixel-stable (1 physical px
    -- exceeds the 0.5 UI-unit epsilon at low UI scale) would otherwise re-arm a
    -- trailing run every 50ms forever. It costs no real correction, since the tail of
    -- a same-frame burst always lands within the first throttle window.
    CludesUI._resizeTrail = { pending = {}, at = {} }

    -- Set by LayoutBar (action bars) to suppress position re-application during
    -- SetSize; LayoutBar handles its own edge re-anchoring.
    CludesUI._layoutBarResizing = nil

    function CludesUI.NotifyElementResized(barKey)
        if LM.isUnlocked then
            return
        end -- unlock mode owns positioning
        -- Skip if we're inside a width/height match propagation to avoid loops:
        -- setWidth/setHeight -> rebuild -> OnSizeChanged -> NotifyElementResized
        if _propagatingMatch then
            return
        end
        -- When LayoutBar handles positioning (custom grow directions), skip only the
        -- position re-apply below; match propagation and anchor chains still run.
        local layoutBarHandled = (CludesUI._layoutBarResizing == barKey)
        -- Suppression scope (spec swap / zone transition): CDM bar icon counts
        -- fluctuate in these windows as Blizzard recycles viewer frames, and a
        -- transient empty width propagated to a width-MATCHED sibling corrupts it until
        -- re-matched. Anchor propagation has no such risk (worst case a child
        -- re-anchors twice), so suppress ONLY the width/height match block below,
        -- never the anchor cascade -- else a spec-swap resize (Class Resource shrinking
        -- 1px on the new pip count) strands anchored children with no event to re-cascade them.
        local suppressMatchProp = CludesUI._specProfileSwitching or CludesUI._zoneTransitionActive
        -- Throttle: skip if we just processed this key, but re-run once when the
        -- window closes. Dropping outright loses the LAST size of a burst, and that
        -- is exactly where a rebuild's final SetSize lands (BuildAllCDMBars then the
        -- synchronous CollectAndReanchor, both inside one frame): the first pass
        -- propagated a transient width to every matched child and the settled one
        -- never propagated at all, so the child stayed wrong until a reload. The
        -- deferred call takes the normal path below and converges, since a size that
        -- no longer changes fires no further OnSizeChanged. One pending re-run per key.
        local nowTime = GetTime()
        local lastNotify = _resizeNotifyThrottle[barKey]
        if lastNotify and (nowTime - lastNotify) < RESIZE_THROTTLE_SEC then
            local trail = CludesUI._resizeTrail
            local lastTrail = trail.at[barKey]
            if not trail.pending[barKey] and (not lastTrail or (nowTime - lastTrail) >= 0.5) then
                trail.pending[barKey] = true
                C_Timer.After(RESIZE_THROTTLE_SEC - (nowTime - lastNotify), function()
                    trail.pending[barKey] = nil
                    trail.at[barKey] = GetTime()
                    CludesUI.NotifyElementResized(barKey)
                end)
            end
            return
        end
        _resizeNotifyThrottle[barKey] = nowTime

        -- Detect which axis changed by comparing to last known size
        local barCfg = LM.GetBarFrame(barKey)
        local curW = barCfg and barCfg:GetWidth()
        local curH = barCfg and barCfg:GetHeight()
        -- A secret size (a frame riding an engine aura container under aura
        -- restriction) can't be compared; the next plain resize converges.
        if issecretvalue and (issecretvalue(curW) or issecretvalue(curH)) then
            return
        end
        curW = curW or 0
        curH = curH or 0
        local previous = _resizeLastSize[barKey]
        local widthChanged = not previous or math.abs(curW - previous.w) > 0.5
        local heightChanged = not previous or math.abs(curH - previous.h) > 0.5

        _resizeLastSize[barKey] = { w = curW, h = curH }

        -- Reapply own anchor first: an anchored element may need repositioning after
        -- its own resize. Unanchored elements get the stored CENTER re-applied so the
        -- WoW anchor stays CENTER after rebuilds that may use TOPLEFT. Skip when
        -- LayoutBar already positioned from its captured edge (avoids CENTER->edge->
        -- CENTER round-trip drift), and skip AB bars during profile swap (stale offsets cause a 1-frame blink); CDM bars are not suppressed.
        local abSwapSkip = CludesUI._abAnchorSuppressed and CludesUI._abBarKeys and CludesUI._abBarKeys[barKey]
        if not layoutBarHandled and not abSwapSkip then
            local anchorDB = GetAnchorDB()
            local ownAnchor = anchorDB and anchorDB[barKey]
            if ownAnchor and ownAnchor.target then
                if CludesUI.ReapplyOwnAnchor then
                    CludesUI.ReapplyOwnAnchor(barKey)
                end
            else
                -- Unanchored: re-apply stored CENTER position
                local element = registeredElements[barKey]
                if element and element.noInitHook then
                    -- Self-positioning element (noInitHook): stored CENTER was captured
                    -- under whatever footprint was live at save time, and re-applying it
                    -- clobbers the element's own scheme (e.g. raid container's per-tier
                    -- growth-corner anchor). Delegate to its own position authority instead.
                    if element.applyPosition then
                        pcall(element.applyPosition, barKey)
                    end
                else
                    local place
                    if element and element.loadPosition then
                        place = element.loadPosition(barKey)
                    else
                        local saved = LM.GetPositionDB()
                        place = saved and saved[barKey]
                    end
                    if place and place.point == "CENTER" and place.relPoint == "CENTER" then
                        LM.ApplyCenterPosition(barKey, place)
                    end
                end
            end
        end

        -- Propagate width/height matches to dependents (suppressed during spec-swap
        -- / zone-transition -- see suppressMatchProp above).
        if not suppressMatchProp then
            local wdb = MatchH.GetWidthMatchDB()
            if wdb then
                local hasChildren = false
                for childBarKey, tKey in pairs(wdb) do
                    if tKey == barKey then
                        hasChildren = true
                        break
                    end
                end
                if hasChildren then
                    CludesUI.PropagateWidthMatch(barKey)
                end
                -- Re-pull from own target if this element is a width-match child
                local ownTarget = wdb[barKey]
                if ownTarget and widthChanged then
                    MatchH.ApplyWidthMatch(barKey, ownTarget)
                end
            end
            local hdb = MatchH.GetHeightMatchDB()
            if hdb then
                local hasChildren = false
                for childBarKey, tKey in pairs(hdb) do
                    if tKey == barKey then
                        hasChildren = true
                        break
                    end
                end
                if hasChildren then
                    CludesUI.PropagateHeightMatch(barKey)
                end
                -- Re-pull from own target if this element is a height-match child
                local ownHTarget = hdb[barKey]
                if ownHTarget and heightChanged then
                    MatchH.ApplyHeightMatch(barKey, ownHTarget)
                end
            end
        end

        -- Propagate the anchor chain to children anchored to this element, using the
        -- detected axis so children on the unaffected axis don't move.
        local dim
        if widthChanged and heightChanged then
            dim = "all"
        elseif widthChanged then
            dim = "width"
        elseif heightChanged then
            dim = "height"
        end
        if dim then
            local existing = LM._pendingAnchorKeys[barKey]
            if existing and existing ~= dim then
                LM._pendingAnchorKeys[barKey] = "all"
            else
                LM._pendingAnchorKeys[barKey] = dim
            end
            ScheduleAnchorBatch()
            -- Arm the settle debounce so a forced full re-apply lands once the chain
            -- stops resizing -- catches late login/spec-swap resizes the one-shot
            -- reanchor misses. See ScheduleSettleReapply.
            if CludesUI.ScheduleSettleReapply then
                CludesUI.ScheduleSettleReapply()
            end
        end
    end

    -- Pad-change notifier. A module calls CludesUI.MatchPadChanged(key) after it  -- cui-style: allow comment-budget
    -- applies an element's border / chrome settings; the element's own getMatchPad
    -- output is compared with the last one seen, so no setter anywhere has to know
    -- which settings move the pad. A key's first sighting only records (the login
    -- match pass already reads pads); a real change queues the key and ONE deferred
    -- flush re-applies each queued key through ReapplyMatchPads, on the axes whose
    -- pad moved (pending value: 1 = width, 2 = height, 3 = both; an element with
    -- linked dimensions re-pulls both). Pads never depend on size, so the re-push's
    -- own setWidth -> rebuild sees an equal pad and stops. During a profile apply
    -- the pad is only recorded: that apply ends in the full match pass
    -- (ApplySavedPositions), which reads every live pad.
    -- State on the addon table: this file sits at the 200-local cap.
    CludesUI._matchPad = { w = {}, h = {}, pending = {}, spare = {}, armed = false }
    CludesUI._matchPad.flush = function()
        local matchPad = CludesUI._matchPad
        matchPad.armed = false
        local batch = matchPad.pending
        matchPad.pending, matchPad.spare = matchPad.spare, batch
        for key, handle in pairs(batch) do
            batch[key] = nil
            CludesUI.ReapplyMatchPads(key, handle)
        end
    end
    function CludesUI.MatchPadChanged(barKey)
        if LM.isUnlocked or not barKey then
            return
        end
        local element = registeredElements[barKey]
        if not (element and element.getMatchPad) then
            return
        end
        local padW, ph = element.getMatchPad(barKey)
        padW, ph = padW or 0, ph or 0
        local matchPad = CludesUI._matchPad
        local ow, oh = matchPad.w[barKey], matchPad.h[barKey]
        matchPad.w[barKey], matchPad.h[barKey] = padW, ph
        if ow == nil or (ow == padW and oh == ph) then
            return
        end
        if CludesUI._abAnchorSuppressed then
            return
        end
        local handle = ((ow ~= padW) and 1 or 0) + ((oh ~= ph) and 2 or 0)
        if element.linkedDimensions then
            handle = 3
        end
        local cur = matchPad.pending[barKey]
        if cur and cur ~= handle then
            handle = 3
        end
        matchPad.pending[barKey] = handle
        if not matchPad.armed then
            matchPad.armed = true
            C_Timer.After(0, matchPad.flush)
        end
    end

    -- An element's match pad or scale changed while its own size did not (a
    -- Classic WoW UI frame-size slider, a Blizzard Style Frame Scale change):
    -- re-pull its own width/height match and re-push its children.
    -- NotifyElementResized cannot do this, since its self re-pull keys on a size
    -- change. Never in unlock mode; a no-op for elements in no match. mask (the
    -- notifier's): 1 = width only, 2 = height only, nil = both.
    function CludesUI.ReapplyMatchPads(barKey, mask)
        if LM.isUnlocked or not barKey then
            return
        end
        -- An explicit call covers a queued one, and the pad it applies is the one
        -- on record, so the rebuild it triggers does not queue the same pass again.
        local matchPad = CludesUI._matchPad
        matchPad.pending[barKey] = nil
        local pe = registeredElements[barKey]
        if pe and pe.getMatchPad then
            local padW, ph = pe.getMatchPad(barKey)
            matchPad.w[barKey], matchPad.h[barKey] = padW or 0, ph or 0
        end
        local wdb = MatchH.GetWidthMatchDB()
        if wdb and mask ~= 2 then
            if wdb[barKey] then
                MatchH.ApplyWidthMatch(barKey, wdb[barKey])
            end
            CludesUI.PropagateWidthMatch(barKey)
        end
        local hdb = MatchH.GetHeightMatchDB()
        if hdb and mask ~= 1 then
            if hdb[barKey] then
                MatchH.ApplyHeightMatch(barKey, hdb[barKey])
            end
            CludesUI.PropagateHeightMatch(barKey)
        end
    end

    -- Commit a typed Extra Width / Height from the unlock cog (axis "w" / "h",
    -- whole pixels clamped to -100..100): store it, re-pull the element's own match,
    -- then re-push its match children and anchor chain exactly as a fresh match pick
    -- does. ReapplyMatchPads cannot serve here, it stands down in unlock mode. File
    -- scope because CreateMover sits at Lua 5.1's 60-upvalue cap.
    function MatchH.CommitMatchExtra(dim, barKey, px)
        if not barKey then
            return
        end
        local isH = (dim == "h")
        local target
        if isH then
            target = MatchH.GetHeightMatchInfo(barKey)
        else
            target = MatchH.GetWidthMatchInfo(barKey)
        end
        if not target then
            return
        end
        local ax = isH and "h" or "w"
        px = math.floor(math.max(-100, math.min(100, tonumber(px) or 0)) + 0.5)
        if px == (CludesUI.GetMatchExtra(ax, barKey) or 0) then
            return
        end
        MatchH.SetMatchExtra(ax, barKey, px)
        if isH then
            MatchH.ApplyHeightMatch(barKey, target)
        else
            MatchH.ApplyWidthMatch(barKey, target)
        end
        LM.hasChanges = true
        local handle = movers[barKey]
        if handle then
            handle:SyncSize()
            if handle.RefreshAnchoredText then
                handle:RefreshAnchoredText()
            end
            -- The matched label grew or shrank ("W Matched +5"): re-lay the row.
            if handle._layoutActionRow then
                handle._layoutActionRow()
            end
        end
        local ai = GetAnchorInfo(barKey)
        if ai then
            LM.ApplyAnchorPosition(barKey, ai.target, ai.side, true)
        end
        if isH then
            CludesUI.PropagateHeightMatch(barKey)
        else
            CludesUI.PropagateWidthMatch(barKey)
        end
        -- A linked-dimensions element (square icons) resizes both sides from one
        -- axis: re-push the other axis's match children too.
        local el = registeredElements[barKey]
        if el and el.linkedDimensions then
            if isH then
                CludesUI.PropagateWidthMatch(barKey)
            else
                CludesUI.PropagateHeightMatch(barKey)
            end
        end
        LM.PropagateAnchorChain(barKey)
    end

    -- Each match's Extra Width / Height as it stood when unlock mode opened
    -- (SnapshotPositions), restored with the links on discard (RevertPositions).
    MatchH.snapExtra = { w = {}, h = {} }

    -------------------------------------------------------------------------------
    --  Apply ALL width/height matches globally (used on login/reload)
    -------------------------------------------------------------------------------
    -- Break circular chains in a match DB before applying: walk each chain and
    -- remove the link that closes a loop.
    function MatchH.BreakMatchCycles(saved)
        if not saved then
            return
        end
        local safe = {} -- keys confirmed cycle-free
        for childBarKey in pairs(saved) do
            if not safe[childBarKey] then
                local seen = {}
                local current = childBarKey
                while current and saved[current] do
                    if seen[current] then
                        -- current closes the cycle; break it
                        saved[current] = nil
                        break
                    end
                    seen[current] = true
                    current = saved[current]
                end
                -- Mark all visited keys as safe
                for key in pairs(seen) do
                    safe[key] = true
                end
            end
        end
    end

    -- Apply every entry in a match DB in dependency order (roots, then children,
    -- then grandchildren). Required for chains A -> B -> C: C processed before B
    -- reads B's stale width and stays wrong. BreakMatchCycles runs first so the
    -- graph is acyclic; the visited guard is defensive.
    local function ApplyMatchesInDependencyOrder(saved, applyFn)
        if not saved then
            return
        end
        local depth = {}
        local function GetDepth(key, visiting)
            if depth[key] ~= nil then
                return depth[key]
            end
            if visiting[key] then
                return 0
            end
            visiting[key] = true
            local target = saved[key]
            if target and saved[target] then
                depth[key] = 1 + GetDepth(target, visiting)
            else
                depth[key] = 0
            end
            visiting[key] = nil
            return depth[key]
        end
        local sequence = {}
        for childBarKey in pairs(saved) do
            GetDepth(childBarKey, {})
            sequence[#sequence + 1] = childBarKey
        end
        table.sort(sequence, function(lhs, rhs)
            return depth[lhs] < depth[rhs]
        end)
        for _, childBarKey in ipairs(sequence) do
            applyFn(childBarKey, saved[childBarKey])
        end
    end

    local function ApplyAllWidthHeightMatches()
        -- No mid-rebuild CDM guard here: CDM fires its own ApplyAllWidthHeightMatches at
        -- the end of CollectAndReanchor, which corrects any transient widths read while its
        -- icon counts were stale. A guard blocked unrelated UF height matches during spec
        -- swap. Break circular chains from old data before applying.
        MatchH.BreakMatchCycles(MatchH.GetWidthMatchDB())
        MatchH.BreakMatchCycles(MatchH.GetHeightMatchDB())
        ApplyMatchesInDependencyOrder(MatchH.GetWidthMatchDB(), MatchH.ApplyWidthMatch)
        ApplyMatchesInDependencyOrder(MatchH.GetHeightMatchDB(), MatchH.ApplyHeightMatch)
    end

    -- Re-sync every active width/height match when the global UI Scale changes.  -- cui-style: allow comment-budget
    -- ApplyWidth/HeightMatch convert the target's size into the source's space via
    -- GetEffectiveScale() ratio, but nothing else re-runs that conversion after a UI
    -- Scale change, so a pair whose frames don't scale identically (a UIParent-parented
    -- element matched to an Edit Mode frame with its own scale) keeps the OLD ratio
    -- until something unrelated forces a re-match, showing as extra spacing. The short
    -- delay lets every frame's GetEffectiveScale() finish propagating. Debounced to a
    -- quiet period, not a fixed delay: a live-preview UI Scale slider fires many times
    -- per second while dragged, and re-running per firing fed a non-converging loop
    -- (re-applied width -> SetSize -> resize propagation -> re-apply). Timer lives on
    -- CludesUI.PP, shared with CludesUI.lua's PP.SetUIScale trigger, so one
    -- listener cancels/replaces the other's pending timer instead of both running a full pass.
    do
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("UI_SCALE_CHANGED")
        frame:SetScript("OnEvent", function()
            local PPu = CludesUI and CludesUI.PP
            if not PPu then
                return
            end
            if PPu._scaleMatchDebounce then
                PPu._scaleMatchDebounce:Cancel()
            end
            PPu._scaleMatchDebounce = C_Timer.NewTimer(0.3, function()
                PPu._scaleMatchDebounce = nil
                ApplyAllWidthHeightMatches()
            end)
        end)
    end

    -------------------------------------------------------------------------------
    --  OnSizeChanged hook for registered element frames: fires NotifyElementResized so
    --  dependent elements (width-matched, anchored) update without the source addon calling anything.
    -------------------------------------------------------------------------------
    local _sizeHookedFrames = {} -- [frame] = true
    local _pointHookedFrames = {} -- [frame] = true

    -- Last-seen screen position per key. NotifyElementMoved compares GetLeft/GetTop to
    -- these to detect real moves (SetPoint fires many times per frame via ClearAllPoints+SetPoint pairs).
    local _lastScreenPos = {} -- [key] = { l = ..., t = ... }
    local _moveCheckScheduled = {} -- [key] = true (dedupes same-frame checks)

    -- Fires the anchor cascade for `key` if its frame actually moved on screen since the
    -- last check. Deferred to end-of-frame so a ClearAllPoints+SetPoint pair coalesces
    -- into one check. Needed because NotifyElementResized only fires from
    -- OnSizeChanged and the cascade only from ApplyAnchorPosition, so pure position
    -- changes from an addon's own SetPoint (e.g. ERB re-applying sp.unlockPos on every
    -- Class Resource rebuild) hit neither emitter and anchored children never learn the target moved.
    local function NotifyElementMoved(barKey)
        if LM.isUnlocked then
            return
        end -- unlock mode owns positioning
        if _moveCheckScheduled[barKey] then
            return
        end
        _moveCheckScheduled[barKey] = true
        C_Timer.After(0, function()
            _moveCheckScheduled[barKey] = nil
            if LM.isUnlocked then
                return
            end
            local barCfg = LM.GetBarFrame(barKey)
            if not barCfg then
                return
            end
            local l, t = barCfg:GetLeft(), barCfg:GetTop()
            -- A frame riding an engine aura container (a Blizzard Style cast bar
            -- under its frame's aura stack) reports a secret position: nothing to
            -- compare, and its children cannot follow it anyway (they re-anchor on
            -- the next plain apply).
            if issecretvalue and (issecretvalue(l) or issecretvalue(t)) then
                return
            end
            if not l or not t then
                return
            end
            local previous = _lastScreenPos[barKey]
            if previous and math.abs(l - previous.l) < 0.5 and math.abs(t - previous.t) < 0.5 then
                return -- position unchanged (within half a physical pixel)
            end
            if previous then
                previous.l, previous.t = l, t
            else
                _lastScreenPos[barKey] = { l = l, t = t }
            end
            -- Convergence: ApplyAnchorPosition's idempotent guard skips SetPoint when the
            -- child is already within 0.5px of target, so the cascade drains in bounded
            -- passes -- each call re-enters this hook, but the check above returns early once settled.
            if CludesUI.PropagateAnchorChain then
                CludesUI.PropagateAnchorChain(barKey, "all")
            end
        end)
    end

    local function HookFrameSizeChanged(barKey)
        -- No hooks on chat frames: ChatFrame1 is docked inside Blizzard's secure
        -- FCF_OpenTemporaryWindow chain and any addon code in OnSizeChanged/SetPoint
        -- hooks taints the execution context. Chat persists its own position/size.
        if barKey and barKey:find("^ECHAT_") then
            return
        end
        local barCfg = LM.GetBarFrame(barKey)
        if not barCfg then
            return
        end
        -- The quest tracker key: Blizzard's tracker is laid out by its managed
        -- frame container, in combat too, and places itself from its Edit Mode
        -- layout entry (its unlock session stand-in included), so it takes no
        -- hooks. WoW Forever's custom tracker, a frame of ours under the same key
        -- that grows with its quests, does: its resize re-applies its anchor link,
        -- which otherwise keeps its centre and moves the edge it hangs from.
        if barKey == "EQT_Tracker" and barCfg ~= _G.CUI_CustomQuestTracker then
            return
        end
        if not _sizeHookedFrames[barCfg] then
            _sizeHookedFrames[barCfg] = true
            barCfg:HookScript("OnSizeChanged", function()
                if LM.isUnlocked then
                    return
                end
                CludesUI.NotifyElementResized(barKey)
            end)
        end
        if not _pointHookedFrames[barCfg] then
            _pointHookedFrames[barCfg] = true
            hooksecurefunc(barCfg, "SetPoint", function()
                NotifyElementMoved(barKey)
            end)
        end
    end

    -- Wrap RegisterUnlockElements so new elements get OnSizeChanged hooks
    -- installed automatically (handles late registrations like CDM bars).
    do
        local origRegister = CludesUI.RegisterUnlockElements
        function CludesUI:RegisterUnlockElements(elements, folder)
            origRegister(self, elements, folder)
            -- Defer hook installation so the frame has time to be created/sized
            C_Timer.After(0.1, function()
                for _, element in ipairs(elements) do
                    if element.key then
                        HookFrameSizeChanged(element.key)
                    end
                end
            end)
        end
    end

    local _overlayFadeFrame -- tiny OnUpdate driver for select-element dimmer fade

    -- Smoothly fade the background overlay between normal and select-element alpha
    local function FadeOverlayForSelectElement(entering)
        if not LM.unlockFrame or not LM.unlockFrame._overlay then
            return
        end
        local startA = entering and (LM.unlockFrame._overlayMaxAlpha or 0.20) or SELECT_ELEMENT_ALPHA
        local endA = entering and SELECT_ELEMENT_ALPHA or (LM.unlockFrame._overlayMaxAlpha or 0.20)
        if not _overlayFadeFrame then
            _overlayFadeFrame = CreateFrame("Frame")
        end
        local timePassed = 0
        _overlayFadeFrame:SetScript("OnUpdate", function(self, elapsed)
            timePassed = timePassed + elapsed
            local t = math.min(timePassed / SELECT_ELEMENT_FADE, 1)
            local a = startA + (endA - startA) * t
            LM.unlockFrame._overlay:SetColorTexture(0.020, 0.025, 0.031, a)
            if t >= 1 then
                self:SetScript("OnUpdate", nil)
            end
        end)
    end

    -- Cancel any active pick mode (width/height match, anchor to, snap select) and
    -- restore overlay text and screen brightness.
    local function CancelPickMode()
        if LM.PointPicker then
            LM.PointPicker.Cancel()
        end
        if LM.pickModeMover then
            local handle = LM.pickModeMover
            -- Restore overlay text visibility only if still hovered
            if handle._hidePickText then
                handle._hidePickText()
            end
            if handle:IsMouseOver() then
                if handle._showOverlayText then
                    handle._showOverlayText()
                end
            else
                if handle._hideOverlayText then
                    handle._hideOverlayText()
                end
            end
            LM.pickMode = nil
            LM.pickModeMover = nil
            FadeOverlayForSelectElement(false)
        end
        -- Also cancel snap select-element picker if active
        if LM.selectElementPicker then
            local picker = LM.selectElementPicker
            picker._snapTarget = picker._preSelectTarget
            picker._preSelectTarget = nil
            if picker._updateSnapLabel then
                picker._updateSnapLabel()
            end
            LM.selectElementPicker = nil
            FadeOverlayForSelectElement(false)
        end
        -- Hide anchor dropdown if open
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
    end

    -- Enter element pick mode for a FALLBACK anchor target: same flow as anchoring,
    -- but the dispatcher stores the result on the child's existing anchor link.
    -- Namespace-attached so the cog menu can start it without another upvalue.
    function CludesUI._BeginFallbackAnchorPick(mover)
        if not mover then
            return
        end
        CancelPickMode()
        LM.pickMode = "fallbackAnchor"
        LM.pickModeMover = mover
        if mover._showPickText then
            mover._showPickText("Click any element\nto set as the Fallback Anchor")
        end
        FadeOverlayForSelectElement(true)
    end

    -- Red border flash animation for error feedback (e.g. trying to drag an anchored element)
    local function FlashRedBorder(handle)
        if not handle or not handle._brd then
            return
        end
        if not handle._redFlashBrd then
            handle._redFlashBrd = CludesUI.MakeBorder(handle, 1, 0.2, 0.2, 0)
            handle._redFlashBrd._frame:SetFrameLevel(handle:GetFrameLevel() + 4)
            local Pix = CludesUI and CludesUI.PP
            if Pix then
                Pix.SetBorderSize(handle._redFlashBrd._frame, 2)
            end
        end
        local brd = handle._redFlashBrd
        local timePassed = 0
        if not handle._redFlashFrame then
            handle._redFlashFrame = CreateFrame("Frame")
        end
        handle._redFlashFrame:SetScript("OnUpdate", function(self, elapsed)
            timePassed = timePassed + elapsed
            if timePassed < 0.8 then
                local a = 0.5 + 0.5 * math.sin(timePassed * 10)
                brd:SetColor(1, 0.2, 0.2, a)
            elseif timePassed < 1.5 then
                brd:SetColor(1, 0.2, 0.2, math.max(0, 1 - (timePassed - 0.8) / 0.7))
            else
                brd:SetColor(1, 0.2, 0.2, 0)
                self:SetScript("OnUpdate", nil)
            end
        end)
    end

    local RejectH = {}
    function RejectH.ShowTooltip(textValue)
        if not RejectH._anchor then
            RejectH._anchor = CreateFrame("Frame", nil, UIParent)
            RejectH._anchor:SetSize(1, 1)
            RejectH._timer = CreateFrame("Frame")
        end
        local uiScale = UIParent:GetEffectiveScale()
        local curX, curY = GetCursorPosition()
        RejectH._anchor:ClearAllPoints()
        RejectH._anchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", curX / uiScale, curY / uiScale)
        CludesUI.ShowWidgetTooltip(RejectH._anchor, textValue, {})
        local timePassed = 0
        RejectH._timer:SetScript("OnUpdate", function(self, elapsed)
            timePassed = timePassed + elapsed
            if timePassed >= 3 then
                CludesUI.HideWidgetTooltip()
                self:SetScript("OnUpdate", nil)
                return
            end
            local uiScale = UIParent:GetEffectiveScale()
            local curX, curY = GetCursorPosition()
            RejectH._anchor:ClearAllPoints()
            RejectH._anchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", curX / uiScale, curY / uiScale)
        end)
    end
    function RejectH.IsActionBar(barId)
        if barId == "MainBar" then
            return true
        end
        if barId:sub(1, 3) == "Bar" then
            local num = tonumber(barId:sub(4))
            return num and num >= 2 and num <= 8
        end
        return false
    end

    -------------------------------------------------------------------------------
    --  Combat-parked positioning: any anchor application (or guarded bar reposition)
    --  skipped for combat lockdown is recorded here and reapplied once on
    --  PLAYER_REGEN_ENABLED. Without it, skips in the cascade paths
    --  (PropagateAnchorChain, ScheduleAnchorBatch, retry loops) are silent and the
    --  element stays misplaced until an unrelated full reapply happens.
    --  Namespace-scoped, not file-local: file is at the Lua 5.1 200-local cap.
    -------------------------------------------------------------------------------
    do
        local AnchorPark = {}
        CludesUI._AnchorPark = AnchorPark

        -- One combat queue for every lockdown-skipped apply in this file
        local queue = CludesUI.NewCombatQueue(CreateFrame("Frame"))
        CludesUI._UnlockCombatQueue = queue

        local function AnchorPark_Drain()
            local anchorKeys = AnchorPark.keys
            local posKeys = AnchorPark.posKeys
            AnchorPark.keys = nil
            AnchorPark.posKeys = nil
            -- Bar positions first: anchored children read target bounds,
            -- so targets must be placed before the anchor pass.
            if posKeys then
                local saved = LM.GetPositionDB()
                for barKey in pairs(posKeys) do
                    local place = saved and saved[barKey]
                    if place and place.point then
                        if not LM.ApplyCenterPosition(barKey, place) then
                            local barCfg = LM.GetBarFrame(barKey)
                            if barCfg then
                                pcall(function()
                                    CludesUI.ClearFramePoints(barCfg)
                                    CludesUI.SetFramePoint(
                                        barCfg,
                                        place.point,
                                        UIParent,
                                        place.relPoint or place.point,
                                        place.x,
                                        place.y
                                    )
                                end)
                            end
                        end
                    end
                end
            end
            if anchorKeys then
                -- Full dependency-sorted pass instead of per-key applies: parked
                -- chains must apply parents first; idempotent for never-parked anchors.
                if CludesUI.ReapplyAllUnlockAnchors then
                    CludesUI.ReapplyAllUnlockAnchors()
                end
            end
        end

        -- Park an anchored child whose apply was blocked by combat lockdown.
        function AnchorPark.Park(childBarKey)
            local keyList = AnchorPark.keys
            if not keyList then
                keyList = {}
                AnchorPark.keys = keyList
            end
            keyList[childBarKey] = true
            queue.Defer("AnchorPark", AnchorPark_Drain)
        end

        -- Park a bar whose saved-position reapply was blocked by combat lockdown.
        function AnchorPark.ParkBarPos(barId)
            local keyList = AnchorPark.posKeys
            if not keyList then
                keyList = {}
                AnchorPark.posKeys = keyList
            end
            keyList[barId] = true
            queue.Defer("AnchorPark", AnchorPark_Drain)
        end
    end

    -- Apply an anchor: place the child on `side` ("LEFT"/"RIGHT"/"TOP"/"BOTTOM") of  -- cui-style: allow comment-budget
    -- the target; offsetX/offsetY, if present, position it from the anchor edge.
    -------------------------------------------------------------------------------
    --  Fallback anchors (opt-in, per anchored element): a target that doesn't exist
    --  leaves the child unpositioned -- its saved position is skipped (anchor-linked)
    --  and the anchor can't apply, so it lands wherever the default build put it. A
    --  stored fallback gives it a concrete position. Scoped to targets absent by
    --  config/gameplay: tracking bars/groups (per-spec) and the pet frame (no pet).
    --  Free until stored: one table lookup per apply; pet watcher created on first use.
    -------------------------------------------------------------------------------
    do
        local function EligibleTarget(targetBarKey)
            if type(targetBarKey) ~= "string" then
                return false
            end
            return targetBarKey == "pet" or targetBarKey:find("^TBB_%d+$") ~= nil or targetBarKey:find("^TBBG_") ~= nil
        end

        -- Targets where a HIDDEN frame means "logically inactive" (pet frame with no
        -- pet). Tracking bars hide by design when their buff is down, so they are NOT
        -- in this set -- their absent signal is a nil frame.
        local hiddenIsInactive = { pet = true }

        function CludesUI.EligibleFallbackTarget(targetBarKey)
            return EligibleTarget(targetBarKey)
        end

        -- Growth-fixed-edge pin for fallback placement: the flush side-snap centers
        -- the child on the target's CROSS axis, which shifts a custom-growth bar's
        -- fixed edge when it's a different size elsewhere. A standard anchor pins the
        -- GROWTH edge, not the center; this returns what to add to the flush-snap
        -- center on the cross axis to match (the snap axis already holds its own edge,
        -- e.g. cx = tL - cW/2 keeps the right edge at tL). Zero for center-growth bars
        -- and non-CDM/AB elements (GetBarGrowDirActual returns "CENTER"). cW/cH are UIParent-space dims. Fallback/override anchor code only.
        CludesUI._FallbackGrowShift = function(childBarKey, edgeSide, cW, cH)
            local gd = GetBarGrowDirActual(childBarKey)
            if not gd or gd == "CENTER" then
                return 0, 0
            end
            local horiz = (gd == "LEFT" or gd == "RIGHT")
            local crossX = (edgeSide == "TOP" or edgeSide == "BOTTOM" or edgeSide == "CENTER" or edgeSide == nil)
            local crossY = (edgeSide == "LEFT" or edgeSide == "RIGHT" or edgeSide == "CENTER" or edgeSide == nil)
            -- RIGHT/UP fix the near edge (left/bottom) -> center sits +half past it;
            -- LEFT/DOWN fix the far edge (right/top) -> center sits -half before it.
            if horiz and crossX then
                return (gd == "RIGHT") and (cW / 2) or (-cW / 2), 0
            elseif (not horiz) and crossY then
                return 0, (gd == "UP") and (cH / 2) or (-cH / 2)
            end
            return 0, 0
        end

        -- True when this owned positioning for the apply (fallback applied, already in
        -- place, held, or parked for regen); false = normal path. A fallback is a
        -- secondary anchor link {target, side}: with the primary target absent, the
        -- child snaps flush to that side of the fallback target, using the same
        -- absolute UIParent-space math as a fresh side-snap anchor.
        function CludesUI._TryFallbackAnchor(childBarKey, targetBarKey, childBar, targetFrame)
            if LM.isUnlocked then
                return false
            end
            local saved = GetAnchorDB()
            local details = saved and saved[childBarKey]
            local fb = details and details.fallback
            if not fb or not fb.target then
                return false
            end
            local edgeSide = fb.side
            local inactive
            if not targetFrame then
                inactive = true
            elseif hiddenIsInactive[targetBarKey] then
                inactive = not targetFrame:IsShown()
            end
            if not inactive then
                return false
            end
            if InCombatLockdown() and childBar:IsProtected() then
                CludesUI._AnchorPark.Park(childBarKey)
                return true
            end
            local tgt = LM.GetBarFrame(fb.target)
            if not tgt or not tgt:GetLeft() then
                -- Fallback target unavailable as well: hold position.
                return true
            end
            local uiScale = UIParent:GetEffectiveScale()
            local tS = tgt:GetEffectiveScale()
            local cS = childBar:GetEffectiveScale()
            local tL = (tgt:GetLeft() or 0) * tS / uiScale
            local tR = (tgt:GetRight() or 0) * tS / uiScale
            local tT = (tgt:GetTop() or 0) * tS / uiScale
            local tB = (tgt:GetBottom() or 0) * tS / uiScale
            local tCX = (tL + tR) / 2
            local tCY = (tT + tB) / 2
            -- Growth-edge extent applies to the fallback target too.
            if CludesUI._GetAnchorTargetExtent then
                local ext = CludesUI._GetAnchorTargetExtent(fb.target, edgeSide)
                if ext then
                    if edgeSide == "TOP" then
                        tT = ext
                    elseif edgeSide == "BOTTOM" then
                        tB = ext
                    elseif edgeSide == "LEFT" then
                        tL = ext
                    elseif edgeSide == "RIGHT" then
                        tR = ext
                    end
                end
            end
            local cW = (childBar:GetWidth() or 50) * cS / uiScale
            local cH = (childBar:GetHeight() or 50) * cS / uiScale
            local cx, cy
            if edgeSide == "LEFT" then
                cx, cy = tL - cW / 2, tCY
            elseif edgeSide == "RIGHT" then
                cx, cy = tR + cW / 2, tCY
            elseif edgeSide == "TOP" then
                cx, cy = tCX, tT + cH / 2
            elseif edgeSide == "BOTTOM" then
                cx, cy = tCX, tB - cH / 2
            else
                cx, cy = tCX, tCY
            end
            -- User-set offsets relative to the fallback anchor point (UIParent
            -- units; edited in physical pixels via the cog menu rows).
            cx = cx + (fb.offsetX or 0)
            cy = cy + (fb.offsetY or 0)
            -- Keep the growth-fixed edge (not the center) pinned on the cross axis so
            -- a differently-sized bar on another character still lines up, like a
            -- standard anchor. Inert (0,0) for center-growth / non-bar children.
            local gsx, gsy = CludesUI._FallbackGrowShift(childBarKey, edgeSide, cW, cH)
            cx = cx + gsx
            cy = cy + gsy
            -- Temporary per-target visual shift (e.g. "Shift Elements if No
            -- Resource/Power"), mirroring the main path. fb.target is the live target
            -- actually in use here, not targetKey (the inactive primary).
            if not LM.isUnlocked and CludesUI._GetAnchorTargetShiftDir then
                local dir, extraY = CludesUI._GetAnchorTargetShiftDir(fb.target, childBarKey)
                if dir ~= 0 then
                    cy = cy + dir * ((tT - tB) + (extraY or 0))
                end
            end
            -- Child-local scale space + pixel snap + idempotent guard, mirroring
            -- the standard CENTER path in ApplyAnchorPosition.
            local acRatio = uiScale / cS
            local bCenterX = (cx - UIParent:GetWidth() / 2) * acRatio
            local bCenterY = (cy - UIParent:GetHeight() / 2) * acRatio
            local PPa = Pix or (CludesUI and CludesUI.PP)
            if PPa and PPa.SnapCenterForDim then
                bCenterX = PPa.SnapCenterForDim(bCenterX, childBar:GetWidth() or 0, cS)
                bCenterY = PPa.SnapCenterForDim(bCenterY, childBar:GetHeight() or 0, cS)
            end
            local okPt, anchorPoint, relTo, relPoint, curX, curY = pcall(childBar.GetPoint, childBar, 1)
            -- A child still on a followed edge reads its anchor back secret: never compared.
            if
                okPt
                and issecretvalue
                and (
                    issecretvalue(anchorPoint)
                    or issecretvalue(relPoint)
                    or issecretvalue(curX)
                    or issecretvalue(curY)
                )
            then
                okPt = false
            end
            if okPt and anchorPoint == "CENTER" and relPoint == "CENTER" and relTo == UIParent then
                local onePx = ((PPa and PPa.perfect) or 1) / cS
                local tol = onePx * 0.5
                if curX and curY and math.abs(curX - bCenterX) < tol and math.abs(curY - bCenterY) < tol then
                    return true
                end
            end
            pcall(function()
                CludesUI.ClearFramePoints(childBar)
                CludesUI.SetFramePoint(childBar, "CENTER", UIParent, "CENTER", bCenterX, bCenterY)
            end)
            -- Children anchored to THIS child must follow it to the fallback spot.
            LM._pendingAnchorKeys[childBarKey] = "all"
            ScheduleAnchorBatch()
            return true
        end

        -- Store the fallback link (target + side), chosen through the same element
        -- pick mode as regular anchoring.
        function CludesUI.SetAnchorFallback(childBarKey, targetBarKey, edgeSide)
            local saved = GetAnchorDB()
            local details = saved and saved[childBarKey]
            if not details or not details.target then
                return false
            end
            if not targetBarKey or targetBarKey == childBarKey or targetBarKey == details.target then
                return false
            end
            details.fallback = { target = targetBarKey, side = edgeSide or "BOTTOM" }
            CludesUI._anchorLinksStamp = (CludesUI._anchorLinksStamp or 0) + 1
            CludesUI._EnsureFallbackWatchers()
            if CludesUI._RefreshFallbackGhosts then
                CludesUI._RefreshFallbackGhosts()
            end
            return true
        end

        function CludesUI.ClearAnchorFallback(childBarKey)
            local saved = GetAnchorDB()
            local details = saved and saved[childBarKey]
            if details then
                details.fallback = nil
            end
            CludesUI._anchorLinksStamp = (CludesUI._anchorLinksStamp or 0) + 1
            CludesUI._EnsureFallbackWatchers()
            if CludesUI._RefreshFallbackGhosts then
                CludesUI._RefreshFallbackGhosts()
            end
        end

        -- Pet watcher: created the first time a pet-target fallback exists (free until
        -- opted in) and kept. Every link change made here (SetAnchorInfo,
        -- ClearAnchorInfo, SetAnchorFallback, ClearAnchorFallback), ApplySavedPositions
        -- and an Unlock Mode discard re-check it: UNIT_PET is registered while such a
        -- fallback is stored and unregistered once none is. UNIT_PET fires on summon AND
        -- dismiss/death, so one debounced reapply covers both.
        local petWatcher
        local petWatchOn
        local petPassPending
        function CludesUI._EnsureFallbackWatchers()
            local saved = GetAnchorDB()
            if not saved then
                return
            end
            local needPet = false
            for _, details in pairs(saved) do
                if details.fallback and hiddenIsInactive[details.target] then
                    needPet = true
                    break
                end
            end
            if needPet and not petWatchOn then
                if not petWatcher then
                    petWatcher = CreateFrame("Frame")
                    petWatcher:SetScript("OnEvent", function()
                        if petPassPending then
                            return
                        end
                        petPassPending = true
                        C_Timer.After(0.1, function()
                            petPassPending = nil
                            if LM.isUnlocked then
                                return
                            end
                            if CludesUI.ReapplyAllUnlockAnchors then
                                CludesUI.ReapplyAllUnlockAnchors()
                            end
                        end)
                    end)
                end
                petWatcher:RegisterUnitEvent("UNIT_PET", "player")
                petWatchOn = true
            elseif not needPet and petWatchOn then
                petWatcher:UnregisterEvent("UNIT_PET")
                petWatchOn = false
            end
        end

        -- Debounced re-eval when a fallback-eligible target may have appeared or
        -- vanished (TBB registration runs on every bar edit / spec swap). No-op
        -- unless at least one fallback is stored.
        local tbbPassPending
        function CludesUI.NotifyFallbackTargetsChanged()
            local saved = GetAnchorDB()
            if not saved then
                return
            end
            local any = false
            for _, details in pairs(saved) do
                if details.fallback then
                    any = true
                    break
                end
            end
            if not any or tbbPassPending or LM.isUnlocked then
                return
            end
            tbbPassPending = true
            C_Timer.After(0.2, function()
                tbbPassPending = nil
                if LM.isUnlocked then
                    return
                end
                if CludesUI.ReapplyAllUnlockAnchors then
                    CludesUI.ReapplyAllUnlockAnchors()
                end
            end)
        end
    end

    LM.GetBarGrowDirActual, LM.GetBarGrowDir, LM.GetAnchorDB, LM.GetAnchorInfo =
        GetBarGrowDirActual, GetBarGrowDir, GetAnchorDB, GetAnchorInfo
    LM.SetAnchorInfo, LM.ClearAnchorInfo, LM.IsAnchored, LM.MatchH =
        SetAnchorInfo, ClearAnchorInfo, IsAnchored, MatchH
    LM.ValidateStoredLinks, LM.ScheduleAnchorBatch, LM.ApplyAllWidthHeightMatches, LM.HookFrameSizeChanged =
        ValidateStoredLinks, ScheduleAnchorBatch, ApplyAllWidthHeightMatches, HookFrameSizeChanged
    LM.FadeOverlayForSelectElement, LM.CancelPickMode, LM.FlashRedBorder, LM.RejectH =
        FadeOverlayForSelectElement, CancelPickMode, FlashRedBorder, RejectH
end
